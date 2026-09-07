-- Hyprland keybindings.
--
-- Deployed as an out-of-store symlink (see config.lua's header for the trade).
-- `paths` is the HM-generated module holding store paths that must be pinned
-- rather than resolved from PATH.

local paths = require("paths")

local mainMod = "SUPER"

-- The Shell's IPC entry point. `qs ipc call` reaches the already-running shell
-- over its IPC socket; `-c shell` names the config, matching `activeConfig` in
-- hyprland.nix. Measured at ~35ms round trip.
--
-- If the shell is not running these print an error and do nothing -- which is
-- the honest failure mode, since without the shell there is no launcher to
-- open and no notification history to show.
local function shellIpc(...)
    local args = table.concat({ ... }, " ")
    return hl.dsp.exec_cmd(paths.qs .. " -c shell ipc call " .. args)
end

---------------------
---- APPLICATIONS ----
---------------------

hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd("ghostty"))

-- Unified nixpkgs/NixOS options search (nix/packages/nix-search).
-- Opens nix-search in ghostty; Enter copies the name to clipboard.
hl.bind(mainMod .. " + slash", hl.dsp.exec_cmd("ghostty -e nix-search"))

hl.bind(mainMod .. " + E", hl.dsp.exec_cmd("dolphin"))

-- `walker` is deliberately NOT a fallback for the launcher bind below: two
-- launchers on one bind is how the demotion would quietly undo itself.
-- Clipboard history is the one job walker keeps.
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.exec_cmd("walker -m clipboard"))

-------------------
---- THE SHELL ----
-------------------

hl.bind(mainMod .. " + D", shellIpc("menu", "toggle"))

-- DND on its own keybind rather than sharing one with the history panel,
-- because the two get used at completely different moments -- and because an
-- accidental DND is exactly the state that is hard to notice. The bar grows a
-- DND indicator while it is on.
hl.bind(mainMod .. " + N", shellIpc("notifications", "toggleHistory"))
hl.bind(mainMod .. " + SHIFT + N", shellIpc("notifications", "toggleDnd"))

------------------
---- WINDOWS ----
------------------

hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exit())

-- Move focus / move the active window with the arrow keys.
for key, direction in pairs({
    left  = "left",
    right = "right",
    up    = "up",
    down  = "down",
}) do
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ direction = direction }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ direction = direction }))
end

---------------------
---- WORKSPACES ----
---------------------

for i = 1, 9 do
    hl.bind(mainMod .. " + " .. i, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end

------------------
---- HARDWARE ----
------------------

-- Toggle touchpad disable-while-typing. See the input block in config.lua for
-- why DWT is on by default and when you would want it off.
--
-- Kept as the original shell pipeline rather than the native
-- `hl.get_config`/`hl.config` pair, so the migration to Lua changed no
-- behaviour: `hyprctl keyword` is the same runtime override The Shell's DWT bar
-- widget uses, and hyprctl returns {"int": 0|1} for this option -- no `.bool`
-- field.
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(
    [[hyprctl keyword input:touchpad:disable_while_typing ]] ..
    [[$(if [ "$(hyprctl getoption input:touchpad:disable_while_typing -j | jq -r .int)" = '0' ]; ]] ..
    [[then echo true; else echo false; fi)]]
))

hl.bind("Print", hl.dsp.exec_cmd([[grim -g "$(slurp)" - | wl-copy]]))

-- `locked = true` is the old `bindl` flag: these keep working while the
-- session is locked.
--
-- Pipewire publishes volume and mute as properties, so The Shell watches them
-- directly and the three audio binds need no OSD nudge.
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

-- Brightness pushes its OSD over IPC. A backlight has no property-change event
-- worth watching, so the bind tells the shell to look.
--
-- `&&`, so a failed `brightnessctl` does not raise an OSD claiming a
-- brightness that was never set. The `qs` call is last and its own failure
-- costs only the OSD -- an unfinished OSD must never cost working hardware
-- keys.
hl.bind("XF86MonBrightnessUp",
    hl.dsp.exec_cmd("brightnessctl set 5%+ && " .. paths.qs .. " -c shell ipc call osd brightness"),
    { locked = true })
hl.bind("XF86MonBrightnessDown",
    hl.dsp.exec_cmd("brightnessctl set 5%- && " .. paths.qs .. " -c shell ipc call osd brightness"),
    { locked = true })
