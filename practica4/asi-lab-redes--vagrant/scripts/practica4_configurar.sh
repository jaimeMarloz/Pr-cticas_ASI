#!/usr/bin/env bash
# Configuración automatizada del estado final de la Práctica 4.
# Ejecutar DENTRO de la VM asi-redes, tras `vagrant up` y con Docker disponible.
# No aplica averías temporales de diagnóstico ni puede crear vídeo/diagrama.
set -Eeuo pipefail

readonly BASE="clab-asi"
readonly LOG="$HOME/practica4-configuracion-$(date +%F-%H%M%S).log"
mkdir -p "$HOME/practica4"
exec > >(tee -a "$LOG") 2>&1

step() { printf '\n== %s ==\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
nexec() { docker exec "${BASE}-$1" sh -c "$2"; }
nfile() { docker exec -i "${BASE}-$1" sh -c "cat > '$2'"; }
has_container() { docker inspect "${BASE}-$1" >/dev/null 2>&1; }

[[ $EUID -ne 0 ]] || echo "Nota: ejecutar como usuario vagrant si tiene acceso a Docker."
command -v docker >/dev/null || fail "No se encuentra docker. Ejecuta este script dentro de la VM."
docker info >/dev/null 2>&1 || fail "Docker no responde o este usuario no tiene permisos."

step "Paso 1: comprobar/desplegar topología"
if ! has_container gwa1 || [[ "$(docker inspect -f '{{.State.Running}}' "${BASE}-gwa1" 2>/dev/null || true)" != true ]]; then
  command -v lab >/dev/null || fail "Falta el comando lab."
  lab up
fi
for n in clia dmza gwa1 gwa2 gwb hostb srva swa wan; do
  has_container "$n" || fail "No está activo el nodo $n (contenedor ${BASE}-$n)."
  [[ "$(docker inspect -f '{{.State.Running}}' "${BASE}-$n")" == true ]] || fail "El nodo $n no está running."
done
lab status || true

step "Confirmación"
cat <<'EOF'
Este script aplica la configuración final del laboratorio, reemplaza direcciones
en interfaces de datos, configura VLAN/firewall y arranca servicios. No toca la
red de gestión eth0 ni ejecuta `lab reset`. Se basa en el plan de
Memoria_Practica4_ASI.md.
EOF
read -r -p "Escribe APLICAR para continuar: " answer
[[ "$answer" == "APLICAR" ]] || fail "Cancelado sin aplicar cambios."

step "Preflight de herramientas"
for n in gwa1 gwa2; do
  nexec "$n" 'for x in ip bridge vtysh wg nft dnsmasq chronyd keepalived pgrep; do command -v "$x" >/dev/null 2>&1 || { echo "Falta $x"; exit 1; }; done'
done
for n in srva dmza; do
  nexec "$n" 'command -v httpd >/dev/null 2>&1 && command -v ip >/dev/null 2>&1'
done
nexec clia 'command -v udhcpc >/dev/null 2>&1'
nexec swa 'command -v bridge >/dev/null 2>&1 && ip link show br0 >/dev/null 2>&1'

step "Pasos 2-8: diagnóstico base y plan VLSM"
cat > "$HOME/practica4/validar_vlsm.py" <<'PY'
#!/usr/bin/env python3
import ipaddress

parent = ipaddress.ip_network("10.10.0.0/24")
segments = [
    ipaddress.ip_network("10.10.0.0/25"),
    ipaddress.ip_network("10.10.0.128/27"),
    ipaddress.ip_network("10.10.0.160/28"),
]
for i, net in enumerate(segments):
    assert net.subnet_of(parent), f"{net} está fuera de {parent}"
    for other in segments[:i]:
        assert not net.overlaps(other), f"Solape: {net} con {other}"
    print(f"{net}: hosts {net.network_address + 1}–{net.broadcast_address - 1}, broadcast {net.broadcast_address}")
print("OK: subredes dentro del bloque y sin solapes.")
PY
python3 "$HOME/practica4/validar_vlsm.py"

# Diagnóstico inicial, guardado como evidencia; eth0 es gestión y se deja intacta.
for n in gwa1 srva wan; do
  {
    echo "===== $n ====="
    nexec "$n" 'ip -br link; ip -br addr; ip route; ip neigh'
  } >> "$HOME/practica4/diagnostico-inicial.txt"
done

step "Pasos 9-14: bridge VLAN y subinterfaces 802.1Q"
nexec swa '
set -eu
ip link set dev br0 type bridge vlan_filtering 1
ip link set br0 up
for p in eth1 eth2 eth3 eth4 eth5; do
  ip link set "$p" up
  for v in 1 10 20 30; do bridge vlan del dev "$p" vid "$v" 2>/dev/null || true; done
done
bridge vlan add dev eth3 vid 10 pvid untagged
bridge vlan add dev eth4 vid 20 pvid untagged
bridge vlan add dev eth5 vid 30 pvid untagged
for p in eth1 eth2; do
  bridge vlan add dev "$p" vid 10
  bridge vlan add dev "$p" vid 20
  bridge vlan add dev "$p" vid 30
done
bridge vlan show
'

for n in gwa1 gwa2; do
  if [[ "$n" == gwa1 ]]; then
    wan_ip=198.51.100.1
    a10=10.10.0.130/27; a20=10.10.0.2/25; a30=10.10.0.162/28
  else
    wan_ip=198.51.100.2
    a10=10.10.0.131/27; a20=10.10.0.3/25; a30=10.10.0.163/28
  fi
  nexec "$n" "set -eu
    ip link set eth1 up
    ip addr flush dev eth1
    ip addr add $wan_ip/24 dev eth1
    ip link set eth2 up
    for v in 10 20 30; do
      ip link show eth2.\$v >/dev/null 2>&1 || ip link add link eth2 name eth2.\$v type vlan id \$v
      ip addr flush dev eth2.\$v
      ip link set eth2.\$v up
    done
    ip addr add $a10 dev eth2.10
    ip addr add $a20 dev eth2.20
    ip addr add $a30 dev eth2.30
    ip route replace default via 198.51.100.254
    sysctl -w net.ipv4.ip_forward=1
  "
done

step "Pasos 12, 15-18: direccionamiento de equipos y sede B"
nexec srva 'set -eu; ip link set eth1 up; ip addr flush dev eth1; ip addr add 10.10.0.140/27 dev eth1; ip route replace default via 10.10.0.130'
nexec dmza 'set -eu; ip link set eth1 up; ip addr flush dev eth1; ip addr add 10.10.0.170/28 dev eth1; ip route replace default via 10.10.0.162'
nexec gwb 'set -eu; ip link set eth1 up; ip addr flush dev eth1; ip addr add 198.51.100.3/24 dev eth1; ip link set eth2 up; ip addr flush dev eth2; ip addr add 10.20.0.1/26 dev eth2; ip route replace default via 198.51.100.254; sysctl -w net.ipv4.ip_forward=1'
nexec hostb 'set -eu; ip link set eth1 up; ip addr flush dev eth1; ip addr add 10.20.0.2/26 dev eth1; ip route replace default via 10.20.0.1'
nexec wan 'set -eu; ip link set eth1 up; ip addr flush dev eth1; ip addr add 198.51.100.254/24 dev eth1'

step "Paso 19: OSPF en gwa1 y gwa2"
for n in gwa1 gwa2; do
  if [[ "$n" == gwa1 ]]; then rid=1.1.1.1; else rid=2.2.2.2; fi
  docker exec "${BASE}-$n" vtysh \
    -c 'configure terminal' \
    -c 'router ospf' \
    -c "ospf router-id $rid" \
    -c 'network 10.10.0.0/25 area 0' \
    -c 'network 10.10.0.128/27 area 0' \
    -c 'network 10.10.0.160/28 area 0' \
    -c 'end' -c 'write memory'
done

step "Pasos 20-22: servicios web de prueba"
nexec dmza 'mkdir -p /tmp/web; echo "<h1>Practica 4 - servidor DMZ</h1>" > /tmp/web/index.html; if ! ss -lnt | grep -q ":80"; then httpd -p 80 -h /tmp/web; fi'
nexec srva 'mkdir -p /tmp/interno; echo "<h1>Servicio interno srva</h1>" > /tmp/interno/index.html; if ! ss -lnt | grep -q ":8080"; then httpd -p 8080 -h /tmp/interno; fi'
nfile srva /tmp/50-practica4-netplan.yaml <<'EOF'
network:
  version: 2
  ethernets:
    eth1:
      addresses: [10.10.0.140/27]
      routes:
        - to: default
          via: 10.10.0.129
      nameservers:
        addresses: [10.10.0.130]
EOF

step "Pasos 23-25: DHCP, DNS interno y NTP"
nfile gwa1 /tmp/dnsmasq-practica4.conf <<'EOF'
interface=eth2.20
interface=eth2.10
interface=eth2.30
bind-interfaces
domain=asi.lab
local=/asi.lab/
dhcp-authoritative
dhcp-range=10.10.0.20,10.10.0.120,255.255.255.128,12h
dhcp-option=option:router,10.10.0.1
dhcp-option=option:dns-server,10.10.0.2
dhcp-leasefile=/tmp/dnsmasq-practica4.leases
log-dhcp
address=/gwa1.asi.lab/10.10.0.2
address=/gwa2.asi.lab/10.10.0.3
address=/srva.asi.lab/10.10.0.140
address=/dmza.asi.lab/10.10.0.170
EOF
nexec gwa1 'dnsmasq --test --conf-file=/tmp/dnsmasq-practica4.conf; if pgrep -x dnsmasq >/dev/null 2>&1; then echo "dnsmasq ya está activo; no se inicia una segunda instancia"; else dnsmasq --conf-file=/tmp/dnsmasq-practica4.conf; fi'
nexec clia 'ip addr flush dev eth1; udhcpc -i eth1 -q'
nfile gwa1 /tmp/chrony-practica4.conf <<'EOF'
port 123
allow 10.10.0.0/24
allow 10.20.0.0/26
local stratum 10
EOF
nexec gwa1 'if pgrep -x chronyd >/dev/null 2>&1; then echo "chronyd ya está activo"; else chronyd -f /tmp/chrony-practica4.conf; fi'

step "Pasos 26-29: túnel WireGuard y ruta de sede B"
nexec gwa1 'umask 077; wg genkey > /tmp/gwa1-wg.key; wg pubkey < /tmp/gwa1-wg.key > /tmp/gwa1-wg.pub'
nexec gwb 'umask 077; wg genkey > /tmp/gwb-wg.key; wg pubkey < /tmp/gwb-wg.key > /tmp/gwb-wg.pub'
GWA1_PUB="$(nexec gwa1 'cat /tmp/gwa1-wg.pub')"
GWB_PUB="$(nexec gwb 'cat /tmp/gwb-wg.pub')"
nexec gwa1 'ip link show wg0 >/dev/null 2>&1 || ip link add wg0 type wireguard'
nexec gwb 'ip link show wg0 >/dev/null 2>&1 || ip link add wg0 type wireguard'
nexec gwa1 "ip addr replace 10.99.0.1/30 dev wg0; wg set wg0 private-key /tmp/gwa1-wg.key listen-port 51820 peer '$GWB_PUB' endpoint 198.51.100.3:51820 allowed-ips 10.20.0.0/26,10.99.0.0/30 persistent-keepalive 25; ip link set wg0 up"
nexec gwb "ip addr replace 10.99.0.2/30 dev wg0; wg set wg0 private-key /tmp/gwb-wg.key listen-port 51820 peer '$GWA1_PUB' endpoint 198.51.100.1:51820 allowed-ips 10.10.0.0/24,10.99.0.0/30 persistent-keepalive 25; ip link set wg0 up; ip route replace 10.10.0.0/24 dev wg0"
docker exec "${BASE}-gwa1" vtysh \
  -c 'configure terminal' \
  -c 'ip prefix-list SITE-B seq 5 permit 10.20.0.0/26' \
  -c 'route-map SITE-B permit 10' \
  -c 'match ip address prefix-list SITE-B' \
  -c 'ip route 10.20.0.0/26 10.99.0.2' \
  -c 'router ospf' \
  -c 'redistribute static route-map SITE-B' \
  -c 'end' -c 'write memory'

step "Pasos 30-36: firewall con estado, NAT de salida y DNAT"
for n in gwa1 gwa2; do
  nfile "$n" /tmp/practica4-firewall.nft <<'EOF'
flush ruleset
table inet filter {
  chain input {
    type filter hook input priority filter; policy drop;
    iifname "lo" accept
    iifname "eth0" accept
    ct state established,related accept
    ip protocol icmp accept
    ip protocol 89 accept
    ip protocol 112 accept
    iifname "eth1" udp dport 51820 accept
    iifname "eth2.20" udp dport 67 accept
    ip saddr { 10.10.0.0/24, 10.20.0.0/26 } udp dport 53 accept
    ip saddr { 10.10.0.0/24, 10.20.0.0/26 } tcp dport 53 accept
    udp dport 123 ip saddr { 10.10.0.0/24, 10.20.0.0/26 } accept
  }
  chain forward {
    type filter hook forward priority filter; policy drop;
    ct state established,related accept
    iifname { "eth2.10", "eth2.20", "wg0" } oifname { "eth2.10", "eth2.20" } ip protocol icmp accept
    iifname { "eth2.10", "eth2.20" } oifname "wg0" ip daddr 10.20.0.0/26 ip protocol icmp counter accept
    iifname "eth2.20" oifname "eth2.10" ip daddr 10.10.0.128/27 tcp dport 8080 counter accept
    iifname "eth2.20" oifname "eth2.30" ip daddr 10.10.0.160/28 tcp dport 80 counter accept
    iifname "wg0" oifname "eth2.10" ip saddr 10.20.0.0/26 ip daddr 10.10.0.140 tcp dport 8080 counter accept
    iifname "eth1" oifname "eth2.30" ip daddr 10.10.0.170 tcp dport 80 ct status dnat counter accept
    iifname { "eth2.10", "eth2.20" } oifname "eth1" tcp dport { 80, 443 } counter accept
    iifname { "eth2.10", "eth2.20" } oifname "eth1" udp dport 53 accept
  }
  chain output {
    type filter hook output priority filter; policy accept;
  }
}
table ip nat {
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    iifname "eth1" tcp dport 8080 dnat to 10.10.0.170:80
  }
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    oifname "eth1" ip saddr 10.10.0.0/24 masquerade
    oifname "eth1" ip saddr 10.20.0.0/26 masquerade
  }
}
EOF
  nexec "$n" 'nft -c -f /tmp/practica4-firewall.nft && nft -f /tmp/practica4-firewall.nft'
