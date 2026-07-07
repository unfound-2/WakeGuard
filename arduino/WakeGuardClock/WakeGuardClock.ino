/*
 * ============================================================================
 *  WakeGuard Clock  —  Arduino Uno R3 firmware
 * ============================================================================
 *
 *  Companion firmware for the WakeGuard Flutter app (smart_ble_alarm).
 *
 *  HARDWARE (as wired for this build):
 *    - Arduino Uno R3 (ATmega328P, 16 MHz, no RTC)
 *    - HM-10 BLE module   (transparent serial-over-BLE, service FFE0 / char FFE1)
 *    - 16x2 I2C LCD1602   (PCF8574 backpack, address 0x27, backlight on/off only)
 *    - Passive speaker    (driven by Timer1 PWM on D9 — NOT an active buzzer)
 *    - (optional) momentary push button for snooze / backlight wake
 *    - (optional) photoresistor (LDR) for ambient auto-dim
 *
 *  This firmware is the "clock node". The phone app is the configuration master
 *  and the authoritative time source. The clock runs fully autonomously between
 *  connections: it keeps time in software, stores alarms/settings/tokens in
 *  EEPROM, rings alarms and timers on its own, and only needs the app to change
 *  configuration or to complete a secured (token-gated) dismissal.
 *
 *  It speaks EXACTLY the framed BLE protocol the app implements
 *  (see smart_ble_alarm/lib/data/datasources/ble_framing.dart,
 *   lib/core/ble/ble_payloads.dart, lib/core/ble/clock_sync.dart). Do not change
 *  the frame format, command IDs, or payload layouts here without changing the
 *  app to match — they are a fixed contract.
 *
 *  ----------------------------------------------------------------------------
 *  WIRING
 *  ----------------------------------------------------------------------------
 *    HM-10 VCC  -> 3.3V           HM-10 GND -> GND
 *    HM-10 TXD  -> D2  (Arduino RX, direct — 3.3V is a valid HIGH at 5V logic)
 *    HM-10 RXD  <- D3  (Arduino TX) THROUGH a divider: D3 --[1k]--+--> RXD
 *                                                                 |
 *                                                               [2k]
 *                                                                 |
 *                                                                GND   (~3.3V)
 *    LCD  VCC -> 5V, GND -> GND, SDA -> A4, SCL -> A5
 *    Speaker(+) -> D9,  Speaker(-) -> GND   (add a 100R series resistor to tame
 *                                            volume/current if desired)
 *    Button -> D10 to GND (uses internal pull-up; harmless/ignored if absent)
 *    LDR    -> A0 divider (only used if ENABLE_LDR is set)
 *
 *  ----------------------------------------------------------------------------
 *  LIBRARIES
 *  ----------------------------------------------------------------------------
 *    NONE to install — this sketch is self-contained. Wire, SoftwareSerial and
 *    EEPROM all ship with the Arduino AVR core. The 16x2 I2C LCD is driven by a
 *    small built-in PCF8574/HD44780 driver (class LcdI2C below), so you do NOT
 *    need the "LiquidCrystal I2C" library. If your backpack maps its expander
 *    pins unusually, adjust the Rs/Rw/En/backlight bit masks in LcdI2C.
 *
 *  ----------------------------------------------------------------------------
 *  ONE-TIME CONFIGURATION YOU SHOULD CHECK  (see the block just below)
 *  ----------------------------------------------------------------------------
 *    - TIMEZONE_OFFSET_SECONDS : the app sends UTC epoch; alarms are LOCAL time.
 *                                Set this to your UTC offset or the clock will
 *                                display/ring in UTC. (No BLE command carries a
 *                                timezone, so it must live here.)
 *    - USE_24H_DISPLAY         : 24-hour vs 12-hour clock face.
 *    - LCD_I2C_ADDRESS         : 0x27 or 0x3F depending on your backpack.
 * ============================================================================
 */

#include <SoftwareSerial.h>
#include <Wire.h>
#include <EEPROM.h>

// ============================================================================
//  USER CONFIGURATION
// ============================================================================

// The phone now transmits its LOCAL wall-clock as the epoch (BlePayloads
// .currentEpochSeconds adds the phone's UTC offset), so this should stay 0 and
// the clock will match the phone automatically, DST included. Only set a nonzero
// value if you are pairing with an OLD app build that still sends UTC — e.g.
// US Eastern: -5L * 3600L. Normally: leave it at 0.
static const long TIMEZONE_OFFSET_SECONDS = 0L;

#define USE_24H_DISPLAY   1        // 1 = HH:MM:SS 24h, 0 = hh:mm:ss AM/PM
#define LCD_I2C_ADDRESS   0x27     // try 0x3F if the screen stays blank

#define ENABLE_SNOOZE_BUTTON 1     // physical snooze / backlight-wake button on D10
#define ENABLE_LDR           0     // ambient-light auto-dim on A0 (off by default)
#define LDR_DARK_THRESHOLD   180   // analogRead below this => "dark" => dim

#define SNOOZE_MINUTES       5     // default snooze length; overridden per-alarm by 0x02 byte[6]
#define SNOOZE_MAX_COUNT     3     // fallback max snoozes when a 0x02 arrives without byte[5] (old app)
#define VOLUME_DEFAULT       200   // 0..255 ring loudness when an alarm's volume% is unset (~78%)
#define VOLUME_FADE_FLOOR    40    // gradual-wake starts this soft, then ramps to the target volume
#define VOLUME_TIMER         210   // fixed loudness for the finished-timer chime (no gradual wake)
#define TIMER_DONE_TIMEOUT_S 60    // auto-silence a finished timer after this long
#define BACKLIGHT_WAKE_MS    10000UL // button wakes the backlight for 10s

// ---- Pin assignments (match the wiring table in the spec) ------------------
#define PIN_HM10_TXD  2   // Arduino RX  (<- HM-10 TXD)
#define PIN_HM10_RXD  3   // Arduino TX  (-> HM-10 RXD, via divider)
#define PIN_BUZZER    9
#define PIN_BUTTON    10
#define PIN_LDR       A0

// ============================================================================
//  PROTOCOL CONSTANTS  (must match ble_framing.dart exactly)
// ============================================================================
static const uint8_t SOF = 0x5B; // '['
static const uint8_t EOF_BYTE = 0x5D; // ']'
static const uint8_t ESC = 0x5C; // '\'
static const uint8_t MAX_PAYLOAD = 15;

// App -> Clock commands
static const uint8_t CMD_TIME_SYNC   = 0x01;
static const uint8_t CMD_ALARM_ADD   = 0x02;
static const uint8_t CMD_ALARM_DEL   = 0x03;
static const uint8_t CMD_SYNC_START  = 0x04;
static const uint8_t CMD_SYNC_END    = 0x05;
static const uint8_t CMD_SETTINGS    = 0x06;
static const uint8_t CMD_QR_KEY      = 0x07;
static const uint8_t CMD_RING_ACK    = 0x88; // app -> clock: "I received your 0x08"
static const uint8_t CMD_DISMISS     = 0x09;
static const uint8_t CMD_TIMER_SET   = 0x0A;

// Clock -> App responses / notifications
static const uint8_t ACK_TIME_SYNC   = 0x81;
static const uint8_t ACK_ALARM_ADD   = 0x82;
static const uint8_t ACK_ALARM_DEL   = 0x83;
static const uint8_t ACK_SYNC_START  = 0x84;
static const uint8_t ACK_SYNC_END    = 0x85;
static const uint8_t ACK_SETTINGS    = 0x86;
static const uint8_t ACK_QR_KEY      = 0x87;
static const uint8_t NOTIFY_RING     = 0x08; // clock -> app: alarm started ringing
static const uint8_t ACK_DISMISS     = 0x89; // clock -> app: buzzer silenced / ring stopped
static const uint8_t ACK_TIMER_SET   = 0x8A;
static const uint8_t CMD_ERROR       = 0xFF;

// Error sub-codes (payload byte of a 0xFF frame)
static const uint8_t ERR_CHECKSUM    = 0x02;
static const uint8_t ERR_TOO_LONG    = 0x03;
static const uint8_t ERR_INVALID_CMD = 0x04;

