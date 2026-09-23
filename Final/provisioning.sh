#!/usr/bin/env bash
set -e
apt-get update
apt-get upgrade -y
# instalar Docker
curl -fsSL https://get.docker.com | sh
# instalar Docker Compose
apt-get install -y docker-compose