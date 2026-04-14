# Driftly experimental zsh hook.
# Source this from `.zshrc` to emit structured terminal command records
# that the future Driftly daemon can ingest from a local inbox.

export DRIFTLY_CAPTURE_DIR="${DRIFTLY_CAPTURE_DIR:-${LOGBOOK_CAPTURE_DIR:-$HOME/Library/Application Support/Driftly/inbox}}"
export LOGBOOK_CAPTURE_DIR="$DRIFTLY_CAPTURE_DIR"
mkdir -p "$DRIFTLY_CAPTURE_DIR"

typeset -g DRIFTLY_LAST_COMMAND=""
typeset -g DRIFTLY_LAST_COMMAND_STARTED_AT=""

_driftly_preexec() {
  DRIFTLY_LAST_COMMAND="${1//$'\n'/ }"
  DRIFTLY_LAST_COMMAND_STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}

_driftly_precmd() {
  local exit_code="$?"

  if [[ -z "$DRIFTLY_LAST_COMMAND" ]]; then
    return
  fi

  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    "$DRIFTLY_LAST_COMMAND_STARTED_AT" \
    "$PWD" \
    "$exit_code" \
    "$DRIFTLY_LAST_COMMAND" >> "$DRIFTLY_CAPTURE_DIR/terminal.tsv"

  DRIFTLY_LAST_COMMAND=""
  DRIFTLY_LAST_COMMAND_STARTED_AT=""
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _driftly_preexec
add-zsh-hook precmd _driftly_precmd