// ============================================================================
//  DATA MODEL
// ============================================================================
#define MAX_ALARMS 5   // AlarmBloc.maxHardwareAlarms

// dayMask bit layout (matches Alarm.isDayActive / isActive in the app):
//   bit0=Sun bit1=Mon ... bit6=Sat, bit7=ACTIVE. (mask & 0x7F)==0 => one-time.
#define DAY_BITS_MASK 0x7F
#define ACTIVE_BIT    0x80

struct AlarmConfig {
  uint8_t id;
  uint8_t hour;
  uint8_t minute;
  uint8_t dayMask;
  uint8_t qrRequired;   // 1 => dismissal requires a matching token (0x09)
  uint8_t hasToken;     // 1 => token[] holds a valid 8-byte dismissal token
  uint8_t token[8];     // HMAC-derived token pushed by the app via 0x07
  uint8_t snoozeCount;  // max button snoozes allowed (0 => snooze disabled); byte[5] of 0x02
  uint8_t snoozeMinutes;// snooze length in minutes (0 => use SNOOZE_MINUTES default); byte[6] of 0x02
  uint8_t volume;       // ring loudness 1..100 (0 => VOLUME_DEFAULT); byte[7] of 0x02
  uint8_t fadeSeconds;  // gradual-wake fade-in length in s (0 => no fade); byte[8] of 0x02
  uint8_t reserved[1];  // headroom for one more per-alarm wire field (e.g. tone select) —
                        // adding one is a length-guarded wire byte with no EEPROM migration
                        // (record size unchanged). See EE_VERSION.
  uint8_t used;         // 1 => this slot holds a real alarm
};

AlarmConfig alarms[MAX_ALARMS];

// Runtime per-alarm guard so an alarm fires once per minute, not every loop.
uint32_t lastFiredMinute[MAX_ALARMS];

// Display / dimming settings (from 0x06 SETTINGS_WRITE).
uint8_t  autoDimMode      = 0;
uint8_t  sleepStartHour   = 22;
uint8_t  sleepStartMinute = 0;
uint8_t  sleepEndHour     = 7;
uint8_t  sleepEndMinute   = 0;

// ---- Timekeeping engine ----------------------------------------------------
uint32_t currentEpoch   = 0;      // seconds since Unix epoch (UTC), software-kept
uint32_t microAccum     = 0;      // fractional-second accumulator (microseconds)
uint32_t lastMicros     = 0;      // micros() at the previous engine tick
bool     haveTime       = false;  // true once the app has pushed the time at least once
int32_t  driftPPM       = 0;      // measured resonator drift correction (parts per million)
uint32_t lastSyncEpoch  = 0;      // epoch of the previous 0x01, for drift measurement
bool     haveSyncBase   = false;

// ---- Ringing state ---------------------------------------------------------
bool     ringLatched   = false;   // an alarm session is in progress (incl. snoozed)
bool     ringActive    = false;   // the buzzer is (or should be) sounding right now
uint8_t  ringAlarmId   = 0;
uint8_t  ringHour      = 0;
uint8_t  ringMinute    = 0;
bool     ringSecured   = false;   // qrRequired: only a token (or app) can end it
uint8_t  ringSnoozeMax = 0;       // this alarm's snooze allowance (0 = none), captured at startRing
uint8_t  ringSnoozeMin = 0;       // this alarm's snooze length in min (0 = default), captured at startRing
uint8_t  ringVolume    = 200;     // target loudness 0..255 (from the alarm's volume%), captured at startRing
uint8_t  ringFadeSeconds = 0;     // gradual-wake fade length in s (0 = none), captured at startRing
uint32_t ringFadeOriginMs = 0;    // millis() when the current ring / snooze-resume began sounding
uint8_t  snoozeUsed    = 0;
uint32_t snoozeUntil   = 0;       // epoch to resume buzzing after a snooze
bool     appAckedRing  = false;   // received 0x88, stop re-broadcasting 0x08
uint32_t lastRingBroadcastMs = 0;

// ---- Timer state -----------------------------------------------------------
bool     timerActive   = false;   // a countdown is running
uint32_t timerEndEpoch = 0;
bool     timerDone     = false;   // countdown hit zero, buzzer announcing it
uint32_t timerDoneStartMs = 0;

// ---- Sync UI ---------------------------------------------------------------
bool     syncing        = false;
bool     alarmsDirty    = false;  // alarm table changed but not yet flushed to
                                  // EEPROM (writes are batched during a sync)
uint32_t syncBannerUntilMs = 0;   // show "SYNCED" briefly after 0x05

// ---- Connection heuristic --------------------------------------------------
uint32_t lastFrameMs    = 0;      // millis() of the last valid frame from the app
static const uint32_t LINK_TIMEOUT_MS = 20000UL;

// ---- Backlight -------------------------------------------------------------
bool     backlightOn    = true;
uint32_t backlightWakeUntilMs = 0;

// ============================================================================
//  MINIMAL 16x2 I2C LCD DRIVER  (PCF8574 backpack + HD44780, 4-bit mode)
// ----------------------------------------------------------------------------
//  Replaces the external LiquidCrystal_I2C library so the sketch needs no
//  add-on libraries. Bit mapping is the near-universal backpack wiring:
//    P0=RS  P1=RW  P2=EN  P3=Backlight  P4..P7=D4..D7
//  Only the methods this firmware uses are implemented.
// ============================================================================
class LcdI2C {
 public:
  LcdI2C(uint8_t addr, uint8_t cols, uint8_t rows)
      : _addr(addr), _cols(cols), _rows(rows), _backlight(BL) {}

  void init() {
    delay(50);                       // wait for the HD44780 to power up
    expanderWrite(0);
    delay(100);
    // Force 4-bit mode via the documented reset dance.
    write4(0x30); delayMicroseconds(4500);
    write4(0x30); delayMicroseconds(4500);
    write4(0x30); delayMicroseconds(150);
    write4(0x20);                     // now in 4-bit mode
    command(0x28);                    // function set: 4-bit, 2 lines, 5x8 font
    command(0x0C);                    // display on, cursor off, blink off
    command(0x01); delay(2);          // clear
    command(0x06);                    // entry mode: increment, no shift
  }

  void clear() { command(0x01); delay(2); }

  void setCursor(uint8_t col, uint8_t row) {
    static const uint8_t rowOffset[2] = {0x00, 0x40};
    if (row >= _rows) row = _rows - 1;
    command(0x80 | (col + rowOffset[row]));
  }

  void backlight()   { _backlight = BL; expanderWrite(0); }
  void noBacklight() { _backlight = 0;  expanderWrite(0); }

  void createChar(uint8_t location, uint8_t charmap[]) {
    location &= 0x7;
    command(0x40 | (location << 3));
    for (uint8_t i = 0; i < 8; i++) write(charmap[i]);
  }

  void write(uint8_t value) { send(value, RS); }

  void print(const char *s) { while (*s) write((uint8_t)*s++); }
  void print(const __FlashStringHelper *s) {
    const char *p = reinterpret_cast<const char *>(s);
    uint8_t c;
    while ((c = pgm_read_byte(p++)) != 0) write(c);
  }

 private:
  static const uint8_t RS = 0x01, RW = 0x02, EN = 0x04, BL = 0x08;
  uint8_t _addr, _cols, _rows, _backlight;

  void command(uint8_t value) { send(value, 0); }

  void send(uint8_t value, uint8_t mode) {
    write4((value & 0xF0) | mode);
    write4(((value << 4) & 0xF0) | mode);
  }

  void write4(uint8_t nibbleAndCtrl) {
    expanderWrite(nibbleAndCtrl);
    pulse(nibbleAndCtrl);
  }

  void expanderWrite(uint8_t data) {
    Wire.beginTransmission(_addr);
    Wire.write(data | _backlight);
    Wire.endTransmission();
  }

  void pulse(uint8_t data) {
    expanderWrite(data | EN);
    delayMicroseconds(1);
    expanderWrite(data & ~EN);
    delayMicroseconds(50);
  }
};

