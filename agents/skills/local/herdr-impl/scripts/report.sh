#!/usr/bin/env bash
# Print the text of a worker's latest reply: its report, question, or summary.
set -euo pipefail
source "$(dirname "$0")/api.sh"

[[ $# -eq 1 ]] || { echo "usage: report.sh <session-id>" >&2; exit 2; }
sid=$1

# One message per page: each step of a turn is its own message carrying its
# tool output, and the reply is almost always the newest one.
query="limit=1&order=desc&type=assistant"
for _ in {1..10}; do
  page=$(api get "/api/session/$sid/message?$query")
  text=$(jq -r '[.data[0].content[]? | select(.type == "text") | .text] | join("\n\n")' <<<"$page")
  [[ -n $text ]] && { printf '%s\n' "$text"; exit 0; }
  cursor=$(jq -r '.cursor.next // empty' <<<"$page")
  [[ -n $cursor ]] || break
  query="limit=1&type=assistant&cursor=$cursor"
done
echo "(no reply text yet)"
