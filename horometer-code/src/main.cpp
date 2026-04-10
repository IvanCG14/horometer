#include <Arduino.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <LittleFS.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <esp_task_wdt.h>

// ============================================================================
// CONFIGURACIÓN DE PINES
// ============================================================================
#define PIN_VFD_SIGNAL 35      // INPUT_PULLUP - Señal "Run" del VFD
#define PIN_INTERLOCK_RELAY 33 // OUTPUT - Relé de interlock
#define PIN_BTN_UP 32          // INPUT_PULLUP - Botón Arriba
#define PIN_BTN_DOWN 34        // INPUT_PULLUP - Botón Abajo
#define PIN_BTN_CONFIRM 36     // INPUT_PULLUP - Botón Confirmar
#define PIN_BTN_BACK 39        // INPUT_PULLUP - Botón Atrás

// ============================================================================
// CONFIGURACIÓN DE RED Y API
// ============================================================================
const char *SSID = "YOUR_SSID";
const char *PASSWORD = "YOUR_PASSWORD";
const char *API_ENDPOINT = "http://192.168.1.100/api/log-mecanizado";
const char *WORK_CENTER = "TORNO 17"; // Centro de trabajo específico
const int MAX_RETRIES = 10;
const unsigned long TIMEOUT_SESSION = 5 * 60 * 60 * 1000; // 5 horas

// ============================================================================
// CONFIGURACIÓN LCD I2C
// ============================================================================
LiquidCrystal_I2C lcd(0x27, 20, 4);

// ============================================================================
// MÁQUINA DE ESTADOS - NUEVA LÓGICA (Asignación activa)
// ============================================================================
enum SystemState
{
  STATE_HOME,            // 0 - Inicio
  STATE_SHOW_ASSIGNMENT, // 1 - Mostrar asignación activa del servidor
  STATE_CONFIRM_START,   // 2 - Confirmar para iniciar sesión
  STATE_ENABLED,         // 3 - Habilitado (esperando Run del VFD)
  STATE_MONITORING,      // 4 - Monitoreo (midiendo tiempo)
  STATE_CLOSING          // 5 - Cierre
};

// ============================================================================
// ESTRUCTURA DE DATOS - ASIGNACIÓN INDUSTRIAL
// ============================================================================
struct AssignmentData
{
  String employeeId;        // Código del empleado
  String firstName;         // Nombre
  String lastName;          // Apellido
  String employeeShiftCode; // Código de turno
  String employeeShiftName; // Nombre del turno
  String opGroup;           // Grupo de operaciones
  String jobOperation;      // Operación específica
  String lastUpdated;       // Última actualización
  String status;            // Estado de la asignación
  float estRunHrs;          // Horas estimadas
  String jobCode;           // Código de trabajo
  String description;       // Descripción de operación
  String opGroupName;       // Nombre del grupo de operaciones
  String workCenter;        // Centro de trabajo
  int orderQuantity;        // Cantidad de orden
  String partNumber;        // Número de parte
  bool esGrupo;             // Es grupo (1) o no (0)
};

struct SystemData
{
  SystemState currentState = STATE_HOME;
  AssignmentData currentAssignment;

  unsigned long timeStart = 0;
  unsigned long timeElapsed = 0;
  bool vfdRunning = false;
  bool interlockClosed = false;
  unsigned long sessionStartTime = 0;

  // Array de asignaciones activas (puede haber múltiples empleados)
  JsonArray activeAssignments;
  int currentAssignmentIndex = 0;
} sysData;

// ============================================================================
// GESTIÓN DE BOTONES CON DEBOUNCE
// ============================================================================
struct ButtonState
{
  int pin;
  bool lastState;
  unsigned long lastDebounceTime;
  const unsigned long DEBOUNCE_DELAY = 50;

  ButtonState(int p) : pin(p), lastState(HIGH), lastDebounceTime(0) {}
};

