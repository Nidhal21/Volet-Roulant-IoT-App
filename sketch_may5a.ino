#include <WiFi.h>
#include <Firebase_ESP_Client.h>

// WiFi credentials
const char* ssid = "OPPO";
const char* password = "00000000";

// Firebase credentials
#define FIREBASE_HOST "https://voletroulantcontrol-default-rtdb.firebaseio.com/ "
#define FIREBASE_AUTH "nFmXQuVkFk9bGcDRrNwrCcuWLLUf4NIKCgk7esFw"

// Pins
const int greenLedPin = 26;     // Window open indicator (Green LED)
const int redLedPin = 32;       // Window closed indicator (Red LED)
const int gasSensorPin = 34;    // Digital input for gas sensor (HIGH normal, LOW detected)
const int rainSensorPin = 15;   // Digital input for rain sensor (HIGH normal, LOW detected)

// Firebase objects
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

// State variables
bool windowOpen = false;
bool manualControlActive = false;
bool gasDetected = false;
bool rainDetected = false;
unsigned long lastCheckTime = 0;
const long checkInterval = 10000; // Sensor check interval (10 seconds)

void setup() {
  Serial.begin(115200);

  pinMode(greenLedPin, OUTPUT);
  pinMode(redLedPin, OUTPUT);
  pinMode(gasSensorPin, INPUT_PULLUP);
  pinMode(rainSensorPin, INPUT_PULLUP);

  digitalWrite(greenLedPin, LOW);
  digitalWrite(redLedPin, HIGH); // Start with window closed

  connectToWiFi();
  connectToFirebase();

  // Set initial state in Firebase
  Firebase.RTDB.setBool(&fbdo, "/window/state", windowOpen);
}

void connectToWiFi() {
  Serial.println("Connecting to WiFi...");
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(1000);
    Serial.print(".");
  }
  Serial.println("\nConnected to WiFi");
  Serial.print("IP Address: ");
  Serial.println(WiFi.localIP());
}

void connectToFirebase() {
  config.database_url = FIREBASE_HOST;
  config.signer.tokens.legacy_token = FIREBASE_AUTH;
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);
  Serial.println("Firebase initialized");
}

void loop() {
  if (!Firebase.ready()) {
    Serial.println("Firebase not ready. Reconnecting...");
    connectToFirebase();
    delay(1000);
    return;
  }

  // Actively fetch latest window state
  if (Firebase.RTDB.getBool(&fbdo, "/window/state")) {
    bool newState = fbdo.boolData();
    if (newState != windowOpen) {
      windowOpen = newState;
      if (windowOpen) {
        openWindow(true); // Manual control assumed
      } else {
        closeWindow(true);
      }
    }
  } else {
    Serial.println("Failed to read /window/state");
    Serial.println(fbdo.errorReason());
  }

  // Check sensors periodically
  if (millis() - lastCheckTime >= checkInterval) {
    lastCheckTime = millis();

    gasDetected = (digitalRead(gasSensorPin) == LOW);
    rainDetected = (digitalRead(rainSensorPin) == LOW);

    Serial.print("Gas Sensor State: "); Serial.println(gasDetected ? "Detected" : "Normal");
    Serial.print("Rain Sensor State: "); Serial.println(rainDetected ? "Detected" : "Normal");

    // Update Firebase if values changed
    static bool lastGas = false, lastRain = false;
    if (gasDetected != lastGas) {
      Firebase.RTDB.setString(&fbdo, "/sensor/gas", gasDetected ? "1" : "0");
      lastGas = gasDetected;
    }
    if (rainDetected != lastRain) {
      Firebase.RTDB.setString(&fbdo, "/sensor/rain", rainDetected ? "1" : "0");
      lastRain = rainDetected;
    }

    // Automatic control based on sensors
    if (rainDetected && !manualControlActive) {
      closeWindow(false);
    } else if (gasDetected && !windowOpen && !manualControlActive) {
      openWindow(false);
    }
  }
}

void openWindow(bool isManual) {
  digitalWrite(greenLedPin, HIGH);
  digitalWrite(redLedPin, LOW);
  windowOpen = true;
  Firebase.RTDB.setBool(&fbdo, "/window/state", true);
  if (isManual) manualControlActive = true;
  Serial.println("[ACTION] Window opened manually: " + String(isManual));
}

void closeWindow(bool isManual) {
  digitalWrite(greenLedPin, LOW);
  digitalWrite(redLedPin, HIGH);
  windowOpen = false;
  Firebase.RTDB.setBool(&fbdo, "/window/state", false);
  if (isManual) manualControlActive = false;
  Serial.println("[ACTION] Window closed manually: " + String(isManual));
}