// ============================================================================
//  BUZZER TEST 2 of 3  —  Arduino tone()  (THE KEY TEST)
//
//  Flash this ALONE. It uses Arduino's OWN built-in tone() function to play a
//  2 kHz square wave on D9 for 1s, silence for 1s, forever. tone() uses Timer2
//  and is completely independent of the WakeGuard firmware's Timer1 code.
//
//  WHAT IT TELLS YOU  (this is the one that separates code vs hardware)
//    * You hear a clear TONE  -> the element + wiring are GOOD and it's a
//      PASSIVE piezo. That means the hardware is fine and any silence from the
//      real firmware is a FIRMWARE bug I will fix. Tell me "Test 2 sings".
//    * You hear NOTHING  -> combined with Test 1, the fault is hardware/wiring
//      (wrong pin, bad joint, dead element), NOT the firmware. Tell me
//      "Test 1 and 2 both silent".
//
//  Wiring assumed: D9 -> buzzer -> GND (direct). Serial Monitor @ 9600.
// ============================================================================

#define BUZZER_PIN 9

void setup() {
  Serial.begin(9600);
  pinMode(BUZZER_PIN, OUTPUT);
  Serial.println();
  Serial.println(F("TEST 2: tone() 2kHz on D9 (1s tone / 1s silence)"));
  Serial.println(F("Passive piezo should SING. Silence => suspect wiring/pin."));
}

void loop() {
  Serial.println(F("TONE 2000 Hz"));
  tone(BUZZER_PIN, 2000);
  delay(1000);

  Serial.println(F("silence"));
  noTone(BUZZER_PIN);
  digitalWrite(BUZZER_PIN, LOW);
  delay(1000);
}
