#!/usr/bin/env python3
"""Collect multi-provider AI quota into one display-ready JSON record.

Everything the bar widget shows comes from this one command. The QML never
talks to an endpoint, never sees the admin key, and never parses a provider's
wire format — it reads the record printed here. That split is lifted from
omarchy's `omarchy-agent-usage-claude`, and it earns its keep for the same
reason: the two data sources below have completely different failure modes,
and none of that belongs in a widget.

One source, one call:

  Quota   GET {base}/v0/management/plugins/cpa-quota-api-extension/v1/quotas
          served by the cpa-quota-api-extension plugin on the live CPA instance.
          The plugin returns a normalized, provider-nested snapshot covering
          every provider (Claude, Copilot, OpenCode Go). All provider knowledge
          — endpoints, payload shapes, window selection, percent normalization —
          lives in the plugin; this client makes one authenticated GET and
          formats the result. It contains no provider-specific endpoint or
          payload knowledge, so a new provider needs no client change.

  Usage   GET {base}/v0/management/dashboard/summary, served from CPAMP's local
          SQLite (drained from CPA's usage queue). No upstream call, cheap, and
          safe to refresh often.

The quota route is read-only and cached by the plugin itself, so the only
client-side cache here protects against CPAMP being unreachable: a stale
reading is served rather than blanking the bar. The widget distinguishes
stale/failed records by reading `ok`/`stale`, not by guessing an exit code.

Note what is NOT used: `/v0/management/usage-queue` is a destructive pop —
reading it removes records CPAMP needs for its own history. And `/v0/management/
usage` returns the full per-request detail (247KB and growing), where
dashboard/summary returns the same totals pre-aggregated.
"""

import argparse
import datetime as dt
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

BASE_URL = os.environ.get("AI_QUOTA_BASE_URL", "http://cpamp.homelab.jonmast.com")

# The single read-only route the plugin exposes. One GET returns a normalized,
# provider-nested snapshot for every provider; the client never assembles
# provider calls itself. `?refresh=true` forces the plugin past its cache.
QUOTA_ROUTE = "/v0/management/plugins/cpa-quota-api-extension/v1/quotas"

WALLET = os.environ.get("AI_QUOTA_WALLET", "kdewallet")
WALLET_FOLDER = os.environ.get("AI_QUOTA_WALLET_FOLDER", "cpamp")
WALLET_ENTRY = os.environ.get("AI_QUOTA_WALLET_ENTRY", "admin-key")

# Display-only metadata for the pill prefix and tooltip header. These are
# cosmetic labels, not endpoint or payload knowledge: any provider key not
# listed falls back to a derived two-letter code and a title-cased name, so a
# new provider needs no client change.
PROVIDER_META = {
    "claude": ("CC", "Claude"),
    "copilot": ("GH", "Copilot"),
    "opencode-go": ("OC", "OpenCode Go"),
}

# Display-only window labels. Unknown ids fall back to a title-cased slug, so a
# provider that introduces a new window id still renders.
WINDOW_LABELS = {
    "five_hour": "Session (5h)",
    "seven_day": "Weekly (7d)",
    "extra": "Extra usage",
    "premium_interactions": "Premium interactions",
    "chat": "Chat",
    "completions": "Completions",
    "rolling": "Rolling",
    "weekly": "Weekly",
    "monthly": "Monthly",
}

# Deliberately short, because this TTL does NOT govern upstream request rate —
# the plugin owns its own cache and only calls providers on a miss, so a client
# fetch inside the plugin's TTL is a clone of an in-memory snapshot. Holding a
# reading here for longer than the plugin holds its own only adds latency
# between the plugin refreshing and the bar showing it. Set this at or below the
# plugin's `cache-ttl` and let the plugin decide what upstream costs.
QUOTA_TTL_SECONDS = int(os.environ.get("AI_QUOTA_TTL", "60"))
USAGE_TTL_SECONDS = int(os.environ.get("AI_QUOTA_USAGE_TTL", "300"))
HTTP_TIMEOUT = 20


