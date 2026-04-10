// config.h - Archivo de Configuración (OPCIONAL para mantener secretos seguros)
// Copiar a src/config.h y completar con tus valores reales

#ifndef CONFIG_H
#define CONFIG_H

// ============================================================================
// CREDENCIALES DE RED
// ============================================================================
#define WIFI_SSID "TuSSIDaqui"
#define WIFI_PASSWORD "TuContraseñaaqui"

// ============================================================================
// CONFIGURACIÓN DE API
// ============================================================================
// Puedes usar IP local o dominio
#define API_SERVER "192.168.1.100"
// O: #define API_SERVER "torno.tudominio.com"

#define API_PORT 80  // Cambiar a 443 si HTTPS
#define API_PATH "/api/log-mecanizado"

// URL completa resultante: http://192.168.1.100/api/log-mecanizado
// Para HTTPS: https://torno.tudominio.com/api/log-mecanizado

// ============================================================================
// CONFIGURACIÓN DE BASE DE DATOS REMOTA (Información del servidor)
// ============================================================================
#define DB_SERVER "192.168.1.50\\SQLEXPRESS"
#define DB_USER "sa"
#define DB_PASSWORD "TuContraseña123"
#define DB_DATABASE "HoroMetroTorno"

// ============================================================================
// PARÁMETROS DE TIMEOUT Y REINTENTOS
// ============================================================================
#define MAX_WIFI_RETRIES 10           // Intentos de conexión WiFi al boot
#define MAX_API_RETRIES 10            // Intentos de envío a API por registro
#define API_TIMEOUT_MS 5000           // Timeout de conexión HTTP (5 seg)
#define WATCHDOG_TIMEOUT_S 10         // Timeout del Watchdog (10 seg)
#define SESSION_TIMEOUT_MS (5 * 60 * 60 * 1000)  // Timeout sesión (5 horas)

// ============================================================================
// CONFIGURACIÓN DE HARDWARE
// ============================================================================
// Pines GPIO
#define PIN_VFD_SIGNAL 35             // Entrada: Relé 2 del VFD
#define PIN_INTERLOCK_RELAY 33        // Salida: Control relé interlock
#define PIN_BTN_UP 32
#define PIN_BTN_DOWN 34
#define PIN_BTN_CONFIRM 36
#define PIN_BTN_BACK 39

// I2C
#define I2C_LCD_ADDRESS 0x27          // Dirección I2C del LCD
#define I2C_SDA 21
#define I2C_SCL 22

// ============================================================================
// CONFIGURACIÓN DE DEBOUNCE
// ============================================================================
#define DEBOUNCE_BUTTON_MS 50         // Debounce botones (50ms)
#define DEBOUNCE_VFD_MS 150           // Debounce señal VFD (150ms)

// ============================================================================
// ACTUALIZACIÓN DE PANTALLA
// ============================================================================
#define LCD_UPDATE_INTERVAL_MS 500    // Actualizar LCD cada 500ms

// ============================================================================
// DEBUG Y LOGGING
// ============================================================================
#define ENABLE_SERIAL_DEBUG 1         // 1 = Enabled, 0 = Disabled
#define SERIAL_BAUD_RATE 115200

// ============================================================================
// INFORMACIÓN DEL DISPOSITIVO
// ============================================================================
#define DEVICE_VERSION "1.0"
#define DEVICE_NAME "SmartHourMeter_Torno_01"
#define LOCATION "Taller Mecánico - Sector A"

#endif  // CONFIG_H

/* ============================================================================
 * CÓMO USAR ESTE ARCHIVO
 * ============================================================================
 * 
 * OPCIÓN 1: Usar este archivo en main.cpp
 * 
 *   #include "config.h"
 *   const char* SSID = WIFI_SSID;
 *   const char* PASSWORD = WIFI_PASSWORD;
 *   const char* API_ENDPOINT = "http://" API_SERVER API_PATH;
 * 
 * OPCIÓN 2: Mantener configuración hardcoded en main.cpp (actual)
 * 
 *   - Más simple pero menos seguro
 *   - No incluir credenciales en repositorio público
 * 
 * OPCIÓN 3: Usar SPIFFS para almacenar config.json
 * 
 *   - Permite cambiar WiFi sin recompilar
 *   - Requiere interfaz web para administración
 *   - Más complejo pero profesional
 * 
 * ============================================================================
 * NOTAS DE SEGURIDAD
 * ============================================================================
 * 
 * 1. NUNCA commiter credenciales al repositorio
 *    git add config.h
 *    echo "config.h" >> .gitignore
 * 
 * 2. Para equipos: Usar variables de entorno en CI/CD
 *    - PlatformIO soporta secretos en platformio.ini
 * 
 * 3. Cambiar contraseñas SQL Server por defecto
 * 
 * 4. Usar HTTPS en producción (API_PORT = 443)
 * 
 * ============================================================================
 */
