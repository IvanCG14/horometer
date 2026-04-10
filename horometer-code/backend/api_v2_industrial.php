<?php
/**
 * API Intermedia v2 - Smart Hour Meter (Modo Industrial)
 * Consulta asignaciones activas del centro de trabajo
 * URL: http://servidor/api/log-mecanizado
 * 
 * ACCIONES:
 *  ?action=getAssignments&workCenter=TORNO_17  → Asignaciones activas
 *  POST con JSON                                → Guardar tiempo actual
 */

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

// Configuración de conexión a SQL Server
$serverName = "192.168.1.50\\SQLEXPRESS";
$connectionInfo = array(
    "UID" => "sa",
    "PWD" => "tu_contraseña",
    "Database" => "ERP_Production",  // Cambio de BD
    "LoginTimeout" => 5,
    "Encrypt" => false,
    "TrustServerCertificate" => false
);

// Función auxiliar de respuesta
function respondJSON($status, $message, $data = null) {
    http_response_code($status === "success" ? 200 : 400);
    echo json_encode([
        "status" => $status,
        "message" => $message,
        "data" => $data,
        "timestamp" => date('Y-m-d H:i:s')
    ]);
    exit;
}

// Función para logging de errores SQL
function logSQLError($context) {
    $errors = sqlsrv_errors();
    error_log("[" . date('Y-m-d H:i:s') . "] SQL Error in $context: " . json_encode($errors));
    return $errors;
}