def cache_dir():
    root = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    path = os.path.join(root, "ai-quota")
    os.makedirs(path, mode=0o700, exist_ok=True)
    return path


def read_json(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except Exception:
        return None


def write_json(path, payload):
    # Written via a temp file and renamed: the widget polls this path on its own
    # schedule, and a reader that catches a half-written file would see a parse
    # error rather than the last good record.
    tmp = path + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as handle:
            json.dump(payload, handle)
        os.replace(tmp, path)
    except Exception:
        pass


def now_ms():
    return int(time.time() * 1000)


def admin_key():
    """Read the CPAMP admin key from kwallet.

    The key never appears in the process table, in the environment, or in this
    repository. kwallet is unlocked at login by kwallet-pam (CONTEXT.md, "KDE
    infra"), so by the time the bar is running the wallet is open.
    """
    try:
        result = subprocess.run(
            ["kwallet-query", "-f", WALLET_FOLDER, "-r", WALLET_ENTRY, WALLET],
            capture_output=True,
            text=True,
            timeout=10,
        )
    except Exception:
        return ""
    if result.returncode != 0:
        return ""
    key = result.stdout.strip()
    # kwallet-query prints a human-readable complaint on stdout rather than
    # failing when the entry is absent, so an implausible value is treated as no
    # key at all instead of being sent as a bearer token.
    if not key or "not found" in key.lower():
        return ""
    return key


def request_json(url, key, method="GET", body=None):
    """One HTTP call to CPAMP. Returns (payload, error, retry_after_seconds)."""
    data = None
    headers = {"Authorization": "Bearer " + key, "Accept": "application/json"}
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT) as response:
            return json.loads(response.read().decode("utf-8", errors="replace")), "", 0
    except urllib.error.HTTPError as error:
        retry_after = 0
        if error.headers:
            try:
                retry_after = int(error.headers.get("retry-after", "0") or 0)
            except ValueError:
                retry_after = 0
        if error.code in (401, 403):
            return None, "CPAMP rejected the admin key", 0
        return None, "CPAMP returned status %d" % error.code, retry_after
    except Exception:
        # No server was reached at all — no route, no DNS, homelab down. Worth
        # distinguishing from a real error status, because it should not start a
        # long backoff: the endpoint never said it was busy.
        return None, "Couldn't reach CPAMP", 0


def iso_to_ms(value):
    if not value:
        return 0
    text = str(value)
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    # Cap fractional seconds at microseconds so nanosecond-precision timestamps
    # (9 digits) parse on older Pythons too.
    dot = text.find(".")
    if dot != -1:
        end = len(text)
        for marker in ("+", "-"):
            pos = text.find(marker, dot + 1)
            if pos != -1:
                end = min(end, pos)
        frac = text[dot + 1 : end]
        if len(frac) > 6:
            text = text[: dot + 1] + frac[:6] + text[end:]
    try:
        return int(dt.datetime.fromisoformat(text).timestamp() * 1000)
    except Exception:
        return 0


def provider_prefix(key):
    meta = PROVIDER_META.get(key)
    if meta:
        return meta[0]
    letters = [c for c in key.upper() if c.isalpha()]
    return "".join(letters[:2]) or key.upper()[:2]


def provider_name(key):
    meta = PROVIDER_META.get(key)
    if meta:
        return meta[1]
    return key.replace("-", " ").replace("_", " ").title()


def window_label(window_id):
    if window_id in WINDOW_LABELS:
        return WINDOW_LABELS[window_id]
    return window_id.replace("_", " ").title()


