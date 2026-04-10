USE ERP_Production;
GO

-- Insertar Empleados
INSERT INTO Employees (Employee, First_Name, Last_Name) VALUES 
('E001', 'Ivan', 'Mecatrónico'),
('E002', 'Maria', 'Garcia'),
('E003', 'Luis', 'Perez');

-- Insertar Grupos
INSERT INTO Op_Groups (Op_Group, Name) VALUES 
('GRP-001', 'Lote Pernos Especiales'),
('GRP-002', 'Ejes de Transmisión');

-- Insertar Jobs y Cantidades (Meta total)
INSERT INTO Jobs (Job, Order_Quantity) VALUES 
('JOB-A1', 10), ('JOB-A2', 15), ('JOB-A3', 25), -- GRP-001 (Total 50)
('JOB-B1', 100), ('JOB-B2', 100),               -- GRP-002 (Total 200)
('JOB-IND-01', 5), ('JOB-IND-02', 12),          -- Individuales
('JOB-OTRO', 1000);                             -- De otro Work Center

-- Insertar Operaciones para TORNO 17
INSERT INTO Job_Operations (Job, Job_Operation, Description, Work_Center, Op_Group, Status, Est_Run_Hrs) VALUES 
-- Caso GRUPO 1 (3 Jobs concatenados)
('JOB-A1', 'OP-10', 'Rosca Fina 1/2', 'TORNO 17', 'GRP-001', 'Assigned', 1.5),
('JOB-A2', 'OP-10', 'Rosca Fina 1/2', 'TORNO 17', 'GRP-001', 'Assigned', 2.0),
('JOB-A3', 'OP-10', 'Rosca Fina 1/2', 'TORNO 17', 'GRP-001', 'Assigned', 3.0),

-- Caso GRUPO 2 (2 Jobs concatenados)
('JOB-B1', 'OP-20', 'Desbaste de Eje', 'TORNO 17', 'GRP-002', 'Assigned', 5.0),
('JOB-B2', 'OP-20', 'Desbaste de Eje', 'TORNO 17', 'GRP-002', 'Assigned', 5.0),

-- Caso INDIVIDUALES (Sin Grupo)
('JOB-IND-01', 'OP-05', 'Corte Inicial', 'TORNO 17', NULL, 'Assigned', 0.5),
('JOB-IND-02', 'OP-15', 'Pulido Espejo', 'TORNO 17', NULL, 'Assigned', 1.2),

-- Caso OTRO WORK CENTER (No debería aparecer en el Torno 17)
('JOB-OTRO', 'OP-99', 'Fresado Externo', 'FRESADORA 02', NULL, 'Assigned', 10.0);
GO