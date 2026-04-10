# 🍓 SMART HOUR METER v3 - RASPBERRY PI ZERO

## Migración de ESP32 a Raspberry Pi Zero con Lógica de Grupos

**Fecha**: 2026-04-09  
**Versión**: 3.0  
**Hardware**: Raspberry Pi Zero (ARM, Linux)  
**Lenguaje**: Python 3.9+  
**BD**: SQL Server (conexión directa)

---

## 📋 RESUMEN DE CAMBIOS v2 → v3

| Aspecto | v2 (ESP32) | v3 (Raspberry Pi) |
|---------|-----------|------------------|
| **Hardware** | ESP32 (C++/Arduino) | Raspberry Pi Zero (Python) |
| **Conectividad** | API intermedia (PHP) | SQL Server directo |
| **Menú Tareas** | Individual | **Agrupadas por Op_Group** |
| **Meta** | Cantidad única | **Suma de grupo** |
| **Reporte** | Automático | **Pregunta cantidad** |
| **LCD** | LCD20x4 I2C | LCD20x4 I2C |
| **GPIO** | 3 botones | **3 botones** |
| **VFD** | Debounce 150ms | **Debounce 150ms** |
| **Base Datos** | Tablas simples | Tablas ERP |

---

## 🔧 REQUISITOS HARDWARE

### Raspberry Pi Zero
- ✓ Pi Zero W (con WiFi integrado) **RECOMENDADO**
- ✓ O Pi Zero 2 W (más rápido)
- ✓ Tarjeta microSD 16GB+
- ✓ Fuente 5V 2A

### Periféricos
- ✓ LCD 20x4 con módulo I2C (dirección 0x27)
- ✓ 3 botones momentáneos (GPIO 27, 22, 23)
- ✓ Pin GPIO 17 para señal VFD
- ✓ Cable VFD (LOW = motor corriendo)

### Red
- ✓ WiFi o Ethernet (para SQL Server)
- ✓ Acceso a SQL Server en red local

---

## 📥 INSTALACIÓN (Paso a Paso)

### PASO 1: Preparar Raspberry Pi

```bash
# 1.1 Usar Raspberry Pi Imager (recomendado)
# Descargar desde: https://www.raspberrypi.com/software/
# Grabar Raspberry Pi OS (Lite o Desktop)

# 1.2 En primera conexión
sudo raspi-config

# Seleccionar:
# - Interface Options → I2C → Enable
# - Interface Options → GPIO → Enable
# - Localization → Timezone (tu zona)
# - Advanced → Expand Filesystem

sudo reboot
```

### PASO 2: Clonar proyecto

```bash
# Crear directorio
mkdir -p /opt/smart_hour_meter
cd /opt/smart_hour_meter

# Copiar archivos
# - smart_hour_meter_v3_rpi.py
# - consultas_sql_v3.sql
# - install_v3_rpi.sh

# O descargar desde repositorio (si usas Git)
git clone https://github.com/tuusuario/smart-hour-meter.git
cd smart-hour-meter/v3
```

### PASO 3: Ejecutar instalación

```bash
# Hacer script ejecutable
chmod +x install_v3_rpi.sh

# Ejecutar instalación (requiere sudo)
sudo ./install_v3_rpi.sh

# Toma ~5-10 minutos (descarga drivers ODBC)
```

### PASO 4: Configurar credenciales SQL

```bash
# Editar archivo de configuración
sudo nano /opt/smart_hour_meter/config.ini

# Cambiar:
[SQL_SERVER]
Server = 192.168.1.50\SQLEXPRESS   ← Tu servidor
Database = ERP_Production
UID = sa
PWD = tu_contraseña_real           ← Tu contraseña
Port = 1433
```

### PASO 5: Ejecutar consultas SQL en servidor

```bash
# En SQL Server Management Studio:
# 1. Abrir archivo: consultas_sql_v3.sql
# 2. Ejecutar todas las consultas (F5)
# 3. Esto crea:
#    - Stored Procedure sp_Record_Production_Session
#    - Views de reportes
#    - Actualiza tablas necesarias
```

### PASO 6: Probar conexión I2C

```bash
# En Raspberry Pi:
i2cdetect -y 1

# Esperado: Mostrar dirección 0x27 (LCD)
# Ejemplo:
#      0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
# 00:                         -- -- -- -- -- -- -- --
# 10: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
# 20: -- -- -- -- -- -- -- 27 -- -- -- -- -- -- -- --
# 30: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
```

### PASO 7: Test manual

