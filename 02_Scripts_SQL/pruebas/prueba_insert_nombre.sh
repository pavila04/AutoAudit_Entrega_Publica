#!/usr/bin/env bash
set -euo pipefail

BASE='autoaudit_restauracion'
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${AUTOAUDIT_OUT_DIR:-$ROOT/salidas_locales}"
mkdir -p "$DEST"
ARCHIVO="$DEST/prueba_insert_nombre_resultado.txt"

echo 'AutoAudit | PRUEBA INSERT de productos_prueba.nombre'
echo "Base: $BASE (la base original NO se modifica)"
echo 'La prueba usa una transaccion y finaliza con ROLLBACK.'
echo 'No es necesario ingresar a PostgreSQL manualmente.'
echo

# El codigo SQL no contiene COMMIT; si falla, al desconectar PostgreSQL revierte la transaccion.
sudo -u postgres psql -X -v ON_ERROR_STOP=1 -P pager=off -d "$BASE" <<'SQL' 2>&1 | tee "$ARCHIVO"
DO $verificar_base$
BEGIN
  IF current_database() <> 'autoaudit_restauracion' THEN
    RAISE EXCEPTION 'Base incorrecta. Abortando prueba.';
  END IF;
END
$verificar_base$;

SET SESSION AUTHORIZATION autoaudit_admin;
BEGIN;
DO $prueba$
DECLARE
    v_id_producto bigint;
    v_coincidencias integer;
    v_columna text := 'nombre';
    v_texto text := 'AA-PRUEBA-INSERT-NOMBRE';
BEGIN
    INSERT INTO public.productos_prueba (nombre, precio)
    VALUES (v_texto, 20.00)
    RETURNING id_producto INTO v_id_producto;

    SELECT COUNT(*) INTO v_coincidencias
    FROM public.bitacora_auditoria AS b
    JOIN public.tablas_auditadas AS t ON t.id_tabla = b.id_tabla
    JOIN public.eventos_auditoria AS e ON e.id_evento = b.id_evento
    JOIN public.detalle_bitacora AS d ON d.id_bitacora = b.id_bitacora
    JOIN public.columnas_auditadas AS c ON c.id_columna = d.id_columna
    WHERE t.esquema = 'public'
      AND t.nombre_tabla = 'productos_prueba'
      AND e.nombre_evento = 'INSERT'
      AND c.nombre_columna = v_columna
      AND b.registro_id = v_id_producto::text
      AND d.valor_anterior IS NULL
      AND d.valor_nuevo = v_texto;

    IF v_coincidencias <> 1 THEN
        RAISE EXCEPTION 'FALLO: Se esperaban 1 detalle INSERT/nombre y se encontraron %', v_coincidencias;
    END IF;

    RAISE NOTICE 'CORRECTO: La regla INSERT/nombre registro el valor nuevo.';
    RAISE NOTICE 'ID de producto temporal: %', v_id_producto;
    RAISE NOTICE 'Detalle de auditoria encontrado: %', v_coincidencias;
END
$prueba$;
ROLLBACK;
RESET SESSION AUTHORIZATION;
SELECT COUNT(*) AS bitacoras_guardadas_despues_del_rollback FROM public.bitacora_auditoria;
SQL

echo
echo 'PRUEBA FINALIZADA. Si viste CORRECTO y ROLLBACK, la validacion fue exitosa.'
echo "Evidencia guardada en: $ARCHIVO"
