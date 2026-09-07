{ config, pkgs, lib, inputs, ... }:

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

  # The `onnx` package, not pkgs.voxtype: nixpkgs builds with no cargo
  # features, so Parakeet is simply absent there — `--model
  # parakeet-tdt-0.6b-v3` logs "Unknown model", silently loads whisper
  # base.en, and looks like it worked. This one reports
  # `Features: parakeet, moonshine, sensevoice, paraformer, dolphin,
  # omnilingual, cohere`, and whisper stays available because whisper-rs is an
  # unconditional dependency rather than a feature — one binary, both engines,
  # which is what let the two be compared on identical everything else.
  #
  # ~280 derivations to build, all small Rust crates; onnxruntime comes
  # prebuilt from cache.nixos.org because upstream links it dynamically
  # (parakeet-load-dynamic) instead of vendoring it.
  #
  # No GPU variant. Whisper could use `vulkan` (GGML has a vendor-neutral
  # Vulkan backend), but ONNX Runtime has no Vulkan execution provider at all,
  # so Parakeet's only GPU path is ROCm/MIGraphX — and this machine's iGPU is
  # gfx1103 (Phoenix1, confirmed via /sys/class/kfd), which ROCm does not
  # officially support. Parakeet here is CPU-only by construction, and at
  # 0.21s per clip that is entirely fine.
  package = inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system}.onnx;

  # Parakeet weights: the transcription engine as of the 2026-09 bake-off.
  #
  # Assembled here rather than downloaded because `voxtype setup --download`
  # cannot fetch them at all — models.voxtype.io sits behind a Cloudflare bot
  # challenge that answers curl with a 403 interstitial. (That is the whole
  # story behind the half-empty models directory this replaced.)
  #
  # Not upstream's own weights either. voxtype's catalog points at
  # istupakov/parakeet-tdt-0.6b-v3-onnx, whose int8 build is measurably broken:
  # scored on the voxtype-eval corpus it gives 3.79% CER against fp32's 2.08%,
  # with meaning-changing substitutions ("grill"->"girl", "auth"->"off") and
  # one clip transcribed as nothing at all. Upstream FLEURS numbers agree —
  # 19.40% WER vs 12.85% for fp32.
  #
  # These are Olicorne's requantisation of the same NVIDIA model, which fixes
  # exactly that. Measured on the 47-clip corpus:
  #
  #   engine                        WER    CER*   resident
  #   whisper base.en (previous)   9.6%   3.12%     250 MB
  #   parakeet fp32                9.4%   2.08%    2209 MB
  #   parakeet nbits8 (this)       9.8%   2.08%    1504 MB
  #
  #   * CER over space-stripped text: word-boundary splits ("tool tips" for
  #     "tooltips") are free, since the consumer of this dictation is an LLM
  #     prompt that recovers them. Plain WER penalises them and understates
  #     Parakeet's lead.
  #
  # 46 of 47 clips come out byte-identical to the full fp32 model, for a third
  # less memory. The cost over whisper is ~1.25GB resident, bought for a 6x
  # latency cut (1.33s -> 0.21s) and a third fewer errors.
  #
  # CAVEAT, and the reason every file is pinned by hash: this is a one-person
  # repo (143 downloads/month) with four breaking changes in the fortnight
  # before it was adopted — files withdrawn then restored, the repo renamed,
  # and the contents of `encoder-model.int8.onnx` swapped underneath the name.
  # Pinning means a change upstream is a loud hash mismatch here, never a
  # silent model swap. Expect to re-pin; `nix build` will tell you when.
  parakeetModel =
    let
      repo = "https://huggingface.co/Olicorne/parakeet-tdt-0.6b-v3-optimized-onnx/resolve/main";
      get = path: hash: pkgs.fetchurl { url = "${repo}/${path}"; inherit hash; };

      # The canonical name upstream's loaders auto-pick, currently a
      # MatMulNBits 8-bit encoder. Deliberately taking the canonical slot
      # rather than the pinned-recipe alternatives (`w4a8`, `int8-lite`), so
      # improvements arrive on the next re-pin.
      encoder = get "int8/encoder-model.int8.onnx"
        "sha256-UMHpuFiMVVDe8b+k7P4fP7PSjgbZrDrlUScb+lkyAh0=";

      # fp32 decoder, not the int8 one beside the encoder: no decoder ships at
      # the MatMulNBits widths, and this is the pairing upstream benchmarks.
      # Worth the 72MB — it took fidelity from 43/47 to 46/47 exact matches
      # against full fp32 for +29MB resident, and fixed "sub agent"/"subagent".
      # Graph and weights are separate files that must land in one directory.
      decoder = get "fp32/decoder_joint-model.onnx"
        "sha256-D1HOFebHGVAeHobz/1Inwvev8FcJuGCnNXJ8FUfbxQY=";
      decoderData = get "fp32/decoder_joint-model.onnx.data"
        "sha256-ZGWxpbMptR8kPeWFAoq+M36NOhlMCZLA3mxq7MFFb+8=";

      vocab = get "vocab.txt"
        "sha256-1YVEZ56kvGrFY9H1Ret9R0vWz6Rn8KbiwdwcfTfjw10=";
      modelConfig = get "config.json"
        "sha256-ZmkDx2uXmMrywhCv1PbNYLCKjb+YAOyNejvA0hSKxGY=";
      preprocessor = get "nemo128.onnx"
        "sha256-qf3hSG6/zAjzKNda1GEMZ4Nf6ljHO6V+Mgmm9s8Bnp8=";
    in
    # A directory, not a file: unlike whisper's single .bin, the Parakeet
    # loader wants encoder, decoder, vocabulary, config and mel preprocessor
    # side by side, and resolves them by exact filename.
    pkgs.runCommand "parakeet-tdt-0.6b-v3-nbits8" { } ''
      mkdir -p $out
      cp ${encoder}      $out/encoder-model.int8.onnx
      cp ${decoder}      $out/decoder_joint-model.onnx
      cp ${decoderData}  $out/decoder_joint-model.onnx.data
      cp ${vocab}        $out/vocab.txt
      cp ${modelConfig}  $out/config.json
      cp ${preprocessor} $out/nemo128.onnx
    '';

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
  # and install the QML here. Taken from the flake input rather than a fresh
  # fetch precisely because that is the same source the binary was built
  # from — the QML talks to the daemon over a versioned state file and audio
  # socket, so a mismatched tree is the one real hazard, and this makes a
  # mismatch impossible by construction.
  #
  # `inputs.voxtype`, not `package.src`: the packages the flake exposes are
  # symlinkJoin wrappers (they add ORT_DYLIB_PATH and the runtime PATH), and a
  # symlinkJoin inherits only `meta` from what it wraps, so `package.src` does
  # not exist. The input itself is the v1.0.1 tree the build used.
  osdQml = "${inputs.voxtype}/quickshell";

  # Transcription-quality harness. Built to tune `whisper.initial_prompt`; the
  # answer it produced was "don't". Across a 47-clip corpus the best prompt
  # bought 0.4 points of WER for 22% more decode time, and seven terms
  # ("Copilot", "symlink", "waybar", ...) were missed by every variant
  # including the unprompted control — a substitution problem a decoder hint
  # cannot fix. `initial_prompt` is therefore still unset, deliberately.
  #
  # Its second use is the one that paid: results are namespaced by engine, so
  # `--engine`/`--bin` can score a different binary against the same corpus.
  # That is how the Parakeet switch above was decided rather than guessed.
  #
  # It drives the same `voxtype` binary this file installs, via
  # `voxtype --initial-prompt <P> transcribe <clip>` — a global flag, so every
  # other setting comes from the generated config.toml below. Model, threads
  # and context_window_optimization are therefore identical to what the daemon
  # uses, by construction rather than by remembering to keep two files in sync.
  #
  # Corpus and results live in ~/.local/share/voxtype-eval, deliberately outside
  # the repo: recordings of my own voice, plus prompt text I want to edit
  # without a rebuild between each attempt. Only a *winning* prompt comes back
  # here, as initial_prompt in the whisper block.
  voxtype-eval = pkgs.writeShellApplication {
    name = "voxtype-eval";
    runtimeInputs = [
      pkgs.python3
      package
      # pw-record, for capturing the corpus at whisper's native 16kHz mono.
      pkgs.pipewire
    ];
    text = ''
      exec python3 ${./scripts/voxtype-eval.py} "$@"
    '';
  };

  # Corpus builder, kept separate from the harness above: different job
  # (sourcing text vs measuring transcription) and a different dependency.
  #
  # `opencode2` is deliberately NOT in runtimeInputs — it is installed outside
  # nix by scripts/update-opencode2.sh, so it has to come from the caller's
  # PATH, which writeShellApplication leaves intact.
  #
  # Writes a REVIEW file to stdout, never straight into the corpus: the prompts
  # it reads were typed, and some were themselves dictated and carry Voxtype's
  # own mistranscriptions. Both have to be corrected by hand before they can
  # serve as ground truth.
  voxtype-eval-corpus = pkgs.writeShellApplication {
    name = "voxtype-eval-corpus";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec python3 ${./scripts/voxtype_corpus.py} "$@"
    '';
  };


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
  hyprlandLua = ''
    -- Push-to-talk: hold the Framework media key, speak, release. The press
    -- bind starts, the `release = true` bind stops — the pairing is what makes
    -- hold-to-talk possible without voxtype grabbing the keyboard itself.
    --
    -- XF86AudioMedia, not the obvious CTRL+SPACE, because a lone key has no
    -- modmask. Hyprland matches modmask exactly on release, so every chord has
    -- a release-order trap: with CTRL+SPACE, lifting CTRL before SPACE matched
    -- no bind, the stop was never sent, and recording ran to the 60s cap. A
    -- single key cannot express that bug. It also stops voxtype eating the
    -- spacebar mid-recording, and frees CTRL+SPACE for Emacs set-mark and IME
    -- switching.
    --
    -- This is the Framework's dedicated media key (confirmed via wev; the only
    -- other free lone key was XF86RFKill, which is wired to the hardware radio
    -- kill and would be a hostile thing to repurpose).
    hl.bind("XF86AudioMedia", hl.dsp.exec_cmd("${voxtype} record start"))
    hl.bind("XF86AudioMedia", hl.dsp.exec_cmd("${voxtype} record stop"), { release = true })

    -- Active during recording and transcription; F12 cancels.
    --
    -- Under hyprlang these submaps had to be appended after every other bind,
    -- because `submap = <name>` opened a block that swallowed everything until
    -- `submap = reset`. `hl.define_submap` takes a function instead, so the
    -- binds are lexically scoped and the ordering hazard is gone.
    hl.define_submap("voxtype_recording", function()
      -- One key, two dispatchers, so it must be a function: cancel the
      -- recording AND leave the submap.
      hl.bind("F12", function()
        hl.dispatch(hl.dsp.exec_cmd("${voxtype} record cancel"))
        hl.dispatch(hl.dsp.submap("reset"))
      end)

      -- The release bind MUST be repeated here. pre_recording_command switches
      -- into this submap the instant recording starts, and a submap only sees
      -- its own binds — so the release bind in the default keymap goes deaf and
      -- the key release is simply lost. Recording then runs to the 60s cap and
      -- transcribes a minute of silence. (It intermittently appeared to work
      -- before this line existed: releasing inside the ~20ms before the hook
      -- landed still hit the default-keymap bind. A race, not a fix.)
      --
      -- One line suffices now that the trigger is a lone key: there is no
      -- modmask to mismatch, so no second release-order variant is needed.
      hl.bind("XF86AudioMedia", hl.dsp.exec_cmd("${voxtype} record stop"), { release = true })
    end)

    -- Active during text output; swallows modifiers so transcribed text cannot
    -- be reinterpreted as keybinds.
    hl.define_submap("voxtype_suppress", function()
      for _, key in ipairs({
        "SUPER_L", "SUPER_R",
        "Control_L", "Control_R",
        "Alt_L", "Alt_R",
        "Shift_L", "Shift_R",
      }) do
        hl.bind(key, hl.dsp.exec_cmd("true"))
      end

      hl.bind("F12", hl.dsp.submap("reset"))
    end)
  '';
