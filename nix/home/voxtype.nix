{ config, pkgs, lib, ... }:

let
  # Whisper weights, fetched declaratively instead of via `voxtype setup
  # --download`. Upstream's own HM module does exactly this (nix/models.nix in
  # the voxtype flake); the URL and SRI hash are copied from there rather than
  # taking the whole flake as an input just to reach a two-field attrset.
  #
  # base.en is 142MB and English-only — the .en models are both faster and more
  # accurate than the multilingual ones at the same size. Swapping model is a
  # url+hash change here; the ladder is tiny/base/small/medium/large-v3(-turbo).
  whisperModel = pkgs.fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin";
    hash = "sha256-oDd5yG3zMjB19eeWyyzlAp8A7Ihp7uP9+4l6/jbG0AI=";
  };

  # pkgs.voxtype is the CPU (AVX) whisper.cpp build and is on cache.nixos.org.
  # The upstream flake also offers `vulkan`/`rocm` variants that compile
  # whisper.cpp's GGML Vulkan backend, but nothing there is cached — it is a
  # 258-derivation source build, repeated on every input bump — and this
  # machine's GPU is a Phoenix1 iGPU sharing system RAM, so the win would be
  # modest. If dictation latency ever becomes annoying, that is the knob:
  # add the flake input and set this to `voxtype.packages.${system}.vulkan`.
  # Nothing else in this file changes.
  package = pkgs.voxtype;

  voxtype = lib.getExe' package "voxtype";

  # The OSD, reassembled from parts nixpkgs ships separately.
  #
  # nixpkgs builds voxtype with no cargo features, so the two real renderer
  # binaries never get built: `voxtype-osd-gtk4` needs `required-features =
  # ["osd-gtk4"]` and `voxtype-osd-native` needs ["osd-native"] (Cargo.toml).
  # What survives is `voxtype-osd` (the dispatcher) and
  # `voxtype-osd-quickshell` — the two with no required-features. The
  # dispatcher defaults to frontend "gtk4", fails to find that binary, and
  # degrades to quickshell.
  #
  # Which would work, except `voxtype-osd-quickshell` is only a launcher: it
  # locates a directory containing shell.qml and execs `qs -d -p <dir>`. The
  # QML itself lives in the source tree under quickshell/, and nixpkgs'
  # postInstall copies only default.toml, the man page and completions — so
  # the launcher searched its five paths, found nothing, exited 3, and the
  # supervisor gave up after three tries in 5s.
  #
  # Both halves are ours to supply: point the frontend at quickshell (below)
  # and install the QML here. Taken from `package.src` rather than a fresh
  # fetch precisely because that is the same source the binary was built
  # from — the QML talks to the daemon over a versioned state file and audio
  # socket, so a mismatched tree is the one real hazard, and this makes a
  # mismatch impossible by construction.
  osdQml = "${package.src}/quickshell";


  # Hyprland tracks *physical* key state, so text typed by voxtype while CTRL
  # is still held would be read as CTRL+<letter> and fire compositor binds
  # instead of landing in the focused input. Upstream's fix (`voxtype setup
  # compositor hyprland`) is a submap that swallows the modifiers for the
  # duration of the typing, driven by the output hooks below. That command
  # writes into ~/.config/hypr/conf.d imperatively; this is the same content,
  # declared.
  #
  # Do NOT bind Escape in voxtype_suppress — it makes wtype drop the first
  # character (Hyprland issue #3165). F12 is the escape hatch instead, for the
  # case where voxtype dies mid-type and never sends us back to `reset`.
  submaps = ''
    # Active during recording and transcription; F12 cancels.
    submap = voxtype_recording
    bind = , F12, exec, ${voxtype} record cancel
    bind = , F12, submap, reset
    # The release bind MUST be repeated here. pre_recording_command switches
    # into this submap the instant recording starts, and a submap only sees
    # its own binds — so the `bindr` in the default keymap goes deaf and the
    # key release is simply lost. Recording then runs to the 60s cap and
    # transcribes a minute of silence. (It intermittently appeared to work
    # before this line existed: releasing inside the ~20ms before the hook
    # landed still hit the default-keymap bind. A race, not a fix.)
    bindr = CTRL, SPACE, exec, ${voxtype} record stop
    submap = reset

    # Active during text output; swallows modifiers so transcribed text cannot
    # be reinterpreted as keybinds.
    submap = voxtype_suppress
    bind = , SUPER_L, exec, true
    bind = , SUPER_R, exec, true
    bind = , Control_L, exec, true
    bind = , Control_R, exec, true
    bind = , Alt_L, exec, true
    bind = , Alt_R, exec, true
    bind = , Shift_L, exec, true
    bind = , Shift_R, exec, true
    bind = , F12, submap, reset
    submap = reset
  '';
