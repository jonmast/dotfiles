#!/usr/bin/env bash
# Advance a Jira issue to a destination status, routing through intermediates.
set -euo pipefail

SCRIPT_NAME=$(basename "$0")
DRY_RUN=0
ASSUME_YES=0
MAX_HOPS=${JIRA_MAX_HOPS:-12}
KEY=""
WAYPOINTS=()

# Jira only lists transitions out of the issue's *current* status, so routing to
# a non-adjacent status needs a prior. This is the pipeline from SKILL.md.
DEFAULT_ORDER="Open|To Do|In Progress|Pending Code Review|Ready for UAT|On Prod"
IFS='|' read -r -a ORDER <<<"${JIRA_STATUS_ORDER:-$DEFAULT_ORDER}"

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options] ISSUE_KEY DESTINATION [WAYPOINT ...]
       $SCRIPT_NAME [options] ISSUE_KEY --to DESTINATION

Moves ISSUE_KEY to DESTINATION, working out the intermediate statuses itself.
Extra positional arguments are treated as waypoints the route must pass through,
and each leg between them is routed the same way.

Jira exposes two names per transition and they often disagree: the transition
NAME (the button, e.g. "Submit for code review") and its destination STATUS
(e.g. "Pending Code Review"). Any argument may be either, plus a raw transition
ID. Resolution is tried in this order:

  1. destination status, exact (case-insensitive)
  2. transition ID
  3. transition name, exact (case-insensitive)
  4. destination status, unique substring
  5. transition name, unique substring

If nothing matches a transition available right now, the argument is treated as
a status further down the pipeline and a route is computed toward it. Every hop
is dispatched by transition ID, the only unambiguous handle when several
transitions share a destination status, and the resulting status is verified
before the next hop.

Options:
  -n, --dry-run   Print the exact commands that would run, and change nothing.
  -y, --yes       Skip the confirmation prompt.
  -t, --to DEST   Destination status (same as passing it positionally).
  -h, --help      Show this help.

Environment:
  JIRA_STATUS_ORDER  '|'-separated pipeline used for routing. Default:
                     $DEFAULT_ORDER
  JIRA_MAX_HOPS      Safety cap on transitions per run (default 12).

Examples:
  $SCRIPT_NAME -n ETHEL-98 "Ready for UAT"     # routes via Pending Code Review
  $SCRIPT_NAME ETHEL-98 --to "Ready for UAT"
  $SCRIPT_NAME ETHEL-98 "On Hold" "In Progress"  # forced via On Hold
  $SCRIPT_NAME -y ETHEL-98 261                   # a single transition, by ID

Exit codes: 0 ok | 2 bad input or unroutable destination | 3 auth
            4 not found | 5 api error | 6 rate limited
EOF
}

die() { local code=$1; shift; printf '%s: %s\n' "$SCRIPT_NAME" "$*" >&2; exit "$code"; }

[[ ${BASH_VERSINFO[0]:-0} -ge 4 ]] || die 2 "requires bash 4+ (found ${BASH_VERSION:-unknown})"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run) DRY_RUN=1; shift ;;
    -y|--yes)     ASSUME_YES=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    -t|--to)      [[ $# -ge 2 ]] || die 2 "--to needs a value"; WAYPOINTS+=("$2"); shift 2 ;;
    --to=*)       WAYPOINTS+=("${1#--to=}"); shift ;;
    --)           shift; break ;;
    -*)           die 2 "unknown option '$1' (try --help)" ;;
    *)            if [[ -z $KEY ]]; then KEY=$1; else WAYPOINTS+=("$1"); fi; shift ;;
  esac
