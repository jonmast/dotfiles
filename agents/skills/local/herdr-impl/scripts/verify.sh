#!/usr/bin/env bash
# Verify a landing from land.sh, then free its worktree. Each step runs only if
# the one before it passed:
#   1. the integration tip is still the landing     else exit 2
#   2. --verify, from the main checkout              else roll back, exit 4
#   3. --teardown, if given, inside the worktree     a failure warns, the land stands
#   4. herdr worktree remove --workspace <ws>
# Prints one JSON line. A failed verify keeps its full log and prints its tail.
#
# --verify and --teardown come from the project profile and run under bash -c
# with LAND_OLD and LAND_NEW (the tip before and after), LAND_BRANCH and
# LAND_WORKTREE set, so a verify can install only when the lockfile changed:
#   git diff --quiet "$LAND_OLD" "$LAND_NEW" -- package-lock.json || npm ci
# The teardown runs in the worktree, so a repo command that derives its
# copies' names from the checkout (e.g. `npm run test:db:drop`) frees them
# without the caller knowing those names.
set -euo pipefail

usage() {
  echo "usage: verify.sh --branch <branch> --workspace <id> --range <old>..<new> --verify '<cmd>' [--teardown '<cmd>']" >&2
  exit 2
}
branch='' ws='' range='' verify='' teardown=''
while [[ $# -gt 0 ]]; do
  case $1 in
    --branch) branch=$2; shift 2 ;;
    --workspace) ws=$2; shift 2 ;;
    --range) range=$2; shift 2 ;;
    --verify) verify=$2; shift 2 ;;
    --teardown) teardown=$2; shift 2 ;;
    *) usage ;;
  esac
done
[[ -n $branch && -n $ws && $range == *..* && -n $verify ]] || usage

old=$(git rev-parse --verify "${range%%..*}^{commit}")
new=$(git rev-parse --verify "${range##*..}^{commit}")
[[ $(git rev-parse HEAD) == "$new" ]] || {
  echo "verify.sh: the integration tip moved past $range; land nothing until its verify passes" >&2
  exit 2
}

worktree=$(git worktree list --porcelain | awk -v ref="refs/heads/$branch" '
  /^worktree / { path = substr($0, 10) }
  $0 == "branch " ref && !found { print path; found = 1 }')

log=/tmp/opencode/land-${branch//\//_}.log
mkdir -p /tmp/opencode
if ! LAND_OLD=$old LAND_NEW=$new LAND_BRANCH=$branch LAND_WORKTREE=$worktree bash -c "$verify" >"$log" 2>&1; then
  git reset --quiet --keep "$old"
  jq -nc --arg b "$branch" --arg l "$log" --arg t "$(tail -n 30 "$log")" \
    '{verified: false, branch: $b, reason: "verify", log: $l, tail: $t}'
  exit 4
fi

warn=''
if [[ -n $teardown ]]; then
  if [[ -z $worktree ]]; then
    warn="teardown skipped: no worktree has $branch checked out"
  elif ! (cd "$worktree" && LAND_OLD=$old LAND_NEW=$new LAND_BRANCH=$branch LAND_WORKTREE=$worktree \
    bash -c "$teardown") >>"$log" 2>&1; then
    warn="teardown failed, see $log"
  fi
fi

herdr worktree remove --workspace "$ws" >/dev/null

jq -nc --arg b "$branch" --arg r "$range" --arg w "$warn" \
  '{verified: true, branch: $b, range: $r} + (if $w == "" then {} else {warning: $w} end)'
