#!/bin/bash

# ============================================================================
# SCRIPT DE INSTALACIÓN - Smart Hour Meter v3 para Raspberry Pi Zero
# ============================================================================

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   Smart Hour Meter v3 - Instalación en Raspberry Pi Zero     ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Verificar si es root
if [ "$EUID" -ne 0 ]; then
   echo "⚠️  Este script debe ejecutarse con sudo"
   exit 1
fi

echo "[PASO 1] Actualizar sistema..."
apt-get update
apt-get upgrade -y

echo ""
echo "[PASO 2] Instalar dependencias de sistema..."
apt-get install -y \
    python3 \
    python3-pip \
    python3-dev \
    python3-rpi.gpio \
    python3-smbus \
    i2c-tools \
    libi2c-dev \
    unixodbc \
    unixodbc-dev

echo ""
echo "[PASO 3] Instalar librerías Python..."
pip3 install --upgrade pip
pip3 install \
    RPi.GPIO \
    pyodbc \
    smbus2 \
    -q

echo ""
echo "[PASO 4] Verificar I2C y GPIO..."

# Habilitar I2C
if ! grep -q "^dtparam=i2c_arm=on" /boot/config.txt; then
    echo "dtparam=i2c_arm=on" >> /boot/config.txt
    echo "✓ I2C habilitado en config.txt"
else
    echo "✓ I2C ya estaba habilitado"
fi

# Habilitar GPIO
if ! grep -q "^dtoverlay=gpio-ir" /boot/config.txt; then
    echo "✓ GPIO disponible"
fi

echo ""
echo "[PASO 5] Configurar controlador ODBC para SQL Server..."

# Verificar si ya está instalado
if ! odbcinst -q -d -n "ODBC Driver 17 for SQL Server" > /dev/null 2>&1; then
    echo "Installing ODBC Driver 17 for SQL Server..."
    
    # Agregar repositorio Microsoft
    curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
    curl https://packages.microsoft.com/config/debian/11/prod.list > /etc/apt/sources.list.d/mssql-release.list
    apt-get update
    
    # Instalar driver ODBC (aceptar licencia automáticamente)
    ACCEPT_EULA=Y apt-get install -y msodbcsql17 -q
    
    echo "✓ Controlador ODBC instalado"
else
    echo "✓ Controlador ODBC ya estaba instalado"
fi

echo ""
echo "[PASO 6] Crear archivo de configuración..."

cat > /opt/smart_hour_meter/config.ini << 'EOF'
[SQL_SERVER]
Server = 192.168.1.50\SQLEXPRESS
Database = ERP_Production
UID = sa
PWD = tu_contraseña
Port = 1433

[WORK_CENTER]
Name = TORNO 17

[GPIO_PINS]
VFD_Signal = 17
Button_UP = 27
Button_DOWN = 22
Button_CONFIRM = 23

[LCD]
Address = 0x27
Port = 1

[TIMING]
VFD_Debounce_ms = 150
Button_Debounce_ms = 50
Update_Interval_ms = 100
EOF

echo "✓ Archivo de configuración creado en /opt/smart_hour_meter/config.ini"

echo ""
echo "[PASO 7] Crear servicio systemd..."

cat > /etc/systemd/system/smart-hour-meter.service << 'EOF'
[Unit]
Description=Smart Hour Meter v3 - Industrial Timer
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=pi
WorkingDirectory=/opt/smart_hour_meter
ExecStart=/usr/bin/python3 /opt/smart_hour_meter/smart_hour_meter_v3_rpi.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
echo "✓ Servicio systemd creado"

echo ""
echo "[PASO 8] Probar conexión I2C (detectar LCD)..."
i2cdetect -y 1 || echo "⚠️  LCD no detectado en 0x27 (verifica conexión)"

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                  ✓ INSTALACIÓN COMPLETADA                    ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "Próximos pasos:"
echo ""
echo "1. EDITAR CONFIGURACIÓN:"
echo "   sudo nano /opt/smart_hour_meter/config.ini"
echo "   (Cambiar credenciales SQL Server)"
echo ""
echo "2. PRUEBA MANUAL:"
echo "   python3 /opt/smart_hour_meter/smart_hour_meter_v3_rpi.py"
echo ""
echo "3. INICIAR COMO SERVICIO:"
echo "   sudo systemctl start smart-hour-meter"
echo ""
echo "4. HABILITAR EN BOOT:"
echo "   sudo systemctl enable smart-hour-meter"
echo ""
echo "5. VER LOGS:"
echo "   sudo journalctl -u smart-hour-meter -f"
echo ""
echo "¡LISTO! 🚀"
