---
name: graphite
description: Work with Graphite (gt) for stacked git commits, branches, and PRs
             creating, navigating, and managing. Use whenever git operations are needed
---

# Graphite Skill

Work with Graphite (`gt`) for creating, navigating, and managing stacked pull requests.

## Quick Reference

| I want to... | Command |
|--------------|---------|
| Create a new branch/PR | `gt create branch-name -m "message"` |
| Amend current branch's commit (NOT new work) | `gt modify -m "message"` |
| Navigate up the stack | `gt up` |
| Navigate down the stack | `gt down` |
| Jump to top of stack | `gt top` |
| Jump to bottom of stack | `gt bottom` |
| View stack structure | `gt ls` |
| Rebase stack on trunk | `gt restack` |
| Change branch parent | `gt track --parent <branch>` |
| Rename current branch | `gt rename <new-name>` |
| Move branch in stack | `gt move` |

---

## What Makes a Good PR?

In roughly descending order of importance:

- **Atomic/hermetic** - independent of other changes; will pass CI and be safe to deploy on its own
- **Narrow semantic scope** - changes only to module X, or the same change across modules X, Y, Z
- **Small diff** - (heuristic) small total diff line count

**Do NOT worry about creating TOO MANY pull requests.** It is **always** preferable to create more pull requests than fewer.

**NO CHANGE IS TOO SMALL:** tiny PRs allow for the medium/larger-sized PRs to have more clarity.

Always argue in favor of creating more PRs, as long as they independently pass build.

---

## Commit messages

Commit messages will later become the PR description, make them meaningful.

Always include the JIRA id if possible, ask the user if you don't know.

Do _not_ use conventional commits, keep it simple human readable text

Example:

```commit.txt
Add carrier service endpoint

Create new endpoint that will be called from checkout extension in the frontend.
Includes all necessary CORS headers.

Also refactored the schemas into shopify_api for better reusability.

PROJ-321
```

---

## Branch Naming Conventions

When naming PRs in a stack, follow this syntax:

`JIRA_ID/terse-description-of-change`

For example, a 4 PR stack:

```
AUTH-123/reorder-args
AUTH-123/improve-logging
AUTH-123/improve-documentation
AUTH-123/handle-401-status-codes
```

---

## Creating a Stack

### Basic Workflow

1. Make changes to files
2. Stage changes: `git add <files>`
3. Create branch: `gt create branch-name -m "commit message"`
4. Repeat for each PR in the stack

### Handle Untracked Branches (common with worktrees)

Before creating branches, check if the current branch is tracked:

```bash
gt branch info
```

If you see "ERROR: Cannot perform this operation on untracked branch":

**Option A (Recommended): Track temporarily, then re-parent**
1. Track current branch: `gt track -p main`
2. Create your stack normally with `gt create`
3. After creating ALL branches, re-parent your first new branch onto main:
   ```bash
   gt checkout <first-branch-of-your-stack>
   gt track -p main
   gt restack
   ```

**Option B: Stash changes and start from main**
1. `git stash`
2. `git checkout main && git pull`
3. Create new branch and unstash: `git checkout -b temp-working && git stash pop`
4. Proceed with `gt track -p main` and `gt create`

---

## Navigating a Stack

```bash
# Move up one branch (toward top of stack)
gt up

# Move down one branch (toward trunk)
gt down

# Jump to top of stack
gt top

# Jump to bottom of stack (first branch above trunk)
gt bottom

# View the full stack structure
gt ls
```

---

## Modifying a Stack

### `gt create` vs `gt modify`

**`gt create`** makes a new branch with a new commit on top. This is the default — use it for any new work.

**`gt modify`** amends the existing commit on the current branch (like `git commit --amend`). Use it ONLY to fix up the current branch's commit — e.g., to add a missed file or update the commit message.

> **STOP before using `gt modify`:** Confirm with the user that they want to amend the existing commit rather than create a new one.

### Amend Current Branch's Commit

```bash
git add <files>
gt modify -m "updated commit message"
```

