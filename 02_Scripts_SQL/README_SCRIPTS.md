# 02 - Código y scripts SQL

Mantuvimos **intacta la estructura relativa que emplean los scripts**: los lanzadores (`iniciar.sh`, `validar_archivos.sh`, `prueba_instalacion_limpia.sh`) están junto a los directorios `sql/`, `interfaz/`, `consulta/` y `pruebas/`.

## Uso de la versión de pruebas

Ejecutar desde Ubuntu, con PostgreSQL 18 y una base `autoaudit_restauracion` ya configurada:

```bash
bash 02_Scripts_SQL/validar_archivos.sh
bash 02_Scripts_SQL/iniciar.sh
bash 02_Scripts_SQL/interfaz/configurar.sh
bash 02_Scripts_SQL/consulta/consultas.sh
```

Los comandos anteriores son orientativos. `validar_archivos.sh` **solo verifica sintaxis y rutas**. Los demás acceden a una base PostgreSQL, por lo que se debe revisar cada operación antes de ejecutarla. El ensayo de instalación limpia `prueba_instalacion_limpia.sh` crea una base de datos adicional y solicita confirmación explícita.

Las versiones antiguas dentro de `sql/historico_no_ejecutar/` son únicamente referencia histórica: **no deben sustituir el código vigente**.

### Seguridad

- `revisar_seguridad.sh`: diagnóstico de solo lectura.
- `verificar_y_ajustar_seguridad.sh`: solicita confirmación, realiza respaldo y ajusta `EXECUTE` en la base restaurada.
- `restringir_funciones.sql`: SQL de dicho ajuste.

En un despliegue nuevo, comprobar que las funciones con `SECURITY DEFINER` pertenezcan a un rol limitado. El usuario propietario puede modificar la bitácora y esta limitación continúa pendiente de resolver para entornos de producción.