done

step "Pasos 37-40: redes Docker"
if ! docker network inspect practica4-net >/dev/null 2>&1; then
  docker network create --driver bridge --subnet 172.30.50.0/24 practica4-net
fi
if docker inspect p4-a >/dev/null 2>&1; then
  [[ "$(docker inspect -f '{{.State.Running}}' p4-a)" == true ]] || docker start p4-a >/dev/null
else
  docker run -d --name p4-a --network practica4-net --entrypoint sh asi-net:1.0 -c 'sleep 3600'
fi
if docker inspect p4-b >/dev/null 2>&1; then
  [[ "$(docker inspect -f '{{.State.Running}}' p4-b)" == true ]] || docker start p4-b >/dev/null
else
  docker run -d --name p4-b --network practica4-net --entrypoint sh asi-net:1.0 -c 'sleep 3600'
fi
if docker inspect p4-web >/dev/null 2>&1 && [[ "$(docker inspect -f '{{.State.Running}}' p4-web)" != true ]]; then
  docker rm p4-web >/dev/null
fi
if ! docker inspect p4-web >/dev/null 2>&1; then
  docker run -d --name p4-web --network practica4-net -p 8081:80 \
    --entrypoint sh asi-net:1.0 -c 'mkdir -p /tmp/www; echo "<h1>Docker Practica 4</h1>" >/tmp/www/index.html; exec httpd -f -p 80 -h /tmp/www'