### Reorder Branches

Use `gt move` to reorder branches in the stack. This is simpler than trying to use `gt create --insert`.

### Re-parent a Stack

If you created a stack on top of a feature branch but want it based on main:

```bash
# Go to first branch of your stack
gt checkout <first-branch>

# Change its parent to main
gt track --parent main

# Rebase the entire stack
gt restack
```

### Rename a Branch

```bash
gt rename new-branch-name
```

---

## Resetting Commits to Unstaged Changes

If changes are already committed but you want to re-stack them differently:

```bash
# Reset the last commit, keeping changes unstaged
git reset HEAD^

# Reset multiple commits (e.g., last 2 commits)
git reset HEAD~2

# View the diff to understand what you're working with
git diff HEAD
```

---


### Run Validation

After creating each PR, run appropriate linting, building, and testing:

1. Refer to the project's AGENTS.md for specific commands
2. If validation fails, fix the issue, stage changes, and use `gt modify`

---

## Submitting and Updating PRs

**IMPORTANT** Do not under any circumstances attempt to create or update pull
requests, submit branches, or anything of that nature.
```

```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Cannot perform this operation on untracked branch" | Run `gt track -p main` first |
| Stack parented on wrong branch | Use `gt track -p main` then `gt restack` |
| Need to reorder PRs | Use `gt move` |
| Conflicts during restack | Resolve conflicts, then `git rebase --continue` |
| Want to split a PR | Reset commits (`git reset HEAD^`), re-stage selectively, create new branches |
| Need to delete a branch (non-interactive) | `gt delete <branch> -f -q` |
| `gt restack` hitting unrelated conflicts | Use targeted `git rebase <target>` instead (see below) |
| Rebase interrupted mid-conflict | Check if files are resolved but unstaged, then `git add` + `git rebase --continue` |

---

## Advanced: Surgical Rebasing in Complex Stacks

In deeply nested stacks with many sibling branches, `gt restack` can be problematic:
- It restacks ALL branches that need it, not just your stack
- Can hit conflicts in completely unrelated branches
- Is all-or-nothing - hard to be surgical

### When to Use `git rebase` Instead of `gt restack`

Use direct `git rebase` when:
- You only want to update specific branches in your stack
- `gt restack` is hitting conflicts in unrelated branches
- You need to skip obsolete commits during the rebase

### Targeted Rebase Workflow

```bash
# 1. Checkout the branch you want to rebase
git checkout my-feature-branch

# 2. Rebase onto the target (e.g., updated parent branch)
git rebase target-branch

# 3. If you hit conflicts:
#    - Resolve the conflict in the file
#    - Stage it: git add <file>
#    - Continue: git rebase --continue

# 4. If a commit is obsolete and should be skipped:
git rebase --skip

# 5. After rebase, use gt modify to sync graphite's tracking
gt modify --no-edit
```

### Recovering from Interrupted Rebase (Context Reset)

If a rebase was interrupted (e.g., Claude session ran out of context):

1. **Check status:**
   ```bash
   git status
   # Look for "interactive rebase in progress" and "Unmerged paths"
   ```

2. **Read the "unmerged" files** - they may already be resolved (no conflict markers)

3. **If already resolved, just stage and continue:**
   ```bash
   git add <resolved-files>
   git rebase --continue
   ```

4. **If still has conflict markers**, resolve them first, then stage and continue

### Deleting Branches from a Stack

```bash
# Delete a branch (non-interactive, even if not merged)
gt delete branch-to-delete -f -q

# Also delete all children (upstack)
gt delete branch-to-delete -f -q --upstack

# Also delete all ancestors (downstack)
gt delete branch-to-delete -f -q --downstack
```

**Flags:**
- `-f` / `--force`: Delete even if not merged or closed
- `-q` / `--quiet`: Implies `--no-interactive`, minimizes output

**After deleting intermediate branches**, children are automatically restacked onto the parent. If you need to manually update tracking:
```bash
gt checkout child-branch
gt track --parent new-parent-branch
```
