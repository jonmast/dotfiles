#!/usr/bin/env bash
# Print a worker's state once, without waiting for it to settle: one of
# wait.sh's states, or `running` or `unclosed` (see wait.sh --once).
set -euo pipefail

[[ $# -eq 1 ]] || { echo "usage: status.sh <session-id>" >&2; exit 2; }
exec "$(dirname "$0")/wait.sh" "$1" --once --interval 1
