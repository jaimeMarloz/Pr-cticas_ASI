#!/usr/bin/env bash
# ============================================================================
#  Práctica 5 ASI — practica5_restaurar_progreso.sh
#  Restaura en ESTA máquina el paquete creado por practica5_exportar_progreso.sh
#
#  USO (dentro de la carpeta del laboratorio, con ./empresa up ya hecho):
#      ./practica5_restaurar_progreso.sh [-y] handoff_practica5_FECHA.tgz
#      ./practica5_restaurar_progreso.sh [-y] handoff_practica5_FECHA/   (carpeta)
#      -y / --si / --yes : no pedir confirmación (por defecto pregunta)
#
#  ORDEN DE LA RESTAURACIÓN
#    .env/config → roles.sql → BD empresa → filestore → Odoo arriba
#    → Metabase → Paperless → verificación de recuentos (paso 27)
#
#  El script detecta solo el nombre de proyecto de compose (el ayudante
#  ./empresa usa '-p empresa'), así que no hay que ajustar nada por eso.
#  Si aún no has hecho el primer arranque, el script te dirá cuándo:
#    copia el .env del paquete  →  ./empresa up  →  vuelve a lanzar este script.
#  NUNCA ejecutes ./empresa reset después de restaurar: destruye los volúmenes.
# ============================================================================
set -euo pipefail

### ====================== AJUSTES (revisar) ================================ ##
DB_SERVICE="db"                 # servicio PostgreSQL
ODOO_SERVICE="odoo"             # servicio Odoo (en algunos compose se llama "web")
PAPERLESS_SERVICE="paperless"   # a veces "paperless-ngx" o "webserver"
METABASE_SERVICE="metabase"
DB_NAME="empresa"               # BD de Odoo
ODOO_DATA_DIR="/var/lib/odoo"                # data_dir de Odoo (se sobreescribe con el data_dir.txt del paquete)
PAPERLESS_IMPORT_DIR="/tmp/import_handoff"   # carpeta de import DENTRO de Paperless
PAPERLESS_EXPORT_NAME="paperless_export"     # debe coincidir con PAPERLESS_EXPORT_DIR del script de export
METABASE_DB=""                  # "" salvo que Metabase use una BD propia (se detecta por metabase_db.txt)
### ========================================================================= ##

info(){ printf '\033[1;34m[ i ]\033[0m %s\n' "$*"; }
ok()  { printf '\033[1;32m[OK ]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[ ! ]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ X ]\033[0m %s\n' "$*" >&2; exit 1; }

# --- argumentos: -y / --si / --yes = no pedir confirmación -------------------
AUTO_CONFIRM=0
SRC=""
for a in "$@"; do
  case "$a" in
    -y|--si|--yes) AUTO_CONFIRM=1 ;;
    *) if [ -z "$SRC" ]; then SRC="$a"; else die "Argumento inesperado: '$a'. Uso: $0 [-y] <handoff....tgz | carpeta_handoff>"; fi ;;
  esac
done
[ -n "$SRC" ] || die "Uso: $0 [-y] <handoff....tgz | carpeta_handoff>"

cd "$(dirname "$0")"
COMPOSE_FILE="docker-compose.yml"
if [ ! -f "$COMPOSE_FILE" ]; then COMPOSE_FILE="compose.yml"; fi
if [ ! -f "$COMPOSE_FILE" ]; then
  die "Este script debe ejecutarse en la carpeta del laboratorio (donde esté el docker-compose.yml del zip)."
fi

if docker compose version >/dev/null 2>&1; then CC=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then CC=(docker-compose)
else die "No encuentro Docker Compose."; fi

# --- confirmación: la restauración reemplaza datos de ESTA máquina ------------
if [ "$AUTO_CONFIRM" != 1 ] && [ -t 0 ]; then
  warn "AVISO: esto REEMPLAZA la BD '$DB_NAME' y los datos de Metabase de ESTA máquina"
  warn "con el contenido del paquete '$SRC' (puedes cancelar antes de que se toque nada)."
  printf '¿Continuar? [s/N] '
  read -r RESP || true
  case "$RESP" in
    s|S|si|SI|y|Y|sí|SÍ) ;;
    *) die "Cancelado: no se ha modificado nada." ;;
  esac
fi