```bash
# Ejecutar script directamente
python3 /opt/smart_hour_meter/smart_hour_meter_v3_rpi.py

# Esperado:
# [GPIO] GPIO inicializado correctamente
# [LCD] Pantalla iniciada correctamente
# [BD] Conectado a SQL Server correctamente
# [BD] 4 empleados cargados
# [APP] Aplicación inicializada
# [APP] Iniciando bucle principal...

# Presionar CONFIRMAR en pantalla de inicio
```

---

## 🚀 INICIO COMO SERVICIO

```bash
# Habilitar para que se inicie automáticamente
sudo systemctl enable smart-hour-meter

# Iniciar servicio
sudo systemctl start smart-hour-meter

# Ver estado
sudo systemctl status smart-hour-meter

# Ver logs en tiempo real
sudo journalctl -u smart-hour-meter -f

# Detener servicio
sudo systemctl stop smart-hour-meter

# Reiniciar servicio
sudo systemctl restart smart-hour-meter
```

---

## 🔄 FLUJO DE OPERACIÓN v3

```
[INICIO]
  ↓
[SELECCIONAR EMPLEADO]
  ↓ Mostrar: "Juan Pérez", "María López", etc.
  ↓ UP/DOWN para navegar
  ↓ CONFIRMAR para seleccionar
  ↓
[SELECCIONAR TAREA]
  ↓ Mostrar: Tareas AGRUPADAS por Op_Group
  ↓ Ejemplo:
  │   - "Cilindrado" (meta: 200) = JOB01 + JOB02
  │   - "Roscado" (meta: 150) = JOB03
  │   - "Acabado" (meta: 100) = JOB04
  ↓ UP/DOWN para navegar
  ↓ CONFIRMAR para seleccionar
  ↓
[MONITOREO]
  ↓ Esperar a que motor se encienda (VFD = LOW)
  ↓ Motor encendido → comenzar cronómetro
  ↓ Mostrar: "Tiempo: 00:15:30 / Progreso: 0/200"
  ↓ CONFIRMAR para finalizar
  ↓
[INGRESO DE CANTIDAD]
  ↓ "¿PIEZAS TERMINADAS HOY?"
  ↓ UP/DOWN para aumentar/disminuir
  ↓ Mostrar cantidad seleccionada
  ↓ CONFIRMAR para guardar
  ↓
[GUARDANDO EN SQL]
  ↓ INSERT en Job_Operation_ActualTime
  ↓ Datos: Employee, Job, Cantidad, Tiempo
  ↓
[ÉXITO / VOLVER A INICIO]
```

---

## 📊 ESTRUCTURA DE DATOS (Python)

### SessionData
```python
@dataclass
class SessionData:
    employee: Optional[Employee]      # Empleado seleccionado
    selected_task: Optional[TaskGroup] # Tarea seleccionada
    vfd_running: bool                 # ¿Motor corriendo?
    time_motor_seconds: int           # Segundos de motor
    session_start_time: datetime      # Inicio de sesión
    monitoring_start_time: datetime   # Inicio de cronómetro
    completed_quantity: int           # Piezas hechas
```

### TaskGroup
```python
@dataclass
class TaskGroup:
    op_group_id: Optional[str]      # ID del grupo (None si individual)
    op_group_name: str              # Nombre mostrado en LCD
    jobs: List[str]                 # ["JOB01", "JOB02"]
    job_operations: List[str]       # ["OP01", "OP02"]
    order_quantity: int             # Meta total (suma si grupo)
    estimated_hours: float          # Horas estimadas
    is_group: bool                  # ¿Es grupo agrupado?
    
    # Métodos dinámicos:
    job_display       → "JOB01-JOB02" (para guardar en BD)
    operation_display → "OP01"
```

---

## 📱 PANTALLAS LCD (v3)

### HOME (Inicial)
```
HORÓMETRO INDUSTRIAL
Centro: TORNO 17
Presione CONFIRMAR
para iniciar
```

### Seleccionar Empleado
```
SELECCIONAR EMPLEADO
> Juan Pérez García
[1/4]
OK=Confirmar ESC=Atrás
```

### Seleccionar Tarea (AGRUPADA)
```
SELECCIONAR TAREA
> Cilindrado (JOB01+JOB02)
Meta: 200
[1/3]
```

### Monitoreo
```
MONITOREANDO
Op: Juan
Tiempo: 00:15:30
75/200
```

### Input de Cantidad
```
¿PIEZAS TERMINADAS HOY?

> 75 <
UP/DOWN: Cantidad OK
```

---

## 🔌 CONEXIONES GPIO

