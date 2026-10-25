#!/usr/bin/env bash
set -euo pipefail
DB='autoaudit_restauracion'
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo 'AutoAudit - interfaz local de consultas (sin login web)'
echo 'Solo lectura; acceso administrativo LOCAL mediante sudo'
while true; do
  printf '\n1 Tablas del diccionario\n2 Columnas del diccionario\n3 Configuracion de auditoria\n4 Historial por usuario\n5 Historial por columna\n6 Triggers\n0 Salir\nOpcion: '
  read -r x
  case "$x" in
   1) sudo -u postgres psql -X -P pager=off -d "$DB" -c "SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE' ORDER BY table_name";;
   2) sudo -u postgres psql -X -P pager=off -d "$DB" -c "SELECT table_name,column_name,data_type FROM information_schema.columns WHERE table_schema='public' ORDER BY table_name,ordinal_position";;
   3) sudo -u postgres psql -X -P pager=off -d "$DB" -f "$ROOT/sql/03_revision_integral.sql";;
   4) read -r -p 'Usuario [letras, numeros, _]: ' who;
      if [[ "$who" =~ ^[a-zA-Z0-9_]+$ ]]; then sudo -u postgres psql -X -P pager=off -d "$DB" -c "SELECT * FROM public.reporte_autoaudit WHERE nombre_usuario='$who' ORDER BY fecha_evento"; else echo 'Usuario no permitido'; fi;;
   5) read -r -p 'Columna [letras, numeros, _]: ' col;
      if [[ "$col" =~ ^[a-zA-Z0-9_]+$ ]]; then sudo -u postgres psql -X -P pager=off -d "$DB" -c "SELECT * FROM public.reporte_autoaudit WHERE nombre_columna='$col' ORDER BY fecha_evento"; else echo 'Columna no permitida'; fi;;
   6) sudo -u postgres psql -X -P pager=off -d "$DB" -c "SELECT c.relname,t.tgname FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid WHERE NOT t.tgisinternal ORDER BY c.relname";;
   0) break;; *) echo 'Opcion invalida';;
  esac
done
