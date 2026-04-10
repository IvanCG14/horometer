-- ============================================================================
-- CONSULTAS SQL SERVER PARA SMART HOUR METER v3 (Raspberry Pi)
-- Centro de Trabajo: TORNO 17 (Configurable)
-- ============================================================================

-- ============================================================================
-- 1. CONSULTA: Obtener tareas agrupadas por Op_Group
-- Usada por: DatabaseManager.get_tasks_by_employee()
-- ============================================================================

-- VERSIÓN COMPLETA CON COMENTARIOS
SELECT 
    -- Identificadores del grupo
    COALESCE(og.Op_Group, jo.Job_Operation) AS op_group_id,
    COALESCE(og.Name, jo.Description) AS op_group_name,
    
    -- Lista de Jobs (concatenados con guión si es grupo)
    STRING_AGG(DISTINCT jo.Job, '-') 
        WITHIN GROUP (ORDER BY jo.Job) AS jobs,
    
    -- Lista de Job_Operations (concatenados con guión si es grupo)
    STRING_AGG(DISTINCT jo.Job_Operation, '-') 
        WITHIN GROUP (ORDER BY jo.Job_Operation) AS job_operations,
    
    -- Cantidad total a hacer (suma de todos los Jobs del grupo)
    SUM(j.Order_Quantity) AS total_order_quantity,
    
    -- Horas estimadas promedio
    AVG(CAST(jo.Est_Run_Hrs AS FLOAT)) AS estimated_hours,
    
    -- Flag: 1 si es grupo, 0 si es operación individual
    CASE 
        WHEN og.Op_Group IS NOT NULL THEN 1 
        ELSE 0 
    END AS es_grupo

FROM dbo.Job_Operation jo
INNER JOIN dbo.Job j ON jo.Job = j.Job
LEFT JOIN dbo.Op_Group og ON jo.Op_Group = og.Op_Group

WHERE jo.Work_Center = 'TORNO 17'  -- Centro de trabajo
  AND j.job_status IN ('Open', 'In_Progress')  -- Solo órdenes activas
  AND jo.operation_status IN ('Not_Started', 'In_Progress')  -- No completadas

-- Agrupar por: Grupo si existe, sino por operación individual
GROUP BY 
    COALESCE(og.Op_Group, jo.Job_Operation),
    COALESCE(og.Name, jo.Description),
    CASE WHEN og.Op_Group IS NOT NULL THEN 1 ELSE 0 END

ORDER BY op_group_name ASC;

-- ============================================================================
-- VERSIÓN OPTIMIZADA (Usar en código Python)
-- ============================================================================

DECLARE @WorkCenter NVARCHAR(100) = 'TORNO 17';

SELECT 
    COALESCE(og.Op_Group, '') AS op_group_id,
    COALESCE(og.Name, jo.Description) AS op_group_name,
    STRING_AGG(jo.Job, '-') WITHIN GROUP (ORDER BY jo.Job) AS jobs,
    STRING_AGG(jo.Job_Operation, '-') WITHIN GROUP (ORDER BY jo.Job_Operation) AS job_operations,
    SUM(j.Order_Quantity) AS total_quantity,
    AVG(CAST(jo.Est_Run_Hrs AS FLOAT)) AS est_hours,
    CASE WHEN og.Op_Group IS NOT NULL THEN 1 ELSE 0 END AS es_grupo

FROM dbo.Job_Operation jo
INNER JOIN dbo.Job j ON jo.Job = j.Job
LEFT JOIN dbo.Op_Group og ON jo.Op_Group = og.Op_Group

WHERE jo.Work_Center = @WorkCenter
  AND j.job_status IN ('Open', 'In_Progress')
  AND jo.operation_status IN ('Not_Started', 'In_Progress')

GROUP BY 
    COALESCE(og.Op_Group, jo.Job_Operation),
    COALESCE(og.Name, jo.Description),
    CASE WHEN og.Op_Group IS NOT NULL THEN 1 ELSE 0 END

ORDER BY op_group_name;

-- ============================================================================
-- 2. STORED PROCEDURE: Guardar datos de sesión
-- Usada por: DatabaseManager.save_session_data()
-- ============================================================================

CREATE OR ALTER PROCEDURE sp_Record_Production_Session
    @Employee NVARCHAR(50),
    @Job NVARCHAR(100),              -- Job IDs concatenados (ej: JOB01-JOB02)
    @Job_Operation NVARCHAR(100),    -- Job_Operation ID
    @Work_Center NVARCHAR(100),
    @Order_Quantity INT,             -- Cantidad total a hacer
    @Completed_Quantity INT,         -- Piezas completadas hoy
    @Motor_Time_Seconds INT          -- Segundos de motor corriendo