// ============================================================================
//  DEVICE INSTANCES
// ============================================================================
LcdI2C lcd(LCD_I2C_ADDRESS, 16, 2);
SoftwareSerial bleSerial(PIN_HM10_TXD, PIN_HM10_RXD); // (rxPin, txPin)

// ---- Forward declarations --------------------------------------------------
// NOTE: types used in any function signature MUST be defined here, above the
// first function, because the Arduino build inserts auto-generated prototypes
// just before the first function — a struct defined lower down would not yet be
// visible to those prototypes.
struct LocalTime { uint8_t hh; uint8_t mm; uint8_t ss; uint8_t dow; };
enum BuzzMode { BUZZ_OFF, BUZZ_ALARM, BUZZ_TIMER };
void buzzerSetMode(BuzzMode m);
void applyBuzzStep();
void endRing(bool notifyApp);
void tryDismiss(uint8_t id, const uint8_t *token);
void startTimer(uint32_t seconds);
void handleFrame(uint8_t *body, uint8_t n);

// ============================================================================
//  EEPROM PERSISTENCE
// ----------------------------------------------------------------------------
//  Layout (so the clock keeps its schedule across power loss — spec 4.1 "Edge
//  Autonomy"). EEPROM.update() is used everywhere to minimise write wear.
//     0x00  magic (0x5A)
//     0x01  version (1)
//     0x02  autoDimMode
//     0x03  sleepStartHour
//     0x04  sleepStartMinute
//     0x05  sleepEndHour
//     0x06  sleepEndMinute
//     0x07  driftPPM (int16, little-endian)
//     0x09  alarms[MAX_ALARMS] (sizeof(AlarmConfig) each)
// ============================================================================
static const int    EE_MAGIC_ADDR   = 0x00;
static const uint8_t EE_MAGIC        = 0x5A;
// Bumped 1 -> 2 when AlarmConfig grew (added snoozeCount + reserved[]): the record
// size changed, so old EEPROM bytes no longer deserialize. eepromLoadAll() treats a
// version mismatch like a first boot (wipe + re-stamp); the phone re-sends every
// alarm on the next connect, so nothing is permanently lost.
static const uint8_t EE_VERSION      = 2;
static const int    EE_VERSION_ADDR = 0x01;
static const int    EE_AUTODIM_ADDR = 0x02;
static const int    EE_SLEEP_ADDR   = 0x03; // 4 bytes: startH,startM,endH,endM
static const int    EE_DRIFT_ADDR   = 0x07; // 2 bytes
static const int    EE_ALARMS_ADDR  = 0x09;

void eepromSaveSettings() {
  EEPROM.update(EE_MAGIC_ADDR, EE_MAGIC);
  EEPROM.update(EE_VERSION_ADDR, EE_VERSION);
  EEPROM.update(EE_AUTODIM_ADDR, autoDimMode);
  EEPROM.update(EE_SLEEP_ADDR + 0, sleepStartHour);
  EEPROM.update(EE_SLEEP_ADDR + 1, sleepStartMinute);
  EEPROM.update(EE_SLEEP_ADDR + 2, sleepEndHour);
  EEPROM.update(EE_SLEEP_ADDR + 3, sleepEndMinute);
}

void eepromSaveDrift() {
  int16_t d = (int16_t)driftPPM;
  EEPROM.update(EE_DRIFT_ADDR + 0, (uint8_t)(d & 0xFF));
  EEPROM.update(EE_DRIFT_ADDR + 1, (uint8_t)((d >> 8) & 0xFF));
}

void eepromSaveAlarms() {
  for (int i = 0; i < MAX_ALARMS; i++) {
    EEPROM.put(EE_ALARMS_ADDR + i * (int)sizeof(AlarmConfig), alarms[i]);
  }
  EEPROM.update(EE_MAGIC_ADDR, EE_MAGIC);
}

// Persist the alarm table, but coalesce the burst of per-frame changes that
// arrive during a sync (0x02 upserts / 0x07 tokens / 0x03 deletes) into a
// single flush at CMD_SYNC_END. A full eepromSaveAlarms() rewrites up to
// 5*20 bytes and blocks for tens–hundreds of ms while the EEPROM cells settle;
// doing that once per frame can back up the 64-byte SoftwareSerial RX buffer
// mid-burst and drop bytes, corrupting the sync. Deferring keeps the UART
// drained during the burst. Outside a sync we still write immediately.
void persistAlarms() {
  if (syncing) alarmsDirty = true;
  else eepromSaveAlarms();
}

// Belt-and-suspenders for the batched writes above: if a sync's closing 0x05 is
// ever lost, don't leave the alarm changes unpersisted (or the clock stuck in
// "syncing"). Once the link has gone idle past the timeout, flush and clear.
void serviceSyncFlush() {
  if (!syncing && !alarmsDirty) return;
  if (lastFrameMs != 0 && (uint32_t)(millis() - lastFrameMs) >= LINK_TIMEOUT_MS) {
    if (alarmsDirty) { eepromSaveAlarms(); alarmsDirty = false; }
    syncing = false;
  }
}

void eepromLoadAll() {
  if (EEPROM.read(EE_MAGIC_ADDR) != EE_MAGIC ||
      EEPROM.read(EE_VERSION_ADDR) != EE_VERSION) {
    // First boot, uninitialised EEPROM, or a firmware whose AlarmConfig layout
    // changed (EE_VERSION bump): the stored bytes no longer deserialize, so start
    // empty and re-stamp (eepromSaveSettings writes the new version). The phone
    // re-sends every alarm on the next connect, so nothing is permanently lost.
    for (int i = 0; i < MAX_ALARMS; i++) {
      memset(&alarms[i], 0, sizeof(AlarmConfig));
    }
    eepromSaveSettings();
    eepromSaveDrift();
    eepromSaveAlarms();
    return;
  }
  autoDimMode      = EEPROM.read(EE_AUTODIM_ADDR);
  sleepStartHour   = EEPROM.read(EE_SLEEP_ADDR + 0);
  sleepStartMinute = EEPROM.read(EE_SLEEP_ADDR + 1);
  sleepEndHour     = EEPROM.read(EE_SLEEP_ADDR + 2);
  sleepEndMinute   = EEPROM.read(EE_SLEEP_ADDR + 3);
  int16_t d = (int16_t)(EEPROM.read(EE_DRIFT_ADDR) |
                        ((uint16_t)EEPROM.read(EE_DRIFT_ADDR + 1) << 8));
  driftPPM = d;
  for (int i = 0; i < MAX_ALARMS; i++) {
    EEPROM.get(EE_ALARMS_ADDR + i * (int)sizeof(AlarmConfig), alarms[i]);
    if (alarms[i].used > 1) { // guard against garbage
      memset(&alarms[i], 0, sizeof(AlarmConfig));
    }
  }
}

// ============================================================================
//  ALARM TABLE HELPERS  (id-keyed upsert / delete, mirroring the app)
// ============================================================================
int findAlarmSlot(uint8_t id) {
  for (int i = 0; i < MAX_ALARMS; i++) {
    if (alarms[i].used && alarms[i].id == id) return i;
  }
  return -1;
}

int findFreeSlot() {
  for (int i = 0; i < MAX_ALARMS; i++) {
    if (!alarms[i].used) return i;
  }
  return -1;
}

