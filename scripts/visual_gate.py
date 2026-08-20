#!/usr/bin/env python3
"""
visual_gate.py — Visual QA review gate for the LandlordHours iOS app (ported from Handly/poker).

Sends one or more app-frame screenshots to multiple vision-capable LLMs via
the OpenRouter REST API and asks each one to critique the frame against
LandlordHours' design system rules (see repo CLAUDE.md).

Usage:
    python3 scripts/visual_gate.py IMAGE [IMAGE ...] \
        [--tier new|regate] [--models MODEL_ID,MODEL_ID] \
        [--context "scene description"] [--no-cache] [--allow-degraded]
    python3 scripts/visual_gate.py --history FRAME_NAME

Model tiering (Brian's decision, 2026-08-12):
    regate  moonshotai/kimi-k3 only — single-model runs for re-gates of
            surfaces the gate has judged before.
    new     kimi-k3 + qwen/qwen3-vl-235b-a22b-instruct as a cheap
            corroborator for never-seen surfaces (replaces the retired
            gemini-3.1-pro-preview slot).
    An explicit --tier always wins. Otherwise the tier is chosen from the
    verdict log: if EVERY input frame's content SHA-256 already appears in
    docs/qa-artifacts/visual-gate-verdicts.jsonl the run defaults to
    "regate"; any never-seen frame defaults the WHOLE run to "new". The
    chosen tier and the reason are always printed. --models still overrides
    the model set entirely (tier is then recorded as "custom").

Blocker corroboration policy:
    - Single-model run: one model's BLOCKER-level FLAG stands — overall
      BLOCKER, exit 1 (unchanged fail-closed semantics).
    - Multi-model run, EVERY model raises a BLOCKER-level FLAG: overall
      BLOCKER, exit 1.
    - Multi-model run, only SOME models raise it (including the surviving
      model of an --allow-degraded DEGRADED run): the frame is labelled
      NEEDS-MEASUREMENT instead of BLOCKER — still exit 1, but the label
      tells the triager corroboration was absent, so the finding should be
      pixel-measured rather than taken as confirmed.
    - DEGRADED handling is unchanged: a partial-model failure without
      --allow-degraded is exit 2 (verdict unknown), never a pass.

Requires OPENROUTER_API_KEY in the environment. Uses `requests` if
available, otherwise falls back to urllib from the stdlib.

Exit codes (the contract other tooling should key off of):
    0 = clean PASS — every frame got a full verdict from all required
        models and none raised a BLOCKER.
    1 = BLOCKER FOUND — at least one model raised a BLOCKER-level finding
        on at least one frame, and every frame's verdict is otherwise
        fully known (no errors, no unresolved DEGRADED frames).
    2 = GATE ERROR — the verdict is UNKNOWN and must be treated as NOT
        PASSED. Causes: missing/empty OPENROUTER_API_KEY, empty frame
        list, a frame path that doesn't exist, every model call erroring
        for a frame, a DEGRADED frame (partial model failure) without
        --allow-degraded, or an OpenRouter balance too low to safely
        complete the batch. This is deliberately distinct from exit 1 so
        a broken harness (dead key, outage, empty balance) can never be
        mistaken for a clean pass.

Persistence & caching:
    Every judged frame (cache hit or fresh) is appended as one JSON
    record to docs/qa-artifacts/visual-gate-verdicts.jsonl. Full model
    critique text is never written there — it goes to a run directory
    under /Volumes/Home/tmp/landlordhours-gates/visual/<run-timestamp>/, whose
    path is recorded in the JSONL line. Fresh judgements are cached by
    exact file-byte SHA-256 (+ context + model set + prompt version) at
    /Volumes/Home/tmp/landlordhours-gates/visual/cache/ — cache hits cost $0 and
    print CACHED. Caching is exact-match only; a perceptual dhash is
    computed and recorded for trend/near-match reporting only and never
    used to decide a cache hit (see NEAR_MATCH_DHASH_THRESHOLD).
"""

import argparse
import base64
import hashlib
import json
import mimetypes
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

try:
    import requests  # type: ignore
    HAVE_REQUESTS = True
except ImportError:
    HAVE_REQUESTS = False

OPENROUTER_BASE = "https://openrouter.ai/api/v1"
# Model tiers (Brian's decision 2026-08-12). Across the 1.6 train,
# gemini-3.1-pro-preview produced ~10 pixel-disproved false blockers vs 2
# unique real catches, so the Pro corroborator slot was retired. Re-gates of
# known surfaces run Kimi K3 alone; never-seen surfaces keep a second opinion
# from a cheap different-family vision model (Qwen3-VL 235B A22B instruct:
# $0.26/M in, $1.04/M out vs Gemini Pro's $2/$12 — roughly a tenth the price,
# strong GUI/screenshot grounding, non-thinking variant so it doesn't burn
# the token budget on hidden reasoning).
TIER_MODELS = {
    "regate": ["moonshotai/kimi-k3"],
    "new": ["moonshotai/kimi-k3", "qwen/qwen3-vl-235b-a22b-instruct"],
}
MAX_TOKENS = 1200
TEMPERATURE = 0.2

