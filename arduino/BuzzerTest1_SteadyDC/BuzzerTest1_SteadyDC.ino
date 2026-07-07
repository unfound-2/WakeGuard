// ============================================================================
//  BUZZER TEST 1 of 3  —  STEADY DC
//
//  Flash this ALONE (not with the main firmware). It just turns pin D9 fully
//  ON for 1 second, OFF for 1 second, forever. No libraries, no PWM.
//
//  WHAT IT TELLS YOU
//    * You hear a steady BEEP that lasts the whole 1s ON  -> you have an
//      ACTIVE buzzer (it has its own oscillator). The WakeGuard firmware is
//      built for a PASSIVE piezo, so it would need a change to drive this.
//      Tell me "Test 1 beeps" and I'll add an active-buzzer mode.
//    * You hear ONE faint CLICK at each ON and OFF, then silence -> that's a
//      PASSIVE piezo (normal). Move on to Test 2.
//    * You hear NOTHING at all (not even a click) -> the pin isn't reaching
//      the element: wrong pin, a broken/ cold solder joint, or a dead part.
//
//  Wiring assumed: D9 -> buzzer -> GND (direct). Serial Monitor @ 9600.
// ============================================================================

#define BUZZER_PIN 9

void setup() {
  Serial.begin(9600);
  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);
  Serial.println();
  Serial.println(F("TEST 1: STEADY DC on D9 (1s ON / 1s OFF)"));
  Serial.println(F("Active buzzer = steady beep. Passive piezo = one click."));
}

void loop() {
  Serial.println(F("ON"));
  digitalWrite(BUZZER_PIN, HIGH);
  delay(1000);

  Serial.println(F("OFF"));
  digitalWrite(BUZZER_PIN, LOW);
  delay(1000);
}
