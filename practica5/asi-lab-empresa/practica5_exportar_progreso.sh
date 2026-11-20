#!/usr/bin/env bash
# ============================================================================
#  Práctica 5 ASI — practica5_exportar_progreso.sh
#  Empaqueta TODO tu progreso del laboratorio para pasárselo a tu compañero.
#
#  USO (dentro de la carpeta del laboratorio, con ./empresa up en marcha):
#      ./practica5_exportar_progreso.sh [nombre_carpeta_salida]
#
#  Crea:  handoff_practica5_FECHA/  y  handoff_practica5_FECHA.tgz
#
#  CONTENIDO DEL PAQUETE
#    roles.sql                 roles y contraseñas de PostgreSQL (pasos 16 y 25)
#    empresa.dump              volcado de la BD de Odoo (bloques 2-4)
#    filestore_empresa.tgz     adjuntos de Odoo (paso 21) — solo si ya existen
#    data_dir.txt              ruta real del data_dir de Odoo
#    paperless_export.tgz      documentos + metadatos de Paperless (pasos 19-20)
#    metabase.tgz|metabase.dump  preguntas y cuadro de mando (pasos 17-18)
#    verificacion_origen.txt  recuentos de tablas (para el paso 27)
#    .env, config/, scripts/  tus ajustes y ficheros modificados
#    LEEME_companero.txt       instrucciones de restauración
#
#  El script detecta solo el nombre de proyecto de compose (el ayudante
#  ./empresa usa '-p empresa') y el data_dir de Odoo. Solo queda revisar
#  la sección AJUSTES contra el docker-compose.yml del zip del laboratorio
#  (los nombres de servicio se ven con ./empresa status).
#  NOTA (Windows): este script bash pasado por Git Bash/MSYS2 (UCRT64)
#  reescribe argumentos tipo /tmp/... a rutas de Windows al llegar a
#  docker.exe, y document_exporter fallaría "sin motivo". En Windows usa
#  la variante .ps1 (PowerShell) o lanza antes:  export MSYS_NO_PATHCONV=1
# ============================================================================
set -euo pipefail

### ====================== AJUSTES (revisar) ================================ ##
DB_SERVICE="db"                 # servicio PostgreSQL
ODOO_SERVICE="odoo"             # servicio Odoo (en algunos compose se llama "web")
PAPERLESS_SERVICE="paperless"   # a veces "paperless-ngx" o "webserver"
METABASE_SERVICE="metabase"
DB_NAME="empresa"               # BD de Odoo
PAPERLESS_EXPORT_DIR="/usr/src/paperless/export"  # montado en ./export del host (docker-compose.yml del lab)
METABASE_DB=""                  # "" si Metabase usa su propio volumen (lo habitual;
                                # se autodetecta una BD llamada 'metabase'). Pon el
                                # nombre a mano si en .env hay MB_DB_TYPE=postgres.
# Ficheros de trabajo que quieras incluir (rutas relativas a la carpeta del lab):
EXTRA_FILES=("checklist_Practica5_ASI.md" "Diagrama_Practica5.drawio" "notas_practica5.md")
### ========================================================================= ##

info(){ printf '\033[1;34m[ i ]\033[0m %s\n' "$*"; }
ok()  { printf '\033[1;32m[OK ]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[ ! ]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ X ]\033[0m %s\n' "$*" >&2; exit 1; }

cd "$(dirname "$0")"
COMPOSE_FILE="docker-compose.yml"
if [ ! -f "$COMPOSE_FILE" ]; then COMPOSE_FILE="compose.yml"; fi
if [ ! -f "$COMPOSE_FILE" ]; then
  die "Este script debe ejecutarse en la carpeta del laboratorio (donde esté el docker-compose.yml del zip)."
fi

if docker compose version >/dev/null 2>&1; then CC=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then CC=(docker-compose)
else die "No encuentro Docker Compose."; fi