REVIEWER_PROMPT = (
    "You are a strict visual QA reviewer for 'LandlordHours', an iOS app that helps "
    "landlords track hours toward IRS Real Estate Professional Status (REPS) and "
    "Material Participation qualification. Design language: Tiimo-inspired, soft, "
    "rounded, friendly, modern; DM Serif Display for headers/titles, DM Sans for body. "
    "Supports light and dark themes via AdaptiveColors — a dark background is a "
    "legitimate theme variant on a dark-theme frame, never a violation on its own. "
    "Color-intent rules (violations of these ARE findings): violet/action "
    "(~#7C6FF7 light / ~#9D8FF5 dark) is the primary action/brand color for CTAs, "
    "toggles-on, links, selected nav; sage/positive/green (~#34D399 / #059669) is "
    "reserved ONLY for success, qualified, complete, goal-met, active-Pro states — "
    "never for ordinary continue/add/save/toggle actions; honey/caution (~#FBBF24) "
    "means warning/needs-attention; coral/destructive (~#F472B6) means delete/error; "
    "sky/informational (~#60A5FA) means imports/sync/neutral info. Cards use white "
    "(light) or near-black secondary surface (dark) backgrounds with rounded corners "
    "(8/12/16/20pt scale) and generous padding (~20px). Review this app frame for: "
    "(a) layout defects — overlapping elements, clipped or truncated text, "
    "collapsed/tiny text, elements colliding with screen edges or each other, "
    "misalignment, inconsistent row heights/padding/corner radii vs adjacent "
    "sections in the same frame; (b) legibility — insufficient contrast on the "
    "given theme's background, type too small, caption text hard to read; "
    "(c) hierarchy — competing focal points, primary action/toggle state unclear; "
    "(d) consistency — components that break the design system (wrong radius, "
    "stray hardcoded colors, wrong icon style, a toggle or badge using the wrong "
    "semantic color per the intent rules above); (e) dark-mode correctness — any "
    "light-theme token bleeding into a dark frame (e.g. light-mode surface color, "
    "wrong text contrast); (f) anything reading as unfinished, placeholder, or "
    "broken. For each finding give: element, location in frame, why it violates, "
    "severity (BLOCKER / MINOR / NIT). Simulator status bars and device bezels are "
    "not findings. End with exactly one line: 'VERDICT: PASS' or "
    "'VERDICT: FLAG — <one-line reason>'."
)
# Bump this whenever REVIEWER_PROMPT's substantive content changes (not for
# typo fixes). Persisted/cached verdicts are only comparable to each other
# within the same promptVersion — the JSONL and cache both key on it so a
# prompt change can never silently reuse a verdict judged under old rules.
PROMPT_VERSION = "landlordhours-visual-gate-v1"

# --- Fail-closed cost/budget knobs -----------------------------------------
# Conservative per-model-call estimate used only for the pre-flight budget
# check (refuse to start rather than run out of balance mid-batch). With the
# two default models this comes to ~$0.10/frame, matching observed spend.
COST_PER_MODEL_CALL_ESTIMATE_USD = 0.05
LOW_BALANCE_WARN_THRESHOLD_USD = 5.0

# --- Persistence / cache locations -----------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)  # scripts -> repo root
JSONL_PATH = os.path.join(REPO_ROOT, "docs", "qa-artifacts", "visual-gate-verdicts.jsonl")
GATES_TMP_ROOT = "/Volumes/Home/tmp/landlordhours-gates/visual"
CACHE_DIR = os.path.join(GATES_TMP_ROOT, "cache")

# Perceptual-hash distance (0-64 bits) below which a fresh frame is flagged
# as a near-match of a prior run, purely as an informational note. This is
# NEVER used to short-circuit judgement — only exact SHA-256 does that.
NEAR_MATCH_DHASH_THRESHOLD = 10
DHASH_SIZE = 8


def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


def fail_closed(reason, exit_code=2):
    """Print the unmissable fail-closed banner to both stdout and stderr and exit.

    exit 2 is reserved for "verdict unknown" harness errors, which must
    never be mistaken for exit 0 (pass) by anything scraping this script's
    output or exit code.
    """
    msg = f"GATE ERROR — verdict unknown, treat as NOT PASSED. ({reason})"
    print(msg)
    eprint(msg)
    sys.exit(exit_code)


def get_api_key():
    key = os.environ.get("OPENROUTER_API_KEY")
    if not key:
        fail_closed("OPENROUTER_API_KEY is not set (or empty) in the environment")
    return key


