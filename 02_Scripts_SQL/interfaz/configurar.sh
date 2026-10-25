#!/usr/bin/env bash
# AutoAudit - Configurador interactivo seguro (solo autoaudit_restauracion).
# Requiere Ubuntu, Python 3, PostgreSQL 18, sudo y las tablas existentes.
# Desde la raiz del repositorio: bash interfaz/configurar.sh
set -euo pipefail
export AUTOAUDIT_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# El codigo Python se entrega como argumento, dejando stdin libre para el menu.
python3 -c "$(cat <<'PY'
import datetime
import os
import re
import subprocess
import sys
from pathlib import Path

DB = 'autoaudit_restauracion'
BASE = Path(os.environ['AUTOAUDIT_PROJECT_ROOT'])
RESULTADOS = Path(os.environ.get('AUTOAUDIT_OUT_DIR', str(BASE / 'salidas_locales')))
INTERNAS = ('bitacora_auditoria','columnas_auditadas','configuracion_auditoria',
            'detalle_bitacora','estaciones_trabajo','eventos_auditoria',
            'tablas_auditadas','usuarios_auditados')

def cmd(args, *, quiet=False):
    try:
        r = subprocess.run(args, text=True, capture_output=True, check=True)
        return r.stdout.strip()
    except FileNotFoundError:
        print('FALTA UNA HERRAMIENTA:', args[0])
        sys.exit(1)
    except subprocess.CalledProcessError as ex:
        print('ERROR al ejecutar la operacion:\n', (ex.stderr or ex.stdout or '').strip())
        if not quiet:
            print('No se confirmo ningun cambio nuevo. Revisa el mensaje y conserva el respaldo.')
        raise

def psql(sql, *, tuples=True):
    args=['sudo','-u','postgres','psql','-X','-v','ON_ERROR_STOP=1','-P','pager=off','-d',DB]
    if tuples:
        args += ['-qAt','-F','|']
    else:
        args += ['-P','format=aligned']
    args += ['-c',sql]
    return cmd(args)

def esc(value):
    return "'" + value.replace("'", "''") + "'"

def choose(items, label):
    if not items:
        print('No hay opciones disponibles.')
        return None
    for i,item in enumerate(items,1): print(f'{i}. {item}')
    print('0. Cancelar')
    try: chosen = int(input(label + ': ').strip())
    except (ValueError, EOFError): return None
    return items[chosen-1] if 1 <= chosen <= len(items) else None

def show_config():
    sql="""SELECT t.nombre_tabla,c.nombre_columna,e.nombre_evento,
         CASE WHEN t.activa AND c.activa AND cfg.activa THEN 'ACTIVA' ELSE 'INACTIVA' END
         FROM public.configuracion_auditoria cfg
         JOIN public.columnas_auditadas c USING(id_columna)
         JOIN public.tablas_auditadas t USING(id_tabla)
         JOIN public.eventos_auditoria e USING(id_evento)
         ORDER BY 1,2,3"""
    lines=psql(sql).splitlines()
    if lines: print('\nTABLA | COLUMNA | EVENTO | ESTADO\n'+'\n'.join(lines))
    else: print('Sin reglas configuradas.')

def get_tables():
    exclusions=','.join(esc(x) for x in INTERNAS)
    sql=f"""SELECT c.relname FROM pg_catalog.pg_class c
         JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
         WHERE n.nspname='public' AND c.relkind='r'
         AND c.relname NOT IN ({exclusions})
         ORDER BY c.relname"""
    return [x for x in psql(sql).splitlines() if x]

def get_cols(table):
    sql=f"""SELECT a.attname FROM pg_catalog.pg_attribute a
         JOIN pg_catalog.pg_class c ON c.oid=a.attrelid
         JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
         WHERE n.nspname='public' AND c.relname={esc(table)} AND c.relkind='r'
         AND a.attnum>0 AND NOT a.attisdropped ORDER BY a.attnum"""
    return [x for x in psql(sql).splitlines() if x]