ButtonState btnUp = {PIN_BTN_UP};
ButtonState btnDown = {PIN_BTN_DOWN};
ButtonState btnConfirm = {PIN_BTN_CONFIRM};
ButtonState btnBack = {PIN_BTN_BACK};

// ============================================================================
// PROTOTIPOS DE FUNCIONES
// ============================================================================
void setupWatchdog();
void setupPins();
void setupWiFi();
bool downloadAssignmentsFromServer();
bool readAssignmentsFromFS();
void saveAssignmentsToFS();
void saveSessionData();
void loadSessionData();
void updateLCD();
void handleState();
void transitionState(SystemState newState);
bool readButton(ButtonState &btn);
void handleMenuNavigation();
void setInterlock(bool state);
bool readVFDSignal();
bool sendDataToAPI(const JsonDocument &data);
void checkSessionTimeout();
void loadAssignmentData(int index);
void displayAssignmentDetails();

// ============================================================================
// SETUP
// ============================================================================
void setup()
{
  Serial.begin(115200);
  delay(1000);
  Serial.println("\n\n=== Smart Hour Meter - Industrial Assignment Mode ===\n");

  setupWatchdog();
  setupPins();

  if (!LittleFS.begin())
  {
    Serial.println("ERROR: LittleFS initialization failed!");
  }
  else
  {
    Serial.println("LittleFS initialized");
  }

  lcd.init();
  lcd.backlight();
  lcd.print("Cargando asignaciones...");

  if (!readAssignmentsFromFS())
  {
    Serial.println("No cache found locally");
  }

  setupWiFi();

  if (!downloadAssignmentsFromServer())
  {
    Serial.println("WARNING: Could not download assignments, using local cache");
  }

  loadSessionData();
  transitionState(STATE_HOME);

  Serial.println("Setup completed successfully!");
}

// ============================================================================
// LOOP PRINCIPAL
// ============================================================================
void loop()
{
  esp_task_wdt_reset();

  handleMenuNavigation();

  bool currentVFDState = readVFDSignal();
  if (currentVFDState != sysData.vfdRunning)
  {
    sysData.vfdRunning = currentVFDState;
    Serial.printf("VFD Signal changed: %d\n", sysData.vfdRunning);
  }

  handleState();
  checkSessionTimeout();
  updateLCD();

  delay(100);
}

// ============================================================================
// IMPLEMENTACIONES
// ============================================================================

void setupWatchdog()
{
  esp_task_wdt_init(10, true);
  esp_task_wdt_add(NULL);
  Serial.println("Watchdog Timer configured: 10 seconds");
}

void setupPins()
{
  pinMode(PIN_VFD_SIGNAL, INPUT_PULLUP);
  pinMode(PIN_INTERLOCK_RELAY, OUTPUT);
  pinMode(PIN_BTN_UP, INPUT_PULLUP);
  pinMode(PIN_BTN_DOWN, INPUT_PULLUP);
  pinMode(PIN_BTN_CONFIRM, INPUT_PULLUP);
  pinMode(PIN_BTN_BACK, INPUT_PULLUP);

  digitalWrite(PIN_INTERLOCK_RELAY, LOW);
  sysData.interlockClosed = false;

  Serial.println("GPIO pins configured");
}

void setupWiFi()
{
  Serial.println("Connecting to WiFi...");
  WiFi.begin(SSID, PASSWORD);

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < MAX_RETRIES)
  {
    delay(500);
    Serial.print(".");
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED)
  {
    Serial.println("\nWiFi connected!");
    Serial.printf("IP: %s\n", WiFi.localIP().toString().c_str());
  }
  else
  {
    Serial.println("\nWiFi connection failed!");
  }
}

