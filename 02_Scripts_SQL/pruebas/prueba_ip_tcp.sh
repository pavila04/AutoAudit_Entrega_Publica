#!/usr/bin/env bash
# AutoAudit - verificacion de la direccion IP a traves de TCP.
# No requiere copiar y pegar SQL en Ubuntu.
# SOLO utiliza la base autoaudit_restauracion.
# La modificacion de prueba y su auditoria se revierten con ROLLBACK.
set -euo pipefail

BASE='autoaudit_restauracion'
USUARIO='autoaudit_admin'

if ! command -v psql >/dev/null 2>&1; then
  echo 'ERROR: no se encontro el comando psql en Ubuntu.'
  exit 1
fi

printf '\n==============================================\n'
printf ' AUTOAUDIT | PRUEBA DE IP POR TCP\n'
printf '==============================================\n'
printf 'Base: %s\nUsuario: %s\nDestino TCP: 127.0.0.1:5432\n' "$BASE" "$USUARIO"
printf '\nCuando solicite Password, introduce la contrasena de %s.\n' "$USUARIO"
printf 'La contrasena NO se guarda en este archivo.\n'
printf 'Se probara un UPDATE temporal y se ejecutara ROLLBACK.\n\n'

if psql -X -P pager=off -v ON_ERROR_STOP=1 -h 127.0.0.1 -p 5432 \
  -U "$USUARIO" -d "$BASE" -W <<'SQL'
\echo ===== VERIFICANDO CONEXION TCP =====
SELECT current_database() AS base,
       session_user AS usuario,
       inet_client_addr() AS ip_conexion;

\echo ===== INICIANDO PRUEBA REVERSIBLE =====
BEGIN;

-- Comprobaciones antes de efectuar la actualizacion.
DO $validacion$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public'
       AND table_name='bitacora_auditoria'
       AND column_name='ip_origen'
  ) THEN
    RAISE EXCEPTION 'Falta la columna public.bitacora_auditoria.ip_origen';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.productos_prueba WHERE id_producto=1) THEN
    RAISE EXCEPTION 'No existe el producto id_producto=1 para la prueba';
  END IF;
END;
$validacion$;

SELECT COALESCE(MAX(id_bitacora), 0) AS ultimo_antes
FROM public.bitacora_auditoria \gset

UPDATE public.productos_prueba
   SET precio=precio+0.01
 WHERE id_producto=1;

\echo ===== RESULTADO DE LA AUDITORIA TEMPORAL =====
SELECT b.id_bitacora,
       b.ip_origen AS ip_registrada,
       inet_client_addr() AS ip_esperada,
       CASE
         WHEN b.ip_origen = inet_client_addr() THEN 'CORRECTO: IP REGISTRADA'
         WHEN b.ip_origen IS NULL THEN 'PENDIENTE: IP NULA'
         ELSE 'REVISAR: IP DIFERENTE'
       END AS resultado
  FROM public.bitacora_auditoria b
  JOIN public.tablas_auditadas t ON t.id_tabla=b.id_tabla
 WHERE b.id_bitacora > :ultimo_antes
   AND t.nombre_tabla='productos_prueba'
 ORDER BY b.id_bitacora DESC
 LIMIT 1;

\echo ===== COMPROBACION DE BITACORA NUEVA =====
SELECT COUNT(*) AS auditorias_temporales
FROM public.bitacora_auditoria
WHERE id_bitacora > :ultimo_antes;

\echo ===== REVIRTIENDO CAMBIOS =====
ROLLBACK;
\echo ===== FIN DE LA PRUEBA: CAMBIOS REVERSIBLES DESHECHOS =====
SQL
then
  printf '\nPrueba terminada. Busca CORRECTO: IP REGISTRADA arriba.\n'
  printf 'Nota: 127.0.0.1 es la IP local de la conexion TCP en Ubuntu.\n'
else
  printf '\nERROR: no se pudo completar la prueba.\n'
  printf 'Si fallo la autenticacion, comprueba la contrasena de autoaudit_admin.\n'
  printf 'Si hubo un error SQL, PostgreSQL revierte automaticamente la transaccion al desconectar.\n'
  printf 'NO cambies pg_hba.conf ni la base original; envia una captura del error.\n'
  exit 1
fi