// ============================================================================
// ACCIÓN: Obtener asignaciones activas del centro de trabajo
// ============================================================================
if ($_REQUEST['action'] === 'getAssignments') {
    try {
        // Validar parámetro obligatorio
        $workCenter = isset($_REQUEST['workCenter']) ? trim($_REQUEST['workCenter']) : null;
        
        if (!$workCenter) {
            respondJSON("error", "workCenter parameter is required");
        }
        
        $conn = sqlsrv_connect($serverName, $connectionInfo);
        if (!$conn) {
            throw new Exception("SQL Server connection failed: " . json_encode(sqlsrv_errors()));
        }
        
        // ====================================================================
        // CONSULTA SQL INDUSTRIAL - ASIGNACIONES ACTIVAS
        // ====================================================================
        $query = "SELECT 
            asig.Employee, 
            e.First_Name,
            e.Last_Name,
            e.shift AS employee_shift_code,
            s.Shift_Name AS employee_shift_name,
            asig.Op_Group, 
            asig.Job_Operation,
            asig.Last_Updated,
            asig.Status,
            
            -- Tiempo estimado de la operación
            CASE 
                WHEN asig.Job_Operation IS NOT NULL THEN job_op.Est_Run_Hrs
                ELSE job_group.Est_Run_Hrs
            END AS Est_Run_Hrs,
       
            CASE 
                WHEN asig.Job_Operation IS NOT NULL THEN job_op.Job
                ELSE job_group.Job
            END AS Job,

            -- Descripción (operación o grupo)
            CASE 
                WHEN asig.Job_Operation IS NOT NULL THEN job_op.Description
                ELSE job_group.Description
            END AS Description,
            
            og.Name AS OpGroupName,

            -- Work Center / Centro de trabajo
            CASE 
                WHEN asig.Job_Operation IS NOT NULL THEN job_op.Work_Center
                ELSE job_group.Work_Center
            END AS Work_Center,

            -- Orden de secuencia
            j.Order_Quantity,
            j.Part_Number,
            
            -- Identificar si es grupo (1=grupo, 0=operación individual)
            CASE 
                WHEN asig.Op_Group IS NOT NULL AND asig.Job_Operation IS NULL THEN 1
                ELSE 0
            END AS es_grupo
        
        FROM dbo.Emp_Assignment asig
        INNER JOIN dbo.Employee e ON asig.Employee = e.Employee
        LEFT JOIN dbo.shift s ON e.shift = s.shift
        
        -- Para operaciones individuales (que no son grupo)
        LEFT JOIN dbo.Job_Operation job_op ON asig.Job_Operation = job_op.Job_Operation
        
        -- Para grupos: JOIN con Job_Operation para obtener CADA operación del grupo
        LEFT JOIN dbo.Job_Operation job_group ON asig.Op_Group = job_group.Op_Group
        LEFT JOIN dbo.Op_Group og ON asig.Op_Group = og.Op_Group
        LEFT JOIN dbo.Job j ON COALESCE(job_op.Job, job_group.Job) = j.Job
        
        -- Filtros: Centro de trabajo específico y asignación activa
        WHERE (job_op.Work_Center = ? OR job_group.Work_Center = ?) 
            AND asig.Status <> 'Closed' 
        
        ORDER BY asig.Employee, asig.Last_Updated DESC";
        
        $params = array($workCenter, $workCenter);
        $result = sqlsrv_query($conn, $query, $params);
        
        if (!$result) {
            throw new Exception("Query execution failed: " . json_encode(logSQLError("getAssignments")));
        }
        
        $assignments = array();
        $rowCount = 0;
        
        while ($row = sqlsrv_fetch_array($result, SQLSRV_FETCH_ASSOC)) {
            $rowCount++;
            
            // Convertir tipos de datos
            $assignment = array(
                "Employee" => $row['Employee'],
                "First_Name" => $row['First_Name'],
                "Last_Name" => $row['Last_Name'],
                "employee_shift_code" => $row['employee_shift_code'],
                "employee_shift_name" => $row['employee_shift_name'] ?: "N/A",
                "Op_Group" => $row['Op_Group'],
                "Job_Operation" => $row['Job_Operation'],
                "Last_Updated" => $row['Last_Updated'] ? $row['Last_Updated']->format('Y-m-d H:i:s') : date('Y-m-d H:i:s'),
                "Status" => $row['Status'],
                "Est_Run_Hrs" => floatval($row['Est_Run_Hrs']) ?: 0.0,
                "Job" => $row['Job'],
                "Description" => $row['Description'],
                "OpGroupName" => $row['OpGroupName'] ?: "N/A",
                "Work_Center" => $row['Work_Center'],
                "Order_Quantity" => intval($row['Order_Quantity']) ?: 0,
                "Part_Number" => $row['Part_Number'],
                "es_grupo" => intval($row['es_grupo'])
            );
            
            $assignments[] = $assignment;
        }
        
        sqlsrv_free_stmt($result);
        sqlsrv_close($conn);
        
        if ($rowCount === 0) {
            respondJSON("warning", "No active assignments found for work center: $workCenter", array(
                "assignments" => array(),
                "workCenter" => $workCenter,
                "rowCount" => 0
            ));
        }
        
        respondJSON("success", "Retrieved $rowCount active assignment(s)", array(
            "assignments" => $assignments,
            "workCenter" => $workCenter,
            "rowCount" => $rowCount
        ));
        
    } catch (Exception $e) {
        respondJSON("error", "Error retrieving assignments: " . $e->getMessage());
    }
}

