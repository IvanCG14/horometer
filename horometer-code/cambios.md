# 🏭 GUÍA DE INTEGRACIÓN INDUSTRIAL v2
## Smart Hour Meter - Modo Asignación de Centro de Trabajo

**Fecha**: 2026-04-08  
**Versión**: 2.0  
**Estado**: Industrial Grade  

---

## 📋 RESUMEN DE CAMBIOS

### ¿Qué cambió?

#### **ANTES (v1 - Genérico)**
```
Flujo: HOME → Seleccionar Operario → Seleccionar Pieza → Seleccionar Tipo
Datos: Menús estáticos en caché
BD: Tablas simples (Operarios, Piezas, Tipos)
```

#### **AHORA (v2 - Industrial)**
```
Flujo: HOME → Mostrar Asignación Activa → Confirmar Inicio → Monitoreo
Datos: Asignaciones dinámicas del ERP
BD: Tablas ERP (Emp_Assignment, Job_Operation, Employee, etc.)
```

---

## 🔄 FLUJO NUEVO DE MÁQUINA DE ESTADOS

### Estados anteriores (6 estados)
```
0. STATE_HOME
1. STATE_SELECT_OP        ❌ ELIMINADO
2. STATE_SELECT_PIECE     ❌ ELIMINADO
3. STATE_SELECT_TYPE      ❌ ELIMINADO
4. STATE_ENABLED
5. STATE_MONITORING
6. STATE_CLOSING
```

### Estados nuevos (5 estados)
```
0. STATE_HOME              ← Inicio, sin asignación
1. STATE_SHOW_ASSIGNMENT   ← Mostrar asignación activa del servidor
2. STATE_CONFIRM_START     ← Confirmar antes de habilitar máquina
3. STATE_ENABLED           ← Relé cerrado, esperando VFD
4. STATE_MONITORING        ← Contando tiempo
5. STATE_CLOSING           ← Cierre y envío a ERP
```

### Diagrama del flujo
```
┌─────────────┐
│  STATE_HOME │  (Sin asignación)
└──────┬──────┘
       │ [CONFIRMAR]
       ▼
┌──────────────────────┐
│ STATE_SHOW_ASSIGNMENT│  (Mostrar: EMP, Job, Op)
│ [UP/DOWN = navegar]  │  [CONFIRMAR = siguiente]
└──────┬───────────────┘
       │
       ▼
┌─────────────────────┐
│ STATE_CONFIRM_START │  (Confirmación final)
│ [CONFIRMAR = habilitar]
└──────┬──────────────┘
       │
       ▼
┌──────────────┐
│ STATE_ENABLED│  (Relé CERRADO)
└──────┬───────┘
       │ [VFD = Run]
       ▼
┌──────────────────┐
│ STATE_MONITORING │  (Cronómetro activo)
│ [CONFIRMAR = finalizar]
└──────┬───────────┘
       │
       ▼
┌──────────────┐
│ STATE_CLOSING│  (Envío a ERP)
└──────┬───────┘
       │
       ▼
  [Reinicia]
```

---

## 📊 ESTRUCTURA DE DATOS NUEVA

### Anterior: JsonArray genérico
```cpp
struct {
  String operario;        // "Juan Pérez"
  String pieza;           // "Eje Cilíndrico"
  String tipoMecanizado;  // "Torneado"
} sysData;
```

### Ahora: Asignación ERP real
```cpp
struct AssignmentData {
  String employeeId;           // EMP001
  String firstName;            // Juan
  String lastName;             // Pérez García
  String employeeShiftCode;    // T1
  String employeeShiftName;    // Turno 1 - Mañana
  String opGroup;              // GRP001
  String jobOperation;         // OP001
  String lastUpdated;          // 2026-04-08 08:30:00
  String status;               // In_Progress
  float estRunHrs;             // 2.5
  String jobCode;              // JOB001
  String description;          // Cilindrado inicial ø50mm
  String opGroupName;          // Cilindrado
  String workCenter;           // TORNO 17
  int orderQuantity;           // 100
  String partNumber;           // PT-2024-001
  bool esGrupo;                // 0
} sysData.currentAssignment;
```

---

## 🗄️ TABLAS SQL SERVER (Nuevas vs Antiguas)

