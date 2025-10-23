#!/usr/bin/env bash
set -e

cd "$(dirname "$(readlink -f "$0")")"

ENV_FILE=".env.local"
get_env_var() {
  local var_name="$1"
  grep -E "^${var_name}=" "${ENV_FILE}" 2>/dev/null | tail -n1 | cut -d '=' -f2-
}

DEFAULT_CONTAINER_NAME=$(get_env_var "SNX_NAME")
DEFAULT_CONTAINER_IMAGE=$(get_env_var "SNX_IMAGE")
CONTAINER_NAME=${DEFAULT_CONTAINER_NAME:-snx}
IMAGE_NAME=${DEFAULT_CONTAINER_IMAGE:-snx}

# -------------------------
# Funções auxiliares
# -------------------------


container_exists() {
  docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
}

get_current_binds() {
  docker inspect "${CONTAINER_NAME}" \
    --format '{{range $p, $conf := .HostConfig.PortBindings}}{{range $conf}}{{.HostPort}}:{{$p}}{{"\n"}}{{end}}{{end}}' 2>/dev/null || true
}


is_host_network() {
  if ! container_exists; then
    return 1
  fi
  mode=$(docker inspect -f '{{.HostConfig.NetworkMode}}' "${CONTAINER_NAME}")
  [[ "$mode" == "host" ]]
}

ensure_container_exists() {
  if ! container_exists; then
    echo "❌ O container '${CONTAINER_NAME}' não existe."
    echo "💡 Use 'snx connect' para criá-lo."
    exit 1
  fi
}


unique_binds() {
  declare -A seen
  local result=()
  for bind in "$@"; do
    if [[ -z "${seen[$bind]}" ]]; then
      seen[$bind]=1
      result+=("$bind")
    fi
  done
  echo "${result[@]}"
}

# -------------------------
# Função principal de run
# -------------------------
run_container() {
local new_binds=("$@")       # argumentos passados para a função
  local binds=()

  if container_exists; then
    # Recupera binds antigos
    mapfile -t binds < <(get_current_binds | grep -v '^$')
  fi

  # Adiciona novos binds passados como parâmetro
  for b in "${new_binds[@]}"; do
    binds+=("$b")
  done


  # Garante SSH_BIND válido
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

  # Normaliza binds atuais
  normalized_binds=()
  for b in "${binds[@]}"; do
    normalized_binds+=("${b%%/*}")
  done

  # Adiciona SSH_BIND se ainda não estiver presente
  if [[ ! " ${normalized_binds[*]} " =~ " ${SSH_BIND} " ]]; then
    binds=("$SSH_BIND" "${binds[@]}")
  fi

  # Remove duplicatas de forma segura
  binds=($(unique_binds "${binds[@]}"))

  # Prepara argumentos -p
  local ports_args=()
  for b in "${binds[@]}"; do
    ports_args+=(-p "$b")
  done

  # Detecta se devemos usar host network
  # Detecta se container atual está em host network
  # Só define HOST_EXPOSED se ainda não estiver definido
  if [[ -z "$HOST_EXPOSED" ]]; then
      if container_exists; then
          mode=$(docker inspect -f '{{.HostConfig.NetworkMode}}' "${CONTAINER_NAME}")
          if [[ "$mode" == "host" ]]; then
              export HOST_EXPOSED=on
          else
              export HOST_EXPOSED=off
          fi
      else
          export HOST_EXPOSED=off
      fi
  fi



  # Prepara argumentos de rede
  network_args=()
  if [[ "$HOST_EXPOSED" == on ]]; then
      echo "🌐 Mantendo container na host network"
      network_args=(--network host)
      ports_args=()   # ignora binds
  fi


  echo "🚀 Iniciando container '${CONTAINER_NAME}' com binds:"
  printf '  - %s\n' "${binds[@]}"

  if container_exists; then
    # Remover o continer aterior
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
  fi

  docker run --rm -it \
    --privileged \
    --cap-add=NET_ADMIN \
    "${ports_args[@]}" \
    "${network_args[@]}" \
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
  snx connect|start|init  Inicializa e cria o container do zero
  snx reconnect|restart   Remove e recria o container
  snx stop|disconnect     Para e remove o container
  snx ssh <args...>       Executa um comando SSH de dentro do container
  snx bind A:B            Adiciona um novo bind de porta (ex: snx bind 8080:80)
  snx expose on|off       Ativa ou desativa host network (ignora binds se ON)
  snx ports               Mostra todos os binds de portas configuradas
  snx logs                Exibe os logs do container
  snx --help|-h           Mostra esta mensagem de ajuda

Exemplos:
  snx                     Abre um shell bash dentro do container
  snx connect              Cria o container caso não exista
  snx reconnect            Reinicia o container do zero
  snx stop                 Para e remove o container
  snx ssh user@10.0.0.5   Executa SSH dentro do container
  snx bind 8080:80         Adiciona um bind de porta adicional
  snx expose on            Ativa host network (binds serão ignorados)
  snx expose off           Volta a usar binds normais
EOF
}