def build_projection(projection):
    """Normalize the plugin's forecast block, or None when it did not send one.

    The plugin declines to forecast a window it cannot honestly forecast — one
    with no duration, or one too early in its span to extrapolate from. That is
    a real answer, so an absent block is passed through as None rather than
    being filled in here: the client already has a clock-only fallback, and it
    needs to know which of the two readings it is showing.
    """
    if not isinstance(projection, dict):
        return None

    expected = projection.get("expected_fraction")
    if expected is None:
        return None

    return {
        # Profile-weighted progress through the window. The figure the client
        # cannot compute for itself, and the reason this block is plumbed
        # through at all rather than derived locally from the reset time.
        "expectedFraction": expected,
        # Raw wall-clock progress. Equal to the above when `basis` is
        # "uniform", i.e. the profile had no history to go on.
        "elapsedFraction": projection.get("elapsed_fraction"),
        "projectedUsedPercent": projection.get("projected_used_percent"),
        "naiveProjectedPercent": projection.get("naive_projected_percent"),
        # None rather than 0 when the forecast never crosses the limit — the
        # client distinguishes "no exhaustion predicted" from a timestamp.
        "projectedExhaustionAtMs": iso_to_ms(projection.get("projected_exhaustion_at")) or None,
        "verdict": projection.get("verdict", ""),
        "confidence": projection.get("confidence", ""),
        "basis": projection.get("basis", ""),
    }


def build_window(window_id, label, used, remaining, reset_at, used_dollars, limit_dollars, binding, model=False, window_seconds=None, projection=None):
    return {
        "id": window_id,
        "label": label,
        "usedPercent": used,
        "remainingPercent": remaining,
        "resetAtMs": iso_to_ms(reset_at),
        "usedDollars": used_dollars,
        "limitDollars": limit_dollars,
        "binding": binding,
        "model": model,
        # How long the window spans. With the reset time this recovers the
        # window's START, which is what any pace reading needs. Absent for
        # windows the plugin has no span for (Claude's `extra`, OpenCode Go's
        # `monthly`), so the client must treat it as optional.
        "windowSeconds": window_seconds,
        "projection": projection,
    }


def parse_provider(key, provider):
    """Normalize one provider entry into the display shape.

    Windows carry `used_percent` (0-100) identical in semantics across every
    provider, so the pill can compare them numerically. Claude's model-scoped
    weeklies arrive as `models[]` rather than `windows[]`; they are folded in as
    windows (used = 100 - remaining) so they compete for the pill and appear in
    the tooltip.
    """
    binding_id = ""
    binding = provider.get("binding_window")
    if isinstance(binding, dict):
        binding_id = binding.get("id", "") or ""

    windows = []
    for window in provider.get("windows") or []:
        if not isinstance(window, dict):
            continue
        window_id = window.get("id", "")
        used = window.get("used_percent")
        windows.append(
            build_window(
                window_id,
                window_label(window_id),
                used,
                window.get("remaining_percent"),
                window.get("reset_at"),
                window.get("used_dollars"),
                window.get("limit_dollars"),
                window_id == binding_id,
                model=False,
                window_seconds=window.get("window_seconds"),
                projection=build_projection(window.get("projection")),
            )
        )

    # Claude's model-scoped weeklies arrive with neither a span nor a
    # projection, so they get neither here. Inferring "these ride the weekly
    # window" is deliberately left to the client, which marks a reading derived
    # that way as inferred; doing it here would launder a guess into a field
    # that otherwise only ever carries what the provider stated.
    for model in provider.get("models") or []:
        if not isinstance(model, dict):
            continue
        model_id = model.get("model", "")
        remaining = model.get("remaining_percent")
        used = None if remaining is None else 100 - remaining
        windows.append(
            build_window(
                model_id,
                model.get("model_name") or model_id,
                used,
                remaining,
                model.get("reset_at"),
                None,
                None,
                False,
                model=True,
            )
        )

    error = provider.get("error")
    return {
        "key": key,
        "prefix": provider_prefix(key),
        "name": provider_name(key),
        "status": provider.get("status", ""),
        "supported": bool(provider.get("supported", False)),
        "credentialState": provider.get("credential_state", ""),
        "error": error if isinstance(error, dict) else None,
        "bindingWindowId": binding_id,
        "windows": windows,
    }


