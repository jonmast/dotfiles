#!/usr/bin/env python3
"""Turn recent opencode prompts into a Voxtype evaluation corpus.

The first version of this harness shipped sentences I invented from CONTEXT.md.
They were grammatical, evenly-paced prose -- nothing like how anyone actually
dictates. These are the real thing: the prompts jon has actually submitted,
which are the closest available sample of what he will dictate next.

Read via `opencode2 api`, never by opening opencode.db. The database is 4.9GB of
live SQLite with a hot WAL, and the OpenCode troubleshooting guide is explicit
that you do not poke at it with external tools while the service is running.

THE CATCH, and the reason this is a review queue rather than a finished file:
those prompts were TYPED, not spoken. 111 of 147 start lowercase and only 5 end
in a period. Voxtype emits capitalised, punctuated text, so scoring a
transcription against the raw prompt would mark whisper WRONG for getting
capitalisation right. Every line therefore has to be rewritten into what
Voxtype *should* produce when that thought is spoken -- which this does
mechanically, and imperfectly, and then asks you to check.

Output is sentences.txt with `# REVIEW` markers on every line the heuristics
were unsure about. Read it before recording. The one failure mode that produces
plausible-but-wrong numbers is a reference that does not match what a correct
transcription would look like.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field

# Canonical spellings for the jargon in this corpus. Two jobs at once: these are
# the terms scored for recall, AND the authority on how they should be cased in
# a reference transcript.
#
# Assembled by diffing every token in the prompts against the hunspell en_US
# wordlist, then reading the ~83 out-of-dictionary hits by hand. That dictionary
# is missing common words ("after", "into"), so out-of-dictionary alone
# over-flags -- it was a candidate generator, not the decision.
#
# Keys are matched case-insensitively; the value is what gets written.
JARGON = {
    # Desktop / dotfiles
    "hyprland": "Hyprland", "quickshell": "Quickshell", "waybar": "waybar",
    "nixos": "NixOS", "sddm": "SDDM", "uwsm": "uwsm", "hy3": "hy3",
    "dwt": "DWT", "kwallet": "kwallet", "hyprlock": "hyprlock",
    "hypridle": "hypridle", "chezmoi": "chezmoi", "walker": "walker",
    "elephant": "elephant", "polkit": "polkit", "plasma": "Plasma",
    "kdeconnect": "kdeconnect", "diogenes": "Diogenes", "omarchy": "Omarchy",
    # Tooling
    "opencode": "opencode", "opencode2": "opencode2", "oc2": "oc2",
    "subagent": "subagent", "symlink": "symlink", "symlinking": "symlinking",
    "openapi": "OpenAPI", "apikey": "apikey", "auth": "auth",
    "config": "config", "configs": "configs", "env": "env", "repo": "repo",
    "eval": "eval", "evals": "evals", "systemd": "systemd",
    "journalctl": "journalctl", "nix": "nix", "flake": "flake",
    "wtype": "wtype", "voxtype": "Voxtype", "whisper": "whisper",
    # Infra / projects. Kept deliberately: these are the proper nouns whisper
    # mangles worst and initial_prompt fixes best, so removing them would make
    # the eval understate what prompting buys. Local file, outside git.
    "cliproxyapi": "CLIProxyApi", "cliproxy": "cliproxy", "cpa": "CPA",
    "locutus": "locutus", "linstor": "linstor", "magicctx": "magicctx",
    "dinhkarate": "dinhkarate", "omniroute": "omniroute",
    "omnirouter": "omnirouter", "nonroot": "nonroot",
    "anthropic": "Anthropic", "copilot": "Copilot", "github": "GitHub",
    "docker": "Docker", "kubernetes": "Kubernetes", "sqlite": "SQLite",
    "tooltips": "tooltips", "dictation": "dictation", "osd": "OSD",
    "quota": "quota", "quotas": "quotas", "plugin": "plugin",
    "glyph": "glyph", "hourglass": "hourglass", "spinner": "spinner",
    "pod": "pod", "rebuild": "rebuild", "merge": "merge", "commit": "commit",
    "openai": "OpenAI", "api": "API", "cli": "CLI", "ui": "UI",
}

# Mistranscriptions found by reading the corpus: prompts that were themselves
# dictated through Voxtype, and carry its errors. Left uncorrected they would
# become ground truth, and the eval would reward a prompt for REPRODUCING the
# error -- the exact inversion of what is being measured.
#
# Only unambiguous ones are auto-corrected. The rest is what SUSPECT below is
# for: this list cannot be complete, because finding these requires knowing what
# was meant.
MISTRANSCRIBED = {
    "glove rendering": "glyph rendering",
    "error glass": "hourglass",
    "Open AI compatible": "OpenAI-compatible",
}

# Signals that a prompt is itself Voxtype output rather than typed. Long,
# comma-light run-ons with spoken filler are the tell. Not a rejection --
# these are the most realistic items in the corpus -- but they are where
# mistranscriptions hide, so they get read twice.
SUSPECT = re.compile(
    r"\b(kind of|sort of|you know|I mean|or something|and stuff|in fact)\b", re.I
)

# Typing artefacts. A typo cannot be read aloud as written, and scoring whisper
# against "gottat" would count a correct transcription as an error -- so these
# are corrected rather than dropped, preserving the sentence.
TYPOS = {
    "gottat": "gotta", "doig": "doing", "everey": "every", "epxose": "expose",
    "thoguht": "thought", "pickinpug": "picking up", "doens't": "doesn't",
    "shouldnt'": "shouldn't", "ust": "just", "uncldera": "unclear",
    "odable": "doable", "chr": "char", "eg": "e.g.", "reqs": "requests",
    "deps": "dependencies", "hem": "them",
}

# Text that was pasted or typed, never spoken. Any hit rejects the line
# outright rather than trying to repair it.
REJECT = [
    (re.compile(r"https?://"), "url"),
    (re.compile(r"\b[\w-]+\.(com|net|org|io|dev|fun|local)\b"), "hostname"),
    (re.compile(r"/nix/store|(?<!\w)/(usr|etc|home|tmp|var|run)/"), "path"),
    (re.compile(r"`|```"), "code"),
    (re.compile(r"^\s*[/@]\w"), "command or file ref"),
    (re.compile(r"[{}\[\]<>|]|=="), "code punctuation"),
    # "ctrl+space" is written, not spoken -- you would say "control space", and
    # guessing which expansion you use would be inventing the reference.
    (re.compile(r"\w\+\w"), "key combo"),
    (re.compile(r"^\s*\d+\.\s"), "numbered list item"),
    (re.compile(r"^\s*>"), "quoted output"),
    (re.compile(r"\bTraceback\b|File \""), "stack trace"),
]

QUESTION_START = {
    "what", "why", "how", "when", "where", "who", "which", "whose", "is",
    "are", "was", "were", "do", "does", "did", "can", "could", "should",
    "would", "will", "have", "has", "had", "am", "any", "shall",
}

MIN_WORDS = 4  # below this, one token swings WER between 0% and 100%
MAX_WORDS = 30  # above this it stops being one dictated breath
WARMUP_MAX = 3  # short prompts kept unscored, to settle the voice


@dataclass
class Candidate:
    original: str
    text: str = ""
    terms: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)


def api(path: str) -> dict:
    """GET from the local opencode service.

    Output goes to a real file, not a pipe: `opencode2 api` truncates at 256KB
    when stdout is a pipe and still exits 0, so piping silently loses most of a
    large session and yields a JSONDecodeError on a string that looks fine up to
    the cut. Session transcripts run to 2.7MB, well past that.
    """
    with tempfile.TemporaryFile("w+") as fh:
        proc = subprocess.run(
            ["opencode2", "api", "get", path], stdout=fh, stderr=subprocess.PIPE,
            text=True,
        )
        if proc.returncode != 0:
            raise SystemExit(f"opencode2 api get {path} failed:\n{proc.stderr}")
        fh.seek(0)
        return json.load(fh)


def fetch_prompts() -> list[str]:
    """Every user message from every session opencode will list."""
    sessions = api("/api/session")["data"]
    out = []
    for s in sessions:
        for m in api(f"/api/session/{s['id']}/message")["data"]:
            # User messages carry a flat `.text`; assistant messages use a
            # `.content[]` array. Only the former is a prompt.
            if m.get("type") == "user" and (t := m.get("text", "").strip()):
                out.append(t)
    return out


def normalise(text: str) -> Candidate:
    """Rewrite a typed prompt into what Voxtype should have produced."""
    c = Candidate(original=text)

    for wrong, right in MISTRANSCRIBED.items():
        if wrong.lower() in text.lower():
            text = re.sub(re.escape(wrong), right, text, flags=re.I)
            c.notes.append(f"MISTRANSCRIPTION {wrong!r}->{right!r}")
    if SUSPECT.search(text):
        c.notes.append("looks dictated -- check for further mistranscriptions")

    fixed = []
    for w in text.split():
        bare = w.strip(".,!?;:\"'")
        trail = w[len(w.rstrip(".,!?;:\"'")):]
        if bare == "i":
            bare = "I"  # typed lowercase; whisper always capitalises it
        elif (low := bare.lower()) in TYPOS:
            bare = TYPOS[low]
            c.notes.append(f"typo {w!r}->{bare!r}")
        elif low in JARGON:
            canon = JARGON[low]
            if canon != bare:
                c.notes.append(f"cased {w!r}->{canon!r}")
            bare = canon
            c.terms.append(canon)
        fixed.append(bare + trail)

    out = " ".join(fixed)

    # Sentence case, unless the first token is a term whose canonical form is
    # deliberately lowercase (`journalctl`, `opencode2`) -- capitalising those
    # would make the reference wrong in the other direction.
    first = out.split()[0] if out.split() else ""
    if first.strip(".,!?") not in JARGON.values() and out[:1].islower():
        out = out[0].upper() + out[1:]

    # Terminal punctuation. Whisper emits it; typed prompts mostly omit it.
    if out and out[-1] not in ".?!":
        is_q = out.split()[0].lower().rstrip(",") in QUESTION_START
        out += "?" if is_q else "."
        c.notes.append("added '?'" if is_q else "added '.'")

    c.text = out
    return c


def screen(text: str) -> str | None:
    """Reason this prompt is unusable as a spoken eval item, or None."""
    if "\n" in text:
        return "multi-line (pasted)"
    for pat, why in REJECT:
        if pat.search(text):
            return why
    n = len(text.split())
    if n < MIN_WORDS:
        return "too short"
    if n > MAX_WORDS:
        return "too long"
    if sum(ch.isalpha() or ch.isspace() for ch in text) / len(text) < 0.85:
        return "not prose"
    return None


def annotate(c: Candidate) -> str:
    """Wrap scored terms in {braces} for voxtype-eval's term-recall metric."""
    out = c.text
    for term in sorted(set(c.terms), key=len, reverse=True):
        out = re.sub(
            rf"(?<![\w{{]){re.escape(term)}(?![\w}}])", "{" + term + "}", out, count=1
        )
    return out


