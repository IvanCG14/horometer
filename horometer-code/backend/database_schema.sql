-- ============================================================================
-- SCRIPT SQL SERVER v2 - SMART HOUR METER (MODO INDUSTRIAL)
-- Base de datos: ERP_Production
-- Propósito: Integración con sistema ERP para centros de trabajo
-- ============================================================================

-- Crear base de datos si no existe
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'ERP_Production')
BEGIN
    CREATE DATABASE ERP_Production;
END
GO

USE ERP_Production;
GO

-- ============================================================================
-- TABLA: Employee (Empleados)
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Employee')
BEGIN
    CREATE TABLE Employee (
        Employee VARCHAR(50) PRIMARY KEY,
        First_Name NVARCHAR(100) NOT NULL,
        Last_Name NVARCHAR(100) NOT NULL,
        shift VARCHAR(10),  -- Código de turno
        email NVARCHAR(100),
        phone NVARCHAR(20),
        active BIT DEFAULT 1,
        hire_date DATETIME2,
        created_date DATETIME2 DEFAULT GETUTCDATE(),
        last_modified DATETIME2 DEFAULT GETUTCDATE()
    );
    
    CREATE INDEX idx_Employee_active ON Employee(active);
    CREATE INDEX idx_Employee_shift ON Employee(shift);
END
GO

-- ============================================================================
-- TABLA: shift (Turnos)
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'shift')
BEGIN
    CREATE TABLE shift (
        shift VARCHAR(10) PRIMARY KEY,
        Shift_Name NVARCHAR(100) NOT NULL,
        start_time TIME,
        end_time TIME,
        active BIT DEFAULT 1,
        created_date DATETIME2 DEFAULT GETUTCDATE()
    );
    
    CREATE INDEX idx_shift_active ON shift(active);
END
GO

-- ============================================================================
-- TABLA: Work_Center (Centros de Trabajo)
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Work_Center')
BEGIN
    CREATE TABLE Work_Center (
        Work_Center VARCHAR(100) PRIMARY KEY,
        Description NVARCHAR(500),
        Location NVARCHAR(200),
        Capacity_Per_Hour INT,
        Setup_Time_Minutes INT,
        active BIT DEFAULT 1,
        created_date DATETIME2 DEFAULT GETUTCDATE()
    );
    
    CREATE INDEX idx_WorkCenter_active ON Work_Center(active);
END
GO

-- ============================================================================
-- TABLA: Job (Órdenes de Fabricación / Trabajos)
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Job')
BEGIN
    CREATE TABLE Job (
        Job VARCHAR(50) PRIMARY KEY,
        Part_Number VARCHAR(100) NOT NULL,
        Order_Quantity INT NOT NULL,
        Customer NVARCHAR(200),
        Due_Date DATETIME2,
        Priority INT,
        job_status VARCHAR(50),  -- Open, In_Progress, On_Hold, Closed
        created_date DATETIME2 DEFAULT GETUTCDATE(),
        closed_date DATETIME2 NULL,
        last_modified DATETIME2 DEFAULT GETUTCDATE()
    );
    
    CREATE INDEX idx_Job_status ON Job(job_status);
    CREATE INDEX idx_Job_PartNumber ON Job(Part_Number);
    CREATE INDEX idx_Job_DueDate ON Job(Due_Date);
END
GO

-- ============================================================================
-- TABLA: Op_Group (Grupos de Operaciones)
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Op_Group')
BEGIN
    CREATE TABLE Op_Group (
        Op_Group VARCHAR(50) PRIMARY KEY,
        Name NVARCHAR(200) NOT NULL,
        Description NVARCHAR(500),
        Sequence_Order INT,
        active BIT DEFAULT 1,
        created_date DATETIME2 DEFAULT GETUTCDATE()
    );
    
    CREATE INDEX idx_OpGroup_active ON Op_Group(active);
    CREATE INDEX idx_OpGroup_sequence ON Op_Group(Sequence_Order);
END
GO

