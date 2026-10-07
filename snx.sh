#!/usr/bin/env bash
set -e

cd "$(dirname "$(readlink -f "$0")")"

ENV_FILE=".env.local"
# ----------------------------------------
# Load variables from the .env.local file
# ----------------------------------------
if [[ -f "${ENV_FILE}" ]]; then
  # Export all variables declared in the file
  set -o allexport
  source "${ENV_FILE}"
  set +o allexport
else
  echo "⚠️  File ${ENV_FILE} not found. Using default values."
fi

# Define variables with fallback
CONTAINER_NAME="${SNX_NAME:-snx}"
IMAGE_NAME="${SNX_IMAGE:-snx}"
SSH_BIND="${SNX_SSH_BIND:-2222}"

# -------------------------
# Helper functions
# -------------------------

ensure_image_exists() {
  if docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
    return 0
  fi

  echo "🛠️  Image '${IMAGE_NAME}' not found locally. Building..."
  if ! docker build -t "${IMAGE_NAME}" .; then
    echo "❌ Failed to build image '${IMAGE_NAME}'."
    exit 1
  fi
}

container_exists() {
  docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
}

get_current_binds() {
docker inspect "${CONTAINER_NAME}" \
  --format '{{json .HostConfig.PortBindings}}' \
  | jq -r 'to_entries[] | "\(.value[0].HostPort):\(.key)"'

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
    echo "❌ Container '${CONTAINER_NAME}' does not exist."
    echo "💡 Use 'snx connect' to create it."
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
# Main run function
# -------------------------
run_container() {
  ensure_image_exists

local new_binds=("$@")       # arguments passed to the function
  local binds=()

  if container_exists; then
    # Get old binds
    mapfile -t binds < <(get_current_binds | grep -v '^$')
  fi

  # Add new binds passed as parameters
  for b in "${new_binds[@]}"; do
    binds+=("$b")
  done


   # Validate and fallback SSH_BIND
   if [[ -z "$SSH_BIND" ]]; then
     echo "⚠️  SNX_SSH_BIND variable not set in ${ENV_FILE}, using 2222 as default."
     SSH_BIND=2222
   fi
   if [[ ! "$SSH_BIND" =~ ^[0-9]+$ ]]; then
     echo "❌ Invalid value for SNX_SSH_BIND in ${ENV_FILE}. Use only the external port number (e.g., 2222)."
     exit 1
   fi

   # Build the full SSH bind
   local ssh_port_bind="${SSH_BIND}:22"

  # Normalize current binds
  normalized_binds=()
  for b in "${binds[@]}"; do
    normalized_binds+=("${b%%/*}")
  done

  # Add SSH bind if not already present
  if [[ ! " ${normalized_binds[*]} " =~ " ${SSH_BIND}:" ]]; then
    binds=("$ssh_port_bind" "${binds[@]}")
  fi

  # Remove duplicates safely
  binds=($(unique_binds "${binds[@]}"))

  # Prepare -p arguments
  local ports_args=()
  for b in "${binds[@]}"; do
    ports_args+=(-p "$b")
  done

  # Detect if we should use host network
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

  # Prepare network arguments
  network_args=()
  if [[ "$HOST_EXPOSED" == on ]]; then
      echo "🌐 Keeping container on host network"
      network_args=(--network host)
      ports_args=()   # ignore binds
  fi


  echo "🚀 Starting container '${CONTAINER_NAME}' with binds:"
  printf '  - %s\n' "${binds[@]}"

  if container_exists; then
    # Remove previous container
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
# Help
# -------------------------
show_help() {
  cat <<EOF
Usage: snx [command] [options]

Available commands:

  snx                     Open a bash shell inside container '${CONTAINER_NAME}'
  snx connect|start|init  Initialize and create the container from scratch
  snx reconnect|restart   Remove and recreate the container
  snx stop|disconnect     Stop and remove the container
  snx ssh <args...>       Execute an SSH command inside the container
  snx bind A:B            Add a new port bind (e.g., snx bind 8080:80)
  snx expose on|off       Enable or disable host network (ignores binds if ON)
  snx ports               Show all configured port binds
  snx logs                Show container logs
  snx status              Show detailed information about the container
  snx --help|-h           Show this help message

Examples:

  snx
      Open a bash shell inside the container.

  snx connect
      Create the container if it does not exist.

  snx reconnect
      Recreate the container from scratch.

  snx stop
      Stop and remove the container.

  snx ssh user@10.0.0.5
      Execute SSH inside the container.

  snx bind 8080:80
      Add an additional port bind.

  snx expose on
      Enable host network (binds will be ignored).

  snx expose off
      Use normal binds again.

  snx ports
      List all currently configured ports.

  snx logs
      Show container logs.

  snx status
      Show full container details, including:
        - Image in use
        - Running status
        - Network mode and exposed ports
        - Volume mounts

Notes:
  - Missing Docker images are built automatically before creating the container.
  - All variables from '.env.local' are automatically loaded.
  - SNX_SSH_BIND defines the external SSH port (default: 2222).
  - HOST_EXPOSED controls whether the container uses host network (ignores binds if 'on').

EOF
}

# -------------------------
# Main execution
# -------------------------
cd "$(dirname "$(readlink -f "$0")")"

case "$1" in
  "")
    ensure_container_exists
    echo "🔗 Connecting to container ${CONTAINER_NAME} via bash..."
    docker exec -it "${CONTAINER_NAME}" bash
    ;;

  connect|start|init)
    if container_exists; then
      echo "❌ Container '${CONTAINER_NAME}' already exists."
      echo "💡 Ready to use snx."
      exit 1
    fi
    echo "♻️  Recreating container '${CONTAINER_NAME}'..."
    run_container
    ;;

  reconnect|restart)
    echo "♻️  Recreating container '${CONTAINER_NAME}'..."
    run_container
    ;;

  stop|disconnect)
    if ! container_exists; then
      echo "⚠️  No container '${CONTAINER_NAME}' found."
      exit 0
    fi
    echo "🛑 Stopping and removing ${CONTAINER_NAME}..."
    docker rm -f "${CONTAINER_NAME}"
    ;;

  ssh)
    ensure_container_exists
    shift
    if [ $# -eq 0 ]; then
      echo "⚠️  No SSH command specified. Example: snx ssh user@10.0.0.5"
      exit 1
    fi
    echo "🔐 Executing SSH inside the container (${CONTAINER_NAME}) → ssh $*"
    docker exec -it "${CONTAINER_NAME}" ssh -- "$@"
    ;;

  bind)
    shift
    if [ $# -ne 1 ]; then
      echo "❌ Incorrect usage. Example: snx bind 8080:80"
      exit 1
    fi
    NEW_BIND="$1"

    ensure_container_exists

    echo "🔎 Getting current binds..."
    mapfile -t current_binds < <(get_current_binds | grep -v '^$')
    if [[ " ${current_binds[*]} " == *" $NEW_BIND "* ]]; then
      echo "⚠️  Bind $NEW_BIND already exists."
      exit 0
    fi

    echo "➕ Adding new bind: $NEW_BIND"
    binds=("$NEW_BIND")

    echo "♻️  Recreating container with updated binds..."
    run_container "${binds[@]}"

    echo "✅ New bind applied:"
    printf '  - %s\n' "${binds[@]}"
    ;;

  expose)
      if [[ "$2" == "on" ]]; then
          echo "🌐 Enabling host network..."
          export HOST_EXPOSED=on
          run_container
          echo "✅ Container is now using host network. Binds will be ignored."
          echo "⚠️  Host network active, all port binds will be ignored."
      elif [[ "$2" == "off" ]]; then
          echo "🌐 Disabling host network..."
          export HOST_EXPOSED=off
          run_container
          echo "✅ Container now uses normal binds."
      else
          echo "❌ Incorrect usage: snx expose on|off"
          exit 1
      fi
      ;;

  ports)
    ensure_container_exists

    echo "🔎 Current binds for container '${CONTAINER_NAME}':"
    mapfile -t current_binds < <(get_current_binds | grep -v '^$')

    # Add SSH_BIND if not present
    if [[ -n "$SSH_BIND" && ! " ${current_binds[*]} " =~ " ${SSH_BIND} " ]]; then
      current_binds=("$SSH_BIND" "${current_binds[@]}")
    fi

    if [ ${#current_binds[@]} -eq 0 ]; then
      echo "⚠️  No binds configured."
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
    echo "📜 Showing logs of ${CONTAINER_NAME}..."
    docker logs "${CONTAINER_NAME}"
    ;;

  status)
      echo "🩺 Status of container '${CONTAINER_NAME}'"
      echo "-------------------------------------"

      # Detect planned configuration (even without container)
      echo "🧩 Planned image: ${IMAGE_NAME}"
      echo "⚙️  Planned SSH port: ${SSH_BIND:-2222}"

      # Determine if host network is enabled
      if [[ "${HOST_EXPOSED}" == "on" ]]; then
        echo "🌐 Planned network mode: host"
      else
        echo "🌐 Planned network mode: bridge"
      fi

      if ! container_exists; then
        echo ""
        echo "🔴 Container does not exist yet."
        echo "💡 Use 'snx connect' to create it."
        exit 0
      fi

      # Container exists — collect real details
      running=$(docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null)
      image=$(docker inspect -f '{{.Config.Image}}' "${CONTAINER_NAME}" 2>/dev/null)
      network_mode=$(docker inspect -f '{{.HostConfig.NetworkMode}}' "${CONTAINER_NAME}" 2>/dev/null)
      created_at=$(docker inspect -f '{{.Created}}' "${CONTAINER_NAME}" 2>/dev/null | cut -d'.' -f1 | sed 's/T/ /')
      ip_addr=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${CONTAINER_NAME}" 2>/dev/null)
      mounts=$(docker inspect -f '{{range .Mounts}}{{println .Source "→" .Destination}}{{end}}' "${CONTAINER_NAME}" 2>/dev/null)

      echo ""
      if [[ "$running" == "true" ]]; then
        echo "🟢 Status: RUNNING"
      else
        echo "🟠 Status: EXISTS, but STOPPED"
      fi

      echo "🧩 Image in use: ${image:-unknown}"
      echo "🌐 Real network mode: ${network_mode:-unknown}"
      echo "📅 Created at: ${created_at:-unknown}"

      if [[ -n "$ip_addr" ]]; then
        echo "🧠 Container IP: ${ip_addr}"
      fi

      echo ""
      echo "🔎 Exposed ports:"
      mapfile -t binds < <(get_current_binds | grep -v '^$')

      if [[ ${#binds[@]} -eq 0 ]]; then
        if [[ "$network_mode" == "host" ]]; then
          echo "  ⚠️  No binds (host mode active)."
        else
          echo "  ⚠️  No ports exposed."
        fi
      else
        for b in "${binds[@]}"; do
          host_port="${b%%:*}"
          container_port="${b##*:}"
          echo "  - ${host_port} → ${container_port}"
        done
      fi

      echo ""
      echo "🗂  Mounts:"
      if [[ -z "$mounts" ]]; then
        echo "  ⚠️  No volumes mounted."
      else
        echo "$mounts" | sed 's/^/  - /'
      fi
      ;;

  --help|-h)
    show_help
    ;;

  *)
    echo "❌ Invalid option: $1"
    echo "Use 'snx --help' to see available options."
    exit 1
    ;;
esac
