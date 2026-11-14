# Imagen única para todos los nodos del laboratorio.
# Base: FRRouting (Alpine). Se le añaden las herramientas que usa la práctica.
FROM frrouting/frr:v8.4.1

RUN apk add --no-cache \
      bash iproute2 iputils mtr tcpdump bind-tools curl \
      nftables wireguard-tools dnsmasq keepalived chrony \
      iperf3 netcat-openbsd nano busybox-extras \
 && sed -i 's/^ospfd=no/ospfd=yes/' /etc/frr/daemons \
 && sed -i 's/^staticd=no/staticd=yes/' /etc/frr/daemons \
 && touch /etc/frr/frr.conf \
 && echo "service integrated-vtysh-config" > /etc/frr/vtysh.conf \
 && chown frr:frr /etc/frr/frr.conf /etc/frr/vtysh.conf

# Se conserva el ENTRYPOINT/CMD de la imagen de FRR (arranca zebra, ospfd, staticd)