-- ============================================================================
-- TABLA: Job_Operation (Operaciones de Trabajo)
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Job_Operation')
BEGIN
    CREATE TABLE Job_Operation (
        Job_Operation VARCHAR(100) PRIMARY KEY,
        Job VARCHAR(50) NOT NULL,
        Op_Group VARCHAR(50),  -- Grupo al que pertenece (NULL si es operación standalone)
        Work_Center VARCHAR(100) NOT NULL,
        Description NVARCHAR(500),
        Sequence_Number INT,
        Est_Run_Hrs DECIMAL(10, 2),  -- Horas estimadas
        Est_Setup_Minutes INT,
        operation_status VARCHAR(50),  -- Not_Started, In_Progress, Complete
        created_date DATETIME2 DEFAULT GETUTCDATE(),
        last_modified DATETIME2 DEFAULT GETUTCDATE(),
        
        FOREIGN KEY (Job) REFERENCES Job(Job),
        FOREIGN KEY (Op_Group) REFERENCES Op_Group(Op_Group),
        FOREIGN KEY (Work_Center) REFERENCES Work_Center(Work_Center)
    );
    
    CREATE INDEX idx_JobOp_Job ON Job_Operation(Job);
    CREATE INDEX idx_JobOp_OpGroup ON Job_Operation(Op_Group);
    CREATE INDEX idx_JobOp_WorkCenter ON Job_Operation(Work_Center);
    CREATE INDEX idx_JobOp_status ON Job_Operation(operation_status);
END
GO

-- ============================================================================
-- TABLA: Emp_Assignment (Asignaciones de Empleados)
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Emp_Assignment')
BEGIN
    CREATE TABLE Emp_Assignment (
        Assignment_ID BIGINT PRIMARY KEY IDENTITY(1,1),
        Employee VARCHAR(50) NOT NULL,
        Job_Operation VARCHAR(100),  -- Operación específica (NULL si es grupo)
        Op_Group VARCHAR(50),        -- Grupo (NULL si es operación standalone)
        Work_Center VARCHAR(100) NOT NULL,
        Status VARCHAR(50),  -- Assigned, In_Progress, Completed, Closed
        Last_Updated DATETIME2 DEFAULT GETUTCDATE(),
        Assigned_Date DATETIME2 DEFAULT GETUTCDATE(),
        Completed_Date DATETIME2 NULL,
        
        FOREIGN KEY (Employee) REFERENCES Employee(Employee),
        FOREIGN KEY (Job_Operation) REFERENCES Job_Operation(Job_Operation),
        FOREIGN KEY (Op_Group) REFERENCES Op_Group(Op_Group),
        FOREIGN KEY (Work_Center) REFERENCES Work_Center(Work_Center)
    );
    
    CREATE INDEX idx_EmpAssign_Employee ON Emp_Assignment(Employee);
    CREATE INDEX idx_EmpAssign_Status ON Emp_Assignment(Status);
    CREATE INDEX idx_EmpAssign_WorkCenter ON Emp_Assignment(Work_Center);
    CREATE INDEX idx_EmpAssign_JobOp ON Emp_Assignment(Job_Operation);
    CREATE INDEX idx_EmpAssign_LastUpdated ON Emp_Assignment(Last_Updated);
END
GO

-- ============================================================================
-- TABLA: Job_Operation_ActualTime (Tiempo Real Registrado)
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Job_Operation_ActualTime')
BEGIN
    CREATE TABLE Job_Operation_ActualTime (
        Record_ID BIGINT PRIMARY KEY IDENTITY(1,1),
        Employee VARCHAR(50) NOT NULL,
        Job VARCHAR(50) NOT NULL,
        Job_Operation VARCHAR(100) NOT NULL,
        Op_Group VARCHAR(50),
        Work_Center VARCHAR(100) NOT NULL,
        Part_Number VARCHAR(100),
        Actual_Run_Hrs DECIMAL(10, 4) NOT NULL,
        Status VARCHAR(50),  -- Completed, Partial
        Record_Date DATETIME2 DEFAULT GETUTCDATE(),
        Recorded_By VARCHAR(100),  -- Identificador del dispositivo/terminal
        
        FOREIGN KEY (Employee) REFERENCES Employee(Employee),
        FOREIGN KEY (Job) REFERENCES Job(Job),
        FOREIGN KEY (Job_Operation) REFERENCES Job_Operation(Job_Operation),
        FOREIGN KEY (Work_Center) REFERENCES Work_Center(Work_Center)
    );
    
    CREATE INDEX idx_JobOpTime_Employee ON Job_Operation_ActualTime(Employee);
    CREATE INDEX idx_JobOpTime_Job ON Job_Operation_ActualTime(Job);
    CREATE INDEX idx_JobOpTime_JobOp ON Job_Operation_ActualTime(Job_Operation);
    CREATE INDEX idx_JobOpTime_WorkCenter ON Job_Operation_ActualTime(Work_Center);
    CREATE INDEX idx_JobOpTime_RecordDate ON Job_Operation_ActualTime(Record_Date);
    CREATE INDEX idx_JobOpTime_DateRange ON Job_Operation_ActualTime(Record_Date, Employee);