# --- resolución de contenedores por etiquetas de compose ----------------------
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
  docker ps --format '        {{.Names}}  ({{.Status}})' >&2 || true
  die "No encuentro el servicio '$DB_SERVICE' entre los contenedores en marcha (listados arriba). ¿./empresa up? Si el servicio se llama distinto, ajústalo en la sección AJUSTES."
fi
ODOO_ID=$(cid "$ODOO_SERVICE")
[ -n "$ODOO_ID" ] || die "No encuentro el servicio '$ODOO_SERVICE' (mira los nombres arriba y la sección AJUSTES)."
PPR_ID=$(cid "$PAPERLESS_SERVICE")
[ -n "$PPR_ID" ] || die "No encuentro el servicio '$PAPERLESS_SERVICE' (mira los nombres arriba y la sección AJUSTES)."
MB_ID=$(cid "$METABASE_SERVICE")
[ -n "$MB_ID" ] || die "No encuentro el servicio '$METABASE_SERVICE' (mira los nombres arriba y la sección AJUSTES)."

# --- proyecto de compose explícito (para 'compose config' y el script gemelo) --
PROYECTO=$(detectar_proyecto)
if [ -n "$PROYECTO" ]; then
  CC=(${CC[@]} -f "$COMPOSE_FILE" -p "$PROYECTO")
  ok "proyecto compose detectado: '$PROYECTO'"
else
  info "no he detectado nombre de proyecto: uso la resolución por defecto de compose"
  info "(si algo falla, mira 'docker compose ls' y arranca con COMPOSE_PROJECT_NAME=<nombre>)"
fi

# --- credenciales desde .env (con valores por defecto razonables) ------------
env_val(){ grep -m1 -E "^$1=" .env 2>/dev/null | cut -d= -f2- | sed 's/^"//;s/"$//' || true; }
DB_USER=$(env_val POSTGRES_USER); DB_USER=${DB_USER:-odoo}
DB_PASS=$(env_val POSTGRES_PASSWORD)
[ -z "$DB_PASS" ] && DB_PASS=$(env_val DB_PASSWORD) || true
if [ ! -f .env ]; then warn "No veo .env: uso DB_USER='$DB_USER'. Si falla, ajusta a mano."; fi

# --- comprobación rápida: ¿podemos hablar con la BD? -------------------------
docker exec "$DB_ID" psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT 1" >/dev/null 2>&1 \
  || die "No puedo conectar a la BD '$DB_NAME' como '$DB_USER' (revisa DB_NAME/DB_USER arriba)."

# --- autodetectar si Metabase va sobre una BD propia de PostgreSQL ------------
if [ -z "$METABASE_DB" ]; then
  if docker exec "$DB_ID" psql -U "$DB_USER" -d postgres -tAc \
      "SELECT 1 FROM pg_database WHERE datname='metabase'" | grep -q 1; then
    METABASE_DB="metabase"
    info "detectada BD 'metabase' en PostgreSQL: exportaré Metabase desde ahí"
  fi
fi

STAMP=$(date +%Y%m%d_%H%M)
OUT="handoff_practica5_${STAMP}"
OUT="${1:-$OUT}"
mkdir -p "$OUT"

info "Exportando el progreso a ./$OUT"
info "  BD='$DB_NAME' usuario='$DB_USER' · servicios: $DB_SERVICE / $ODOO_SERVICE / $PAPERLESS_SERVICE / $METABASE_SERVICE"

# --- 1/7 roles y contraseñas ---------------------------------------------------
# IMPORTANTE: las contraseñas de los roles NO viajan dentro de pg_dump de una
# base de datos (son del clúster), por eso se exportan aparte con pg_dumpall.
info "1/7  Roles y contraseñas de PostgreSQL…"
docker exec "$DB_ID" pg_dumpall -U "$DB_USER" --roles-only > "$OUT/roles.sql"
ok "roles.sql (incluye metabase_ro y las contraseñas del paso 25)"

# --- 2/7 volcado de la BD de Odoo ----------------------------------------------
info "2/7  Volcado de la BD '$DB_NAME'…"
docker exec "$DB_ID" pg_dump -U "$DB_USER" -Fc "$DB_NAME" > "$OUT/${DB_NAME}.dump"
ok "${DB_NAME}.dump"

