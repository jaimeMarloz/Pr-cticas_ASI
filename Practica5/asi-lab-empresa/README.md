# Práctica 5: la empresa integrada

Laboratorio de **Administración de Sistemas Informáticos** (EPS Zamora, USAL, curso 2026/2027).
Una pequeña empresa ficticia, *Distribuciones Duero Norte S.L.*, con sus sistemas de información:

| Servicio | Para qué sirve | Dirección | Acceso inicial |
|---|---|---|---|
| Odoo 17 Community | ERP, CRM, compras, inventario y facturación | http://localhost:8069 | admin / admin |
| PostgreSQL 15 | Base de datos de Odoo (y origen de datos del BI) | solo interno | usuario y clave de `.env` |
| Metabase | Inteligencia de negocio y cuadros de mando | http://localhost:3000 | cuenta que creas la primera vez |
| Paperless-ngx | Gestión documental con OCR | http://localhost:8000 | admin / la de `.env` |
| Caddy | Proxy inverso con HTTPS (ampliación opcional) | https://odoo.localhost y similares | no arranca por defecto |

Todo es software libre y gratuito. No hay que registrarse en ningún sitio.

## Requisitos

- **Docker Desktop** (Mac, Windows o Linux) o Docker Engine con el plugin Compose. Sirve cualquier Mac, también con chip Apple Silicon.
- 8 GB de RAM en el equipo y **al menos 4 GB asignados a Docker** (Docker Desktop, Ajustes, Recursos).
- 10 GB de disco libres.
- Libres los puertos 8069, 3000, 8000, 80 y 443.
- En Windows, ejecuta los comandos desde **Git Bash** o **WSL**. Si prefieres PowerShell, al final tienes las órdenes equivalentes.

## Puesta en marcha

```bash
cd asi-lab-empresa
./empresa up
```

La primera vez descarga las imágenes (unos 2 GB) y crea la base de datos de Odoo instalando los módulos del curso. Tarda entre 5 y 15 minutos según la conexión. Las veces siguientes arranca en menos de un minuto.

Cuando termine, abre Odoo en http://localhost:8069 con `admin` / `admin`.
Metabase y Paperless tardan uno o dos minutos más en estar listos la primera vez.

## Órdenes del ayudante `./empresa`

| Orden | Qué hace |
|---|---|
| `./empresa up` | Arranca todo; la primera vez crea la base de datos de Odoo |
| `./empresa status` | Estado de los contenedores |
| `./empresa logs <servicio>` | Registros de `odoo`, `db`, `metabase` o `paperless` |
| `./empresa psql [base]` | Consola de PostgreSQL (por defecto, la base `empresa`) |
| `./empresa shell <servicio>` | Terminal dentro de un contenedor |
| `./empresa proxy` | Arranca también el proxy HTTPS (ampliación opcional) |
| `./empresa down` | Para los contenedores; los datos se conservan |
| `./empresa reset` | Borra contenedores **y datos** para empezar de cero |

## Qué hay en la carpeta

```
docker-compose.yml   definición de los servicios
.env                 contraseñas y variables (se cambian en el bloque 8)
empresa              ayudante con las órdenes anteriores
config/              odoo.conf y Caddyfile (el Caddyfile es solo para la ampliación opcional)
scripts/             leer_pedidos.py, ejemplo de integración por API (bloque 7)
datos/               CSV de productos, clientes y proveedores
documentos/          facturas, albarán y contrato de ejemplo (datos ficticios)
consume/             carpeta de entrada de Paperless
export/              exportaciones de Paperless (copias de seguridad)
backups/             aquí guardas tus copias de seguridad
```

## Si algo falla

- **`port is already allocated`**: otro programa usa ese puerto. Páralo o cambia el puerto de la izquierda en `docker-compose.yml` (por ejemplo `"8070:8069"`).
- **Odoo no abre o se queda cargando**: mira `./empresa logs odoo`. Si dice que no encuentra la base `empresa`, ejecuta `./empresa init`.
- **Contenedores que se reinician o mueren (código 137)**: falta memoria. Sube la memoria de Docker Desktop a 4 GB o más.
- **Metabase tarda mucho la primera vez**: es normal, inicializa su base interna. Espera dos minutos.
- **El IVA no aparece en una cuenta propia en los asientos (paso 8)**: al crear los impuestos del paso 4, abre la pestaña *Definición* y asigna una cuenta a la línea de tipo *Impuesto* (en facturas y en reembolsos): **251000 Tax Received** para el IVA 21 % de ventas y **131000 Tax Paid** para el de compras. Sin ello, el IVA se contabiliza junto a los ingresos.
- **Al validar la primera entrega aparece un aviso de SMS**: ciérralo; hasta entonces la entrega no queda validada.
- **Valores iniciales de Odoo**: la compañía arranca como *My Company* (EE. UU., USD) y trae dos impuestos del 15 % de ejemplo que no se usan; se cambian en el paso 4.
- **Quieres empezar de cero**: `./empresa reset` y después `./empresa up`.
- **Las imágenes no se descargan**: comprueba tu conexión y que Docker Desktop está arrancado.

## Órdenes equivalentes en PowerShell

```powershell
docker compose up -d db
docker compose exec -T db psql -U odoo -d postgres -c "CREATE DATABASE empresa OWNER odoo ENCODING 'UTF8' TEMPLATE template0"
docker compose run --rm --no-deps odoo odoo -d empresa -i base,contacts,crm,sale_management,stock,purchase,account,hr --without-demo=all --load-language=es_ES --stop-after-init
docker compose up -d
docker compose ps
docker compose down
```

## Aviso sobre los datos

La empresa, los clientes, los proveedores y todos los documentos son **ficticios**. Los CIF, IBAN y direcciones de correo (dominio `.example`) no corresponden a ninguna entidad real.
