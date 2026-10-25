# AutoAudit — Sistema de auditoría de PostgreSQL 18

**Proyecto académico de base de datos**, realizado en PostgreSQL 18, Ubuntu y Oracle VirtualBox. El repositorio se organiza con los mismos cuatro apartados usados en la entrega: base de datos, scripts, evidencias y documentación.

## Contenido del proyecto

| Carpeta | Contenido |
|---|---|
| [`01_Base_Datos`](01_Base_Datos/) | Esquema SQL real y datos iniciales reproducibles para una base de prueba. |
| [`02_Scripts_SQL`](02_Scripts_SQL/) | Funciones PL/pgSQL, triggers, configurador de consola, consultas y pruebas. |
| [`03_Evidencias`](03_Evidencias/) | Capturas de pruebas, configuración, auditoría, IP, rendimiento, seguridad e instalación limpia. |
| [`04_Documentacion`](04_Documentacion/) | Informe técnico, manuales, diagrama E-R, checklist y enunciado del proyecto. |

## Funcionalidades verificadas

- Auditoría de operaciones **INSERT, UPDATE y DELETE**, configurable por tabla, columna y evento.
- Cinco reglas verificadas, incluidas `productos_prueba.nombre / INSERT` y `productos_prueba.precio / UPDATE`.
- Historial consultable por usuario y columna, valores anteriores y nuevos y fecha de evento.
- Registro de IP de cliente mediante TCP local (`127.0.0.1`), en columna `ip_origen` tipo `inet`.
- Rol `autoaudit_lector` con acceso de solo lectura a bitácoras.
- Pruebas de rendimiento con 100 y 1,000 registros **con** trigger, sin línea base equivalente sin trigger.
- Respaldo, restauración y prueba de instalación limpia en base aislada.
- Restricción de `EXECUTE` para `PUBLIC` en funciones sensibles; comprobación de regresión con `ROLLBACK`.

## Iniciar la versión de consola en el entorno de pruebas

**Prerrequisitos:** Linux/Ubuntu, `bash`, `python3`, `sudo`, servidor y cliente PostgreSQL 18, roles y base de pruebas configurados. El menú principal utiliza `autoaudit_restauracion` y no realiza por sí solo una instalación inicial.

```bash
bash 02_Scripts_SQL/validar_archivos.sh
bash 02_Scripts_SQL/iniciar.sh
bash 02_Scripts_SQL/interfaz/configurar.sh
bash 02_Scripts_SQL/consulta/consultas.sh
```

**Instalación reproducible en nueva base (entorno de ensayo):**

```bash
bash 02_Scripts_SQL/prueba_instalacion_limpia.sh
```

Esta última operación **crea una base nueva** y requiere confirmación; revisar el script antes de ejecutarlo. Los scripts de uso diario apuntan a una base de pruebas existente, nunca a una instancia de producción. El esquema y las semillas están también en `01_Base_Datos/`; se conserva una copia de ambos en `02_Scripts_SQL` para mantener las rutas relativas de los comandos verificados.

## Alcance de los datos

Se adjuntan las **capturas originales y los datos de muestra disponibles**, sin ocultar los valores de ejemplo mostrados en el trabajo académico. `semillas_y_prueba.sql` reproduce los catálogos y reglas principales.

**No se dispone aquí del respaldo binario `.dump` ni de los CSV exportados directamente desde Ubuntu**: no estaban entre los archivos compartidos para la compilación de este repositorio. Se describen en el informe y en las evidencias, pero no se simula su presencia ni se inventan datos. Para incluirlos, primero deben exportarse desde la máquina virtual y verificarse.

## Limitaciones declaradas

- **Seguridad:** el propietario `autoaudit_admin` aún puede modificar directamente las tablas de bitácora; falta una separación estricta de roles antes de un uso de producción.
- **Rendimiento:** se carece de medición comparable sin trigger que cuantifique la sobrecarga.
- **Interfaz:** la interfaz probada es de **consola**, no web; confirmar la aceptación por el docente.
- **Despliegue:** la instalación limpia se probó en base aislada con catálogos mínimos; no equivale a certificación de producción.

## Entrega

Fecha prevista: **3 de noviembre de 2026**. Los materiales se ofrecen como proyecto académico, con datos de prueba y evidencias. Confirmar la portada antes de entregar.
