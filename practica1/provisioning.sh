#!/usr/bin/env bash
set -e
apt-get update
apt-get upgrade -y
# instalar Docker
curl -fsSL https://get.docker.com | sh
# instalar Docker Compose
apt-get install -y docker-compose
# Habilitar que cual trafico pueda entrar o salir por la interfaz de red
# Para que el anfitrión pueda acceder al servidor Nginx
sudo ufw allow in on enp0s8