# -------------------------
# Execução principal
# -------------------------
cd "$(dirname "$(readlink -f "$0")")"

case "$1" in
  "")
    ensure_container_exists
    echo "🔗 Conectando ao container ${CONTAINER_NAME} via bash..."
    docker exec -it "${CONTAINER_NAME}" bash
    ;;

  connect|start|init)
    if container_exists; then
      echo "❌ O container '${CONTAINER_NAME}' já existe."
      echo "💡 Tudo pronto para usar o snx."
      exit 1
    fi
    echo "♻️  Recriando container '${CONTAINER_NAME}'..."
    run_container
    ;;

  reconnect|restart)
    echo "♻️  Recriando container '${CONTAINER_NAME}'..."
    run_container
    ;;

  stop|disconnect)
    if ! container_exists; then
      echo "⚠️  Nenhum container '${CONTAINER_NAME}' encontrado."
      exit 0
    fi
    echo "🛑 Parando e removendo ${CONTAINER_NAME}..."
    docker rm -f "${CONTAINER_NAME}"
    ;;

  ssh)
    ensure_container_exists
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

    ensure_container_exists

    echo "🔎 Obtendo binds atuais..."
    mapfile -t current_binds < <(get_current_binds | grep -v '^$')
    if [[ " ${current_binds[*]} " == *" $NEW_BIND "* ]]; then
      echo "⚠️  O bind $NEW_BIND já existe."
      exit 0
    fi

    echo "➕ Adicionando novo bind: $NEW_BIND"
    binds=("$NEW_BIND")

    echo "♻️  Recriando container com binds atualizados..."
    run_container "${binds[@]}"

    echo "✅ Novo bind aplicado:"
    printf '  - %s\n' "${binds[@]}"
    ;;

  expose)
      if [[ "$2" == "on" ]]; then
          echo "🌐 Ativando host network..."
          export HOST_EXPOSED=on
          run_container
          echo "✅ Container agora está usando host network. Binds serão ignorados."
          echo "⚠️  Host network ativa, todos os binds de porta serão ignorados."
      elif [[ "$2" == "off" ]]; then
          echo "🌐 Desativando host network..."
          export HOST_EXPOSED=off
          run_container
          echo "✅ Container agora usa binds normais."
      else
          echo "❌ Uso incorreto: snx expose on|off"
          exit 1
      fi
      ;;


  ports)
    ensure_container_exists

    echo "🔎 Binds atuais do container '${CONTAINER_NAME}':"
    mapfile -t current_binds < <(get_current_binds | grep -v '^$')

    # Adiciona SSH_BIND se ainda não estiver presente
    SSH_BIND=$(get_env_var "SSH_BIND")
    if [[ -n "$SSH_BIND" && ! " ${current_binds[*]} " =~ " $SSH_BIND " ]]; then
      current_binds=("$SSH_BIND" "${current_binds[@]}")
    fi

    # Mantém todos os binds como estão, sem filtrar
    # current_binds=("${current_binds[@]}")


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
    ensure_container_exists
    echo "📜 Exibindo logs de ${CONTAINER_NAME}..."
    docker logs "${CONTAINER_NAME}"
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