// ============================================================================
// ACCIÓN: Guardar registro de tiempo actual (POST)
// ============================================================================
else if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    try {
        $jsonData = file_get_contents("php://input");
        $data = json_decode($jsonData, true);
        
        if (!$data) {
            throw new Exception("Invalid JSON received");
        }
        
        // Campos requeridos (estructura ERP)
        $required = ['Employee', 'Job', 'Job_Operation', 'Work_Center', 
                     'Part_Number', 'Actual_Run_Hrs', 'Status'];
        
        foreach ($required as $field) {
            if (!isset($data[$field]) || $data[$field] === '') {
                throw new Exception("Required field missing: $field");
            }
        }
        
        $employee = $data['Employee'];
        $job = $data['Job'];
        $jobOperation = $data['Job_Operation'];
        $opGroup = isset($data['Op_Group']) ? $data['Op_Group'] : NULL;
        $workCenter = $data['Work_Center'];
        $partNumber = $data['Part_Number'];
        $actualRunHrs = floatval($data['Actual_Run_Hrs']);
        $status = $data['Status'];
        $timestamp = isset($data['Timestamp']) ? intval($data['Timestamp']) : time();
        
        // Validaciones de negocio
        if ($actualRunHrs < 0) {
            throw new Exception("Actual_Run_Hrs cannot be negative");
        }
        
        if ($actualRunHrs > 24) {
            throw new Exception("Actual_Run_Hrs cannot exceed 24 hours");
        }
        
        $conn = sqlsrv_connect($serverName, $connectionInfo);
        if (!$conn) {
            throw new Exception("SQL Server connection failed");
        }
        
        // Obtener IDs de tablas relacionadas
        // 1. Verificar que el empleado existe
        $queryEmp = "SELECT Employee FROM dbo.Employee WHERE Employee = ?";
        $resultEmp = sqlsrv_query($conn, $queryEmp, array($employee));
        
        if (!$resultEmp || !sqlsrv_fetch_array($resultEmp, SQLSRV_FETCH_ASSOC)) {
            throw new Exception("Employee not found: $employee");
        }
        sqlsrv_free_stmt($resultEmp);
        
        // 2. Verificar que la operación existe
        $queryJobOp = "SELECT Job_Operation FROM dbo.Job_Operation WHERE Job_Operation = ?";
        $resultJobOp = sqlsrv_query($conn, $queryJobOp, array($jobOperation));
        
        if (!$resultJobOp || !sqlsrv_fetch_array($resultJobOp, SQLSRV_FETCH_ASSOC)) {
            throw new Exception("Job_Operation not found: $jobOperation");
        }
        sqlsrv_free_stmt($resultJobOp);
        
        // 3. Verificar que el Job existe
        $queryJob = "SELECT Job FROM dbo.Job WHERE Job = ?";
        $resultJob = sqlsrv_query($conn, $queryJob, array($job));
        
        if (!$resultJob || !sqlsrv_fetch_array($resultJob, SQLSRV_FETCH_ASSOC)) {
            throw new Exception("Job not found: $job");
        }
        sqlsrv_free_stmt($resultJob);
        
        // Insertar o actualizar registro de tiempo actual
        // Tabla: Job_Operation_ActualTime (o similar según tu diseño)
        $insertQuery = "INSERT INTO dbo.Job_Operation_ActualTime 
                       (Employee, Job, Job_Operation, Op_Group, Work_Center, 
                        Part_Number, Actual_Run_Hrs, Status, Record_Date)
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?, CONVERT(datetime2, GETUTCDATE()))";
        
        $insertParams = array(
            $employee,
            $job,
            $jobOperation,
            $opGroup,
            $workCenter,
            $partNumber,
            $actualRunHrs,
            $status
        );
        
        $insertResult = sqlsrv_query($conn, $insertQuery, $insertParams);
        
        if (!$insertResult) {
            $err = logSQLError("INSERT actual time");
            throw new Exception("Failed to insert actual time record: " . json_encode($err));
        }
        
        // Actualizar estado de la asignación si está completada
        if ($status === 'Completed') {
            $updateQuery = "UPDATE dbo.Emp_Assignment 
                           SET Status = 'Completed', Last_Updated = GETUTCDATE()
                           WHERE Employee = ? AND Job_Operation = ?";
            
            $updateParams = array($employee, $jobOperation);
            $updateResult = sqlsrv_query($conn, $updateQuery, $updateParams);
            
            if (!$updateResult) {
                // Log pero no fallar (ya guardamos el tiempo)
                logSQLError("UPDATE assignment status");
            }
        }
        
        sqlsrv_close($conn);
        
        respondJSON("success", "Actual time recorded successfully", array(
            "Employee" => $employee,
            "Job" => $job,
            "Job_Operation" => $jobOperation,
            "Actual_Run_Hrs" => $actualRunHrs,
            "Status" => $status
        ));
        
    } catch (Exception $e) {
        respondJSON("error", $e->getMessage());
    }
}

// Método no permitido
else {
    http_response_code(405);
    respondJSON("error", "Method not allowed");
}
?>