def current(table,col,event):
    sql=f"""SELECT CASE WHEN t.activa AND c.activa AND cfg.activa THEN 'ACTIVA'
          ELSE 'INACTIVA' END
         FROM public.configuracion_auditoria cfg
         JOIN public.columnas_auditadas c USING(id_columna)
         JOIN public.tablas_auditadas t USING(id_tabla)
         JOIN public.eventos_auditoria e USING(id_evento)
         WHERE t.esquema='public' AND t.nombre_tabla={esc(table)}
         AND c.nombre_columna={esc(col)} AND e.nombre_evento={esc(event)} LIMIT 1"""
    return psql(sql) or 'SIN CONFIGURAR'

def make_sql(table,col,event,enabled,commit):
    # Todas las entradas fueron escogidas por indice desde el catalogo;
    # aun asi se escapan como literales SQL.
    table,col,event = esc(table),esc(col),esc(event)
    active='TRUE' if enabled else 'FALSE'
    save='COMMIT' if commit else 'ROLLBACK'
    # Validacion de cada columna en diccionario antes de escribir la configuracion.
    return f"""BEGIN;
SET SESSION AUTHORIZATION autoaudit_admin;
DO $autoconf$
DECLARE v_tab bigint; v_col bigint; v_evento bigint; v_count bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  JOIN pg_catalog.pg_attribute a ON a.attrelid=c.oid
  WHERE n.nspname='public' AND c.relkind='r' AND c.relname={table}
   AND a.attname={col} AND a.attnum>0 AND NOT a.attisdropped) THEN
   RAISE EXCEPTION 'La tabla/columna ya no existe: %.%',{table},{col};
 END IF;
 SELECT id_evento INTO v_evento FROM public.eventos_auditoria
  WHERE nombre_evento={event};
 IF v_evento IS NULL THEN RAISE EXCEPTION 'Evento inexistente: %',{event}; END IF;
 SELECT id_tabla INTO v_tab FROM public.tablas_auditadas
  WHERE esquema='public' AND nombre_tabla={table};
 IF v_tab IS NULL THEN
   IF NOT {active} THEN RAISE EXCEPTION 'No hay una regla que desactivar'; END IF;
   INSERT INTO public.tablas_auditadas(esquema,nombre_tabla,activa)
     VALUES('public',{table},TRUE) RETURNING id_tabla INTO v_tab;
 ELSIF {active} THEN
   UPDATE public.tablas_auditadas SET activa=TRUE WHERE id_tabla=v_tab;
 END IF;
 SELECT id_columna INTO v_col FROM public.columnas_auditadas
   WHERE id_tabla=v_tab AND nombre_columna={col};
 IF v_col IS NULL THEN
   IF NOT {active} THEN RAISE EXCEPTION 'Columna aun sin configurar'; END IF;
   INSERT INTO public.columnas_auditadas(id_tabla,nombre_columna,activa)
     VALUES(v_tab,{col},TRUE) RETURNING id_columna INTO v_col;
 ELSIF {active} THEN
   UPDATE public.columnas_auditadas SET activa=TRUE WHERE id_columna=v_col;
 END IF;
 SELECT count(*) INTO v_count FROM public.configuracion_auditoria
  WHERE id_columna=v_col AND id_evento=v_evento;
 IF v_count=0 THEN
   IF NOT {active} THEN RAISE EXCEPTION 'No existe esa regla para desactivar'; END IF;
   INSERT INTO public.configuracion_auditoria(id_columna,id_evento,activa)
     VALUES(v_col,v_evento,TRUE);
 ELSE
   UPDATE public.configuracion_auditoria SET activa={active}
     WHERE id_columna=v_col AND id_evento=v_evento;
 END IF;
END;
$autoconf$;
SELECT nombre_evento, t.nombre_tabla, c.nombre_columna, cfg.activa
 FROM public.configuracion_auditoria cfg
 JOIN public.columnas_auditadas c USING(id_columna)
 JOIN public.tablas_auditadas t USING(id_tabla)
 JOIN public.eventos_auditoria e USING(id_evento)
 WHERE t.esquema='public' AND t.nombre_tabla={table}
 AND c.nombre_columna={col} AND e.nombre_evento={event};
-- Solo sincronizar al activar. Al desactivar la funcion actual ignora reglas inactivas.
{ 'SELECT * FROM public.fn_sincronizar_triggers_autoaudit();' if enabled else '' }
{save};"""

