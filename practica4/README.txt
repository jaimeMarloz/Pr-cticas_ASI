PLAN DE RED Sede A 
VLAN 20 (clia – estaciones de trabajo de clientes) (128 IPs totales, 126 útiles).
•	Dirección de red: 10.10.0.0/25		    |	Máscara de red: 255.255.255.128
•	IP de gwa1: 10.10.0.2			        |	IP de gwa2: 10.10.0.3
•	IP de la pasarela virtual: 10.10.0.1	|	Dirección de difusión: 10.10.0.127

•	Rango de equipos en clia: 10.10.0.4 – 10.10.0.126

VLAN 10 (srva – servidores y servicios de la red) (32 IPs totales, 30 útiles).
•	Dirección de red: 10.10.0.128/27	    |	Máscara de red: 255.255.255.224
•	IP de gwa1: 10.10.0.130		            |	IP de gwa2: 10.10.0.131
•	IP pasarela virtual: 10.10.0.129		|	Dirección de difusión: 10.10.0.159

•	Rango de equipos de srva: 10.10.0.132 – 10.10.0.158

VLAN 30 (dmza – DMZ, servicios accesibles dentro y fuera de la red) (16 IPs totales, 14 útiles)
•	Dirección de red: 10.10.0.160/28	    |	Máscara de red: 255.255.255.240
•	IP de gwa1: 10.10.0.162		            |	IP de gwa2: 10.10.0.163
•	IP pasarela virtual: 10.10.0.161		|	Dirección de difusión: 10.10.0.175

•	Rango de equipos de dmza: 10.10.0.164 – 10.10.0.174

Espacio de Direccionamiento Libre
•	10.10.0.176 a 10.10.0.255 (80 direcciones IP).
    o	Bloque 1: Corresponde a 10.10.0.176/28 (16 IPs)
    o	Bloque 2: Corresponde a 10.10.0.192/26 (64 IPs)

PLAN DE RED Sede B 
LAN Sede B (No hay segmentación de red)  (64 IPs totales, 62 útiles).
•	Dirección de red: 10.20.0.0/26		    |	Máscara de red: 255.255.255.192
•	IP de gwb: 10.20.0.1			        |	Dirección de difusión: 10.20.0.63

•	Rango de equipos en hostb: 10.20.0.2 – 10.20.0.62



Otras
•	WAN: 198.51.100.0/24 
    o	gwa1=198.51.100.1
    o	gwa2=198.51.100.2
    o	gwb=198.51.100.3
    o	wan=198.51.100.254

•	Túnel VPN (WireGuard): 10.99.0.0/30 
