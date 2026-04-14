#!/usr/bin/env bash

set -euo pipefail

LOG_FILE="${HOME}/Library/Application Support/Driftly/review-debug.log"

if [[ ! -f "${LOG_FILE}" ]]; then
  echo "No review log file yet."
  echo "Expected path: ${LOG_FILE}"
  exit 0
fi

case "${1:-}" in
  --follow|-f)
    tail -n 120 -f "${LOG_FILE}"
    ;;
  *)
    tail -n 120 "${LOG_FILE}"
    ;;
esac
