---
name: herdr-impl
description: Implement a set of tickets in parallel, one Herdr worktree and tier-pinned opencode worker per ticket.
argument-hint: "Tickets: a .scratch/<feature> path, issue numbers, or URLs"
disable-model-invocation: true
---

# Herdr Impl

Implement a set of **tickets** (from `/to-tickets`) in parallel. Each ticket gets its own Herdr worktree and an opencode **worker** pinned to a model **tier**; you orchestrate. Work the **frontier**: every ticket whose blockers are all done runs, up to the **cap**, and each finished ticket can open new ones. Each **epic** gets a review once it has landed, and the run closes with a final review.

Keep your context **contained**: it holds the plan, the IDs, and each worker's report. Ticket bodies live in files, implementation lives in the workers, and command output reaches you as one line or a tail.

Load the `herdr` skill first; invoking this skill is the user's request for worktree topology. It owns the `HERDR_ENV` preflight and the safety rules.

## Scripts

Drive workers through the scripts in `~/.agents/skills/herdr-impl/scripts/`, run by full path. Each header documents its details. They replace `herdr agent prompt`, `wait`, and `read`: Herdr watches the TUI, which shows idle while a worker's background subagents still run.

| Script | Does |
| --- | --- |
| `spawn.sh --name <name> --tier <tier> --branch <branch> --base <ref>` | Worktree, session pinned to the tier, TUI started; prints `session` and `workspace_id` |
| `prompt.sh <session> < <file>` | Sends the file as the worker's next turn |
| `wait.sh <session>` | Blocks until the worker **settles**; prints its state |
| `report.sh <session>` | Prints the worker's latest reply |
| `reply.sh <session> <request-id> once\|always\|reject [message]` | Answers one permission request |
| `pin.sh <session> <tier>` | Moves a worker to a tier and verifies it |
| `land.sh --branch <branch>` | Fast-forwards the integration branch onto the branch; prints one JSON line with the landed `range` |
| `verify.sh --branch <branch> --workspace <id> --range <range> --verify '<cmd>' [--teardown '<cmd>']` | Verifies a landing (rolling it back on failure), runs the teardown inside the worktree, frees it, each step gated on the last; prints one JSON line |
| `render.ts <template> key=value... > <file>` | Fills a prompt template from `../templates/`; `key=@file` reads a value from a file; `--keys <template>` lists its keys |

Every prompt you send, and the gather brief, is a template. Render it into `prompts/` and send the file; never read a template or a rendered prompt. `render.ts` fails on an unknown or missing key, so its exit status is your check.

## State

Keep the run in `/tmp/opencode/<feature-slug>/`:

- `state.md`: the profile, the approved plan, each ticket's epic, each worker's session, workspace, and status, the landing queue, each landing's commit range, and each review's status and open findings. Update it after every settle; it is what you resume from after a compaction.
- `tickets/<NN>.md`: each ticket's body, verbatim.
- `notes/`: shared exploration notes, when step 1 writes them.
- `prompts/`: every prompt you send, built as a file.

## Tiers

Every worker is pinned to Opus 5.5; its tier is the variant (`spawn.sh` and `pin.sh` hold the model). Choose each ticket's tier by complexity:

| Tier | Ticket shape |
| --- | --- |
| `low` | Mechanical and fully specified: rename, config, boilerplate, one area |
| `medium` | A typical tracer bullet with clear acceptance criteria and an existing pattern to follow |
| `high` | Crosses several modules, introduces a new pattern, or carries real unknowns |
| `xhigh` | Ambiguous spec, cross-cutting architecture, or data or concurrency risk |

Tiers are approved at the gate and stay fixed. A ticket added mid-run gets its tier approved the same way before it spawns. **Escalation**: a worker that fails the same check twice is a candidate for one tier up; propose it to the user, and switch only on approval.

## Cap

The **cap** is the most workers **running** at once, set by the user at the gate. A worker is running while it has a turn in progress: building, fixing, rebasing, or validating. An idle worker is not, whether it is queued to land, held for review, or waiting on the user.

Before every prompt that starts a turn, count the running workers; send only while under the cap. The head of the landing queue is the one exception: its turn always goes, so landing never starves. Every other exemption is the user's call: ask, and record their answer in `state.md`.

## Permissions

### Yours: stay out of the worktrees

Every worktree path is outside your session, so reading, searching, or running `git -C` against one raises an external-directory prompt. Never read, list, search, or rebase in a worktree. Reach each one through two channels instead:

- **Its worker**, through the Scripts, which talk to the worker's session by ID.
- **Branches**, from the main checkout: `git log <base>..<branch>`, `git diff --stat <base>...<branch>`. Worktrees share refs, so a worker's commits show there immediately.

### Workers': answer through the API

A worker waiting on a permission prompt settles as `blocked`, and `wait.sh` lists each pending request, its subagents' included, with a `sessionID`, `id`, `action`, `resources`, and `save`. Decide by scope:

