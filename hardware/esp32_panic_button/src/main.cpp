/*
 * Aanchal Panic Button - ESP32 BLE Firmware
 * ==========================================
 * Press the button -> BLE notification "SOS" -> Flutter app
 * triggers full SOS chain (SMS + Firestore + TTS alert)
 *
 * Wiring:
 *   GPIO 13 -> Tactile button -> GND   (uses INPUT_PULLUP)
 *   GPIO 2  -> Built-in LED           (status indicator)
 *
 * LED behaviour:
 *   Slow blink (1s)  = scanning / not connected
 *   Solid ON         = phone connected
 *   Fast blink (3x)  = SOS sent successfully
 *   Rapid blink      = button pressed but not connected
 */

#include <NimBLEDevice.h>

// -- UUIDs - must match Flutter BleService exactly --
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define DEVICE_NAME         "Aanchal"
// ---------------------------------------------------

#define BUTTON_PIN    13
#define LED_PIN       2
#define DEBOUNCE_MS   5000

NimBLECharacteristic* pCharacteristic = nullptr;
bool                  connected       = false;
bool                  oldButtonState  = HIGH;
unsigned long         lastTrigger     = 0;
unsigned long         lastBlink       = 0;
bool                  ledState        = false;

// -- BLE server callbacks ----------------------------
class ServerCB : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* s) override {
    connected = true;
    digitalWrite(LED_PIN, HIGH);
    Serial.println("[BLE] Phone connected");
  }
  void onDisconnect(NimBLEServer* s) override {
    connected = false;
    digitalWrite(LED_PIN, LOW);
    Serial.println("[BLE] Disconnected - restarting advert");
    NimBLEDevice::startAdvertising();
  }
};

void setup() {
  Serial.begin(115200);
  pinMode(BUTTON_PIN, INPUT_PULLUP);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  // Init BLE
  NimBLEDevice::init(DEVICE_NAME);
  NimBLEDevice::setPower(ESP_PWR_LVL_P9); // max range

  NimBLEServer* pServer =
      NimBLEDevice::createServer();
  pServer->setCallbacks(new ServerCB());

  NimBLEService* pService =
      pServer->createService(SERVICE_UUID);

  pCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID,
      NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
  );
  pCharacteristic->setValue("ready");
  pService->start();

  NimBLEAdvertising* pAdvert =
      NimBLEDevice::getAdvertising();
  pAdvert->addServiceUUID(SERVICE_UUID);
  pAdvert->start();

  Serial.println("[ESP32] Aanchal button ready");
  Serial.println("[ESP32] Waiting for phone...");
}

void blinkLed(int times, int ms) {
  for (int i = 0; i < times; i++) {
    digitalWrite(LED_PIN, HIGH);
    delay(ms);
    digitalWrite(LED_PIN, LOW);
    delay(ms);
  }
  if (connected) digitalWrite(LED_PIN, HIGH);
}

void loop() {
  unsigned long now = millis();

  // Slow blink when not connected
  if (!connected && (now - lastBlink > 1000)) {
    lastBlink = now;
    ledState = !ledState;
    digitalWrite(LED_PIN, ledState);
  }

  // Read button
  bool btnState = digitalRead(BUTTON_PIN);
  if (btnState == LOW
      && oldButtonState == HIGH
      && (now - lastTrigger) > DEBOUNCE_MS) {

    lastTrigger = now;
    Serial.println("[ESP32] Button pressed");

    if (connected && pCharacteristic != nullptr) {
      pCharacteristic->setValue("SOS");
      pCharacteristic->notify();
      Serial.println("[ESP32] SOS sent via BLE");
      blinkLed(3, 100); // 3 fast blinks = success
    } else {
      Serial.println("[ESP32] Not connected - SOS lost!");
      blinkLed(10, 50); // rapid blinks = failure
    }
  }
  oldButtonState = btnState;
  delay(20);
}
