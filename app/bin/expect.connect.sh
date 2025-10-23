#!/usr/bin/env bash
# connect.sh - Conecta SNX automaticamente com tentativas até a VPN ficar funcional
# Variáveis de ambiente necessárias:
#   VPN_GETWAI  -> Gateway SNX (ex: vpn.gov.st)
#   VPN_USERNAME -> Usuário SNX
#   VPN_PASSWORD -> Senha SNX

set -euo pipefail

# Verifica se todas as variáveis foram definidas
for var in VPN_GETWAI VPN_USERNAME VPN_PASSWORD; do
    if [ -z "${!var:-}" ]; then
        echo "ERROR: Variable $var not set"
        exit 1
    fi
done

# Exporta a senha para o script expect
export SNX_PASS="${VPN_PASSWORD}"

# Cria o script expect que automatiza login
cat > /usr/local/bin/snx-login.exp <<'EOF'
#!/usr/bin/expect -f
set timeout 120

if {$argc != 2} {
    puts "Usage: snx-login.exp <server> <username>"
    exit 1
}

set server [lindex $argv 0]
set user   [lindex $argv 1]

spawn snx -s $server -u $user

expect {
    -re {Please enter your password:} {
        after 1500
        send -- "$env(SNX_PASS)\r"
        exp_continue
    }
    -re {Do you accept\?.*\[y\]es/\[N\]o:} {
        after 1500
        send -- "y\r"
        exp_continue
    }
    -re {SNX - connected\.} {
        send_user "INFO: SNX connected successfully\n"
        interact
    }
    eof {
        catch wait result
        set code [lindex $result 3]
        exit $code
    }
}
EOF

chmod +x /usr/local/bin/snx-login.exp

# Função para verificar se a VPN está funcional
check_vpn() {
    VPN_IFACE=$(ip -4 addr | awk '/172\.16\./ {print $NF; exit}')
    if [ -n "$VPN_IFACE" ] && ip route show dev "$VPN_IFACE" | grep -q "172.16"; then
        return 0
    else
        return 1
    fi
}

# Tenta conectar SNX até 3 vezes ou até VPN ficar funcional
MAX_ATTEMPTS=3
for attempt in $(seq 1 $MAX_ATTEMPTS); do
    echo "INFO: Attempt $attempt to connect SNX..."
    if pgrep -f "snx.*-s $VPN_GETWAI" > /dev/null; then
        echo "INFO: SNX session already running, skipping login..."
    else
        /usr/local/bin/snx-login.exp "$VPN_GETWAI" "$VPN_USERNAME"
    fi

    echo "INFO: Waiting for VPN interface and routes..."
    for i in {1..30}; do
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