# --- 3/7 recuentos de verificación (paso 27 del compañero) ---------------------
info "3/7  Recuentos de verificación (paso 27 del compañero)…"
COUNTS_SQL="SELECT 'pedidos_venta' AS clave, count(*) AS valor FROM sale_order
UNION ALL SELECT 'contactos', count(*) FROM res_partner
UNION ALL SELECT 'productos', count(*) FROM product_template
UNION ALL SELECT 'asientos', count(*) FROM account_move
UNION ALL SELECT 'lineas_asiento', count(*) FROM account_move_line
UNION ALL SELECT 'registros_stock', count(*) FROM stock_quant
ORDER BY 1;"
docker exec "$DB_ID" psql -U "$DB_USER" -d "$DB_NAME" -A -F ' ' -t -c "$COUNTS_SQL" > "$OUT/verificacion_origen.txt"
ok "verificacion_origen.txt"

# --- 4/7 filestore de Odoo (adjuntos, p. ej. la factura del paso 21) ----------
info "4/7  Filestore de Odoo (adjuntos)…"
# Ruta real del data_dir (por defecto /var/lib/odoo; puede venir en config/odoo.conf).
# OJO: Odoo crea <data_dir>/filestore/<BD> de forma perezosa, solo cuando se
# guarda el primer adjunto: si aún no existe, no es un error, es que no hay adjuntos.
DATA_DIR=$(docker exec "$ODOO_ID" sh -c \
  'grep -hE "^[[:space:]]*data_dir[[:space:]]*=" /etc/odoo/odoo.conf 2>/dev/null | tail -n1' 2>/dev/null \
  | sed 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//') || true
if [ -n "$DATA_DIR" ]; then
  info "  data_dir (odoo.conf): $DATA_DIR"
else
  DATA_DIR="/var/lib/odoo"
  ALT=$(docker exec "$ODOO_ID" sh -c 'find /var/lib/odoo /home /opt /srv /mnt /data -maxdepth 4 -type d -name filestore 2>/dev/null | head -n1') || true
  if [ -n "$ALT" ]; then
    DATA_DIR=$(dirname "$ALT")
    warn "  filestore hallado fuera de la ruta habitual: data_dir=$DATA_DIR"
  else
    info "  data_dir por defecto: $DATA_DIR (sin rastro de filestore aún)"
  fi
fi
printf '%s\n' "$DATA_DIR" > "$OUT/data_dir.txt"   # el script de restauración usará esta misma ruta

FS="${DATA_DIR}/filestore/${DB_NAME}"
if docker exec "$ODOO_ID" test -d "$FS"; then
  TMPFS=$(mktemp -d)
  mkdir -p "$TMPFS/filestore"
  docker cp "${ODOO_ID}:${FS}" "$TMPFS/filestore/" >/dev/null \
    || die "No pude leer el filestore desde el contenedor Odoo."
  [ -d "$TMPFS/filestore/${DB_NAME}" ] || die "La copia del filestore no quedó donde esperaba."
  tar czf "$OUT/filestore_${DB_NAME}.tgz" -C "$TMPFS" "filestore"
  rm -rf "$TMPFS"
  ok "filestore_${DB_NAME}.tgz"
elif docker exec "$ODOO_ID" test -d "${DATA_DIR}/filestore"; then
  warn "Existe ${DATA_DIR}/filestore pero sin la subcarpeta '$DB_NAME': no exporto nada de ahí."
  warn "  (mira su contenido: docker exec $ODOO_ID ls ${DATA_DIR}/filestore)"
else
  warn "Todavía no existe '$FS': lo NORMAL si aún no hay adjuntos (se crean en el paso 21)."
  warn "El paquete seguirá sin filestore; el volcado de la BD se restaura igualmente."
fi

# --- 5/7 Paperless (document_exporter) ------------------------------------------
info "5/7  Paperless: document_exporter…"
# La carpeta de destino NO la crea document_exporter: exige que exista. Se usa
# la que el compose monta en ./export del host: existe SIEMPRE y no sufre los
# problemas de /tmp dentro del contenedor (bit sticky + carpetas creadas por
# root que luego 'paperless' no puede borrar ni escribir). Se limpia antes para
# que re-ejecutar no deje restos de una exportación anterior.
if [ ! -d export ]; then
  warn "No existe ./export: ¿estás en la carpeta del laboratorio? El paquete seguirá sin Paperless."
elif ! docker exec "$PPR_ID" test -d "$PAPERLESS_EXPORT_DIR" 2>/dev/null; then
  warn "El contenedor Paperless no ve '$PAPERLESS_EXPORT_DIR': revisa los volúmenes del compose."
else
  docker exec "$PPR_ID" sh -c "rm -rf '$PAPERLESS_EXPORT_DIR'/* '$PAPERLESS_EXPORT_DIR'/.[!.]* 2>/dev/null; true"
  # 1er intento como usuario 'paperless' (los ficheros quedan con uid 1000, el
  # mismo que tu usuario del host); si el uid no casa, reintento como root.
  if docker exec "$PPR_ID" document_exporter "$PAPERLESS_EXPORT_DIR" >/dev/null 2>&1 \
     || docker exec -u 0 "$PPR_ID" document_exporter "$PAPERLESS_EXPORT_DIR" >/dev/null 2>&1; then
    # document_exporter escribe los ficheros (originales, versiones OCR y
    # miniaturas) DIRECTAMENTE en la carpeta destino, sin subcarpeta
    # 'documents': se cuentan todos los ficheros no-JSON.
    NFICH=$(find export -type f ! -name '*.json' 2>/dev/null | wc -l) || NFICH=0
    if [ "${NFICH:-0}" -eq 0 ]; then
      warn "La exportación de Paperless está VACÍA (0 ficheros)."
      warn "  ¿Has hecho los pasos 19-21 (copiar documentos/ a consume/ y clasificar)?"
      warn "  Si no, el paquete llevará un Paperless vacío y quien restaure tendrá que rehacerlos."
    fi
    tar czf "$OUT/paperless_export.tgz" -C export . \
      || die "No pude empaquetar ./export."
    ok "paperless_export.tgz (${NFICH:-0} ficheros: originales, versiones OCR y miniaturas)"
  else
    warn "document_exporter falló: el paquete seguirá sin documentos de Paperless."
    warn "  Compruébalo a mano: docker exec -it $PPR_ID document_exporter $PAPERLESS_EXPORT_DIR"
  fi
fi

# --- 6/7 Metabase (preguntas + cuadro de mando) --------------------------------
info "6/7  Metabase…"
if [ -n "$METABASE_DB" ]; then
  docker exec "$DB_ID" pg_dump -U "$DB_USER" -Fc "$METABASE_DB" > "$OUT/${METABASE_DB}.dump"
  echo "$METABASE_DB" > "$OUT/metabase_db.txt"
  ok "${METABASE_DB}.dump (Metabase en PostgreSQL)"
else
  MB_LINE=$(docker inspect "$MB_ID" --format '{{range .Mounts}}{{.Name}}:{{.Source}}:{{.Destination}}\n{{end}}' | grep -i metabase | head -n1) || MB_LINE=""
  if [ -n "$MB_LINE" ]; then
    MB_VOL=$(printf '%s' "$MB_LINE" | cut -d: -f1)
    MB_SRC=$(printf '%s' "$MB_LINE" | cut -d: -f2)
    if [ -n "$MB_VOL" ]; then
      docker run --rm -v "$MB_VOL":/data:ro -v "$PWD/$OUT":/out alpine tar czf /out/metabase.tgz -C /data . >/dev/null \
        || die "Fallo tarendo el volumen de Metabase."
    else
      tar czf "$OUT/metabase.tgz" -C "$MB_SRC" . \
        || die "Fallo tarendo la carpeta de Metabase ($MB_SRC)."
    fi
    ok "metabase.tgz (volumen de Metabase)"
  else
    warn "No he localizado el volumen de Metabase: crea a mano una copia (docker inspect $METABASE_SERVICE) y guárdala como $OUT/metabase.tgz"
  fi
fi

# --- 7/7 ficheros de configuración y trabajo ------------------------------------
info "7/7  Ficheros de configuración y trabajo…"
if [ -f .env ]; then cp .env "$OUT/"; fi
if [ -d config ]; then cp -r config "$OUT/"; fi
if ls scripts/*.py >/dev/null 2>&1; then mkdir -p "$OUT/scripts"; cp scripts/*.py "$OUT/scripts/"; fi
for f in *.drawio *registro* *notas*; do
  if [ -f "$f" ]; then cp "$f" "$OUT/"; fi
done
for f in ${EXTRA_FILES[@]+"${EXTRA_FILES[@]}"}; do
  if [ -f "$f" ]; then
    cp "$f" "$OUT/"
  else
    warn "EXTRA_FILES: no encuentro '$f' (sigo sin él; añade ahí tu checklist/notas si las quieres en el paquete)."
  fi
done
ok ".env, config/ y ficheros de trabajo copiados"

# --- LEEME para el compañero ------------------------------------------------------
cat > "$OUT/LEEME_companero.txt" <<'EOF'
PAQUETE DE PROGRESO — Práctica 5 ASI (Distribuciones Duero Norte S.L.)
=====================================================================

Cómo continuar donde lo dejó tu compañero:

 1) Descomprime el zip original del laboratorio (Studium) en una carpeta nueva.
 2) Copia ENCIMA el .env y la carpeta config/ de este paquete
    (llevan las contraseñas cambiadas en el paso 25).
 3) Primer arranque:   ./empresa up        (necesita internet, tarda un rato)
    Comprueba con ./empresa status que los contenedores están en marcha.
 4) Copia los dos scripts junto al docker-compose.yml y ejecuta:
        ./practica5_restaurar_progreso.sh <este_paquete>.tgz
    Restaura BD, filestore, Paperless y Metabase, y compara los recuentos
    (el paso 27, restauración probada, te sale gratis).
 5) NO ejecutes ./empresa reset nunca: borra los volúmenes y todo esto.

Recordatorios:
 - Las contraseñas de Odoo/Paperless/Metabase están en las notas o el
   registro de cambios incluidos en el paquete.
 - Los recuentos correctos (pedidos, contactos, asientos…) están en
   verificacion_origen.txt: sírvelte para comprobar la restauración.
 - Si el paquete no trae filestore_empresa.tgz es que no había adjuntos
   todavía: no pasa nada, esos datos van aparte del dump de la BD.
EOF

# --- imágenes y sumas ---------------------------------------------------------------
{ $CC config --images 2>/dev/null || docker images --format '{{.Repository}}:{{.Tag}}'; } > "$OUT/imagenes.txt" || true
if command -v sha256sum >/dev/null 2>&1; then
  ( cd "$OUT" && find . -maxdepth 1 -type f ! -name SHA256SUMS.txt -exec sha256sum {} \; > SHA256SUMS.txt )
elif command -v shasum >/dev/null 2>&1; then
  ( cd "$OUT" && find . -maxdepth 1 -type f ! -name SHA256SUMS.txt -exec shasum -a 256 {} \; > SHA256SUMS.txt )
fi

# --- paquete final --------------------------------------------------------------------
tar czf "${OUT}.tgz" "$OUT"
ok "PAQUETE LISTO: ${OUT}.tgz"
info "Contenido y tamaños:"
du -sh "$OUT"/* | sed 's/^/    /'
echo
warn "El paquete lleva credenciales (.env y roles.sql): pásalo por un canal seguro."
info "Avisa a tu compañero: copia el .env del paquete ANTES del primer ./empresa up;"
info "después  ./empresa up  →  ./practica5_restaurar_progreso.sh ${OUT}.tgz"