# --- localizar y descomprimir el paquete --------------------------------------
if [ -d "$SRC" ]; then
  HANDOFF="$SRC"
elif [ -f "$SRC" ]; then
  # Carpeta esperada: el nombre del tgz sin extensión (así la crea el export).
  # Para leer el nombre real dentro del tarball se usa sed y NO head: head
  # cierra la tubería al terminar, tar recibe SIGPIPE al seguir listando y,
  # con pipefail activo, fallaría aunque el paquete fuera perfecto.
  CAND="${SRC%.tgz}"
  if [ -d "$CAND" ] && [ -f "$CAND/roles.sql" ]; then
    HANDOFF="$CAND"
  else
    HANDOFF=$(tar tzf "$SRC" 2>/dev/null | sed -n '1{s#/.*$##p;}') || true
    if [ ! -d "$HANDOFF" ]; then
      info "Descomprimiendo '$SRC'…"
      tar xzf "$SRC" || die "Fallo al descomprimir '$SRC' (¿paquete incompleto? compara tamaño y SHA256SUMS.txt con el original)."
    fi
  fi
else
  die "No encuentro '$SRC'."
fi
[ -d "$HANDOFF" ] || die "No encuentro la carpeta del paquete (¿se descomprimió en otra parte?)."

[ -f "$HANDOFF/roles.sql" ]       || die "Falta roles.sql en el paquete."
[ -f "$HANDOFF/${DB_NAME}.dump" ] || die "Falta ${DB_NAME}.dump en el paquete (¿otro nombre de BD? ajusta DB_NAME arriba)."

# --- 1/6 .env y config del compañero (ANTES de restaurar nada) -----------------
# Así las contraseñas del paso 25 casan con las del paquete. Se guarda copia
# de tus ficheros previos si eran distintos.
info "1/6  Copiando .env y config/ del compañero…"
if [ -f "$HANDOFF/.env" ]; then
  if [ -f .env ] && ! cmp -s .env "$HANDOFF/.env"; then
    cp .env ".env.pre_handoff_$(date +%Y%m%d_%H%M)"
    warn "Tu .env era distinto: copia guardada como .env.pre_handoff_*"
  fi
  cp "$HANDOFF/.env" .env
  ok ".env del compañero aplicado"
fi
if [ -d "$HANDOFF/config" ]; then
  mkdir -p config
  cp -r "$HANDOFF/config/." config/
  ok "config/ aplicado (odoo.conf: list_db, proxy_mode, …)"
fi

# ficheros de trabajo (registro de cambios, drawio, scripts, checklist…)
if [ -d "$HANDOFF/scripts" ]; then
  mkdir -p scripts
  cp "$HANDOFF/scripts/"*.py scripts/ 2>/dev/null || true
  ok "scripts/*.py copiados (incluye leer_pedidos.py modificado)"