def build_record(payload):
    """Turn the plugin's snapshot into (providers_list, tightest).

    The pill shows the single tightest window across every provider and every
    window: the one with the highest used percent. Because percent semantics
    are identical across providers, that is a pure numeric comparison — the
    client needs no provider knowledge to pick it.
    """
    providers_map = payload.get("providers") or {}
    providers_list = []
    best = None  # (used_percent, provider_key, prefix, window_id, reset_at_ms)
    for key in sorted(providers_map.keys()):
        provider = providers_map[key] or {}
        entry = parse_provider(key, provider)
        providers_list.append(entry)
        for window in entry["windows"]:
            used = window["usedPercent"]
            if used is None:
                continue
            if best is None or used > best[0]:
                best = (used, key, provider_prefix(key), window["id"], window["resetAtMs"])

    tightest = None
    if best is not None:
        tightest = {
            "usedPercent": best[0],
            "provider": best[1],
            "prefix": best[2],
            "windowId": best[3],
            "resetAtMs": best[4],
        }
    return providers_list, tightest


def fetch_quota(key):
    cache_path = os.path.join(cache_dir(), "quota.json")
    cached = read_json(cache_path) or {}

    def stale_result(error):
        """Serve the last good snapshot rather than blanking the bar.

        A quota window is 5 hours or 7 days wide, so a reading from twenty
        minutes ago is still substantially true, whereas an empty pill says
        nothing and invites a manual check that costs another rate-limited
        request. The record carries the age so the widget can dim itself.
        """
        if cached.get("providers") is not None:
            return {
                "ok": True,
                "stale": True,
                "error": error,
                "fetchedAtMs": cached.get("fetchedAtMs", 0),
                "generatedAtMs": cached.get("generatedAtMs", 0),
                "providers": cached.get("providers", []),
                "tightest": cached.get("tightest"),
            }
        return {"ok": False, "stale": False, "error": error, "fetchedAtMs": 0, "generatedAtMs": 0, "providers": [], "tightest": None}

    if not key:
        return stale_result("No CPAMP admin key in kwallet (%s/%s)" % (WALLET_FOLDER, WALLET_ENTRY))

    # A 429 names the moment it is willing to talk again. Honouring it is not
    # politeness — ignoring it extends the penalty and keeps the widget dark for
    # longer than the provider asked for.
    backoff_until = cached.get("backoffUntilMs", 0)
    if not FORCE and backoff_until > now_ms():
        remaining = int((backoff_until - now_ms()) / 1000)
        return stale_result("Rate limited; retrying in %ds" % remaining)

    age = (now_ms() - cached.get("fetchedAtMs", 0)) / 1000
    if not FORCE and cached.get("providers") is not None and age < QUOTA_TTL_SECONDS:
        return {
            "ok": cached.get("ok", True),
            "stale": False,
            "error": "",
            "fetchedAtMs": cached.get("fetchedAtMs", 0),
            "generatedAtMs": cached.get("generatedAtMs", 0),
            "providers": cached.get("providers", []),
            "tightest": cached.get("tightest"),
        }

    url = BASE_URL.rstrip("/") + QUOTA_ROUTE
    if FORCE:
        url += "?refresh=true"
    payload, error, retry_after = request_json(url, key)
    if error:
        if retry_after:
            cached["backoffUntilMs"] = now_ms() + retry_after * 1000
            write_json(cache_path, cached)
        return stale_result(error)

    try:
        providers_list, tightest = build_record(payload)
    except Exception as exc:
        return stale_result("Couldn't parse quota response: %s" % exc)

    # Two different clocks, and the difference is the point. `fetchedAtMs` is
    # when THIS client last spoke to CPAMP; `generatedAtMs` is when the plugin
    # last spoke to the providers. They diverge by up to the plugin's own
    # cache-ttl, so reporting only the first would call a half-hour-old reading
    # fresh just because the local fetch was recent.
    record = {
        "ok": True,
        "stale": False,
        "error": "",
        "fetchedAtMs": now_ms(),
        "generatedAtMs": iso_to_ms(payload.get("generated_at")),
        "providers": providers_list,
        "tightest": tightest,
        "backoffUntilMs": 0,
    }
    write_json(cache_path, record)
    return record