// Upsert an alarm from a 0x02 ALARM_DB_ADD frame. Preserves any token already
// stored for this id (the token arrives separately via 0x07 and both orders
// happen during a sync).
void upsertAlarm(uint8_t id, uint8_t hour, uint8_t minute,
                 uint8_t dayMask, uint8_t qrRequired, uint8_t snoozeCount,
                 uint8_t snoozeMinutes, uint8_t volume, uint8_t fadeSeconds) {
  int slot = findAlarmSlot(id);
  if (slot < 0) slot = findFreeSlot();
  if (slot < 0) return; // table full; app also caps at MAX_ALARMS so this is rare

  AlarmConfig &a = alarms[slot];
  bool sameId = (a.used && a.id == id);
  a.id          = id;
  a.hour        = hour;
  a.minute      = minute;
  a.dayMask     = dayMask;
  a.qrRequired   = qrRequired ? 1 : 0;
  a.snoozeCount  = snoozeCount;
  a.snoozeMinutes = snoozeMinutes;
  a.volume       = volume;      // 0 => startRing falls back to VOLUME_DEFAULT
  a.fadeSeconds  = fadeSeconds; // 0 => no gradual-wake fade
  if (!sameId) {          // brand-new slot: no token yet, clear reserved headroom
    a.hasToken = 0;
    memset(a.token, 0, 8);
    memset(a.reserved, 0, sizeof(a.reserved));
  }
  a.used = 1;
  lastFiredMinute[slot] = 0xFFFFFFFF; // don't retro-fire on load/edit
  persistAlarms();
}

void deleteAlarm(uint8_t id) {
  int slot = findAlarmSlot(id);
  if (slot < 0) return;
  // If this alarm is currently ringing, stop it.
  if (ringLatched && ringAlarmId == id) endRing(false);
  memset(&alarms[slot], 0, sizeof(AlarmConfig));
  persistAlarms();
}

void storeToken(uint8_t id, const uint8_t *token) {
  int slot = findAlarmSlot(id);
  if (slot < 0) return;
  alarms[slot].hasToken = 1;
  memcpy(alarms[slot].token, token, 8);
  alarms[slot].used = 1;
  persistAlarms();
}

// ============================================================================
//  TIMEKEEPING ENGINE
// ----------------------------------------------------------------------------
//  The Uno has no RTC. We integrate micros() into a seconds counter, applying a
//  measured drift correction. Unsigned subtraction makes the micros() rollover
//  (~71 min) harmless as long as the loop runs far more often than that.
// ============================================================================
void tickClock() {
  uint32_t now = micros();
  uint32_t dt = now - lastMicros;   // correct across rollover (unsigned wrap)
  lastMicros = now;

  // Apply drift: effective = dt * (1 + driftPPM/1e6).
  int32_t corr = (int32_t)(((int64_t)dt * driftPPM) / 1000000L);
  uint32_t eff = dt + corr;
  microAccum += eff;
  while (microAccum >= 1000000UL) {
    microAccum -= 1000000UL;
    currentEpoch++;
  }
}

// Set the clock from a 0x01 TIME_SYNC and refine the drift estimate by comparing
// how many seconds WE counted between syncs vs how many actually elapsed.
void applyTimeSync(uint32_t epoch) {
  if (haveSyncBase && haveTime && epoch > lastSyncEpoch) {
    uint32_t realElapsed = epoch - lastSyncEpoch;         // phone-authoritative
    int32_t  ourElapsed  = (int32_t)(currentEpoch - lastSyncEpoch);
    // Only calibrate over a long-enough window for a stable measurement.
    if (realElapsed >= 600UL && realElapsed <= 7UL * 24UL * 3600UL) {
      int32_t errSec = ourElapsed - (int32_t)realElapsed;  // + => we ran fast
      // Reject implausible corrections. A real resonator drifts at most a few
      // percent, so over `realElapsed` seconds the counted error cannot exceed
      // ~realElapsed/20 (5%). A bigger gap means the phone's WALL clock moved —
      // the epoch we receive is LOCAL time, so a DST change or timezone hop adds
      // a ±3600s step that is not oscillator drift. Re-base the clock to it (we
      // always do, below) but don't poison the drift estimate with it.
      int32_t maxPlausible = (int32_t)(realElapsed / 20UL) + 5;
      if (errSec > -maxPlausible && errSec < maxPlausible) {
        // ppm adjustment that would have cancelled this error over the window.
        int32_t adj =
            (int32_t)(((int64_t)(-errSec) * 1000000L) / (int32_t)realElapsed);
        driftPPM += adj;
        if (driftPPM >  30000) driftPPM =  30000;
        if (driftPPM < -30000) driftPPM = -30000;
        eepromSaveDrift();
      }
    }
  }
  currentEpoch  = epoch;
  lastSyncEpoch = epoch;
  haveSyncBase  = true;
  haveTime      = true;
  microAccum    = 0;
  lastMicros    = micros();
}

// Decompose the software clock into LOCAL date/time parts. (LocalTime is
// declared up in the forward-declaration block so prototypes can see it.)
LocalTime localNow() {
  LocalTime t = {0, 0, 0, 0};
  int64_t local = (int64_t)currentEpoch + (int64_t)TIMEZONE_OFFSET_SECONDS;
  if (local < 0) local = 0;
  uint32_t secOfDay = (uint32_t)(local % 86400);
  uint32_t days     = (uint32_t)(local / 86400);
  t.hh  = secOfDay / 3600;
  t.mm  = (secOfDay % 3600) / 60;
  t.ss  = secOfDay % 60;
  t.dow = (uint8_t)((days + 4) % 7); // Unix day 0 (1970-01-01) was a Thursday
  return t;
}

// ============================================================================
//  BLE FRAME I/O
// ----------------------------------------------------------------------------
//  Encoder/decoder mirror BleFraming in the app: body = [cmd,len,data...,cs],
//  cs = cmd^len^data..., every body byte escaped if it equals SOF/EOF/ESC.
// ============================================================================
void sendFrame(uint8_t cmd, const uint8_t *data, uint8_t len) {
  if (len > MAX_PAYLOAD) return;
  uint8_t cs = cmd ^ len;
  for (uint8_t i = 0; i < len; i++) cs ^= data[i];

  bleSerial.write(SOF);
  // cmd, len, data..., cs  — all uniformly escaped.
  uint8_t header[2] = { cmd, len };
  for (uint8_t i = 0; i < 2; i++) {
    if (header[i] == SOF || header[i] == EOF_BYTE || header[i] == ESC) bleSerial.write(ESC);
    bleSerial.write(header[i]);
  }
  for (uint8_t i = 0; i < len; i++) {
    if (data[i] == SOF || data[i] == EOF_BYTE || data[i] == ESC) bleSerial.write(ESC);
    bleSerial.write(data[i]);
  }
  if (cs == SOF || cs == EOF_BYTE || cs == ESC) bleSerial.write(ESC);
  bleSerial.write(cs);
  bleSerial.write(EOF_BYTE);
}

void sendAck(uint8_t code) { sendFrame(code, NULL, 0); }
void sendAck1(uint8_t code, uint8_t b) { sendFrame(code, &b, 1); }
void sendError(uint8_t err) { sendFrame(CMD_ERROR, &err, 1); }

// Incoming byte-stream state machine. Handles frames split across the HM-10's
// ~20-byte notification chunks without blocking.
enum RxState { RX_WAIT_SOF, RX_BODY };
RxState  rxState = RX_WAIT_SOF;
uint8_t  rxBody[MAX_PAYLOAD + 3]; // cmd + len + data(<=15) + cs
uint8_t  rxLen = 0;
bool     rxEscape = false;

void resetRx() { rxState = RX_WAIT_SOF; rxLen = 0; rxEscape = false; }

void pumpBle() {
  while (bleSerial.available() > 0) {
    uint8_t b = (uint8_t)bleSerial.read();

    if (rxState == RX_WAIT_SOF) {
      if (b == SOF) { rxState = RX_BODY; rxLen = 0; rxEscape = false; }
      continue;
    }

    // RX_BODY
    if (rxEscape) {
      if (rxLen < sizeof(rxBody)) rxBody[rxLen++] = b;
      else resetRx();
      rxEscape = false;
      continue;
    }
    if (b == ESC) { rxEscape = true; continue; }
    if (b == SOF) { rxLen = 0; rxEscape = false; continue; } // restart on stray SOF
    if (b == EOF_BYTE) {
      // Validate: body = [cmd, len, data(len), cs] => length == len + 3.
      if (rxLen >= 3) {
        uint8_t cmd = rxBody[0];
        uint8_t len = rxBody[1];
        if (len > MAX_PAYLOAD) {
          sendError(ERR_TOO_LONG);
        } else if (rxLen == (uint8_t)(len + 3)) {
          uint8_t cs = cmd ^ len;
          for (uint8_t i = 0; i < len; i++) cs ^= rxBody[2 + i];
          if (cs == rxBody[2 + len]) {
            lastFrameMs = millis();
            handleFrame(rxBody, rxLen);
          } else {
            sendError(ERR_CHECKSUM);
          }
        }
      }
      resetRx();
      continue;
    }
    if (rxLen < sizeof(rxBody)) rxBody[rxLen++] = b;
    else resetRx(); // overrun; drop and resync
  }
}