### Tablas Nuevas (Modelo ERP)
```
Employee              ← Empleados reales del ERP
shift                 ← Turnos
Work_Center           ← Centros de trabajo (TORNO 17, etc)
Job                   ← Órdenes de fabricación
Op_Group              ← Grupos de operaciones
Job_Operation         ← Operaciones específicas
Emp_Assignment        ← Asignaciones de empleados a operaciones
Job_Operation_ActualTime  ← Registro de tiempos reales
Work_Center_Device    ← Dispositivos por centro
```

### Flujo de datos SQL
```
Emp_Assignment
    ├─ Employee (FK) → Employee
    ├─ Job_Operation (FK) → Job_Operation
    │   ├─ Job (FK) → Job
    │   ├─ Work_Center (FK) → Work_Center
    │   └─ Op_Group (FK) → Op_Group
    │
    └─ Cuando finaliza, se registra en Job_Operation_ActualTime
        ├─ Employee (FK)
        ├─ Job (FK)
        ├─ Job_Operation (FK)
        └─ Actual_Run_Hrs (Tiempo real)
```

---

## 🌐 API v2 - Cambios Principales

### Antes (getCache)
```php
GET ?action=getCache
Response: {
  "operarios": ["Juan", "María"],
  "piezas": ["Eje", "Tuerca"],
  "tiposMecanizado": ["Torneado", "Fresado"]
}
```

### Ahora (getAssignments)
```php
GET ?action=getAssignments&workCenter=TORNO_17
Response: {
  "status": "success",
  "data": {
    "assignments": [
      {
        "Employee": "EMP001",
        "First_Name": "Juan",
        "Last_Name": "Pérez García",
        "employee_shift_code": "T1",
        "employee_shift_name": "Turno 1 - Mañana",
        "Op_Group": "GRP001",
        "Job_Operation": "OP001",
        "Last_Updated": "2026-04-08 08:30:00",
        "Status": "In_Progress",
        "Est_Run_Hrs": 2.5,
        "Job": "JOB001",
        "Description": "Cilindrado inicial ø50mm",
        "OpGroupName": "Cilindrado",
        "Work_Center": "TORNO 17",
        "Order_Quantity": 100,
        "Part_Number": "PT-2024-001",
        "es_grupo": 0
      }
    ],
    "workCenter": "TORNO 17",
    "rowCount": 1
  }
}
```

### POST - Envío de tiempo (Cambio en estructura)

#### Antes
```json
{
  "operario": "Juan Pérez",
  "pieza": "Eje Cilíndrico",
  "tipoMecanizado": "Torneado",
  "tiempoSegundos": 3600,
  "timestamp": 1234567
}
```

#### Ahora (Estructura ERP)
```json
{
  "Employee": "EMP001",
  "Job": "JOB001",
  "Job_Operation": "OP001",
  "Op_Group": "GRP001",
  "Work_Center": "TORNO 17",
  "Part_Number": "PT-2024-001",
  "Actual_Run_Hrs": 1.25,
  "Status": "Completed",
  "Timestamp": 1712572200
}
```

---

## 📱 LCD - Cambios en Pantalla

### STATE_HOME (Igual)
```
===== INICIO =====
Centro: TORNO 17
Asignaciones: 1
OK=Continuar
```

### STATE_SHOW_ASSIGNMENT (NUEVO)
```
ASIGNACION
Empl: EMP001
Op: JOB001
OK=Confirm  ESC=Back
```

### STATE_CONFIRM_START (NUEVO)
```
CONFIRMAR INICIO
Juan Pérez
Pieza: PT-2024-001
OK=Iniciar
```

### STATE_ENABLED (Ahora muestra Employee ID)
```
HABILITADO
Empl: EMP001
Esperando VFD...
(vacío)
```

### STATE_MONITORING (Igual estructura, menos datos)
```
MIDIENDO
Tiempo: 01:23:45
Op: OP001
OK=Finalizar
```

---

## 🔌 PROCEDIMIENTO DE IMPLEMENTACIÓN

### Paso 1: Preparar la Base de Datos

```bash
# En SQL Server Management Studio:
1. Crear nueva base de datos: ERP_Production
2. Ejecutar: database_v2_industrial.sql
3. Verificar tablas creadas:
   SELECT * FROM Employee;
   SELECT * FROM Emp_Assignment;
   SELECT * FROM Job_Operation;
```

