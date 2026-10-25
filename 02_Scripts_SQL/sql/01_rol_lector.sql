-- EN AUTOAUDIT_RESTAURACION. Idempotente. Rol SIN LOGIN, y sin acceso de escritura.
BEGIN;
DO $plpgsql$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='autoaudit_lector') THEN
    CREATE ROLE autoaudit_lector NOLOGIN;
  END IF;
END
$plpgsql$;
REVOKE ALL ON TABLE public.bitacora_auditoria, public.detalle_bitacora FROM autoaudit_lector;
GRANT USAGE ON SCHEMA public TO autoaudit_lector;
GRANT SELECT ON public.bitacora_auditoria, public.detalle_bitacora TO autoaudit_lector;
GRANT SELECT ON public.reporte_autoaudit TO autoaudit_lector;
COMMIT;
SELECT tabla,
       has_table_privilege('autoaudit_lector',tabla,'SELECT') AS leer,
       has_table_privilege('autoaudit_lector',tabla,'UPDATE') AS modificar,
       has_table_privilege('autoaudit_lector',tabla,'DELETE') AS borrar
FROM (VALUES ('public.bitacora_auditoria'),('public.detalle_bitacora')) v(tabla);
-- La comprobacion no sustituye un ensayo con un rol LOGIN real.