// ============================================================================
//  COMMAND DISPATCH
// ============================================================================
void handleFrame(uint8_t *body, uint8_t n) {
  (void)n;
  uint8_t cmd = body[0];
  uint8_t len = body[1];
  uint8_t *data = &body[2];

  switch (cmd) {
    case CMD_TIME_SYNC: {                 // [epoch uint32 big-endian]
      if (len >= 4) {
        uint32_t epoch = ((uint32_t)data[0] << 24) | ((uint32_t)data[1] << 16) |
                         ((uint32_t)data[2] << 8)  |  (uint32_t)data[3];
        applyTimeSync(epoch);
      }
      sendAck(ACK_TIME_SYNC);
      break;
    }
    case CMD_ALARM_ADD: {                 // [id,hour,minute,dayMask,qrRequired,snoozeCount?,snoozeMin?,vol?,fade?]
      if (len >= 5) {
        // Every byte past [4] is optional so older/shorter frames still work:
        // an older app sends fewer bytes and each field falls back to a safe
        // default. Bytes beyond [8] are reserved headroom and ignored here.
        uint8_t snoozeCount   = (len >= 6) ? data[5] : SNOOZE_MAX_COUNT;
        // byte[6] snooze length (min): 0/absent => SNOOZE_MINUTES, at snooze time.
        uint8_t snoozeMinutes = (len >= 7) ? data[6] : 0;
        // byte[7] volume 1..100: 0/absent => VOLUME_DEFAULT, resolved at startRing.
        uint8_t volume        = (len >= 8) ? data[7] : 0;
        // byte[8] gradual-wake fade (s): 0/absent => no fade (ring at full volume).
        uint8_t fadeSeconds   = (len >= 9) ? data[8] : 0;
        upsertAlarm(data[0], data[1], data[2], data[3], data[4], snoozeCount,
                    snoozeMinutes, volume, fadeSeconds);
        sendAck1(ACK_ALARM_ADD, data[0]); // echo the id (app expects it)
      } else {
        sendError(ERR_INVALID_CMD);
      }
      break;
    }
    case CMD_ALARM_DEL: {                 // [id]
      if (len >= 1) { deleteAlarm(data[0]); sendAck1(ACK_ALARM_DEL, data[0]); }
      else sendError(ERR_INVALID_CMD);
      break;
    }
    case CMD_SYNC_START:
      syncing = true;
      sendAck(ACK_SYNC_START);
      break;
    case CMD_SYNC_END:
      syncing = false;
      // Commit the whole sync's alarm changes in one EEPROM write now that the
      // frame burst is over (see persistAlarms).
      if (alarmsDirty) { eepromSaveAlarms(); alarmsDirty = false; }
      syncBannerUntilMs = millis() + 1200UL;
      sendAck(ACK_SYNC_END);
      break;
    case CMD_SETTINGS: {                  // [autoDim,startH,startM,endH,endM]
      if (len >= 5) {
        autoDimMode      = data[0] ? 1 : 0;
        sleepStartHour   = data[1];
        sleepStartMinute = data[2];
        sleepEndHour     = data[3];
        sleepEndMinute   = data[4];
        eepromSaveSettings();
      }
      sendAck(ACK_SETTINGS);
      break;
    }
    case CMD_QR_KEY: {                     // [id, token x8]
      if (len >= 9) storeToken(data[0], &data[1]);
      sendAck(ACK_QR_KEY);
      break;
    }
    case CMD_DISMISS: {                    // [id, token x8]
      if (len >= 9) tryDismiss(data[0], &data[1]);
      // ACK_DISMISS (0x89) is emitted by endRing() only on a successful stop, so
      // a wrong token leaves the buzzer sounding (enforces the wake challenge).
      break;
    }
    case CMD_TIMER_SET: {                  // [seconds uint32 big-endian]
      if (len >= 4) {
        uint32_t secs = ((uint32_t)data[0] << 24) | ((uint32_t)data[1] << 16) |
                        ((uint32_t)data[2] << 8)  |  (uint32_t)data[3];
        startTimer(secs);
      }
      sendAck(ACK_TIMER_SET);
      break;
    }
    case CMD_RING_ACK:                     // app confirmed it saw the ring
      appAckedRing = true;
      break;
    default:
      sendError(ERR_INVALID_CMD);
      break;
  }
}

// ============================================================================
//  ALARM RINGING LIFECYCLE
// ============================================================================
void startRing(int slot) {
  AlarmConfig &a = alarms[slot];
  ringLatched  = true;
  ringActive   = true;
  ringAlarmId  = a.id;
  ringHour     = a.hour;
  ringMinute   = a.minute;
  ringSecured  = a.qrRequired ? true : false;
  ringSnoozeMax = a.snoozeCount;   // honour the app's per-alarm snooze allowance (0 = none)
  ringSnoozeMin = a.snoozeMinutes; // ...and its snooze length (0 => SNOOZE_MINUTES default)
  // Map the alarm's volume% (1..100; 0 => default) to the 0..255 loudness the
  // synth's PWM duty uses, and remember the gradual-wake fade length.
  ringVolume    = a.volume ? (uint8_t)((uint16_t)a.volume * 255 / 100) : VOLUME_DEFAULT;
  ringFadeSeconds = a.fadeSeconds;
  snoozeUsed   = 0;
  appAckedRing = false;
  lastRingBroadcastMs = 0; // force an immediate 0x08 broadcast

  // One-time alarms ((mask & 0x7F)==0) disarm immediately so they never re-fire
  // — matching the app's one-time auto-disable in AlarmBloc._onSetRingingAlarm.
  if ((a.dayMask & DAY_BITS_MASK) == 0) {
    a.dayMask &= ~ACTIVE_BIT;
    eepromSaveAlarms();
  }
  buzzerSetMode(BUZZ_ALARM);
}

// End the current ring session. If notifyApp, also emit 0x89 so the app clears
// its ringing UI (this is both the dismiss-ack and the ring-stop notification).
void endRing(bool notifyApp) {
  ringLatched = false;
  ringActive  = false;
  buzzerSetMode(BUZZ_OFF);
  if (notifyApp) sendAck(ACK_DISMISS);
}

// Verify a token-gated dismissal request (0x09) against the ringing alarm.
void tryDismiss(uint8_t id, const uint8_t *token) {
  if (!ringLatched || id != ringAlarmId) {
    // Not the ringing alarm — still acknowledge so the app's state can settle.
    sendAck(ACK_DISMISS);
    return;
  }
  int slot = findAlarmSlot(id);
  bool ok;
  if (!ringSecured) {
    ok = true;                                   // button-dismissal alarm
  } else if (slot >= 0 && alarms[slot].hasToken) {
    ok = (memcmp(alarms[slot].token, token, 8) == 0);
  } else {
    ok = true; // secured but no key on record — accept rather than strand the user
  }
  if (ok) endRing(true); // endRing emits 0x89
  // On mismatch: stay silent and keep ringing; the user must present the right code.
}

// Snooze the current ring (physical button). Secured alarms may only snooze
// (never fully dismiss) via the button; unsecured alarms are dismissed outright.
void buttonOnRing() {
  if (!ringLatched) return;
  if (!ringSecured) {
    endRing(true); // button dismissal for non-secured alarms
    return;
  }
  if (snoozeUsed < ringSnoozeMax) {
    snoozeUsed++;
    ringActive = false;
    buzzerSetMode(BUZZ_OFF);
    uint8_t snoozeMin = ringSnoozeMin ? ringSnoozeMin : SNOOZE_MINUTES;
    snoozeUntil = currentEpoch + (uint32_t)snoozeMin * 60UL;
  }
  // else: snooze disabled (ringSnoozeMax 0) or budget exhausted — keep sounding
  // until the app scan (0x09) arrives.
}

