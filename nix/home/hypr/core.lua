-- Hyprland configuration: monitors, environment, look and feel, input.
--
-- Deployed by nix/home/hyprland.nix as an out-of-store symlink, so edits here
-- go live without a rebuild (Hyprland reloads on file change; `hyprctl reload`
-- forces it). The trade is the same one the quickshell QML makes: this file is
-- in no Nix generation, so a rollback will not roll it back, and git is its
-- only history.
--
-- Store paths that must be pinned live in the HM-generated `paths` module.
-- Everything referenced here by bare name is resolved from the session PATH.

------------------
---- MONITORS ----
------------------

-- Framework 13 eDP-1 panel (2256x1504, ~200 DPI). Hyprland quantizes scale to
-- multiples of 1/120 and requires both dimensions to divide cleanly. 1.5x
-- fails because 1504/1.5 = 1002.67 (not integer). The closest valid scale is
-- 1.5667 (188/120) -> effective 1440x960.
--
-- `output = ""` is the catch-all entry, matching the leading comma of the old
-- hyprlang `monitor = ,preferred,auto,1.5667`.
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1.5667,
})

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- Compositor-specific env vars. Kept here rather than in home.sessionVariables
-- so they stay scoped to a Hyprland session (the original reason was to avoid
-- leaking into Plasma; Plasma is gone, but scoping them to the compositor is
-- still the right shape -- they are wrong for a TTY or a non-Hyprland login).
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("GDK_BACKEND", "wayland,x11")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XCURSOR_THEME", "phinger-cursors-dark")
hl.env("XCURSOR_SIZE", "24")

-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
    general = {
        gaps_in     = 5,
        gaps_out    = 10,
        border_size = 2,
    },

    decoration = {
        rounding = 8,
    },

    misc = {
        -- `xdg-open <url>` does not start a browser -- it hands the URL to the
        -- already-running Firefox, which then asks the compositor to raise
        -- itself via xdg-activation. Hyprland ignores those requests by
        -- default, so the tab opened silently on whatever workspace Firefox
        -- was parked on and you had to go find it.
        --
        -- This is global, not browser-scoped: any app that requests activation
        -- (Slack, Zoom, a file dialog) can now pull focus. That is the trade --
        -- a window rule would scope it to Firefox but only fires for NEW
        -- windows, which is the case xdg-open almost never hits.
        focus_on_activate = true,
    },
})

---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout    = "us",
        follow_mouse = 1,
        -- Remap Caps Lock to Escape (holds-as-escape too -- great for vim).
        -- Note this is a plain string in the Lua API; the old hyprlang config
        -- used a list, which rendered as repeated `kb_options` lines.
        kb_options   = "caps:escape",

        -- natural_scroll on a Framework 13 touchpad only takes effect when
        -- nested under `input.touchpad` -- putting it in the global `input`
        -- block silently no-ops on the touchpad (Hyprland issue #2458).
        --
        -- disable_while_typing ON, which is NOT Hyprland's default (false).
        -- Phantom clicks while typing -- Ghostty is the worst offender -- are
        -- the everyday problem; palm rejection is worth the cost.
        --
        -- It costs something real, which is why this was false until now: the
        -- kernel's i2c-hid palm-rejection can leave the pad unresponsive for
        -- ~1s after every key, and typing into Moonlight's streamed window
        -- with the pad dead is miserable. That case is now the exception you
        -- reach for the toggle for, rather than the case the default serves.
        --
        -- Toggle with $mainMod+T or The Shell's DWT widget. Both are runtime
        -- overrides: a config reload (and every home-manager switch) returns
        -- the pad to DWT-on.
        touchpad = {
            natural_scroll       = true,
            disable_while_typing = true,
            -- 1/2/3-finger physical click = left/right/middle (libinput
            -- default, set explicitly so it survives any future libinput
            -- default flip).
            clickfinger_behavior = true,
        },
    },
})

-- Touchpad gestures: 3-finger horizontal swipe to change workspace.
-- `horizontal` is a direction meaning "any horizontal swipe", and `workspace`
-- automatically steps in the swipe direction -- no `e+1` / `e-1` needed.
hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})

-------------------
---- AUTOSTART ----
-------------------

-- The Shell is started by the HM-managed systemd user service
-- (programs.quickshell.systemd.enable in hyprland.nix) -- do NOT also start it
-- here, or you'll get two instances fighting over the layer-shell bar surface.
--
-- The systemd activation-environment handshake and the
-- hyprland-session.target start are emitted into hyprland.lua by home-manager
-- itself, as their own `hyprland.start` handler. Handlers are additive, so
-- this one only has to carry the wallpaper.
hl.on("hyprland.start", function()
    hl.exec_cmd("swaybg -i ~/.config/hypr/wallpaper.jpg -m fill")
end)
