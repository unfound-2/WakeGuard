// ============================================================================
//  BUZZER TEST 3 of 3  —  RAW BIT-BANG  (last-resort proof)
//
//  Flash this ALONE. It hand-toggles D9 HIGH/LOW every 500 microseconds to make
//  a ~1 kHz square wave for 1s, then silence for 1s, forever. It uses ZERO
//  libraries and no hardware timers at all — just digitalWrite in a loop.
//
//  WHY THIS EXISTS
//    It's the simplest possible way to move the element. If Test 2 (tone) was
//    silent but this one makes sound, something is odd with the timer path; if
//    BOTH are silent, that's strong confirmation the fault is the hardware or
//    wiring, not any software.
//
//    * You hear a rough TONE  -> element + wiring work (passive piezo).
//    * You hear NOTHING (and Test 2 was also silent) -> hardware/wiring fault:
//      check that D9 truly goes to one lead and GND to the other, and reflow
//      both solder joints.
//
//  Wiring assumed: D9 -> buzzer -> GND (direct). Serial Monitor @ 9600.
// ============================================================================

#define BUZZER_PIN 9

void setup() {
  Serial.begin(9600);
  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);
  Serial.println();
  Serial.println(F("TEST 3: bit-bang ~1kHz on D9 (1s tone / 1s silence)"));
  Serial.println(F("Raw toggle, no libraries. Should buzz on a passive piezo."));
}

void loop() {
  Serial.println(F("BUZZ ~1000 Hz"));
  unsigned long start = millis();
  while (millis() - start < 1000UL) {
    digitalWrite(BUZZER_PIN, HIGH);
    delayMicroseconds(500);
    digitalWrite(BUZZER_PIN, LOW);
    delayMicroseconds(500);
  }

  Serial.println(F("silence"));
  digitalWrite(BUZZER_PIN, LOW);
  delay(1000);
}