in
{
  home.packages = [ package ];

  # Search path #3 for the launcher ($XDG_DATA_HOME/voxtype/quickshell).
  xdg.dataFile."voxtype/quickshell".source = osdQml;

  xdg.configFile."voxtype/config.toml".source =
    (pkgs.formats.toml { }).generate "voxtype-config.toml" {
      engine = "whisper";
      # $XDG_RUNTIME_DIR/voxtype/state, written on every transition between
      # idle/recording/transcribing. `voxtype record toggle` and `voxtype
      # status` both need it, and it is the hook a bar widget would read.
      state_file = "auto";

      # Compositor keybindings, not voxtype's own evdev grab — the evdev path
      # wants `input` group membership and would fight Hyprland for the key.
      hotkey.enabled = false;

      audio = {
        device = "default";
        sample_rate = 16000;
        max_duration_secs = 60;
      };

      whisper = {
        # Absolute store path, so this never depends on anything having been
        # downloaded into ~/.local/share/voxtype/models.
        model = "${whisperModel}";
        language = "en";
        translate = false;
        # Keep the model resident. It is 142MB of RAM in exchange for not
        # paying the load on every single dictation, which is the whole
        # latency budget for a short clip.
        on_demand_loading = false;
      };

      output = {
        mode = "type";
        fallback_to_clipboard = true;
        # The three hooks that drive the submaps declared above.
        pre_recording_command = "hyprctl dispatch submap voxtype_recording";
        pre_output_command = "hyprctl dispatch submap voxtype_suppress";
        post_output_command = "hyprctl dispatch submap reset";
        notification = {
          # Belt and braces alongside the OSD: if the OSD ever fails to come
          # up again, silent notifications would leave no indication that the
          # mic is live — which is how a stuck recording runs to the 60s cap
          # unnoticed. Start/stop stay off (too chatty for every dictation);
          # the completion notice is upstream's own default.
          on_recording_start = false;
          on_recording_stop = false;
          on_transcription = true;
        };
      };

      osd = {
        # Not the "gtk4" default: that binary does not exist in the nixpkgs
        # build. See the osdQml comment above.
        frontend = "quickshell";
        style = "default";
        layout = "compact";
      };
    };

  # PartOf, not just WantedBy: without it the unit is started by
  # graphical-session.target but never stopped by it — the logout leak ADR 0003
  # exists to close. Same triple as every other Hyprland-scoped service here.
  systemd.user.services.voxtype = {
    Unit = {
      Description = "Voxtype push-to-talk voice-to-text daemon";
      Documentation = "https://voxtype.io";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" "pipewire.service" "pipewire-pulse.service" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${voxtype} daemon";
      Restart = "on-failure";
      RestartSec = 5;
      # The OSD chain resolves two binaries by bare name off PATH, and a
      # systemd user unit does not reliably inherit the login shell's:
      # `voxtype-osd-quickshell` execs `qs`, and the QML's AudioBridge spawns
      # `voxtype-audio-bridge` (its bridgeBinary property is the bare name).
      # quickshell comes from the same pinned package the session runs, so
      # the OSD cannot end up on a different Qt build than the bar.
      Environment = [
        "PATH=${lib.makeBinPath [ package config.programs.quickshell.package ]}"
      ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  wayland.windowManager.hyprland = {
    settings = {
      # Push-to-talk: hold CTRL+SPACE, speak, release. `bind` fires on press,
      # `bindr` on release — the pairing is what makes hold-to-talk possible
      # without voxtype grabbing the keyboard itself.
      bind = [ "CTRL, SPACE, exec, ${voxtype} record start" ];
      bindr = [ "CTRL, SPACE, exec, ${voxtype} record stop" ];
    };
    # Submaps must come after the main keybind block: everything following a
    # `submap = <name>` line belongs to that submap until the next
    # `submap = reset`. extraConfig is appended last, which is what makes this
    # safe — defining these inline in `settings` would capture whatever binds
    # happened to be serialised after them.
    extraConfig = submaps;
  };
}