in
{
  # The Nerd Font is here rather than in common.nix because the OSD is its
  # only consumer: upstream's OsdSurface.qml hardcodes
  # `font.family: "JetBrainsMono Nerd Font"` for the state glyphs, and nothing
  # else in this configuration uses icon glyphs at all — the quickshell bar
  # deliberately asks for plain "monospace". Without it fontconfig fell back to
  # DejaVu Sans Mono, which has no coverage for U+F036C/U+F051F, so the OSD
  # rendered a tofu box where the mic and hourglass should be.
  home.packages = [
    package
    pkgs.nerd-fonts.jetbrains-mono
    voxtype-eval
    voxtype-eval-corpus
  ];

  # Required for the above to be visible to fontconfig: home-manager only
  # builds the font cache from home.packages when this is on, and it defaults
  # off. Installing the font without it leaves the tofu box exactly as it was.
  fonts.fontconfig.enable = true;

  # Search path #3 for the launcher ($XDG_DATA_HOME/voxtype/quickshell).
  xdg.dataFile."voxtype/quickshell".source = osdQml;

  xdg.configFile."voxtype/config.toml".source =
    (pkgs.formats.toml { }).generate "voxtype-config.toml" {
      engine = "parakeet";
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

      parakeet = {
        # Absolute store path to the assembled directory above.
        model = "${parakeetModel}";
        # TDT, not CTC. TDT emits cased, punctuated text; CTC is char-level and
        # would need a separate punctuation pass to be usable as dictation.
        # Auto-detected from the directory, but naming it makes a silently
        # wrong detection impossible.
        model_type = "tdt";
        # Keep it resident. This is the expensive knob now: ~1.5GB held for the
        # session. On-demand loading is not an escape hatch — Parakeet takes
        # 3.0s to load versus whisper's 0.12s, so paying it per dictation would
        # be far worse than the 1.33s whisper transcription this replaced.
        on_demand_loading = false;
      };

      # Whisper stays configured though `engine` above selects Parakeet: the
      # binary supports both, `--engine whisper` is a one-flag fallback if a
      # weights re-pin ever goes bad, and voxtype-eval needs a working whisper
      # config to keep scoring the two against each other. 142MB in the store.
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

        # Upstream defaults to `num_cpus::get().min(4)` (transcribe/whisper.rs)
        # — 4 of this machine's 16 cores, which is what the 391% CPU during
        # transcription was. Not 16: whisper.cpp's encoder scales poorly past
        # ~8 threads on a memory-bandwidth-bound iGPU-sharing part, and
        # leaving headroom keeps the desktop responsive mid-dictation.
        threads = 8;

        # Whisper pads every clip to a full 30s mel window, so a 2s dictation
        # cost the same ~8s encoder pass as a 30s one — a fixed floor that
        # dominated short clips (measured: 1.8s audio -> 8.57s, 36s -> 17.3s;
        # extrapolating to zero-length audio still cost ~8s). This caps
        # audio_ctx to fit the actual clip (384 for anything under 5s).
        #
        # Upstream ships it off because large-v3/turbo can fall into
        # repetition loops with a truncated context. That risk is model
        # specific and does not apply to base.en above — but it is the first
        # thing to suspect if transcripts ever start stuttering, and the
        # reason this must be revisited when changing `model`.
        #
        # Inert while engine = "parakeet": this works around whisper padding
        # every clip to a 30s mel window, which is an architectural quirk
        # Parakeet does not have. It matters again only via --engine whisper.
        context_window_optimization = true;
      };

      output = {
        mode = "type";
        fallback_to_clipboard = true;
        # The three hooks that drive the submaps declared above.
        pre_recording_command = "hyprctl dispatch submap voxtype_recording";
        pre_output_command = "hyprctl dispatch submap voxtype_suppress";
        post_output_command = "hyprctl dispatch submap reset";
        notification = {
          # All off. The completion notice (upstream's default) was kept as
          # belt-and-braces while the OSD was unreliable — the OSD is the
          # better signal now that it works, and a toast on every dictation
          # is pure noise once transcription lands in ~1s.
          on_recording_start = false;
          on_recording_stop = false;
          on_transcription = false;
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
      # The daemon reads config.toml once at startup and never re-reads it, so
      # without this a config-only change lands on disk and has no effect until
      # something else happens to restart the unit. That is not hypothetical:
      # `threads` and `context_window_optimization` were written correctly by a
      # switch and then appeared to do nothing, because the daemon was still
      # the process started before them. Naming the store path here makes
      # home-manager restart the unit whenever the generated file changes.
      #
      # The OSD tree is listed for the same reason: the daemon spawns
      # quickshell as a child, so patched QML (and any font it resolves at
      # startup) only takes effect on a daemon restart. Listing only the
      # config file meant a switch that changed just the QML left the old
      # Qt process running and the change invisible.
      X-Restart-Triggers = [
        "${config.xdg.configFile."voxtype/config.toml".source}"
        "${osdQml}"
      ];
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
      #
      # hyprland is here for `hyprctl` and bash for `sh`: run_hook (upstream
      # src/output/mod.rs) execs `sh -c "<command>"`, resolving BOTH names off
      # this PATH. With either missing every hook fails with a bare ENOENT
      # that names neither binary, and the submaps declared in this file are
      # silently dead code.
      Environment = [
        "PATH=${lib.makeBinPath [
          package
          config.programs.quickshell.package
          config.wayland.windowManager.hyprland.package
          pkgs.bash
        ]}"
      ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # Hyprland integration, as a Lua module. See nix/home/hyprland.nix for why
  # the session config is Lua rather than hyprlang.
  #
  # Generated into the store rather than symlinked to the working tree like
  # core.lua and binds.lua, because every command in it is a pinned store path
  # — there is nothing here worth hot-reloading by hand.
  wayland.windowManager.hyprland.extraLuaFiles.voxtype = hyprlandLua;
}
