#!/usr/bin/env bash
# AutoAudit: respaldo verificable de la base de pruebas ANTES de cambiar IP.
# Este script NO modifica la base y NO ejecuta los parches de IP.
set -Eeuo pipefail
BASE='autoaudit_restauracion'
CARPETA="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$CARPETA/.." && pwd)"
DESTINO="${AUTOAUDIT_OUT_DIR:-$ROOT/salidas_locales}"
mkdir -p "$DESTINO"

for comando in sudo pg_dump pg_restore; do
  if ! command -v "$comando" >/dev/null 2>&1; then
    echo "ERROR: no existe el comando $comando" >&2
    exit 1
  fi
done

if ! sudo -u postgres psql -X -At -d "$BASE" -c 'SELECT 1;' >/dev/null 2>&1; then
  echo "ERROR: no se pudo abrir $BASE. No se generó ningún respaldo." >&2
  exit 1
fi

MARCA="$(date +%Y%m%d_%H%M%S)"
ARCHIVO="$DESTINO/autoaudit_antes_ip_${MARCA}.dump"
TEMPORAL="$(mktemp /tmp/autoaudit_backup_XXXXXXXX.dump)"
trap 'rm -f "$TEMPORAL"' EXIT

echo "Generando respaldo completo de datos y esquema de: $BASE"
sudo -u postgres pg_dump --format=custom --dbname="$BASE" > "$TEMPORAL"

if [[ ! -s "$TEMPORAL" ]] || ! pg_restore --list "$TEMPORAL" >/dev/null 2>&1; then
  echo 'ERROR: el archivo generado no pasa la comprobación de formato. No se copiará.' >&2
  exit 1
fi

sudo cp -- "$TEMPORAL" "$ARCHIVO"
if ! sudo test -s "$ARCHIVO" || ! sudo cmp -s "$TEMPORAL" "$ARCHIVO"; then
  echo 'ERROR: la copia en la carpeta compartida no quedó correctamente verificada.' >&2
  exit 1
fi

echo
echo 'RESPALDO CORRECTO: archivo .dump comprobado'
echo "Base: $BASE"
echo "Archivo: $ARCHIVO"
ls -lh "$ARCHIVO"
echo 'El respaldo incluye datos y esquema de esta base, pero NO los roles globales del servidor.'
echo 'Todavía NO se aplicó ningún cambio de IP.'