- **In scope** (edits and commands inside the worker's own worktree, reading `~/.agents/skills` or `/tmp/opencode/<feature-slug>/`): approve it yourself. This overrides the herdr skill's ask-first default for these requests.
- **Out of scope** (paths outside the worktree, `git push`, network or deploy commands, secrets, anything destructive): relay it to the user with the action, resources, and `save` patterns, and answer as they decide.

Answer with `reply.sh`, passing the request's `sessionID`: `once` for your own approvals, `reject` with a message so the worker knows why, and `always` only when the user chooses it.

- `reject` also rejects every other request pending in that session, so send a session's approvals before its rejection.
- `always` saves the `save` patterns as a durable rule for the whole project, so it also answers sibling workers' matching requests and outlasts this run (`/api/permission/saved` lists and removes them).

## Reviews

A **reviewer** is a worker whose job is one `code-review` and one fix round over a **scope**:

- **Epic review**, only when the run has two or more epics: due once every ticket in the epic has landed, failed, or stranded. Its scope is the epic's landed ranges from `state.md`, judged against the epic's spec.
- **Final review**, every run: due once every ticket and epic review has landed, failed, or stranded. Its scope is everything landed since the base commit. With one epic, it is judged against that epic's spec. With several, each spec has had its review, so it judges standards and the **seams** between epics instead.

Every review diffs against the **base commit**: the base ref's commit, recorded in `state.md` at the gate. In merge mode the base ref is the integration branch itself, so its name points at the moving tip.

Reviewers run at `high` unless the user picks another tier at the gate, and count toward the cap like any worker. Spawn one from the main checkout on the current integration tip, named `r-<epic-slug>` or `r-final`, on branch `<feature-slug>/review-<epic-slug>` or `<feature-slug>/review-final`, and handle its settles as in step 4. Its fixes land through the landing queue like a ticket, while other workers keep landing around it.

Prompt it with the `reviewer` template: `spec` and `epic=1` for an epic review, `spec` alone for a final review of one epic, `seams=1` alone for a final review of several.

## Process

### 1. Gather the tickets

Gather through a `standard` subagent, so ticket bodies stay out of your context. Render the `gather` template to `prompts/gather.md` and tell the subagent to read and follow that file. It writes each ticket's body to `tickets/<NN>.md` and returns a table (per ticket: ID, title, blockers, **epic**, size, and what it creates or changes) and the project's **profile**: **verify** (the commands that prove the integration branch healthy after a landing), **services** (what a worker needs running, and how each gets its own copy), **teardown** (the repo command, run inside a landing worker's worktree, that frees its copies), and **prune** (the repo command that frees copies whose checkout is gone, if any). Both come from the repo, so you never hold a copy's name; when the repo has neither, propose adding them before the gate.

From its table, choose each ticket's tier, and find the **overlaps**: two tickets that could run at once and that create or change the same thing. Resolve each one:

- **Both only add** to the shared thing (a key in a message catalogue, an entry in a registry, a field on a shared type): fix the exact names each ticket adds in `notes/shared-names.md`, and let them run at once. The landing rebase merges the additions.
- **One changes what the other builds on**: give it a blocking edge, with the ticket that should own the shared thing first.

When tickets need the same codebase or docs exploration, brief an exploration subagent to do it once and save its findings as markdown in `notes/`, so workers start from the notes instead of each exploring again.

Done when every ticket's body is on file, its blockers and epic are known, every overlap has fixed names or an edge, the blocking edges form no cycle and name no missing ticket, and the profile names verify, services, and teardown.

### 2. Gate the plan

Show the user, then wait for approval before spawning anything:

- the initial frontier, and what each later ticket waits on, marking the edges you added for overlaps and the names fixed in `notes/shared-names.md`
- each ticket's tier, with a few words on why
- the epics, and the reviews that follow from them (see Reviews), with the reviewer tier
- each ticket's branch: `<feature-slug>/<NN>-<slug>`
- the base ref: the current branch unless told otherwise; record its commit in `state.md` as the base commit
- the profile
- the cap

Ask the **finish mode** here. In both, finished tickets **land** one at a time on an **integration branch** checked out in the main checkout: the worker rebases onto its tip, and you fast-forward it. Every ticket branches from the current tip, so a ticket with any number of blockers starts with all their work, and the landed branches form a straight line in landing order, with blockers always below their dependents.

- **merge**: the integration branch is the current branch, and its linear history is the result.
- **stack**: the integration branch is a scratch `<feature-slug>/integration`; create and check it out from the base before spawning. The landed branches become the stack, bottom to top in landing order.

Then start the profile's shared services yourself, from the main checkout, so no worker's pane owns them, and record where each one runs in `state.md`.

Done when the user has approved the plan, the tiers, the reviews, the cap, and a finish mode, and the shared services are up.

### 3. Spawn the frontier

For each frontier ticket, while under the cap, from the main checkout:

1. Launch its worker, named `t<NN>-<slug>`, and record the `session` and `workspace_id` it prints. A failed spawn names what it created; clean that up before retrying.

   ```bash
   spawn.sh --name t<NN>-<slug> --tier <tier> --branch <branch> --base <integration branch>
   ```

2. Render its prompt from the `worker` template, with `ticket=@tickets/<NN>.md` so the body goes from file to file without passing through your context, and send it:

   ```bash
   render.ts worker ticket=@tickets/<NN>.md ... > prompts/<NN>.md
   prompt.sh <session> < prompts/<NN>.md
   ```

3. Run `wait.sh <session>` with the harness's background mode, one per worker, so each settle comes back to you. Background with `&` or `disown` and the settle is lost.

4. If the tracker records status, mark the ticket in progress, following the repo's tracker conventions.

Done when every frontier ticket under the cap has a prompted worker with a background wait.

### 4. Handle each settle

React to each worker as its background wait returns, independent of the rest of the frontier, by the state it prints. Every answer you send is followed by a fresh background `wait.sh`.

- **blocked**: answer per Permissions.
- **asking**: a question form is open in the worker's TUI, and it won't resolve itself. Ask the user to answer it in that worker's workspace now.
- **interrupted** or **failed**: the turn was cut off. Send the `resume` template.
- **stalled**: the turn stopped without closing; check the pane with `herdr agent read <name> --source visible` and tell the user.
- **idle**: read only its reply, with `report.sh <session>`, and act on it below.

The reply is one of:

- **A question**: relay it to the user, and send the answer with `prompt.sh`.
- **Reports done**: verify. `git log <integration branch>..<branch>` shows its commits, and the report says `git status` is clean and marks every acceptance criterion met or unverified. Send any failed check back to the worker; a second failure of the same check is an escalation (see Tiers). Tell the user about each unverified criterion. A verified worker joins the **landing queue**.
- **A reviewer reports done**: the report marks every finding fixed or open and says `git status` is clean. Record the open findings in `state.md` and tell the user each one. With commits, it joins the landing queue; with none, free its worktree with `herdr worktree remove --workspace <id>`.
- **Reports landed**: see Landing.

A worker that cannot finish **strands** its dependents: hold them back and report them as stranded.

If the opencode server restarts, every wait dies with it. Re-arm a background wait for every worker, and resume each one that settles `interrupted`.

Tell the user one line per event. Give a full status only when they ask, or when you need them.

Repeat until no ticket or epic review is left to spawn, no worker is running, and no verify is running.

#### Landing

The queue lands one worker at a time, so each rebases onto a tip that holds still. Rework finishes before a worker joins the queue, so a landing turn is only a rebase and checks. A landing has two phases: the **merge**, which takes seconds, and the **verify**, which runs the full suite in the background. The next worker rebases onto a merged tip while the verify runs, but nothing merges until it passes, so a failure rolls back cleanly. A ticket counts as landed once its verify passes.

Give the head of the queue its turn by sending it the `landing` template with `final=1`: it rebases onto the tip, resolves conflicts so both sides' behaviour survives, and runs static checks and the tests covering both sides and any conflict. It reports each conflict's resolution, what it ran and the result, and any resolution it is unsure of. The full suite is the verify's job, on the same commit, so the worker doesn't run it too.

The next one or two workers behind the head may get the `landing` template early, with `early=1`, cap permitting, so most of their rebase is done before their turn: it rebases and runs static checks only. At their turn, with `final=1`, they catch up on whatever landed since and test. Hold the rest of the queue: a worker further back rebases once per landing ahead of it.

When the head reports, check `git log <integration branch>..<branch>` shows only its commits. Tests passing with no unsure resolution, and no verify running, means merge it from the main checkout:

```bash
land.sh --branch <branch>
```

- `landed: true`: record its `range` in `state.md`. Start its verify with the harness's background mode, from the main checkout, with the profile's verify and teardown, then give the next worker in the queue its `final=1` turn without waiting:

  ```bash
  verify.sh --branch <branch> --workspace <id> --range <range> --verify '<verify>' --teardown '<teardown>'
  ```

- `reason: "behind"`: the tip moved; give the same worker another turn.

While a verify runs, leave the main checkout alone and hold the next merge, even when its worker reports ready. When the verify returns:

- `verified: true`: the worktree is freed. Mark the ticket done in the tracker, if it records status. Recompute the frontier, spawn each newly unblocked ticket (step 3), spawn each epic review that is now due (see Reviews), and merge the next worker if it has reported.
- `reason: "verify"`: the integration branch is rolled back and the worktree kept; send the tail to the worker, and put it back in the queue once it is fixed. A worker that already rebased onto the failed landing now fails the `git log` check; give it another `final=1` turn with `dropped=<range>`, so it rebases off it.

An unsure resolution goes to the user before anything lands.

### 5. Final review

Once the final review is due (see Reviews), spawn its reviewer and handle its settles as in step 4 until its fixes land or it reports no commits.

Done when the final review has landed or freed its worktree, and its open findings are recorded and reported.

### 6. Finish

In merge mode the integration branch is already the result.

In stack mode, the landed branches already form the line. Adopt them in landing order with `gh stack init --base <base> <first landed> ... <last landed>`, following `/gh-stack`. Then check out the base in the main checkout and delete the scratch integration branch.

Stop the shared services you started, and run the profile's prune from the main checkout.

Done when every ticket and review is landed, failed, or stranded with a reason, and no worker or verify is still running. Report per ticket: branch, tier, outcome, and anything unverified; then per review, its open findings.