END
GO

-- ============================================================================
-- TABLA: Work_Center_Device (Dispositivos asociados a centros de trabajo)
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Work_Center_Device')
BEGIN
    CREATE TABLE Work_Center_Device (
        Device_ID VARCHAR(100) PRIMARY KEY,
        Work_Center VARCHAR(100) NOT NULL,
        Device_Name NVARCHAR(200),
        Device_Type VARCHAR(50),  -- ESP32, PLC, etc
        MAC_Address VARCHAR(20),
        IP_Address VARCHAR(50),
        Last_Heartbeat DATETIME2,
        active BIT DEFAULT 1,
        registered_date DATETIME2 DEFAULT GETUTCDATE(),
        
        FOREIGN KEY (Work_Center) REFERENCES Work_Center(Work_Center)
    );
    
    CREATE INDEX idx_Device_WorkCenter ON Work_Center_Device(Work_Center);
    CREATE INDEX idx_Device_active ON Work_Center_Device(active);
END
GO

-- ============================================================================
-- VISTA: V_Active_Assignments_By_WorkCenter
-- (Asignaciones activas por centro de trabajo)
-- ============================================================================
CREATE OR ALTER VIEW V_Active_Assignments_By_WorkCenter AS
SELECT 
    asig.Assignment_ID,
    asig.Employee,
    e.First_Name,
    e.Last_Name,
    e.shift AS employee_shift_code,
    s.Shift_Name AS employee_shift_name,
    asig.Op_Group,
    asig.Job_Operation,
    asig.Work_Center,
    asig.Status,
    asig.Last_Updated,
    
    -- Datos de la operación
    CASE 
        WHEN asig.Job_Operation IS NOT NULL THEN job_op.Est_Run_Hrs
        ELSE NULL
    END AS Est_Run_Hrs,
    
    CASE 
        WHEN asig.Job_Operation IS NOT NULL THEN job_op.Job
        ELSE NULL
    END AS Job,
    
    CASE 
        WHEN asig.Job_Operation IS NOT NULL THEN job_op.Description
        ELSE og.Name
    END AS Description,
    
    og.Name AS OpGroupName,
    
    -- Datos de la orden
    j.Order_Quantity,
    j.Part_Number,
    j.Due_Date,
    
    -- Identificar si es grupo
    CASE 
        WHEN asig.Op_Group IS NOT NULL AND asig.Job_Operation IS NULL THEN 1
        ELSE 0
    END AS es_grupo

FROM Emp_Assignment asig
INNER JOIN Employee e ON asig.Employee = e.Employee
LEFT JOIN shift s ON e.shift = s.shift
LEFT JOIN Job_Operation job_op ON asig.Job_Operation = job_op.Job_Operation
LEFT JOIN Op_Group og ON asig.Op_Group = og.Op_Group
LEFT JOIN Job j ON COALESCE(job_op.Job, NULL) = j.Job

WHERE asig.Status IN ('Assigned', 'In_Progress')
  AND e.active = 1;
GO

-- ============================================================================
-- VISTA: V_WorkCenter_Performance
-- (Rendimiento del centro de trabajo)
-- ============================================================================
CREATE OR ALTER VIEW V_WorkCenter_Performance AS
SELECT 
    wc.Work_Center,
    wc.Description,
    COUNT(DISTINCT asig.Employee) AS Active_Employees,
    COUNT(DISTINCT asig.Job_Operation) AS Operations_In_Progress,
    AVG(CAST(jat.Actual_Run_Hrs AS FLOAT)) AS Avg_Actual_Hours,
    MAX(jat.Record_Date) AS Last_Activity,
    SUM(jat.Actual_Run_Hrs) AS Total_Hours_Today
    
FROM Work_Center wc
LEFT JOIN Emp_Assignment asig ON wc.Work_Center = asig.Work_Center 
    AND asig.Status IN ('Assigned', 'In_Progress')
