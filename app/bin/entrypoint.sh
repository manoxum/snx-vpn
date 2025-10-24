#!/bin/bash
set -e

FLAG_FILE="/app/.setup_done"

SSH_USER="${SNX_SSH_USER:-ssh}"
SSH_PASSWORD="${SNX_SSH_PASSWORD:-Secret}"

# Executa setup.sh apenas se nunca foi executado
if [ ! -f "$FLAG_FILE" ]; then
    /app/bin/setup.sh
    touch "$FLAG_FILE"

    # Mensagem de detalhes do setup
    echo "=============================="
    echo "✅ Setup inicial concluído!"
    echo "Usuário SSH: ${SSH_USER:-ssh}"
    echo "Senha SSH: ${SSH_PASSWORD:-Secret}"
    echo "Porta SSH: 22"
    echo "PasswordAuthentication: $(grep -E '^PasswordAuthentication' /etc/ssh/sshd_config | awk '{print $2}')"
    echo "PermitRootLogin: $(grep -E '^PermitRootLogin' /etc/ssh/sshd_config | awk '{print $2}')"
    echo "AllowTcpForwarding: $(grep -E '^AllowTcpForwarding' /etc/ssh/sshd_config | awk '{print $2}')"
    echo "GatewayPorts: $(grep -E '^GatewayPorts' /etc/ssh/sshd_config | awk '{print $2}')"
    echo "X11Forwarding: $(grep -E '^X11Forwarding' /etc/ssh/sshd_config | awk '{print $2}')"
    echo "=============================="
fi

# Continua com a VPN
/app/bin/connect.sh

# Iniciar o serviço ssh
sleep 2
/usr/sbin/sshd

exec "$@"
