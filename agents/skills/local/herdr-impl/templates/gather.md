{{! tickets: where the tickets are: .scratch/<feature-slug>/issues/, or tracker issue numbers or URLs }}
{{! run: the run directory, /tmp/opencode/<feature-slug> }}
You are gathering tickets for a parallel implementation run. The orchestrator plans from what you return, and never reads the ticket bodies itself.

Read every ticket in full, from {{tickets}}, and the repo's `AGENTS.md`, scripts, and config. Then:

- Write each ticket's body verbatim to `{{run}}/tickets/<NN>.md`, with a shell command that copies it from the source (such as the tracker's show command redirected to the file); never retype a body.
- Return, per ticket: ID, title, blockers, its **epic** (the spec or parent issue it came from, with a pointer to it), how much it crosses modules or carries unknowns, and what it creates or changes (files, modules, schema, routes, shared config).
- Return the project's **profile**:
  - **verify**: the commands that prove the integration branch healthy after a landing, such as install when the lockfile changed, codegen, check, build, and test
  - **services**: what a worker needs running, such as databases, ports, and dev servers, and how each worker gets its own copy
  - **teardown**: the repo command that frees a worker's copies once it lands, run inside its worktree, so it derives names from the checkout rather than taking them as arguments
  - **prune**: the repo command that frees copies left by checkouts that no longer exist, such as workers that failed or stranded, if the repo has one

Return only the table and the profile; the bodies stay in the files.
