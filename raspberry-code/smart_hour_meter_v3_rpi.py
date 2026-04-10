#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Smart Hour Meter v3 - Raspberry Pi Zero
Sistema de Horómetro Industrial con Lógica de Grupos de Producción
Conexión directa a SQL Server (sin API intermedia)
"""

import RPi.GPIO as GPIO
import time
import sys
import signal
import threading
from datetime import datetime, timedelta
import pyodbc
from enum import Enum
from dataclasses import dataclass
from typing import List, Optional, Dict

# ============================================================================
# CONFIGURACIÓN DE PINES GPIO
# ============================================================================

PIN_VFD_SIGNAL = 17          # GPIO 17 - Entrada del VFD (HIGH = motor corriendo)
PIN_BTN_UP = 27              # GPIO 27 - Botón arriba
PIN_BTN_DOWN = 22            # GPIO 22 - Botón abajo
PIN_BTN_CONFIRM = 23         # GPIO 23 - Botón confirmar

# ============================================================================
# CONFIGURACIÓN SQL SERVER
# ============================================================================

DB_SERVER = "192.168.1.50\\SQLEXPRESS"  # Cambiar según tu servidor
DB_NAME = "ERP_Production"
DB_USER = "sa"
DB_PASSWORD = "tu_contraseña"  # Cambiar por contraseña real
WORK_CENTER = "TORNO 17"  # Centro de trabajo

# Cadena de conexión ODBC
CONNECTION_STRING = (
    f"Driver={{ODBC Driver 17 for SQL Server}};"
    f"Server={DB_SERVER};"
    f"Database={DB_NAME};"
    f"UID={DB_USER};"
    f"PWD={DB_PASSWORD};"
    f"TrustServerCertificate=yes"
)

# ============================================================================
# MÁQUINA DE ESTADOS
# ============================================================================

class SystemState(Enum):
    """Estados del sistema"""
    HOME = 0                  # Inicio
    SELECT_EMPLOYEE = 1       # Seleccionar empleado
    SELECT_TASK = 2           # Seleccionar tarea (grupo o individual)
    MONITORING = 3            # Monitoreo de tiempo
    INPUT_COMPLETED = 4       # Ingresar cantidad completada
    CLOSING = 5               # Cierre y envío de datos

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
    op_group_id: Optional[str]  # None si es individual
    op_group_name: str          # Nombre a mostrar
    jobs: List[str]             # Lista de Job IDs
    job_operations: List[str]   # Lista de Job_Operation IDs
    order_quantity: int         # Cantidad total a hacer
    estimated_hours: float      # Horas estimadas
    is_group: bool              # True si es grupo, False si es individual
    
    @property
    def job_display(self) -> str:
        """Para envío: concatena jobs con guión si es grupo"""
        if self.is_group:
            return "-".join(self.jobs)
        else:
            return self.jobs[0] if self.jobs else ""
    
    @property
    def operation_display(self) -> str:
        """Operación para identificar en BD"""
        if self.job_operations:
            return self.job_operations[0]
        return ""

@dataclass
class SessionData:
    """Datos de la sesión actual"""
    employee: Optional[Employee] = None
    selected_task: Optional[TaskGroup] = None
    vfd_running: bool = False
    time_motor_seconds: int = 0  # Tiempo total motor encendido
    session_start_time: Optional[datetime] = None
    monitoring_start_time: Optional[datetime] = None
    completed_quantity: int = 0  # Cantidad de piezas completadas
    
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
# CLASE LCD - INTERFAZ CON PANTALLA I2C
# ============================================================================

class LCD20x4:
    """Controlador de pantalla LCD 20x4 vía I2C"""
    
    def __init__(self, address=0x27, port=1):
        """
        Inicializar pantalla LCD
        address: Dirección I2C (típicamente 0x27 o 0x3F)
        port: Puerto I2C (1 para RPi)
        """
        try:
            import smbus2
            self.bus = smbus2.SMBus(port)
            self.address = address
            self.cols = 20
            self.rows = 4
            self._init_lcd()
            print("[LCD] Pantalla iniciada correctamente")
        except Exception as e:
            print(f"[ERROR] No se pudo inicializar LCD: {e}")
            self.bus = None
    
    def _init_lcd(self):
        """Inicialización de pantalla LCD"""
        if not self.bus:
            return
        
        # Secuencia de inicialización estándar para LCD 16x2/20x4
        self.bus.write_byte(self.address, 0x00)
        time.sleep(0.02)
        
        # 4-bit mode
        self._send_command(0x33)
        time.sleep(0.005)
        self._send_command(0x32)
        time.sleep(0.005)
        self._send_command(0x28)
        time.sleep(0.005)
        
        # Display ON/OFF
        self._send_command(0x0C)
        self._send_command(0x01)  # Clear
        time.sleep(0.002)
        
        # Entry mode
        self._send_command(0x06)
    
    def _send_command(self, cmd):
        """Enviar comando a LCD"""
        if not self.bus:
            return
        try:
            self.bus.write_byte(self.address, cmd)
            time.sleep(0.001)
        except:
            pass
    
    def clear(self):
        """Limpiar pantalla"""
        if self.bus:
            self._send_command(0x01)
            time.sleep(0.002)
    
    def print(self, text: str, row: int = 0, col: int = 0):
        """
        Imprimir texto en posición
        row: 0-3 (filas)
        col: 0-19 (columnas)
        """
        if not self.bus:
            print(f"[LCD Row {row}] {text}")
            return
        
        # Posicionar cursor
        if row == 0:
            pos = 0x00 + col
        elif row == 1:
            pos = 0x40 + col
        elif row == 2:
            pos = 0x14 + col
        elif row == 3:
            pos = 0x54 + col
        
        self._send_command(0x80 | pos)
        time.sleep(0.001)
        
        # Enviar texto
        for char in text[:self.cols - col]:
            try:
                self.bus.write_byte(self.address, ord(char))
                time.sleep(0.001)
            except:
                pass

# ============================================================================
# CLASE GPIO - MANEJO DE PINES
# ============================================================================

class GPIOController:
    """Controlador de pines GPIO"""
    
    def __init__(self):
        """Inicializar GPIO"""
        GPIO.setmode(GPIO.BCM)
        GPIO.setwarnings(False)
        
        # Configurar pines
        GPIO.setup(PIN_VFD_SIGNAL, GPIO.IN, pull_up_down=GPIO.PUD_UP)
        GPIO.setup(PIN_BTN_UP, GPIO.IN, pull_up_down=GPIO.PUD_UP)
        GPIO.setup(PIN_BTN_DOWN, GPIO.IN, pull_up_down=GPIO.PUD_UP)
        GPIO.setup(PIN_BTN_CONFIRM, GPIO.IN, pull_up_down=GPIO.PUD_UP)
        
        # Variables de debounce
        self.last_vfd_state = False
        self.last_vfd_change_time = time.time()
        self.vfd_debounce_time = 0.15  # 150ms debounce VFD
        
        self.btn_debounce_time = 0.05  # 50ms debounce botones
        self.last_btn_time = {}
        for pin in [PIN_BTN_UP, PIN_BTN_DOWN, PIN_BTN_CONFIRM]:
            self.last_btn_time[pin] = 0
        
        print("[GPIO] GPIO inicializado correctamente")
    
    def read_vfd_signal(self) -> bool:
        """
        Leer señal del VFD con debounce
        Retorna True si motor está corriendo (LOW = corriendo)
        """
        current_state = GPIO.input(PIN_VFD_SIGNAL) == GPIO.LOW
        
        if current_state != self.last_vfd_state:
            self.last_vfd_change_time = time.time()
            self.last_vfd_state = current_state
            return self.last_vfd_state
        
        if (time.time() - self.last_vfd_change_time) > self.vfd_debounce_time:
            return current_state
        
        return self.last_vfd_state
    
    def read_button(self, pin: int) -> bool:
        """
        Leer botón con debounce
        Retorna True si botón fue presionado
        """
        if time.time() - self.last_btn_time[pin] < self.btn_debounce_time:
            return False
        
        if GPIO.input(pin) == GPIO.LOW:  # Presionado (LOW)
            self.last_btn_time[pin] = time.time()
            return True
        
        return False
    
    def read_button_up(self) -> bool:
        return self.read_button(PIN_BTN_UP)
    
    def read_button_down(self) -> bool:
        return self.read_button(PIN_BTN_DOWN)
    
    def read_button_confirm(self) -> bool:
        return self.read_button(PIN_BTN_CONFIRM)
    
    def cleanup(self):
        """Limpiar GPIO"""
        GPIO.cleanup()

# ============================================================================
# CLASE DATABASE - CONEXIÓN SQL SERVER
# ============================================================================

class DatabaseManager:
    """Gestor de conexión a SQL Server"""
    
    def __init__(self):
        """Inicializar conexión"""
        self.conn = None
        self._connect()
    
    def _connect(self):
        """Conectar a SQL Server"""
        try:
            self.conn = pyodbc.connect(CONNECTION_STRING)
            print("[BD] Conectado a SQL Server correctamente")
        except Exception as e:
            print(f"[ERROR] No se pudo conectar a SQL Server: {e}")
            self.conn = None
    
    def is_connected(self) -> bool:
        """Verificar si hay conexión"""
        try:
            if self.conn:
                cursor = self.conn.cursor()
                cursor.execute("SELECT 1")
                return True
        except:
            self._connect()
        return self.conn is not None
    
    def get_employees(self) -> List[Employee]:
        """Obtener lista de empleados activos"""
        if not self.is_connected():
            print("[ERROR] No hay conexión a BD")
            return []
        
        try:
            cursor = self.conn.cursor()
            query = """
                SELECT Employee, First_Name, Last_Name
                FROM dbo.Employee
                WHERE active = 1
                ORDER BY First_Name, Last_Name
            """
            cursor.execute(query)
            
            employees = []
            for row in cursor.fetchall():
                employees.append(Employee(
                    employee_id=row[0],
                    first_name=row[1],
                    last_name=row[2]
                ))
            
            print(f"[BD] {len(employees)} empleados cargados")
            return employees
        
        except Exception as e:
            print(f"[ERROR] Error al obtener empleados: {e}")
            return []
    
    def get_tasks_by_employee(self, employee_id: str) -> List[TaskGroup]:
        """
        Obtener tareas agrupadas para un empleado
        Agrupa por Op_Group si es_grupo=1
        """
        if not self.is_connected():
            print("[ERROR] No hay conexión a BD")
            return []
        
        try:
            cursor = self.conn.cursor()
            
            # Consulta que agrupa tareas
            query = """
                SELECT DISTINCT
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
            
            print(f"[BD] {len(tasks)} tareas cargadas para {employee_id}")
            return tasks
        
        except Exception as e:
            print(f"[ERROR] Error al obtener tareas: {e}")
            return []
    
    def save_session_data(self, session: SessionData) -> bool:
        """
        Guardar datos de sesión en SQL Server
        Inserta en tabla de tiempo actual
        """
        if not self.is_connected() or not session.employee or not session.selected_task:
            print("[ERROR] Datos de sesión incompletos")
            return False
        
        try:
            cursor = self.conn.cursor()
            
            # Insertar en Job_Operation_ActualTime
            query = """
                INSERT INTO dbo.Job_Operation_ActualTime 
                    (Employee, Job, Job_Operation, Work_Center, Actual_Run_Hrs, 
                     Completed_Quantity, Motor_Time_Seconds, Status, Record_Date)
                VALUES (?, ?, ?, ?, ?, ?, ?, 'Completed', GETUTCDATE())
            """
            
            actual_hours = session.time_motor_seconds / 3600.0  # Convertir segundos a horas
            
            cursor.execute(query, (
                session.employee.employee_id,
                session.selected_task.job_display,
                session.selected_task.operation_display,
                WORK_CENTER,
                actual_hours,
                session.completed_quantity,
                session.time_motor_seconds
            ))
            
            self.conn.commit()
            print(f"[BD] Datos guardados: {session.employee.employee_id} - {session.completed_quantity} piezas")
            return True
        
        except Exception as e:
            print(f"[ERROR] Error al guardar datos: {e}")
            self.conn.rollback()
            return False
    
    def close(self):
        """Cerrar conexión"""
        if self.conn:
            self.conn.close()
            print("[BD] Conexión cerrada")

