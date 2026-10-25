#!/usr/bin/env bash
# AUTOAUDIT | Limitar EXECUTE PUBLIC sin alterar tablas ni datos.
set -Eeuo pipefail
umask 077
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB="autoaudit_restauracion"
OUT="$DIR/salidas_locales"
mkdir -p "$OUT"

printf '\nAUTOAUDIT - AJUSTE DE SEGURIDAD EN BASE DE PRUEBAS\n'
printf 'Base fija: %s\n' "$DB"
printf 'Cambios: REVOKE EXECUTE FROM PUBLIC y GRANT EXECUTE a autoaudit_admin.\n'
printf 'NO cambia propietarios, datos ni la base autoaudit.\n\n'

if ! command -v sudo >/dev/null || ! command -v pg_restore >/dev/null; then
  echo 'ERROR: se requieren sudo y las herramientas PostgreSQL instaladas.'
  exit 1
fi

printf 'Comprobando que existen las funciones y el propietario esperado...\n'
check_sql="SELECT CASE WHEN
 current_database()='autoaudit_restauracion'
 AND EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='autoaudit_admin')
 AND EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='autoaudit_lector')
 AND EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE oid='public.fn_autoaudit_generica()'::regprocedure
   AND prosecdef AND pg_catalog.pg_get_userbyid(proowner)='autoaudit_admin')
 AND EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE oid='public.fn_sincronizar_triggers_autoaudit()'::regprocedure
   AND NOT prosecdef)
 THEN 'LISTO' ELSE 'REVISAR' END;"
status="$(sudo -u postgres psql -X -v ON_ERROR_STOP=1 -At -d "$DB" -c "$check_sql")"
if [[ "$status" != "LISTO" ]]; then
  echo "NO SE APLICO NADA. Comprobacion previa: $status"
  exit 1
fi

printf '\nConfirmacion: escribe APLICAR_SEGURIDAD para continuar: '
IFS= read -r answer
if [[ "$answer" != "APLICAR_SEGURIDAD" ]]; then
  echo 'Cancelado sin modificaciones.'
  exit 0
fi

stamp="$(date +%Y%m%d_%H%M%S)"
backup="$OUT/NO_PUBLICAR_respaldo_antes_seguridad_${stamp}.dump"
log="$OUT/seguridad_ajuste_resultado_${stamp}.txt"
echo 'Generando respaldo completo de restauracion...'
if ! sudo -u postgres pg_dump -Fc -d "$DB" > "$backup"; then
  rm -f "$backup"
  echo 'ERROR: fallo el respaldo. No se aplicaron cambios.'
  exit 1
fi
if ! pg_restore -l "$backup" >/dev/null; then
  echo 'ERROR: no se pudo leer el respaldo. No se aplicaron cambios.'
  exit 1
fi
printf 'Respaldo comprobado (NO PUBLICAR): %s\n' "$backup"

echo 'Aplicando permisos en una transaccion...'
# Usar psql -f con rutas claras, y guardar evidencia. pipefail evita falsa confirmacion.
if ! sudo -u postgres psql -X -v ON_ERROR_STOP=1 -d "$DB" -f "$DIR/restringir_funciones.sql" | tee "$log"; then
  echo 'ERROR: la instruccion fallo. Si fallo antes de COMMIT, PostgreSQL revierte la transaccion.'
  echo 'NO vuelvas a ejecutar sin revisar el resultado.'
  exit 1
fi

printf '\nREVISION: publico_puede_ejecutar debe ser f en ambas filas; admin_puede_ejecutar debe ser t.\n'
printf 'Evidencia: %s\n' "$log"
printf 'El propietario autoaudit_admin conserva acceso de dueno a las tablas: aun requiere separacion de roles.\n'
printf 'No publiques archivos NO_PUBLICAR*.dump en GitHub/GitLab.\n'
