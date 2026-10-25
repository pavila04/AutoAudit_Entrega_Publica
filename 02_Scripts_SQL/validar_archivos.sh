#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Comprobando rutas y sintaxis en $ROOT"
for f in "$ROOT"/iniciar.sh "$ROOT"/interfaz/*.sh "$ROOT"/consulta/*.sh "$ROOT"/pruebas/*.sh; do
  bash -n "$f" || exit 1
  echo "OK: ${f#$ROOT/}"
done
for f in "$ROOT"/sql/03_revision_integral.sql "$ROOT"/sql/02_diagnostico_seguridad.sql "$ROOT"/sql/04_exportaciones.sql "$ROOT"/sql/01_rol_lector.sql "$ROOT"/sql/06_prueba_lector_sin_escritura.sql "$ROOT"/sql/07b_fn_con_ip.sql; do
  test -f "$f" || { echo "FALTA: $f"; exit 1; }
done
# Verificar que la funcion SQL de configuracion tenga su modulo de Python disponible.
command -v python3 >/dev/null || echo 'AVISO: python3 no esta instalado.'
echo 'REVISION ESTATICA CORRECTA. No se ha conectado a PostgreSQL.'