AS
BEGIN
    SET NOCOUNT ON;
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Validar empleado existe
        IF NOT EXISTS (SELECT 1 FROM dbo.Employee WHERE Employee = @Employee AND active = 1)
        BEGIN
            RAISERROR('Empleado no encontrado', 16, 1);
        END
        
        -- Validar que Work_Center existe
        IF NOT EXISTS (SELECT 1 FROM dbo.Work_Center WHERE Work_Center = @Work_Center AND active = 1)
        BEGIN
            RAISERROR('Centro de trabajo no encontrado', 16, 1);
        END
        
        -- Convertir segundos a horas decimales
        DECLARE @Actual_Run_Hrs DECIMAL(10, 4) = CAST(@Motor_Time_Seconds AS DECIMAL(10, 2)) / 3600.0;
        
        -- Insertar registro en tabla de tiempos reales
        INSERT INTO dbo.Job_Operation_ActualTime
            (Employee, Job, Job_Operation, Work_Center, 
             Order_Quantity, Completed_Quantity, Motor_Time_Seconds, 
             Actual_Run_Hrs, Status, Record_Date)
        VALUES
            (@Employee, @Job, @Job_Operation, @Work_Center,
             @Order_Quantity, @Completed_Quantity, @Motor_Time_Seconds,
             @Actual_Run_Hrs, 'Completed', GETUTCDATE());
        
        -- Opcionalmente: Actualizar estado de operaciones como completadas
        -- (comentado para no afectar datos)
        -- UPDATE dbo.Job_Operation
        -- SET operation_status = 'Complete'
        -- WHERE Job_Operation = @Job_Operation;
        
        COMMIT TRANSACTION;
        
        SELECT 
            'OK' AS Result,
            'Sesión guardada correctamente' AS Message,
            @@IDENTITY AS Record_ID;
    
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        
        SELECT 
            'ERROR' AS Result,
            ERROR_MESSAGE() AS Message,
            NULL AS Record_ID;
    END CATCH
END;

-- ============================================================================
-- 3. VIEW: Registro de sesiones hoy
-- ============================================================================

CREATE OR ALTER VIEW vw_Production_Sessions_Today AS
SELECT 
    jat.Record_ID,
    e.Employee,
    CONCAT(e.First_Name, ' ', e.Last_Name) AS Employee_Name,
    jat.Job,
    jat.Job_Operation,
    jat.Work_Center,
    jat.Order_Quantity,
    jat.Completed_Quantity,
    jat.Motor_Time_Seconds,
    jat.Actual_Run_Hrs,
    jat.Status,
    CAST(jat.Record_Date AS DATE) AS Session_Date,
    CAST(jat.Record_Date AS TIME) AS Session_Time
FROM dbo.Job_Operation_ActualTime jat
INNER JOIN dbo.Employee e ON jat.Employee = e.Employee
WHERE CAST(jat.Record_Date AS DATE) = CAST(GETUTCDATE() AS DATE)
ORDER BY jat.Record_Date DESC;

-- ============================================================================
-- 4. VIEW: Rendimiento por centro de trabajo (hoy)
-- ============================================================================

CREATE OR ALTER VIEW vw_WorkCenter_Performance_Today AS
SELECT 
    wc.Work_Center,
    wc.Description,
    COUNT(DISTINCT jat.Employee) AS Active_Operators,
    COUNT(DISTINCT jat.Job_Operation) AS Operations_Completed,
    SUM(jat.Completed_Quantity) AS Total_Pieces_Completed,
    SUM(jat.Motor_Time_Seconds) AS Total_Motor_Seconds,
    SUM(jat.Actual_Run_Hrs) AS Total_Hours,
    AVG(CAST(jat.Actual_Run_Hrs AS FLOAT)) AS Avg_Hours_Per_Session,
    MAX(jat.Record_Date) AS Last_Activity
FROM dbo.Work_Center wc
LEFT JOIN dbo.Job_Operation_ActualTime jat 
    ON wc.Work_Center = jat.Work_Center 
    AND CAST(jat.Record_Date AS DATE) = CAST(GETUTCDATE() AS DATE)
WHERE wc.active = 1
GROUP BY wc.Work_Center, wc.Description;

-- ============================================================================
-- 5. SCRIPTS DE PRUEBA
-- ============================================================================

-- Prueba 1: Ver tareas disponibles para TORNO 17
DECLARE @WorkCenter NVARCHAR(100) = 'TORNO 17';

SELECT 
    'TAREAS DISPONIBLES' AS Tipo,
    COALESCE(og.Op_Group, '') AS op_group_id,
    COALESCE(og.Name, jo.Description) AS Tarea,
    STRING_AGG(jo.Job, '-') AS Jobs,
    SUM(j.Order_Quantity) AS Total_Meta
FROM dbo.Job_Operation jo
INNER JOIN dbo.Job j ON jo.Job = j.Job
LEFT JOIN dbo.Op_Group og ON jo.Op_Group = og.Op_Group
WHERE jo.Work_Center = @WorkCenter
  AND j.job_status IN ('Open', 'In_Progress')
