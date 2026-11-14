# Laboratorio de redes (Práctica 4)

Administración de Sistemas Informáticos · EPS Zamora · Universidad de Salamanca

Un laboratorio completo de red dentro de **una sola máquina virtual**. Todo el software es libre y gratuito: VirtualBox, Vagrant, Docker, containerlab, FRRouting, nftables, WireGuard, dnsmasq y keepalived.

## 1. Qué necesitas

| Requisito | Detalle |
|---|---|
| Equipo | 8 GB de RAM (la VM usa 4 GB) y 15 GB de disco libres |
| Software | [VirtualBox](https://www.virtualbox.org) y [Vagrant](https://www.vagrantup.com) |
| Red | Conexión a Internet solo durante el primer `vagrant up` |

Alternativa sin Vagrant: cualquier Ubuntu 22.04 (VM propia, WSL2 con systemd o una máquina real). Descomprime el zip y ejecuta `sudo bash provision.sh`.

## 2. Puesta en marcha

```
unzip asi-lab-redes.zip
cd asi-lab-redes
vagrant up            # primera vez: 10-15 min
vagrant ssh
lab up                # despliega la topología
lab status            # los 9 nodos deben aparecer como running
```

Para empezar de cero en cualquier momento: `lab reset`.
Al terminar la sesión: `exit` y `vagrant halt` (apaga la VM) o `vagrant suspend`.
Si borras la VM (`vagrant destroy`) pierdes lo configurado: usa `lab save <carpeta>` antes (la carpeta puede ser `/vagrant/mi-config`, que queda en tu equipo).

## 3. Topología

```
                      Internet simulada (198.51.100.0/24)
        +-------------------------wan (.254)-------------------------+
        |                           |                                |
     eth1|                       eth1|                             eth1|
      [gwa1]                     [gwa2]                           [gwb]
     eth2|                       eth2|                             eth2|
        |                           |                                |
        +--------[ swa ]------------+                             [hostb]
                 eth3 eth4 eth5                                    Sede B
                  |    |    |
               [srva][clia][dmza]
                      Sede A
```

| Nodo | Papel | Interfaces (todas sin configurar) |
|---|---|---|
| `wan` | "Internet": puente 198.51.100.0/24 con IP .254 y un servidor web | eth1 gwa1, eth2 gwa2, eth3 gwb |
| `gwa1`, `gwa2` | Pasarelas redundantes de la sede A | eth1 WAN, eth2 hacia `swa` (troncal) |
| `swa` | Conmutador de la sede A (puente `br0`, sin filtrado de VLAN) | eth1 gwa1, eth2 gwa2, eth3 srva, eth4 clia, eth5 dmza |
| `srva`, `clia`, `dmza` | Equipos de las futuras VLAN servidores, clientes y DMZ | eth1 |
| `gwb` | Pasarela de la sede B | eth1 WAN, eth2 hacia `hostb` |
| `hostb` | Equipo de la sede B | eth1 |

`eth0` de cada nodo es la red de gestión de Docker. No se usa en la práctica y sale sin ruta por defecto.

Estado inicial: todo está cableado, `swa` funciona como un conmutador plano y ningún equipo tiene IP. Configurar el resto es la práctica.

## 4. Manejo diario

| Orden | Para qué |
|---|---|
| `lab sh gwa1` | Abrir una shell en un nodo |
| `lab vtysh gwa1` | Consola de FRRouting (OSPF, rutas) |
| `lab x clia ip -br a` | Ejecutar un comando suelto en un nodo |
| `lab cap gwa1 eth1 icmp` | Capturar tráfico con tcpdump |
| `lab save <carpeta>` | Volcar la configuración de todos los nodos a ficheros |
| `comprobar` | Revisión orientativa de lo que llevas montado |
| `lab reset` | Volver al estado inicial |

Dentro de un nodo tienes: `ip`, `bridge`, `nft`, `wg`, `dnsmasq`, `keepalived`, `vtysh`, `tcpdump`, `mtr`, `traceroute`, `dig`, `curl`, `iperf3`, `nc`, `chronyd`.

Lo que configures dentro de un nodo **no persiste** si ejecutas `lab reset` o `lab down`. Guarda tus comandos en un fichero de notas o scripts, que además te servirá para la documentación.

## 5. Problemas conocidos

| Síntoma | Causa y arreglo |
|---|---|
| `vagrant up` falla al descargar la box | Sin conexión o proxy. Reintenta con `vagrant up --provision` |
| `lab up` dice que no encuentra la imagen `asi-net:1.0` | El aprovisionamiento no terminó: `vagrant provision` |
| `ip link add ... type vlan` da "Operation not supported" | Falta el módulo: `sudo modprobe 8021q` en la VM |
| `ip link add wg0 type wireguard` falla | `sudo modprobe wireguard` en la VM (el kernel 5.15 de Ubuntu 22.04 lo trae) |
| VirtualBox pide activar virtualización | Activa VT-x/AMD-V en la BIOS, o desactiva Hyper-V si Windows lo bloquea |
| Un nodo no arranca | `docker logs clab-asi-<nodo>` |
| La VM va lenta | Cierra otras aplicaciones; no hace falta más de 2 CPU |

## 6. Estado de validación

Los ficheros se han comprobado en sintaxis (YAML, Ruby y Bash). El despliegue completo (`vagrant up` + `lab up`) **no se ha ejecutado de principio a fin** en el entorno donde se preparó este material. Los dos puntos con más riesgo son los módulos `8021q` y `wireguard` en la VM y los permisos de los contenedores. Antes de la primera sesión conviene hacer una prueba completa en un equipo del aula.

## 7. Contenido del zip

```
Vagrantfile            Define y arranca la VM
provision.sh           Instala Docker, containerlab y construye la imagen
docker/Dockerfile      Imagen única de todos los nodos (FRRouting + herramientas)
topologia.clab.yml     Nodos y cables del laboratorio
scripts/lab            Ayudante: lab up, lab sh, lab cap...
scripts/comprobar.sh   Revisión orientativa (se instala como "comprobar")
README.md              Este documento
```