bool downloadAssignmentsFromServer()
{
  if (WiFi.status() != WL_CONNECTED)
  {
    Serial.println("WiFi not connected, skipping download");
    return false;
  }

  HTTPClient http;
  http.setTimeout(5000);

  // API ahora devuelve asignaciones activas del centro de trabajo
  String assignmentURL = String(API_ENDPOINT) + "?action=getAssignments&workCenter=" + String(WORK_CENTER);

  Serial.printf("Downloading assignments from: %s\n", assignmentURL.c_str());

  http.begin(assignmentURL);
  int httpCode = http.GET();

  if (httpCode == 200)
  {
    String payload = http.getString();

    JsonDocument doc;
    DeserializationError error = deserializeJson(doc, payload);

    if (!error)
    {
      File f = LittleFS.open("/assignments.json", "w");
      if (f)
      {
        serializeJson(doc, f);
        f.close();
        Serial.println("Assignments downloaded and saved");
      }

      sysData.activeAssignments = doc["assignments"].as<JsonArray>();

      if (sysData.activeAssignments.size() > 0)
      {
        Serial.printf("Found %d active assignments\n", sysData.activeAssignments.size());
        loadAssignmentData(0);
      }

      http.end();
      return true;
    }
    else
    {
      Serial.printf("JSON parse error: %s\n", error.c_str());
    }
  }
  else
  {
    Serial.printf("HTTP error: %d\n", httpCode);
  }

  http.end();
  return false;
}

bool readAssignmentsFromFS()
{
  if (!LittleFS.exists("/assignments.json"))
  {
    return false;
  }

  File f = LittleFS.open("/assignments.json", "r");
  if (!f)
    return false;

  JsonDocument doc;
  DeserializationError error = deserializeJson(doc, f);
  f.close();

  if (error)
  {
    Serial.printf("Error reading assignments: %s\n", error.c_str());
    return false;
  }

  sysData.activeAssignments = doc["assignments"].as<JsonArray>();

  if (sysData.activeAssignments.size() > 0)
  {
    Serial.println("Assignments loaded from LittleFS");
    loadAssignmentData(0);
    return true;
  }

  return false;
}

void saveAssignmentsToFS()
{
  JsonDocument doc;
  doc["assignments"] = sysData.activeAssignments;
  doc["lastUpdated"] = millis();

  File f = LittleFS.open("/assignments.json", "w");
  if (f)
  {
    serializeJson(doc, f);
    f.close();
    Serial.println("Assignments saved to LittleFS");
  }
}

void saveSessionData()
{
  JsonDocument doc;
  doc["employeeId"] = sysData.currentAssignment.employeeId;
  doc["jobOperation"] = sysData.currentAssignment.jobOperation;
  doc["opGroup"] = sysData.currentAssignment.opGroup;
  doc["jobCode"] = sysData.currentAssignment.jobCode;
  doc["timeElapsed"] = sysData.timeElapsed;
  doc["timestamp"] = millis();

  File f = LittleFS.open("/session.json", "w");
  if (f)
  {
    serializeJson(doc, f);
    f.close();
    Serial.println("Session data saved");
  }
}

void loadSessionData()
{
  if (!LittleFS.exists("/session.json"))
  {
    return;
  }

  File f = LittleFS.open("/session.json", "r");
  if (!f)
    return;

  JsonDocument doc;
  DeserializationError error = deserializeJson(doc, f);
  f.close();

  if (!error)
  {
    sysData.currentAssignment.employeeId = doc["employeeId"].as<String>();
    sysData.currentAssignment.jobOperation = doc["jobOperation"].as<String>();
    sysData.currentAssignment.opGroup = doc["opGroup"].as<String>();
    sysData.currentAssignment.jobCode = doc["jobCode"].as<String>();
    sysData.timeElapsed = doc["timeElapsed"].as<unsigned long>();

    Serial.println("Session recovered from LittleFS");
  }
}

bool readButton(ButtonState &btn)
{
  int reading = digitalRead(btn.pin);

  if (reading != btn.lastState)
  {
    btn.lastDebounceTime = millis();
  }

  if ((millis() - btn.lastDebounceTime) > btn.DEBOUNCE_DELAY)
  {
    if (reading != btn.lastState)
    {
      btn.lastState = reading;
      return (reading == LOW);
    }
  }

  return false;
}

