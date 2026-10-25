#!/usr/bin/env bash
set -euo pipefail
BASE='autoaudit_restauracion'
CARPETA="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$CARPETA/.." && pwd)"
S="$ROOT/sql"
OUT="${AUTOAUDIT_OUT_DIR:-$ROOT/salidas_locales}"
mkdir -p "$OUT"
if ! command -v psql >/dev/null 2>&1; then echo 'No se encontro psql'; exit 1; fi
if ! sudo -u postgres psql -X -At -d "$BASE" -c 'SELECT 1' >/dev/null 2>&1; then
 echo 'No se puede entrar a autoaudit_restauracion. No se ha realizado ningun cambio.'; exit 1
fi
correr(){ sudo -u postgres psql -X -v ON_ERROR_STOP=1 -P pager=off -d "$BASE" -f "$S/$1"; }
while true; do
  echo
  echo 'AutoAudit | BASE EXCLUSIVA: autoaudit_restauracion'
  echo '1. Diagnostico integral y seguridad (SOLO LECTURA)'
  echo '2. Crear/verificar rol lector (CAMBIA PERMISOS SOLO DE PRUEBAS)'
  echo '3. Exportar CSV de reporte, estructura, relaciones y configuracion'
  echo '4. IP: mostrar estado (SOLO LECTURA)'
  echo '5. IP: instalar campo y funcion adaptada (EXPERIMENTAL; REQUIERE CONFIRMACION)'
  echo '6. Probar triggers con ROLLBACK'
  echo '7. Consola de consultas (SOLO LECTURA)'
  echo '8. Revisar los 1000 productos de rendimiento (SOLO LECTURA)'
  echo '0. Salir'
  read -r -p 'Opcion: ' op
  case "$op" in
  1) correr 03_revision_integral.sql | tee "$OUT/diagnostico_integral.txt";
     correr 02_diagnostico_seguridad.sql | tee "$OUT/diagnostico_seguridad.txt";;
  2) correr 01_rol_lector.sql | tee "$OUT/prueba_rol_lector.txt";
     correr 06_prueba_lector_sin_escritura.sql | tee "$OUT/prueba_lectura.txt";;
  3) correr 04_exportaciones.sql;
     for f in consolidado diccionario relaciones configuracion; do
       sudo cp "/tmp/autoaudit_${f}_final.csv" "$OUT/autoaudit_${f}_final.csv"
     done;
     sudo -u postgres pg_dump --schema-only --no-owner --no-privileges -d "$BASE" -f /tmp/autoaudit_estructura_restaurada.sql;
     sudo cp /tmp/autoaudit_estructura_restaurada.sql "$OUT/autoaudit_estructura_restaurada.sql";
     echo 'Archivos disponibles en 05_Resultados:'; ls -lh "$OUT"/*.csv "$OUT"/*.sql;;
  4) correr 02_diagnostico_seguridad.sql | tee "$OUT/estado_ip.txt";;
  5) echo 'ATENCION: este paso cambia la estructura y función de auditoría EN LA BASE DE PRUEBAS.';
     echo 'Confirma que tienes respaldo, dueño autoaudit_admin y que aceptarás una prueba de regresion.';
     read -r -p 'Escribe exactamente APLICAR_IP para continuar: ' ok;
     if [[ "$ok" == 'APLICAR_IP' ]]; then
       correr 07_ip_opcional_y_funcion.sql;
       correr 07b_fn_con_ip.sql;
       echo 'Hecho. Ejecuta la opcion 6 y valida manualmente IP con conexion TCP.';
     else echo 'No se realizaron cambios de IP'; fi;;
  6) correr 08_prueba_transaccional_trigger.sql | tee "$OUT/prueba_trigger_rollback.txt";;
  7) bash "$ROOT/consulta/consultas.sh";;
  8) correr 09_limpieza_perf_SOLO_PREVISUALIZAR.sql;;
  0) echo 'Finalizado'; break;;
  *) echo 'Opcion invalida';;
  esac
done
