#!/usr/bin/env bash
# Answer one pending permission request. Use the sessionID that wait.sh
# reported for the request: a subagent's requests live on its own session.
# `reject` rejects every request pending in that session; `always` saves the
# request's `save` patterns as a durable project-wide allow rule.
set -euo pipefail
source "$(dirname "$0")/api.sh"

[[ $# -ge 3 && $# -le 4 ]] || { echo "usage: reply.sh <session-id> <request-id> <once|always|reject> [message]" >&2; exit 2; }
sid=$1 rid=$2 decision=$3 message=${4:-}
case $decision in once | always | reject) ;; *) echo "reply.sh: decision must be once, always, or reject" >&2; exit 2 ;; esac

api post "/api/session/$sid/permission/$rid/reply" \
  --data "$(jq -nc --arg d "$decision" --arg m "$message" '{decision: $d} + (if $m == "" then {} else {message: $m} end)')" >/dev/null
echo "{\"replied\":\"$rid\",\"decision\":\"$decision\"}"
