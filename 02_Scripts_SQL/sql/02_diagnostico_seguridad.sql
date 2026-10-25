\pset pager off
\echo === BASE ACTUAL Y USUARIO ===
SELECT current_database() AS base, session_user AS usuario_sesion, current_user AS rol_efectivo, inet_client_addr() AS ip_cliente;
\echo === ESTADO ROLES ===
SELECT rolname,rolcanlogin,rolsuper,rolcreatedb,rolcreaterole
FROM pg_catalog.pg_roles WHERE rolname IN ('autoaudit_admin','autoaudit_lector');
\echo === PROPIETARIOS TABLAS ===
SELECT tablename,tableowner FROM pg_catalog.pg_tables WHERE schemaname='public'
ORDER BY tablename;
\echo === PRIVILEGIOS ROL LECTOR (si existe) ===
SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='autoaudit_lector')
 THEN has_table_privilege('autoaudit_lector','public.bitacora_auditoria','SELECT') ELSE NULL END AS leer_bitacora,
 CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='autoaudit_lector')
 THEN has_table_privilege('autoaudit_lector','public.bitacora_auditoria','UPDATE') ELSE NULL END AS modificar_bitacora;
\echo === SEGURIDAD DE FUNCION AUDITORIA ===
SELECT p.proname,p.prosecdef AS ejecuta_privilegios_propietario,
  pg_get_userbyid(p.proowner) AS propietario, p.proconfig AS configuracion_seguridad
FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='fn_autoaudit_generica';
\echo === TRIGGERS ACTUALES ===
SELECT c.relname,t.tgname,t.tgenabled
FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
WHERE NOT t.tgisinternal AND t.tgname='trg_autoaudit' ORDER BY 1;
\echo === ¿ESTÁ IMPLEMENTADO CAMPO IP? ===
SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public'
AND table_name='bitacora_auditoria' AND column_name='ip_origen') AS tiene_ip_origen;
