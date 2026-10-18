#!/usr/bin/env python3
"""Collect multi-provider AI quota into one display-ready JSON record.

Everything the bar widget shows comes from this one command. The QML never
talks to an endpoint and never parses a wire format — it reads the record
printed here. That split is lifted from omarchy's `omarchy-agent-usage-claude`,
and it earns its keep for the same reason: the two data sources below have
different failure modes, and none of that belongs in a widget.

Both come from Sextant, the Telemetry Hub (jonmast/bifrost-meridian), which
polls the upstreams itself and serves what it stored:

  Quota   GET {base}/v1/quota
          One window map per upstream (Claude, OpenCode Go), each window with
          its utilization, reset time and pace projection. `--force` sends
          POST {base}/v1/quota/refresh instead, which returns the same body;
          Sextant skips an upstream it polled under 30 s ago, so the client
          needs no rate limiting of its own.

  Usage   GET {base}/v1/usage/summary?since=<local midnight, RFC 3339>
          Today's totals over every Gateway request, from Sextant's own copy of
          the request log. No upstream call, cheap, and safe to refresh often.

Both routes are served without auth. Everything else on the host sits behind
forward-auth, so a route that has fallen through to the UI Ingress answers with
an HTML redirect to the login page; any non-JSON answer is therefore an error,
never data.

The only client-side cache here protects against Sextant being unreachable: a
stale reading is served rather than blanking the bar. The widget distinguishes
stale/failed records by reading `ok`/`stale`, not by guessing an exit code.
"""

import argparse
import datetime as dt
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE_URL = os.environ.get("AI_QUOTA_BASE_URL", "https://quota.homelab.jonmast.com")

QUOTA_ROUTE = "/v1/quota"
REFRESH_ROUTE = "/v1/quota/refresh"
USAGE_ROUTE = "/v1/usage/summary"

# Display-only metadata for the pill prefix and tooltip header. These are
# cosmetic labels, not endpoint or payload knowledge: any upstream not listed
# falls back to a derived two-letter code and a title-cased name, so a new
# upstream needs no client change.
PROVIDER_META = {
    "claude": ("CC", "Claude"),
    "opencode-go": ("OC", "OpenCode Go"),
}

# Window ids that name a span. Sextant reports a per-model limit as an ordinary
# window whose id is a span plus a model suffix (`7d_fable`), so an id of the
# form `<span>_<model>` is the per-model subdivision of that span.
SPAN_NAMES = {
    "5h": "session",
    "7d": "weekly",
}

# Display-only window labels. Unknown ids fall back to a title-cased slug, so an
# upstream that introduces a new window id still renders.
WINDOW_LABELS = {
    "5h": "Session (5h)",
    "7d": "Weekly (7d)",
    "7d_fable": "Fable weekly (7d)",
    "rolling": "Rolling",
    "weekly": "Weekly",
    "monthly": "Monthly",
}

# Deliberately short, because this TTL does NOT govern upstream request rate —
# Sextant polls the upstreams on its own schedule, so a client fetch only reads
# what it already stored. Holding a reading here longer only adds latency
# between Sextant polling and the bar showing it.
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


def request_json(url, method="GET"):
    """One HTTP call to Sextant. Returns (payload, error)."""
    request = urllib.request.Request(url, headers={"Accept": "application/json"}, method=method)
    try:
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT) as response:
            content_type = response.headers.get("Content-Type", "")
            body = response.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as error:
        return None, "Sextant returned status %d" % error.code
    except Exception:
        return None, "Couldn't reach Sextant"

    # urllib follows redirects, so a route that fell through to forward-auth
    # arrives here as a 200 carrying the login page.
    if "json" not in content_type:
        return None, "Sextant answered with %s, not JSON (route behind forward-auth?)" % (content_type or "no content type")
    try:
        payload = json.loads(body)
    except ValueError:
        return None, "Sextant returned malformed JSON"
    if not isinstance(payload, dict):
        return None, "Sextant returned an unexpected JSON shape"
    return payload, ""


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


def model_span(window_id):
    """The span a per-model window subdivides (`7d` for `7d_fable`), or ""."""
    span, sep, model = window_id.partition("_")
    if sep and model and span in SPAN_NAMES:
        return span
    return ""


def window_label(window_id):
    if window_id in WINDOW_LABELS:
        return WINDOW_LABELS[window_id]
    span = model_span(window_id)
    if span:
        model = window_id[len(span) + 1 :].replace("_", " ").title()
        return "%s %s (%s)" % (model, SPAN_NAMES[span], span)
    return window_id.replace("_", " ").title()


