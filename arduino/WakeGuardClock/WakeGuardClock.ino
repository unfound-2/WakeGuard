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
 *    - 2.4"/2.8" ILI9341  240x320 SPI TFT on hardware SPI (backlight LED tied
 *                         straight to 3.3V, so it is ALWAYS ON; touch pins unused)
 *    - Passive speaker    (driven by Timer1 PWM on D9 — NOT an active buzzer)
 *    - (optional) momentary push button for snooze / backlight wake (now on D4)
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
 *    ILI9341 TFT — a 3.3V-logic panel, so every 5V Arduino OUTPUT feeding it goes
 *    through a resistor divider. MISO is an INPUT to the Arduino (no divider), and
 *    the backlight is tied directly to 3.3V (no GPIO control):
 *        Display VCC      -> 5V
 *        Display GND      -> GND
 *        Display LED      -> 3.3V                 (backlight, permanently on)
 *        Display SDO/MISO -> D12                  (direct, no divider)
 *        Display SCK      <- D13 --[divider]-->   (SPI clock)
 *        Display SDI/MOSI <- D11 --[divider]-->   (SPI data in)
 *        Display CS       <- D10 --[divider]-->   (chip select)
 *        Display DC/RS    <- D7  --[divider]-->   (data/command; moved off D9)
 *        Display RESET    <- D8  --[divider]-->   (reset)
 *        Display T_*      : touch pins intentionally left UNCONNECTED
 *      Divider = Arduino pin --[1k]--+--> display, with [2k] from that node to GND
 *      (a 5V HIGH becomes ~3.3V). Any ~1:2 ratio works (1k/2k, 2.2k/3.3k, ...).
 *    Speaker(+) -> D9,  Speaker(-) -> GND   (add a 100R series resistor to tame
 *                                            volume/current if desired)
 *    Button -> D4 to GND (internal pull-up; harmless/ignored if absent — moved off
 *                         D10 because the TFT now uses D10 for CS)
 *    LDR    -> A0 divider (only used if ENABLE_LDR is set)
 *
 *  ----------------------------------------------------------------------------
 *  LIBRARIES  (install these two via the Arduino IDE Library Manager)
 *  ----------------------------------------------------------------------------
 *    - "Adafruit GFX Library"
 *    - "Adafruit ILI9341"
 *  (Library Manager will offer to pull in "Adafruit BusIO" as a dependency — accept
 *  it.) SoftwareSerial, SPI and EEPROM ship with the Arduino AVR core. The panel is
 *  a 240x320 ILI9341 on hardware SPI; to swap in a different controller later,
 *  change the #include, the `tft` constructor, and (if needed) the init call.
 *
 *  ----------------------------------------------------------------------------
 *  ONE-TIME CONFIGURATION YOU SHOULD CHECK  (see the block just below)
 *  ----------------------------------------------------------------------------
 *    - TIMEZONE_OFFSET_SECONDS : the app sends UTC epoch; alarms are LOCAL time.
 *                                Set this to your UTC offset or the clock will
 *                                display/ring in UTC. (No BLE command carries a
 *                                timezone, so it must live here.)
 *    - USE_24H_DISPLAY         : 24-hour vs 12-hour clock face.
 *    - TFT_ROTATION            : 1 or 3 = landscape (320x240); flip to the other if
 *                                the panel reads upside down. 0/2 give portrait.
 * ============================================================================
 */

#include <SoftwareSerial.h>
#include <SPI.h>
#include <Adafruit_GFX.h>
#include <Adafruit_ILI9341.h>
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
#define TFT_ROTATION      1        // 1 or 3 = landscape 320x240; flip if upside down

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

// ---- Pin assignments (match the wiring table in the header) ----------------
#define PIN_HM10_TXD  2   // Arduino RX  (<- HM-10 TXD)
#define PIN_HM10_RXD  3   // Arduino TX  (-> HM-10 RXD, via divider)
#define PIN_BUZZER    9
#define PIN_BUTTON    4   // moved off D10: the TFT now uses D10 for CS
#define PIN_LDR       A0

// ---- ILI9341 TFT (hardware SPI: MOSI=D11, MISO=D12, SCK=D13) ----------------
#define TFT_CS   10
#define TFT_DC    7
#define TFT_RST   8

