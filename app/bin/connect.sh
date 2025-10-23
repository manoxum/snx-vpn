#!/usr/bin/env bash
# connect-no-expect.sh - Conecta SNX sem usar Expect
# Variáveis de ambiente necessárias:
#   SNX_VPN_GETWAI  -> Gateway SNX (ex: vpn.gov.st)
#   SNX_VPN_USERNAME -> Usuário SNX
#   SNX_VPN_PASSWORD -> Senha SNX

set -euo pipefail

# Verifica se todas as variáveis foram definidas
for var in SNX_VPN_GETWAI SNX_VPN_USERNAME SNX_VPN_PASSWORD; do
    if [ -z "${!var:-}" ]; then
        echo "ERROR: Variable $var not set"
        exit 1
    fi
done

# Função para verificar se a VPN está funcional
check_vpn() {
    VPN_IFACE=$(ip -4 addr | awk '/172\.16\./ {print $NF; exit}')
    if [ -n "$VPN_IFACE" ] && ip route show dev "$VPN_IFACE" | grep -q "172.16"; then
        return 0
    else
        return 1
    fi
}

# Tenta conectar SNX até 3 vezes
MAX_ATTEMPTS=3
for attempt in $(seq 1 $MAX_ATTEMPTS); do
    echo "INFO: Attempt $attempt to connect SNX..."

    if pgrep -f "snx.*-s $SNX_VPN_GETWAI" > /dev/null; then
        echo "INFO: SNX session already running, skipping login..."
    else
        # Conecta SNX usando stdin para senha e aceitar certificado
        {
            echo "${SNX_VPN_PASSWORD}"  # senha
            echo "y"               # aceitar certificado
        } | snx -s "$SNX_VPN_GETWAI" -u "$SNX_VPN_USERNAME"
    fi

    echo "INFO: Waiting for VPN interface and routes..."
    for _i in {1..30}; do
        if check_vpn; then
            echo "INFO: VPN interface is up and routes applied."
            break 2
        fi
        sleep 1
    done

    echo "WARNING: VPN interface or routes not ready, retrying..."
done

# Mostra rotas VPN
VPN_IFACE=$(ip -4 addr | awk '/172\.16\./ {print $NF; exit}')
echo "VPN routes:"
ip route show | grep "${VPN_IFACE:-}" || echo "No routes detected for VPN interface yet."

echo "INFO: VPN is fully ready."

sleep 2
/usr/sbin/sshd


exec "$@"

