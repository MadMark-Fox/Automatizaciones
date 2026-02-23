#!/bin/bash
# ============================================================
#  autoBackup.sh — Backup interactivo de directorios a tar.gz
#  Autor: Marcos Bolívar
#  Fecha: 2026-02-23
# ============================================================

set -euo pipefail

# ── Colores ──────────────────────────────────────────────────
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # Sin color

# ── Funciones auxiliares ─────────────────────────────────────
info()    { echo -e "${CYAN}ℹ  ${NC}$1"; }
success() { echo -e "${GREEN}✔  ${NC}$1"; }
warn()    { echo -e "${YELLOW}⚠  ${NC}$1"; }
error()   { echo -e "${RED}✖  ${NC}$1"; }

separator() {
  echo -e "${CYAN}──────────────────────────────────────────────${NC}"
}

# ── Banner ───────────────────────────────────────────────────
clear
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║        BACKUP INTERACTIVO            ║"
echo "  ║        Directorios → tar.gz          ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"

# ── 1. Recoger directorios a respaldar ───────────────────────
DIRS=()

info "Introduce las rutas de los directorios a respaldar."
info "Puedes usar rutas absolutas o relativas."
echo -e "${YELLOW}   Escribe una ruta por línea. Deja vacío y pulsa ENTER para terminar.${NC}"
separator

while true; do
  read -r -p "$(echo -e "${BOLD}Directorio: ${NC}")" dir_input

  # Línea vacía → fin de la entrada
  [[ -z "$dir_input" ]] && break

  # Expandir ~ y variables de entorno
  dir_expanded=$(eval echo "$dir_input" 2>/dev/null || echo "$dir_input")

  # Validar que existe y es un directorio
  if [[ ! -d "$dir_expanded" ]]; then
    warn "\"$dir_expanded\" no existe o no es un directorio. Inténtalo de nuevo."
    continue
  fi

  # Convertir a ruta absoluta
  dir_abs=$(cd "$dir_expanded" && pwd)
  DIRS+=("$dir_abs")
  success "Añadido: $dir_abs"
done