### Paso 2: Implementar API PHP v2

```bash
# En servidor web:
1. Copiar api_v2_industrial.php a /api/log-mecanizado-v2.php
2. Editar líneas 21-28 (credenciales SQL Server)
3. Probar en navegador:
   http://servidor/api/log-mecanizado-v2.php?action=getAssignments&workCenter=TORNO_17
4. Debe retornar JSON con asignaciones activas
```

### Paso 3: Actualizar Firmware ESP32

```bash
# En PlatformIO:
1. Reemplazar main.cpp con main_v2_industrial.cpp
2. Editar líneas 24-25 (WiFi credentials)
3. Editar línea 26 (WORK_CENTER = "TORNO 17")
4. Editar línea 25 (API_ENDPOINT)
5. Compilar: pio run
6. Subir: pio run -t upload
```

### Paso 4: Probar Flujo Completo

```
[Encender ESP32]
  ↓
Serial: "Downloading assignments from: http://..."
  ↓
LCD: "===== INICIO ===== / Centro: TORNO 17 / Asignaciones: 1"
  ↓
[Presionar CONFIRMAR]
  ↓
LCD: "ASIGNACION / Empl: EMP001 / Op: JOB001"
  ↓
[Presionar CONFIRMAR]
  ↓
LCD: "CONFIRMAR INICIO / Juan Pérez / Pieza: PT-2024-001"
  ↓
[Presionar CONFIRMAR]
  ↓
LCD: "HABILITADO / Empl: EMP001 / Esperando VFD..."
  ↓
[Encender motor desde HMI VFD]
  ↓
LCD: "MIDIENDO / Tiempo: 00:00:05 / Op: OP001"
  ↓
[Apagar motor]
  ↓
[Presionar CONFIRMAR]
  ↓
[Datos enviados a SQL Server]
  ↓
LCD: "===== INICIO ===== / Centro: TORNO 17"
```

---

## 🔍 DIFERENCIAS CLAVE EN CÓDIGO

### main.cpp v1 vs v2

| Aspecto | v1 | v2 |
|---------|----|----|
| **Estructura de datos** | JsonArray genérico | AssignmentData struct |
| **Estados** | 6 (con menús) | 5 (directo a asignación) |
| **Navegación** | Seleccionar 3 veces | Navegar y confirmar |
| **API GET** | getCache | getAssignments?workCenter=X |
| **API POST** | 5 campos | 9 campos ERP |
| **Identificadores** | String operario | Employee ID + Job_Operation |
| **Base de datos** | Tablas simples | Tablas ERP reales |

### Debounce y Watchdog

**SIN CAMBIOS** ✅
- Debounce de botones: 50ms (igual)
- Debounce VFD: 150ms (igual)
- Watchdog Timer: 10 segundos (igual)
- Timeout sesión: 5 horas (igual)

---

## ⚠️ CONSIDERACIONES IMPORTANTES

### 1. Validación de Datos
En `api_v2_industrial.php` hay validaciones de negocio:
```php
// Tiempo no puede ser negativo
if ($actualRunHrs < 0) {
    throw new Exception("Actual_Run_Hrs cannot be negative");
}

// Tiempo no puede superar 24 horas
if ($actualRunHrs > 24) {
    throw new Exception("Actual_Run_Hrs cannot exceed 24 hours");
}
```

### 2. Manejo de Grupos vs Operaciones Individuales
```cpp
// Si es grupo (sin Job_Operation específica):
if (sysData.currentAssignment.esGrupo == 1) {
  // Mostrar operaciones del grupo
}
// Si es operación (con Job_Operation):
else {
  // Mostrar operación específica
}
```

### 3. Recuperación ante Fallos
- LittleFS guarda asignaciones en `/assignments.json`
- Si WiFi falla, usa caché local
- Asignaciones se sincronizan al siguiente boot

### 4. Múltiples Centros de Trabajo
- Parámetro `WORK_CENTER = "TORNO 17"` es configurable
- Cada dispositivo reporta su centro específico
- BD soporta N centros de trabajo

---

## 🚀 VERIFICACIÓN POST-INTEGRACIÓN

### Checklist de validación

