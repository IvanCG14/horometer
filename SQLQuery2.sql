USE [ERP_Production];
GO

-- 1. INSERTAR EMPLEADOS ADICIONALES (Para tener variedad en el menú)
INSERT INTO dbo.Employee (Employee, First_Name, Last_Name, active) VALUES 
('EMP002', 'Maria', 'Lopez', 1),
('EMP003', 'Carlos', 'Ruiz', 1),
('EMP004', 'Ana', 'Bermudez', 1);

-- 2. INSERTAR TRABAJOS (Jobs)
INSERT INTO dbo.Job (Job, Order_Quantity) VALUES 
('JOB-002', 1000), ('JOB-003', 150), ('JOB-004', 300), 
('JOB-005', 500), ('JOB-006', 200);

-- 3. INSERTAR GRUPOS DE OPERACIÓN
INSERT INTO dbo.Op_Group (Op_Group, Name) VALUES 
('GRP-ROS', 'Roscado Especial'),
('GRP-ACA', 'Acabado Fino'),
('GRP-PER', 'Perforado');

-- 4. INSERTAR 20 OPERACIONES (Ligadas al TORNO 17 que usa tu script)
-- Se asignan a diferentes combinaciones de Job y Op_Group
INSERT INTO dbo.Job_Operation (Job_Operation, Job, Work_Center, Description, Op_Group, Est_Run_Hrs) VALUES 
('OP-11', 'JOB-2024-001', 'TORNO 17', 'Refrentado', 'GRP-CIL', 1.5),
('OP-12', 'JOB-2024-001', 'TORNO 17', 'Ranurado', 'GRP-CIL', 0.8),
('OP-20', 'JOB-002', 'TORNO 17', 'Roscado Interno', 'GRP-ROS', 3.0),
('OP-21', 'JOB-002', 'TORNO 17', 'Roscado Externo', 'GRP-ROS', 2.5),
('OP-30', 'JOB-003', 'TORNO 17', 'Perforado Base', 'GRP-PER', 1.2),
('OP-31', 'JOB-003', 'TORNO 17', 'Escariado', 'GRP-PER', 0.5),
('OP-40', 'JOB-004', 'TORNO 17', 'Pulido Espejo', 'GRP-ACA', 4.0),
('OP-41', 'JOB-004', 'TORNO 17', 'Moleteado', 'GRP-ACA', 1.0),
('OP-50', 'JOB-005', 'TORNO 17', 'Desbaste Pesado', 'GRP-CIL', 5.0),
('OP-51', 'JOB-005', 'TORNO 17', 'Corte de Material', 'GRP-CIL', 0.3),
('OP-60', 'JOB-006', 'TORNO 17', 'Centrado', 'GRP-PER', 0.2),
('OP-61', 'JOB-006', 'TORNO 17', 'Chaflanado', 'GRP-ACA', 0.6),
('OP-13', 'JOB-2024-001', 'TORNO 17', 'Limpieza', 'GRP-ACA', 0.4),
('OP-22', 'JOB-002', 'TORNO 17', 'Verificación Dim.', 'GRP-ACA', 0.5),
('OP-23', 'JOB-002', 'TORNO 17', 'Ajuste de Rosca', 'GRP-ROS', 1.1),
('OP-32', 'JOB-003', 'TORNO 17', 'Avellanado', 'GRP-PER', 0.7),
('OP-42', 'JOB-004', 'TORNO 17', 'Rectificado', 'GRP-ACA', 2.2),
('OP-52', 'JOB-005', 'TORNO 17', 'Torneado Cónico', 'GRP-CIL', 3.5),
('OP-62', 'JOB-006', 'TORNO 17', 'Marcado Laser', 'GRP-ACA', 0.1),
('OP-14', 'JOB-2024-001', 'TORNO 17', 'Inspección Final', 'GRP-ACA', 0.5);
GO