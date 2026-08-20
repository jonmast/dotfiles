# jira CLI Command Reference

## Issues

```bash
# List issues
jira issues list
jira issues list --project MYAPP --status "In Progress"
jira issues list --project MYAPP --type Bug --assignee me
jira issues list --sprint active
jira issues list --all                        # fetch every page

# Issues assigned to you
jira issues mine
jira issues mine --project MYAPP --status "To Do"

# Show single issue
jira issues show MYAPP-123

# Create issue
jira issues create --project MYAPP --summary "Fix login bug" --type Bug
jira issues create --project MYAPP --summary "Add dark mode" --type Story \
  --description "Users want a dark mode option." --priority High --assignee me
jira issues create --project MYAPP --summary "Write unit tests" \
  --parent MYAPP-42                           # creates a subtask

# Update issue
jira issues update MYAPP-123 --summary "Updated title"
jira issues update MYAPP-123 --priority Low --assignee me
jira issues update MYAPP-123 --field customfield_10016=5

# Transitions
jira issues list-transitions MYAPP-123
jira issues transition MYAPP-123 --to "In Review"

# Assign
jira issues assign MYAPP-123 --assignee me
jira issues assign MYAPP-123 --assignee user@example.com

# Comments
jira issues comment MYAPP-123 --body "Deployed to staging."
jira issues comments MYAPP-123

# Log work
jira issues log-work MYAPP-123 --time-spent 2h
jira issues log-work MYAPP-123 --time-spent 30m --comment "Fixed the flaky test"

# Issue links
jira issues link-types
jira issues link MYAPP-123 --to MYAPP-456 --type "Blocks"
jira issues unlink <link-id>

# Move to sprint
jira issues move MYAPP-123 --sprint active
jira issues move MYAPP-123 --sprint "Sprint 14"

# Bulk operations (use --dry-run to preview)
jira issues bulk-transition --jql 'project = MYAPP AND status = "To Do"' --to "In Progress"
jira issues bulk-transition --jql 'project = MYAPP AND status = "To Do"' --to "In Progress" --dry-run
jira issues bulk-assign --jql 'project = MYAPP AND sprint in openSprints()' --assignee me
```

## Projects

```bash
jira projects list
jira projects show MYAPP
```

## Search (JQL)

```bash
jira search 'project = MYAPP AND sprint in openSprints() ORDER BY priority'
jira search 'assignee = currentUser() AND status != Done' --limit 20
jira search 'project = MYAPP' --all                       # fetch every page
```

## Boards and Sprints

```bash
jira boards list
jira sprints list
jira sprints list --board "MYAPP board"
```

## Users and Fields

```bash
jira users search --query "alice"
jira fields list
jira fields list --custom                     # custom fields only
```

## Config

```bash
jira init                    # setup guide with example config and token URLs
jira config show             # resolved credentials (token masked)
jira config init             # same as jira init
```

## Shell Completions

```bash
jira completions bash --install
jira completions zsh --install
jira completions fish --install
```
