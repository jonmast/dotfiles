# AGENTS.md

Dotfiles for several machines. Two trees, two activation paths:

- **`chezmoi/`** — shared dotfiles, applied on every machine with `chezmoi apply`. Templates branch on `.chezmoi.os` (linux/darwin); the one hostname conditional is in `.chezmoiignore`, which keeps chezmoi's opencode config and agent skills off Diogenes (managed outside chezmoi there).
- **`nix/` + `flake.nix`** — NixOS config for one host, **Diogenes**. No other machine evaluates it. Activation and gotchas are in `nix/AGENTS.md`.

No CI, tests, or task runner. One linter: `qs-lint` for The Shell's QML (see `nix/AGENTS.md`). Vocabulary (Diogenes, The Shell, Lock stack, …) lives in `CONTEXT.md`; decisions in `docs/adr/`.

## Gotchas

- **chezmoi file modes**: chezmoi ignores git's executable bit. Scripts and git hooks need the `executable_` prefix or they land as `644` and git silently skips the hook.
- **`.scratch/`** is the local issue tracker the engineering skills write to. It is ignored via `.git/info/exclude` (not `.gitignore`), so it never shows in `git status` and won't follow a fresh clone.