def image_to_data_url(path):
    mime, _ = mimetypes.guess_type(path)
    if not mime:
        mime = "image/png"
    with open(path, "rb") as f:
        raw = f.read()
    b64 = base64.b64encode(raw).decode("ascii")
    return f"data:{mime};base64,{b64}"


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def compute_dhash(path, hash_size=DHASH_SIZE):
    """Perceptual difference-hash, reporting/trend only — see module docstring."""
    try:
        from PIL import Image  # lazy import: dhash is optional, script must run without Pillow
    except ImportError:
        eprint("[warn] Pillow not installed — dhash unavailable for this frame "
               "(cache correctness and BLOCKER detection are unaffected).")
        return None
    try:
        with Image.open(path) as img:
            img = img.convert("L").resize((hash_size + 1, hash_size), Image.LANCZOS)
            # Pillow >= 12 deprecates getdata() in favor of get_flattened_data();
            # fall back for older Pillow that doesn't have the new method yet.
            if hasattr(img, "get_flattened_data"):
                pixels = list(img.get_flattened_data())
            else:
                pixels = list(img.getdata())
            bits = []
            for row in range(hash_size):
                row_start = row * (hash_size + 1)
                for col in range(hash_size):
                    left = pixels[row_start + col]
                    right = pixels[row_start + col + 1]
                    bits.append("1" if left > right else "0")
            bitstring = "".join(bits)
            nibble_len = (hash_size * hash_size + 3) // 4
            return f"{int(bitstring, 2):0{nibble_len}x}"
    except Exception as e:
        eprint(f"[warn] dhash computation failed for {path}: {e}")
        return None


def hamming_distance_hex(hex1, hex2):
    if not hex1 or not hex2:
        return None
    try:
        v1, v2 = int(hex1, 16), int(hex2, 16)
        return bin(v1 ^ v2).count("1")
    except Exception:
        return None


def git_sha():
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=REPO_ROOT, capture_output=True, text=True, timeout=10, check=True,
        )
        return out.stdout.strip() or "unknown"
    except Exception:
        return "unknown"


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def http_post_json(url, headers, payload, timeout=90):
    """POST JSON via requests if available, else urllib. Returns (status, parsed_json_or_None, raw_text)."""
    body = json.dumps(payload).encode("utf-8")
    if HAVE_REQUESTS:
        try:
            resp = requests.post(url, headers=headers, data=body, timeout=timeout)
            text = resp.text
            try:
                parsed = resp.json()
            except Exception:
                parsed = None
            return resp.status_code, parsed, text
        except requests.RequestException as e:
            return None, None, str(e)
    else:
        req = urllib.request.Request(url, data=body, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                text = resp.read().decode("utf-8")
                status = resp.getcode()
        except urllib.error.HTTPError as e:
            text = e.read().decode("utf-8", errors="replace")
            status = e.code
        except urllib.error.URLError as e:
            return None, None, str(e)
        try:
            parsed = json.loads(text)
        except Exception:
            parsed = None
        return status, parsed, text


def http_get_json(url, headers, timeout=30):
    if HAVE_REQUESTS:
        try:
            resp = requests.get(url, headers=headers, timeout=timeout)
            try:
                return resp.status_code, resp.json()
            except Exception:
                return resp.status_code, None
        except requests.RequestException as e:
            return None, str(e)
    else:
        req = urllib.request.Request(url, headers=headers, method="GET")
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                text = resp.read().decode("utf-8")
                status = resp.getcode()
        except urllib.error.HTTPError as e:
            return e.code, None
        except urllib.error.URLError as e:
            return None, str(e)
        try:
            return status, json.loads(text)
        except Exception:
            return status, None


def get_remaining_credits(api_key):
    """Returns remaining USD balance (float), or None if the endpoint couldn't be read."""
    headers = {"Authorization": f"Bearer {api_key}"}
    status, parsed = http_get_json(f"{OPENROUTER_BASE}/credits", headers)
    if status != 200 or not parsed:
        return None
    try:
        data = parsed["data"]
        return float(data["total_credits"]) - float(data["total_usage"])
    except Exception:
        return None


def probe(api_key, models):
    """One cheap text-only call to confirm auth + endpoint work."""
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    # Generous max_tokens: some reviewer models (e.g. kimi-k3) are reasoning
    # models that spend tokens on hidden reasoning before emitting content —
    # too small a budget cuts them off mid-reasoning with content=null.
    payload = {
        "model": models[0],
        "messages": [{"role": "user", "content": "Reply with exactly: OK"}],
        "max_tokens": 30,
        "temperature": 0,
        "reasoning": {"effort": "minimal"},
    }
    print(f"[probe] sending tiny text-only ping to {models[0]} ...")
    status, parsed, raw = http_post_json(f"{OPENROUTER_BASE}/chat/completions", headers, payload)
    if status != 200 or not parsed:
        fail_closed(f"auth probe failed — status={status} raw={raw[:300] if isinstance(raw, str) else raw}")
    try:
        message = parsed["choices"][0]["message"]
        content = message.get("content")
        if not content:
            # Reasoning model cut off before emitting content — fall back to
            # the reasoning field just to prove the round-trip worked.
            content = message.get("reasoning") or "(empty content, but request succeeded)"
    except Exception:
        fail_closed(f"auth probe returned unexpected response shape: {parsed}")
    print(f"[probe] OK — auth + endpoint confirmed. Model replied: {content.strip()!r}\n")


def call_model(api_key, model, image_data_url, prompt_text):
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }

    def build_payload(max_tokens):
        return {
            "model": model,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt_text},
                        {"type": "image_url", "image_url": {"url": image_data_url}},
                    ],
                }
            ],
            "max_tokens": max_tokens,
            "temperature": TEMPERATURE,
            # Some reviewer models (e.g. kimi-k3) are
            # hidden-reasoning models that will burn a large chunk — or the
            # entire — max_tokens budget on invisible reasoning before/instead
            # of emitting the visible critique. Capping effort to "minimal"
            # keeps more of the budget for the actual answer. Models that
            # don't support this field simply ignore it.
            "reasoning": {"effort": "minimal"},
            # Ask OpenRouter to report actual USD cost in usage.cost so we
            # can print real spend instead of only the pre-flight estimate.
            "usage": {"include": True},
        }

    last_error = None
    current_max_tokens = MAX_TOKENS
    for attempt in (1, 2):
        status, parsed, raw = http_post_json(
            f"{OPENROUTER_BASE}/chat/completions", headers, build_payload(current_max_tokens)
        )
        if status == 200 and parsed:
            try:
                message = parsed["choices"][0]["message"]
                content = message.get("content")
                finish_reason = parsed["choices"][0].get("finish_reason")
                usage = parsed.get("usage", {})
                if not content:
                    # Hidden-reasoning model burned the whole budget on
                    # invisible reasoning and returned content=null.
                    reasoning = message.get("reasoning")
                    last_error = (
                        f"empty content (finish_reason={finish_reason}); "
                        f"reasoning_snippet={str(reasoning)[:200]!r}"
                    )
                elif finish_reason == "length":
                    # Got SOME content but it was cut off mid-critique —
                    # hidden reasoning tokens ate an unpredictable share of
                    # the budget this call. Don't silently accept a partial
                    # critique; retry once with a much larger budget.
                    last_error = (
                        f"truncated (finish_reason=length) at max_tokens={current_max_tokens}; "
                        f"got {len(content)} chars of content: {content[:150]!r}..."
                    )
                else:
                    cost = usage.get("cost") if isinstance(usage, dict) else None
                    return {"ok": True, "content": content, "usage": usage, "cost": cost}
            except Exception as e:
                last_error = f"unexpected response shape: {e} — raw={str(parsed)[:500]}"
        else:
            snippet = raw[:500] if isinstance(raw, str) else str(raw)[:500]
            last_error = f"status={status} raw={snippet}"
        if attempt == 1:
            current_max_tokens = MAX_TOKENS * 3
            eprint(
                f"  [{model}] attempt 1 failed ({last_error[:200]}), "
                f"retrying once with max_tokens={current_max_tokens}..."
            )
            time.sleep(2)
    return {"ok": False, "error": last_error}