def sql_file(content):
    import tempfile
    # PostgreSQL debe poder leer el archivo: /tmp en Linux.
    with tempfile.NamedTemporaryFile(prefix='autoaudit_cfg_',suffix='.sql',mode='w',
       encoding='utf-8',dir='/tmp',delete=False) as f:
        f.write(content+'\n'); name=f.name
    os.chmod(name,0o644)
    return name

def exec_script(sql):
    path=sql_file(sql)
    try:
        return cmd(['sudo','-u','postgres','psql','-X','-v','ON_ERROR_STOP=1',
            '-P','pager=off','-d',DB,'-f',path])
    finally:
        os.unlink(path)

def backup():
    RESULTADOS.mkdir(parents=True, exist_ok=True)
    stamp=datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    temporary=f'/tmp/autoaudit_config_pre_{stamp}.dump'
    target=RESULTADOS/f'autoaudit_pre_config_{stamp}.dump'
    try:
        cmd(['sudo','-u','postgres','pg_dump','-Fc','--no-owner','--no-privileges','-d',DB,'-f',temporary])
        cmd(['sudo','-u','postgres','pg_restore','-l',temporary])
        cmd(['sudo','cp',temporary,str(target)])
        print('Respaldo completo creado y verificado:',target)
    finally:
        subprocess.run(['sudo','rm','-f',temporary],capture_output=True)

def configure():
    print('\nTABLAS DE USUARIO (diccionario de PostgreSQL):')
    table=choose(get_tables(),'Numero de tabla')
    if table is None: return
    print('\nCOLUMNAS DE '+table+':')
    col=choose(get_cols(table),'Numero de columna')
    if col is None: return
    event=choose(['INSERT','UPDATE','DELETE'],'Tipo de operacion')
    if event is None:return
    action=choose(['ACTIVAR','DESACTIVAR'],'Que deseas hacer')
    if action is None:return
    enable=(action=='ACTIVAR')
    now=current(table,col,event)
    print(f'\nRESUMEN | public.{table}.{col} | {event} | ahora: {now} -> {action}')
    if (now=='ACTIVA' and enable) or (now=='INACTIVA' and not enable):
        print('Ese estado ya esta aplicado. No hacen falta cambios.')
        return
    if now=='SIN CONFIGURAR' and not enable:
        print('Esa regla no existe; no hay nada que desactivar.')
        return
    print('1. SIMULAR y revertir (recomendado)')
    print('2. APLICAR en autoaudit_restauracion (genera respaldo)')
    print('0. Cancelar')
    option=input('Opcion: ').strip()
    if option not in ('1','2'): return
    commit=(option=='2')
    if commit:
        confirm=input('Para aplicar escribe APLICAR: ').strip()
        if confirm!='APLICAR':
            print('Cancelado; sin cambios.')
            return
        backup()
    print('\nEjecutando ' + ('CAMBIO REAL' if commit else 'SIMULACION CON ROLLBACK') + ' ...')
    print(exec_script(make_sql(table,col,event,enable,commit)))
    print('Estado actual:',current(table,col,event))
    print('La base ORIGINAL autoaudit no se modifica.')

def main():
    print('AutoAudit | CONFIGURACION CONTROLADA')
    print('Base EXCLUSIVA:',DB)
    print('Este script usa sudo local; no pide la clave de PostgreSQL.')
    print('No modifica la base de datos original autoaudit.')
    # Fallar temprano si la base no existe o no se conoce el esquema.
    if psql('SELECT current_database()')!=DB:
        raise RuntimeError('Conexion inesperada: se cancela para proteger la base original.')
    required={'tablas_auditadas','columnas_auditadas','configuracion_auditoria','eventos_auditoria'}
    out=set(psql("SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'").splitlines())
    if not required <= out:
        raise RuntimeError('Faltan tablas de configuracion; no ejecutar cambios.')
    while True:
        print('\n1. Ver configuracion actual\n2. Configurar una tabla/columna/evento\n0. Salir')
        try: option=input('Opcion: ').strip()
        except EOFError: break
        try:
            if option=='1': show_config()
            elif option=='2':configure()
            elif option=='0':break
            else:print('Opcion invalida')
        except (subprocess.CalledProcessError,KeyboardInterrupt,EOFError):
            print('Operacion detenida; verifique la salida anterior.')
        except Exception as e:
            print('No se aplico la operacion:',e)

if __name__=='__main__':
    main()
PY
)"
