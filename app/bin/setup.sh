#!/bin/bash
set -e

SSH_USER="${SSH_USER:-ssh}"
SSH_PASSWORD="${SSH_PASSWORD:-Secret}"

# Cria usuário apenas se não existir, adicionando ao grupo ssh existente
if ! id "$SSH_USER" &>/dev/null; then
    useradd -m -s /bin/bash -g ssh "$SSH_USER"
fi

# Define senha de forma compatível com Ubuntu 14.04
echo -e "${SSH_PASSWORD}\n${SSH_PASSWORD}" | passwd "$SSH_USER"

# Função para configurar sshd
set_sshd_config() {
    local key="$1"
    local value="$2"
    if grep -qE "^#?$key" /etc/ssh/sshd_config; then
        sed -i "s|^#\?$key.*|$key $value|" /etc/ssh/sshd_config
    else
        echo "$key $value"
    fi
}

# Configurações SSH
{
    set_sshd_config "PasswordAuthentication" "yes"
    set_sshd_config "PermitRootLogin" "yes"
    set_sshd_config "AllowTcpForwarding" "yes"
    set_sshd_config "GatewayPorts" "yes"
    set_sshd_config "X11Forwarding" "yes"
} >> /etc/ssh/sshd_config