def count_blockers(critique_text):
    """Count actual BLOCKER-severity findings, not prose mentions of the word.

    Models format the per-finding severity tag inconsistently in practice —
    "Severity: BLOCKER", "**BLOCKER.**" as a trailing sentence, "(BLOCKER)",
    etc. — so we can't require a "severity" keyword nearby without risking
    false negatives (missing a real blocker). Instead we count every bare
    "BLOCKER" token and only exclude ones immediately preceded by a negation
    qualifier (no/zero/none/without/not — e.g. a closing remark like "all
    MINOR, no blockers" must NOT count as a finding).
    """
    text = critique_text
    count = 0
    for m in re.finditer(r"\bBLOCKERS?\b", text, re.IGNORECASE):
        start = m.start()
        window_start = max(0, start - 25)
        preceding_lower = text[window_start:start].lower()

        # Skip negated mentions: "no blocker(s)", "zero blockers",
        # "not a blocker", "without any blockers", etc.
        if re.search(r"\b(no|zero|none|without|not)\b[^.\n]{0,20}$", preceding_lower):
            continue

        # Skip near-miss qualifiers where the finding's own severity is lower:
        # "approaches BLOCKER", "borderline BLOCKER", "nearly/almost/short of".
        if re.search(r"\b(approach(?:es|ing)?|borderline|near(?:ly)?|almost|short of|close to|verging on)\b[^.\n]{0,20}$", preceding_lower):
            continue

        # Skip mentions inside a finding explicitly tagged at a lower severity
        # on the same line ("Severity: MINOR ... approaches BLOCKER given ...").
        line_start = text.rfind("\n", 0, start) + 1
        line_so_far = text[line_start:start].upper()
        if "SEVERITY: MINOR" in line_so_far or "SEVERITY: NIT" in line_so_far:
            continue

        count += 1
    return count


