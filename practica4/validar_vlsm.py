import ipaddress

# Bloques Principales
BLOQUE_SEDE_A = ipaddress.ip_network('10.10.0.0/24')
BLOQUE_SEDE_B = ipaddress.ip_network('10.20.0.0/24')

# Todas las subredes definidas según el enunciado oficial
subredes = {
    "VLAN 20 - Clientes (Sede A)": ipaddress.ip_network('10.10.0.0/25'),
    "VLAN 10 - Servidores (Sede A)": ipaddress.ip_network('10.10.0.128/27'),
    "VLAN 30 - DMZ (Sede A)": ipaddress.ip_network('10.10.0.160/28'),
    "LAN Sede B": ipaddress.ip_network('10.20.0.0/26'),
    "Tunel VPN": ipaddress.ip_network('10.99.0.0/30'),
}

def validar_plan():
    print("=== VALIDACIÓN DEL PLAN DE DIRECCIONAMIENTO ===")
    
    # 1. Comprobar que las subredes de Sede A pertenecen al bloque 10.10.0.0/24
    subredes_sede_a = ["VLAN 20 - Clientes (Sede A)", "VLAN 10 - Servidores (Sede A)", "VLAN 30 - DMZ (Sede A)"]
    correcto = True
    
    for nombre in subredes_sede_a:
        subred = subredes[nombre]
        if not subred.subnet_of(BLOQUE_SEDE_A):
            print(f"[ERROR] '{nombre}' ({subred}) está FUERA de {BLOQUE_SEDE_A}")
            correcto = False
        else:
            print(f"[OK] '{nombre}' ({subred}) pertenece a {BLOQUE_SEDE_A}")

    # 2. Comprobar que Sede B pertenece a 10.20.0.0/24
    if not subredes["LAN Sede B"].subnet_of(BLOQUE_SEDE_B):
        print(f"[ERROR] Sede B está FUERA de {BLOQUE_SEDE_B}")
        correcto = False
    else:
        print(f"[OK] 'LAN Sede B' ({subredes['LAN Sede B']}) pertenece a {BLOQUE_SEDE_B}")

    # 3. Comprobar solapamientos globales mediante overlaps()
    solapamiento = False
    items = list(subredes.items())
    for i in range(len(items)):
        for j in range(i + 1, len(items)):
            n1, net1 = items[i]
            n2, net2 = items[j]
            if net1.overlaps(net2):
                print(f"[ERROR] Solapamiento entre '{n1}' ({net1}) y '{n2}' ({net2})")
                solapamiento = True

    if correcto and not solapamiento:
        print("\n--> ¡VALIDACIÓN CORRECTA! Todo el plan de direccionamiento cumple las restricciones.")

if __name__ == "__main__":
    validar_plan()