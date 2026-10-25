\set ON_ERROR_STOP on
-- Semillas MINIMAS basadas en los nombres comprobados de AutoAudit.
-- Se ejecuta SOLO sobre la base nueva, bajo SESSION AUTHORIZATION autoaudit_admin.
BEGIN;
INSERT INTO public.eventos_auditoria (nombre_evento)
VALUES ('INSERT'), ('UPDATE'), ('DELETE');
INSERT INTO public.usuarios_auditados (nombre_usuario) VALUES ('autoaudit_admin');
INSERT INTO public.tablas_auditadas (esquema, nombre_tabla)
VALUES ('public', 'cliente_prueba'), ('public', 'productos_prueba');
INSERT INTO public.columnas_auditadas (id_tabla, nombre_columna)
SELECT id_tabla, 'telefono' FROM public.tablas_auditadas WHERE nombre_tabla='cliente_prueba'
UNION ALL
SELECT id_tabla, 'precio' FROM public.tablas_auditadas WHERE nombre_tabla='productos_prueba'
UNION ALL
SELECT id_tabla, 'nombre' FROM public.tablas_auditadas WHERE nombre_tabla='productos_prueba';
INSERT INTO public.configuracion_auditoria (id_columna, id_evento)
SELECT c.id_columna, e.id_evento
FROM public.columnas_auditadas c
JOIN public.tablas_auditadas t ON t.id_tabla=c.id_tabla
CROSS JOIN public.eventos_auditoria e
WHERE (t.nombre_tabla='cliente_prueba' AND c.nombre_columna='telefono' AND e.nombre_evento IN ('INSERT','UPDATE','DELETE'))
   OR (t.nombre_tabla='productos_prueba' AND c.nombre_columna='nombre' AND e.nombre_evento='INSERT')
   OR (t.nombre_tabla='productos_prueba' AND c.nombre_columna='precio' AND e.nombre_evento='UPDATE');
DO $$
BEGIN
  IF (SELECT count(*) FROM public.configuracion_auditoria) <> 5 THEN
    RAISE EXCEPTION 'Fallo de semillas: se esperaban 5 reglas';
  END IF;
END $$;
COMMIT;

-- Confirma que los triggers ya existen en el DDL restaurado.
-- La prueba de escritura se revierte para no conservar datos ni auditorias.
BEGIN;
INSERT INTO public.productos_prueba(nombre, precio)
VALUES ('AA-INSTALACION-LIMPIA', 10.00);
DO $$
BEGIN
 IF NOT EXISTS (
     SELECT 1 FROM public.bitacora_auditoria b
     JOIN public.detalle_bitacora d ON d.id_bitacora = b.id_bitacora
     JOIN public.columnas_auditadas c ON c.id_columna = d.id_columna
     JOIN public.tablas_auditadas t ON t.id_tabla = b.id_tabla
     JOIN public.eventos_auditoria e ON e.id_evento = b.id_evento
     WHERE t.nombre_tabla='productos_prueba'
       AND c.nombre_columna='nombre'
       AND e.nombre_evento='INSERT'
       AND d.valor_nuevo='AA-INSTALACION-LIMPIA'
 ) THEN
   RAISE EXCEPTION 'El trigger no registro el INSERT de prueba';
 END IF;
 RAISE NOTICE 'CORRECTO: nueva base, semillas y trigger INSERT funcionan';
END $$;
ROLLBACK;