fi

step "Pasos 41-44: VRRP"
for n in gwa1 gwa2; do
  if [[ "$n" == gwa1 ]]; then state=MASTER; priority=150; else state=BACKUP; priority=100; fi
  nfile "$n" /tmp/keepalived-practica4.conf <<EOF
vrrp_instance VI10 {
  state $state
  interface eth2.10
  virtual_router_id 10
  priority $priority
  advert_int 1
  virtual_ipaddress { 10.10.0.129/27 dev eth2.10 }
}
vrrp_instance VI20 {
  state $state
  interface eth2.20
  virtual_router_id 20
  priority $priority
  advert_int 1
  virtual_ipaddress { 10.10.0.1/25 dev eth2.20 }
}
vrrp_instance VI30 {
  state $state
  interface eth2.30
  virtual_router_id 30
  priority $priority
  advert_int 1
  virtual_ipaddress { 10.10.0.161/28 dev eth2.30 }
}
EOF
  nexec "$n" 'if pgrep -x keepalived >/dev/null 2>&1; then echo "keepalived ya está activo"; else keepalived -f /tmp/keepalived-practica4.conf; fi'
done
nexec srva 'ip route replace default via 10.10.0.129'
nexec dmza 'ip route replace default via 10.10.0.161'
nexec clia 'udhcpc -i eth1 -q'

