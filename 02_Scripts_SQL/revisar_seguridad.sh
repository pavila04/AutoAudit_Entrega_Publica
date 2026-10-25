#!/usr/bin/env bash
# AutoAudit - Revision final de seguridad, SOLO LECTURA, 24/10/2026.
set -euo pipefail
BASE='autoaudit_restauracion'
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$ROOT/salidas_locales"
mkdir -p "$OUT"
REPORT="$OUT/seguridad_final_lectura.txt"

if ! command -v psql >/dev/null 2>&1; then
  echo 'ERROR: no se encuentra psql. No se realizaron cambios.'
  exit 1
fi

echo 'AUTOAUDIT | DIAGNOSTICO FINAL DE SEGURIDAD (SOLO LECTURA)'
echo "Base objetivo: $BASE"
echo 'No crea roles, no cambia permisos, no modifica tablas.'
echo 'El informe contiene nombres de roles: no subirlo a GitHub sin revisarlo.'
echo 'Es posible que sudo solicite la contrasena local de Ubuntu.'
echo

sudo -u postgres psql -X -v ON_ERROR_STOP=1 -P pager=off -d "$BASE" <<'SQL' | tee "$REPORT"
\pset null '(NULL)'
\echo ===== 1. IDENTIDAD DE LA CONEXION =====
SELECT current_database() AS base,
       session_user AS usuario_sesion,
       current_user AS usuario_efectivo;

\echo ===== 2. ROLES DE AUTOAUDIT =====
SELECT rolname, rolcanlogin, rolsuper, rolcreatedb, rolcreaterole, rolbypassrls
FROM pg_catalog.pg_roles
WHERE rolname LIKE 'autoaudit%'
ORDER BY rolname;

\echo ===== 3. PROPIETARIOS DE TABLAS CRITICAS =====
SELECT tablename, tableowner
FROM pg_catalog.pg_tables
WHERE schemaname='public'
  AND tablename IN ('bitacora_auditoria','detalle_bitacora',
                    'configuracion_auditoria','tablas_auditadas',
                    'columnas_auditadas','productos_prueba')
ORDER BY tablename;

\echo ===== 4. PERMISOS DEL ROL LECTOR (SI EXISTE) =====
SELECT x.tabla,
       has_table_privilege(r.rolname,format('public.%I',x.tabla),'SELECT') AS leer,
       has_table_privilege(r.rolname,format('public.%I',x.tabla),'INSERT') AS insertar,
       has_table_privilege(r.rolname,format('public.%I',x.tabla),'UPDATE') AS modificar,
       has_table_privilege(r.rolname,format('public.%I',x.tabla),'DELETE') AS borrar
FROM pg_catalog.pg_roles r
CROSS JOIN (VALUES ('bitacora_auditoria'),('detalle_bitacora')) x(tabla)
WHERE r.rolname='autoaudit_lector'
ORDER BY x.tabla;

\echo ===== 5. ROLES CON LOGIN Y PRIVILEGIOS SOBRE BITACORA =====
SELECT r.rolname AS rol_login,
       r.rolsuper AS superusuario,
       has_table_privilege(r.oid,'public.bitacora_auditoria','SELECT') AS leer,
       has_table_privilege(r.oid,'public.bitacora_auditoria','INSERT') AS insertar,
       has_table_privilege(r.oid,'public.bitacora_auditoria','UPDATE') AS modificar,
       has_table_privilege(r.oid,'public.bitacora_auditoria','DELETE') AS borrar
FROM pg_catalog.pg_roles r WHERE r.rolcanlogin
ORDER BY r.rolname;

\echo ===== 6. FUNCIONES, PROPIETARIO, SECURITY DEFINER Y PUBLIC EXECUTE =====
SELECT p.proname AS funcion,
       pg_catalog.pg_get_userbyid(p.proowner) AS propietario,
       r.rolsuper AS propietario_es_superusuario,
       p.prosecdef AS security_definer,
       coalesce(array_to_string(p.proconfig, ', '), '(SIN CONFIGURACION)') AS configuracion,
       EXISTS (
         SELECT 1 FROM pg_catalog.aclexplode(
           coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
         WHERE a.grantee=0 AND a.privilege_type='EXECUTE'
       ) AS public_puede_execute
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
WHERE n.nspname='public'
  AND p.proname IN ('fn_autoaudit_generica','fn_sincronizar_triggers_autoaudit')
ORDER BY p.proname;

\echo ===== 7. PERMISO CREATE DEL ESQUEMA PUBLIC PARA PUBLIC =====
SELECT n.nspname,
       EXISTS (
         SELECT 1 FROM pg_catalog.aclexplode(
           coalesce(n.nspacl,pg_catalog.acldefault('n',n.nspowner))) a
         WHERE a.grantee=0 AND a.privilege_type='CREATE'
       ) AS public_puede_crear_objetos
FROM pg_catalog.pg_namespace n WHERE n.nspname='public';

\echo ===== 8. ESTADO DE TRIGGERS (O = HABILITADO NORMAL) =====
SELECT c.relname AS tabla, t.tgname AS trigger, t.tgenabled AS estado
FROM pg_catalog.pg_trigger t
JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND NOT t.tgisinternal
  AND t.tgname='trg_autoaudit'
ORDER BY c.relname;

\echo ===== 9. REGISTRO DE IP Y NUMERO ACTUAL DE REGLAS =====
SELECT EXISTS(
  SELECT 1 FROM information_schema.columns
  WHERE table_schema='public' AND table_name='bitacora_auditoria'
    AND column_name='ip_origen') AS existe_ip_origen;
SELECT count(*) AS reglas_activas FROM public.configuracion_auditoria
WHERE activa IS TRUE;

\echo ===== FIN: DIAGNOSTICO SOLO LECTURA =====
SQL

echo
echo 'TERMINADO: Diagnostico de seguridad generado sin cambios en PostgreSQL.'
echo "Evidencia local: $REPORT"
echo 'NO publicar este informe directamente: revisar nombres de cuentas y permisos.'
echo 'Comparte una captura de las secciones 5, 6 y 7 para analizar riesgos.'