def main() -> None:
    verbose = "--verbose" in sys.argv
    print("fetching sessions from opencode...", file=sys.stderr)
    prompts = fetch_prompts()
    print(f"  {len(prompts)} user messages", file=sys.stderr)

    seen: set[str] = set()
    kept: list[Candidate] = []
    warmups: list[str] = []
    rejected: dict[str, int] = {}

    for p in prompts:
        key = re.sub(r"[^a-z0-9 ]", "", p.lower()).strip()
        if key in seen:
            rejected["duplicate"] = rejected.get("duplicate", 0) + 1
            continue
        seen.add(key)

        if why := screen(p):
            rejected[why] = rejected.get(why, 0) + 1
            if why == "too short" and len(warmups) < WARMUP_MAX:
                warmups.append(p)
            elif verbose:
                print(f"  drop [{why}] {p[:70]}", file=sys.stderr)
            continue
        kept.append(normalise(p))

    print(f"\n  kept {len(kept)}, rejected:", file=sys.stderr)
    for why, n in sorted(rejected.items(), key=lambda kv: -kv[1]):
        print(f"    {n:>3}  {why}", file=sys.stderr)
    terms = sum(len(set(c.terms)) for c in kept)
    unsure = sum(1 for c in kept if c.notes)
    print(f"  {terms} scored terms, {unsure} lines flagged REVIEW\n", file=sys.stderr)

    print(f"""\
# Voxtype evaluation corpus -- REVIEW BEFORE RECORDING.
#
# Built by voxtype_corpus.py from {len(prompts)} prompts submitted to opencode.
# These are the real thing, so the vocabulary and register are yours -- but they
# were TYPED, and this file has to hold what Voxtype should output when you
# SPEAK them. Lines were mechanically sentence-cased, terminally punctuated and
# typo-corrected to get there.
#
# Your job, once:
#   - Delete anything you would never say out loud.
#   - Fix any line that is not what you would actually dictate.
#   - Check the {{braced}} terms: those are what term-recall scores. Brace
#     anything else whisper is likely to mangle; unbrace anything trivial.
#   - Every `# REVIEW` note below marks a guess this script made. Then delete
#     the notes, or leave them -- comments are ignored.
#
# Warm-ups (read aloud before recording, not scored, not saved):
{chr(10).join('#   ' + w for w in warmups) or '#   (none)'}
""")

    for c in kept:
        if c.notes:
            print(f"# REVIEW: {'; '.join(c.notes)}")
            if verbose:
                print(f"# was: {c.original}")
        print(annotate(c))


if __name__ == "__main__":
    main()
