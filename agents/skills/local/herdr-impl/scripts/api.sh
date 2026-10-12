# Sourced by the other scripts. `opencode api` exits before a piped stdout
# drains, cutting responses at the 64 KiB pipe buffer; a file receives all of it.
api() {
  local out rc=0
  out=$(mktemp)
  opencode api "$@" >"$out" || rc=$?
  cat "$out"
  rm -f "$out"
  return "$rc"
}