GROUP BY 
    COALESCE(og.Op_Group, jo.Job_Operation),
    COALESCE(og.Name, jo.Description)
ORDER BY Tarea;

-- Prueba 2: Ver sesiones registradas hoy
SELECT TOP 10 * FROM vw_Production_Sessions_Today;

-- Prueba 3: Ver rendimiento del centro
SELECT * FROM vw_WorkCenter_Performance_Today;

-- Prueba 4: Registrar sesión de prueba (TORNO 17)
EXEC sp_Record_Production_Session
    @Employee = 'EMP001',
    @Job = 'JOB001',
    @Job_Operation = 'OP001',
    @Work_Center = 'TORNO 17',
    @Order_Quantity = 100,
    @Completed_Quantity = 75,
    @Motor_Time_Seconds = 7200;  -- 2 horas

-- Verificar que se guardó
SELECT * FROM vw_Production_Sessions_Today WHERE Employee = 'EMP001';

-- ============================================================================
-- TABLA ACTUALIZADA: Job_Operation_ActualTime
-- (Agregar columnas faltantes si no existen)
-- ============================================================================

-- Verificar columnas
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'Job_Operation_ActualTime' 
    AND COLUMN_NAME = 'Order_Quantity'
)
BEGIN
    ALTER TABLE dbo.Job_Operation_ActualTime
    ADD Order_Quantity INT NULL,
        Completed_Quantity INT NULL,
        Motor_Time_Seconds INT NULL;
END;

-- Crear índices para performance
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE name = 'idx_JobOpTime_Date_WorkCenter'
)
BEGIN
    CREATE INDEX idx_JobOpTime_Date_WorkCenter 
    ON dbo.Job_Operation_ActualTime(Record_Date, Work_Center);
END;

-- ============================================================================
-- INFORMACIÓN ÚTIL
-- ============================================================================

/*
CONSULTA SQL PARA PYTHON:
========================

query = """
    SELECT 
        COALESCE(og.Op_Group, '') AS op_group_id,
        COALESCE(og.Name, jo.Description) AS op_group_name,
        STRING_AGG(jo.Job, '-') AS jobs,
        STRING_AGG(jo.Job_Operation, '-') AS job_operations,
        SUM(j.Order_Quantity) AS total_quantity,
        AVG(jo.Est_Run_Hrs) AS est_hours,
        CASE WHEN og.Op_Group IS NOT NULL THEN 1 ELSE 0 END AS es_grupo
    FROM dbo.Job_Operation jo
    INNER JOIN dbo.Job j ON jo.Job = j.Job
    LEFT JOIN dbo.Op_Group og ON jo.Op_Group = og.Op_Group
    WHERE jo.Work_Center = ?
      AND j.job_status IN ('Open', 'In_Progress')
      AND jo.operation_status != 'Complete'
    GROUP BY 
        COALESCE(og.Op_Group, jo.Job_Operation),
        COALESCE(og.Name, jo.Description),
        CASE WHEN og.Op_Group IS NOT NULL THEN 1 ELSE 0 END
    ORDER BY op_group_name
"""

cursor.execute(query, (WORK_CENTER,))


ESTRUCTURA DE DATOS EN PYTHON:
==============================

class TaskGroup:
    op_group_id: str          # ID del grupo o None
    op_group_name: str        # Nombre a mostrar en LCD
    jobs: List[str]           # ["JOB01", "JOB02"]
    job_operations: List[str] # ["OP01", "OP02"]
    order_quantity: int       # Meta total
    estimated_hours: float    # Horas estimadas
    is_group: bool            # True si es grupo
    
    # Métodos:
    - job_display: "JOB01-JOB02" (para BD)
    - operation_display: "OP01" (para BD)


FLUJO DE GUARDADO:
==================

1. Usuario selecciona tarea (grupo o individual)
2. Motor se enciende → cronómetro comienza
3. Usuario presiona CONFIRMAR → pregunta cantidad
4. Usuario ingresa cantidad (UP/DOWN)
5. Usuario confirma → se ejecuta:
   
   INSERT INTO Job_Operation_ActualTime
   (Employee, Job, Job_Operation, Work_Center, 
    Order_Quantity, Completed_Quantity, Motor_Time_Seconds,
    Actual_Run_Hrs, Status, Record_Date)
   
   Ejemplo:
   - Employee: 'EMP001'
   - Job: 'JOB01-JOB02' (si es grupo) o 'JOB01' (individual)
   - Job_Operation: 'OP01'
   - Work_Center: 'TORNO 17'
   - Order_Quantity: 100 (meta total)
   - Completed_Quantity: 75 (piezas hechas)
   - Motor_Time_Seconds: 7200 (2 horas en segundos)
   - Actual_Run_Hrs: 2.0 (7200/3600)
   - Status: 'Completed'
   - Record_Date: GETUTCDATE()
*/
