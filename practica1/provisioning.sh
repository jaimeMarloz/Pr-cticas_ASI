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

# Cambia a la direccion donde se encuentran los archivos que se encuentran en
#   el proyecto (desde donde se hace vagrant up), se encuentran ahi mediante
#   una carpeta compartida
cd /vagrant

# Levanta el nginx definido en docker-compose.yml
docker compose up -d
