#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Smart Hour Meter v3 - Windows Development Version
Versión para Windows con mocks de GPIO y LCD
Permite desarrollar sin hardware real en Raspberry Pi
"""

import os
import sys
import time
from datetime import datetime, timedelta
from enum import Enum
from dataclasses import dataclass
from typing import List, Optional
import json

# Importación condicional de librerías (solo si están disponibles)
try:
    import pyodbc
    HAS_PYODBC = True
except ImportError:
    HAS_PYODBC = False
    print("[WARNING] pyodbc no instalado - usando modo mock")

# ============================================================================
# MOCKS PARA WINDOWS (Cuando no hay GPIO/I2C real)
# ============================================================================

class MockGPIO:
    """Mock de RPi.GPIO para desarrollo en Windows"""
    
    BCM = "BCM"
    IN = "IN"
    OUT = "OUT"
    LOW = 0
    HIGH = 1
    PUD_UP = "PUD_UP"
    
    @staticmethod
    def setmode(mode):
        print(f"[MOCK GPIO] setmode({mode})")
    
    @staticmethod
    def setup(pin, mode, pull_up_down=None):
        print(f"[MOCK GPIO] setup(pin={pin}, mode={mode}, pull_up_down={pull_up_down})")
    
    @staticmethod
    def input(pin):
        print(f"[MOCK GPIO] input(pin={pin}) → HIGH")
        return MockGPIO.HIGH
    
    @staticmethod
    def output(pin, state):
        print(f"[MOCK GPIO] output(pin={pin}, state={state})")
    
    @staticmethod
    def cleanup():
        print("[MOCK GPIO] cleanup()")
    
    setwarnings = False

# Reemplazar RPi.GPIO con mock si no está disponible
try:
    import RPi.GPIO as GPIO
except (ImportError, RuntimeError):
    GPIO = MockGPIO()
    print("[WINDOWS] Usando GPIO mock para desarrollo")

# ============================================================================
# MÁQUINA DE ESTADOS
# ============================================================================

class SystemState(Enum):
    """Estados del sistema"""
    HOME = 0
    SELECT_EMPLOYEE = 1
    SELECT_TASK = 2
    MONITORING = 3
    INPUT_COMPLETED = 4
    CLOSING = 5

# ============================================================================
# ESTRUCTURAS DE DATOS
# ============================================================================

@dataclass
class Employee:
    """Información del empleado"""
    employee_id: str
    first_name: str
    last_name: str
    
    @property
    def display_name(self) -> str:
        return f"{self.first_name} {self.last_name}"

@dataclass
class TaskGroup:
    """Tarea agrupada o individual"""
    op_group_id: Optional[str]
    op_group_name: str
    jobs: List[str]
    job_operations: List[str]
    order_quantity: int
    estimated_hours: float
    is_group: bool
    
    @property
    def job_display(self) -> str:
        if self.is_group:
            return "-".join(self.jobs)
        else:
            return self.jobs[0] if self.jobs else ""
    
    @property
    def operation_display(self) -> str:
        if self.job_operations:
            return self.job_operations[0]
        return ""

@dataclass
class SessionData:
    """Datos de la sesión actual"""
    employee: Optional[Employee] = None
    selected_task: Optional[TaskGroup] = None
    vfd_running: bool = False
    time_motor_seconds: int = 0
    session_start_time: Optional[datetime] = None
    monitoring_start_time: Optional[datetime] = None
    completed_quantity: int = 0
    
    def reset(self):
        """Limpiar datos de sesión"""
        self.employee = None
        self.selected_task = None
        self.vfd_running = False
        self.time_motor_seconds = 0
        self.session_start_time = None
        self.monitoring_start_time = None
        self.completed_quantity = 0

# ============================================================================
# CLASE LCD - MOCK PARA WINDOWS
# ============================================================================

class LCD20x4:
    """Mock de pantalla LCD para Windows"""
    
    def __init__(self, address=0x27, port=1):
        """Inicializar LCD (mock)"""
        self.address = address
        self.cols = 20
        self.rows = 4
        self.buffer = ["", "", "", ""]
        print(f"[LCD MOCK] Inicializado (dirección: 0x{address:02x})")
    
    def clear(self):
        """Limpiar pantalla"""
        self.buffer = ["", "", "", ""]
        self._print_buffer()
    
    def print(self, text: str, row: int = 0, col: int = 0):
        """Imprimir texto en posición"""
        if row < 4:
            line = text[:self.cols - col]
            self.buffer[row] = line
            self._print_buffer()
    
    def _print_buffer(self):
        """Mostrar buffer en consola"""
        print("\n" + "="*22)
        for i, line in enumerate(self.buffer):
            padded = line.ljust(20)
            print(f"|{padded}|")
        print("="*22 + "\n")

# ============================================================================
# CLASE GPIO - WINDOWS
# ============================================================================

class GPIOController:
    """Controlador de GPIO con fallback a mock"""
    
    def __init__(self):
        """Inicializar GPIO"""
        try:
            GPIO.setmode(GPIO.BCM)
            GPIO.setwarnings(False)
            
            # Configurar pines
            GPIO.setup(17, GPIO.IN, pull_up_down=GPIO.PUD_UP)   # VFD
            GPIO.setup(27, GPIO.IN, pull_up_down=GPIO.PUD_UP)   # BTN UP
            GPIO.setup(22, GPIO.IN, pull_up_down=GPIO.PUD_UP)   # BTN DOWN
            GPIO.setup(23, GPIO.IN, pull_up_down=GPIO.PUD_UP)   # BTN CONFIRM
            
            print("[GPIO] Inicializado correctamente")
        except Exception as e:
            print(f"[GPIO] Error: {e} - Usando modo mock")
        
        # Variables de debounce
        self.last_vfd_state = False
        self.last_vfd_change_time = time.time()
        self.vfd_debounce_time = 0.15
        
        self.btn_debounce_time = 0.05
        self.last_btn_time = {27: 0, 22: 0, 23: 0}
        
        # Para simular en Windows
        self.simulated_button_press = None
        self.simulated_vfd_running = False
    
    def read_vfd_signal(self) -> bool:
        """Leer señal del VFD"""
        # En Windows, usar simulación
        if isinstance(GPIO, MockGPIO):
            return self.simulated_vfd_running
        
        try:
            current_state = GPIO.input(17) == GPIO.LOW
        except:
            current_state = self.simulated_vfd_running
        
        if current_state != self.last_vfd_state:
            self.last_vfd_change_time = time.time()
            self.last_vfd_state = current_state
            return self.last_vfd_state
        
        if (time.time() - self.last_vfd_change_time) > self.vfd_debounce_time:
            return current_state
        
        return self.last_vfd_state
    
    def read_button(self, pin: int) -> bool:
        """Leer botón con debounce"""
        if time.time() - self.last_btn_time[pin] < self.btn_debounce_time:
            return False
        
        try:
            if GPIO.input(pin) == GPIO.LOW:
                self.last_btn_time[pin] = time.time()
                return True
        except:
            # Usar simulación en Windows
            if self.simulated_button_press == pin:
                self.last_btn_time[pin] = time.time()
                self.simulated_button_press = None
                return True
        
        return False
    
    def read_button_up(self) -> bool:
        return self.read_button(27)
    
    def read_button_down(self) -> bool:
        return self.read_button(22)
    
    def read_button_confirm(self) -> bool:
        return self.read_button(23)
    
    def simulate_button_press(self, button_id: int):
        """Simular presión de botón en Windows"""
        self.simulated_button_press = button_id
        print(f"[SIM] Botón {button_id} presionado")
    
    def simulate_vfd_toggle(self):
        """Simular encendido/apagado del motor"""
        self.simulated_vfd_running = not self.simulated_vfd_running
        state = "ON" if self.simulated_vfd_running else "OFF"
        print(f"[SIM] Motor {state}")
    
    def cleanup(self):
        """Limpiar GPIO"""
        try:
            GPIO.cleanup()
        except:
            pass

# ============================================================================
# CLASE DATABASE - MOCK PARA WINDOWS
# ============================================================================

class DatabaseManager:
    """Gestor de BD con fallback a mock"""
    
    def __init__(self):
        """Inicializar conexión"""
        self.conn = None
        self.is_mock = False
        
        # Datos mock para desarrollo
        self.mock_employees = [
            Employee("EMP001", "Juan", "Pérez García"),
            Employee("EMP002", "María", "López Rodríguez"),
            Employee("EMP003", "Carlos", "González Martínez"),
        ]
        
        self.mock_tasks = [
            TaskGroup(
                op_group_id="GRP001",
                op_group_name="Cilindrado",
                jobs=["JOB001", "JOB002"],
                job_operations=["OP001"],
                order_quantity=200,
                estimated_hours=2.5,
                is_group=True
            ),
            TaskGroup(
                op_group_id="GRP002",
                op_group_name="Roscado",
                jobs=["JOB003"],
                job_operations=["OP002"],
                order_quantity=150,
                estimated_hours=1.5,
                is_group=False
            ),
            TaskGroup(
                op_group_id=None,
                op_group_name="Acabado",
                jobs=["JOB004"],
                job_operations=["OP003"],
                order_quantity=100,
                estimated_hours=1.0,
                is_group=False
            ),
        ]
        
        self._connect()
    
    def _connect(self):
        """Conectar a SQL Server (con fallback a mock)"""
        if not HAS_PYODBC:
            print("[BD] pyodbc no disponible - usando modo mock")
            self.is_mock = True
            return
        
        try:
            conn_str = (
                "Driver={ODBC Driver 17 for SQL Server};"
                "Server=localhost\\SQLEXPRESS;"
                "Database=ERP_Production;"
                "Trusted_Connection=yes;"
                "TrustServerCertificate=yes"
            )
            self.conn = pyodbc.connect(conn_str)
            print("[BD] Conectado a SQL Server")

        except Exception as e:
            print(f"[BD] No se pudo conectar: {e}")
            print("[BD] Usando modo mock")
            self.is_mock = True
    
    def is_connected(self) -> bool:
        """Verificar conexión"""
        if self.is_mock:
            return True
        
        try:
            if self.conn:
                cursor = self.conn.cursor()
                cursor.execute("SELECT 1")
                return True
        except:
            pass
        
        return False
    
    def get_employees(self) -> List[Employee]:
        """Obtener empleados"""
        if self.is_mock:
            print(f"[BD MOCK] Retornando {len(self.mock_employees)} empleados")
            return self.mock_employees
        
        # Implementación real para SQL Server
        try:
            cursor = self.conn.cursor()
            cursor.execute("SELECT Employee, First_Name, Last_Name FROM dbo.Employee WHERE active = 1")
            
            employees = []
            for row in cursor.fetchall():
                employees.append(Employee(row[0], row[1], row[2]))
            
            return employees
        except Exception as e:
            print(f"[ERROR] {e}")
            return []
    
    def get_tasks_by_employee(self, employee_id: str) -> List[TaskGroup]:
        """Obtener tareas del empleado"""
        if self.is_mock:
            print(f"[BD MOCK] Retornando {len(self.mock_tasks)} tareas para {employee_id}")
            return self.mock_tasks
        
        # Implementación real para SQL Server
        try:
            cursor = self.conn.cursor()
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
                GROUP BY 
                    og.Op_Group, 
                    og.Name, 
                    jo.Description, 
                    jo.Job_Operation
            """
            cursor.execute(query, ("TORNO 17",))
            
            tasks = []
            for row in cursor.fetchall():
                task = TaskGroup(
                    op_group_id=row[0] if row[0] else None,
                    op_group_name=row[1],
                    jobs=row[2].split('-') if row[2] else [],
                    job_operations=row[3].split('-') if row[3] else [],
                    order_quantity=int(row[4]) if row[4] else 0,
                    estimated_hours=float(row[5]) if row[5] else 0.0,
                    is_group=bool(row[6])
                )
                tasks.append(task)
            
            return tasks
        except Exception as e:
            print(f"[ERROR] {e}")
            return []
    
    def save_session_data(self, session: SessionData) -> bool:
        """Guardar datos de sesión"""
        if self.is_mock:
            print("[BD MOCK] Guardando datos de sesión:")
            print(f"  Employee: {session.employee.employee_id}")
            print(f"  Job: {session.selected_task.job_display}")
            print(f"  Cantidad: {session.completed_quantity}")
            print(f"  Tiempo: {session.time_motor_seconds}s")
            return True
        
        # Implementación real
        try:
            cursor = self.conn.cursor()
            actual_hours = session.time_motor_seconds / 3600.0
            
            cursor.execute(
                """INSERT INTO dbo.Job_Operation_ActualTime 
                   (Employee, Job, Job_Operation, Work_Center, 
                    Order_Quantity, Completed_Quantity, Motor_Time_Seconds,
                    Actual_Run_Hrs, Status, Record_Date)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'Completed', GETDATE())""",
                (session.employee.employee_id,
                 session.selected_task.job_display,
                 session.selected_task.operation_display,
                 "TORNO 17",
                 session.selected_task.order_quantity,
                 session.completed_quantity,
                 session.time_motor_seconds,
                 actual_hours)
            )
            
            self.conn.commit()
            return True
        except Exception as e:
            print(f"[ERROR] {e}")
            return False
    
    def close(self):
        """Cerrar conexión"""
        if self.conn:
            self.conn.close()