def build_projection(window):
    """Normalize a window's forecast fields, or None when it has none.

    Sextant declines to forecast a window it cannot honestly forecast — one
    with no fixed cycle start (`rolling`) or no reset time — and says so with a null
    `expected_fraction`. That is a real answer, so it is passed through as None
    rather than being filled in here: the client already has a clock-only
    fallback, and it needs to know which of the two readings it is showing.
    """
    expected = window.get("expected_fraction")
    if expected is None:
        return None

    return {
        # Profile-weighted progress through the window. The figure the client
        # cannot compute for itself, and the reason this block is plumbed
        # through at all rather than derived locally from the reset time.
        "expectedFraction": expected,
        # Raw wall-clock progress. Equal to the above when `basis` is
        # "uniform", i.e. the profile had no history to go on.
        "elapsedFraction": window.get("elapsed_fraction"),
        "projectedUsedPercent": window.get("projected_used_percent"),
        "naiveProjectedPercent": window.get("naive_projected_percent"),
        # None rather than 0 when the forecast never crosses the limit — the
        # client distinguishes "no exhaustion predicted" from a timestamp.
        "projectedExhaustionAtMs": iso_to_ms(window.get("projected_exhaustion")) or None,
        "verdict": window.get("verdict") or "",
        "confidence": window.get("confidence") or "",
        "basis": window.get("basis") or "",
    }


def build_window(window_id, window):
    used = window.get("utilization")
    return {
        "id": window_id,
        "label": window_label(window_id),
        "usedPercent": used,
        "remainingPercent": None if used is None else 100 - used,
        "resetAtMs": iso_to_ms(window.get("resets_at")),
        "usedDollars": None,
        "limitDollars": None,
        "binding": False,
        "model": bool(model_span(window_id)),
        # How long the window spans. With the reset time this recovers the
        # window's START, which is what any pace reading needs. Null for
        # windows with no fixed cycle, so the client must treat it as optional.
        "windowSeconds": window.get("window_seconds"),
        # Sextant marks a window stale once it is older than three of its poll
        # intervals: the upstream has stopped answering for it.
        "stale": window.get("stale") is True,
        "projection": build_projection(window),
    }


def parse_provider(key, upstream):
    """Normalize one Sextant upstream into the display shape.

    Windows carry `utilization` (0-100) identical in semantics across every
    upstream, so the pill can compare them numerically. Per-model limits are
    ordinary windows on the wire and are only flagged `model` here.
    """
    windows_map = upstream.get("windows") or {}
    windows = [
        build_window(window_id, windows_map[window_id])
        for window_id in sorted(windows_map.keys())
        if isinstance(windows_map[window_id], dict)
    ]

    last_error = upstream.get("last_error")
    return {
        "key": key,
        "prefix": provider_prefix(key),
        "name": provider_name(key),
        "status": "",
        "supported": True,
        "credentialState": "",
        # The tooltip reads `error.message`.
        "error": {"message": str(last_error)} if last_error else None,
        "bindingWindowId": "",
        "windows": windows,
    }


def oldest_fetched_at_ms(upstreams):
    """The `fetched_at` of the stalest window, so no reading is called fresher
    than its oldest part. 0 when no window carries one."""
    oldest = 0
    for upstream in upstreams.values():
        for window in ((upstream or {}).get("windows") or {}).values():
            if not isinstance(window, dict):
                continue
            fetched = iso_to_ms(window.get("fetched_at"))
            if fetched and (oldest == 0 or fetched < oldest):
                oldest = fetched
    return oldest


def build_record(payload):
    """Turn Sextant's quota body into (providers_list, tightest).

    The pill shows the single tightest window across every upstream and every
    window: the one with the highest used percent. Because percent semantics
    are identical across upstreams, that is a pure numeric comparison — the
    client needs no provider knowledge to pick it.
    """
    upstreams = payload.get("upstreams")
    if not isinstance(upstreams, dict):
        raise ValueError("no upstreams map")
    providers_list = []
    best = None  # (used_percent, provider_key, prefix, window_id, reset_at_ms, stale)
    for key in sorted(upstreams.keys()):
        upstream = upstreams[key] or {}
        entry = parse_provider(key, upstream)
        providers_list.append(entry)
        for window in entry["windows"]:
            used = window["usedPercent"]
            if used is None:
                continue
            if best is None or used > best[0]:
                best = (used, key, provider_prefix(key), window["id"], window["resetAtMs"], window["stale"])

    tightest = None
    if best is not None:
        tightest = {
            "usedPercent": best[0],
            "provider": best[1],
            "prefix": best[2],
            "windowId": best[3],
            "resetAtMs": best[4],
            "stale": best[5],
        }
    return providers_list, tightest


