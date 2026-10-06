# jira CLI Skill

A global skill for interacting with Jira via the agent-friendly `jira` CLI.

## What's Included

- `SKILL.md` — comprehensive reference for all `jira` commands, security rules, and agent-specific features (schema introspection, read-only mode, exit codes).
- `scripts/advance.sh` — moves an issue to a destination status, routing through the intermediate statuses itself. Accepts a status name, transition name, or transition ID, and has a `--dry-run` mode that prints the exact `jira` commands it would run.

## Security Notes

- Never hardcode tokens in commands. Use env vars or the config file.
- Set `JIRA_READ_ONLY=1` when giving an AI agent access to prevent accidental modifications.
- Confirm with the user before executing write operations (create, update, transition, assign, comment, log-work, link, unlink, move).

## Reference

For complete command details, see `SKILL.md` or run:
```bash
jira schema
```
