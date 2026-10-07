# Bash completion for the SNX container manager.
_snx_completion() {
  local current="${COMP_WORDS[COMP_CWORD]}"
  COMPREPLY=()

  case "${COMP_CWORD}" in
    1)
      COMPREPLY=($(compgen -W 'install build rebuild reinstall uninstall connect start init reconnect restart stop disconnect ssh bind expose ports logs status --help -h' -- "${current}"))
      ;;
    2)
      if [[ "${COMP_WORDS[1]}" == expose ]]; then
        COMPREPLY=($(compgen -W 'on off' -- "${current}"))
      fi
      ;;
  esac
}

complete -F _snx_completion snx
