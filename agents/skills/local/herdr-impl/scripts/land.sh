#!/usr/bin/env bash
# Land one worker's branch onto the integration branch checked out here:
#   1. the branch sits on the integration tip       else exit 3, "behind"
#   2. git merge --ff-only
# Prints one JSON line with the landed range, for verify.sh. Landing is fast so
# the next worker can rebase onto the new tip while verify.sh runs; land the
# next branch only once that verify passes.
set -euo pipefail

usage() {
  echo "usage: land.sh --branch <branch>" >&2
  exit 2
}
branch=''
while [[ $# -gt 0 ]]; do
  case $1 in
    --branch) branch=$2; shift 2 ;;
    *) usage ;;
  esac
done
[[ -n $branch ]] || usage

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

jq -nc --arg b "$branch" --arg r "${old:0:7}..${new:0:7}" --argjson n "$(git rev-list --count "$old..$new")" \
  '{landed: true, branch: $b, range: $r, commits: $n}'
