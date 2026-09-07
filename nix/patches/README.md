# Fractal hover-reactions patch

Personal patch that moves the quick-reaction chooser from the
right-click context menu to a hover-revealed button in
[gnome-fractal](https://gitlab.gnome.org/GNOME/fractal).

## Status: **enabled** in `home/common.nix`

`fractalPatched` (a `pkgs.fractal.overrideAttrs` in the `let` block at the
top of `home/common.nix`) is what's in `home.packages`. The rebuild is slow;
to fall back to stock, swap `fractalPatched` for `fractal` in the package
list.

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
`pkgs.fractal.overrideAttrs`.