// ---- Buzzer type -----------------------------------------------------------
// 1 = ACTIVE buzzer (has a built-in oscillator: makes sound on steady DC, fixed
//     pitch, fixed loudness). Confirmed on this unit 2026-07-07 via the
//     BuzzerTest sketches — steady DC produced a tone, square waves produced
//     garble. In this mode the alarm/timer patterns play as on/off BEEP
//     rhythms, and per-alarm volume% and the gradual-wake fade are NO-OPs
//     because the hardware physically cannot vary its loudness.
// 0 = PASSIVE piezo/speaker (needs a driven frequency): the original mode that
//     supports the chime melodies, volume, and gradual-wake fade via Timer1 PWM.
// Same wiring either way (D9 -> buzzer -> GND); this only changes how D9 is driven.
#ifndef BUZZER_IS_ACTIVE
#define BUZZER_IS_ACTIVE 1
#endif

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
static const uint8_t CMD_TIMER_STOP  = 0x0B; // app -> clock: cancel/silence the countdown timer

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
static const uint8_t ACK_TIMER_STOP  = 0x8B; // clock -> app: timer cancelled / silenced
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
uint32_t syncStartMs    = 0;      // millis() at SYNC_START, to bound a stuck sync

// ---- Connection heuristic --------------------------------------------------
uint32_t lastFrameMs    = 0;      // millis() of the last valid frame from the app
static const uint32_t LINK_TIMEOUT_MS = 20000UL;
// A real sync batch (<=5 alarms + tokens + settings) completes in ~1-2s. If we've
// been "syncing" this long, the closing 0x05 was lost — force-end so the UI (which
// pauses rendering during a sync) can't hang. See serviceSyncFlush / renderTft.
static const uint32_t SYNC_MAX_MS = 8000UL;

// ---- Backlight -------------------------------------------------------------
bool     backlightOn    = true;
uint32_t backlightWakeUntilMs = 0;

