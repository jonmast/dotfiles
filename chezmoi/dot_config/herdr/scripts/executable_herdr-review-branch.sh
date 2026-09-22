#!/usr/bin/env bash
# Herdr popup: fuzzy-pick a recently modified branch, then open a stack-aware
# reviewr pane next to the caller pane.
set -euo pipefail

# Popups get a minimal PATH; make sure we use the current herdr (and fzf/jq).
export PATH="$HOME/.local/bin:$PATH"

die() { printf '%s\n' "$1" >&2; read -rsn1 -p 'press any key...' </dev/tty || sleep 5; exit 1; }

caller="${HERDR_ACTIVE_PANE_ID:?run from a herdr popup keybind}"
cache_root="$HOME/.cache/herdr-review"

# Sweep: remove leftover throwaway worktrees from crashed/killed review panes.
# Skips any worktree still hosting a live pane, and any with uncommitted changes.
if [ -d "$cache_root" ]; then
  live_cwds=$(herdr pane list 2>/dev/null | jq -r '.result.panes[]? | .foreground_cwd // .cwd' || true)
  for wt in "$cache_root"/*/*/; do
    [ -d "$wt" ] || continue
    wt=${wt%/}
    grep -qxF "$wt" <<<"$live_cwds" && continue
    [ -z "$(git -C "$wt" status --porcelain 2>/dev/null)" ] || continue
    git -C "$wt" worktree remove "$wt" >/dev/null 2>&1 || true
  done
fi

# Resolve the caller pane's working directory (foreground process cwd wins).
cwd=$(herdr pane get "$caller" | jq -r '.result.pane.foreground_cwd // .result.pane.cwd')
cd "$cwd" 2>/dev/null || die "cannot cd to $cwd"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git repo: $cwd"

# Pick a branch, most recently committed first.
branch=$(git for-each-ref --sort=-committerdate refs/heads \
    --format='%(refname:short)%09%(committerdate:relative)%09%(subject)' |
  column -t -s $'\t' -o '  ' |
  fzf --prompt='review branch> ' --header='recently modified branches' --no-multi |
  awk '{print $1}') || true
[ -n "${branch:-}" ] || exit 0

# Find a checkout of that branch: existing worktree, or create a throwaway one.
dir=$(git worktree list --porcelain | awk -v b="refs/heads/$branch" '
  /^worktree /{wt=$2} $0=="branch "b{print wt; exit}')
if [ -z "$dir" ]; then
  dir="$cache_root/$(basename "$(git rev-parse --show-toplevel)")/${branch//\//__}"
  if [ ! -d "$dir" ]; then
    mkdir -p "$(dirname "$dir")"
    git worktree add "$dir" "$branch" >/dev/null 2>&1 || die "worktree add failed for $branch"
  fi
  ephemeral=1
fi

# Stack-aware base: parent layer from gh-stack, else repo default branch.
base=""
stack_json=$(cd "$dir" && gh stack view --json 2>/dev/null) || stack_json=""
if [ -n "$stack_json" ]; then
  base=$(jq -r --arg b "$branch" '
    (.branches | map(.name)) as $n | ($n | index($b)) as $i |
    if $i == null then "" elif $i == 0 then .trunk else $n[$i-1] end' <<<"$stack_json")
fi
if [ -z "$base" ]; then
  base=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||') || base="main"
fi

# Resolve the reviewr binary from the live plugin root (path is pinned per commit).
plugin_root=$(herdr plugin list --plugin persiyanov.reviewr --json |
  jq -r '.result.plugins[0].plugin_root')
reviewr="$plugin_root/bin/herdr-reviewr"
[ -x "$reviewr" ] || die "reviewr binary not found: $reviewr"

# Open the reviewer pane beside the caller.
id=$(herdr pane split --pane "$caller" --direction right --cwd "$dir" --focus |
  jq -r '.result.pane.pane_id')
if [ -n "${ephemeral:-}" ]; then
  # Throwaway worktree: after reviewr exits, remove it (unless dirty) and close the pane.
  qdir=$(printf '%q' "$dir")
  herdr pane run "$id" "$reviewr --base $(printf '%q' "$base"); cd /; [ -n \"\$(git -C $qdir status --porcelain)\" ] || git -C $qdir worktree remove $qdir; herdr pane close $id"
else
  herdr pane run "$id" "exec $reviewr --base $(printf '%q' "$base")"
fi
