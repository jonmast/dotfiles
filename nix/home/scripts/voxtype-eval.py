#!/usr/bin/env python3
"""Measure what `whisper.initial_prompt` actually buys you.

Voxtype keeps no audio (dictation is buffered in memory, transcribed, typed,
discarded), so there is nothing to evaluate against until you record something.
This builds that corpus once, then replays it through the real binary under
different prompts and scores the results.

The sweep shells out to `voxtype --initial-prompt <P> transcribe <clip>`, which
reads your live ~/.config/voxtype/config.toml. Model, threads and
context_window_optimization are therefore identical to production by
construction -- the prompt is the only thing that varies. That is the whole
reason this drives the CLI instead of calling whisper.cpp directly.

Stdlib only, like ai-quota.py. WER is 30 lines of Levenshtein; pulling in jiwer
would mean a python package set in the closure for one function.

Corpus, prompts and results all live under $VOXTYPE_EVAL_DIR
(default ~/.local/share/voxtype-eval), NOT in the repo -- recordings of your
voice, and prompt text you want to iterate on without a nixos-rebuild between
each edit. Commit a winning prompt into nix/home/voxtype.nix, not the tuning
sessions that found it.

  voxtype-eval init     seed sentences.txt and prompts.txt
  voxtype-eval record   read the sentences aloud, one clip each
  voxtype-eval run      transcribe every clip under every prompt
  voxtype-eval report   scores, per-variant and per-term
  voxtype-eval report --diff   the above, plus a word-level diff per clip
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

EVAL_DIR = Path(
    os.environ.get("VOXTYPE_EVAL_DIR", Path.home() / ".local/share/voxtype-eval")
)
CLIPS = EVAL_DIR / "clips"
RUNS = EVAL_DIR / "runs"
SENTENCES = EVAL_DIR / "sentences.txt"
PROMPTS = EVAL_DIR / "prompts.txt"

# Whisper is trained on 16kHz mono; voxtype records at that rate and
# `transcribe` refuses anything else. Matching it here means the eval clips are
# bit-for-bit the kind of input the daemon feeds the model.
RATE = 16000

# Results are namespaced by engine, because `initial_prompt` is a whisper
# decoder feature that Parakeet has no equivalent for -- the prompt sweep and an
# engine comparison are different experiments and must not share a namespace.
# Anything recorded before namespacing existed is whisper by definition.
DEFAULT_ENGINE = "whisper"


def runs_dir(engine: str) -> Path:
    d = RUNS / engine
    d.mkdir(parents=True, exist_ok=True)
    return d


def migrate_flat_runs() -> None:
    """Move pre-namespacing runs/*.json into runs/whisper/ so they still count."""
    if not RUNS.exists():
        return
    if stray := list(RUNS.glob("*.json")):
        dest = runs_dir(DEFAULT_ENGINE)
        for p in stray:
            p.replace(dest / p.name)
        print(f"note: moved {len(stray)} result file(s) into runs/{DEFAULT_ENGINE}/\n")


# --------------------------------------------------------------------------
# Corpus
# --------------------------------------------------------------------------

# The corpus is NOT shipped here. An earlier version of this file seeded it with
# sentences invented from CONTEXT.md -- grammatical, evenly-paced prose that read
# nothing like real dictation. `voxtype-eval-corpus` builds a better one from
# prompts actually submitted to opencode: same vocabulary, same terse register,
# same typos. What stays here is only the format.
SEED_SENTENCES = """\
# One sentence per line. {Braces} mark terms scored for recall.
# Lines starting with # are ignored. Clips are keyed by line content, so
# editing a line orphans its clip rather than scoring new text against old audio.
#
# This file is empty on purpose. Fill it with:
#
#     voxtype-eval-corpus > sentences.txt
#
# then read it top to bottom before recording -- it arrives as a review queue,
# not a finished corpus.
"""

SEED_PROMPTS = """\
# Prompt variants, swept in order. `## name` starts a variant; everything up to
# the next `##` is its prompt text. An empty body means no prompt at all.
#
# whisper.cpp feeds this as decoder context, capped at n_text_ctx/2 = 224 tokens
# for base.en -- anything past that is silently dropped from the FRONT, so put
# your most important terms last. Long prompts also cost decode time and can
# push the model into repetition loops, which is what `wer` in the report is
# there to catch.

## control

## short
Voxtype, Hyprland, Quickshell, NixOS, systemd.

## termlist
Voxtype, Hyprland, Quickshell, NixOS, nix, flake, home-manager, systemd,
journalctl, submap, wtype, whisper.cpp, kwallet, hyprlock, hypridle, chezmoi,
walker, elephant, opencode, kdeconnect, SDDM, uwsm, polkit, QML, iGPU, Vulkan.

## sentence
Technical discussion about NixOS, Hyprland and Quickshell, covering flakes,
home-manager modules, systemd units and the Voxtype dictation daemon.

## sentence-plus-terms
Technical discussion about NixOS and Hyprland. Terms: Quickshell, flake,
home-manager, systemd, journalctl, submap, wtype, whisper.cpp, kwallet,
hyprlock, hypridle, chezmoi, walker, elephant, opencode, SDDM, uwsm, polkit.

## style
Dictated notes for a NixOS and Hyprland configuration repository. Proper nouns
are capitalised: Voxtype, Quickshell, Hyprland, NixOS, SDDM. Commands are
lowercase: nixos-rebuild, journalctl, systemctl, wtype, chezmoi.
"""


@dataclass
class Sentence:
    """One line of the corpus: what to say, what to score, where the clip is."""

    index: int
    raw: str  # with {braces}
    text: str  # braces stripped -- the reference transcript
    terms: list[str]

    @property
    def key(self) -> str:
        # Content-addressed so edits to a sentence orphan its clip rather than
        # silently scoring new text against old audio -- the one failure mode
        # of this harness that would produce plausible, wrong numbers.
        return hashlib.sha256(self.raw.encode()).hexdigest()[:12]

    @property
    def clip(self) -> Path:
        return CLIPS / f"{self.index:03d}-{self.key}.wav"


def load_sentences() -> list[Sentence]:
    if not SENTENCES.exists():
        die(f"no corpus at {SENTENCES} -- run `voxtype-eval init` first")
    out = []
    for line in SENTENCES.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        terms = re.findall(r"\{([^}]*)\}", line)
        text = re.sub(r"[{}]", "", line)
        out.append(Sentence(len(out) + 1, line, text, terms))
    if not out:
        die(f"{SENTENCES} has no sentences -- fill it with:\n"
            f"    voxtype-eval-corpus > {SENTENCES}")
    return out


def load_prompts() -> list[tuple[str, str]]:
    if not PROMPTS.exists():
        die(f"no prompts at {PROMPTS} -- run `voxtype-eval init` first")
    variants: list[tuple[str, list[str]]] = []
    for line in PROMPTS.read_text().splitlines():
        if line.startswith("##"):
            variants.append((line[2:].strip(), []))
        elif line.startswith("#") or not variants:
            continue
        else:
            variants[-1][1].append(line)
    out = [(n, " ".join(b).split()) for n, b in variants]
    return [(n, " ".join(b)) for n, b in out]


# --------------------------------------------------------------------------
# Scoring
# --------------------------------------------------------------------------

# Standard ASR normalisation: casing and punctuation are the output layer's
# problem, not the model's, and scoring them would drown the signal we care
# about. Cased matching is still reported separately for terms, because
# "hyperland" and "Hyprland" are a real difference to a dictation user.
#
# Hyphens and underscores become spaces rather than being deleted, so "go-keys"
# and "go keys" score identically -- where the model puts a word boundary in a
# compound is a punctuation choice, and charging it two edits (a deletion plus a
# substitution) made cosmetic disagreements look worse than genuinely misheard
# words. Apostrophes are deleted instead, because "don't" is one word however
# it's punctuated and splitting it would invent a token.
_SEPARATOR = re.compile(r"[-_]")
_APOSTROPHE = re.compile(r"['\u2018\u2019\u02bc]")
_PUNCT = re.compile(r"[^\w\s]")


def normalise(text: str) -> list[str]:
    text = text.lower()
    text = _APOSTROPHE.sub("", text)
    text = _SEPARATOR.sub(" ", text)
    text = _PUNCT.sub(" ", text)
    return text.split()


def edit_distance(a: list[str], b: list[str]) -> int:
    """Levenshtein over token lists. O(len(a)*len(b)) time, O(len(b)) space."""
    if not a:
        return len(b)
    prev = list(range(len(b) + 1))
    for i, ta in enumerate(a, 1):
        cur = [i] + [0] * len(b)
        for j, tb in enumerate(b, 1):
            cur[j] = min(
                prev[j] + 1,  # deletion
                cur[j - 1] + 1,  # insertion
                prev[j - 1] + (ta != tb),  # substitution
            )
        prev = cur
    return prev[-1]


def align(a: list[str], b: list[str]) -> list[tuple[str, str, str]]:
    """Levenshtein alignment as (op, ref_token, hyp_token) triples.

    Same recurrence as edit_distance, but keeps the full matrix so the path can
    be walked back. Only used by the diff view, where the corpus is a few
    hundred words -- the quadratic memory is irrelevant at that size.
    """
    n, m = len(a), len(b)
    d = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(1, n + 1):
        d[i][0] = i
    for j in range(1, m + 1):
        d[0][j] = j
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            d[i][j] = min(
                d[i - 1][j] + 1,
                d[i][j - 1] + 1,
                d[i - 1][j - 1] + (a[i - 1] != b[j - 1]),
            )

    ops: list[tuple[str, str, str]] = []
    i, j = n, m
    while i or j:
        if i and j and d[i][j] == d[i - 1][j - 1] + (a[i - 1] != b[j - 1]):
            op = "=" if a[i - 1] == b[j - 1] else "~"
            ops.append((op, a[i - 1], b[j - 1]))
            i, j = i - 1, j - 1
        elif i and d[i][j] == d[i - 1][j] + 1:
            ops.append(("-", a[i - 1], ""))  # deletion: ref word not spoken back
            i -= 1
        else:
            ops.append(("+", "", b[j - 1]))  # insertion: hallucinated word
            j -= 1
    ops.reverse()
    return ops


# Colour only when a human is watching; piping the report into a file or a
# pager-less diff shouldn't get escape codes baked in.
_COLOUR = sys.stdout.isatty() and os.environ.get("NO_COLOR") is None


def _c(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if _COLOUR else text


def render_diff(ops: list[tuple[str, str, str]]) -> tuple[str, str]:
    """Two padded, column-aligned lines: reference above, hypothesis below."""
    ref_out, hyp_out = [], []
    for op, r, h in ops:
        if op == "=":
            ref_out.append(r)
            hyp_out.append(h)
            continue
        w = max(len(r), len(h), 1)
        ref_out.append(_c("31", (r or "·").ljust(w)))
        hyp_out.append(_c("32", (h or "·").ljust(w)))
    return " ".join(ref_out), " ".join(hyp_out)


def contains(haystack: list[str], needle: list[str]) -> bool:
    if not needle:
        return True
    return any(
        haystack[i : i + len(needle)] == needle
        for i in range(len(haystack) - len(needle) + 1)
    )


def misheard_as(term: str, ref: str, hyp: str) -> str:
    """What the model produced where `term` should have been.

    Aligns the reference against the hypothesis, finds the span the term
    occupies in the reference, and returns whatever landed opposite it. This is
    the string you'd put on the left of a substitution rule.
    """
    ref_t, hyp_t, term_t = normalise(ref), normalise(hyp), normalise(term)
    start = next(
        (
            i
            for i in range(len(ref_t) - len(term_t) + 1)
            if ref_t[i : i + len(term_t)] == term_t
        ),
        None,
    )
    if start is None or not term_t:
        return hyp
    end = start + len(term_t)

    heard, ref_i = [], 0
    for op, r, h in align(ref_t, hyp_t):
        # Insertions consume no reference token, but belong to the span if we
        # are inside it -- that is how "symlink" becomes "sim link".
        if op == "+":
            if start <= ref_i < end:
                heard.append(h)
            continue
        if start <= ref_i < end and h:
            heard.append(h)
        ref_i += 1
    return " ".join(heard) or "(nothing)"


@dataclass
class Score:
    wer: float
    errors: int
    ref_words: int
    term_hits: int
    term_total: int
    cased_hits: int
    misses: list[tuple[str, str, str]]  # (term, reference, hypothesis)


def score(sentences: list[Sentence], hyps: dict[str, str]) -> Score:
    errors = ref_words = hits = total = cased = 0
    misses: list[tuple[str, str, str]] = []
    for s in sentences:
        hyp = hyps.get(s.key)
        if hyp is None:
            continue
        ref_t, hyp_t = normalise(s.text), normalise(hyp)
        errors += edit_distance(ref_t, hyp_t)
        ref_words += len(ref_t)
        for term in s.terms:
            total += 1
            if contains(hyp_t, normalise(term)):
                hits += 1
                # Cased credit only where the reference itself is cased;
                # lowercase terms can't fail this check and shouldn't inflate it.
                if term in hyp or term == term.lower():
                    cased += 1
            else:
                misses.append((term, s.text, hyp))
    return Score(
        wer=errors / ref_words if ref_words else 0.0,
        errors=errors,
        ref_words=ref_words,
        term_hits=hits,
        term_total=total,
        cased_hits=cased,
        misses=misses,
    )


# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------


def cmd_init(args: argparse.Namespace) -> None:
    CLIPS.mkdir(parents=True, exist_ok=True)
    RUNS.mkdir(parents=True, exist_ok=True)
    for path, seed in ((SENTENCES, SEED_SENTENCES), (PROMPTS, SEED_PROMPTS)):
        if path.exists() and not args.force:
            print(f"keeping existing {path}")
        else:
            path.write_text(seed)
            print(f"wrote {path}")
    print(f"\nEdit those, then: voxtype-eval record")


def record_one(dest: Path) -> bool:
    """Record until Enter. Returns False if the user wants to bail."""
    tmp = dest.with_suffix(".part.wav")
    proc = subprocess.Popen(
        ["pw-record", "--rate", str(RATE), "--channels", "1", "--format", "s16",
         str(tmp)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        input()
    except (EOFError, KeyboardInterrupt):
        proc.send_signal(signal.SIGINT)
        proc.wait()
        tmp.unlink(missing_ok=True)
        return False
    # SIGINT, not kill: pw-record finalises the WAV header on interrupt, and a
    # truncated header is a file `transcribe` rejects outright.
    proc.send_signal(signal.SIGINT)
    proc.wait()
    if not tmp.exists() or tmp.stat().st_size < 1024:
        tmp.unlink(missing_ok=True)
        print("  nothing captured -- is the mic live?")
        return True
    tmp.replace(dest)
    return True


def parse_indices(specs: list[str], count: int) -> set[int]:
    """Expand "16", "16-20", "16,20" into clip indices."""
    out: set[int] = set()
    for part in " ".join(specs).replace(",", " ").split():
        if m := re.fullmatch(r"(\d+)-(\d+)", part):
            lo, hi = sorted((int(m[1]), int(m[2])))
            out.update(range(lo, hi + 1))
        elif part.isdigit():
            out.add(int(part))
        else:
            die(f"bad clip selector {part!r} -- use 16, 16-20 or 16,20")
    if bad := sorted(i for i in out if not 1 <= i <= count):
        die(f"no such clip: {', '.join(map(str, bad))} (corpus has 1-{count})")
    return out


def cmd_record(args: argparse.Namespace) -> None:
    if not shutil.which("pw-record"):
        die("pw-record not on PATH (pipewire)")
    CLIPS.mkdir(parents=True, exist_ok=True)
    sentences = load_sentences()
    if args.only:
        # Explicit selection overrides "skip what exists" -- the whole point is
        # replacing a clip you misspoke, which by definition already exists.
        want = parse_indices(args.only, len(sentences))
        todo = [s for s in sentences if s.index in want]
    else:
        todo = [s for s in sentences if args.redo or not s.clip.exists()]
    if not todo:
        print(f"all {len(sentences)} clips already recorded -- `--redo` to start over")
        return

    print(f"{len(todo)} to record. Enter starts, Enter stops. Ctrl-C to stop early.")
    print("Say it the way you would dictate it: normal pace, normal room.\n")
    for n, s in enumerate(todo, 1):
        while True:
            print(f"[{n}/{len(todo)}] #{s.index} {s.text}")
            try:
                input("      ready> ")
            except (EOFError, KeyboardInterrupt):
                print("\nstopped -- progress kept")
                return
            print("      RECORDING (Enter to stop)", end="", flush=True)
            if not record_one(s.clip):
                print("\nstopped -- progress kept")
                return
            if not s.clip.exists():
                continue
            dur = wav_duration(s.clip)
            print(f"      saved {dur:.1f}s")
            if args.confirm:
                if input("      [Enter] keep, r retry> ").strip().lower() == "r":
                    continue
            break
        print()
    print("done -- now: voxtype-eval run")


def wav_duration(path: Path) -> float:
    import wave

    with wave.open(str(path)) as w:
        return w.getnframes() / w.getframerate()


TRANSCRIPT_LINE = re.compile(r'Transcription completed in ([\d.]+)s: "(.*)"')


def transcribe(
    voxtype: str, clip: Path, prompt: str, model: str | None = None
) -> tuple[str, float]:
    """One clip, one prompt. Returns (text, model seconds)."""
    cmd = [voxtype]
    if model:
        cmd += ["--model", model]
    if prompt:
        cmd += ["--initial-prompt", prompt]
    cmd += ["transcribe", str(clip)]
    started = time.monotonic()
    proc = subprocess.run(cmd, capture_output=True, text=True)
    wall = time.monotonic() - started
    if proc.returncode != 0:
        die(f"voxtype failed on {clip.name}:\n{proc.stdout}\n{proc.stderr}")

    # voxtype prints whisper.cpp's model dump, its own tracing lines and the
    # transcript all to stdout. The tracing line carries the model's own timing,
    # which is the number worth comparing; the bare last line is the transcript
    # and survives even if log levels change.
    out = proc.stdout + proc.stderr
    secs = wall
    if m := TRANSCRIPT_LINE.search(out):
        secs = float(m.group(1))
    lines = [ln for ln in proc.stdout.splitlines() if ln.strip()]
    text = lines[-1].strip() if lines else ""
    if "INFO" in text or text.startswith("whisper_"):
        text = m.group(2) if (m := TRANSCRIPT_LINE.search(out)) else ""
    return text, secs


def cmd_run(args: argparse.Namespace) -> None:
    if args.bin:
        voxtype = str(Path(args.bin).expanduser())
        if not os.access(voxtype, os.X_OK):
            die(f"not executable: {voxtype}")
    else:
        voxtype = shutil.which("voxtype") or die("voxtype not on PATH")
    RUNS.mkdir(parents=True, exist_ok=True)
    migrate_flat_runs()
    engine = args.engine or DEFAULT_ENGINE
    out_dir = runs_dir(engine)
    sentences = load_sentences()
    clips = [s for s in sentences if s.clip.exists()]
    if not clips:
        die("no clips recorded yet -- run `voxtype-eval record`")
    if missing := len(sentences) - len(clips):
        print(f"note: {missing} sentence(s) have no clip, skipping them\n")

    variants = load_prompts()
    if args.only:
        variants = [v for v in variants if v[0] in args.only]
        if not variants:
            die(f"no variant matched {args.only}")

    for name, prompt in variants:
        path = out_dir / f"{name}.json"
        # Cached per clip, not per run. Recording is meant to be done in
        # batches, and keying the cache on the whole clip set meant adding ten
        # clips re-transcribed the lot -- six variants x every clip x 3s, for
        # ten new recordings. The prompt hash is what invalidates: change the
        # prompt and every clip legitimately has to be redone.
        # Model is folded in: swapping --model with the same prompt text is a
        # different experiment, and reusing the cache there would silently
        # attribute one model's transcripts to another.
        prompt_hash = hashlib.sha256(
            f"{prompt}\0{args.model or ''}".encode()
        ).hexdigest()[:16]
        hyps: dict[str, str] = {}
        secs: dict[str, float] = {}
        if path.exists() and not args.force:
            cached = json.loads(path.read_text())
            if cached.get("prompt_hash") == prompt_hash:
                hyps = cached.get("hyps", {})
                secs = cached.get("secs", {})

        todo = [s for s in clips if s.key not in hyps]
        if not todo:
            print(f"{name}: cached ({len(hyps)} clips)")
            continue

        print(f"{name}: {len(todo)} new clips", end="", flush=True)
        for s in todo:
            text, t = transcribe(voxtype, s.clip, prompt, args.model)
            hyps[s.key] = text
            secs[s.key] = t
            print(".", end="", flush=True)
            # Written after every clip: a 70-clip sweep is minutes long, and
            # losing all of it to a Ctrl-C is a bad trade for one write each.
            path.write_text(
                json.dumps(
                    {
                        "prompt": prompt,
                        "prompt_hash": prompt_hash,
                        "engine": engine,
                        "model": args.model,
                        "bin": voxtype,
                        "mean_secs": sum(secs.values()) / len(secs),
                        "hyps": hyps,
                        "secs": secs,
                    },
                    indent=2,
                )
            )
        print(f" {sum(secs.values()) / len(secs):.2f}s avg")
    print("\nnow: voxtype-eval report")


def cmd_report(args: argparse.Namespace) -> None:
    sentences = load_sentences()
    migrate_flat_runs()
    engines = sorted(
        (d.name for d in RUNS.iterdir() if d.is_dir()),
        # Whisper first so `control` stays the natural baseline.
        key=lambda e: (e != DEFAULT_ENGINE, e),
    )
    if args.engine:
        engines = [e for e in engines if e in args.engine]
        if not engines:
            die(f"no results for engine(s): {', '.join(args.engine)}")

    results = []
    for engine in engines:
        for name, _ in load_prompts():
            path = RUNS / engine / f"{name}.json"
            if not path.exists():
                continue
            data = json.loads(path.read_text())
            # Only label with the engine once there is more than one, so the
            # everyday prompt-sweep report stays as terse as it was.
            label = f"{engine}/{name}" if len(engines) > 1 else name
            results.append((label, data, score(sentences, data["hyps"])))
    if not results:
        die("no results -- run `voxtype-eval run`")

    # Unprompted whisper stays the baseline across engines: it is what you are
    # running today, so every delta reads as "versus the status quo".
    base = next(
        (s for n, _, s in results if n in ("control", f"{DEFAULT_ENGINE}/control")),
        results[0][2],
    )
    w = max(22, max(len(n) for n, _, _ in results) + 1)

    print(f"{'variant':<{w}} {'term recall':>12} {'cased':>7} {'WER':>7} "
          f"{'vs base':>8} {'sec':>6}")
    print("-" * (w + 46))
    for name, data, sc in results:
        recall = sc.term_hits / sc.term_total if sc.term_total else 0
        cased = sc.cased_hits / sc.term_total if sc.term_total else 0
        delta = sc.wer - base.wer
        print(
            f"{name:<{w}} {sc.term_hits:>4}/{sc.term_total:<3} {recall:>5.0%} "
            f"{cased:>6.0%} {sc.wer:>6.1%} {delta:>+7.1%} "
            f"{data['mean_secs']:>6.2f}"
        )

    # Per-term breakdown: which words are actually hard, and which prompt fixed
    # them. This is the table that tells you what to put in the real config --
    # the aggregate above only tells you whether anything moved at all.
    #
    # Counted per variant, not per miss: a term appearing twice in the corpus
    # can be failed twice by one variant, which used to report totals like
    # "12/6" and made a common word look unfixable.
    print("\nterms still missed (term -> variants that failed it):")
    by_term: dict[str, dict[str, None]] = {}
    for name, _, sc in results:
        for term, _ref, _hyp in sc.misses:
            by_term.setdefault(term, {})[name] = None
    if not by_term:
        print("  none")
    for term, names in sorted(by_term.items(), key=lambda kv: -len(kv[1])):
        print(f"  {term:<28} {len(names)}/{len(results)}  {', '.join(names)}")

    # Terms no prompt rescues. A 6/6 failure isn't a sampling artefact the way a
    # 1/6 difference is, so this is the one part of the report that's actionable
    # at small sample size -- and the fix is a substitution rule, not a prompt.
    always = [t for t, names in by_term.items() if len(names) == len(results)]
    if always:
        print(f"\nmissed by every variant ({len(always)}) -- "
              f"substitution candidates, no prompt will fix these:")
        for term in sorted(always):
            heard = sorted({
                misheard_as(t, r, h)
                for _, _, sc in results
                for t, r, h in sc.misses
                if t == term
            })
            print(f"  {term:<20} heard as: {', '.join(heard)}")

    if args.diff_all and args.diff is None:
        args.diff = []
    if args.diff is not None:
        want = set(args.diff) if args.diff else {n for n, _, _ in results}
        unknown = want - {n for n, _, _ in results}
        if unknown:
            die(f"no results for variant(s): {', '.join(sorted(unknown))}")
        print_diff(sentences, results, want, args.diff_all)


def print_diff(sentences, results, want: set[str], show_all: bool) -> None:
    """Per-clip word-level diff, worst clips first.

    The aggregate table says a prompt is worse; this says which four words it
    broke. `-` / red is the reference, `+` / green is what the model produced,
    `·` marks a word that has no counterpart on the other side.
    """
    print(f"\nper-clip diff ({'red' if _COLOUR else '-'} = reference, "
          f"{'green' if _COLOUR else '+'} = transcript, · = missing):")

    clips = []
    for s in sentences:
        ref_t = normalise(s.text)
        rows = []
        worst = 0.0
        for name, data, _ in results:
            if name not in want:
                continue
            hyp = data["hyps"].get(s.key)
            if hyp is None:
                continue
            ops = align(ref_t, normalise(hyp))
            errors = sum(1 for op, _, _ in ops if op != "=")
            wer = errors / len(ref_t) if ref_t else 0.0
            missed = [t for t in s.terms if not contains(normalise(hyp), normalise(t))]
            worst = max(worst, wer)
            rows.append((name, hyp, ops, errors, wer, missed))
        if rows and (show_all or any(r[3] or r[5] for r in rows)):
            clips.append((worst, s, rows))

    if not clips:
        print("  every clip in these variants is clean")
        return

    for _, s, rows in sorted(clips, key=lambda c: -c[0]):
        print(f"\n  #{s.index}  {s.key}  ({len(normalise(s.text))} words)")
        print(f"    ref   {s.text}")
        for name, hyp, ops, errors, wer, missed in rows:
            tag = f"{errors} err {wer:.0%}"
            if missed:
                tag += f", missed {', '.join(missed)}"
            print(f"    {name}  [{tag}]")
            if errors:
                ref_line, hyp_line = render_diff(ops)
                print(f"      - {ref_line}".rstrip())
                print(f"      + {hyp_line}".rstrip())
            else:
                print(f"      = {hyp}")


def die(msg: str) -> None:
    print(f"voxtype-eval: {msg}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    p = argparse.ArgumentParser(
        prog="voxtype-eval", description=__doc__.split("\n")[0]
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    i = sub.add_parser("init", help="seed sentences.txt and prompts.txt")
    i.add_argument("--force", action="store_true", help="overwrite existing files")
    i.set_defaults(fn=cmd_init)

    r = sub.add_parser("record", help="read the sentences aloud")
    r.add_argument("--redo", action="store_true", help="re-record everything")
    r.add_argument("--only", nargs="+", metavar="N",
                   help="re-record just these clips: 16, 16-20, 16,20")
    r.add_argument("--confirm", action="store_true", help="review each take")
    r.set_defaults(fn=cmd_record)

    x = sub.add_parser("run", help="transcribe every clip under every prompt")
    x.add_argument("--only", nargs="+", metavar="VARIANT")
    x.add_argument("--force", action="store_true", help="ignore cached results")
    x.add_argument("--bin", metavar="PATH",
                   help="voxtype binary to drive (default: the one on PATH)")
    x.add_argument("--engine", metavar="NAME",
                   help=f"namespace for results (default: {DEFAULT_ENGINE})")
    x.add_argument("--model", metavar="NAME",
                   help="pass --model to voxtype, e.g. parakeet-tdt-0.6b-v3")
    x.set_defaults(fn=cmd_run)

    rep = sub.add_parser("report", help="scores per variant and per term")
    rep.add_argument("--diff", nargs="*", metavar="VARIANT",
                     help="per-clip word-level diffs; no args means every variant")
    rep.add_argument("--engine", nargs="+", metavar="NAME",
                     help="restrict the report to these engines")
    rep.add_argument("--diff-all", action="store_true",
                     help="include clips that transcribed perfectly")
    rep.set_defaults(fn=cmd_report)

    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
