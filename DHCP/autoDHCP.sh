#!/bin/bash

# ----------------------------------------------------------
# Script para automatizar la inserción de dispositivos en dhcpd.conf
# Uso: ./autoDHCP.sh [--dry-run] <archivo_csv> <archivo_conf>
#
# Opciones:
#   --dry-run   Simula la ejecución sin modificar archivos ni reiniciar servicios
#
# Formato CSV esperado (separado por ';'):
#   Nombre;MAC;Ámbito
#   Servidor-Web;AA:BB:CC:DD:EE:FF;Server
# ----------------------------------------------------------

# ========================
#        COLORES
# ========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ========================
#      FUNCIONES
# ========================

msg_ok()    { echo -e "${GREEN}✔ $1${NC}"; }
msg_warn()  { echo -e "${YELLOW}⚠ $1${NC}"; }
msg_error() { echo -e "${RED}✖ $1${NC}"; }
msg_info()  { echo -e "${CYAN}ℹ $1${NC}"; }

# Función portable para formatear timestamps (Linux y macOS)
format_time() {
    local ts="$1" fmt="$2"
    date -d "@$ts" +"$fmt" 2>/dev/null || date -r "$ts" +"$fmt" 2>/dev/null || echo "N/A"
}

# Validar formato de dirección MAC (XX:XX:XX:XX:XX:XX)
validar_mac() {
    [[ "$1" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]
}

# Buscar la siguiente IP disponible (sin colisión)
buscar_ip_disponible() {
    local base="$1" siguiente="$2" conf="$3"
    local ip="${base}.${siguiente}"

    while grep -qF "$ip" "$conf"; do
        msg_warn "  IP $ip ya existe en la configuración. Buscando siguiente..." | tee -a "$LOG"
        siguiente=$((siguiente + 1))
        ip="${base}.${siguiente}"
        # Protección contra bucle infinito (máximo .254)
        if [ "$siguiente" -gt 254 ]; then
            echo ""
            return 1
        fi
    done

    echo "$ip"
    return 0
}

# Insertar reserva en la sección correspondiente del archivo de configuración
insertar_reserva() {
    local host="$1" mac="$2" ip="$3" marcador="$4" conf="$5"
    awk -v name="$host" -v mac="$mac" -v ip="$ip" -v mark="$marcador" '
        $0 ~ mark {
            print $0
            print "\thost " name " {"
            print "\t\thardware ethernet " mac ";"
            print "\t\tfixed-address " ip ";"
            print "\t\tdefault-lease-time 315360000;"
            print "\t\tmax-lease-time 315360000;"
            print "\t}\n"
            next
        }1
    ' "$conf" > "$TMP_CONF" && mv "$TMP_CONF" "$conf"
}

# ========================
#   PARSEO DE ARGUMENTOS
# ========================
DRY_RUN=false

if [ "$1" = "--dry-run" ]; then
    DRY_RUN=true
    shift
fi

if [ "$#" -ne 2 ]; then
    echo -e "${BOLD}Uso:${NC} $0 [--dry-run] <archivo_csv> <archivo_conf>"
    echo ""
    echo "  --dry-run   Simula la ejecución sin modificar archivos"
    exit 1
fi

CSV="$1"
CONF="$2"
TMP_CONF="/tmp/dhcpd_conf_tmp.$$"
LOG="/tmp/log_dhcp_$(date +%Y%m%d_%H%M%S).log"

# Limpiar archivos temporales al salir (éxito, error o interrupción)
trap 'rm -f "$TMP_CONF"' EXIT

# ========================
#    VALIDACIONES
# ========================
if [ ! -f "$CSV" ]; then
    msg_error "No se encuentra el archivo CSV: $CSV"
    exit 1
fi
if [ ! -f "$CONF" ]; then
    msg_error "No se encuentra el archivo de configuración: $CONF"
    exit 1
fi

# ========================
#       INICIO
# ========================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BOLD}  autoDHCP — Inserción automatizada de reservas${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

START_TIME=$(date +%s)
echo "Inicio: $(format_time "$START_TIME" '%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"

if $DRY_RUN; then
    msg_warn "MODO DRY-RUN activado: no se realizarán cambios reales"
    echo "[DRY-RUN] Simulación activada" >> "$LOG"
fi

# Crear respaldo del archivo de configuración
if ! $DRY_RUN; then
    BACKUP="${CONF}.bak.$(date +%Y%m%d_%H%M%S)"
    echo "Creando respaldo: $BACKUP" | tee -a "$LOG"
    sudo cp "$CONF" "$BACKUP"
fi

echo ""
msg_info "Contenido del CSV:" | tee -a "$LOG"
cat "$CSV" | tee -a "$LOG"
echo ""

# ========================
#  MAPAS DE CONFIGURACIÓN
# ========================
declare -A ip_base=(
    ["Server"]="192.168.1"
    ["Desktop"]="192.168.2"
    ["Wireless"]="192.168.3"
)
declare -A ip_next=(
    ["Server"]=4
    ["Desktop"]=6
    ["Wireless"]=7
)
declare -A marcadores=(
    ["Server"]="#Reservas Para Servidores"
    ["Desktop"]="#Reservas para Impresoras"
    ["Wireless"]="#Reserva para CamaraIP"
)

# ========================
#  CONTADORES / RESUMEN
# ========================
total_insertados=0
total_saltados_mac_duplicada=0
total_saltados_mac_invalida=0
total_saltados_ambito=0
total_saltados_ip=0
total_saltados_otros=0

# ========================
#   PROCESAMIENTO CSV
# ========================
while IFS=';' read -r nombre mac ambito; do
    # Recortar espacios
    nombre="$(echo "$nombre" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    mac="$(echo "$mac" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    ambito="$(echo "$ambito" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    # Saltar líneas vacías o cabecera
    [ -z "$nombre" ] && continue
    case "$nombre" in
        List*|Nombre*|Name*|Device*) continue ;;
    esac

    echo -e "\n${BOLD}Procesando:${NC} $nombre"
    echo "  MAC:    $mac"
    echo "  Ámbito: $ambito"

    # --- Validar MAC ---
    if [ -z "$mac" ]; then
        msg_warn "  MAC vacía para '$nombre'. Saltando." | tee -a "$LOG"
        ((total_saltados_otros++))
        continue
    fi
    if ! validar_mac "$mac"; then
        msg_error "  MAC inválida: '$mac'. Formato esperado: XX:XX:XX:XX:XX:XX" | tee -a "$LOG"
        ((total_saltados_mac_invalida++))
        continue
    fi

    # --- Validar ámbito ---
    if [ -z "$ambito" ]; then
        msg_warn "  Ámbito vacío para '$nombre'. Saltando." | tee -a "$LOG"
        ((total_saltados_otros++))
        continue
    fi

    base="${ip_base[$ambito]}"
    marcador="${marcadores[$ambito]}"
    if [ -z "$base" ] || [ -z "$marcador" ]; then
        msg_error "  Ámbito desconocido: '$ambito'. Valores válidos: Server, Desktop, Wireless" | tee -a "$LOG"
        ((total_saltados_ambito++))
        continue
    fi

    # --- Comprobar MAC duplicada ---
    if grep -qiF "$mac" "$CONF"; then
        msg_warn "  La MAC $mac ya existe en la configuración. Saltando." | tee -a "$LOG"
        ((total_saltados_mac_duplicada++))
        continue
    fi

    # --- Sanitizar nombre de host ---
    host=$(echo "$nombre" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_.-]/_/g')

    # --- Buscar IP disponible (sin colisiones) ---
    ip=$(buscar_ip_disponible "$base" "${ip_next[$ambito]}" "$CONF")
    if [ -z "$ip" ]; then
        msg_error "  No hay IPs disponibles en el rango $base.x para '$nombre'" | tee -a "$LOG"
        ((total_saltados_ip++))
        continue
    fi
    # Actualizar el siguiente número para este ámbito
    ultimo_octeto="${ip##*.}"
    ip_next[$ambito]=$((ultimo_octeto + 1))

    msg_ok "  Asignando IP: $ip → $host" | tee -a "$LOG"

    # --- Insertar reserva ---
    if $DRY_RUN; then
        msg_info "  [DRY-RUN] Se insertaría: host $host { MAC=$mac, IP=$ip }" | tee -a "$LOG"
    else
        insertar_reserva "$host" "$mac" "$ip" "$marcador" "$CONF"
    fi

    ((total_insertados++))

done < <(tail -n +2 "$CSV")

# ========================
#  VALIDAR Y REINICIAR
# ========================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if ! $DRY_RUN && [ "$total_insertados" -gt 0 ]; then
    msg_info "Validando configuración DHCP..."
    if sudo dhcpd -t -cf "$CONF" 2>/dev/null; then
        msg_ok "Configuración válida. Reiniciando servicio DHCP..."
        sudo systemctl restart isc-dhcp-server 2>/dev/null
        if [ $? -eq 0 ]; then
            msg_ok "Servicio DHCP reiniciado correctamente"
        else
            msg_error "Error al reiniciar el servicio DHCP"
        fi
    else
        msg_error "La configuración tiene errores de sintaxis. Restaurando backup..."
        sudo cp "$BACKUP" "$CONF"
        msg_warn "Archivo restaurado desde: $BACKUP"
    fi | tee -a "$LOG"

    # Comprobar dispositivos activos
    msg_info "Comprobando dispositivos activos..." | tee -a "$LOG"
    activos=0
    total_ips=0
    for ip in $(awk '/fixed-address/ {print $2}' "$CONF" | tr -d ';'); do
        ((total_ips++))
        if ping -c 1 -W 1 "$ip" &>/dev/null; then
            ((activos++))
        fi
    done
    msg_info "Dispositivos activos: $activos / $total_ips" | tee -a "$LOG"
elif $DRY_RUN; then
    msg_warn "DRY-RUN: No se validó ni reinició el servicio DHCP"
else
    msg_info "No se insertaron dispositivos. No es necesario reiniciar."
fi

# ========================
#     RESUMEN FINAL
# ========================
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BOLD}  RESUMEN${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
{
    echo "  Hora de inicio:              $(format_time "$START_TIME" '%H:%M:%S')"
    echo "  Hora de fin:                 $(format_time "$END_TIME" '%H:%M:%S')"
    echo "  Duración:                    ${ELAPSED}s"
    echo "  ──────────────────────────────────────────"
    echo "  Dispositivos insertados:     $total_insertados"
    echo "  Saltados (MAC duplicada):    $total_saltados_mac_duplicada"
    echo "  Saltados (MAC inválida):     $total_saltados_mac_invalida"
    echo "  Saltados (ámbito inválido):  $total_saltados_ambito"
    echo "  Saltados (sin IP disponible):$total_saltados_ip"
    echo "  Saltados (otros):            $total_saltados_otros"
} | tee -a "$LOG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
msg_info "Log completo guardado en: $LOG"