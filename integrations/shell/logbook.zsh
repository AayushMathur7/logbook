# Logbook experimental zsh hook.
# Source this from `.zshrc` to emit structured terminal command records
# that the future Logbook daemon can ingest from a local inbox.

export LOGBOOK_CAPTURE_DIR="${LOGBOOK_CAPTURE_DIR:-$HOME/Library/Application Support/Logbook/inbox}"
mkdir -p "$LOGBOOK_CAPTURE_DIR"

typeset -g LOGBOOK_LAST_COMMAND=""
typeset -g LOGBOOK_LAST_COMMAND_STARTED_AT=""

_logbook_preexec() {
  LOGBOOK_LAST_COMMAND="${1//$'\n'/ }"
  LOGBOOK_LAST_COMMAND_STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}

_logbook_precmd() {
  local exit_code="$?"

  if [[ -z "$LOGBOOK_LAST_COMMAND" ]]; then
    return
  fi

  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    "$LOGBOOK_LAST_COMMAND_STARTED_AT" \
    "$PWD" \
    "$exit_code" \
    "$LOGBOOK_LAST_COMMAND" >> "$LOGBOOK_CAPTURE_DIR/terminal.tsv"

  LOGBOOK_LAST_COMMAND=""
  LOGBOOK_LAST_COMMAND_STARTED_AT=""
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _logbook_preexec
add-zsh-hook precmd _logbook_precmd