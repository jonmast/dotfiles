# Plasma session removed; KDE software stays app-level

## Status

accepted (2026-08-22)

## Decision

`services.desktopManager.plasma6.enable` and `services.xserver.enable` come out of diogenes.nix. SDDM (wayland) remains the display manager with Hyprland as its only session entry. KDE software is retained standalone: kwallet + kwallet-pam (unlocks at SDDM login — that PAM wiring is session-independent), xdg-desktop-portal-kde (Secret portal, Dolphin file chooser), kdeconnect, kate.

## Consequences

- There is no full-Plasma fallback session; `nixos-rebuild --rollback` / boot generations are the safety net.
- Anything plasma-workspace silently provided must now be explicit. Notably: a polkit agent (the Shell provides one — the old Hyprland session had none, GUI auth prompts were already broken there).
- `kdePackages.plasma-workspace` in xdg.portal configPackages needs re-checking once Plasma is gone.
- Known follow-ups from research: disable baloo, fix XDG_MENU_PREFIX at the systemd layer for Dolphin's sycoca.

## Implementation amendments (2026-08-26, issue 02)

The decision stands. Five things the original text got wrong or did not anticipate,
all found by building the post-removal system and diffing it against the live one.

1. **plasma-workspace stays — but for the menu, not for portals.** The
   configPackages re-check is resolved: **keep it**. The old justification (that
   configPackages makes HM scan for `*.portal` files and register the KDE portal's
   interfaces) is simply false — HM's module does only
   `home.packages = packages ++ cfg.configPackages`, i.e. it installs the package.
   The Secret interface is registered by `kwallet.portal` from `kdePackages.kwallet`.
   plasma-workspace is nonetheless load-bearing as the **sole** provider of
   `etc/xdg/menus/plasma-applications.menu` and the 40 `share/desktop-directories/*.directory`
   files it references — exactly what `XDG_MENU_PREFIX=plasma-` resolves to. Its
   Plasma autostart entries are all `OnlyShowIn=KDE`, so nothing Plasma starts.

2. **Removing plasma6 silently changes the SDDM greeter's compositor.** plasma6 set
   `sddm.wayland.compositor = "kwin"` via `mkDefault`; without it the module default
   `weston` applies. Accepted deliberately — retaining kwin purely for the greeter
   would keep most of what this ADR set out to remove. `compositor = "kwin"` restores
   the old behaviour if the greeter misbehaves.

3. **`defaultSession` must be set explicitly.** plasma6 set it to `plasma`; with
   plasma6 gone it becomes `null` and SDDM preselects nothing. Now
   `hyprland-uwsm`.

4. **Dolphin was never actually declared in this repo.** It — along with
   `kbuildsycoca6` (kservice), breeze-icons and qqc2-desktop-style — arrived purely
   as plasma6 `optionalPackages`/`requiredPackages`. "KDE software is retained
   standalone" therefore required *adding* these explicitly, or `$mod+E` would exec a
   missing binary and KDE apps would render with only the bare `hicolor` icon theme.

5. **`services.xserver.xkb` outlives `services.xserver.enable`.** The weston greeter
   generates its keymap from those values, so that block stays even though the X
   server is disabled. Disabling `services.xserver` is what removes the
   `plasmax11.desktop` entry; the built `sddm.conf` now has no `[X11]` section.

## Verification amendment (2026-08-27, issue 02 sign-off)

6. **"That PAM wiring is session-independent" was true but irrelevant — the wiring
   never existed.** The decision text assumed kwallet unlocking at SDDM login kept
   working because it does not depend on Plasma. It does not depend on Plasma; it
   also never ran. `security.pam.services.sddm.kwallet.enable = true` is silently
   discarded, because nixpkgs' SDDM module declares that PAM service with
   `useDefaultRules = false` and a body that is pure delegation
   (`auth substack login`, `session include login`), while every convenience flag —
   `kwallet`, `fprintAuth`, gnome-keyring — is generated inside
   `lib.optionalAttrs cfg.useDefaultRules` in `security/pam.nix`. `grep -rl kwallet
   /etc/pam.d/` matched nothing on the live system, and the wallet was closed
   (`isOpen kdewallet` → `false`) in a fully booted session.

   Pre-existing, not caused by Plasma removal — but removal raised the stakes: with
   no Plasma session, pam_kwallet5 is the only thing that opens the wallet at all,
   so every secret lookup would otherwise raise a password dialog.

   Fixed by moving the setting to `security.pam.services.login.kwallet.enable`,
   which is where SDDM's auth actually resolves. The same mechanism explains the
   long-standing "SDDM demands a fingerprint after the password" annoyance
   (`.scratch/issues/01`), so `login.fprintAuth` was turned off in the same edit:
   SDDM cannot evaluate PAM modules in parallel, and pam_kwallet5 needs the typed
   password in PAM_AUTHTOK, which a fingerprint cannot supply. Fingerprint remains
   on sudo, polkit, and hyprlock's native fprintd backend; it is gone from TTY
   login, which is the accepted cost.

   Watch for: pam_kwallet5 is compiled to exec **`ksecretd`**, not `kwalletd6`
   (both ship in `kdePackages.kwallet`). If wallet unlock regresses after a KDE
   bump, check that binary first.

7. **The PAM half alone does nothing — the session half was also missing.**
   `pam_kwallet5` only creates `$XDG_RUNTIME_DIR/kwallet5.socket` and forks
   `ksecretd --pam-login`, which then blocks, owning no D-Bus name, until
   something pipes the session environment into that socket. That something is
   `pam_kwallet_init`, shipped as the **static** unit
   `plasma-kwallet-pam.service` (`PartOf=graphical-session.target`, no
   `[Install]`) — pulled in by plasma-workspace under Plasma, by nothing after
   this ADR. The autostart `.desktop` is not a fallback: it sets
   `X-systemd-skip=true` so systemd's generator ignores it deliberately.

   This is the general shape of the risk this ADR accepted in consequence #2
   ("anything plasma-workspace silently provided must now be explicit") — the
   surprise is that it extends to *static systemd units* the Plasma session
   pulled in, not just packages and agents. Worth checking for others.

   Declared in `nix/home/hyprland.nix` as a HM unit shadowing the upstream name,
   with the `After=graphical-session.target` upstream omits, since the piped env
   is only useful once uwsm has populated the manager environment.

   Verification trap, recorded because it consumed real time: right after login
   the Secret Service reports the collection `Locked = true` even when the
   wallet is open, because the fdo collection objects are built before
   `pamOpen()` runs and their handle is stale. The first client `Unlock`
   completes instantly with no dialog and flips it. Test the round-trip, never
   the raw property.
