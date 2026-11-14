#!/usr/bin/env bash
# Verifica el estado observable de la configuración final de la Práctica 4.
# Ejecutar DENTRO de la VM asi-redes tras `vagrant ssh`.
set -u

readonly BASE="clab-asi"
PASS=0
FAIL=0
WARN=0

nexec() { docker exec "${BASE}-$1" sh -c "$2"; }
check() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf 'PASS  %s\n' "$name"; PASS=$((PASS + 1))
  else
    printf 'FAIL  %s\n' "$name"; FAIL=$((FAIL + 1))
  fi
}
node_check() {
  local name="$1" node="$2" cmd="$3"
  if nexec "$node" "$cmd" >/dev/null 2>&1; then
    printf 'PASS  %s\n' "$name"; PASS=$((PASS + 1))
  else
    printf 'FAIL  %s\n' "$name"; FAIL=$((FAIL + 1))
  fi
}
warn() { printf 'MANUAL %s\n' "$*"; WARN=$((WARN + 1)); }

command -v docker >/dev/null 2>&1 || { echo "ERROR: ejecutar dentro de la VM con Docker."; exit 2; }
docker info >/dev/null 2>&1 || { echo "ERROR: Docker no responde."; exit 2; }

echo "=== 1. Nodos ==="
for n in clia dmza gwa1 gwa2 gwb hostb srva swa wan; do
  if [[ "$(docker inspect -f '{{.State.Running}}' "clab-asi-$n" 2>/dev/null || true)" == true ]]; then
    echo "PASS  contenedor clab-asi-$n activo"; PASS=$((PASS + 1))
  else
    echo "FAIL  contenedor clab-asi-$n no está activo"; FAIL=$((FAIL + 1))
  fi
done

echo
echo "=== 2. VLAN, direccionamiento y rutas ==="
node_check "swa VLAN filtering activo" swa 'bridge vlan show >/dev/null && ip -d link show br0 | grep -q vlan_filtering'
node_check "swa puerto srva en VLAN 10" swa 'bridge vlan show dev eth3 | grep -q "10"'
node_check "swa puerto clia en VLAN 20" swa 'bridge vlan show dev eth4 | grep -q "20"'
node_check "swa puerto dmza en VLAN 30" swa 'bridge vlan show dev eth5 | grep -q "30"'
node_check "swa trunk gwa1 lleva VLAN 10/20/30" swa 'bridge vlan show dev eth1 | grep -q 10 && bridge vlan show dev eth1 | grep -q 20 && bridge vlan show dev eth1 | grep -q 30'
node_check "swa trunk gwa2 lleva VLAN 10/20/30" swa 'bridge vlan show dev eth2 | grep -q 10 && bridge vlan show dev eth2 | grep -q 20 && bridge vlan show dev eth2 | grep -q 30'
node_check "gwa1 VLAN 10 direccionada" gwa1 'ip -o -4 addr show dev eth2.10 | grep -q "10.10.0.130/27"'
node_check "gwa1 VLAN 20 direccionada" gwa1 'ip -o -4 addr show dev eth2.20 | grep -q "10.10.0.2/25"'
node_check "gwa1 VLAN 30 direccionada" gwa1 'ip -o -4 addr show dev eth2.30 | grep -q "10.10.0.162/28"'
node_check "gwa2 VLAN 10 direccionada" gwa2 'ip -o -4 addr show dev eth2.10 | grep -q "10.10.0.131/27"'
node_check "gwa2 VLAN 20 direccionada" gwa2 'ip -o -4 addr show dev eth2.20 | grep -q "10.10.0.3/25"'
node_check "gwa2 VLAN 30 direccionada" gwa2 'ip -o -4 addr show dev eth2.30 | grep -q "10.10.0.163/28"'
node_check "srva con IP/gateway" srva 'ip -o -4 addr show dev eth1 | grep -q 10.10.0.140/27 && ip route | grep -q "default via 10.10.0.129"'
node_check "dmza con IP/gateway" dmza 'ip -o -4 addr show dev eth1 | grep -q 10.10.0.170/28 && ip route | grep -q "default via 10.10.0.161"'
node_check "hostb con IP/gateway" hostb 'ip -o -4 addr show dev eth1 | grep -q 10.20.0.2/26 && ip route | grep -q "default via 10.20.0.1"'
node_check "clia tiene concesión DHCP del rango" clia 'ip -o -4 addr show dev eth1 | grep -Eq "10\\.10\\.0\\.(2[0-9]|[3-9][0-9]|1[01][0-9]|120)/25"'

