---
name: using-mcpc-with-mikes-minion
description: Use when answering questions about projects, tickets, meetings, Slack, or time tracking - or any task requiring data from mikes-minion (AgentPM MCP server)
---

# Using mcpc with mikes-minion

## Overview

`mcpc` is a universal MCP CLI client. `@mikes-minion` is a persistent session connected to the AgentPM server at `pm-dashboard-production-2c16.up.railway.app`, which indexes project data from Jira, Fireflies meetings, Slack, Tempo time tracking, and Notion/GitHub.

## Check / Restore Session

```bash
mcpc                          # list sessions — look for @mikes-minion ● live
mcpc @mikes-minion            # show server info and tools
mcpc restart @mikes-minion    # if session is crashed or stale
```

If session is missing entirely:
```bash
mcpc connect https://pm-dashboard-production-2c16.up.railway.app @mikes-minion
```

## Tool Quick Reference

| Tool | Use for |
|------|---------|
| `search_project_data` | Broad search across ALL sources at once |
| `search_meetings` | Meeting transcripts and decisions (Fireflies) |
| `search_tickets` | Jira issues, bugs, stories, comments |
| `search_time_logs` | Find specific time entries by topic |
| `get_tempo_hours` | Aggregated hour totals per project/person |
| `search_slack` | Slack channel discussions |
| `get_document` | Full content of a document by ID from search results |
| `list_projects` | List available project keys (run this first if unsure) |

## Key Distinctions

**`search_time_logs` vs `get_tempo_hours`:**
- `search_time_logs` → "What did Mike work on related to authentication?" (specific entries)
- `get_tempo_hours` → "How many hours were logged on SUBS last week?" (totals/aggregates)

**`search_project_data` vs targeted search:**
- Use targeted tools (`search_tickets`, `search_meetings`, etc.) when you know the source
- Use `search_project_data` to cast a wide net across all sources at once

## Command Syntax

```bash
# Basic tool call
mcpc @mikes-minion tools-call search_tickets query:="authentication bug"

# With optional filters
mcpc @mikes-minion tools-call search_tickets \
  query:="login error" \
  project:=SUBS \
  status:="In Progress" \
  assignee:=Mike

# Date range filter
mcpc @mikes-minion tools-call search_meetings \
  query:="roadmap planning" \
  date_from:=2026-01-01 \
  date_to:=2026-03-31

# Get full document (use exact ID from search results)
mcpc @mikes-minion tools-call get_document document_id:="fireflies-01JP32GZ06TBEVEC0R2PA1HRH9"

# Aggregated hours
mcpc @mikes-minion tools-call get_tempo_hours project:=SUBS date_from:=2026-04-01

# List projects to find valid project keys
mcpc @mikes-minion tools-call list_projects
```

## Argument Syntax Rules

- Use `:=` with no spaces: `query:="my search"` ✅ not `query := "my search"` ❌
- Values auto-parsed: numbers/booleans become their types, otherwise strings
- Variables with spaces: `"query:=${VAR}"` (wrap whole arg in quotes)
- JSON input via stdin: `echo '{"query":"..."}' | mcpc @mikes-minion tools-call search_tickets`

## Common Patterns

**Discover then deep-dive:**
```bash
# 1. Search to find relevant item IDs
mcpc @mikes-minion tools-call search_meetings query:="subscription pricing"
# 2. Get full transcript using the ID from results
mcpc @mikes-minion tools-call get_document document_id:="fireflies-XXXXX"
```

**Cross-source investigation:**
```bash
# Start broad
mcpc @mikes-minion tools-call search_project_data query:="payment integration" project:=BC
# Then drill into specific source
mcpc @mikes-minion tools-call search_tickets query:="payment integration" project:=BC
```

**JSON mode for scripting:**
```bash
mcpc --json @mikes-minion tools-call list_projects | jq '.result'
```

## Troubleshooting

- **"Cannot connect to bridge"** → `mcpc restart @mikes-minion`
- **Wrong IDs** → Always use the `**ID**:` field from search results, never construct IDs manually
- **No results** → Try `list_projects` to confirm valid project keys; broaden the query
- **Session missing** → Re-run `mcpc connect` command above
