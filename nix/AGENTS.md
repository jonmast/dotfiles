# nix/

Activated only by:

```
sudo nixos-rebuild switch --flake .#diogenes
```

home-manager runs as a NixOS module inside that rebuild, so this activates system and user config together. A standalone `home-manager switch` writes to the same generation profile and the next rebuild silently reverts it. `nix flake check --no-build` validates evaluation. Layout and "where to edit what" are in `nix/README.md`.

## The Shell and the hyprland config need no rebuild

`nix/home/quickshell/` and `nix/home/hypr/` are both reached via `mkOutOfStoreSymlink` in `nix/home/hyprland.nix`. QML edits go live with `systemctl --user restart quickshell`; hyprland Lua edits with `hyprctl reload`. Consequence for both: the files are in no Nix generation — a rollback leaves them untouched; git is their only history.

Nothing builds the QML, so check it before restarting: `qs-lint <file>...`, or bare to lint the whole shell (`nix/home/qmllint.nix`, needs a rebuild to reach PATH). It catches the mistakes a restart reports only as a blank bar — misspelled property, missing `required property var modelData` in a delegate, unresolved type. A clean file is silent; the tree still has a backlog of ~45 pre-existing findings, so judge your own file, not the total.

## Hyprland config is Lua, not hyprlang

`configType = "lua"` (hyprlang is deprecated upstream since 0.55). The compositor config is hand-written Lua in `nix/home/hypr/`, **not** the module's `settings` attrset — in Lua mode `settings` renders each attribute as an `hl.<name>(...)` call, so hyprlang-shaped attrs emit garbage and drop the session into emergency mode. `nix/home/voxtype.nix` contributes its binds and submaps the same way, via `extraLuaFiles`.

Authoritative API reference is the stub Hyprland ships at `/run/current-system/sw/share/hypr/stubs/hl.meta.lua`. Validate any change with `hyprland --verify-config -c <file>` before switching — it executes the Lua and reports errors with file:line.

## Gotchas in `nix/nixos/diogenes.nix`

Each has a comment block at the site; read it before changing the option.

- **SDDM PAM**: `security.pam.services.sddm.*` is a no-op (nixpkgs sets `useDefaultRules = false`). Login-time PAM — kwallet, fingerprint — goes on `security.pam.services.login`.
- **uwsm**: `programs.uwsm.waylandCompositors.hyprland` stays unset; the generated `.desktop` bypasses `start-hyprland` and drops `cap_sys_nice`.