def extract_verdict(critique_text):
    for line in critique_text.splitlines():
        stripped = line.strip()
        if stripped.upper().startswith("VERDICT:"):
            return stripped
    # Fallback: search anywhere in text
    upper = critique_text.upper()
    if "VERDICT: FLAG" in upper or "VERDICT:FLAG" in upper:
        return "VERDICT: FLAG — (verdict line not cleanly formatted; FLAG detected in text)"
    if "VERDICT: PASS" in upper or "VERDICT:PASS" in upper:
        return "VERDICT: PASS (verdict line not cleanly formatted)"
    return "VERDICT: UNKNOWN (no verdict line found)"


def resolve_tier(explicit_tier, frame_shas, history_shas):
    """Pick the model tier for this run. Returns (tier, reason).

    explicit_tier : value of --tier, or None. An explicit flag always wins.
    frame_shas    : list of (basename, content_sha256) for every input frame.
    history_shas  : set of every contentSha256 ever recorded in the verdict
                    log (docs/qa-artifacts/visual-gate-verdicts.jsonl).

    Smart default: if every frame's exact content SHA already appears in the
    verdict history, the whole run is a re-gate ("regate", Kimi only); a
    single never-seen frame flips the WHOLE run to "new" (corroborated).
    """
    if explicit_tier:
        return explicit_tier, f"--tier {explicit_tier} was passed explicitly"
    unseen = sorted({name for name, sha in frame_shas if sha not in history_shas})
    if unseen:
        return "new", (
            f"{len(unseen)} of {len(frame_shas)} frame(s) have a content SHA never seen "
            f"in the verdict log ({', '.join(unseen[:5])}) — whole run gets a corroborator"
        )
    return "regate", "every frame's content SHA-256 already appears in the verdict log"


def decide_frame_verdict(model_records, num_models, allow_degraded):
    """Apply the blocker corroboration policy to one frame's model records.

    Returns (overall, unknown): overall is one of PASS / BLOCKER /
    NEEDS-MEASUREMENT / DEGRADED / ERROR; unknown=True means the frame's
    verdict is unresolved and the gate must fail closed (exit 2).

    Policy (see module docstring): a BLOCKER stands when the run is
    single-model, or when EVERY model of a multi-model run raises one. A
    blocker raised by only some models of a multi-model run (including the
    surviving model of an --allow-degraded DEGRADED run) is downgraded to
    NEEDS-MEASUREMENT — still a gate failure (exit 1), but labelled so the
    triager knows corroboration was absent.
    """
    n_ok = sum(1 for m in model_records if m["status"] == "OK")
    flagging = [
        m for m in model_records
        if m["status"] == "OK" and m.get("verdictLine")
        and "FLAG" in m["verdictLine"].upper() and (m.get("blockerCount") or 0) > 0
    ]
    if n_ok == 0:
        return "ERROR", True
    if n_ok < num_models and not allow_degraded:
        return "DEGRADED", True
    if not flagging:
        return "PASS", False
    if num_models == 1 or len(flagging) == num_models:
        return "BLOCKER", False
    return "NEEDS-MEASUREMENT", False


def verify_models_support_image(api_key, models):
    """Check the /models endpoint's architecture.input_modalities for each chosen model."""
    headers = {"Authorization": f"Bearer {api_key}"}
    status, parsed = http_get_json(f"{OPENROUTER_BASE}/models", headers)
    if status != 200 or not parsed:
        eprint(f"[warn] could not verify model list (status={status}); proceeding without verification.")
        return
    by_id = {m["id"]: m for m in parsed.get("data", [])}
    for model in models:
        m = by_id.get(model)
        if not m:
            eprint(f"[warn] model {model!r} not found in /models listing; proceeding anyway.")
            continue
        modalities = m.get("architecture", {}).get("input_modalities", [])
        if "image" not in modalities:
            eprint(f"[warn] model {model!r} does not advertise image input support (modalities={modalities}).")
        else:
            print(f"[check] {model} supports image input (modalities={modalities}).")


# --- Cache -------------------------------------------------------------------

def compute_cache_key(content_sha256, context, models, prompt_version):
    material = "|".join([
        content_sha256,
        context or "",
        ",".join(sorted(models)),
        prompt_version,
    ])
    return hashlib.sha256(material.encode("utf-8")).hexdigest()


def cache_entry_path(key):
    return os.path.join(CACHE_DIR, f"{key}.json")


def load_cache_entry(key):
    path = cache_entry_path(key)
    if not os.path.isfile(path):
        return None
    try:
        with open(path, "r") as f:
            return json.load(f)
    except Exception as e:
        eprint(f"[warn] failed to read cache entry {path}: {e} — treating as a miss.")
        return None


