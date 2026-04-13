-- 1. CREACIÓN DE LA BASE DE DATOS
USE [master];
GO

IF EXISTS (SELECT * FROM sys.databases WHERE name = 'ERP_Production')
BEGIN
    ALTER DATABASE [ERP_Production] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [ERP_Production];
END
GO

CREATE DATABASE [ERP_Production];
GO

USE [ERP_Production];
GO

-- 2. TABLA DE EMPLEADOS
-- El script busca: Employee, First_Name, Last_Name y la columna 'active'
CREATE TABLE dbo.Employee (
    Employee VARCHAR(50) PRIMARY KEY,
    First_Name VARCHAR(100) NOT NULL,
    Last_Name VARCHAR(100) NOT NULL,
    active BIT DEFAULT 1
);

-- 3. TABLA DE GRUPOS DE OPERACIÓN (OP_GROUP)
-- El script realiza un LEFT JOIN con esta tabla para agrupar tareas
CREATE TABLE dbo.Op_Group (
    Op_Group VARCHAR(50) PRIMARY KEY,
    Name VARCHAR(100) NOT NULL
);

-- 4. TABLA DE TRABAJOS (JOB)
-- Provee el Order_Quantity que el script muestra en pantalla
CREATE TABLE dbo.Job (
    Job VARCHAR(50) PRIMARY KEY,
    Order_Quantity INT NOT NULL
);

-- 5. TABLA DE OPERACIONES (JOB_OPERATION)
-- Contiene la lógica del Work_Center (ej. 'TORNO 17') y los tiempos estimados
CREATE TABLE dbo.Job_Operation (
    Job_Operation VARCHAR(50) PRIMARY KEY,
    Status VARCHAR(20),
    Job VARCHAR(50) NOT NULL REFERENCES dbo.Job(Job),
    Work_Center VARCHAR(50) NOT NULL,
    Description VARCHAR(200),
    Op_Group VARCHAR(50) REFERENCES dbo.Op_Group(Op_Group),
    Est_Run_Hrs FLOAT DEFAULT 0.0
);

-- 6. TABLA DE REGISTRO DE SESIONES (JOB_OPERATION_ACTUALTIME)
-- Donde el script guarda los datos finales al terminar una tarea
CREATE TABLE dbo.Job_Operation_ActualTime (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    Employee VARCHAR(50) NOT NULL,
    Job VARCHAR(200) NOT NULL,
    Job_Operation VARCHAR(100),
    Work_Center VARCHAR(50) NOT NULL,
    Order_Quantity INT,
    Completed_Quantity INT,
    Motor_Time_Seconds INT,
    Actual_Run_Hrs FLOAT,
    Status VARCHAR(20),
    Record_Date DATETIME DEFAULT GETDATE()
);
GO

-- Cambiamos el valor por defecto de la columna Record_Date a hora local
ALTER TABLE dbo.Job_Operation_ActualTime 
DROP CONSTRAINT IF EXISTS DF__Job_Opera__Recor__XXXXXXXX; -- SQL genera un nombre aleatorio

-- Aplicamos GETDATE() para hora local
ALTER TABLE dbo.Job_Operation_ActualTime 
ADD CONSTRAINT DF_RecordDate_Local DEFAULT GETDATE() FOR Record_Date;
GO