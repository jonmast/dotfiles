---
name: jira
description: "Use when jira, tickets, or issues are mentioned"
---

# jira CLI Reference

An agent-friendly Jira CLI with auto-JSON output, structured exit codes, and schema introspection.

## Agent Use

### Schema Introspection

`jira schema` returns a complete, machine-readable description of all commands, flags, JSON output shapes, auth requirements, and exit codes. Agents should call this once at the start of a session instead of relying on help text.

```bash
jira schema | jq '.commands[] | .name'
jira schema | jq '.commands[] | select(.name == "issues list")'
```

### Read-Only Mode

Set `JIRA_READ_ONLY=1` to block all write operations (create, update, transition, comment, assign, etc.). The CLI returns exit code 2 with a clear error message for any blocked command.

```bash
JIRA_READ_ONLY=1 jira issues mine
JIRA_READ_ONLY=1 jira issues show ABC-123
```

### Output Flags

| Flag | Effect |
|------|--------|
| `--json` | Force JSON output (auto-enabled when stdout is not a TTY) |
| `--quiet` | Suppress counts, confirmations, and status messages |

Both flags are available on every command.

## Security

### Secret Handling
- **Use `JIRA_READ_ONLY=1`** when agents only need to inspect data.

### Destructive Operations
The following commands are **destructive or irreversible** — always confirm with the user before executing:
- `jira issues transition` / `bulk-transition` — changes workflow status
- `jira issues update` — modifies issue fields
- `jira issues assign` — changes assignee
- `jira issues move` — moves issues between sprints
- `jira issues link` / `unlink` — changes issue links
- `jira issues comment` — adds a comment (irreversible in the sense it publishes data)
- `jira issues log-work` — logs time (affects reporting)

**Agent safety rules:**
1. Never run write commands without explicit user confirmation.
2. When bulk-targeting via `--jql`, first run `jira search` with the same JQL to show the user what will be affected.
3. Prefer `--json` output to verify targets before applying changes.
4. Use `--dry-run` on bulk operations when available.

## Command Quick Reference

See [REFERENCE.md](REFERENCE.md) for the full command quick reference (issues, projects, search, boards/sprints, users/fields, config).

For machine-readable command discovery, use `jira schema`:

```bash
jira schema
jira schema | jq '.commands[] | select(.name == "issues create")'
```

Don't attempt to guess commands


## Transitions

Ascii diagram
```text
( START )
                      │
                      ▼
                  ┌───────┐
     ┌───────────▶│ OPEN  │◀────────────────────────────┐
     │            └───────┘                             │
     │                │                                 │
     │                ▼                                 │
     │            ┌───────┐                             │
     │            │ TO DO │◀────────┐                   │
     │            └───────┘         │                   │
     │                │             │                   │
     │                ▼             │                   │
     │          ┌───────────┐       │                   │
     │          │    IN     │       │                   │
     │          │ PROGRESS  │───────┼───────────────────┤
     │          └───────────┘       │                   │
     │                │             │                   │
     │                ▼             │                   │
     │          ┌───────────┐       │                   │
     │          │  PENDING  │       │                   │
     │          │ CODE REV  │───────┼───────────────────┤
     │          └───────────┘       │                   │
     │                │             │                   │
     │                ▼             │                   │
     │          ┌───────────┐       │                   │
     │          │ READY FOR │       │                   │
     │          │    UAT    │───────┼───────────────────┘
     │          └───────────┘       │
     │                │             │
     │                ▼             │
     │            ┌───────┐         │
     │            │  ON   │─────────┘
     │            │ PROD  │
     │            └───────┘


================================================================
GLOBAL STATUSES (Accessible from "Any" state)
================================================================

  ┌─────────┐      ┌───────┐
  │ CLOSED  │◀─────│ [Any] │  (End State)
  └─────────┘      └───────┘

  ┌─────────┐      ┌───────┐
  │ ON DECK │◀─────│ [Any] │
  └────┬────┘      └───────┘
       │
       ├──────────────▶ [ OPEN ]
       └──────────────▶ [ TO DO ]

  ┌─────────┐      ┌───────┐
  │ ON HOLD │◀─────│ [Any] │
  └────┬────┘      └───────┘
       │
       ├──────────────▶ [ OPEN ]
       ├──────────────▶ [ TO DO ]
       └──────────────▶ [ IN PROGRESS ]
```

Use `jira issues transition $ISSUE_KEY --to $STATUS` to update status. If there
are no direct links you must move through intermediate states.

### Transition name vs status name

`jira issues list-transitions` returns three fields, and confusing them is the
most common failure:

| Field | Meaning | Example |
|-------|---------|---------|
| `id` | Transition ID — the only unambiguous handle | `261` |
| `name` | The action/button name | `Submit for code review` |
| `to.name` | The status you end up in | `Pending Code Review` |

Two traps:

1. `--to` accepts a **status name or transition ID**, never a transition name.
   Passing `--to "Submit for code review"` fails even though it is a real name.
2. Several transitions can share one destination, so a status name is not always
   unique. On this workflow both `4` ("Closed") and `141` ("Cancel / Close")
   land on `Closed`, making `--to Closed` ambiguous.

Note `.to` is an **object**, not the string that `jira schema` advertises. Read
`.to.name`.

### Advancing to a destination status

Use [scripts/advance.sh](scripts/advance.sh) to move an issue to a destination,
letting it work out the intermediate statuses. Give it just the destination:

```bash
# "Ready for UAT" is not reachable from "In Progress" directly; it routes
# through "Pending Code Review" on its own
scripts/advance.sh ETHEL-98 "Ready for UAT"
scripts/advance.sh ETHEL-98 --to "Ready for UAT"
```

Each argument may be a destination status, a transition name, a transition ID,
or a unique substring of any of them — all three of these hit transition `261`:

```bash
scripts/advance.sh -n ETHEL-98 "Pending Code Review"        # destination status
scripts/advance.sh -n ETHEL-98 "Submit for code review"     # transition name
scripts/advance.sh -n ETHEL-98 261                          # transition ID
```

Extra positional arguments are waypoints the route must pass through, with each
leg routed the same way — useful to force a detour:

```bash
scripts/advance.sh ETHEL-98 "On Hold" "In Progress"
```

- `-n` / `--dry-run` prints the exact `jira` commands it would run, and writes
  nothing.
- `-y` / `--yes` skips the prompt; without a TTY it refuses unless `--yes` is given.
- Leading waypoints equal to the current status are skipped, so re-running a
  half-finished sequence is safe. A *later* waypoint matching the current status
  is treated as a deliberate return trip.
- Ambiguous or unroutable arguments exit `2` and print the full transition table.
- Every hop dispatches by transition ID and verifies the resulting status before
  continuing. `JIRA_MAX_HOPS` (default 12) caps runaway routes.

Routing needs a prior, because Jira only lists transitions out of the issue's
*current* status — the rest of the graph is invisible until you get there. The
pipeline above is the default; override it with `JIRA_STATUS_ORDER`:

```bash
JIRA_STATUS_ORDER='Open|To Do|In Progress|Code Review|Done' scripts/advance.sh ...
```

Consequently only the first hop is resolved against live data; later hops are
projected from that order and marked `[projected]` in the plan. A direct
transition always wins over the projection when one exists.
