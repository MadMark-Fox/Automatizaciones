#!/bin/bash
# ============================================
#  Script interactivo para gestionar registros
#  en un archivo de zona DNS (BIND9)
# ============================================

# --- Configuración ---
ZONA_FILE="$(dirname "$0")/db.ejemplo.com"

# --- Colores ---
VERDE='\033[0;32m'
AZUL='\033[0;34m'
AMARILLO='\033[1;33m'
ROJO='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # Sin color

# --- Funciones auxiliares ---
separador() {
    echo -e "${AZUL}══════════════════════════════════════════${NC}"
}

exito() {
    echo -e "\n${VERDE}✔ $1${NC}\n"
}

error() {
    echo -e "\n${ROJO}✘ $1${NC}\n"
}

# Validar formato de IPv4
validar_ipv4() {
    local ip="$1"
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 0
    fi
    return 1
}

# Validar formato de IPv6 (simplificado)
validar_ipv6() {
    local ip="$1"
    if [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$ ]]; then
        return 0
    fi
    return 1
}

# Validar nombre de host
validar_nombre() {
    local nombre="$1"
    if [[ "$nombre" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?$ ]]; then
        return 0
    fi
    return 1
}

# Actualizar el serial del SOA (formato YYYYMMDDNN)
actualizar_serial() {
    local hoy
    hoy=$(date +%Y%m%d)
    local serial_actual
    serial_actual=$(grep -oP '\d{10}(?=\s*;\s*Serial)' "$ZONA_FILE")

    if [[ -z "$serial_actual" ]]; then
        echo -e "${AMARILLO}⚠ No se encontró el serial en el archivo de zona.${NC}"
        return
    fi

    local fecha_serial="${serial_actual:0:8}"
    local num_serial="${serial_actual:8:2}"

    if [[ "$fecha_serial" == "$hoy" ]]; then
        num_serial=$((10#$num_serial + 1))
        num_serial=$(printf "%02d" "$num_serial")
    else
        num_serial="01"
    fi

    local nuevo_serial="${hoy}${num_serial}"
    sed -i.bak "s/$serial_actual/$nuevo_serial/" "$ZONA_FILE"
    echo -e "${CYAN}↻ Serial actualizado: ${serial_actual} → ${nuevo_serial}${NC}"
}

# Mostrar registros actuales
mostrar_registros() {
    separador
    echo -e "${BOLD}📋 Registros actuales en ${ZONA_FILE}:${NC}\n"
    echo -e "${CYAN}"
    grep -v '^\s*;' "$ZONA_FILE" | grep -v '^\s*$' | grep -v '^\$' | grep -v 'SOA' | \
        grep -v 'Serial\|Refresh\|Retry\|Expire\|Negative\|)'
    echo -e "${NC}"
    separador
}

# --- Funciones para añadir registros ---

agregar_registro_a() {
    echo -e "\n${BOLD}➕ Nuevo registro A (Nombre → IPv4)${NC}"
    read -rp "   Nombre del host (ej: www, mail, ftp): " nombre

    if ! validar_nombre "$nombre"; then
        error "Nombre no válido. Usa solo letras, números y guiones."
        return
    fi

    read -rp "   Dirección IPv4 (ej: 192.168.1.20): " ip

    if ! validar_ipv4 "$ip"; then
        error "Dirección IPv4 no válida."
        return
    fi

    # Comprobar si ya existe
    if grep -q "^${nombre}\s" "$ZONA_FILE"; then
        error "Ya existe un registro para '${nombre}'."
        return
    fi

    echo "${nombre}     IN      A       ${ip}" >> "$ZONA_FILE"
    actualizar_serial
    exito "Registro A añadido: ${nombre} → ${ip}"
}

agregar_registro_aaaa() {
    echo -e "\n${BOLD}➕ Nuevo registro AAAA (Nombre → IPv6)${NC}"
    read -rp "   Nombre del host (ej: www, mail): " nombre

    if ! validar_nombre "$nombre"; then
        error "Nombre no válido. Usa solo letras, números y guiones."
        return
    fi

    read -rp "   Dirección IPv6 (ej: 2001:db8::1): " ip

    if ! validar_ipv6 "$ip"; then
        error "Dirección IPv6 no válida."
        return
    fi

    if grep -q "^${nombre}\s" "$ZONA_FILE"; then
        error "Ya existe un registro para '${nombre}'."
        return
    fi

    echo "${nombre}     IN      AAAA    ${ip}" >> "$ZONA_FILE"
    actualizar_serial
    exito "Registro AAAA añadido: ${nombre} → ${ip}"
}

agregar_registro_cname() {
    echo -e "\n${BOLD}➕ Nuevo registro CNAME (Alias)${NC}"
    read -rp "   Nombre del alias (ej: ftp, webmail): " alias_name

    if ! validar_nombre "$alias_name"; then
        error "Nombre no válido."
        return
    fi

    read -rp "   Apunta a (ej: www): " destino

    if ! validar_nombre "$destino"; then
        error "Nombre de destino no válido."
        return
    fi

    if grep -q "^${alias_name}\s" "$ZONA_FILE"; then
        error "Ya existe un registro para '${alias_name}'."
        return
    fi

    echo "${alias_name}     IN      CNAME   ${destino}" >> "$ZONA_FILE"
    actualizar_serial
    exito "Registro CNAME añadido: ${alias_name} → ${destino}"
}

agregar_registro_mx() {
    echo -e "\n${BOLD}➕ Nuevo registro MX (Servidor de correo)${NC}"
    read -rp "   Servidor de correo (ej: mail): " servidor

    if ! validar_nombre "$servidor"; then
        error "Nombre no válido."
        return
    fi

    read -rp "   Prioridad (número, ej: 10): " prioridad

    if ! [[ "$prioridad" =~ ^[0-9]+$ ]]; then
        error "La prioridad debe ser un número."
        return
    fi

    echo "@       IN      MX      ${prioridad}    ${servidor}" >> "$ZONA_FILE"
    actualizar_serial
    exito "Registro MX añadido: prioridad ${prioridad} → ${servidor}"
}

agregar_registro_ns() {
    echo -e "\n${BOLD}➕ Nuevo registro NS (Servidor de nombres)${NC}"
    read -rp "   Nombre del servidor DNS (ej: ns2.ejemplo.com.): " servidor

    # Asegurar que termina en punto
    if [[ "${servidor: -1}" != "." ]]; then
        servidor="${servidor}."
    fi

    echo "@       IN      NS      ${servidor}" >> "$ZONA_FILE"
    actualizar_serial
    exito "Registro NS añadido: ${servidor}"
}

agregar_registro_txt() {
    echo -e "\n${BOLD}➕ Nuevo registro TXT${NC}"
    read -rp "   Nombre (ej: @ para el dominio, o un subdominio): " nombre
    read -rp "   Contenido del TXT (ej: v=spf1 mx ~all): " contenido

    echo "${nombre}     IN      TXT     \"${contenido}\"" >> "$ZONA_FILE"
    actualizar_serial
    exito "Registro TXT añadido: ${nombre} → \"${contenido}\""
}

eliminar_registro() {
    echo -e "\n${BOLD}🗑  Eliminar un registro${NC}"
    echo ""

    # Mostrar registros con números de línea
    local registros
    registros=$(grep -n 'IN\s' "$ZONA_FILE" | grep -v 'SOA' | grep -v 'Serial\|Refresh\|Retry\|Expire\|Negative\|)')

    if [[ -z "$registros" ]]; then
        error "No hay registros para eliminar."
        return
    fi

    echo -e "${CYAN}${registros}${NC}"
    echo ""
    read -rp "   Número de línea a eliminar: " linea

    if ! [[ "$linea" =~ ^[0-9]+$ ]]; then
        error "Número de línea no válido."
        return
    fi

    local contenido_linea
    contenido_linea=$(sed -n "${linea}p" "$ZONA_FILE")

    echo -e "\n${AMARILLO}Se eliminará: ${contenido_linea}${NC}"
    read -rp "   ¿Confirmar? (s/n): " confirmar

    if [[ "$confirmar" == "s" || "$confirmar" == "S" ]]; then
        sed -i.bak "${linea}d" "$ZONA_FILE"
        actualizar_serial
        exito "Registro eliminado correctamente."
    else
        echo -e "${AMARILLO}Operación cancelada.${NC}"
    fi
}

# --- Menú principal ---
while true; do
    echo ""
    separador
    echo -e "${BOLD}   🌐 Gestor de Zona DNS - ejemplo.com${NC}"
    separador
    echo -e "  ${VERDE}1)${NC} Añadir registro ${BOLD}A${NC}       (Nombre → IPv4)"
    echo -e "  ${VERDE}2)${NC} Añadir registro ${BOLD}AAAA${NC}    (Nombre → IPv6)"
    echo -e "  ${VERDE}3)${NC} Añadir registro ${BOLD}CNAME${NC}   (Alias)"
    echo -e "  ${VERDE}4)${NC} Añadir registro ${BOLD}MX${NC}      (Correo)"
    echo -e "  ${VERDE}5)${NC} Añadir registro ${BOLD}NS${NC}      (Servidor DNS)"
    echo -e "  ${VERDE}6)${NC} Añadir registro ${BOLD}TXT${NC}     (Texto)"
    echo -e "  ${AZUL}7)${NC} 📋 Ver registros actuales"
    echo -e "  ${ROJO}8)${NC} 🗑  Eliminar un registro"
    echo -e "  ${AMARILLO}0)${NC} ❌ Salir"
    separador
    read -rp "  Elige una opción: " opcion

    case $opcion in
        1) agregar_registro_a ;;
        2) agregar_registro_aaaa ;;
        3) agregar_registro_cname ;;
        4) agregar_registro_mx ;;
        5) agregar_registro_ns ;;
        6) agregar_registro_txt ;;
        7) mostrar_registros ;;
        8) eliminar_registro ;;
        0)
            echo -e "\n${VERDE}👋 ¡Hasta luego!${NC}\n"
            exit 0
            ;;
        *)
            error "Opción no válida."
            ;;
    esac
done
