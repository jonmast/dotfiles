#!/usr/bin/env bash
# Launch one worker: a Herdr worktree, an opencode session pinned to a tier,
# and the opencode TUI on that session so the user can watch it. Prints
# {"name","session","workspace_id","pane_id","model"}.
#
# The session is created before the TUI starts because `--model` only works
# with `opencode mini`, whose state Herdr cannot track, and `--session` with an
# unknown ID opens a default session instead of creating one. It is created
# from the worktree's own shell so the worktree path never enters the caller's
# commands (reading a worktree raises an external-directory prompt).
set -euo pipefail

usage() {
  echo "usage: spawn.sh --name <t01-slug> --tier <tier> --branch <branch> --base <ref> [--cwd <main checkout>]" >&2
  exit 2
}
name='' tier='' branch='' base='' cwd=''
while [[ $# -gt 0 ]]; do
  case $1 in
    --name) name=$2; shift 2 ;;
    --tier) tier=$2; shift 2 ;;
    --branch) branch=$2; shift 2 ;;
    --base) base=$2; shift 2 ;;
    --cwd) cwd=$2; shift 2 ;;
    *) usage ;;
  esac
done
[[ -n $name && -n $tier && -n $branch && -n $base ]] || usage
[[ $name =~ ^[A-Za-z0-9-]{1,32}$ ]] || { echo "spawn.sh: name must be 1-32 letters, digits, or dashes" >&2; exit 2; }
cwd=${cwd:-$(git rev-parse --show-toplevel)}
here=$(dirname "$0")
sid="ses_${name//-/}$(date +%s)"

created=()
trap '(( ${#created[@]} )) && echo "spawn.sh: failed after creating: ${created[*]}" >&2' ERR

wt=$(herdr worktree create --cwd "$cwd" --branch "$branch" --base "$base" --label "$name" --no-focus)
ws=$(jq -r '.result.workspace.workspace_id' <<<"$wt")
pane=$(jq -r '.result.root_pane.pane_id' <<<"$wt")
created+=("workspace=$ws")

herdr pane run "$pane" "opencode api post /api/session --data \"{\\\"id\\\":\\\"$sid\\\",\\\"title\\\":\\\"$name\\\",\\\"agent\\\":\\\"build\\\",\\\"location\\\":{\\\"directory\\\":\\\"\$PWD\\\"}}\" >/dev/null" >/dev/null
for _ in $(seq 60); do
  opencode api get "/api/session/$sid" >/dev/null 2>&1 && break
  sleep 0.5
done
opencode api get "/api/session/$sid" >/dev/null
created+=("session=$sid")

"$here/pin.sh" "$sid" "$tier" >/dev/null
herdr agent start "$name" --kind opencode --pane "$pane" -- --session "$sid" >/dev/null
created+=("agent=$name")

# Re-check after the TUI attaches, in case it re-applied its own default.
model=$("$here/pin.sh" "$sid" "$tier")
jq -nc --arg n "$name" --arg s "$sid" --arg w "$ws" --arg p "$pane" --argjson m "$model" \
  '{name: $n, session: $s, workspace_id: $w, pane_id: $p, model: $m}'
