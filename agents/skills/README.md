# Agent skills

Skills pulled from upstream repos, with local edits that survive updates. Managed by
`skills-sync` (source: `chezmoi/dot_local/bin/executable_skills-sync`).

- `sources.toml`: skill name = upstream source (anything `npx skills add` accepts).
- `upstream/<name>/`: untouched upstream copy from the last update. Don't edit it; it is the
  merge base.
- `local/<name>/`: what agents load, through a symlink at `~/.agents/skills/<name>`. Edit
  skills here.

A skill in `local/` with no entry in `sources.toml` is local-only and never updated.

chezmoi still deploys some skills as plain folders from `chezmoi/dot_agents/skills/`: skills with no
upstream (jira, using-qsv, ...) and the Shopify skills, which are frozen for now. Never manage
the same skill in both places; `chezmoi apply` would replace its symlink with a plain folder.

This repo is public. Keep private skills out of `local/` and install them straight into
`~/.agents/skills`, which `skills-sync` leaves alone.

## Commands

| Command | What it does |
|---|---|
| `skills-sync status` | List managed skills, whether they have local edits, and link state. |
| `skills-sync check [name...]` | Report available upstream updates. Changes nothing. |
| `skills-sync update [name...]` | Merge upstream changes into `local/`. Needs a clean git tree. |
| `skills-sync diff [name...]` | Show your edits against upstream. Defaults to every edited skill. |
| `skills-sync add <source> <name...>` | Start managing a skill. `--adopt` keeps the installed copy as `local/`. |
| `skills-sync link [--replace]` | Symlink `local/*` into `~/.agents/skills`. Runs after every `chezmoi apply`. |

## Updating

1. `skills-sync update`
2. Resolve any conflict markers it lists. They are labelled `local`, `old upstream`, and
   `new upstream`.
3. Review with `git diff -- agents/skills/local`, then commit `local/` and `upstream/` together.

To back out an update, `git checkout -- agents/skills` restores both sides.

Don't run `npx skills update`, `check`, or `add` against `~/.agents/skills`: they overwrite local
edits. `npx skills find` is fine for discovering skills; install them with `skills-sync add`.

Skills disabled with lazyskills (moved into `~/.agents/skills/.lazyskills-disabled/`) are left
disabled by `link`.