# Verificar que se seleccionó al menos un directorio
if [[ ${#DIRS[@]} -eq 0 ]]; then
  error "No se seleccionó ningún directorio. Saliendo."
  exit 1
fi

# ── 2. Mostrar resumen ──────────────────────────────────────
echo ""
separator
info "${BOLD}Directorios seleccionados (${#DIRS[@]}):${NC}"
for d in "${DIRS[@]}"; do
  echo -e "   📁 $d"
done
separator

# ── 3. Directorio de destino ────────────────────────────────
DEFAULT_DEST="$HOME/Backups"
echo ""
read -r -p "$(echo -e "${BOLD}Directorio de destino${NC} [${DEFAULT_DEST}]: ")" dest_input
DEST="${dest_input:-$DEFAULT_DEST}"

# Expandir ~ y variables
DEST=$(eval echo "$DEST" 2>/dev/null || echo "$DEST")

# Crear si no existe
if [[ ! -d "$DEST" ]]; then
  info "Creando directorio de destino: $DEST"
  mkdir -p "$DEST"
  success "Directorio creado."
fi

# ── 4. Nombre del archivo ───────────────────────────────────
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
DEFAULT_NAME="backup_${TIMESTAMP}"
echo ""
read -r -p "$(echo -e "${BOLD}Nombre del backup${NC} (sin extensión) [${DEFAULT_NAME}]: ")" name_input
BACKUP_NAME="${name_input:-$DEFAULT_NAME}"
BACKUP_FILE="${DEST}/${BACKUP_NAME}.tar.gz"

# Comprobar si ya existe
if [[ -f "$BACKUP_FILE" ]]; then
  warn "El archivo $BACKUP_FILE ya existe."
  read -r -p "$(echo -e "${YELLOW}¿Sobrescribir? (s/N): ${NC}")" overwrite
  if [[ ! "$overwrite" =~ ^[sS]$ ]]; then
    error "Operación cancelada."
    exit 1
  fi
fi

# ── 5. Nivel de compresión ──────────────────────────────────
echo ""
info "Nivel de compresión gzip (1=rápido, 9=máxima compresión)"
read -r -p "$(echo -e "${BOLD}Nivel${NC} [6]: ")" comp_input
COMP_LEVEL="${comp_input:-6}"

# Validar nivel
if ! [[ "$COMP_LEVEL" =~ ^[1-9]$ ]]; then
  warn "Nivel inválido. Usando nivel 6 por defecto."
  COMP_LEVEL=6
fi

# ── 6. Confirmación final ───────────────────────────────────
echo ""
separator
echo -e "${BOLD}${CYAN}  RESUMEN DEL BACKUP${NC}"
separator
echo -e "  📁 Directorios:    ${#DIRS[@]}"
for d in "${DIRS[@]}"; do
  echo -e "                     → $d"
done
echo -e "  📦 Destino:        ${BACKUP_FILE}"
echo -e "  🔧 Compresión:     Nivel ${COMP_LEVEL}"
separator
echo ""

read -r -p "$(echo -e "${BOLD}${GREEN}¿Continuar con el backup? (S/n): ${NC}")" confirm
if [[ "$confirm" =~ ^[nN]$ ]]; then
  error "Backup cancelado por el usuario."
  exit 0
fi

# ── 7. Crear el backup ──────────────────────────────────────
echo ""
info "Creando backup…"

# Calcular tamaño total antes de comprimir
TOTAL_SIZE=0
for d in "${DIRS[@]}"; do
  DIR_SIZE=$(du -sk "$d" 2>/dev/null | awk '{print $1}')
  TOTAL_SIZE=$((TOTAL_SIZE + DIR_SIZE))
done
info "Tamaño total estimado (sin comprimir): $((TOTAL_SIZE / 1024)) MB"

# Construir la lista de argumentos para tar
# Usamos -C para cambiar al directorio padre y solo incluir el nombre base
TAR_ARGS=()
for d in "${DIRS[@]}"; do
  parent=$(dirname "$d")
  base=$(basename "$d")
  TAR_ARGS+=(-C "$parent" "$base")
done

# Ejecutar tar con el nivel de compresión elegido
START_TIME=$(date +%s)

GZIP="-${COMP_LEVEL}" tar -czf "$BACKUP_FILE" "${TAR_ARGS[@]}"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

# ── 8. Verificación y resultado ──────────────────────────────
if [[ -f "$BACKUP_FILE" ]]; then
  FINAL_SIZE=$(du -sh "$BACKUP_FILE" | awk '{print $1}')
  echo ""
  separator
  echo -e "${BOLD}${GREEN}  ✔  BACKUP COMPLETADO CON ÉXITO${NC}"
  separator
  echo -e "  📦 Archivo:   ${BACKUP_FILE}"
  echo -e "  📏 Tamaño:    ${FINAL_SIZE}"
  echo -e "  ⏱  Tiempo:    ${ELAPSED}s"
  echo ""

  # Mostrar contenido del archivo
  read -r -p "$(echo -e "${BOLD}¿Ver contenido del backup? (s/N): ${NC}")" show_content
  if [[ "$show_content" =~ ^[sS]$ ]]; then
    echo ""
    info "Contenido de ${BACKUP_NAME}.tar.gz:"
    separator
    tar -tzf "$BACKUP_FILE" | head -50
    TOTAL_FILES=$(tar -tzf "$BACKUP_FILE" | wc -l | tr -d ' ')
    if [[ "$TOTAL_FILES" -gt 50 ]]; then
      echo -e "  ${YELLOW}... y $((TOTAL_FILES - 50)) archivos más${NC}"
    fi
    separator
    echo -e "  Total: ${BOLD}${TOTAL_FILES}${NC} archivos/directorios"
  fi

  echo ""
  success "¡Backup guardado en ${BACKUP_FILE}!"
else
  error "Algo falló al crear el backup."
  exit 1
fi