LEFT JOIN Job_Operation_ActualTime jat ON wc.Work_Center = jat.Work_Center 
    AND CAST(jat.Record_Date AS DATE) = CAST(GETUTCDATE() AS DATE)

WHERE wc.active = 1

GROUP BY wc.Work_Center, wc.Description;
GO

-- ============================================================================
-- STORED PROCEDURE: sp_Get_Active_Assignments
-- (Obtener asignaciones activas para un centro de trabajo)
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_Get_Active_Assignments
    @WorkCenter VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        asig.Employee,
        e.First_Name,
        e.Last_Name,
        e.shift AS employee_shift_code,
        s.Shift_Name AS employee_shift_name,
        asig.Op_Group,
        asig.Job_Operation,
        asig.Last_Updated,
        asig.Status,
        
        CASE 
            WHEN asig.Job_Operation IS NOT NULL THEN job_op.Est_Run_Hrs
            ELSE NULL
        END AS Est_Run_Hrs,
        
        CASE 
            WHEN asig.Job_Operation IS NOT NULL THEN job_op.Job
            ELSE NULL
        END AS Job,
        
        CASE 
            WHEN asig.Job_Operation IS NOT NULL THEN job_op.Description
            ELSE og.Name
        END AS Description,
        
        og.Name AS OpGroupName,
        asig.Work_Center,
        j.Order_Quantity,
        j.Part_Number,
        
        CASE 
            WHEN asig.Op_Group IS NOT NULL AND asig.Job_Operation IS NULL THEN 1
            ELSE 0
        END AS es_grupo
    
    FROM Emp_Assignment asig
    INNER JOIN Employee e ON asig.Employee = e.Employee
    LEFT JOIN shift s ON e.shift = s.shift
    LEFT JOIN Job_Operation job_op ON asig.Job_Operation = job_op.Job_Operation
    LEFT JOIN Op_Group og ON asig.Op_Group = og.Op_Group
    LEFT JOIN Job j ON COALESCE(job_op.Job, NULL) = j.Job
    
    WHERE asig.Work_Center = @WorkCenter
        AND asig.Status <> 'Closed'
        AND e.active = 1
    
    ORDER BY asig.Employee, asig.Last_Updated DESC;
END
GO

-- ============================================================================
-- STORED PROCEDURE: sp_Record_Actual_Time
-- (Guardar tiempo actual de operación)
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_Record_Actual_Time
    @Employee VARCHAR(50),
    @Job VARCHAR(50),
    @Job_Operation VARCHAR(100),
    @Work_Center VARCHAR(100),
    @Part_Number VARCHAR(100),
    @Actual_Run_Hrs DECIMAL(10, 4),
    @Status VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Validar que la operación existe
        IF NOT EXISTS (SELECT 1 FROM Job_Operation WHERE Job_Operation = @Job_Operation)
        BEGIN
            RAISERROR('Job_Operation not found', 16, 1);
        END
        
        -- Insertar registro de tiempo
        INSERT INTO Job_Operation_ActualTime 
            (Employee, Job, Job_Operation, Work_Center, Part_Number, Actual_Run_Hrs, Status)
        VALUES 
            (@Employee, @Job, @Job_Operation, @Work_Center, @Part_Number, @Actual_Run_Hrs, @Status);
        
        -- Actualizar estado de asignación si está completada
        IF @Status = 'Completed'
        BEGIN
            UPDATE Emp_Assignment
            SET Status = 'Completed', Completed_Date = GETUTCDATE()
            WHERE Employee = @Employee 
              AND Job_Operation = @Job_Operation
              AND Status != 'Closed';
        END
        
        COMMIT TRANSACTION;
        
        SELECT 'OK' AS Result, 'Time recorded successfully' AS Message;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        SELECT 'ERROR' AS Result, ERROR_MESSAGE() AS Message;
    END CATCH
END
GO

-- ============================================================================
-- INSERCIÓN DE DATOS DE PRUEBA
-- ============================================================================

-- Turnos
INSERT INTO shift (shift, Shift_Name, start_time, end_time) VALUES
    ('T1', 'Turno 1 - Mañana', '06:00', '14:00'),
    ('T2', 'Turno 2 - Tarde', '14:00', '22:00'),
    ('T3', 'Turno 3 - Noche', '22:00', '06:00');