done
while [[ $# -gt 0 ]]; do
  if [[ -z $KEY ]]; then KEY=$1; else WAYPOINTS+=("$1"); fi
  shift
done

[[ -n $KEY ]] || { usage >&2; exit 2; }
[[ ${#WAYPOINTS[@]} -ge 1 ]] || die 2 "no destination given (try --help)"

command -v jira >/dev/null || die 2 "'jira' CLI not found on PATH"
command -v jq   >/dev/null || die 2 "'jq' not found on PATH"

# Populates JIRA_OUT; retries the one error class the CLI marks retryable.
JIRA_OUT=""
run_jira() {
  local attempt=0 rc errfile msg
  errfile=$(mktemp)
  while :; do
    set +e
    JIRA_OUT=$(jira --output json "$@" 2>"$errfile")
    rc=$?
    set -e
    [[ $rc -eq 6 && $attempt -lt 3 ]] || break
    attempt=$((attempt + 1))
    printf 'rate limited; retrying in %ss\n' $((attempt * 5)) >&2
    sleep $((attempt * 5))
  done
  msg=$(cat "$errfile")
  rm -f "$errfile"
  if [[ $rc -ne 0 ]]; then
    [[ -n $msg ]] || msg=$JIRA_OUT
    printf '%s: command failed (exit %s): jira %s\n%s\n' "$SCRIPT_NAME" "$rc" "$*" "$msg" >&2
  fi
  return $rc
}

# list-transitions returns a bare array while list-style commands wrap in .items;
# normalise both, and flatten .to (an object) down to its status name.
normalise_transitions='
  (if type == "array" then . else (.items // []) end)
  | map({ id: .id, name: .name, to: (if (.to | type) == "object" then .to.name else .to end) })
'

fetch_transitions() {
  run_jira issues list-transitions "$KEY" || exit $?
  jq -c "$normalise_transitions" <<<"$JIRA_OUT"
}

current_status() {
  run_jira issues show "$KEY" || exit $?
  jq -r '.status // empty' <<<"$JIRA_OUT"
}

# Render an argv as a copy-pasteable shell command, quoting only where needed.
shell_cmd() {
  local a parts=()
  for a in "$@"; do
    if [[ -z $a || $a == *[!A-Za-z0-9_./:=-]* ]]; then
      parts+=("'${a//\'/\'\\\'\'}'")
    else
      parts+=("$a")
    fi
  done
  printf '%s' "${parts[*]}"
}

print_transitions() {
  local transitions=$1 id name to
  printf '\nAvailable transitions from "%s":\n' "$CURRENT"
  printf '  %-6s  %-30s  %s\n' "ID" "TRANSITION NAME" "DESTINATION STATUS"
  while IFS=$'\t' read -r id name to; do
    printf '  %-6s  %-30s  %s\n' "$id" "$name" "$to"
  done < <(jq -r '.[] | [.id, .name, .to] | @tsv' <<<"$transitions")
  printf '\n'
}

order_idx() {
  local s=${1,,} i
  for i in "${!ORDER[@]}"; do
    [[ ${ORDER[$i],,} == "$s" ]] && { printf '%s' "$i"; return; }
  done
  printf '%s' -1
}

# Map a loose token onto a pipeline status name, for routing purposes.
canon_status() {
  local t=${1,,} i hits=()
  for i in "${!ORDER[@]}"; do
    [[ ${ORDER[$i],,} == "$t" ]] && { printf '%s' "${ORDER[$i]}"; return; }
  done
  for i in "${!ORDER[@]}"; do
    [[ ${ORDER[$i],,} == *"$t"* ]] && hits+=("${ORDER[$i]}")
  done
  [[ ${#hits[@]} -eq 1 ]] && printf '%s' "${hits[0]}"
  return 0
}

resolve() {
  local token=$1 transitions=$2
  jq -c --arg tok "$token" '
    def ci: ascii_downcase;
    ($tok | ci) as $t
    | [ (map(select((.to   | ci) == $t))          | select(length > 0) | {tier: "status",            m: .}),
        (map(select( .id           == $tok))      | select(length > 0) | {tier: "transition ID",     m: .}),
        (map(select((.name | ci) == $t))          | select(length > 0) | {tier: "transition name",   m: .}),
        (map(select((.to   | ci) | contains($t))) | select(length > 0) | {tier: "status ~",          m: .}),
        (map(select((.name | ci) | contains($t))) | select(length > 0) | {tier: "transition name ~", m: .}) ]
    | first as $hit
    | if $hit == null then
        {ok: false, reason: "no_match"}
      elif ($hit.m | map(.to) | unique | length) > 1 then
        {ok: false, reason: "ambiguous", tier: $hit.tier,
         options: ($hit.m | map("\(.id) \(.name) -> \(.to)"))}
      else
        $hit.m[0] as $x
        | {ok: true, tier: $hit.tier, id: $x.id, name: $x.name, to: $x.to,
           siblings: (($hit.m | length) - 1)}
      end
  ' <<<"$transitions"
}

# Choose the transition that makes the most progress toward $1 (a pipeline index)
# without overshooting it. Sets RES_* on success.
next_hop() {
  local tidx=$1 transitions=$2 cidx id name to didx best=-1
  cidx=$(order_idx "$CURRENT")
  RES_ID=""
  while IFS=$'\t' read -r id name to; do
    didx=$(order_idx "$to")
    [[ $didx -eq -1 ]] && continue
    if [[ $tidx -gt $cidx ]]; then
      (( didx > cidx && didx <= tidx )) || continue
      (( best == -1 || didx > best )) || continue
    else
      (( didx >= tidx && didx < cidx )) || continue
      (( best == -1 || didx < best )) || continue
    fi
    best=$didx; RES_ID=$id; RES_NAME=$name; RES_TO=$to; RES_TIER="routed"; RES_SIBLINGS=0
  done < <(jq -r '.[] | [.id, .name, .to] | @tsv' <<<"$transitions")
  [[ -n $RES_ID ]]
}

# Work out the single next transition toward $1. Sets RES_*.
decide() {
  local token=$1 transitions=$2 res reason canon tidx
  res=$(resolve "$token" "$transitions")
  reason=$(jq -r '.reason // ""' <<<"$res")

  if [[ $(jq -r '.ok' <<<"$res") == true ]]; then
    RES_ID=$(jq -r '.id' <<<"$res")
    RES_NAME=$(jq -r '.name' <<<"$res")
    RES_TO=$(jq -r '.to' <<<"$res")
    RES_TIER=$(jq -r '.tier' <<<"$res")
    RES_SIBLINGS=$(jq -r '.siblings' <<<"$res")
    return 0
  fi

  if [[ $reason == ambiguous ]]; then
    printf '%s: "%s" is ambiguous — matches by %s lead to different statuses:\n' \
      "$SCRIPT_NAME" "$token" "$(jq -r '.tier' <<<"$res")" >&2
    jq -r '.options[] | "  " + .' <<<"$res" >&2
    printf 'Re-run using the transition ID to disambiguate.\n' >&2
    print_transitions "$transitions" >&2
    exit 2
  fi

  canon=$(canon_status "$token")
  if [[ -z $canon ]]; then
    printf '%s: "%s" is not available from "%s" and is not a known pipeline status.\n' \
      "$SCRIPT_NAME" "$token" "$CURRENT" >&2
    printf 'Known pipeline (JIRA_STATUS_ORDER): %s\n' "${ORDER[*]}" >&2
    print_transitions "$transitions" >&2
    exit 2
  fi

  tidx=$(order_idx "$canon")
  if ! next_hop "$tidx" "$transitions"; then
    printf '%s: no transition from "%s" makes progress toward "%s".\n' \
      "$SCRIPT_NAME" "$CURRENT" "$canon" >&2
    print_transitions "$transitions" >&2
    exit 2
  fi
}

# Statuses the route is expected to pass through, per the pipeline order.
project_chain() {
  local from=$1 target=$2 from_i to_i i
  from_i=$(order_idx "$from"); to_i=$(order_idx "$target")
  if [[ $to_i -eq -1 || $from_i -eq -1 ]]; then printf '%s\n' "$target"; return; fi
  if (( to_i > from_i )); then
    for ((i = from_i + 1; i <= to_i; i++)); do printf '%s\n' "${ORDER[$i]}"; done
  else
    for ((i = from_i - 1; i >= to_i; i--)); do printf '%s\n' "${ORDER[$i]}"; done
  fi
}

CURRENT=$(current_status)
[[ -n $CURRENT ]] || die 5 "could not read current status for $KEY"
printf '%s is currently "%s"\n' "$KEY" "$CURRENT"

# ---- plan -------------------------------------------------------------------
# Only the first hop can be resolved against live data; the rest is projected
# from the pipeline order, since Jira will not reveal those transitions yet.
# Only *leading* waypoints are skipped: a later one matching the current status
# is a deliberate return trip, not a no-op.
PENDING=()
leading=1
for wp in "${WAYPOINTS[@]}"; do
  canon=$(canon_status "$wp")
  if [[ $leading -eq 1 && ( ${wp,,} == "${CURRENT,,}" || ( -n $canon && ${canon,,} == "${CURRENT,,}" ) ) ]]; then
    printf '  skip  %s (already current)\n' "$wp"
    continue
  fi
  leading=0
  PENDING+=("$wp")
done

if [[ ${#PENDING[@]} -eq 0 ]]; then
  printf 'Nothing to do; %s is already at "%s".\n' "$KEY" "$CURRENT"
  exit 0
fi

TRANSITIONS=$(fetch_transitions)
decide "${PENDING[0]}" "$TRANSITIONS"

printf '\nPlan:\n'
printf '  1. %s -> %s   [%s]\n' "$CURRENT" "$RES_TO" "$RES_TIER"
printf '     %s\n' "$(shell_cmd jira issues transition "$KEY" --to "$RES_ID")"
printf '        # transition %s "%s"\n' "$RES_ID" "$RES_NAME"
if [[ ${RES_SIBLINGS:-0} -gt 0 ]]; then
  printf '        # %s other transition(s) also reach "%s"; using ID %s\n' \
    "$RES_SIBLINGS" "$RES_TO" "$RES_ID"
fi

step=1
sim=$RES_TO
for idx in "${!PENDING[@]}"; do
  wp=${PENDING[$idx]}
  canon=$(canon_status "$wp"); [[ -n $canon ]] || canon=$wp
  [[ ${sim,,} == "${canon,,}" ]] && continue
  while IFS= read -r hop; do
    [[ ${sim,,} == "${hop,,}" ]] && continue
    step=$((step + 1))
    printf '  %s. %s -> %s   [projected]\n' "$step" "$sim" "$hop"
    printf '     %s\n' "$(shell_cmd jira issues list-transitions "$KEY")"
    printf '     %s\n' "$(shell_cmd jira issues transition "$KEY" --to '<id>')"
    sim=$hop
  done < <(project_chain "$sim" "$canon")
done
printf '\n'

if [[ $DRY_RUN -eq 1 ]]; then
  printf 'Dry run; nothing changed.\n'
  exit 0
fi

if [[ $ASSUME_YES -ne 1 ]]; then
  [[ -t 0 ]] || die 2 "refusing to transition non-interactively without --yes"
  read -r -p "Apply these transitions to $KEY? [y/N] " reply
  [[ ${reply,,} == y || ${reply,,} == yes ]] || die 0 "aborted"
fi

# ---- execute ----------------------------------------------------------------
printf '\n'
hops=0
for wp in "${PENDING[@]}"; do
  canon=$(canon_status "$wp")
  while :; do
    [[ ${wp,,} == "${CURRENT,,}" ]] && break
    [[ -n $canon && ${canon,,} == "${CURRENT,,}" ]] && break

    hops=$((hops + 1))
    [[ $hops -le $MAX_HOPS ]] || die 5 "exceeded JIRA_MAX_HOPS=$MAX_HOPS; stopping at \"$CURRENT\""

    TRANSITIONS=$(fetch_transitions)
    decide "$wp" "$TRANSITIONS"

    run_jira issues transition "$KEY" --to "$RES_ID" || exit $?
    new=$(jq -r '.status // empty' <<<"$JIRA_OUT")
    [[ -n $new ]] || new=$(current_status)
    [[ ${new,,} == "${RES_TO,,}" ]] ||
      die 5 "expected \"$RES_TO\" after transition $RES_ID but $KEY is \"$new\""

    printf '  ok  %s -> %s (via %s "%s")\n' "$CURRENT" "$new" "$RES_ID" "$RES_NAME"
    CURRENT=$new
  done
done

printf '\n%s is now "%s"\n' "$KEY" "$CURRENT"