def fetch_usage(key):
    """Today's activity from CPAMP's local store. Never touches a provider."""
    cache_path = os.path.join(cache_dir(), "usage.json")
    cached = read_json(cache_path) or {}

    age = (now_ms() - cached.get("fetchedAtMs", 0)) / 1000
    if not FORCE and cached.get("today") and age < USAGE_TTL_SECONDS:
        return cached

    if not key:
        return cached

    # The dashboard defines "today" by an explicit local-midnight boundary
    # rather than assuming the server's timezone matches this machine's.
    midnight = dt.datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    url = "%s/v0/management/dashboard/summary?today_start_ms=%d" % (
        BASE_URL.rstrip("/"),
        int(midnight.timestamp() * 1000),
    )
    payload, error, _ = request_json(url, key)
    if error or not isinstance(payload, dict):
        return cached

    today = payload.get("today") or {}
    rolling = payload.get("rolling_30m") or {}

    # Cache hit rate, over prompt tokens only.
    #
    # `input_tokens` is the whole prompt side, and it decomposes into three
    # parts: tokens read from cache, tokens written to cache, and fresh tokens
    # that were neither. So the denominator is input_tokens, NOT total_tokens —
    # including completions would drag the rate down with tokens that were never
    # cacheable in the first place, which would make a genuinely well-cached
    # session look mediocre.
    #
    # Cache *creation* counts as a miss here. It is a write, not a read: those
    # tokens were paid for at full rate on this request, and folding them into
    # the numerator would report a cache that had never once been read from as
    # a hit.
    input_tokens = today.get("input_tokens", 0) or 0
    cache_read = today.get("cache_read_tokens", 0) or 0
    cache_hit_rate = round(100.0 * cache_read / input_tokens, 1) if input_tokens > 0 else -1

    record = {
        "fetchedAtMs": now_ms(),
        "today": {
            "calls": today.get("total_calls", 0),
            "failures": today.get("failure_calls", 0),
            "tokens": today.get("total_tokens", 0),
            "inputTokens": input_tokens,
            "cacheReadTokens": cache_read,
            "cacheCreationTokens": today.get("cache_creation_tokens", 0),
            # -1, not 0, when there is nothing to divide by: a fresh day with no
            # requests has no hit rate, and showing "0%" would read as a
            # catastrophically cold cache rather than as an absent measurement.
            "cacheHitRate": cache_hit_rate,
            # Deliberately carried as-is. CPAMP reports 0 when model prices have
            # not been synced, and a rendered "$0.00" would be a fabrication;
            # the widget shows cost only when this is non-zero.
            "cost": today.get("total_cost", 0),
        },
        "rolling30m": {
            "rpm": round(rolling.get("rpm", 0), 1),
            "tpm": int(rolling.get("tpm", 0)),
        },
        "topModels": [
            {
                "model": entry.get("model", ""),
                "calls": entry.get("calls", 0),
                "tokens": entry.get("tokens", 0),
            }
            for entry in (payload.get("top_models_today") or [])[:3]
        ],
    }
    write_json(cache_path, record)
    return record


def main():
    parser = argparse.ArgumentParser(description="Print multi-provider AI quota and CPAMP activity as one JSON record.")
    parser.add_argument(
        "--force",
        action="store_true",
        help="ignore caches and backoff; a person asking for fresh numbers overrules the reuse window",
    )
    args = parser.parse_args()

    global FORCE
    FORCE = args.force

    key = admin_key()
    quota = fetch_quota(key)
    usage = fetch_usage(key)

    record = {
        "ok": quota.get("ok", False),
        "stale": quota.get("stale", False),
        "error": quota.get("error", ""),
        "fetchedAtMs": quota.get("fetchedAtMs", 0),
        "generatedAtMs": quota.get("generatedAtMs", 0),
        "providers": quota.get("providers", []),
        "tightest": quota.get("tightest"),
        "today": usage.get("today", {}),
        "rolling30m": usage.get("rolling30m", {}),
        "topModels": usage.get("topModels", []),
    }
    json.dump(record, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


FORCE = False

if __name__ == "__main__":
    sys.exit(main())