// Scan the alarm table once per loop and fire anything due this minute.
void checkAlarms() {
  if (!haveTime) return;
  if (ringLatched) return;                     // one ring at a time
  LocalTime t = localNow();
  // Fire on a minute-boundary match rather than the exact ss==0 instant: a
  // TIME_SYNC that jumps the clock across hh:mm:00, or a blocking EEPROM/LCD
  // write straddling that second, can mean no loop iteration ever observes
  // ss==0 — which would silently skip the alarm. Matching hh:mm and de-duping
  // on minuteIndex fires each alarm exactly once in its minute despite jitter.
  uint32_t minuteIndex = currentEpoch / 60UL;

  for (int i = 0; i < MAX_ALARMS; i++) {
    AlarmConfig &a = alarms[i];
    if (!a.used) continue;
    if ((a.dayMask & ACTIVE_BIT) == 0) continue;
    if (a.hour != t.hh || a.minute != t.mm) continue;
    if (lastFiredMinute[i] == minuteIndex) continue;

    uint8_t dayBits = a.dayMask & DAY_BITS_MASK;
    bool today = (dayBits == 0) ? true : ((dayBits & (1 << t.dow)) != 0);
    if (!today) continue;

    lastFiredMinute[i] = minuteIndex;
    startRing(i);
    break;
  }
}

// While an alarm is ringing, resume after a snooze and keep the app informed by
// re-broadcasting 0x08 until it acknowledges with 0x88.
void serviceRing() {
  if (!ringLatched) return;

  if (!ringActive && currentEpoch >= snoozeUntil) {
    ringActive = true;
    appAckedRing = false;
    lastRingBroadcastMs = 0;
    buzzerSetMode(BUZZ_ALARM);
  }
  if (ringActive && !appAckedRing) {
    uint32_t nowMs = millis();
    if (lastRingBroadcastMs == 0 || (nowMs - lastRingBroadcastMs) >= 3000UL) {
      sendFrame(NOTIFY_RING, &ringAlarmId, 1);
      lastRingBroadcastMs = nowMs;
    }
  }
}

// ============================================================================
//  COUNTDOWN TIMER
// ============================================================================
void startTimer(uint32_t seconds) {
  if (seconds == 0) return;
  timerActive   = true;
  timerDone     = false;
  timerEndEpoch = currentEpoch + seconds;
}

void serviceTimer() {
  if (timerActive && currentEpoch >= timerEndEpoch) {
    timerActive = false;
    timerDone   = true;
    timerDoneStartMs = millis();
    // A ringing alarm owns the speaker; don't let a finishing timer steal it.
    if (!ringActive) buzzerSetMode(BUZZ_TIMER);
  }
  if (timerDone) {
    // Auto-silence after a timeout (there is no BLE "stop timer" command) or if
    // an alarm needs the buzzer.
    if (ringActive || (millis() - timerDoneStartMs) >= (uint32_t)TIMER_DONE_TIMEOUT_S * 1000UL) {
      timerDone = false;
      if (!ringActive) buzzerSetMode(BUZZ_OFF);
    }
  }
}

// ============================================================================
//  SOUND ENGINE — Timer1 hardware PWM on D9 (OC1A), replacing tone()
// ----------------------------------------------------------------------------
//  tone() emits a fixed-amplitude square wave and can't vary loudness. Driving
//  Timer1 in phase-correct PWM lets us set BOTH pitch (ICR1 = TOP) and loudness
//  (OCR1A = duty) directly in hardware — so the wave keeps sounding even while
//  SoftwareSerial masks interrupts to receive the dismiss frame, AND we can
//  shape the duty across each note for a struck-bell (glockenspiel) decay
//  instead of a flat beep. Loudness drives two effects: the per-note envelope
//  (the chime timbre) and the master gradual-wake fade toward the alarm volume.
// ============================================================================
BuzzMode buzzMode = BUZZ_OFF;

// Per-note amplitude envelope — a struck-bell shape: a very fast attack then an
// exponential decay. Built once in soundInit() so there's no hand-typed table.
#define ENV_LEN       40      // decay samples...
#define ENV_STEP_MS   10      // ...one every 10 ms => ~400 ms of shaped decay
#define ATTACK_MS     4       // brief ramp-in so note onsets don't click
uint8_t envTable[ENV_LEN];

void soundOff() {
  TCCR1A = 0;               // release OC1A (pin returns to the port latch = LOW)
  TCCR1B = 0;               // stop Timer1's clock
  digitalWrite(PIN_BUZZER, LOW);
}

// Set the loudness of the note in progress. OCR1A is double-buffered (latched at
// TOP), so this is glitch-free to call every service tick to shape the envelope.
void soundSetVol(uint8_t vol) {
  uint16_t top = ICR1;
  if (top == 0) return;
  // Duty peaks near 50% (a square wave) at vol=255; lower duty = quieter.
  OCR1A = (uint16_t)(((uint32_t)top * vol) / 512UL);  // vol 0 => duty 0 => silent
}

// Begin a new note at frequency `hz`, loudness `vol` (0..255).
void soundStart(uint16_t hz, uint8_t vol) {
  if (hz < 123) { soundOff(); return; }    // below this, TOP overflows 16 bits
  ICR1 = (uint16_t)(F_CPU / (2UL * hz));    // phase-correct: f = F_CPU / (2*TOP)
  soundSetVol(vol);
  TCNT1 = 0;                                // clean phase start avoids a wrap click
  TCCR1A = _BV(COM1A1) | _BV(WGM11);        // non-inverting, phase-correct PWM,
  TCCR1B = _BV(WGM13) | _BV(CS10);          // TOP = ICR1, prescaler 1
}

void soundInit() {
  pinMode(PIN_BUZZER, OUTPUT);
  digitalWrite(PIN_BUZZER, LOW);
  TCCR1A = 0; TCCR1B = 0;                    // Timer1 idle until the first note
  for (uint8_t i = 0; i < ENV_LEN; i++) {
    // Exp decay, tau ~= 18 samples (~180 ms to 37%): rings like a soft chime.
    envTable[i] = (uint8_t)(255.0 * exp(-(float)i / 18.0) + 0.5);
  }
}

// The per-note envelope amplitude (0..255) at `elapsed` ms into the note.
uint8_t noteEnv(uint32_t elapsed) {
  if (elapsed < ATTACK_MS) return (uint8_t)(255UL * elapsed / ATTACK_MS);
  uint32_t di = (elapsed - ATTACK_MS) / ENV_STEP_MS;
  if (di >= ENV_LEN) return envTable[ENV_LEN - 1];
  return envTable[di];
}

// Master loudness right now: a fixed level for timers; for an alarm, the
// gradual-wake ramp from VOLUME_FADE_FLOOR up to ringVolume over ringFadeSeconds
// (or straight to ringVolume when no fade). Unsigned millis() math is rollover-safe.
uint8_t masterVolNow() {
  if (buzzMode == BUZZ_TIMER) return VOLUME_TIMER;
  if (ringFadeSeconds == 0) return ringVolume;
  uint32_t elapsed = millis() - ringFadeOriginMs;
  uint32_t fadeMs  = (uint32_t)ringFadeSeconds * 1000UL;
  if (elapsed >= fadeMs) return ringVolume;
  uint16_t span = (ringVolume > VOLUME_FADE_FLOOR) ? (ringVolume - VOLUME_FADE_FLOOR) : 0;
  return (uint8_t)(VOLUME_FADE_FLOOR + (uint32_t)span * elapsed / fadeMs);
}

// ---- Non-blocking chime player --------------------------------------------
//  Rests (freq 0) between phrases both make it sound like a chime and give
//  SoftwareSerial clean windows to receive the dismiss frame while ringing.
struct ToneStep { uint16_t freq; uint16_t ms; }; // freq 0 = silence

