#!/usr/bin/env bash
# Aprovisionamiento del laboratorio de redes.
# Se ejecuta solo con "vagrant up". Si no usas Vagrant, puedes lanzarlo a mano
# en cualquier Ubuntu 22.04:  sudo bash provision.sh
set -euo pipefail

LAB_DIR="${LAB_DIR:-/vagrant}"
export DEBIAN_FRONTEND=noninteractive

echo "[1/6] Paquetes base"
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg jq tcpdump mtr-tiny traceroute \
  wireguard-tools nftables iproute2 iputils-ping dnsutils \
  docker.io

echo "[2/6] Módulos del kernel necesarios (VLAN, bridge, WireGuard)"
cat > /etc/modules-load.d/asi-redes.conf <<MODS
8021q
bridge
wireguard
MODS
for m in 8021q bridge wireguard; do modprobe "$m" || echo "AVISO: no se pudo cargar $m"; done

echo "[3/6] Docker"
systemctl enable --now docker
if id vagrant >/dev/null 2>&1; then usermod -aG docker vagrant; fi

echo "[4/6] containerlab"
if ! command -v containerlab >/dev/null 2>&1; then
  curl -sL https://get.containerlab.dev | bash
fi

echo "[5/6] Imagen del laboratorio (asi-net)"
docker build -t asi-net:1.0 "$LAB_DIR/docker"

echo "[6/6] Comando de ayuda 'lab'"
install -m 0755 "$LAB_DIR/scripts/lab" /usr/local/bin/lab
install -m 0755 "$LAB_DIR/scripts/comprobar.sh" /usr/local/bin/comprobar
mkdir -p /etc/asi-redes && echo "$LAB_DIR" > /etc/asi-redes/lab_dir

echo
echo "Listo. Entra con 'vagrant ssh' y escribe: lab up"
