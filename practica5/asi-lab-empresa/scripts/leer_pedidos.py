#!/usr/bin/env python3
"""Lee los pedidos de venta confirmados de Odoo por la API XML-RPC.

Solo usa la biblioteca estándar de Python. Uso:
    ODOO_PWD='<contraseña>' python3 scripts/leer_pedidos.py

MODIFICACIÓN (paso 22): ahora muestra también el estado de cada pedido.
"""
import os
import xmlrpc.client

URL = "http://localhost:8069"
DB = "empresa"
USER = "admin"
PWD = os.environ.get("ODOO_PWD", "admin")

# MODIFICACIÓN (paso 22): etiquetas legibles para el campo 'state' de sale.order
ESTADOS = {
    "draft":  "borrador",
    "sent":   "presupuesto enviado",
    "sale":   "confirmado",
    "done":   "bloqueado (ciclo completo)",
    "cancel": "cancelado",
}

# 1) Autenticarse: devuelve el identificador numérico del usuario
common = xmlrpc.client.ServerProxy(f"{URL}/xmlrpc/2/common")
uid = common.authenticate(DB, USER, PWD, {})
if not uid:
    raise SystemExit("Autenticación fallida: revisa usuario y contraseña")

# 2) Pedir datos al modelo sale.order con un filtro
models = xmlrpc.client.ServerProxy(f"{URL}/xmlrpc/2/object")
pedidos = models.execute_kw(
    DB, uid, PWD, "sale.order", "search_read",
    [[["state", "in", ["sale", "done"]]]],
    {"fields": ["name", "partner_id", "date_order", "amount_total", "state"]},  # MODIFICACIÓN: + state
)

for p in pedidos:
    # MODIFICACIÓN (paso 22): se imprime también el estado de cada pedido
    estado = ESTADOS.get(p["state"], p["state"])
    print(p["name"], p["partner_id"][1], p["date_order"], p["amount_total"], f"[{p['state']}] {estado}")
print(f"{len(pedidos)} pedidos confirmados")
