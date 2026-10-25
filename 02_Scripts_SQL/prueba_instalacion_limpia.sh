#!/usr/bin/env bash
# AutoAudit - prueba de despliegue desde cero en una base AISLADA.
# No usa ni altera las bases autoaudit y autoaudit_restauracion.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ESQUEMA="$ROOT/sql/estructura_actual.sql"
SALIDA="$ROOT/salidas_locales"
mkdir -p "$SALIDA"
DB="autoaudit_limpia_$(date +%Y%m%d_%H%M%S)_$$"
LOG="$SALIDA/instalacion_limpia_${DB}.txt"

if [[ ! -f "$ESQUEMA" ]]; then
  echo "ERROR: falta $ESQUEMA"
  echo "Coloca este archivo en la RAIZ de AutoAudit_Repositorio_Revisado, junto a iniciar.sh."
  exit 1
fi
for util in sudo psql createdb; do
  if ! command -v "$util" >/dev/null 2>&1; then
    echo "ERROR: falta el comando $util"; exit 1
  fi
done

printf '\nAUTOAUDIT | PRUEBA DE INSTALACION LIMPIA\n'
printf 'Nueva base aislada: %s\n' "$DB"
printf 'Se leera: %s\n' "$ESQUEMA"
printf 'No se modificara autoaudit ni autoaudit_restauracion.\n'
printf 'Se creara una base nueva y se conservara para comprobacion.\n'
printf 'Escribe PROBAR para confirmar: '
read -r CONFIRMAR
if [[ "$CONFIRMAR" != "PROBAR" ]]; then echo 'Cancelado sin cambios.'; exit 0; fi

# Validar el rol global antes de crear cualquier base.
CHECK="$(sudo -u postgres psql -XAt -d postgres -c "SELECT CASE WHEN rolsuper = false AND rolcanlogin = true THEN 'APTO' ELSE 'NO_APTO' END FROM pg_roles WHERE rolname = 'autoaudit_admin';")"
if [[ "$CHECK" != "APTO" ]]; then
  echo 'ERROR: autoaudit_admin no existe como LOGIN limitado, o es superusuario.'
  echo 'No se creo ninguna base.'
  exit 1
fi

# El nombre contiene fecha, segundos y PID; nunca reemplaza una base existente.
if [[ "$(sudo -u postgres psql -XAt -d postgres -c "SELECT count(*) FROM pg_database WHERE datname = '$DB';")" != "0" ]]; then
  echo 'ERROR: ese nombre de base ya existe. No se realizaron cambios.'; exit 1
fi

printf '\n[1/4] Creando base nueva (propietario: autoaudit_admin)...\n'
sudo -u postgres createdb -T template0 -O autoaudit_admin "$DB"
# pg_dump --schema-only incluye CREATE SCHEMA public; para evitar conflicto,
# retiramos public SOLO de la base acabada de crear (aun vacia).
sudo -u postgres psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -c 'DROP SCHEMA IF EXISTS public CASCADE;' >/dev/null

printf '[2/4] Instalando SOLO el esquema real (sin respaldos ni datos)...\n'
if ! sudo -u postgres psql -X -q -v ON_ERROR_STOP=1 -d "$DB" \
    -c 'SET SESSION AUTHORIZATION autoaudit_admin;' -f "$ESQUEMA" >"$LOG" 2>&1; then
  echo "ERROR instalando el esquema. Detalle en: $LOG"
  echo "La base separada $DB se conservo para diagnostico; no se tocaron otras bases."
  tail -n 25 "$LOG" || true
  exit 1
fi

printf '[3/4] Instalando catalogos MINIMOS desde cero...\n'
if ! sudo -u postgres psql -X -v ON_ERROR_STOP=1 -d "$DB" \
    -c 'SET SESSION AUTHORIZATION autoaudit_admin;' -f "$ROOT/semillas_y_prueba.sql" >>"$LOG" 2>&1; then
  echo "ERROR en semillas o prueba transaccional. Detalle: $LOG"
  tail -n 30 "$LOG" || true
  exit 1
fi

printf '[4/4] Confirmando propietario limitado y cero auditorias de prueba...\n'
sudo -u postgres psql -X -v ON_ERROR_STOP=1 -d "$DB" \
  -c "SELECT current_database() AS base_nueva, p.proowner::regrole AS propietario_funcion, r.rolsuper AS superusuario, p.prosecdef AS security_definer FROM pg_proc p JOIN pg_roles r ON r.oid=p.proowner WHERE p.proname='fn_autoaudit_generica';" \
  -c 'SELECT count(*) AS auditorias_persistentes FROM public.bitacora_auditoria;' | tee -a "$LOG"

printf '\nINSTALACION LIMPIA: SCRIPT TERMINADO SIN ERRORES.\n'
printf 'Base NUEVA: %s\n' "$DB"
printf 'Evidencia: %s\n' "$LOG"
printf 'Verifica arriba propietario_funcion=autoaudit_admin, superusuario=f, security_definer=t y auditorias_persistentes=0.\n'
printf 'La base de prueba NO se elimina automaticamente; no la uses en produccion.\n'
