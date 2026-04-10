-- 1. Crear la Base de Datos
CREATE DATABASE ERP_Production;
GO

USE ERP_Production;
GO

-- 2. Tabla de Empleados (Para la selección inicial)
CREATE TABLE Employees (
    Employee VARCHAR(50) PRIMARY KEY,
    First_Name VARCHAR(50),
    Last_Name VARCHAR(50)
);

-- 3. Tabla de Grupos Operacionales
CREATE TABLE Op_Groups (
    Op_Group VARCHAR(50) PRIMARY KEY,
    Name VARCHAR(100)
);

-- 4. Tabla de Cabecera de Jobs (Para las cantidades)
CREATE TABLE Jobs (
    Job VARCHAR(50) PRIMARY KEY,
    Order_Quantity INT
);

-- 5. Tabla de Operaciones (El corazón del filtro)
CREATE TABLE Job_Operations (
    Job_Operation_ID INT PRIMARY KEY IDENTITY(1,1),
    Job VARCHAR(50),
    Job_Operation VARCHAR(50),
    Description VARCHAR(100),
    Work_Center VARCHAR(50),
    Op_Group VARCHAR(50),
    Status VARCHAR(20),
    Est_Run_Hrs FLOAT,
    FOREIGN KEY (Job) REFERENCES Jobs(Job),
    FOREIGN KEY (Op_Group) REFERENCES Op_Groups(Op_Group)
);

-- 6. Tabla de Logs de Producción (Donde se guardará el resultado)
CREATE TABLE Job_Operation_ActualTime (
    Log_ID INT PRIMARY KEY IDENTITY(1,1),
    Employee VARCHAR(50),
    Job VARCHAR(255), -- Longitud extendida para concatenados
    Job_Operation VARCHAR(100),
    Work_Center VARCHAR(50),
    Order_Quantity INT,
    Completed_Quantity INT,
    Motor_Time_Seconds INT,
    Actual_Run_Hrs FLOAT,
    Status VARCHAR(20),
    Record_Date DATETIME DEFAULT GETDATE()
);
GO