def save_cache_entry(key, entry):
    os.makedirs(CACHE_DIR, exist_ok=True)
    path = cache_entry_path(key)
    tmp_path = path + f".tmp{os.getpid()}"
    with open(tmp_path, "w") as f:
        json.dump(entry, f, indent=2)
    os.replace(tmp_path, path)


# --- JSONL verdict persistence ------------------------------------------------

def append_verdict_record(record):
    os.makedirs(os.path.dirname(JSONL_PATH), exist_ok=True)
    with open(JSONL_PATH, "a") as f:
        f.write(json.dumps(record) + "\n")


def read_verdict_records():
    if not os.path.isfile(JSONL_PATH):
        return []
    records = []
    with open(JSONL_PATH, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except Exception:
                continue
    return records


def print_history(frame_name):
    target = os.path.basename(frame_name)
    records = [r for r in read_verdict_records() if r.get("frame") == target]
    if not records:
        print(f"No prior verdicts recorded for frame {target!r} in {JSONL_PATH}.")
        return
    records.sort(key=lambda r: r.get("timestamp", ""))
    print(f"History for {target} — {len(records)} record(s) from {JSONL_PATH}:")
    for r in records:
        cost = r.get("estimatedCostUsd")
        cost_str = f"${cost:.4f}" if isinstance(cost, (int, float)) else "$?"
        print(
            f"  {r.get('timestamp')}  sha={r.get('gitSha')}  "
            f"verdict={r.get('overallVerdict')}  cached={r.get('cached')}  "
            f"cost={cost_str}  promptVersion={r.get('promptVersion')}"
        )
        for m in r.get("models", []):
            print(
                f"      - {m.get('model')}: {m.get('status')} "
                f"blockers={m.get('blockerCount')} :: {m.get('verdictLine')}"
            )


# --- Near-match reporting (informational only — never gates cache hits) ------

def print_near_match_note(frame_basename, new_dhash, prior_records):
    if not new_dhash:
        return
    candidates = [
        r for r in prior_records
        if r.get("frame") == frame_basename and r.get("dhash")
    ]
    if not candidates:
        return
    candidates.sort(key=lambda r: r.get("timestamp", ""), reverse=True)
    latest = candidates[0]
    dist = hamming_distance_hex(new_dhash, latest.get("dhash"))
    if dist is not None and 0 < dist <= NEAR_MATCH_DHASH_THRESHOLD:
        print(
            f"[info] near-match of {frame_basename} (dhash distance {dist}) vs run at "
            f"{latest.get('timestamp')} — re-judging (cache is exact-match only, never fuzzy)."
        )


def build_arg_parser():
    parser = argparse.ArgumentParser(
        description="LandlordHours visual-consistency review gate (fails closed; caches by exact byte hash).",
    )
    parser.add_argument("images", nargs="*", help="Path(s) to image file(s) to review.")
    parser.add_argument("--models", default=None, help="Comma-separated OpenRouter model IDs (overrides tier selection; tier recorded as 'custom').")
    parser.add_argument(
        "--tier", choices=("new", "regate"), default=None,
        help="Model tier: 'regate' = Kimi K3 only (re-gates of known surfaces); "
             "'new' = Kimi K3 + Qwen3-VL corroborator (never-seen surfaces). "
             "Default: chosen automatically from verdict-log history — regate if every "
             "frame's content SHA has been judged before, otherwise new. "
             "Ignored when --models is passed.",
    )
    parser.add_argument("--context", default=None, help="Extra scene context to append to the reviewer prompt.")
    parser.add_argument(
        "--history", metavar="FRAME_NAME", default=None,
        help="Print prior verdicts for a frame (matched by filename) from the JSONL log and exit. "
             "No model calls, no billing.",
    )
    parser.add_argument(
        "--no-cache", action="store_true",
        help="Force a fresh judgement for every frame, ignoring any cached verdict.",
    )
    parser.add_argument(
        "--allow-degraded", action="store_true",
        help="If one model errors while another succeeds for a frame, accept the surviving "
             "model's verdict instead of failing closed (exit 2). Off by default: every model "
             "in the run's tier is required for a frame to count as a known verdict. In a "
             "multi-model run an accepted surviving model's blocker is labelled "
             "NEEDS-MEASUREMENT (uncorroborated), still exit 1.",
    )
    return parser


def main():
    parser = build_arg_parser()
    args = parser.parse_args()

    if args.history:
        print_history(args.history)
        sys.exit(0)

    if not args.images:
        fail_closed("no frame paths were provided")

    for path in args.images:
        if not os.path.isfile(path):
            fail_closed(f"frame path does not exist: {path}")

    api_key = get_api_key()
    prior_records = read_verdict_records()

    # --- Hash frames first: tier selection keys off verdict-log history ----
    frame_hashes = [(os.path.basename(p), sha256_file(p)) for p in args.images]

    # --- Resolve tier + model set -------------------------------------------
    if args.models:
        models = [m.strip() for m in args.models.split(",") if m.strip()]
        tier = "custom"
        tier_reason = "--models overrides tier-based model selection"
    else:
        history_shas = {r["contentSha256"] for r in prior_records if r.get("contentSha256")}
        tier, tier_reason = resolve_tier(args.tier, frame_hashes, history_shas)
        models = list(TIER_MODELS[tier])
    if not models:
        fail_closed("resolved model list is empty")

    prompt_text = REVIEWER_PROMPT
    if args.context:
        prompt_text = prompt_text + "\n\nScene context: " + args.context

    print("=" * 78)
    print("LandlordHours Visual Consistency Gate")
    print(f"Tier: {tier} — {tier_reason}")
    print(f"Models: {', '.join(models)}  |  promptVersion={PROMPT_VERSION}")
    print(f"Images: {', '.join(args.images)}")
    print("=" * 78 + "\n")

    # --- Resolve cache status for every frame up front --------------------
    frame_infos = []
    for path, (_basename, content_sha256) in zip(args.images, frame_hashes):
        dhash_val = compute_dhash(path)
        key = compute_cache_key(content_sha256, args.context, models, PROMPT_VERSION)
        cached_entry = None if args.no_cache else load_cache_entry(key)
        frame_infos.append({
            "path": path,
            "basename": os.path.basename(path),
            "content_sha256": content_sha256,
            "dhash": dhash_val,
            "cache_key": key,
            "cached_entry": cached_entry,
        })

    misses = [f for f in frame_infos if f["cached_entry"] is None]

    # --- Budget gate (fail closed) -----------------------------------------
    if misses:
        remaining = get_remaining_credits(api_key)
        if remaining is None:
            fail_closed("could not confirm OpenRouter balance from /credits before a billable batch")
        estimated_cost = len(misses) * len(models) * COST_PER_MODEL_CALL_ESTIMATE_USD
        print(
            f"[budget] remaining balance: ${remaining:.2f}  |  "
            f"estimated cost of this batch: ${estimated_cost:.2f} "
            f"({len(misses)} frame(s) x {len(models)} model(s) x "
            f"${COST_PER_MODEL_CALL_ESTIMATE_USD:.2f}/call)"
        )
        if estimated_cost > remaining:
            fail_closed(
                f"estimated batch cost ${estimated_cost:.2f} exceeds remaining balance ${remaining:.2f}"
            )
        if remaining < LOW_BALANCE_WARN_THRESHOLD_USD:
            print(f"[budget] WARNING: remaining balance is under ${LOW_BALANCE_WARN_THRESHOLD_USD:.2f} — refill soon.")
        print()
    else:
        print("[budget] every frame served from cache — $0.00 spend, balance not checked.\n")

    run_dir = None
    if misses:
        verify_models_support_image(api_key, models)
        print()
        probe(api_key, models)
        run_slug = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        run_dir = os.path.join(GATES_TMP_ROOT, run_slug)
        os.makedirs(run_dir, exist_ok=True)

    sha = git_sha()
    any_unknown = False
    any_blocker = False
    any_needs_measurement = False
    run_spend_usd = 0.0
    frame_lines = []      # compact per-frame stdout lines
    blocker_digest = []   # lines for the blocker digest section

    for info in frame_infos:
        path = info["path"]
        basename = info["basename"]

        if info["cached_entry"] is not None:
            entry = info["cached_entry"]
            overall = entry.get("overallVerdict", "UNKNOWN")
            total_blockers = sum(m.get("blockerCount", 0) or 0 for m in entry.get("models", []))
            frame_lines.append(f"CACHED   · {basename} · {overall} · blockers={total_blockers} · $0.0000")
            if overall in ("BLOCKER", "NEEDS-MEASUREMENT"):
                any_blocker = True
                if overall == "NEEDS-MEASUREMENT":
                    any_needs_measurement = True
                for m in entry.get("models", []):
                    if (m.get("blockerCount") or 0) > 0:
                        tag = " (uncorroborated)" if overall == "NEEDS-MEASUREMENT" else ""
                        blocker_digest.append(f"  {basename} [{m.get('model')}]{tag}: {m.get('verdictLine')}")
            elif overall not in ("PASS",):
                # A cached DEGRADED/ERROR entry (shouldn't normally be cached,
                # but be defensive) is still an unknown verdict on replay.
                any_unknown = True

            record = dict(entry)
            record["timestamp"] = now_iso()
            record["gitSha"] = sha
            record["tier"] = tier
            record["modelIds"] = list(models)
            record["cached"] = True
            record["estimatedCostUsd"] = 0.0
            append_verdict_record(record)
            continue

        # Fresh judgement.
        print_near_match_note(basename, info["dhash"], prior_records)
        data_url = image_to_data_url(path)

        model_records = []
        frame_spend = 0.0
        for model in models:
            print("-" * 78)
            print(f"FRAME: {basename}  MODEL: {model}")
            print("-" * 78)
            result = call_model(api_key, model, data_url, prompt_text)
            if not result["ok"]:
                print(f"ERRORED: {result['error']}\n")
                model_records.append({
                    "model": model, "status": "ERRORED", "error": result["error"],
                    "blockerCount": None, "verdictLine": None, "costUsd": 0.0,
                })
                continue

            content = result["content"]
            verdict_line = extract_verdict(content)
            blockers = count_blockers(content)
            cost = result.get("cost")
            if not isinstance(cost, (int, float)):
                cost = COST_PER_MODEL_CALL_ESTIMATE_USD
            frame_spend += cost
            print(f"{verdict_line}  (blockers={blockers}, cost=${cost:.4f})\n")

            if run_dir:
                critique_path = os.path.join(run_dir, f"{basename}__{model.replace('/', '_')}.txt")
                with open(critique_path, "w") as cf:
                    cf.write(content)
            else:
                critique_path = None

            model_records.append({
                "model": model, "status": "OK", "blockerCount": blockers,
                "verdictLine": verdict_line, "costUsd": cost,
                "critiquePath": critique_path,
            })

        run_spend_usd += frame_spend

        n_blockers_total = sum((m.get("blockerCount") or 0) for m in model_records if m["status"] == "OK")
        overall, unknown = decide_frame_verdict(model_records, len(models), args.allow_degraded)
        if unknown:
            any_unknown = True

        if overall in ("BLOCKER", "NEEDS-MEASUREMENT"):
            any_blocker = True
            if overall == "NEEDS-MEASUREMENT":
                any_needs_measurement = True
            for m in model_records:
                if m["status"] == "OK" and (m.get("blockerCount") or 0) > 0:
                    tag = " (uncorroborated)" if overall == "NEEDS-MEASUREMENT" else ""
                    blocker_digest.append(f"  {basename} [{m['model']}]{tag}: {m['verdictLine']}")

        label = overall
        errored_models = [m["model"] for m in model_records if m["status"] == "ERRORED"]
        suffix = f" ({', '.join(errored_models)} ERRORED)" if errored_models else ""
        frame_lines.append(
            f"{label:<8} · {basename} · blockers={n_blockers_total} · ${frame_spend:.4f}{suffix}"
        )

        # Only cache a frame whose verdict is fully known (all models OK) —
        # a DEGRADED/ERROR result must never become the permanent cached
        # answer for these bytes.
        if overall in ("PASS", "BLOCKER", "NEEDS-MEASUREMENT"):
            cache_entry = {
                "frame": basename,
                "framePath": os.path.abspath(path),
                "contentSha256": info["content_sha256"],
                "dhash": info["dhash"],
                "context": args.context,
                "models": model_records,
                "overallVerdict": overall,
                "tier": tier,
                "modelIds": list(models),
                "promptVersion": PROMPT_VERSION,
                "originalTimestamp": now_iso(),
                "originalGitSha": sha,
                "critiqueDir": run_dir,
            }
            save_cache_entry(info["cache_key"], cache_entry)

        record = {
            "timestamp": now_iso(),
            "gitSha": sha,
            "frame": basename,
            "framePath": os.path.abspath(path),
            "contentSha256": info["content_sha256"],
            "dhash": info["dhash"],
            "context": args.context,
            "models": model_records,
            "overallVerdict": overall,
            "tier": tier,
            "modelIds": list(models),
            "cached": False,
            "estimatedCostUsd": frame_spend,
            "promptVersion": PROMPT_VERSION,
            "critiqueDir": run_dir,
        }
        append_verdict_record(record)

    # --- Compact summary ----------------------------------------------------
    print("=" * 78)
    print("SUMMARY")
    print("=" * 78)
    for line in frame_lines:
        print(line)

    if blocker_digest:
        print("\nBLOCKER DIGEST:")
        for line in blocker_digest:
            print(line)

    print()
    if run_dir:
        print(f"Full critiques: {run_dir}")
    print(f"Verdict log:    {JSONL_PATH}")

    if misses:
        final_remaining = get_remaining_credits(api_key)
        remaining_str = f"${final_remaining:.2f}" if final_remaining is not None else "unknown"
        print(f"[cost] spent this run: ${run_spend_usd:.4f}  |  balance remaining: {remaining_str}")

    print()
    if any_unknown:
        fail_closed("one or more frames have an unresolved verdict (all-models-errored, or DEGRADED without --allow-degraded)")
    if any_blocker:
        msg = "GATE RESULT: FAIL — at least one model flagged a BLOCKER-level Screen Law violation."
        if any_needs_measurement:
            msg += ("\nAt least one finding is NEEDS-MEASUREMENT: raised by only one model of a "
                    "multi-model run — corroboration was absent; pixel-measure before trusting it.")
        print(msg)
        sys.exit(1)
    print("GATE RESULT: PASS — no model raised a BLOCKER-level FLAG, and every frame's verdict is fully known.")
    sys.exit(0)


if __name__ == "__main__":
    main()
