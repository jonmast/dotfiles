#!/usr/bin/env bash
# Land one worker's branch onto the integration branch checked out here, then
# free its worktree. Each step runs only if the one before it passed:
#   1. the branch sits on the integration tip       else exit 3, "behind"
#   2. git merge --ff-only
#   3. --verify, from the main checkout              else roll back, exit 4
#   4. herdr worktree remove --workspace <ws>
#   5. --teardown, if given                          a failure warns, the land stands
# Prints one JSON line. A failed verify keeps its full log and prints its tail.
#
# --verify and --teardown come from the project profile and run under bash -c
# with LAND_OLD and LAND_NEW (the tip before and after) and LAND_BRANCH set, so
# a verify can install only when the lockfile changed:
#   git diff --quiet "$LAND_OLD" "$LAND_NEW" -- package-lock.json || npm ci
set -euo pipefail

usage() {
  echo "usage: land.sh --branch <branch> --workspace <id> --verify '<cmd>' [--teardown '<cmd>']" >&2
  exit 2
}
branch='' ws='' verify='' teardown=''
while [[ $# -gt 0 ]]; do
  case $1 in
    --branch) branch=$2; shift 2 ;;
    --workspace) ws=$2; shift 2 ;;
    --verify) verify=$2; shift 2 ;;
    --teardown) teardown=$2; shift 2 ;;
    *) usage ;;
  esac
done
[[ -n $branch && -n $ws && -n $verify ]] || usage

into=$(git symbolic-ref --short HEAD)
[[ -z $(git status --porcelain --untracked-files=no) ]] || {
  echo "land.sh: $into has uncommitted changes" >&2
  exit 2
}
git rev-parse --verify --quiet "refs/heads/$branch" >/dev/null || {
  echo "land.sh: no branch $branch" >&2
  exit 2
}

old=$(git rev-parse HEAD)
if ! git merge-base --is-ancestor "$old" "$branch"; then
  jq -nc --arg b "$branch" --arg i "$into" '{landed: false, branch: $b, reason: "behind", into: $i}'
  exit 3
fi

git merge --ff-only --quiet "$branch"
new=$(git rev-parse HEAD)

log=/tmp/opencode/land-${branch//\//_}.log
mkdir -p /tmp/opencode
if ! LAND_OLD=$old LAND_NEW=$new LAND_BRANCH=$branch bash -c "$verify" >"$log" 2>&1; then
  git reset --quiet --keep "$old"
  jq -nc --arg b "$branch" --arg l "$log" --arg t "$(tail -n 30 "$log")" \
    '{landed: false, branch: $b, reason: "verify", log: $l, tail: $t}'
  exit 4
fi

herdr worktree remove --workspace "$ws" >/dev/null

warn=''
if [[ -n $teardown ]] && ! LAND_OLD=$old LAND_NEW=$new LAND_BRANCH=$branch bash -c "$teardown" >>"$log" 2>&1; then
  warn="teardown failed, see $log"
fi

jq -nc --arg b "$branch" --arg c "${new:0:7}" --argjson n "$(git rev-list --count "$old..$new")" --arg w "$warn" \
  '{landed: true, branch: $b, commit: $c, commits: $n} + (if $w == "" then {} else {warning: $w} end)'