bool readVFDSignal()
{
  static unsigned long lastDebounceTime = 0;
  static bool lastValidState = false;
  static int readCount = 0;
  static bool currentReading = false;

  bool pinState = digitalRead(PIN_VFD_SIGNAL) == LOW;

  if (pinState != currentReading)
  {
    currentReading = pinState;
    lastDebounceTime = millis();
    readCount = 0;
  }

  if ((millis() - lastDebounceTime) >= 150)
  {
    if (currentReading == lastValidState)
    {
      readCount = 0;
    }
    else if (++readCount >= 2)
    {
      lastValidState = currentReading;
      return lastValidState;
    }
  }

  return lastValidState;
}

void setInterlock(bool state)
{
  if (state)
  {
    digitalWrite(PIN_INTERLOCK_RELAY, HIGH);
    sysData.interlockClosed = true;
    Serial.println("Interlock CLOSED - Machine ENABLED");
  }
  else
  {
    digitalWrite(PIN_INTERLOCK_RELAY, LOW);
    sysData.interlockClosed = false;
    Serial.println("Interlock OPEN - Machine DISABLED");
  }
}

void loadAssignmentData(int index)
{
  if (index < 0 || index >= sysData.activeAssignments.size())
  {
    Serial.println("Invalid assignment index");
    return;
  }

  JsonObject assignment = sysData.activeAssignments[index].as<JsonObject>();

  sysData.currentAssignment.employeeId = assignment["Employee"].as<String>();
  sysData.currentAssignment.firstName = assignment["First_Name"].as<String>();
  sysData.currentAssignment.lastName = assignment["Last_Name"].as<String>();
  sysData.currentAssignment.employeeShiftCode = assignment["employee_shift_code"].as<String>();
  sysData.currentAssignment.employeeShiftName = assignment["employee_shift_name"].as<String>();
  sysData.currentAssignment.opGroup = assignment["Op_Group"].as<String>();
  sysData.currentAssignment.jobOperation = assignment["Job_Operation"].as<String>();
  sysData.currentAssignment.lastUpdated = assignment["Last_Updated"].as<String>();
  sysData.currentAssignment.status = assignment["Status"].as<String>();
  sysData.currentAssignment.estRunHrs = assignment["Est_Run_Hrs"].as<float>();
  sysData.currentAssignment.jobCode = assignment["Job"].as<String>();
  sysData.currentAssignment.description = assignment["Description"].as<String>();
  sysData.currentAssignment.opGroupName = assignment["OpGroupName"].as<String>();
  sysData.currentAssignment.workCenter = assignment["Work_Center"].as<String>();
  sysData.currentAssignment.orderQuantity = assignment["Order_Quantity"].as<int>();
  sysData.currentAssignment.partNumber = assignment["Part_Number"].as<String>();
  sysData.currentAssignment.esGrupo = assignment["es_grupo"].as<bool>();

  sysData.currentAssignmentIndex = index;

  Serial.printf("Loaded assignment: %s (%s %s) - Op: %s\n",
                sysData.currentAssignment.employeeId.c_str(),
                sysData.currentAssignment.firstName.c_str(),
                sysData.currentAssignment.lastName.c_str(),
                sysData.currentAssignment.jobOperation.c_str());
}