# ============================================================================
# CLASE PRINCIPAL - APLICACIÓN
# ============================================================================

class SmartHourMeterApp:
    """Aplicación principal del Horómetro Industrial"""
    
    def __init__(self):
        """Inicializar aplicación"""
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
        
        print("[APP] Aplicación inicializada")
    
    def display_home(self):
        """Pantalla de inicio"""
        self.lcd.clear()
        self.lcd.print("HORÓMETRO INDUSTRIAL", 0)
        self.lcd.print("Centro: " + WORK_CENTER, 1)
        self.lcd.print("Presione CONFIRMAR", 2)
        self.lcd.print("para iniciar", 3)
    
    def display_select_employee(self):
        """Menú de selección de empleado"""
        if not self.employees:
            self.lcd.clear()
            self.lcd.print("ERROR: Sin empleados", 1)
            return
        
        self.lcd.clear()
        self.lcd.print("SELECCIONAR EMPLEADO", 0)
        
        # Mostrar empleado actual
        emp = self.employees[self.menu_index]
        self.lcd.print(f"> {emp.display_name[:18]}", 1)
        
        # Índice
        self.lcd.print(f"[{self.menu_index + 1}/{len(self.employees)}]", 2)
        self.lcd.print("OK=Confirmar ESC=Atrás", 3)
    
    def display_select_task(self):
        """Menú de selección de tarea"""
        if not self.tasks:
            self.lcd.clear()
            self.lcd.print("ERROR: Sin tareas", 1)
            return
        
        self.lcd.clear()
        self.lcd.print("SELECCIONAR TAREA", 0)
        
        # Mostrar tarea actual
        task = self.tasks[self.menu_index]
        self.lcd.print(f"> {task.op_group_name[:18]}", 1)
        self.lcd.print(f"Meta: {task.order_quantity}", 2)
        
        # Índice
        self.lcd.print(f"[{self.menu_index + 1}/{len(self.tasks)}]", 3)
    
    def display_monitoring(self):
        """Pantalla de monitoreo"""
        self.lcd.clear()
        self.lcd.print("MONITOREANDO", 0)
        
        # Mostrar empleado
        emp_name = self.session.employee.first_name[:10]
        self.lcd.print(f"Op: {emp_name}", 1)
        
        # Mostrar tiempo
        mins = self.session.time_motor_seconds // 60
        secs = self.session.time_motor_seconds % 60
        time_str = f"Tiempo: {mins:02d}:{secs:02d}"
        self.lcd.print(time_str, 2)
        
        # Progreso
        task = self.session.selected_task
        progress = f"{self.session.completed_quantity}/{task.order_quantity}"
        self.lcd.print(progress, 3)
    
    def display_input_completed(self):
        """Pantalla para ingresar cantidad completada"""
        self.lcd.clear()
        self.lcd.print("¿PIEZAS TERMINADAS HOY?", 0)
        self.lcd.print("", 1)
        
        # Mostrar cantidad seleccionada
        quantity_str = f"> {self.quantity_input} <"
        self.lcd.print(quantity_str.center(20), 2)
        
        self.lcd.print("UP/DOWN: Cantidad OK", 3)
    
    def display_closing(self):
        """Pantalla de cierre"""
        self.lcd.clear()
        self.lcd.print("GUARDANDO DATOS...", 1)
        self.lcd.print("", 2)
        self.lcd.print("", 3)
    
    def update_display(self):
        """Actualizar pantalla según estado"""
        if self.state == SystemState.HOME:
            self.display_home()
        elif self.state == SystemState.SELECT_EMPLOYEE:
            self.display_select_employee()
        elif self.state == SystemState.SELECT_TASK:
            self.display_select_task()
        elif self.state == SystemState.MONITORING:
            self.display_monitoring()
        elif self.state == SystemState.INPUT_COMPLETED:
            self.display_input_completed()
        elif self.state == SystemState.CLOSING:
            self.display_closing()
    
    def handle_input(self):
        """Manejar entrada de botones"""
        if self.gpio.read_button_up():
            self.on_button_up()
        
        if self.gpio.read_button_down():
            self.on_button_down()
        
        if self.gpio.read_button_confirm():
            self.on_button_confirm()
    
    def on_button_up(self):
        """Botón arriba"""
        if self.state == SystemState.SELECT_EMPLOYEE:
            self.menu_index = (self.menu_index - 1) % len(self.employees)
        elif self.state == SystemState.SELECT_TASK:
            self.menu_index = (self.menu_index - 1) % len(self.tasks)
        elif self.state == SystemState.INPUT_COMPLETED:
            self.quantity_input += 1
    
    def on_button_down(self):
        """Botón abajo"""
        if self.state == SystemState.SELECT_EMPLOYEE:
            self.menu_index = (self.menu_index + 1) % len(self.employees)
        elif self.state == SystemState.SELECT_TASK:
            self.menu_index = (self.menu_index + 1) % len(self.tasks)
        elif self.state == SystemState.INPUT_COMPLETED:
            if self.quantity_input > 0:
                self.quantity_input -= 1
    
    def on_button_confirm(self):
        """Botón confirmar"""
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
            # Ir a input de cantidad completada
            self.quantity_input = 0
            self.state = SystemState.INPUT_COMPLETED
        
        elif self.state == SystemState.INPUT_COMPLETED:
            # Confirmar cantidad y guardar
            self.session.completed_quantity = self.quantity_input
            self.state = SystemState.CLOSING
            self.save_and_close()
    
    def update_vfd_monitoring(self):
        """Actualizar monitoreo de motor"""
        if self.state != SystemState.MONITORING:
            return
        
        vfd_state = self.gpio.read_vfd_signal()
        
        if vfd_state and not self.session.vfd_running:
            # Motor acaba de encender
            self.session.vfd_running = True
            self.session.monitoring_start_time = datetime.now()
            print("[VFD] Motor encendido")
        
        elif not vfd_state and self.session.vfd_running:
            # Motor acaba de apagar
            self.session.vfd_running = False
            if self.session.monitoring_start_time:
                elapsed = (datetime.now() - self.session.monitoring_start_time).total_seconds()
                self.session.time_motor_seconds += int(elapsed)
                print(f"[VFD] Motor apagado. Tiempo acumulado: {self.session.time_motor_seconds}s")
    
    def save_and_close(self):
        """Guardar datos y volver a inicio"""
        time.sleep(1)  # Mostrar "Guardando..." por 1 segundo
        
        success = self.db.save_session_data(self.session)
        
        if success:
            self.lcd.clear()
            self.lcd.print("¡DATOS GUARDADOS!", 1)
            self.lcd.print("", 2)
            self.lcd.print("", 3)
            time.sleep(2)
        else:
            self.lcd.clear()
            self.lcd.print("ERROR AL GUARDAR", 1)
            self.lcd.print("", 2)
            self.lcd.print("", 3)
            time.sleep(2)
        
        # Limpiar y volver a HOME
        self.session.reset()
        self.menu_index = 0
        self.state = SystemState.HOME
    
    def run(self):
        """Bucle principal"""
        print("[APP] Iniciando bucle principal...")
        
        try:
            while True:
                # Manejar entrada
                self.handle_input()
                
                # Actualizar monitoreo VFD
                self.update_vfd_monitoring()
                
                # Actualizar pantalla
                self.update_display()
                
                # Delay para no saturar CPU
                time.sleep(0.1)
        
        except KeyboardInterrupt:
            print("\n[APP] Interrumpido por usuario")
        
        finally:
            self.cleanup()
    
    def cleanup(self):
        """Limpiar recursos"""
        print("[APP] Limpiando recursos...")
        self.gpio.cleanup()
        self.db.close()
        print("[APP] Bye!")

# ============================================================================
# PUNTO DE ENTRADA
# ============================================================================

if __name__ == "__main__":
    app = SmartHourMeterApp()
    app.run()
