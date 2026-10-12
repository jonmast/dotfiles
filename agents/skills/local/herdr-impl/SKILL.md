---
name: herdr-impl
description: Implement a set of tickets in parallel, one Herdr worktree and tier-pinned opencode worker per ticket.
argument-hint: "Tickets: a .scratch/<feature> path, issue numbers, or URLs"
disable-model-invocation: true
---

# Herdr Impl

Implement a set of **tickets** (from `/to-tickets`) in parallel. Each ticket gets its own Herdr worktree and an opencode **worker** pinned to a model **tier**; you orchestrate. Work the **frontier**: every ticket whose blockers are all done runs at once, and each finished ticket can open new ones.

Keep your context **contained**: it holds the plan, the IDs, and each worker's report. The implementation lives in the workers.

Load the `herdr` skill first; invoking this skill is the user's request for worktree topology. It owns the `HERDR_ENV` preflight and the safety rules.

## Scripts

Drive workers through the scripts in `~/.agents/skills/herdr-impl/scripts/`, run by full path. Each header documents its details. They replace `herdr agent prompt`, `wait`, and `read`: Herdr watches the TUI, which shows idle while a worker's background subagents still run.

| Script | Does |
| --- | --- |
| `spawn.sh --name <name> --tier <tier> --branch <branch> --base <ref>` | Worktree, session pinned to the tier, TUI started; prints `session` and `workspace_id` |
| `prompt.sh <session> <<'PROMPT'` | Sends stdin as the worker's next turn |
| `wait.sh <session>` | Blocks until the worker **settles**; prints its state |
| `report.sh <session>` | Prints the worker's latest reply |
| `reply.sh <session> <request-id> once\|always\|reject [message]` | Answers one permission request |
| `pin.sh <session> <tier>` | Moves a worker to a tier and verifies it |

## Tiers

Every worker is pinned to Opus 5.5; its tier is the variant (`spawn.sh` and `pin.sh` hold the model). Choose each ticket's tier by complexity:

| Tier | Ticket shape |
| --- | --- |
| `low` | Mechanical and fully specified: rename, config, boilerplate, one area |
| `medium` | A typical tracer bullet with clear acceptance criteria and an existing pattern to follow |
| `high` | Crosses several modules, introduces a new pattern, or carries real unknowns |
| `xhigh` | Ambiguous spec, cross-cutting architecture, or data or concurrency risk |

Tiers are approved at the gate and stay fixed. **Escalation**: a worker that fails the same check twice is a candidate for one tier up; propose it to the user, and switch only on approval.

## Permissions

### Yours: stay out of the worktrees

Every worktree path is outside your session, so reading, searching, or running `git -C` against one raises an external-directory prompt. Never read, list, or search a worktree. Reach each one through two channels instead:

- **Its worker**, through the Scripts, which talk to the worker's session by ID.
- **Branches**, from the main checkout: `git log <base>..<branch>`, `git diff --stat <base>...<branch>`. Worktrees share refs, so a worker's commits show there immediately.

### Workers': answer through the API

A worker waiting on a permission prompt settles as `blocked`, and `wait.sh` lists each pending request, its subagents' included, with a `sessionID`, `id`, `action`, `resources`, and `save`. Decide by scope:

- **In scope** (edits and commands inside the worker's own worktree, reading `~/.agents/skills`): approve it yourself. This overrides the herdr skill's ask-first default for these requests.
- **Out of scope** (paths outside the worktree, `git push`, network or deploy commands, secrets, anything destructive): relay it to the user with the action, resources, and `save` patterns, and answer as they decide.

Answer with `reply.sh`, passing the request's `sessionID`: `once` for your own approvals, `reject` with a message so the worker knows why, and `always` only when the user chooses it.

- `reject` also rejects every other request pending in that session, so send a session's approvals before its rejection.
- `always` saves the `save` patterns as a durable rule for the whole project, so it also answers sibling workers' matching requests and outlasts this run (`/api/permission/saved` lists and removes them).

## Process

### 1. Gather the tickets

Read every ticket in full: local files under `.scratch/<feature-slug>/issues/`, or tracker issues.

Done when every ticket's body and blockers are known, and the blocking edges form no cycle and name no missing ticket.

### 2. Gate the plan

Show the user, then wait for approval before spawning anything:

- the initial frontier, and what each later ticket waits on
- each ticket's tier, with a few words on why
- each ticket's branch: `<feature-slug>/<NN>-<slug>`
- the base ref: the current branch unless told otherwise

Ask the **finish mode** here. In both, finished tickets **land** one at a time on an **integration branch** checked out in the main checkout: the worker rebases onto its tip, and you fast-forward it. Every ticket branches from the current tip, so a ticket with any number of blockers starts with all their work, and the landed branches form a straight line in landing order, with blockers always below their dependents.

- **merge**: the integration branch is the current branch, and its linear history is the result.
- **stack**: the integration branch is a scratch `<feature-slug>/integration`; create and check it out from the base before spawning. The landed branches become the stack, bottom to top in landing order.

Done when the user has approved the plan and chosen a finish mode.

### 3. Spawn the frontier

For each frontier ticket, from the main checkout:

1. Launch its worker, named `t<NN>-<slug>`, and record the `session` and `workspace_id` it prints. A failed spawn names what it created; clean that up before retrying.

   ```bash
   spawn.sh --name t<NN>-<slug> --tier <tier> --branch <branch> --base <integration branch>
   ```

2. Send the worker prompt through a quoted heredoc, so nothing in the ticket expands:

   ```bash
   prompt.sh <session> <<'PROMPT'
   <worker prompt>
   PROMPT
   ```

3. Run `wait.sh <session>` in the background, one per worker, so each settles independently.

Done when every frontier ticket has a prompted worker with a background wait.

<worker-prompt>
You are a worker implementing one ticket while other workers build other tickets in their own git worktrees.

Branch: <branch>, checked out in this worktree.

Ticket (for a tracker issue, its URL instead):
<the ticket's full body>

Read and follow the implement skill at ~/.agents/skills/implement/SKILL.md for this ticket. This worktree is fresh, so install dependencies before running anything.

Delegate execution: send mechanical edits (renames, boilerplate, small edits) to the `light` subagent and well-specified coding slices to the `standard` subagent, each with a self-contained brief (files, the change, how to verify). Keep planning, judgement calls, debugging, integration, and final verification yourself.

Stay inside this worktree and this ticket's scope. Commit to this branch only; the orchestrator handles pushing and merging. If you need a decision, stop and ask.

Finish with a short report: each acceptance criterion met or not, the commits made, whether `git status` is clean, and anything unverified.
</worker-prompt>

The ticket body goes into the prompt because a worker reading the main checkout would hit its own external-directory prompt.

### 4. Handle each settle

React to each worker as its background wait returns, independent of the rest of the frontier, by the state it prints. Every answer you send is followed by a fresh background `wait.sh`.

- **blocked**: answer per Permissions.
- **asking**: a question form is open in the worker's TUI; ask the user to answer it in that worker's workspace.
- **stalled**: the turn stopped without closing; check the pane with `herdr agent read <name> --source visible` and tell the user.
- **idle**: read only its reply, with `report.sh <session>`, and act on it below.

The reply is one of:

- **A question**: relay it to the user, and send the answer with `prompt.sh`.
- **Reports done**: verify. `git log <integration branch>..<branch>` shows its commits, and the report says `git status` is clean and marks every acceptance criterion met. Send any failed check back to the worker; a second failure of the same check is an escalation (see Tiers). A verified worker joins the **landing queue**.
- **Reports landed**: see Landing.

A worker that cannot finish **strands** its dependents: hold them back and report them as stranded.

Repeat until no ticket is left to spawn and no worker is running.

#### Landing

The queue lands one worker at a time, so each rebases onto a tip that holds still. Give the head of the queue its turn by sending it the landing prompt:

<landing-prompt>
Your turn to land. Rebase this branch onto <integration branch>, which now holds these landed tickets: <title and one-line intent of each>.

Resolve any conflicts so your ticket's behaviour and theirs both survive; editing their code is in scope for this. Then run the full test suite.

Report: each conflicted file and how you resolved it, the test result, whether `git status` is clean, and any resolution you are unsure of.
</landing-prompt>

When it reports, check `git log <integration branch>..<branch>` shows only its commits. Tests passing with no unsure resolution means land it, in the main checkout:

```bash
git merge --ff-only <branch>
```

Run the full test suite, then `herdr worktree remove --workspace <id>`; the branch itself stays. Recompute the frontier, spawn each newly unblocked ticket (step 3), and give the next worker in the queue its turn.

A refused fast-forward means the tip moved: give the same worker another turn. Failing tests go back to the worker, and an unsure resolution goes to the user, before anything lands.

### 5. Finish

In merge mode the integration branch is already the result.

In stack mode, the landed branches already form the line. Adopt them in landing order with `gh stack init --base <base> <first landed> ... <last landed>`, following `/gh-stack`. Then check out the base in the main checkout and delete the scratch integration branch.

Done when every ticket is landed, failed, or stranded with a reason, and no worker is still running. Report per ticket: branch, tier, outcome, and anything unverified.