### Botones
```
GPIO 27 (PIN 36) ─── Botón UP
GPIO 22 (PIN 15) ─── Botón DOWN
GPIO 23 (PIN 16) ─── Botón CONFIRM

Cada botón tiene:
  ├─ Conexión a GPIO
  └─ Otra terminal a GND

Pull-up interno habilitado (INPUT_PULLUP)
```

### VFD
```
GPIO 17 (PIN 11) ─── Señal del VFD
  
Estados:
  - LOW (0V)  = Motor corriendo
  - HIGH (3.3V) = Motor parado

Debounce: 150ms en software
```

### LCD I2C
```
GPIO 2 (PIN 3)  ─── SDA (I2C)
GPIO 3 (PIN 5)  ─── SCL (I2C)
GND  (PIN 6)    ─── GND LCD
5V   (PIN 4)    ─── VCC LCD (opcional, si LCD tiene regulador)

Dirección I2C: 0x27 (típica)
```

---

## 💾 BASE DE DATOS (SQL Server)

### Tablas usadas
- `Employee` → Empleados
- `Job_Operation` → Operaciones
- `Op_Group` → Grupos de operaciones
- `Job_Operation_ActualTime` → **Registro de sesiones** (INSERT aquí)

### Columnas en Job_Operation_ActualTime
```sql
- Employee (FK)
- Job (concatenado si grupo)
- Job_Operation
- Work_Center
- Order_Quantity (meta)
- Completed_Quantity (piezas hechas) ← NUEVO v3
- Motor_Time_Seconds (segundos) ← NUEVO v3
- Actual_Run_Hrs (horas)
- Status ('Completed')
- Record_Date (GETUTCDATE())
```

### Inserción típica
```python
INSERT INTO Job_Operation_ActualTime 
    (Employee, Job, Job_Operation, Work_Center, 
     Order_Quantity, Completed_Quantity, Motor_Time_Seconds,
     Actual_Run_Hrs, Status, Record_Date)
VALUES 
    ('EMP001', 'JOB01-JOB02', 'OP01', 'TORNO 17',
     200, 75, 7200, 2.0, 'Completed', GETUTCDATE())
```

---

## 🐛 TROUBLESHOOTING

| Problema | Causa | Solución |
|----------|-------|----------|
| **No se ve LCD** | I2C no conectado | `i2cdetect -y 1` → debe mostrar 0x27 |
| **LCD muestra basura** | Dirección I2C incorrecta | Editar en código: `LCD20x4(address=0x3F)` |
| **Botones no responden** | GPIO mal configurado | Verificar pines en config.ini |
| **VFD no se detecta** | Cable no conectado | Medir con multímetro (LOW=corriendo) |
| **No conecta a SQL** | Credenciales incorrectas | Probar con `sqlcmd` en consola |
| **Error ODBC** | Driver no instalado | Ejecutar: `apt-get install msodbcsql17` |
| **CPU al 100%** | delay insuficiente | Aumentar `time.sleep(0.1)` en loop |
| **Servicio no inicia** | Permisos o ruta | `sudo systemctl status smart-hour-meter` |

---

## 📝 REGISTROS Y LOGS

```bash
# Ver logs del servicio en tiempo real
sudo journalctl -u smart-hour-meter -f

# Ver últimas 50 líneas
sudo journalctl -u smart-hour-meter -n 50

# Ver logs de hoy
sudo journalctl -u smart-hour-meter --since today

# Guardar logs en archivo
sudo journalctl -u smart-hour-meter > /tmp/smart_hour_meter.log
```

### Ejemplo de salida esperada
```
Apr 09 14:30:15 raspberrypi python3[1234]: [GPIO] GPIO inicializado correctamente
Apr 09 14:30:16 raspberrypi python3[1234]: [LCD] Pantalla iniciada correctamente
Apr 09 14:30:17 raspberrypi python3[1234]: [BD] Conectado a SQL Server correctamente
Apr 09 14:30:18 raspberrypi python3[1234]: [BD] 4 empleados cargados
Apr 09 14:30:20 raspberrypi python3[1234]: [VFD] Motor encendido
Apr 09 14:30:45 raspberrypi python3[1234]: [VFD] Motor apagado. Tiempo acumulado: 25s
Apr 09 14:30:47 raspberrypi python3[1234]: [BD] Datos guardados: EMP001 - 75 piezas
```

---

## 🔒 CONFIGURACIÓN DE SEGURIDAD

### Cambiar contraseña SQL
```bash
# En SQL Server Management Studio:
# 1. Right-click en SQL Server → Properties
# 2. Security → SA password
# 3. Cambiar contraseña (mínimo 8 caracteres, mayúscula + número)
```

### Restringir acceso a archivo config
```bash
# Solo root puede leer credenciales
sudo chmod 600 /opt/smart_hour_meter/config.ini
sudo chown root:root /opt/smart_hour_meter/config.ini
```