void handleMenuNavigation()
{
  if (sysData.currentState == STATE_HOME)
  {
    if (readButton(btnConfirm))
    {
      if (sysData.activeAssignments.size() > 0)
      {
        transitionState(STATE_SHOW_ASSIGNMENT);
      }
      else
      {
        Serial.println("No active assignments available");
        lcd.clear();
        lcd.print("No hay asignaciones");
      }
    }
    return;
  }

  if (sysData.currentState == STATE_SHOW_ASSIGNMENT)
  {
    // Navegar entre asignaciones disponibles
    if (readButton(btnUp))
    {
      int newIndex = sysData.currentAssignmentIndex - 1;
      if (newIndex < 0)
        newIndex = sysData.activeAssignments.size() - 1;
      loadAssignmentData(newIndex);
    }

    if (readButton(btnDown))
    {
      int newIndex = sysData.currentAssignmentIndex + 1;
      if (newIndex >= sysData.activeAssignments.size())
        newIndex = 0;
      loadAssignmentData(newIndex);
    }

    if (readButton(btnConfirm))
    {
      transitionState(STATE_CONFIRM_START);
    }

    if (readButton(btnBack))
    {
      transitionState(STATE_HOME);
    }
  }

  if (sysData.currentState == STATE_CONFIRM_START)
  {
    if (readButton(btnConfirm))
    {
      transitionState(STATE_ENABLED);
    }

    if (readButton(btnBack))
    {
      transitionState(STATE_SHOW_ASSIGNMENT);
    }
  }

  if (sysData.currentState == STATE_MONITORING)
  {
    if (readButton(btnConfirm))
    {
      transitionState(STATE_CLOSING);
    }
  }
}

void transitionState(SystemState newState)
{
  Serial.printf("State transition: %d -> %d\n", sysData.currentState, newState);
  sysData.currentState = newState;

  switch (newState)
  {
  case STATE_HOME:
    setInterlock(false);
    sysData.timeElapsed = 0;
    sysData.timeStart = 0;
    break;

  case STATE_SHOW_ASSIGNMENT:
    Serial.println("Displaying active assignment");
    break;

  case STATE_CONFIRM_START:
    Serial.println("Waiting for start confirmation");
    break;

  case STATE_ENABLED:
    setInterlock(true);
    sysData.sessionStartTime = millis();
    Serial.printf("Session enabled for employee: %s\n", sysData.currentAssignment.employeeId.c_str());
    break;

  case STATE_MONITORING:
    sysData.timeStart = millis();
    Serial.println("Monitoring time - VFD is running");
    break;

  case STATE_CLOSING:
  {
    setInterlock(false);
    sysData.timeElapsed += (millis() - sysData.timeStart);
    saveSessionData();

    // Enviar datos con estructura ERP
    JsonDocument reportData;
    reportData["Employee"] = sysData.currentAssignment.employeeId;
    reportData["Job"] = sysData.currentAssignment.jobCode;
    reportData["Job_Operation"] = sysData.currentAssignment.jobOperation;
    reportData["Op_Group"] = sysData.currentAssignment.opGroup;
    reportData["Work_Center"] = sysData.currentAssignment.workCenter;
    reportData["Part_Number"] = sysData.currentAssignment.partNumber;
    reportData["Actual_Run_Hrs"] = sysData.timeElapsed / 3600000.0; // Convertir ms a horas
    reportData["Status"] = "Completed";
    reportData["Timestamp"] = (long)(millis() / 1000);

    if (sendDataToAPI(reportData))
    {
      LittleFS.remove("/session.json");
    }

    transitionState(STATE_HOME);
  }
  break;

  default:
    break;
  }
}

void handleState()
{
  switch (sysData.currentState)
  {
  case STATE_ENABLED:
    if (sysData.vfdRunning)
    {
      transitionState(STATE_MONITORING);
    }
    break;

  case STATE_MONITORING:
    // Mantener monitoreo mientras VFD corre
    break;

  default:
    break;
  }
}

void checkSessionTimeout()
{
  if (sysData.currentState == STATE_ENABLED || sysData.currentState == STATE_MONITORING)
  {
    unsigned long elapsedTime = millis() - sysData.sessionStartTime;
    if (elapsedTime > TIMEOUT_SESSION)
    {
      Serial.println("Session timeout! Returning to HOME");
      transitionState(STATE_HOME);
    }
  }
}