fi
for f in "$HANDOFF"/*.drawio "$HANDOFF"/*registro* "$HANDOFF"/*notas* "$HANDOFF"/checklist_Practica5_ASI.md; do
  if [ -f "$f" ]; then cp "$f" .; fi
done

# --- credenciales desde .env ---------------------------------------------------
env_val(){ grep -m1 -E "^$1=" .env 2>/dev/null | cut -d= -f2- | sed 's/^"//;s/"$//' || true; }
DB_USER=$(env_val POSTGRES_USER); DB_USER=${DB_USER:-odoo}
DB_PASS=$(env_val POSTGRES_PASSWORD)
[ -z "$DB_PASS" ] && DB_PASS=$(env_val DB_PASSWORD) || true

# --- resolución de contenedores por etiquetas de compose ------------------------
# Funciona aunque el ayudante ./empresa use un nombre de proyecto explícito
# (-p empresa): los contenedores llevan las etiquetas
# com.docker.compose.service / .project / .project.working_dir.
cid(){
  local svc="$1" id=""
  for wd in "$(pwd -P)" "$(pwd)"; do
    id=$(docker ps -q --filter "label=com.docker.compose.service=$svc" \
                    --filter "label=com.docker.compose.project.working_dir=$wd" 2>/dev/null | head -n1) || true
    if [ -n "$id" ]; then break; fi
  done
  if [ -z "$id" ]; then
    id=$(docker ps -q --filter "label=com.docker.compose.service=$svc" 2>/dev/null | head -n1) || true
  fi
  printf '%s' "$id"
}

detectar_proyecto(){
  local p=""
  for wd in "$(pwd -P)" "$(pwd)"; do
    p=$(docker ps --filter "label=com.docker.compose.service=$DB_SERVICE" \
               --filter "label=com.docker.compose.project.working_dir=$wd" \
               --format '{{.Label "com.docker.compose.project"}}' 2>/dev/null | head -n1) || true
    if [ -n "$p" ]; then printf '%s' "$p"; return 0; fi
  done
  p=$(docker ps --filter "label=com.docker.compose.service=$DB_SERVICE" \
             --format '{{.Label "com.docker.compose.project"}}' 2>/dev/null | head -n1) || true
  printf '%s' "$p"
}

DB_ID=$(cid "$DB_SERVICE")
if [ -z "$DB_ID" ]; then
  warn "No encuentro el contenedor del servicio '$DB_SERVICE'."
  info "Si es el primer arranque: ./empresa up (necesita internet, tarda un rato)."
  info "Cuando ./empresa status muestre los contenedores, vuelve a lanzar este script."
  exit 2
fi
ODOO_ID=$(cid "$ODOO_SERVICE")
[ -n "$ODOO_ID" ] || die "No encuentro el servicio '$ODOO_SERVICE' (¿./empresa up?). Revisa la sección AJUSTES."
PPR_ID=$(cid "$PAPERLESS_SERVICE")
[ -n "$PPR_ID" ] || die "No encuentro el servicio '$PAPERLESS_SERVICE' (¿./empresa up?). Revisa la sección AJUSTES."
MB_ID=$(cid "$METABASE_SERVICE")
if [ -z "$MB_ID" ]; then warn "Metabase no está en marcha: restauraré lo demás y saltaré su parte de volumen."; fi

# --- proyecto de compose explícito, para stop/start/up -d -----------------------
PROYECTO=$(detectar_proyecto)
if [ -n "$PROYECTO" ]; then
  CC=(${CC[@]} -f "$COMPOSE_FILE" -p "$PROYECTO")
  ok "proyecto compose detectado: '$PROYECTO'"
else
  info "no he detectado nombre de proyecto: uso la resolución por defecto de compose"
  info "(si falla, mira 'docker compose ls' y exporta COMPOSE_PROJECT_NAME=<nombre>)"
fi

# --- 2/6 roles y contraseñas ------------------------------------------------------
# Los avisos "role already exists" son NORMALES (el rol odoo ya existe en un
# clúster recién inicializado): lo importante son los ALTER ROLE ... PASSWORD
# y el CREATE ROLE metabase_ro que vienen después.
info "2/6  Aplicando roles y contraseñas de PostgreSQL…"
docker exec -i "$DB_ID" psql -U "$DB_USER" -d postgres < "$HANDOFF/roles.sql" >/dev/null 2>&1 || true
if docker exec "$DB_ID" psql -U "$DB_USER" -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='metabase_ro'" | grep -q 1; then
  ok "roles aplicados (metabase_ro presente)"
else
  warn "metabase_ro no figura en el paquete: ¿se hizo antes del paso 16? Créalo a mano (bloque 5)."
fi

# comprobación del clásico lío de contraseñas (rol restaurado vs .env)
if [ -n "$DB_PASS" ]; then
  if docker exec -e PGPASSWORD="$DB_PASS" "$DB_ID" psql -U "$DB_USER" -h 127.0.0.1 -d postgres -tAc "SELECT 1" >/dev/null 2>&1; then
    ok "la contraseña de .env casa con el rol restaurado"
  else
    warn "La contraseña de .env NO casa con la del rol restaurado."
    info "  Usa el .env del paquete (ya copiado) o redefine la contraseña del rol:"
    info "  docker exec -it $DB_ID psql -U $DB_USER -c \"ALTER USER $DB_USER WITH PASSWORD '<la de .env>';\""
  fi
fi

# --- 3/6 restaurar la BD de Odoo ---------------------------------------------------
info "3/6  Restaurando la BD '$DB_NAME' (drop + create + pg_restore)…"
# Se para POR ID DE CONTENEDOR (resuelto antes por etiquetas) y no con
# 'docker compose stop': aquí compose intentaba resolver un contenedor
# llamado literalmente 'odoo' ('No such container: odoo') porque el ayudante
# ./empresa despliega con su propia invocación, y un stop que no para nada
# deja sesiones abiertas que rompen el DROP.
docker stop "$ODOO_ID" >/dev/null || warn "docker stop (Odoo, id $ODOO_ID) devolvió un error: mira arriba. El DROP con FORCE cortará igualmente sus sesiones."
if [ -n "$MB_ID" ]; then
  docker stop "$MB_ID" >/dev/null || warn "docker stop (Metabase, id $MB_ID) devolvió un error: mira arriba. El DROP con FORCE cortará igualmente sus sesiones."
fi

# WITH (FORCE): PostgreSQL 13+ (el lab usa 15). Corta las sesiones que queden
# (autovacuum tras el pg_dump, una consola './empresa psql empresa' abierta en
# otro terminal, pools lentos por cerrar) y bloquea conexiones nuevas mientras
# se borra. Si una consola tuya se cierra sola, ha sido esto.
docker exec "$DB_ID" psql -U "$DB_USER" -v ON_ERROR_STOP=1 -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME WITH (FORCE);" >/dev/null \
  || die "No pude borrar '$DB_NAME'. Mira quién sigue conectado con: docker exec $DB_ID psql -U $DB_USER -d postgres -c \"SELECT pid, usename, application_name FROM pg_stat_activity WHERE datname='$DB_NAME'\""
docker exec "$DB_ID" psql -U "$DB_USER" -v ON_ERROR_STOP=1 -d postgres -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" >/dev/null \
  || die "No pude crear '$DB_NAME'."
docker exec -i "$DB_ID" pg_restore -U "$DB_USER" --no-owner -d "$DB_NAME" < "$HANDOFF/${DB_NAME}.dump" \
  || die "pg_restore falló (¿dump corrupto? comprueba contra SHA256SUMS.txt del paquete)."
ok "BD '$DB_NAME' restaurada"

# El DROP DATABASE pierde los ALTER DEFAULT PRIVILEGES del paso 16 (van por
# base de datos): los re-aplicamos para que Metabase pueda leer también las
# tablas que se creen en el futuro. Es un refuerzo silencioso del paso 16.
docker exec -i "$DB_ID" psql -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1 <<'SQL' || true
DO $do$
BEGIN
  IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'metabase_ro') THEN
    GRANT USAGE ON SCHEMA public TO metabase_ro;
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO metabase_ro;
    ALTER DEFAULT PRIVILEGES FOR ROLE CURRENT_USER IN SCHEMA public
      GRANT SELECT ON TABLES TO metabase_ro;
  END IF;
END
$do$;
SQL
ok "permisos de solo lectura de metabase_ro reforzados (paso 16)"

# --- 4/6 filestore de Odoo y arranque -----------------------------------------------
info "4/6  Filestore de Odoo y arranque…"
# data_dir: la misma ruta que usó el script de export (data_dir.txt del paquete)
if [ -f "$HANDOFF/data_dir.txt" ]; then
  read -r PKG_DD < "$HANDOFF/data_dir.txt" || true
  if [ -n "$PKG_DD" ]; then ODOO_DATA_DIR="$PKG_DD"; fi
fi
FS_RESTAURADO=0
FS_TGZ="$HANDOFF/filestore_${DB_NAME}.tgz"
if [ -f "$FS_TGZ" ]; then
  TMPFS=$(mktemp -d)
  tar xzf "$FS_TGZ" -C "$TMPFS" || die "No pude descomprimir el filestore."
  docker cp "$TMPFS/filestore" "${ODOO_ID}:${ODOO_DATA_DIR}/" >/dev/null \
    || die "No pude copiar el filestore al contenedor de Odoo (${ODOO_DATA_DIR})."
  rm -rf "$TMPFS"
  FS_RESTAURADO=1
  ok "filestore restaurado en ${ODOO_DATA_DIR}/filestore/${DB_NAME}"
else
  warn "El paquete no traía filestore (aún no había adjuntos): el paso 21 se hará sobre esta máquina."
fi

# Arrancar de nuevo lo parado, por id (docker start conserva el contenedor y
# los ids no cambian). Si hubieras copiado un .env distinto, el aviso del paso
# 2/6 ya te habrá orientado con la contraseña del rol.
docker start "$ODOO_ID" >/dev/null || warn "no pude re-arrancar Odoo (docker start $ODOO_ID); hazlo con ./empresa up"
if [ -n "$MB_ID" ]; then
  docker start "$MB_ID" >/dev/null || warn "no pude re-arrancar Metabase (docker start $MB_ID); hazlo con ./empresa up"
fi

info "Esperando a que Odoo responda en http://localhost:8069 …"
ODOO_OK=0
for i in $(seq 1 60); do
  if curl -sf -m 2 -o /dev/null "http://localhost:8069/"; then ODOO_OK=1; break; fi
  sleep 2
done
if [ "$ODOO_OK" = 1 ]; then
  ok "Odoo responde"
else
  warn "Odoo no responde tras 2 min (mira './empresa status' o los logs: docker logs --tail 20 $ODOO_ID)."
fi
if [ "$FS_RESTAURADO" = 1 ] && [ -n "$ODOO_ID" ]; then
  docker exec -u 0 "$ODOO_ID" chown -R odoo:odoo "${ODOO_DATA_DIR}/filestore/${DB_NAME}" >/dev/null 2>&1 \
    || warn "No pude reajustar el dueño del filestore. Si Odoo no muestra adjuntos, ejecuta a mano: docker exec -u 0 $ODOO_ID chown -R odoo:odoo ${ODOO_DATA_DIR}/filestore/${DB_NAME}"
fi

# --- 5/6 Metabase --------------------------------------------------------------------
info "5/6  Metabase…"
METABASE_DB_LOCAL=""
if [ -f "$HANDOFF/metabase_db.txt" ]; then METABASE_DB_LOCAL=$(cat "$HANDOFF/metabase_db.txt"); fi
if [ -n "$METABASE_DB_LOCAL" ]; then
  MB_DUMP="$HANDOFF/${METABASE_DB_LOCAL}.dump"
  [ -f "$MB_DUMP" ] || die "Falta ${METABASE_DB_LOCAL}.dump en el paquete."
  docker exec "$DB_ID" psql -U "$DB_USER" -v ON_ERROR_STOP=1 -d postgres -c "DROP DATABASE IF EXISTS $METABASE_DB_LOCAL WITH (FORCE);" >/dev/null
  docker exec "$DB_ID" psql -U "$DB_USER" -v ON_ERROR_STOP=1 -d postgres -c "CREATE DATABASE $METABASE_DB_LOCAL OWNER $DB_USER;" >/dev/null
  docker exec -i "$DB_ID" pg_restore -U "$DB_USER" --no-owner -d "$METABASE_DB_LOCAL" < "$MB_DUMP" >/dev/null 2>&1 \
    || die "Fallo restaurando la BD de Metabase."
  ok "BD de Metabase restaurada"
elif [ -f "$HANDOFF/metabase.tgz" ]; then
  if [ -z "$MB_ID" ]; then
    warn "Metabase no está en marcha: arráncalo ('${CC[*]} start $METABASE_SERVICE' o ./empresa up) y restaura a mano metabase.tgz"
  else
    MB_LINE=$(docker inspect "$MB_ID" --format '{{range .Mounts}}{{.Name}}:{{.Source}}:{{.Destination}}\n{{end}}' | grep -i metabase | head -n1) || MB_LINE=""
    if [ -n "$MB_LINE" ]; then
      MB_VOL=$(printf '%s' "$MB_LINE" | cut -d: -f1)
      MB_SRC=$(printf '%s' "$MB_LINE" | cut -d: -f2)
      warn "Se va a SUSTITUIR el contenido actual del volumen de Metabase por el del paquete."
      MB_TGZ=$(cd "$HANDOFF" && pwd)/metabase.tgz
      docker stop "$MB_ID" >/dev/null || die "No pude parar Metabase antes de restaurar su volumen (docker stop $MB_ID)."
      if [ -n "$MB_VOL" ]; then
        docker run --rm -v "$MB_VOL":/data -v "$MB_TGZ":/pkg:ro alpine \
          sh -c 'rm -rf /data/* /data/.[!.]* /data/..?* 2>/dev/null; tar xzf /pkg -C /data' \
          || die "Fallo restaurando el volumen de Metabase."
      else
        ( cd "$MB_SRC" && find . -mindepth 1 -maxdepth 1 -exec rm -rf {} + && tar xzf "$MB_TGZ" ) \
          || die "Fallo restaurando Metabase (bind mount en $MB_SRC)."
      fi
      docker start "$MB_ID" >/dev/null || warn "no pude re-arrancar Metabase: hazlo con './empresa up' o 'docker start $MB_ID'"
      ok "volumen de Metabase restaurado"
    else
      warn "No localizo el volumen de Metabase en tu equipo: mira 'docker inspect $MB_ID' y restaura a mano metabase.tgz"
    fi
  fi
else
  warn "El paquete no traía datos de Metabase: rehaz preguntas y cuadro de mando (pasos 17-18)."
fi
if [ -n "$MB_ID" ]; then
  docker start "$MB_ID" >/dev/null || warn "no pude re-arrancar Metabase: hazlo con './empresa up' o 'docker start $MB_ID'"
fi

# --- 6/6 Paperless ---------------------------------------------------------------------
info "6/6  Paperless…"
if [ -f "$HANDOFF/paperless_export.tgz" ]; then
  TMPPP=$(mktemp -d)
  tar xzf "$HANDOFF/paperless_export.tgz" -C "$TMPPP" || die "No pude descomprimir la exportación de Paperless."
  docker cp "$TMPPP/$PAPERLESS_EXPORT_NAME" "${PPR_ID}:${PAPERLESS_IMPORT_DIR}" >/dev/null \
    || die "No pude copiar la exportación al contenedor de Paperless."
  docker exec "$PPR_ID" document_importer "$PAPERLESS_IMPORT_DIR" \
    || warn "document_importer falló; prueba a mano: docker exec -it $PPR_ID document_importer $PAPERLESS_IMPORT_DIR"
  rm -rf "$TMPPP"
  ok "documentos importados en Paperless"
else
  warn "El paquete no traía exportación de Paperless: rehaz los pasos 19-21."
fi

# --- verificación de recuentos (paso 27) --------------------------------------------------
COUNTS_SQL="SELECT 'pedidos_venta' AS clave, count(*) AS valor FROM sale_order
UNION ALL SELECT 'contactos', count(*) FROM res_partner
UNION ALL SELECT 'productos', count(*) FROM product_template
UNION ALL SELECT 'asientos', count(*) FROM account_move
UNION ALL SELECT 'lineas_asiento', count(*) FROM account_move_line
UNION ALL SELECT 'registros_stock', count(*) FROM stock_quant
ORDER BY 1;"

ORIG="$HANDOFF/verificacion_origen.txt"
if [ -f "$ORIG" ]; then
  info "Verificando recuentos contra el origen (paso 27)…"
  TMPV=$(mktemp)
  docker exec "$DB_ID" psql -U "$DB_USER" -d "$DB_NAME" -A -F ' ' -t -c "$COUNTS_SQL" > "$TMPV"
  TODO_OK=1
  while read -r k v; do
    [ -n "$k" ] || continue
    vo=$(grep -E "^$k " "$ORIG" | awk '{print $2}' || true)
    if [ "$vo" = "$v" ]; then
      printf '    \033[1;32mOK\033[0m  %-16s %s\n' "$k" "$v"
    else
      printf '    \033[1;31m X \033[0m %-16s origen=%s restaurado=%s\n' "$k" "${vo:-?}" "$v"
      TODO_OK=0
    fi
  done < "$TMPV"
  rm -f "$TMPV"
  if [ "$TODO_OK" = 1 ]; then
    ok "verificación superada: el progreso del compañero está entero"
  else
    warn "hay recuentos distintos: ¿restauraste sobre datos viejos, o el paquete se hizo a mitad de un paso?"
  fi
else
  warn "El paquete no traía verificacion_origen.txt: cuenta a mano pedidos, contactos y asientos."
fi

echo
info "Restauración terminada. Comprobaciones manuales recomendadas:"
info "  - Odoo       http://localhost:8069   (usuario/contraseña del compañero: mira sus notas)"
info "  - Paperless  http://localhost:8000  ·  Metabase  http://localhost:3000"
info "  - ./empresa status  → contenedores en marcha"
warn "A partir de ahora NO ejecutes ./empresa reset: destruiría los volúmenes y todo lo restaurado."
info "Sigue por la checklist incluida (checklist_Practica5_ASI.md) desde el último paso marcado."