### Firewall SQL Server
```sql
-- En SQL Server, restringir usuario 'sa' a solo máquina local si es posible
-- O crear usuario específico con permisos limitados:

CREATE USER [pi_user] FROM LOGIN [pi_user];
GRANT SELECT, INSERT ON dbo.Job_Operation TO [pi_user];
GRANT SELECT, INSERT ON dbo.Job_Operation_ActualTime TO [pi_user];
GRANT EXECUTE ON OBJECT::sp_Record_Production_Session TO [pi_user];
```

---

## 📊 REPORTES POST-SESIÓN

### Ver sesiones de hoy
```sql
SELECT * FROM vw_Production_Sessions_Today
WHERE Work_Center = 'TORNO 17'
ORDER BY Session_Time DESC;
```

### Resumen de operador
```sql
SELECT 
    Employee_Name,
    COUNT(*) AS Sessions,
    SUM(Completed_Quantity) AS Total_Piezas,
    SUM(Motor_Time_Seconds) / 3600.0 AS Total_Horas
FROM vw_Production_Sessions_Today
WHERE Work_Center = 'TORNO 17'
GROUP BY Employee_Name;
```

### Performance del centro
```sql
SELECT * FROM vw_WorkCenter_Performance_Today
WHERE Work_Center = 'TORNO 17';
```

---

## ✅ CHECKLIST FINAL

```
HARDWARE
☐ RPi Zero conectada a WiFi/Ethernet
☐ LCD 20x4 en i2c (0x27)
☐ 3 botones en GPIO 27, 22, 23
☐ VFD signal en GPIO 17

SOFTWARE
☐ Python 3.9+ instalado
☐ Librerías instaladas (RPi.GPIO, pyodbc, smbus2)
☐ ODBC Driver 17 para SQL Server
☐ smart_hour_meter_v3_rpi.py copiado

BASE DE DATOS
☐ BD ERP_Production existe
☐ Consultas SQL ejecutadas
☐ Tabla Job_Operation_ActualTime con columnas nuevas
☐ Stored Procedure sp_Record_Production_Session creada

CONFIGURACIÓN
☐ config.ini editado con credenciales reales
☐ Credenciales SQL Server válidas
☐ Work_Center = "TORNO 17" correcto
☐ I2C y GPIO habilitados en /boot/config.txt

PRUEBAS
☐ i2cdetect -y 1 → muestra 0x27
☐ python3 smart_hour_meter_v3_rpi.py → sin errores
☐ Seleccionar empleado → OK
☐ Seleccionar tarea → OK (agrupadas)
☐ Presionar botones → responden sin dobles
☐ Motor enciende → cronómetro comienza
☐ Ingresar cantidad → UP/DOWN funciona
☐ Confirmar → datos en SQL Server

SERVICIO
☐ systemctl enable smart-hour-meter
☐ systemctl start smart-hour-meter
☐ sudo journalctl -u smart-hour-meter -f → sin errores
```

---

## 🎓 DIFERENCIAS PRINCIPALES v2 → v3

### Lógica de Grupos
```
v2: Un Job = Una tarea
v3: Múltiples Jobs con mismo Op_Group = Una tarea

Ejemplo:
  v2: Mostrar 3 opciones (OP01, OP02, OP03 por separado)
  v3: Mostrar 1 opción ("Cilindrado" que incluye OP01, OP02, OP03)
```

### Input de Cantidad
```
v2: Automático (lo que mide el cronómetro)
v3: Manual (usuario ingresa cuántas piezas terminó)
```

### Conexión BD
```
v2: API intermedia (HTTP JSON)
v3: ODBC directo (pyodbc)
```

### Plataforma
```
v2: Embedded (Arduino/C++)
v3: Linux (Python, más flexible)
```

---

## 🚀 PRÓXIMOS PASOS

1. ✅ Instalar Raspberry Pi OS
2. ✅ Ejecutar `install_v3_rpi.sh`
3. ✅ Editar `config.ini` con credenciales
4. ✅ Ejecutar `consultas_sql_v3.sql` en SQL Server
5. ✅ Probar con `python3 smart_hour_meter_v3_rpi.py`
6. ✅ Habilitar servicio: `sudo systemctl enable smart-hour-meter`
7. ✅ Verificar logs: `sudo journalctl -u smart-hour-meter -f`

---

**Versión**: 3.0  
**Hardware**: Raspberry Pi Zero W  
**Lenguaje**: Python 3.9+  
**Status**: ✅ Production Ready  
**Soporte**: Contactar si hay problemas