// A warm ascending major arpeggio (G5-C6-E6) that steps down to resolve on C6
// and rings out through the bell decay — a gentle wake chime, not a jarring beep.
const ToneStep ALARM_PATTERN[] = {
  { 784, 260}, {0, 30},   // G5
  {1047, 260}, {0, 30},   // C6
  {1319, 300}, {0, 40},   // E6  (bright peak)
  {1175, 260}, {0, 30},   // D6
  {1047, 480},            // C6  (resolve — held, decays away)
  {   0, 620},            // breathe before the phrase repeats
};
// A short two-note "ding-dong" for finished timers, distinct from the alarm.
const ToneStep TIMER_PATTERN[] = {
  {1319, 200}, {0, 60},   // E6
  {1047, 340},            // C6
  {   0, 520},
};
const uint8_t ALARM_STEPS = sizeof(ALARM_PATTERN) / sizeof(ToneStep);
const uint8_t TIMER_STEPS = sizeof(TIMER_PATTERN) / sizeof(ToneStep);

uint8_t  buzzStep = 0;
uint32_t buzzStepStart = 0;
uint16_t buzzNoteFreq = 0;     // frequency of the step in progress (0 = a rest)

void applyBuzzStep() {
  const ToneStep *pat = (buzzMode == BUZZ_ALARM) ? ALARM_PATTERN : TIMER_PATTERN;
  buzzNoteFreq = pat[buzzStep].freq;
  if (buzzNoteFreq == 0) { soundOff(); return; }
  // Start at the envelope onset scaled by the current master (gradual-wake) volume.
  soundStart(buzzNoteFreq, (uint8_t)((uint16_t)noteEnv(0) * masterVolNow() / 255));
}

void buzzerSetMode(BuzzMode m) {
  if (m == buzzMode) return;
  buzzMode = m;
  buzzStep = 0;
  buzzStepStart = millis();
  if (m != BUZZ_OFF) ringFadeOriginMs = buzzStepStart; // (re)start the gradual-wake fade
  soundOff();
  if (m != BUZZ_OFF) applyBuzzStep();
}

void serviceBuzzer() {
  if (buzzMode == BUZZ_OFF) return;
  const ToneStep *pat = (buzzMode == BUZZ_ALARM) ? ALARM_PATTERN : TIMER_PATTERN;
  uint8_t steps = (buzzMode == BUZZ_ALARM) ? ALARM_STEPS : TIMER_STEPS;
  uint32_t now = millis();
  uint32_t elapsed = now - buzzStepStart;
  if (elapsed >= pat[buzzStep].ms) {          // advance to the next note / rest
    buzzStep = (buzzStep + 1) % steps;
    buzzStepStart = now;
    applyBuzzStep();
    return;
  }
  if (buzzNoteFreq != 0) {                     // shape the note in progress
    uint16_t v = (uint16_t)noteEnv(elapsed) * masterVolNow() / 255;
    soundSetVol((uint8_t)v);
  }
}

// ============================================================================
//  PHYSICAL BUTTON + BACKLIGHT / AUTO-DIM
// ============================================================================
bool     lastButton = HIGH;
uint32_t lastButtonMs = 0;

void serviceButton() {
#if ENABLE_SNOOZE_BUTTON
  bool cur = digitalRead(PIN_BUTTON);
  uint32_t now = millis();
  if (lastButton == HIGH && cur == LOW && (now - lastButtonMs) > 200UL) {
    lastButtonMs = now;
    if (ringLatched) {
      buttonOnRing();
    } else {
      backlightWakeUntilMs = now + BACKLIGHT_WAKE_MS; // wake the screen
    }
  }
  lastButton = cur;
#endif
}

// Decide whether the backlight should be on. Priority: any active buzzer or a
// recent button press forces it on; otherwise the app's sleep window (when
// autoDim is enabled) and/or ambient darkness turns it off.
void serviceBacklight() {
  bool wantOn = true;

  if (ringActive || timerDone) {
    wantOn = true;
  } else if ((int32_t)(millis() - backlightWakeUntilMs) < 0) {
    // Signed difference stays correct across the ~49.7-day millis() rollover,
    // unlike a bare `millis() < deadline` absolute comparison.
    wantOn = true;
  } else {
    bool inSleep = false;
    if (autoDimMode && haveTime) {
      LocalTime t = localNow();
      uint16_t nowMin  = (uint16_t)t.hh * 60 + t.mm;
      uint16_t startMin = (uint16_t)sleepStartHour * 60 + sleepStartMinute;
      uint16_t endMin   = (uint16_t)sleepEndHour * 60 + sleepEndMinute;
      if (startMin == endMin) {
        inSleep = false;
      } else if (startMin < endMin) {
        inSleep = (nowMin >= startMin && nowMin < endMin);
      } else { // window wraps past midnight
        inSleep = (nowMin >= startMin || nowMin < endMin);
      }
    }
    bool dark = false;
#if ENABLE_LDR
    dark = (analogRead(PIN_LDR) < LDR_DARK_THRESHOLD);
#endif
    if (inSleep || (autoDimMode && dark)) wantOn = false;
  }

  if (wantOn != backlightOn) {
    backlightOn = wantOn;
    if (wantOn) lcd.backlight();
    else        lcd.noBacklight();
  }
}

// ============================================================================
//  16x2 LCD USER INTERFACE
// ============================================================================
// CGRAM custom glyphs (from the spec): 1=BT connected, 2=BT disconnected,
// 3=alarm bell, 4=timer.
byte GLYPH_BT_ON[8]  = {0b01100,0b01010,0b01100,0b01010,0b01100,0b00000,0b00000,0b00000};
byte GLYPH_BT_OFF[8] = {0b10001,0b01010,0b00100,0b01010,0b10001,0b00000,0b00000,0b00000};
byte GLYPH_BELL[8]   = {0b00100,0b01110,0b01110,0b01110,0b11111,0b00000,0b00100,0b00000};
byte GLYPH_TIMER[8]  = {0b11111,0b01001,0b00100,0b01010,0b10001,0b11111,0b00000,0b00000};
#define CH_BT_ON  1
#define CH_BT_OFF 2
#define CH_BELL   3
#define CH_TIMER  4

char line0[17];
char line1[17];
char prev0[17];
char prev1[17];

const char *DOW_NAMES[7] = {"Sun","Mon","Tue","Wed","Thu","Fri","Sat"};

void lcdRegisterGlyphs() {
  lcd.createChar(CH_BT_ON,  GLYPH_BT_ON);
  lcd.createChar(CH_BT_OFF, GLYPH_BT_OFF);
  lcd.createChar(CH_BELL,   GLYPH_BELL);
  lcd.createChar(CH_TIMER,  GLYPH_TIMER);
}

bool linkUp() { return lastFrameMs != 0 && (millis() - lastFrameMs) < LINK_TIMEOUT_MS; }

void padLine(char *buf) {
  int n = strlen(buf);
  for (int i = n; i < 16; i++) buf[i] = ' ';
  buf[16] = '\0';
}

// Format a compact "time until" string (<= 6 chars): "6d23h", "23h59m", "59m".
void formatCountdown(uint32_t minutes, char *out) {
  if (minutes >= 1440UL) {
    uint16_t d = minutes / 1440UL;
    uint16_t h = (minutes % 1440UL) / 60UL;
    snprintf(out, 8, "%ud%uh", d, h);
  } else if (minutes >= 60UL) {
    uint16_t h = minutes / 60UL;
    uint16_t m = minutes % 60UL;
    snprintf(out, 8, "%uh%um", h, m);
  } else {
    snprintf(out, 8, "%um", (uint16_t)minutes);
  }
}

// Minutes until the next occurrence of alarm[slot] from "now" (local). Returns
// 0xFFFFFFFF if the alarm can never fire (inactive).
uint32_t minutesUntilAlarm(int slot, LocalTime now) {
  AlarmConfig &a = alarms[slot];
  if (!a.used || (a.dayMask & ACTIVE_BIT) == 0) return 0xFFFFFFFFUL;
  int target = (int)a.hour * 60 + a.minute;
  int cur    = (int)now.hh * 60 + now.mm;
  uint8_t dayBits = a.dayMask & DAY_BITS_MASK;

  if (dayBits == 0) { // one-time: today if still ahead, else tomorrow
    int diff = target - cur;
    if (diff <= 0) diff += 1440;
    return (uint32_t)diff;
  }
  for (int d = 0; d < 8; d++) {
    uint8_t day = (now.dow + d) % 7;
    if (dayBits & (1 << day)) {
      if (d == 0 && target <= cur) continue; // already passed today
      return (uint32_t)(d * 1440 + (target - cur));
    }
  }
  return 0xFFFFFFFFUL;
}

