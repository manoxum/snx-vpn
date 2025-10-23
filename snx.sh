#!/usr/bin/env bash
set -e

CONTAINER_NAME="inic-vpn"
IMAGE_NAME="inic-vpn:latest"
ENV_FILE=".env.local"

# -------------------------
# Funções auxiliares
# -------------------------
get_env_var() {
  local var_name="$1"
  grep -E "^${var_name}=" "${ENV_FILE}" 2>/dev/null | tail -n1 | cut -d '=' -f2-
}

container_exists() {
  docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
}

get_current_binds() {
  docker inspect "${CONTAINER_NAME}" --format '{{range $p, $conf := .HostConfig.PortBindings}}{{(index $conf 0).HostPort}}:{{$p}}{{"\n"}}{{end}}' 2>/dev/null || true
}

unique_binds() {
  declare -A seen
  local bind
  for bind in "$@"; do
    seen["$bind"]=1
  done
  echo "${!seen[@]}"
}


# -------------------------
# Função principal de run
# -------------------------
run_container() {
  local binds=("$@")

  # Garante que SSH_BIND sempre exista e seja válido
  local SSH_BIND
  SSH_BIND=$(get_env_var "SSH_BIND")
  if [[ -z "$SSH_BIND" ]]; then
    echo "⚠️  Variável SSH_BIND não definida em ${ENV_FILE}, usando 2222:22 por padrão."
    SSH_BIND="2222:22"
  fi
  if [[ ! "$SSH_BIND" =~ ^[0-9]+:[0-9]+$ ]]; then
    echo "❌ SSH_BIND inválido em ${ENV_FILE}. Use o formato HOST:CONTAINER (ex: 2222:22)."
    exit 1
  fi

  # Se ainda não estiver presente na lista de binds, adiciona
  if [[ ! " ${binds[*]} " =~ " ${SSH_BIND} " ]]; then
    binds=("$SSH_BIND" "${binds[@]}")
  fi

  binds=($(unique_binds "${SSH_BIND}" "${binds[@]}"))
  local ports_args=()
  for b in "${binds[@]}"; do
    ports_args+=(-p "$b")
  done

  echo "🚀 Iniciando container '${CONTAINER_NAME}' com binds:"
  printf '  - %s\n' "${binds[@]}"

  docker run --rm -it \
    --privileged \
    --cap-add=NET_ADMIN \
    "${ports_args[@]}" \
    -d \
    -v /lib/modules:/lib/modules:ro \
    --device /dev/net/tun \
    --env-file "${ENV_FILE}" \
    --name "${CONTAINER_NAME}" \
    "${IMAGE_NAME}"
}


# -------------------------
# Ajuda
# -------------------------
show_help() {
  cat <<EOF
Uso: snx [opção]

Comandos disponíveis:
  snx                     Abre um shell bash dentro do container '${CONTAINER_NAME}'
  snx ssh <args...>       Executa um comando SSH de dentro do container
  snx bind A:B            Adiciona um novo bind de porta (ex: snx bind 8080:80)
  snx list-bind|binds     Monstra todos os binds de portas expostas
  snx logs                Exibe os logs do container
  snx stop                Para e remove o container
  snx reconnect           Remove e recria o container do zero
  snx --help              Mostra esta mensagem de ajuda

Exemplos:
  snx ssh user@10.0.0.5
  snx bind 8080:80
  snx reconnect
EOF
}

# -------------------------
# Execução principal
# -------------------------
cd "$(dirname "$(readlink -f "$0")")"

case "$1" in
  "")
    if ! container_exists; then
      echo "❌ O container '${CONTAINER_NAME}' não existe."
      echo "💡 Use 'snx reconnect' para criá-lo novamente."
      exit 1
    fi
    echo "🔗 Conectando ao container ${CONTAINER_NAME} via bash..."
    docker exec -it "${CONTAINER_NAME}" bash
    ;;

  ssh)
    if ! container_exists; then
      echo "❌ O container '${CONTAINER_NAME}' não existe."
      echo "💡 Use 'snx reconnect' para criá-lo novamente."
      exit 1
    fi
    shift
    if [ $# -eq 0 ]; then
      echo "⚠️  Nenhum comando SSH especificado. Exemplo: snx ssh user@10.0.0.5"
      exit 1
    fi
    echo "🔐 Executando SSH dentro do container (${CONTAINER_NAME}) → ssh $*"
    docker exec -it "${CONTAINER_NAME}" ssh -- "$@"
    ;;

  bind)
    shift
    if [ $# -ne 1 ]; then
      echo "❌ Uso incorreto. Exemplo: snx bind 8080:80"
      exit 1
    fi
    NEW_BIND="$1"

    if ! container_exists; then
      echo "❌ O container '${CONTAINER_NAME}' não existe. Use 'snx reconnect' primeiro."
      exit 1
    fi

    echo "🔎 Obtendo binds atuais..."
    mapfile -t current_binds < <(get_current_binds | grep -v '^$')

    if [[ " ${current_binds[*]} " == *" $NEW_BIND "* ]]; then
      echo "⚠️  O bind $NEW_BIND já existe."
      exit 0
    fi

    echo "➕ Adicionando novo bind: $NEW_BIND"
    updated_binds=("${current_binds[@]}" "$NEW_BIND")

    echo "♻️  Recriando container com binds atualizados..."
    docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    run_container "${updated_binds[@]}"

    echo "✅ Novo bind aplicado:"
    printf '  - %s\n' "${updated_binds[@]}"
    ;;

    list-bind|binds)
      if ! container_exists; then
        echo "❌ O container '${CONTAINER_NAME}' não existe."
        exit 1
      fi

      echo "🔎 Binds atuais do container '${CONTAINER_NAME}':"
      mapfile -t current_binds < <(get_current_binds | grep -v '^$')

      # Garante que o SSH_BIND também apareça se não estiver mapeado (por segurança)
      SSH_BIND=$(get_env_var "SSH_BIND")
      if [[ -n "$SSH_BIND" && ! " ${current_binds[*]} " =~ " $SSH_BIND " ]]; then
        current_binds=("$SSH_BIND" "${current_binds[@]}")
      fi

      if [ ${#current_binds[@]} -eq 0 ]; then
        echo "⚠️  Nenhum bind configurado."
      else
        for b in "${current_binds[@]}"; do
          host_port="${b%%:*}"
          container_port="${b##*:}"
          echo "  $host_port → $container_port"
        done
      fi
      ;;


  logs)
    if ! container_exists; then
      echo "❌ O container '${CONTAINER_NAME}' não existe."
      exit 1
    fi
    echo "📜 Exibindo logs de ${CONTAINER_NAME}..."
    docker logs "${CONTAINER_NAME}"
    ;;

  stop)
    if ! container_exists; then
      echo "⚠️  Nenhum container '${CONTAINER_NAME}' encontrado."
      exit 0
    fi
    echo "🛑 Parando e removendo ${CONTAINER_NAME}..."
    docker rm -f "${CONTAINER_NAME}"
    ;;

  reconnect)
    echo "♻️  Recriando container '${CONTAINER_NAME}'..."
    mapfile -t current_binds < <(get_current_binds | grep -v '^$')
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
    run_container "${current_binds[@]}"
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
