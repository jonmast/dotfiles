# Fractal hover-reactions patch

Personal patch that moves the quick-reaction chooser from the
right-click context menu to a hover-revealed button in
[gnome-fractal](https://gitlab.gnome.org/GNOME/fractal).

## Status: **enabled** in `home/common.nix`

`fractalPatched` (a `fractalPkgs.fractal.overrideAttrs` in the `let` block at
the top of `home/common.nix`) is what's in `home.packages`. The rebuild is
slow; to fall back to stock, swap `fractalPatched` for `fractal` in the
package list.

`fractalPkgs` is imported from the frozen `fractal-nixpkgs` flake input (see
`flake.nix`), not from the main `pkgs`. Because the patch forces a local
build, using the main nixpkgs would make every `nix flake update` recompile
fractal; the frozen input keeps it bit-identical to the installed build.

## Regenerate

The patch is generated from a separate checkout at `~/fractal-patch`.
To regenerate after fractal upstream changes:

```bash
cd ~/fractal-patch
git diff HEAD -- src/session_view/room_history/ \
  data/resources/stylesheet/_room_history.scss \
  > fractal-hover-reactions.patch
cp fractal-hover-reactions.patch ~/.dotfiles/nix/patches/
```

The patched package is built in `home/common.nix` via
`fractalPkgs.fractal.overrideAttrs`.