step "Convergencia final OSPF y ruta sede B"
# Reafirma la configuración después de cargar el firewall y arrancar VRRP.
docker exec "${BASE}-gwa1" vtysh \
  -c 'configure terminal' \
  -c 'ip prefix-list SITE-B seq 5 permit 10.20.0.0/26' \
  -c 'route-map SITE-B permit 10' \
  -c 'match ip address prefix-list SITE-B' \
  -c 'ip route 10.20.0.0/26 10.99.0.2' \
  -c 'router ospf' \
  -c 'ospf router-id 1.1.1.1' \
  -c 'network 10.10.0.0/25 area 0' \
  -c 'network 10.10.0.128/27 area 0' \
  -c 'network 10.10.0.160/28 area 0' \
  -c 'redistribute static route-map SITE-B' \
  -c 'end' -c 'write memory'
docker exec "${BASE}-gwa2" vtysh \
  -c 'configure terminal' \
  -c 'router ospf' \
  -c 'ospf router-id 2.2.2.2' \
  -c 'network 10.10.0.0/25 area 0' \
  -c 'network 10.10.0.128/27 area 0' \
  -c 'network 10.10.0.160/28 area 0' \
  -c 'end' -c 'write memory'

ospf_ok=0
for attempt in $(seq 1 45); do
  neighbors_a="$(docker exec "${BASE}-gwa1" vtysh -c 'show ip ospf neighbor' 2>/dev/null || true)"
  neighbors_b="$(docker exec "${BASE}-gwa2" vtysh -c 'show ip ospf neighbor' 2>/dev/null || true)"
  routes_b="$(docker exec "${BASE}-gwa2" vtysh -c 'show ip route ospf' 2>/dev/null || true)"
  if grep -q 'Full' <<<"$neighbors_a" &&
     grep -q 'Full' <<<"$neighbors_b" &&
     grep -q '10.20.0.0/26' <<<"$routes_b"; then
    ospf_ok=1
    break
  fi
  sleep 1
