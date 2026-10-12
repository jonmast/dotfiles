#!/usr/bin/env bash
# Send stdin as a prompt to a worker's session. Returns once the message is
# recorded, so a wait.sh started afterwards cannot see the previous turn's idle.
set -euo pipefail
source "$(dirname "$0")/api.sh"

[[ $# -eq 1 ]] || { echo "usage: prompt.sh <session-id> < prompt.txt" >&2; exit 2; }
sid=$1
text=$(cat)
[[ -n $text ]] || { echo "prompt.sh: empty prompt on stdin" >&2; exit 2; }

api post "/api/session/$sid/prompt" --data "$(jq -nc --arg t "$text" '{text: $t}')" |
  jq -c '{message: .data.id}'