# ============================================================================
# CLASE PRINCIPAL - APLICACIÓN (SIMPLIFICADA PARA WINDOWS)
# ============================================================================

class SmartHourMeterApp:
    """Aplicación principal (versión Windows)"""
    
    def __init__(self):
        """Inicializar"""
        self.state = SystemState.HOME
        self.session = SessionData()
        self.employees: List[Employee] = []
        self.tasks: List[TaskGroup] = []
        self.menu_index = 0
        self.quantity_input = 0
        
        # Inicializar componentes
        self.gpio = GPIOController()
        self.lcd = LCD20x4()
        self.db = DatabaseManager()
        
        # Cargar empleados
        self.employees = self.db.get_employees()
        
        print("\n[APP] Aplicación inicializada (Windows Development Mode)\n")
    
    def display_current_state(self):
        """Mostrar estado actual"""
        self.lcd.clear()
        
        if self.state == SystemState.HOME:
            self.lcd.print("HORÓMETRO INDUSTRIAL", 0)
            self.lcd.print("Centro: TORNO 17", 1)
            self.lcd.print("Presione CONFIRMAR", 2)
            self.lcd.print("para iniciar", 3)
        
        elif self.state == SystemState.SELECT_EMPLOYEE:
            self.lcd.print("SELECCIONAR EMPLEADO", 0)
            emp = self.employees[self.menu_index]
            self.lcd.print(f"> {emp.display_name[:18]}", 1)
            self.lcd.print(f"[{self.menu_index + 1}/{len(self.employees)}]", 2)
            self.lcd.print("OK=Confirmar", 3)
        
        elif self.state == SystemState.SELECT_TASK:
            self.lcd.print("SELECCIONAR TAREA", 0)
            if self.tasks:
                task = self.tasks[self.menu_index]
                self.lcd.print(f"> {task.op_group_name[:18]}", 1)
                self.lcd.print(f"Meta: {task.order_quantity}", 2)
                self.lcd.print(f"[{self.menu_index + 1}/{len(self.tasks)}]", 3)

        # Sugerencia de cambio en el bloque MONITORING
        elif self.state == SystemState.MONITORING:
            self.lcd.print(f"TRABAJANDO EN:", 0)
            if self.tasks:
                task = self.tasks[self.menu_index]
                self.lcd.print(f"> {task.op_group_name[:18]}", 1) # Muestra el nombre del grupo
                self.lcd.print("OK=FINALIZAR TAREA", 3)
        
        elif self.state == SystemState.INPUT_COMPLETED:
            self.lcd.print("¿PIEZAS TERMINADAS?", 0)
            self.lcd.print("", 1)
            quantity_str = f"> {self.quantity_input} <"
            self.lcd.print(quantity_str.center(20), 2)
            self.lcd.print("UP/DOWN=Cant OK", 3)
    
    def handle_commands(self, command: str):
        """Manejar comandos de consola en Windows"""
        if command.lower() == "up":
            self.simulate_button_up()
        elif command.lower() == "down":
            self.simulate_button_down()
        elif command.lower() == "confirm":
            self.simulate_button_confirm()
        elif command.lower() == "motor":
            # 1. Detectar si el motor estaba apagado antes del cambio
            was_off = not self.gpio.simulated_vfd_running
            
            # 2. Cambiar el estado del motor
            self.gpio.simulate_vfd_toggle()
            
            # 3. Lógica de cronómetro
            if was_off:
                # Si se encendió, guardamos la hora de inicio en la sesión
                self.session.monitoring_start_time = datetime.now()
                print(f"[DEBUG] Inicio de conteo: {self.session.monitoring_start_time.strftime('%H:%M:%S')}")
            else:
                # Si se apagó, calculamos la diferencia y la sumamos al total
                if self.session.monitoring_start_time:
                    delta = datetime.now() - self.session.monitoring_start_time
                    segundos_ganados = int(delta.total_seconds())
                    self.session.time_motor_seconds += segundos_ganados
                    print(f"[DEBUG] Motor detenido. Sumados {segundos_ganados}s. Total: {self.session.time_motor_seconds}s")
                    self.session.monitoring_start_time = None
        elif command.lower() == "status":
            print(f"\n[STATUS] Estado: {self.state.name}")
            print(f"[STATUS] Empleado: {self.session.employee}")
            print(f"[STATUS] Tarea: {self.session.selected_task}")
            print(f"[STATUS] Tiempo motor: {self.session.time_motor_seconds}s")
        elif command.lower() == "help":
            self.print_help()
        elif command.lower() == "exit":
            return False
        
        return True
    
    def simulate_button_up(self):
        if self.state == SystemState.SELECT_EMPLOYEE:
            self.menu_index = (self.menu_index - 1) % len(self.employees)
        elif self.state == SystemState.SELECT_TASK:
            if self.tasks:
                self.menu_index = (self.menu_index - 1) % len(self.tasks)
        elif self.state == SystemState.INPUT_COMPLETED:
            self.quantity_input += 1
    
    def simulate_button_down(self):
        if self.state == SystemState.SELECT_EMPLOYEE:
            self.menu_index = (self.menu_index + 1) % len(self.employees)
        elif self.state == SystemState.SELECT_TASK:
            if self.tasks:
                self.menu_index = (self.menu_index + 1) % len(self.tasks)
        elif self.state == SystemState.INPUT_COMPLETED:
            if self.quantity_input > 0:
                self.quantity_input -= 1
    
    def simulate_button_confirm(self):
        if self.state == SystemState.HOME:
            if self.employees:
                self.menu_index = 0
                self.state = SystemState.SELECT_EMPLOYEE
        
        elif self.state == SystemState.SELECT_EMPLOYEE:
            self.session.employee = self.employees[self.menu_index]
            self.tasks = self.db.get_tasks_by_employee(self.session.employee.employee_id)
            self.menu_index = 0
            self.state = SystemState.SELECT_TASK
        
        elif self.state == SystemState.SELECT_TASK:
            if self.tasks:
                self.session.selected_task = self.tasks[self.menu_index]
                self.session.session_start_time = datetime.now()
                self.state = SystemState.MONITORING
        
        elif self.state == SystemState.MONITORING:
            self.quantity_input = 0
            self.state = SystemState.INPUT_COMPLETED
        
        elif self.state == SystemState.INPUT_COMPLETED:
            self.session.completed_quantity = self.quantity_input
            self.state = SystemState.CLOSING
            time.sleep(1)
            self.db.save_session_data(self.session)
            self.session.reset()
            self.menu_index = 0
            self.state = SystemState.HOME
    
    def print_help(self):
        """Mostrar ayuda"""
        print("\n" + "="*50)
        print("COMANDOS DISPONIBLES EN WINDOWS:")
        print("="*50)
        print("  up       - Botón arriba")
        print("  down     - Botón abajo")
        print("  confirm  - Botón confirmar")
        print("  motor    - Toggle motor ON/OFF (simular VFD)")
        print("  status   - Ver estado actual")
        print("  help     - Este mensaje")
        print("  exit     - Salir")
        print("="*50 + "\n")
    
    def run_interactive(self):
        """Modo interactivo para Windows"""
        print("\n[APP] Modo Interactivo (Windows)")
        self.print_help()
        
        running = True
        while running:
            self.display_current_state()
            
            try:
                command = input("\n[INPUT] > ").strip().lower()
                running = self.handle_commands(command)
            except KeyboardInterrupt:
                print("\n[APP] Interrumpido por usuario")
                running = False
            except Exception as e:
                print(f"[ERROR] {e}")

# ============================================================================
# PUNTO DE ENTRADA
# ============================================================================

if __name__ == "__main__":
    print("\n" + "="*60)
    print("Smart Hour Meter v3 - WINDOWS DEVELOPMENT VERSION")
    print("="*60)
    print("Nota: Esta versión usa mocks para GPIO y LCD")
    print("Ejecutar en Raspberry Pi para usar hardware real")
    print("="*60 + "\n")
    
    app = SmartHourMeterApp()
    app.run_interactive()
    app.gpio.cleanup()
    app.db.close()