done
if [[ "$ospf_ok" -ne 1 ]]; then
  echo "--- Diagnóstico OSPF gwa1 ---"
  docker exec "${BASE}-gwa1" vtysh -c 'show ip ospf interface' || true
  docker exec "${BASE}-gwa1" vtysh -c 'show ip ospf neighbor' || true
  docker exec "${BASE}-gwa1" vtysh -c 'show ip route 10.20.0.0/26' || true
  echo "--- Diagnóstico OSPF gwa2 ---"
  docker exec "${BASE}-gwa2" vtysh -c 'show ip ospf interface' || true
  docker exec "${BASE}-gwa2" vtysh -c 'show ip ospf neighbor' || true
  docker exec "${BASE}-gwa2" vtysh -c 'show ip route ospf' || true
  fail "OSPF no convergió o gwa2 no aprendió la ruta de sede B; revisa el diagnóstico anterior."
fi

step "Pasos 45-51: copia de configuración"
mkdir -p "$HOME/practica4/evidencias"
SAVE_DIR="$HOME/practica4/backup-$(date +%F-%H%M%S)"
mkdir -p "$SAVE_DIR"
echo "Ejecutando guardado privilegiado: sudo /usr/local/bin/lab save $SAVE_DIR"
sudo -v
sudo /usr/local/bin/lab save "$SAVE_DIR"
sudo chown -R "$(id -u):$(id -g)" "$SAVE_DIR"
cat <<EOF

Configuración automática finalizada. Log: $LOG
VLSM: $HOME/practica4/validar_vlsm.py
Diagnóstico inicial: $HOME/practica4/diagnostico-inicial.txt
Copia de configuraciones: $SAVE_DIR

Pendiente realizar y documentar manualmente:
 - Pruebas temporales de ARP/tcpdump, servicio solo en 127.0.0.1 y rutas/VLAN erróneas
   (restaurando inmediatamente el estado); no se ejecutan automáticamente.
 - Matriz completa desde cada origen, capturas de la WAN/túnel, mtr/iperf3 y averías
   controladas por el revisor.
 - Medir pérdida en failover VRRP, crear el diagrama draw.io, preparar el PDF y grabar
   la defensa. El script no puede acreditar que esas demostraciones se hayan hecho.
 - Revisar `nft list ruleset`, OSPF, WireGuard y servicios con el script verificador.
EOF