echo
echo "=== 3. OSPF y VPN ==="
node_check "gwa1 ve vecino OSPF Full" gwa1 'vtysh -c "show ip ospf neighbor" | grep -q Full'
node_check "gwa2 ve vecino OSPF Full" gwa2 'vtysh -c "show ip ospf neighbor" | grep -q Full'
node_check "gwa2 aprende ruta OSPF a sede B" gwa2 'vtysh -c "show ip route ospf" | grep -q "10.20.0.0/26"'
node_check "gwa1 tiene ruta WireGuard a sede B" gwa1 'ip route | grep -q "10.20.0.0/26.*wg0"'
node_check "gwb tiene ruta WireGuard a sede A" gwb 'ip route | grep -q "10.10.0.0/24.*wg0"'
node_check "WireGuard tiene handshake previo" gwa1 'wg show wg0 latest-handshakes | awk '\''$2 > 0 {ok=1} END {exit !ok}'\'''
node_check "ping por túnel srva -> hostb" srva 'ping -c 1 -W 2 10.20.0.2'

echo
echo "=== 4. Servicios, firewall y publicación ==="
node_check "HTTP en dmza escucha TCP/80" dmza 'ss -lnt | grep -q ":80"'
node_check "HTTP interno en srva escucha TCP/8080" srva 'ss -lnt | grep -q ":8080"'
node_check "dnsmasq está activo" gwa1 'pgrep dnsmasq >/dev/null'
node_check "chronyd está activo" gwa1 'pgrep chronyd >/dev/null'
node_check "DNS interno resuelve srva.asi.lab" clia 'dig @10.10.0.2 srva.asi.lab +short | grep -q 10.10.0.140'
node_check "Chrony responde a srva sin cambiar su reloj" srva 'chronyd -Q -t 5 "server 10.10.0.2 iburst"'
node_check "dnsmasq registra concesión clia" gwa1 'test -s /tmp/dnsmasq-practica4.leases'
node_check "forwarding IPv4 activo en gwa1" gwa1 'test "$(cat /proc/sys/net/ipv4/ip_forward)" = 1'
node_check "nftables filter cargado en gwa1" gwa1 'nft list table inet filter'
node_check "nftables NAT cargado en gwa1" gwa1 'nft list table ip nat'
node_check "nftables filter cargado en gwa2" gwa2 'nft list table inet filter'
node_check "nftables NAT cargado en gwa2" gwa2 'nft list table ip nat'
node_check "DNAT WAN:8080 devuelve la web DMZ" wan 'curl -fsS --max-time 4 http://198.51.100.1:8080/ | grep -qi "servidor DMZ"'

echo
echo "=== 5. Docker y redundancia ==="
check "red Docker practica4-net existe" docker network inspect practica4-net
check "contenedor p4-a está activo" bash -c '[[ "$(docker inspect -f "{{.State.Running}}" p4-a 2>/dev/null)" == true ]]'
check "contenedor p4-b está activo" bash -c '[[ "$(docker inspect -f "{{.State.Running}}" p4-b 2>/dev/null)" == true ]]'
check "contenedor p4-web está activo" bash -c '[[ "$(docker inspect -f "{{.State.Running}}" p4-web 2>/dev/null)" == true ]]'
check "p4-a resuelve y alcanza p4-b por nombre" docker exec p4-a ping -c 1 -W 2 p4-b
check "puerto Docker 8081 publicado" docker port p4-web 80/tcp
if nexec gwa1 'ip -o -4 addr show | grep -q "10.10.0.1/25" || ip -o -4 addr show | grep -q "10.10.0.129/27" || ip -o -4 addr show | grep -q "10.10.0.161/28"' ||
   nexec gwa2 'ip -o -4 addr show | grep -q "10.10.0.1/25" || ip -o -4 addr show | grep -q "10.10.0.129/27" || ip -o -4 addr show | grep -q "10.10.0.161/28"'; then
  echo "PASS  al menos una pasarela tiene una VIP VRRP"; PASS=$((PASS + 1))
else
  echo "FAIL  no se encuentran VIP VRRP"; FAIL=$((FAIL + 1))
fi
node_check "keepalived activo en gwa1" gwa1 'pgrep keepalived >/dev/null'
node_check "keepalived activo en gwa2" gwa2 'pgrep keepalived >/dev/null'

echo
echo "=== 6. Acceso y evidencias que requieren demostración manual ==="
warn "Paso 3: captura ARP/ICMP temporal y limpieza de direcciones de prueba."
warn "Pasos 13-14 y 18: demostrar averías y restaurar la configuración."
warn "Pasos 21-22 y 30-35: completar matriz de flujos desde cada origen y guardar resultados."
warn "Paso 29: captura WAN UDP/51820 y captura interior wg0."
warn "Pasos 43-47: medir failover, mtr/iperf3, averías del revisor y capturas PCAP."
warn "Pasos 48-51: diagrama, PDF, registro de cambios y vídeo."
warn "Este verificador comprueba el estado actual; no puede probar que los comandos históricos se ejecutaran ni que se grabaran evidencias."

echo
printf 'Resultado: %d PASS, %d FAIL, %d comprobaciones/manuales.\n' "$PASS" "$FAIL" "$WARN"
[[ "$FAIL" -eq 0 ]] || exit 1