// ============================================================================
//  DEVICE INSTANCES
// ----------------------------------------------------------------------------
//  The ILI9341 panel is driven by Adafruit_GFX + Adafruit_ILI9341 over hardware
//  SPI (MOSI=D11, MISO=D12, SCK=D13); only CS/DC/RST are passed to the ctor. The
//  old self-contained LcdI2C driver is gone — the display layer now lives in the
//  "ILI9341 TFT USER INTERFACE" section further down.
// ============================================================================
Adafruit_ILI9341 tft(TFT_CS, TFT_DC, TFT_RST);
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
void stopTimer();
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
// "syncing" — which now also freezes the display, since renderTft() skips drawing
// while syncing). Clear if the link goes idle past the timeout, OR if a sync has
// simply run too long (a real batch finishes in ~1-2s; SYNC_MAX_MS means 0x05 was lost).
void serviceSyncFlush() {
  if (!syncing && !alarmsDirty) return;
  bool linkIdle  = (lastFrameMs != 0 && (uint32_t)(millis() - lastFrameMs) >= LINK_TIMEOUT_MS);
  bool syncStuck = (syncing && syncStartMs != 0 && (uint32_t)(millis() - syncStartMs) >= SYNC_MAX_MS);
  if (linkIdle || syncStuck) {
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
      syncStartMs = millis();
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
    case CMD_TIMER_STOP: {                 // (no payload) cancel a running or finished timer
      stopTimer();
      sendAck(ACK_TIMER_STOP);
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

// Cancel a countdown from the app (0x0B): drops a still-running timer AND
// silences a finished-timer chime. A ringing alarm owns the speaker, so only
// turn the buzzer off if no alarm is currently sounding.
void stopTimer() {
  timerActive = false;
  timerDone   = false;
  // A ringing alarm owns the speaker; only silence if no alarm is sounding.
  // buzzerSetMode(BUZZ_OFF) is a no-op if the buzzer is already off, so this is
  // safe during a snooze gap too. (Mirrors serviceTimer's auto-silence.)
  if (!ringActive) buzzerSetMode(BUZZ_OFF);
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
#if BUZZER_IS_ACTIVE
  // Active buzzer: silence is simply the pin LOW. Timer1 is never engaged.
  digitalWrite(PIN_BUZZER, LOW);
#else
  TCCR1A = 0;               // release OC1A (pin returns to the port latch = LOW)
  TCCR1B = 0;               // stop Timer1's clock
  digitalWrite(PIN_BUZZER, LOW);
#endif
}

// Set the loudness of the note in progress. OCR1A is double-buffered (latched at
// TOP), so this is glitch-free to call every service tick to shape the envelope.
void soundSetVol(uint8_t vol) {
#if BUZZER_IS_ACTIVE
  // Active buzzer has fixed loudness — it can't be shaped. Deliberately a no-op
  // so the per-note decay envelope doesn't chop the beep off mid-note; on/off is
  // owned by soundStart()/soundOff() at note/rest boundaries.
  (void)vol;
#else
  uint16_t top = ICR1;
  if (top == 0) return;
  // Duty peaks near 50% (a square wave) at vol=255; lower duty = quieter.
  OCR1A = (uint16_t)(((uint32_t)top * vol) / 512UL);  // vol 0 => duty 0 => silent
#endif
}

// Begin a new note at frequency `hz`, loudness `vol` (0..255).
void soundStart(uint16_t hz, uint8_t vol) {
#if BUZZER_IS_ACTIVE
  // Active buzzer: pitch and loudness are fixed in hardware, so a "note" is just
  // the pin driven HIGH. applyBuzzStep() only calls this for real notes (rests
  // call soundOff()), so the alarm/timer patterns come out as beep rhythms.
  (void)hz;
  (void)vol;
  digitalWrite(PIN_BUZZER, HIGH);
#else
  if (hz < 123) { soundOff(); return; }    // below this, TOP overflows 16 bits
  ICR1 = (uint16_t)(F_CPU / (2UL * hz));    // phase-correct: f = F_CPU / (2*TOP)
  soundSetVol(vol);
  TCNT1 = 0;                                // clean phase start avoids a wrap click
  TCCR1A = _BV(COM1A1) | _BV(WGM11);        // non-inverting, phase-correct PWM,
  TCCR1B = _BV(WGM13) | _BV(CS10);          // TOP = ICR1, prescaler 1
#endif
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

// An ascending major arpeggio (G6-C7-E7) that steps down to resolve on C7 and
// rings out through the bell decay. Pitched an octave up from the "musical"
// register on purpose: a passive piezo's output peaks sharply around 2-4 kHz
// and is far quieter below ~1.5 kHz, so keeping the notes in the 1.5-2.6 kHz
// band is what makes the alarm actually loud on the hardware buzzer.
const ToneStep ALARM_PATTERN[] = {
  {1568, 260}, {0, 30},   // G6
  {2093, 260}, {0, 30},   // C7
  {2637, 300}, {0, 40},   // E7  (bright peak — near the piezo's resonance)
  {2349, 260}, {0, 30},   // D7
  {2093, 480},            // C7  (resolve — held, decays away)
  {   0, 620},            // breathe before the phrase repeats
};
// A short two-note "ding-dong" for finished timers, distinct from the alarm,
// kept in the same loud piezo band.
const ToneStep TIMER_PATTERN[] = {
  {2637, 200}, {0, 60},   // E7
  {2093, 340},            // C7
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

  // The backlight LED is hard-wired to 3.3V, so it can't be dimmed in hardware.
  // Instead the renderer blanks the panel to black while backlightOn is false
  // (renderTft's SCR_BLANK mode) — the visible equivalent of "backlight off".
  backlightOn = wantOn;
}

// ============================================================================
//  ILI9341 TFT USER INTERFACE  (240x320 panel driven in 320x240 landscape)
// ----------------------------------------------------------------------------
//  Replaces the old 16x2 LCD. Rendering keeps the LCD's "only draw what changed"
//  idea, but per text field: each field caches its last drawn string and repaints
//  only when it differs. setTextColor(fg,bg) fills every glyph cell's background,
//  so a fixed-width, space-padded field cleanly overwrites its predecessor with
//  no ghosting and no flicker. A full-screen fill happens ONLY on a mode change
//  (clock <-> ring <-> timer-up <-> syncing <-> blank), never per frame — this
//  keeps SPI traffic low so it can't starve the SoftwareSerial RX during a sync.
// ============================================================================
// Colours (RGB565). The ILI9341_* names come from the Adafruit header.
#define COL_BG       ILI9341_BLACK
#define COL_TITLE    ILI9341_CYAN
#define COL_TIME     ILI9341_WHITE
#define COL_DATE     0x9CD3            // soft blue-grey
#define COL_INFO     ILI9341_YELLOW
#define COL_LINK_ON  ILI9341_GREEN
#define COL_LINK_OFF 0x7BEF            // dim grey
#define COL_ALERT    ILI9341_RED
#define COL_ALERT_TX ILI9341_WHITE
#define COL_SYNC     ILI9341_CYAN

const char *DOW_FULL[7] = {"SUNDAY","MONDAY","TUESDAY","WEDNESDAY",
                           "THURSDAY","FRIDAY","SATURDAY"};

bool linkUp() { return lastFrameMs != 0 && (millis() - lastFrameMs) < LINK_TIMEOUT_MS; }

// ---- Field-diff rendering primitives ---------------------------------------
enum ScreenMode { SCR_NONE, SCR_BLANK, SCR_CLOCK, SCR_RING, SCR_TIMER_DONE };
ScreenMode scrMode = SCR_NONE;

// Per-field "last drawn" caches (sentinel first byte => force a repaint).
char pvTitle[28], pvLink[28], pvTime[28], pvDate[28], pvInfo[28];
char pvRingFlash[28], pvRingTime[28], pvRingHint[28];
char pvTdFlash[28], pvTd2[28];

// Invalidate every field cache so the next render of the active mode repaints in
// full (used right after a full-screen clear on a mode change).
void forceRedrawAll() {
  char *all[] = {pvTitle, pvLink, pvTime, pvDate, pvInfo, pvRingFlash, pvRingTime,
                 pvRingHint, pvTdFlash, pvTd2};
  for (uint8_t i = 0; i < sizeof(all) / sizeof(all[0]); i++) {
    all[i][0] = '\x01'; all[i][1] = '\0';
  }
}

// Copy `s` into `out`, padded with spaces to exactly `width` chars (out>=width+1).
// The trailing spaces are what erase a longer previous string with no ghosting.
void padTo(char *out, const char *s, uint8_t width) {
  uint8_t i = 0;
  for (; s[i] && i < width; i++) out[i] = s[i];
  for (; i < width; i++) out[i] = ' ';
  out[width] = '\0';
}

// Draw a text field only when its string changed since the last call.
void drawField(int16_t x, int16_t y, uint8_t size, uint16_t fg,
               const char *s, char *prev) {
  if (strcmp(s, prev) == 0) return;
  tft.setTextSize(size);
  tft.setTextColor(fg, COL_BG);
  tft.setCursor(x, y);
  tft.print(s);
  strcpy(prev, s);
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

// ---- Clock-face field builders ---------------------------------------------
void buildTimeStr(char *out) {                     // always 8 chars: "HH:MM:SS"
  if (!haveTime) { strcpy(out, "--:--:--"); return; }
  LocalTime t = localNow();
#if USE_24H_DISPLAY
  snprintf(out, 9, "%02u:%02u:%02u", t.hh, t.mm, t.ss);
#else
  uint8_t h12 = t.hh % 12; if (h12 == 0) h12 = 12;
  snprintf(out, 9, "%2u:%02u:%02u", h12, t.mm, t.ss);   // leading space keeps 8 chars
#endif
}

void buildDateStr(char *out) {
  if (!haveTime) { strcpy(out, "sync needed"); return; }
  LocalTime t = localNow();
#if USE_24H_DISPLAY
  snprintf(out, 15, "%s", DOW_FULL[t.dow]);
#else
  snprintf(out, 15, "%s %s", DOW_FULL[t.dow], (t.hh < 12) ? "AM" : "PM");
#endif
}

// Bottom status line: running countdown timer, else next alarm, else a hint or
// the brief "Synced!" banner after a sync completes.
void buildInfoStr(char *out) {
  if (timerActive) {
    uint32_t rem = (timerEndEpoch > currentEpoch) ? (timerEndEpoch - currentEpoch) : 0;
    uint16_t hh = rem / 3600; uint8_t mm = (rem % 3600) / 60; uint8_t ss = rem % 60;
    snprintf(out, 27, "Timer %02u:%02u:%02u", hh, mm, ss);
    return;
  }
  if (!haveTime) { strcpy(out, "Open the app to sync"); return; }
  if ((int32_t)(millis() - syncBannerUntilMs) < 0) { strcpy(out, "Synced!"); return; }

  LocalTime t = localNow();
  uint32_t best = 0xFFFFFFFFUL; int bestSlot = -1;
  for (int i = 0; i < MAX_ALARMS; i++) {
    uint32_t m = minutesUntilAlarm(i, t);
    if (m < best) { best = m; bestSlot = i; }
  }
  if (bestSlot < 0) { strcpy(out, "No alarms set"); return; }
  char cd[8]; formatCountdown(best, cd);
  snprintf(out, 27, "Next %02u:%02u in %s",
           alarms[bestSlot].hour, alarms[bestSlot].minute, cd);
}

// ---- Per-mode renderers (each only repaints fields that changed) -----------
void renderClock() {
  char buf[28], pad[28];

  drawField(8, 10, 2, COL_TITLE, "WakeGuard", pvTitle);          // static title

  padTo(pad, linkUp() ? "BLE ON" : "BLE --", 6);                 // link status
  drawField(224, 10, 2, linkUp() ? COL_LINK_ON : COL_LINK_OFF, pad, pvLink);

  buildTimeStr(buf);
  drawField(40, 92, 5, COL_TIME, buf, pvTime);                   // big HH:MM:SS

  buildDateStr(buf); padTo(pad, buf, 14);
  drawField(40, 152, 3, COL_DATE, pad, pvDate);                  // day + AM/PM

  buildInfoStr(buf); padTo(pad, buf, 26);
  drawField(8, 212, 2, COL_INFO, pad, pvInfo);                   // status line
}

void renderRing(uint32_t nowMs) {
  // Flashing headline; the "off" phase draws spaces which erase it (no clear).
  bool on = ((nowMs / 500) % 2) == 0;
  drawField(70, 44, 6, COL_ALERT, on ? "ALARM" : "     ", pvRingFlash);

  char ts[8];
#if USE_24H_DISPLAY
  snprintf(ts, 8, "%02u:%02u", ringHour, ringMinute);
#else
  { uint8_t h12 = ringHour % 12; if (h12 == 0) h12 = 12;
    snprintf(ts, 8, "%2u:%02u%s", h12, ringMinute, (ringHour < 12) ? "a" : "p"); }
#endif
  drawField(100, 118, 4, COL_ALERT_TX, ts, pvRingTime);

  char pad[28];
  padTo(pad, ringSecured ? "Dismiss in the app" : "Press button to stop", 22);
  drawField(20, 178, 2, COL_ALERT_TX, pad, pvRingHint);
}

void renderTimerDone(uint32_t nowMs) {
  bool on = ((nowMs / 500) % 2) == 0;
  drawField(70, 60, 6, COL_INFO, on ? "TIMER" : "     ", pvTdFlash);
  drawField(70, 128, 3, COL_ALERT_TX, "Time's up!", pvTd2);
}

// Top-level display refresh. Picks a screen mode with the same priority the LCD
// used, repaints the whole panel once on a mode change, then diff-updates that
// mode's text fields. Throttled so bursts of small redraws can't hog the SPI bus.
void renderTft() {
  static uint32_t lastRenderMs = 0;
  uint32_t nowMs = millis();
  if ((uint32_t)(nowMs - lastRenderMs) < 120UL) return;
  lastRenderMs = nowMs;

  // CRITICAL: do not touch the SPI bus while a sync batch is streaming. A blocking
  // panel write (a full-screen fillScreen is ~150ms) would stall loop() long enough
  // to overflow the 64-byte SoftwareSerial RX buffer and drop sync frames — e.g.
  // TIME_SYNC (clock would then show --:--:-- forever) or SYNC_END (UI would hang).
  // The screen holds its last frame for the ~1-2s the batch takes and repaints the
  // instant it ends; serviceSyncFlush() force-ends a stuck sync after SYNC_MAX_MS.
  if (syncing) return;

  ScreenMode want;
  if (ringActive)        want = SCR_RING;        // ring/timer force the panel on
  else if (timerDone)    want = SCR_TIMER_DONE;
  else if (!backlightOn) want = SCR_BLANK;       // auto-dim: blank to black
  else                   want = SCR_CLOCK;

  if (want != scrMode) {          // mode change: clear once, force a full repaint
    scrMode = want;
    tft.fillScreen(COL_BG);
    forceRedrawAll();
  }

  switch (scrMode) {
    case SCR_BLANK:      break;                    // nothing but black
    case SCR_CLOCK:      renderClock();            break;
    case SCR_RING:       renderRing(nowMs);        break;
    case SCR_TIMER_DONE: renderTimerDone(nowMs);   break;
    default:             break;
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

// Power-on self-test: a rising frequency SWEEP (0.5 -> 4.5 kHz) proving the
// speaker + Timer1 PWM path works at boot, independent of BLE/time sync. A
// sweep (rather than a fixed chime) is used deliberately: a passive piezo has a
// sharp resonant peak — usually somewhere in 2-4 kHz — and can be almost
// inaudible off it, so sweeping the whole band guarantees the peak is excited
// and you hear a chirp if the hardware works AT ALL.
//
// Diagnostic: if you hear this chirp but ALARMS stay silent, the fault is
// upstream — the clock never got a time sync, so checkAlarms() returns on
// !haveTime and never fires (fix the app-side connect/sync). If you DON'T hear
// the chirp, it is the audio hardware: check the buzzer wiring (D9 -> buzzer ->
// GND), that PIN_BUZZER matches the pin you soldered, and that it's a passive
// piezo/speaker (an ACTIVE buzzer ignores frequency and needs a steady DC pin).
void bootSelfTestChime() {
  // Two-phase test that makes ANY working buzzer on D9 audible, and tells the
  // buzzer TYPE apart:
  //   Phase 1 — steady DC (pin driven HIGH). An ACTIVE buzzer (built-in
  //     oscillator) beeps here; a passive piezo only clicks faintly.
  //   Phase 2 — PWM frequency sweep. A PASSIVE piezo/speaker sings across the
  //     sweep and crosses its loud resonance; an active buzzer stays quiet.
  // Diagnosis on next power-on:
  //   • beep in phase 1 but silent sweep  => ACTIVE buzzer (this firmware drives
  //     it as passive; it needs steady-DC alarm tones — tell the app dev).
  //   • hear the rising sweep             => PASSIVE buzzer OK; if alarms are
  //     still silent the fault is upstream (no time sync => checkAlarms returns).
  //   • silent in BOTH phases             => wiring/pin/dead hardware: confirm
  //     D9 -> buzzer -> GND, PIN_BUZZER matches the soldered pin, and (for a
  //     coil speaker) that a transistor driver is present — a pin can't drive 8Ω.

  // Phase 1: steady DC. soundInit() left the pin OUTPUT/LOW; Timer1 is idle so
  // plain digitalWrite owns the pin here.
  digitalWrite(PIN_BUZZER, HIGH);
  delay(300);
  digitalWrite(PIN_BUZZER, LOW);
  delay(150);

  // Phase 2: PWM sweep (soundStart takes over OC1A via Timer1).
  for (uint16_t hz = 500; hz <= 4500; hz += 250) {
    soundStart(hz, VOLUME_TIMER);
    delay(40);
  }
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

  tft.begin();
  tft.setRotation(TFT_ROTATION);   // landscape 320x240
  tft.fillScreen(COL_BG);

  for (int i = 0; i < MAX_ALARMS; i++) lastFiredMinute[i] = 0xFFFFFFFFUL;
  eepromLoadAll();

  lastMicros = micros();

  // Splash.
  tft.setTextSize(4);
  tft.setTextColor(COL_TITLE, COL_BG);
  tft.setCursor(43, 84);   tft.print(F("WakeGuard"));
  tft.setTextSize(2);
  tft.setTextColor(COL_DATE, COL_BG);
  tft.setCursor(94, 140);  tft.print(F("clock ready"));
  scrMode = SCR_NONE;      // make the first renderTft() lay out a fresh screen

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
  renderTft();      // 10. refresh the TFT (mode-aware, field-diffed)
}
