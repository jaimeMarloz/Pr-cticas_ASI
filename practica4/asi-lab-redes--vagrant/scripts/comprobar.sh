#!/usr/bin/env bash
# Comprobaciones orientativas del laboratorio. No sustituyen a la defensa en vídeo.
# No asume tu plan de direccionamiento: solo mira que las piezas estén en marcha.
PFX="clab-asi"
ok=0; ko=0
x() { docker exec "$PFX-$1" "${@:2}" 2>/dev/null; }
t() { # t "descripción" comando...
  local d="$1"; shift
  if "$@" >/dev/null 2>&1; then printf "  [ OK ] %s\n" "$d"; ok=$((ok+1))
  else printf "  [FALLA] %s\n" "$d"; ko=$((ko+1)); fi
}

echo "== Nodos"
for n in gwa1 gwa2 swa srva clia dmza gwb hostb wan; do
  t "contenedor $n en marcha" docker inspect -f '{{.State.Running}}' "$PFX-$n"
done

echo "== Segmentación (VLAN)"
t "swa con filtrado de VLAN activo" bash -c "[ \"\$(docker exec $PFX-swa cat /sys/class/net/br0/bridge/vlan_filtering)\" = 1 ]"
for v in 10 20 30; do
  t "VLAN $v definida en swa" bash -c "docker exec $PFX-swa bridge vlan show | grep -qE '[[:space:]]$v([[:space:]]|\$)'"
done

echo "== Encaminamiento"
for g in gwa1 gwa2 gwb; do
  t "$g reenvía paquetes (ip_forward)" bash -c "[ \"\$(docker exec $PFX-$g cat /proc/sys/net/ipv4/ip_forward)\" = 1 ]"
done
t "OSPF: gwa1 con al menos 1 vecino Full" bash -c "docker exec $PFX-gwa1 vtysh -c 'show ip ospf neighbor' | grep -q Full"
t "gwa1 tiene ruta hacia la sede B (no conectada)" bash -c "docker exec $PFX-gwa1 ip route | grep -vE 'dev eth|proto kernel' | grep -q ."

echo "== Servicios"
t "dnsmasq en marcha en gwa1" docker exec "$PFX-gwa1" pgrep dnsmasq
t "keepalived en marcha en gwa1" docker exec "$PFX-gwa1" pgrep keepalived
t "keepalived en marcha en gwa2" docker exec "$PFX-gwa2" pgrep keepalived

echo "== Firewall y VPN"
t "nftables con reglas en gwa1" bash -c "docker exec $PFX-gwa1 nft list ruleset | grep -q chain"
t "nftables con DNAT en gwa1 o gwa2" bash -c "docker exec $PFX-gwa1 nft list ruleset | grep -q dnat || docker exec $PFX-gwa2 nft list ruleset | grep -q dnat"
t "WireGuard con handshake en gwa1" bash -c "docker exec $PFX-gwa1 wg show all latest-handshakes | awk '{if (\$NF>0) f=1} END{exit !f}'"
t "WireGuard con handshake en gwb" bash -c "docker exec $PFX-gwb wg show all latest-handshakes | awk '{if (\$NF>0) f=1} END{exit !f}'"

echo "== Conectividad entre equipos finales (según tus IP de eth1)"
ip_of() { docker exec "$PFX-$1" ip -4 -o addr show dev "${2:-eth1}" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1; }
for src in srva clia dmza hostb; do
  for dst in srva clia dmza hostb; do
    [ "$src" = "$dst" ] && continue
    ip=$(ip_of "$dst")
    [ -z "$ip" ] && { printf "  [  -  ] %s -> %s: sin IP en eth1\n" "$src" "$dst"; continue; }
    if docker exec "$PFX-$src" ping -c1 -W1 "$ip" >/dev/null 2>&1; then r="llega"; else r="NO llega"; fi
    printf "  %s -> %s (%s): %s\n" "$src" "$dst" "$ip" "$r"
  done
done
echo
echo "Resumen: $ok correctas, $ko pendientes. (Que algo NO llegue puede ser lo correcto: depende de tu firewall.)"