def fetch_quota():
    cache_path = os.path.join(cache_dir(), "quota.json")
    cached = read_json(cache_path) or {}

    def stale_result(error):
        """Serve the last good snapshot rather than blanking the bar.

        A quota window is 5 hours or 7 days wide, so a reading from twenty
        minutes ago is still substantially true, whereas an empty pill says
        nothing. The record carries the age so the widget can dim itself.
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

    if FORCE:
        payload, error = request_json(BASE_URL.rstrip("/") + REFRESH_ROUTE, method="POST")
    else:
        payload, error = request_json(BASE_URL.rstrip("/") + QUOTA_ROUTE)
    if error:
        return stale_result(error)

    try:
        providers_list, tightest = build_record(payload)
        generated_at = oldest_fetched_at_ms(payload["upstreams"])
    except Exception as exc:
        return stale_result("Couldn't parse quota response: %s" % exc)

    # Two different clocks, and the difference is the point. `fetchedAtMs` is
    # when THIS client last spoke to Sextant; `generatedAtMs` is when Sextant
    # last spoke to the upstreams. They diverge by up to Sextant's poll
    # interval, so reporting only the first would call a half-hour-old reading
    # fresh just because the local fetch was recent.
    record = {
        "ok": True,
        "stale": False,
        "error": "",
        "fetchedAtMs": now_ms(),
        "generatedAtMs": generated_at,
        "providers": providers_list,
        "tightest": tightest,
    }
    write_json(cache_path, record)
    return record


def fetch_usage():
    """Today's activity from Sextant's copy of the Gateway log. Never touches
    an upstream."""
    cache_path = os.path.join(cache_dir(), "usage.json")
    cached = read_json(cache_path) or {}

    # "Today" is defined by an explicit local-midnight boundary rather than by
    # assuming the server's timezone matches this machine's.
    midnight = dt.datetime.now().astimezone().replace(hour=0, minute=0, second=0, microsecond=0)
    since_ms = int(midnight.timestamp() * 1000)

    # Yesterday's totals are not a stale reading of today, they are a wrong
    # one, so a cache from before midnight is never served.
    if cached.get("sinceMs") != since_ms:
        cached = {}

    age = (now_ms() - cached.get("fetchedAtMs", 0)) / 1000
    if not FORCE and cached.get("today") and age < USAGE_TTL_SECONDS:
        return cached

    url = "%s%s?since=%s" % (
        BASE_URL.rstrip("/"),
        USAGE_ROUTE,
        urllib.parse.quote(midnight.isoformat()),
    )
    payload, error = request_json(url)
    if error:
        return cached

    # A failing Gateway copy still answers, with whatever it stored before it
    # broke. Those totals undercount, so the last complete reading is kept
    # instead — unless there is none, where an undercount beats nothing.
    bifrost = (payload.get("sources") or {}).get("bifrost") or {}
    if bifrost.get("last_error") and cached.get("today"):
        return cached

    totals = payload.get("totals") or {}
    rolling = payload.get("last_30m") or {}

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
    input_tokens = totals.get("input_tokens", 0) or 0
    cache_read = totals.get("cache_read_tokens", 0) or 0
    cache_hit_rate = round(100.0 * cache_read / input_tokens, 1) if input_tokens > 0 else -1

    record = {
        "fetchedAtMs": now_ms(),
        "sinceMs": since_ms,
        "today": {
            "calls": totals.get("calls", 0),
            "failures": totals.get("failures", 0),
            "tokens": totals.get("total_tokens", 0),
            "inputTokens": input_tokens,
            "cacheReadTokens": cache_read,
            "cacheCreationTokens": totals.get("cache_write_tokens", 0),
            # -1, not 0, when there is nothing to divide by: a fresh day with no
            # requests has no hit rate, and showing "0%" would read as a
            # catastrophically cold cache rather than as an absent measurement.
            "cacheHitRate": cache_hit_rate,
            # Sextant stores no cost. Kept in the record shape; nothing shows it.
            "cost": 0,
        },
        "rolling30m": {
            "rpm": round(rolling.get("rpm", 0) or 0, 1),
            "tpm": int(rolling.get("tpm", 0) or 0),
        },
        "topModels": [
            {
                "model": entry.get("model", ""),
                "calls": entry.get("calls", 0),
                "tokens": entry.get("tokens", 0),
            }
            for entry in (payload.get("top_models") or [])[:3]
        ],
    }
    write_json(cache_path, record)
    return record


def main():
    parser = argparse.ArgumentParser(description="Print multi-provider AI quota and activity from Sextant as one JSON record.")
    parser.add_argument(
        "--force",
        action="store_true",
        help="ignore caches and ask Sextant to re-poll; a person asking for fresh numbers overrules the reuse window",
    )
    args = parser.parse_args()

    global FORCE
    FORCE = args.force

    quota = fetch_quota()
    usage = fetch_usage()

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