-- Centros de Trabajo
INSERT INTO Work_Center (Work_Center, Description, Location, Capacity_Per_Hour, Setup_Time_Minutes) VALUES
    ('TORNO 17', 'Torno CNC 17 - Línea Principal', 'Planta A, Sección 3', 60, 15),
    ('TORNO 18', 'Torno CNC 18 - Línea Principal', 'Planta A, Sección 3', 60, 15),
    ('FRESADORA 1', 'Fresadora CNC 1', 'Planta A, Sección 2', 50, 20);

-- Empleados
INSERT INTO Employee (Employee, First_Name, Last_Name, shift, email) VALUES
    ('EMP001', 'Juan', 'Pérez García', 'T1', 'juan.perez@empresa.com'),
    ('EMP002', 'María', 'López Rodríguez', 'T2', 'maria.lopez@empresa.com'),
    ('EMP003', 'Carlos', 'González Martínez', 'T1', 'carlos.gonzalez@empresa.com'),
    ('EMP004', 'Ana', 'Fernández López', 'T3', 'ana.fernandez@empresa.com');

-- Grupos de Operaciones
INSERT INTO Op_Group (Op_Group, Name, Description, Sequence_Order) VALUES
    ('GRP001', 'Cilindrado', 'Grupo de operaciones de cilindrado', 1),
    ('GRP002', 'Roscado', 'Grupo de operaciones de roscado', 2),
    ('GRP003', 'Acabado', 'Operaciones de acabado final', 3);

-- Órdenes de Trabajo
INSERT INTO Job (Job, Part_Number, Order_Quantity, Customer, Priority, job_status) VALUES
    ('JOB001', 'PT-2024-001', 100, 'Cliente Alfa', 1, 'In_Progress'),
    ('JOB002', 'PT-2024-002', 50, 'Cliente Beta', 2, 'In_Progress'),
    ('JOB003', 'PT-2024-003', 200, 'Cliente Gamma', 1, 'Open');

-- Operaciones de Trabajo
INSERT INTO Job_Operation (Job_Operation, Job, Op_Group, Work_Center, Description, Sequence_Number, Est_Run_Hrs, operation_status) VALUES
    ('OP001', 'JOB001', 'GRP001', 'TORNO 17', 'Cilindrado inicial ø50mm', 1, 2.5, 'In_Progress'),
    ('OP002', 'JOB001', 'GRP002', 'TORNO 17', 'Roscado M20x2.5', 2, 1.5, 'Not_Started'),
    ('OP003', 'JOB001', 'GRP003', 'TORNO 17', 'Acabado y pulido', 3, 1.0, 'Not_Started'),
    ('OP004', 'JOB002', 'GRP001', 'TORNO 18', 'Cilindrado ø30mm', 1, 3.0, 'In_Progress'),
    ('OP005', 'JOB003', 'GRP001', 'TORNO 17', 'Cilindrado ø40mm', 1, 2.0, 'Not_Started');

-- Asignaciones Activas
INSERT INTO Emp_Assignment (Employee, Job_Operation, Op_Group, Work_Center, Status, Assigned_Date) VALUES
    ('EMP001', 'OP001', 'GRP001', 'TORNO 17', 'In_Progress', GETUTCDATE()),
    ('EMP002', 'OP002', 'GRP002', 'TORNO 17', 'Assigned', GETUTCDATE()),
    ('EMP003', 'OP004', NULL, 'TORNO 18', 'In_Progress', GETUTCDATE()),
    ('EMP004', 'OP005', 'GRP001', 'TORNO 17', 'Assigned', GETUTCDATE());

-- Dispositivos registrados
INSERT INTO Work_Center_Device (Device_ID, Work_Center, Device_Name, Device_Type, MAC_Address, IP_Address) VALUES
    ('ESP32-TORNO17-001', 'TORNO 17', 'Horómetro Torno 17', 'ESP32', 'AA:BB:CC:DD:EE:01', '192.168.1.150'),
    ('ESP32-TORNO18-001', 'TORNO 18', 'Horómetro Torno 18', 'ESP32', 'AA:BB:CC:DD:EE:02', '192.168.1.151');

PRINT 'Database ERP_Production created successfully with industrial work center data!';
PRINT 'Tables: Employee, shift, Work_Center, Job, Op_Group, Job_Operation, Emp_Assignment, Job_Operation_ActualTime';
PRINT 'Sample data loaded for TORNO 17 center';