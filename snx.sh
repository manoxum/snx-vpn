#!/usr/bin/env bash
set -e

CONTAINER_NAME="inic-vpn"
IMAGE_NAME="inic-vpn:latest"
ENV_FILE=".env.local"

# Funções auxiliares
container_exists() {
  docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
}

show_help() {
  cat <<EOF
Uso: snx [opção]

Comandos disponíveis:
  snx                 Abre um shell bash dentro do container '${CONTAINER_NAME}'
  snx ssh <args...>   Executa um comando SSH de dentro do container (ex: snx ssh user@ip)
  snx --logs          Exibe os logs do container
  snx --stop          Para e remove o container
  snx --reconnect     Remove e recria o container do zero
  snx --help          Mostra esta mensagem de ajuda

Exemplos:
  snx                 # Entra direto via docker exec
  snx ssh user@10.0.0.5    # Conecta via SSH de dentro do container
  snx ssh -i key.pem user@10.0.0.5   # Passa parâmetros extras ao SSH
  snx --reconnect     # Reinicia o container
  snx --logs          # Exibe logs atuais

EOF
}

# Garante que estamos no diretório do script
cd "$(dirname "$(readlink -f "$0")")"

case "$1" in
  "")
    if ! container_exists; then
      echo "❌ O container '${CONTAINER_NAME}' não existe."
      echo "💡 Use 'snx --reconnect' para criá-lo novamente."
      exit 1
    fi
    echo "🔗 Conectando ao container ${CONTAINER_NAME} via bash..."
    docker exec -it "${CONTAINER_NAME}" bash
    ;;

  ssh)
    if ! container_exists; then
      echo "❌ O container '${CONTAINER_NAME}' não existe."
      echo "💡 Use 'snx --reconnect' para criá-lo novamente."
      exit 1
    fi
    shift
    if [ $# -eq 0 ]; then
      echo "⚠️  Nenhum comando SSH especificado. Exemplo: snx ssh user@10.0.0.5"
      exit 1
    fi
    echo "🔐 Executando SSH dentro do container (${CONTAINER_NAME}) → ssh $*"
    docker exec -it "${CONTAINER_NAME}" ssh "$@"
    ;;

  --logs)
    if ! container_exists; then
      echo "❌ O container '${CONTAINER_NAME}' não existe."
      exit 1
    fi
    echo "📜 Exibindo logs de ${CONTAINER_NAME}..."
    docker logs "${CONTAINER_NAME}"
    ;;

  --stop)
    if ! container_exists; then
      echo "⚠️  Nenhum container '${CONTAINER_NAME}' encontrado."
      exit 0
    fi
    echo "🛑 Parando e removendo ${CONTAINER_NAME}..."
    docker rm -f "${CONTAINER_NAME}"
    ;;

  --reconnect)
    echo "🔄 Reiniciando container ${CONTAINER_NAME}..."
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
    docker run --rm -it \
      --privileged \
      --cap-add=NET_ADMIN \
      -p 2222:22 \
      -d \
      -v /lib/modules:/lib/modules:ro \
      --device /dev/net/tun \
      --env-file "${ENV_FILE}" \
      --name "${CONTAINER_NAME}" \
      "${IMAGE_NAME}"
    echo "✅ Container '${CONTAINER_NAME}' reiniciado."
    ;;

  --help|-h)
    show_help
    ;;

  *)
    echo "❌ Opção inválida: $1"
    echo "Use 'snx --help' para ver as opções disponíveis."
    exit 1
    ;;
esac
