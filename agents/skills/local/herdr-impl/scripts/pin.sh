#!/usr/bin/env bash
# Pin a session to Opus 5.5 at a tier, verify it took, and print the model.
set -euo pipefail
source "$(dirname "$0")/api.sh"

[[ $# -eq 2 ]] || { echo "usage: pin.sh <session-id> <low|medium|high|xhigh>" >&2; exit 2; }
sid=$1 tier=$2
case $tier in low | medium | high | xhigh) ;; *) echo "pin.sh: unknown tier '$tier'" >&2; exit 2 ;; esac

model=$(jq -nc --arg v "$tier" '{providerID: "cliproxyapi-anthropic", id: "claude-opus-5-5", variant: $v}')
api post "/api/session/$sid/model" --data "{\"model\":$model}" >/dev/null

got=$(api get "/api/session/$sid" | jq -c '.data.model')
if ! jq -e --argjson want "$model" '. == $want' <<<"$got" >/dev/null; then
  echo "pin.sh: $sid is on $got, wanted $model" >&2
  exit 1
fi
echo "$got"
