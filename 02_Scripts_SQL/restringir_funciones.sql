-- AUTOAUDIT | Ajuste limitado a autoaudit_restauracion.
-- Solo modifica privilegios EXECUTE de dos funciones; NO cambia tablas ni datos.
-- Ejecutar mediante el script verificar_y_ajustar_seguridad.sh.
\set ON_ERROR_STOP on
DO $seguridad$ BEGIN
 IF current_database() <> 'autoaudit_restauracion' THEN
   RAISE EXCEPTION 'Base incorrecta: %', current_database();
 END IF;
END $seguridad$;
BEGIN;
REVOKE EXECUTE ON FUNCTION public.fn_autoaudit_generica() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_sincronizar_triggers_autoaudit() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_autoaudit_generica() TO autoaudit_admin;
GRANT EXECUTE ON FUNCTION public.fn_sincronizar_triggers_autoaudit() TO autoaudit_admin;
COMMIT;
\echo '=== Verificacion posterior de privilegios ==='
SELECT p.proname AS funcion,
       pg_catalog.pg_get_userbyid(p.proowner) AS propietario,
       p.prosecdef AS security_definer,
       EXISTS (
         SELECT 1 FROM pg_catalog.aclexplode(
           COALESCE(p.proacl, pg_catalog.acldefault('f',p.proowner))
         ) a
         WHERE a.grantee=0 AND a.privilege_type='EXECUTE'
       ) AS publico_puede_ejecutar,
       pg_catalog.has_function_privilege('autoaudit_admin',p.oid,'EXECUTE') AS admin_puede_ejecutar,
       pg_catalog.has_function_privilege('autoaudit_lector',p.oid,'EXECUTE') AS lector_puede_ejecutar
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname IN ('fn_autoaudit_generica','fn_sincronizar_triggers_autoaudit')
ORDER BY p.proname;
\echo '=== Triggers instalados (O significa habilitado) ==='
SELECT c.relname AS tabla, t.tgname AS trigger, t.tgenabled AS estado
FROM pg_catalog.pg_trigger t
JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
WHERE NOT t.tgisinternal AND n.nspname='public' AND t.tgname='trg_autoaudit'
ORDER BY c.relname;