```
FIRMWARE
☐ ESP32 conecta a WiFi
☐ Descarga asignaciones de API
☐ Muestra empleado + operación en LCD
☐ Debounce funciona (sin dobles clics)
☐ VFD signal se detecta (150ms debounce)
☐ Relé interlock abre/cierra
☐ Watchdog activo (reinicia si congela)

BASE DE DATOS
☐ Tablas ERP creadas
☐ Datos de prueba insertados
☐ Vistas funcionan
☐ Stored Procs ejecutan sin error

API
☐ GET ?action=getAssignments devuelve JSON válido
☐ POST acepta estructura ERP
☐ Datos se insertan en Job_Operation_ActualTime
☐ Asignación se marca como Completed

INTEGRACIÓN
☐ Dispositivo obtiene asignación del centro
☐ Usuario ve datos en LCD
☐ Tiempo se registra en ERP
☐ Siguiente boot trae nuevas asignaciones
```

---

## 📈 ESCALABILIDAD FUTURA

El nuevo esquema soporta fácilmente:

1. **Múltiples dispositivos por centro**
   - Tabla `Work_Center_Device`
   - Cada dispositivo reporta con su ID único

2. **Múltiples turnos**
   - Tabla `shift` con horarios
   - Empleados asignados a turnos

3. **Reportes de rendimiento**
   - Vista `V_WorkCenter_Performance`
   - Análisis de horas vs tiempo estimado

4. **Histórico completo**
   - Tabla `Job_Operation_ActualTime` inmutable
   - Auditoría y trazabilidad 100%

5. **Integración con MES/ERP**
   - APIs REST para actualización de órdenes
   - Feedback en tiempo real

---

## 🔧 TROUBLESHOOTING v2

| Problema | Causa | Solución |
|----------|-------|----------|
| No obtiene asignaciones | BD vacía o credenciales incorrectas | Verificar data en Emp_Assignment |
| Muestra "Sin asignaciones" | Todas las asignaciones están 'Closed' | Insertar asignaciones 'Assigned' o 'In_Progress' |
| API retorna error 400 | Work_Center no existe | Verificar WORK_CENTER en main.cpp |
| Datos no se guardan en ERP | JSON estructura incorrecta | Validar campos en POST (Employee, Job, etc) |
| Tabla Job_Operation_ActualTime vacía | No se envió POST correctamente | Ver logs API en servidor web |

---

## 📞 EJEMPLOS PRÁCTICOS

### Agregar nueva asignación en SQL Server

```sql
-- Crear Job si no existe
INSERT INTO Job (Job, Part_Number, Order_Quantity, Priority, job_status)
VALUES ('JOB004', 'PT-2024-004', 75, 2, 'Open');

-- Crear Operación
INSERT INTO Job_Operation 
  (Job_Operation, Job, Op_Group, Work_Center, Description, Est_Run_Hrs, operation_status)
VALUES 
  ('OP006', 'JOB004', 'GRP001', 'TORNO 17', 'Cilindrado 60mm', 3.0, 'Not_Started');

-- Asignar a empleado
INSERT INTO Emp_Assignment 
  (Employee, Job_Operation, Op_Group, Work_Center, Status)
VALUES 
  ('EMP002', 'OP006', 'GRP001', 'TORNO 17', 'Assigned');
  
-- ¡Al siguiente boot, ESP32 descargará esta asignación!
```

### Ver histórico de tiempos

```sql
SELECT 
  Employee,
  Job,
  Job_Operation,
  Actual_Run_Hrs,
  Record_Date,
  CONVERT(DATE, Record_Date) AS Fecha
FROM Job_Operation_ActualTime
WHERE CONVERT(DATE, Record_Date) = CAST(GETUTCDATE() AS DATE)
ORDER BY Record_Date DESC;
```

---

## 📚 DOCUMENTACIÓN RELACIONADA

- `main_v2_industrial.cpp` - Firmware nuevo
- `api_v2_industrial.php` - API nuevamente
- `database_v2_industrial.sql` - Schema ERP
- `README_v2_INDUSTRIAL.md` - Guía de usuario (próximamente)

---

**Versión**: 2.0  
**Última actualización**: 2026-04-08  
**Estado**: ✅ Listo para Producción  
**Centro de Trabajo**: TORNO 17 (configurable)
