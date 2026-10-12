#!/usr/bin/env bash
# Block until a worker settles, then print one JSON line:
#   {"state":"idle"}                       turn closed, nothing in its session tree running
#   {"state":"blocked","permissions":[…]}  a permission request is pending (worker or subagent)
#   {"state":"asking","forms":[…]}         a question form is waiting in the worker's TUI
#   {"state":"stalled","last":"<type>"}    nothing running, yet the turn never closed
#   {"state":"timeout"}                    --timeout elapsed (exit 124)
#
# `herdr agent wait` reads the TUI, which shows idle while background subagents
# still run. This reads the opencode API instead: the session and every
# descendant must be inactive, the last message must be `idle`, and the inbox
# empty, on two polls in a row (a finished subagent wakes its parent a few ms
# after going idle itself).
set -euo pipefail
source "$(dirname "$0")/api.sh"

usage() { echo "usage: wait.sh <session-id> [--interval SEC] [--timeout SEC] [--stall SEC]" >&2; exit 2; }
[[ $# -ge 1 ]] || usage
sid=$1; shift
interval=5 timeout=0 stall=120
while [[ $# -gt 0 ]]; do
  case $1 in
    --interval) interval=$2; shift 2 ;;
    --timeout) timeout=$2; shift 2 ;;
    --stall) stall=$2; shift 2 ;;
    *) usage ;;
  esac
done

api get "/api/session/$sid" >/dev/null

declare -A parent
in_tree() {
  local s=$1
  while [[ -n $s && $s != null ]]; do
    [[ $s == "$sid" ]] && return 0
    [[ -v parent[$s] ]] || parent[$s]=$(api get "/api/session/$s" 2>/dev/null | jq -r '.data.parentID // "null"' || echo null)
    s=${parent[$s]}
  done
  return 1
}

pending() {
  local path=$1 filter=$2 s
  for s in "${tree[@]}"; do
    api get "/api/session/$s/$path" | jq -c '.data[]'
  done | jq -sc "unique_by(.id) | map($filter)"
}

calm=0 quiet=0
while :; do
  mapfile -t running < <(api get /api/session/active | jq -r '.data | keys[]')
  tree=("$sid") busy=0
  for s in "${running[@]}"; do
    if in_tree "$s"; then
      busy=1
      [[ $s == "$sid" ]] || tree+=("$s")
    fi
  done

  perms=$(pending permission '{sessionID, id, action, resources, save}')
  if [[ $perms != "[]" ]]; then
    jq -nc --argjson p "$perms" '{state: "blocked", permissions: $p}'
    exit 0
  fi
  forms=$(pending form '{sessionID, id, title}')
  if [[ $forms != "[]" ]]; then
    jq -nc --argjson f "$forms" '{state: "asking", forms: $f}'
    exit 0
  fi

  if (( busy )); then
    calm=0 quiet=0
  else
    last=$(api get "/api/session/$sid/message?limit=1&order=desc" | jq -r '.data[0].type // "none"')
    queued=$(api get "/api/session/$sid/inbox" | jq '.data | length')
    if [[ $last == idle && $queued == 0 ]]; then
      quiet=0
      if (( ++calm >= 2 )); then
        echo '{"state":"idle"}'
        exit 0
      fi
    else
      calm=0
      if (( (quiet += interval) >= stall )); then
        jq -nc --arg l "$last" '{state: "stalled", last: $l}'
        exit 0
      fi
    fi
  fi

  if (( timeout > 0 && SECONDS >= timeout )); then
    echo '{"state":"timeout"}'
    exit 124
  fi
  sleep "$interval"
done