void displayAssignmentDetails()
{
  // Mostrar detalles de la asignación actual
  String empDisplay = sysData.currentAssignment.firstName.substring(0, 10);
  empDisplay += " ";
  empDisplay += sysData.currentAssignment.lastName.substring(0, 9);

  String jobDisplay = sysData.currentAssignment.jobCode + " - " +
                      sysData.currentAssignment.description.substring(0, 8);
}

void updateLCD()
{
  static unsigned long lastUpdate = 0;
  if (millis() - lastUpdate < 500)
    return;
  lastUpdate = millis();

  lcd.clear();

  switch (sysData.currentState)
  {
  case STATE_HOME:
    lcd.setCursor(0, 0);
    lcd.print("===== INICIO =====");
    lcd.setCursor(0, 1);
    lcd.print("Centro: " + String(WORK_CENTER));
    lcd.setCursor(0, 2);
    if (sysData.activeAssignments.size() > 0)
    {
      lcd.print("Asignaciones: ");
      lcd.print(sysData.activeAssignments.size());
    }
    else
    {
      lcd.print("Sin asignaciones");
    }
    lcd.setCursor(0, 3);
    lcd.print("OK=Continuar");
    break;

  case STATE_SHOW_ASSIGNMENT:
    lcd.setCursor(0, 0);
    lcd.print("ASIGNACION");
    lcd.setCursor(0, 1);
    lcd.print("Empl: " + sysData.currentAssignment.employeeId);
    lcd.setCursor(0, 2);
    lcd.print("Op: " + sysData.currentAssignment.jobCode.substring(0, 12));
    lcd.setCursor(0, 3);
    lcd.print("OK=Confirm  ESC=Back");
    break;

  case STATE_CONFIRM_START:
    lcd.setCursor(0, 0);
    lcd.print("CONFIRMAR INICIO");
    lcd.setCursor(0, 1);
    lcd.print(sysData.currentAssignment.firstName + " " +
              sysData.currentAssignment.lastName.substring(0, 8));
    lcd.setCursor(0, 2);
    lcd.print("Pieza: " + sysData.currentAssignment.partNumber);
    lcd.setCursor(0, 3);
    lcd.print("OK=Iniciar");
    break;

  case STATE_ENABLED:
    lcd.setCursor(0, 0);
    lcd.print("HABILITADO");
    lcd.setCursor(0, 1);
    lcd.print("Empl: " + sysData.currentAssignment.employeeId);
    lcd.setCursor(0, 2);
    lcd.print("Esperando VFD...");
    break;

  case STATE_MONITORING:
  {
    unsigned long displayTime = sysData.timeElapsed + (millis() - sysData.timeStart);
    unsigned long seconds = displayTime / 1000;
    unsigned long minutes = seconds / 60;
    unsigned long hours = minutes / 60;

    lcd.setCursor(0, 0);
    lcd.print("MIDIENDO");
    lcd.setCursor(0, 1);
    lcd.printf("Tiempo: %02lu:%02lu:%02lu", hours, minutes % 60, seconds % 60);
    lcd.setCursor(0, 2);
    lcd.print("Op: " + sysData.currentAssignment.jobOperation.substring(0, 14));
    lcd.setCursor(0, 3);
    lcd.print("OK=Finalizar");
    break;
  }
  }
}

bool sendDataToAPI(const JsonDocument &data)
{
  if (WiFi.status() != WL_CONNECTED)
  {
    Serial.println("WiFi not connected, data queued for retry");
    return false;
  }

  HTTPClient http;
  http.setTimeout(5000);
  http.begin(API_ENDPOINT);
  http.addHeader("Content-Type", "application/json");

  String jsonString;
  serializeJson(data, jsonString);

  Serial.printf("Sending to API: %s\n", jsonString.c_str());

  int httpCode = http.POST(jsonString);
  bool success = (httpCode == 200 || httpCode == 201);

  if (success)
  {
    Serial.println("API response: OK");
  }
  else
  {
    Serial.printf("API error: %d\n", httpCode);
  }

  http.end();
  return success;
}