void buildClockLine0() {
  if (!haveTime) {
    strcpy(line0, "--:--:--  ---");
  } else {
    LocalTime t = localNow();
#if USE_24H_DISPLAY
    snprintf(line0, 17, "%02u:%02u:%02u %s",
             t.hh, t.mm, t.ss, DOW_NAMES[t.dow]);
#else
    uint8_t h12 = t.hh % 12; if (h12 == 0) h12 = 12;
    char ap = (t.hh < 12) ? 'A' : 'P';
    snprintf(line0, 17, "%2u:%02u:%02u%c %s",
             h12, t.mm, t.ss, ap, DOW_NAMES[t.dow]);
#endif
  }
  padLine(line0);
  // Bluetooth status glyph in the top-right corner.
  line0[15] = linkUp() ? (char)CH_BT_ON : (char)CH_BT_OFF;
}

void buildClockLine1() {
  if (timerActive) {                               // timer takes the info line
    uint32_t rem = (timerEndEpoch > currentEpoch) ? (timerEndEpoch - currentEpoch) : 0;
    uint16_t hh = rem / 3600; uint8_t mm = (rem % 3600) / 60; uint8_t ss = rem % 60;
    snprintf(line1, 17, "%c %02u:%02u:%02u", (char)CH_TIMER, hh, mm, ss);
    padLine(line1);
    return;
  }
  if (!haveTime) { strcpy(line1, "Open app to sync"); padLine(line1); return; }

  // Next upcoming alarm.
  LocalTime t = localNow();
  uint32_t best = 0xFFFFFFFFUL; int bestSlot = -1;
  for (int i = 0; i < MAX_ALARMS; i++) {
    uint32_t m = minutesUntilAlarm(i, t);
    if (m < best) { best = m; bestSlot = i; }
  }
  if (bestSlot < 0) { strcpy(line1, "No alarms set"); padLine(line1); return; }

  char cd[8]; formatCountdown(best, cd);
  snprintf(line1, 17, "%c %02u:%02u %s",
           (char)CH_BELL, alarms[bestSlot].hour, alarms[bestSlot].minute, cd);
  padLine(line1);
}

void renderLcd() {
  uint32_t nowMs = millis();

  if (ringActive) {
    // Flash the alert every 500ms (spec "ACTIVE ALARM STATE").
    bool on = ((nowMs / 500) % 2) == 0;
    if (on) snprintf(line0, 17, " !!! ALARM !!! ");
    else    strcpy(line0, "");
    padLine(line0);
#if USE_24H_DISPLAY
    snprintf(line1, 17, "    %02u:%02u", ringHour, ringMinute);
#else
    { uint8_t h12 = ringHour % 12; if (h12 == 0) h12 = 12;
      char ap = (ringHour < 12) ? 'A' : 'P';
      snprintf(line1, 17, "   %2u:%02u %cM", h12, ringMinute, ap); }
#endif
    padLine(line1);
  } else if (timerDone) {
    bool on = ((nowMs / 500) % 2) == 0;
    strcpy(line0, on ? " !! TIMER UP !! " : "");
    padLine(line0);
    strcpy(line1, "  Time's up!");
    padLine(line1);
  } else if (syncing) {
    strcpy(line0, "SYNCHRONIZING...");
    padLine(line0);
    strcpy(line1, "  Please wait");
    padLine(line1);
  } else if ((int32_t)(nowMs - syncBannerUntilMs) < 0) { // rollover-safe compare
    strcpy(line0, "   SYNC OK!");
    padLine(line0);
    buildClockLine1();
  } else {
    buildClockLine0();
    buildClockLine1();
  }

  // Only push changed characters to avoid flicker.
  if (strcmp(line0, prev0) != 0) {
    lcd.setCursor(0, 0); lcd.print(line0); strcpy(prev0, line0);
  }
  if (strcmp(line1, prev1) != 0) {
    lcd.setCursor(0, 1); lcd.print(line1); strcpy(prev1, line1);
  }
}

// ============================================================================
//  SETUP / LOOP
// ============================================================================

// Best-effort one-time HM-10 rename so the clock advertises as "WG Clock".
// Set to 0 if a particular module misbehaves during boot.
#define HM10_SET_NAME 1

#if HM10_SET_NAME
void configureBleName() {
  // Runs once at boot, BEFORE any central connects (AT only works while
  // unconnected), so the AT text goes to the module in command mode and never
  // over-air. We send both the genuine-HMSoft form (no '=', no terminator; the
  // command ends on an idle gap) and the CC41-A clone form ('=' + CRLF); the
  // wrong one for a given module simply returns an error. Responses are drained
  // so a late "OK+Set" can't corrupt the first protocol frame. Either way the
  // module keeps advertising service FFE0, so the app still finds it even if the
  // rename is ignored. "WG Clock" is 8 chars, within the HM-10 name limit.
  delay(200);                                 // let the module finish booting
  bleSerial.print(F("AT+NAMEWG Clock"));      // genuine HMSoft firmware
  delay(300);
  while (bleSerial.available()) bleSerial.read();
  bleSerial.print(F("AT+NAME=WG Clock\r\n")); // CC41-A / clones
  delay(300);
  while (bleSerial.available()) bleSerial.read();
}
#endif

// Power-on self-test: a short rising blip proving the speaker + Timer1 PWM path
// works at boot, independent of BLE/time sync. If you hear this but alarms are
// silent, the fault is upstream (the clock never got a time sync, so checkAlarms
// never fires); if you DON'T hear it, it's wiring or the PWM registers.
void bootSelfTestChime() {
  soundStart(1047, VOLUME_TIMER); delay(150); // C6
  soundStart(1319, VOLUME_TIMER); delay(150); // E6
  soundStart(1568, VOLUME_TIMER); delay(200); // G6
  soundOff();
}

void setup() {
  soundInit();          // configure D9 (OC1A) for PWM audio + build the decay curve
#if ENABLE_SNOOZE_BUTTON
  pinMode(PIN_BUTTON, INPUT_PULLUP);
#endif

  bleSerial.begin(9600); // HM-10 default UART baud
  bleSerial.listen();
#if HM10_SET_NAME
  configureBleName();    // advertise as "WG Clock" (best-effort, one-time)
#endif

  Wire.begin();
  lcd.init();
  lcd.backlight();
  lcdRegisterGlyphs();

  for (int i = 0; i < MAX_ALARMS; i++) lastFiredMinute[i] = 0xFFFFFFFFUL;
  eepromLoadAll();

  lastMicros = micros();

  // Splash.
  lcd.clear();
  lcd.setCursor(0, 0); lcd.print(F("   WakeGuard"));
  lcd.setCursor(0, 1); lcd.print(F("  clock ready"));
  prev0[0] = prev1[0] = '\1'; prev0[1] = prev1[1] = '\0'; // force first render

  bootSelfTestChime();  // audible proof the speaker + PWM path works at power-on
}

void loop() {
  pumpBle();        // 1. drain the HM-10 serial, decode + dispatch frames
  tickClock();      // 2. advance the software clock
  checkAlarms();    // 3. fire any alarm due this minute
  serviceRing();    // 4. maintain a ringing alarm (snooze resume, re-broadcast)
  serviceTimer();   // 5. maintain the countdown timer
  serviceBuzzer();  // 6. step the non-blocking tone pattern
  serviceButton();  // 7. read the physical button
  serviceBacklight();// 8. sleep-window / ambient / wake backlight control
  serviceSyncFlush();// 9. flush batched alarm writes if a sync's 0x05 was lost
  renderLcd();      // 10. refresh the display (diffed)
}
