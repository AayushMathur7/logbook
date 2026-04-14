# Legacy compatibility shim for older `source integrations/shell/logbook.zsh`
# instructions. Prefer `integrations/shell/driftly.zsh`.

source "${${(%):-%N}:A:h}/driftly.zsh"
