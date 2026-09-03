# jon's dotfiles

NixOS flake (home-manager as a NixOS module) plus chezmoi, building a single host. The desktop story: Hyprland is the only session; a self-written Quickshell shell provides the desktop UI; KDE software runs app-level without a Plasma desktop.

## Language

### Host & sessions

**Diogenes**:
The single NixOS host this flake builds (`sudo nixos-rebuild switch --flake .#diogenes`).
_Avoid_: "the laptop", hostname drift elsewhere

**Hyprland session**:
The only graphical login session on Diogenes, launched by SDDM under uwsm.
_Avoid_: dual-boot talk about other sessions

**Plasma session**:
The removed full-KWin desktop session. Exists only in boot-generation history.
_Avoid_: reinstating it as a fallback — rollback generations are the fallback

### Desktop shell

**The Shell**:
The self-written Quickshell QML tree providing bar, launcher menu, notifications, volume/brightness OSDs, and the polkit agent — one long-lived process per Hyprland session.
_Avoid_: calling any single component "the shell"; they are plugins/widgets of The Shell

**Omarchy**:
Reference implementation only. Its quattro-shell QML is read for how to build Shell pieces; nothing is vendored wholesale and no omarchy runtime (scripts, `OMARCHY_PATH`) is used.
_Avoid_: depending on omarchy binaries or paths

**Bar parity**:
DISCHARGED. Was the constraint that The Shell's first release reproduce the previous waybar layout, modules, keybinds, and Nord palette exactly. That release shipped and waybar is gone, so the term is history, not a live rule — it survives here only to explain why early bar values look arbitrary.
_Avoid_: citing it to block a change; there is no waybar left to be at parity with

### Retained daemons

**Lock stack**:
hyprlock + hypridle. Deliberately NOT part of The Shell — the fingerprint unlock setup is proven and the shell-lock PAM path is unverified on NixOS.
_Avoid_: swapping in a shell-provided lock screen

**Walker stack**:
elephant (data provider service) + walker (frontend), demoted to clipboard history only ($mod SHIFT V). App launching belongs to The Shell's menu.
_Avoid_: using walker as the app launcher

**KDE infra**:
kwallet (+ kwallet-pam at SDDM), xdg-desktop-portal-kde (Secret portal, Dolphin file chooser), kdeconnect, polkit framework, kate — run standalone under Hyprland without any Plasma session daemon.
_Avoid_: assuming plasma-workspace provides agents/daemons; it isn't installed

**DWT**:
Disable-while-typing touchpad toggle; exposed as a Bar widget and $mod T bind.
_Avoid_: spelling it out in UI copy
