#!/usr/bin/env python3
"""Copy gate for LandlordHours: flags user-facing strings, never rewrites them.

  copy_gate.py check  [--root DIR] [--label NAME] [--out DIR] [--baseline REPORT.json] [--no-ai]
  copy_gate.py calibrate [--rerun]     score scripts/qa/copy_gate_calibration.json, write thresholds
  copy_gate.py extract [--root DIR]    print the extracted strings and what was skipped
  copy_gate.py l10n   [--root DIR] [--out DIR] [--show N]   non-localizable string patterns (deterministic, flag only)

Layer 1 is deterministic (banned words, straight apostrophes, Title Case labels). No AI.
Layer 2 asks TypeSafe Jev three things per string, in one request:
  plain_speech (Noul)  would a regular person say this out loud to a friend?
  tax_claim    (Noul)  does it claim or imply a tax status, or give tax advice?
  tone         (Choice) plain / jargon / salesy
Thresholds and the advisory-only marks come from copy_gate_calibration.json.

Fail-open: any Jev error makes that string "unchecked" in the report (counted, listed, never
dropped). Exit codes: 0 nothing flagged, 1 flagged, 2 some strings unchecked.
Stdlib only. Key: $TYPESAFE_API_KEY or ~/.config/typesafe/api_key (never printed).
"""
import argparse, hashlib, json, os, re, sys, time, urllib.error, urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
CAL_FILE = HERE / "copy_gate_calibration.json"
MODEL = "jev-latest"
URL = "https://api.typesafe.ai/v1/systemone"
PRICE_PER_TOK = 0.042 / 1e6  # USD per input token (docs/price seen in scripts/copy-gate/README.md)
CACHE_FILE = Path(os.environ.get("LH_COPY_GATE_CACHE",
                  Path.home() / "AgentScratch/landlordhours/copy-gate-cache.json"))
QUESTION_VERSION = "v1"
MD_LIMIT = 60

# ---------------------------------------------------------------- extraction

SKIP_FILE_RE = re.compile(r"(DebugSeed|Fixture|PreviewLaunchHook|/Preview|Mock)", re.I)
UI_CALLS = ("Text", "Label", "Button", "Toggle", "Section", "navigationTitle", "navigationBarTitle",
            "TextField", "SecureField", "Picker", "Link", "DisclosureGroup", "ContentUnavailableView",
            "LabeledContent", "Menu", "alert", "confirmationDialog", "accessibilityLabel",
            "accessibilityHint", "accessibilityValue", "help", "badge", "prompt", "placeholder",
            "String(localized", "LocalizedStringResource", "IntentDialog", "NSLocalizedString",
            "Tab", "tabItem", "TabItem", "Stepper", "DatePicker", "Slider", "ShareLink", "ProgressView",
            "UNNotificationAction", "AppShortcut", "Gauge")
LABEL_ARGS = ("title", "subtitle", "message", "body", "label", "text", "detail", "description", "caption",
              "headline", "placeholder", "prompt", "hint", "cta", "heading", "summary", "dialog",
              "confirmation", "emptyTitle", "emptyMessage", "footer", "header", "actionTitle", "buttonTitle")
UI_CALL_RE = re.compile(r"(?:\b(" + "|".join(re.escape(c) for c in UI_CALLS) + r")\(|\b(" +
                        "|".join(LABEL_ARGS) + r"):)\s*(?:\w+:\s*)?$")
LINE_SKIP_RE = re.compile(
    r"(\bprint\(|debugPrint\(|\bLogger\b|\blogger\.|os_log|\bNSLog\(|\bassert|precondition|fatalError|"
    r"#Preview|PreviewProvider|accessibilityIdentifier|systemName:|\bImage\(|forKey|UserDefaults|@AppStorage|"
    r"Notification\.Name|URL\(string|dateFormat|DateFormatter|NSPredicate|#selector|identifier:|subsystem:|"
    r"category:|\.id\(|\.tag\(|Color\(|\.font\(|CodingKeys|static let \w*(Key|ID|Id|Identifier)\b|"
    r"bundleIdentifier|launchArguments|ProcessInfo|\.symbolName|iconName|assetName|\.imageName|UIImage\(|"
    r"NSUbiquitous|\.contains\(\"|== \"|!= \"|hasPrefix|hasSuffix|\.replacingOccurrences|"
    r"extension\s+\w+\s*\{|PostHog|capture\(|Analytics|trackEvent|\.userInfo|storageKey|keyPath)")
IDENT_RE = re.compile(r"^[a-z][A-Za-z0-9_.\-/:#@]*$|^[A-Za-z0-9_]+\.[A-Za-z0-9_.]+$|^[A-Z0-9_]{4,}$|^https?:|^[/.~]")


def scan_swift(text):
    """Yield (offset, line_no, raw_text_with_{}, end_offset) for every string literal outside comments."""
    i, n, line = 0, len(text), 1
    out = []
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1; i += 1; continue
        if text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if text.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if text.startswith("/*", j): depth += 1; j += 2
                elif text.startswith("*/", j): depth -= 1; j += 2
                else:
                    if text[j] == "\n": line += 1
                    j += 1
            i = j; continue
        if c == '"':
            start, start_line = i, line
            multi = text.startswith('"""', i)
            j = i + (3 if multi else 1)
            buf = []
            while j < n:
                ch = text[j]
                if multi and text.startswith('"""', j):
                    j += 3; break
                if not multi and ch == '"':
                    j += 1; break
                if not multi and ch == "\n":
                    break  # unterminated; bail
                if ch == "\\" and j + 1 < n:
                    nx = text[j + 1]
                    if nx == "(":
                        depth, k = 1, j + 2
                        while k < n and depth:
                            if text[k] == "(": depth += 1
                            elif text[k] == ")": depth -= 1
                            elif text[k] == '"':  # nested literal inside interpolation
                                k += 1
                                while k < n and text[k] != '"':
                                    if text[k] == "\\": k += 1
                                    k += 1
                            elif text[k] == "\n": line += 1
                            k += 1
                        buf.append("{}"); j = k; continue
                    if nx == "u" and text.startswith("{", j + 2):
                        e = text.find("}", j + 2)
                        try:
                            buf.append(chr(int(text[j + 3:e], 16))); j = e + 1; continue
                        except ValueError:
                            pass
                    buf.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'"}.get(nx, nx))
                    j += 2; continue
                if ch == "\n": line += 1
                buf.append(ch); j += 1
            out.append((start, start_line, "".join(buf), j, multi))
            i = j; continue
        i += 1
    return out


def debug_lines(lines):
    """Set of 1-based line numbers inside `#if DEBUG` (the active branch)."""
    stack, dbg = [], set()
    for no, ln in enumerate(lines, 1):
        s = ln.strip()
        if s.startswith("#if"):
            stack.append(s.startswith("#if DEBUG") and "DEBUG" == s[3:].strip())
        elif s.startswith("#else") and stack:
            stack[-1] = False
        elif s.startswith("#endif") and stack:
            stack.pop(); continue
        if any(stack):
            dbg.add(no)
    return dbg


def extract_file(path, rel, skipped):
    text = path.read_text(errors="replace")
    lines = text.split("\n")
    dbg = debug_lines(lines)
    found = []
    for off, ln, s, end, multi in scan_swift(text):
        line_text = lines[ln - 1] if ln - 1 < len(lines) else ""
        col = off - (text.rfind("\n", 0, off) + 1)
        prefix = line_text[:col]
        ctx = prefix if prefix.strip() else (lines[ln - 2] if ln >= 2 else "")
        if not prefix.strip():
            ctx = (lines[ln - 2] if ln >= 2 else "") + " " + prefix
        m = UI_CALL_RE.search(ctx)
        kind = (m.group(1) or m.group(2)) if m else None
        if kind is None and re.search(r"\bcase\s+\w+\s*=\s*$", prefix) and s[:1].isupper():
            kind = "enum-display"  # capitalised raw values are shown to people
        s_clean = re.sub(r"\s+", " ", s).strip() if not multi else re.sub(r"[ \t]*\n[ \t]*", " ", s).strip()
        why = None
        if ln in dbg: why = "debug-block"
        elif not re.search(r"[A-Za-z]{2}", s_clean.replace("{}", "")): why = "no-words"
        elif LINE_SKIP_RE.search(line_text) and not kind: why = "code-context"
        elif IDENT_RE.match(s_clean): why = "identifier-like"
        elif kind is None:
            # not a known UI call: keep only prose (>=2 words, capital start or sentence punctuation)
            words = s_clean.split(" ")
            if len(words) < 2 or len(s_clean) < 8: why = "short-non-ui-literal"
            elif not (s_clean[0].isupper() or s_clean[0] in "{") and not re.search(r"[.!?,]", s_clean):
                why = "non-prose-literal"
            elif re.search(r"[%][@dfsl.0-9]*[@dfsl]", s_clean) and len(words) < 3:
                why = "format-string"
        if why:
            skipped.setdefault(why, []).append(f"{rel}:{ln}: {s_clean[:60]}")
            continue
        found.append({"file": rel, "line": ln, "text": s_clean, "kind": kind or "literal"})
    return found


def extract_plist(path, rel):
    out = []
    txt = path.read_text(errors="replace")
    for m in re.finditer(r"<key>(\w*UsageDescription)</key>\s*<string>(.*?)</string>", txt, re.S):
        line = txt.count("\n", 0, m.start(2)) + 1
        out.append({"file": rel, "line": line, "text": re.sub(r"\s+", " ", m.group(2)).strip(),
                    "kind": m.group(1)})
    return out


def extract_all(root):
    root = Path(root)
    skipped, items, skipped_files = {}, [], []
    for p in sorted((root / "Sources").rglob("*.swift")):
        rel = str(p.relative_to(root))
        if SKIP_FILE_RE.search(rel):
            skipped_files.append(rel); continue
        items += extract_file(p, rel, skipped)
    for p in sorted((root / "Sources").rglob("Info.plist")):
        items += extract_plist(p, str(p.relative_to(root)))
    for p in sorted((root / "Sources").rglob("*.xcstrings")):
        items += extract_xcstrings(p, str(p.relative_to(root)))
    return items, skipped, skipped_files


def extract_xcstrings(path, rel):
    """Source-language values of a String Catalog (e.g. the Learning center's article text)."""
    out = []
    raw = path.read_text(errors="replace")
    data = json.loads(raw)
    src = data.get("sourceLanguage", "en")
    for key, entry in data.get("strings", {}).items():
        unit = (entry.get("localizations", {}).get(src, {}) or {}).get("stringUnit", {})
        text = unit.get("value") or key
        if not re.search(r"[A-Za-z]{2}", text):
            continue
        line = raw.count("\n", 0, max(0, raw.find(json.dumps(key)))) + 1
        out.append({"file": rel, "line": line, "text": re.sub(r"\s+", " ", text).strip(), "kind": "catalog"})
    return out


# ------------------------------------------------------------ deterministic

BANNED = [
    (r"\bevidence\b", "evidence"),
    (r"\bqualif(?:y|ies|ied|ying)\b", "qualify/qualified"),
    (r"\baudit[- ]ready\b", "audit-ready"),
    (r"\bdefensible\b", "defensible"),
    (r"\btax[- ]ready\b", "tax-ready"),
    (r"\blandlord work\b", "landlord work"),
    (r"\bREPS goal\b", "REPS goal"),
    (r"\bTrack Time\b", "Track Time"),
]
SMALL = {"a", "an", "the", "of", "to", "and", "or", "for", "in", "on", "with", "at", "by", "from", "as", "is", "vs"}
PROPER = {"landlordhours", "pro", "apple", "icloud", "irs", "siri", "face", "touch", "id", "app", "store",
          "calendar", "photos", "files", "pdf", "csv", "ai", "reps", "mp", "ltr", "str", "cpa", "ios",
          "ipad", "iphone", "testflight", "wi-fi", "sign", "in", "google", "mail", "messages", "maps",
          "notes", "reminders", "siri", "shortcuts", "spotlight", "healthkit", "q1", "q2", "q3", "q4",
          "january", "february", "march", "april", "may", "june", "july", "august", "september",
          "october", "november", "december", "monday", "tuesday", "wednesday", "thursday", "friday",
          "saturday", "sunday", "self", "spouse", "i", "restore", "purchases", "ok", "today", "settings"}
LABEL_KINDS = {"Button", "Label", "navigationTitle", "navigationBarTitle", "Toggle", "Section", "Picker",
               "TextField", "Tab", "tabItem", "TabItem", "Menu", "UNNotificationAction", "LabeledContent",
               "Link", "DisclosureGroup", "ShareLink", "title", "label", "actionTitle", "buttonTitle",
               "Text", "AppShortcut", "heading", "enum-display", "literal"}


def deterministic(item):
    s, flags = item["text"], []
    for rx, name in BANNED:
        if re.search(rx, s, re.I if name != "Track Time" and name != "REPS goal" else 0):
            flags.append({"flag": f"banned: {name}", "p": 1.0, "source": "rule"})
    if item["kind"] in ("Button", "UNNotificationAction", "actionTitle", "buttonTitle") and \
            re.fullmatch(r"Not work", s, re.I):
        flags.append({"flag": 'banned: "Not work" as a button', "p": 1.0, "source": "rule"})
    if re.search(r"(?<=[A-Za-z])'(?=[A-Za-z])", s):
        flags.append({"flag": "straight apostrophe (use ’)", "p": 1.0, "source": "rule"})
    if item["kind"] in LABEL_KINDS and not item["kind"].endswith("UsageDescription"):
        words = [w for w in re.split(r"\s+", s) if w]
        if 2 <= len(words) <= 6 and not re.search(r"[.!?:]$", s) and "{}" not in s:
            caps = [w for w in words[1:] if w[0].isupper() and not w.isupper() and
                    w.lower().strip(",") not in PROPER and w.lower() not in SMALL and w[0].isalpha()]
            first_word_caps = words[0][0].isupper()
            if first_word_caps and caps and len(caps) == len([w for w in words[1:] if w.lower() not in SMALL
                                                              and w[0].isalpha() and not w.isupper()
                                                              and w.lower() not in PROPER]):
                flags.append({"flag": "Title Case label (use sentence case)", "p": 0.8, "source": "rule"})
    return flags


# ------------------------------------------------------------------- Jev

CONTEXT = ("The state is one piece of text shown to people in a phone app for rental property owners "
           "who log the hours they spend on their rentals for tax records. ")
QUESTIONS = {
    "plain_speech": {"type": "noul", "instructions": CONTEXT +
        "Would a regular person say this out loud to a friend, in everyday words? Short button and label text "
        "like 'Save' or 'Add property' counts as yes. Stiff office wording, legal or tax jargon, stacked "
        "clauses and marketing talk count as no.",
        "criteria": {"true": "Sounds like something a person would actually say, in short plain words.",
                     "false": "Sounds like a policy document, a legal notice, jargon, or a sales pitch."}},
    "tax_claim": {"type": "noul", "instructions": CONTEXT +
        "Does this text claim or imply that the user qualifies for a tax status, or give tax advice? Count: "
        "saying or implying the user will qualify, pass an audit, save on taxes or be accepted by the IRS; "
        "telling them what to do on their return. Do not count: plain descriptions of logging hours, "
        "exports for a tax professional, counting hours toward a number, or a note that the app does not give tax advice.",
        "criteria": {"true": "Promises or implies a tax status or outcome, or gives tax advice.",
                     "false": "Describes a feature or a record, or says the app does not decide or advise."}},
    "tone": {"type": "choice", "instructions": CONTEXT + "What is the tone of this text?",
        "criteria": {"plain": "Everyday words a person would say; short and clear.",
                     "jargon": "Technical, legal, tax or office wording that a regular person would not say.",
                     "salesy": "Marketing talk: hype, big promises, superlatives or pressure."}},
}
_stats = {"calls": 0, "tokens": 0, "errors": 0, "cached": 0, "model": None}
_cache = {}


def api_key():
    k = os.environ.get("TYPESAFE_API_KEY")
    return k.strip() if k else (Path.home() / ".config/typesafe/api_key").read_text().strip()


def load_cache():
    global _cache
    try: _cache = json.loads(CACHE_FILE.read_text())
    except Exception: _cache = {}


def save_cache():
    try:
        CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
        CACHE_FILE.write_text(json.dumps(_cache))
    except Exception: pass


def jev(text, key, retries=3):
    """Returns dict {plain_speech, tax_claim, tone:{plain,jargon,salesy}} or None on failure."""
    ck = hashlib.sha1(f"{QUESTION_VERSION}|{MODEL}|{text}".encode()).hexdigest()
    if ck in _cache:
        _stats["cached"] += 1
        return _cache[ck]
    body = json.dumps({"model": MODEL, "state": text, "questions": QUESTIONS}).encode()
    for attempt in range(retries):
        req = urllib.request.Request(URL, data=body, headers={
            "Authorization": f"Bearer {key}", "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=40) as r:
                j = json.load(r)
            a = j["answers"]
            res = {"plain_speech": float(a["plain_speech"]["noul"]), "tax_claim": float(a["tax_claim"]["noul"]),
                   "tone": {k: float(v) for k, v in a["tone"]["probabilities"].items()}}
            _stats["calls"] += 1
            _stats["tokens"] += j.get("usage", {}).get("input_tokens", 0)
            _stats["model"] = j.get("model")
            _cache[ck] = res
            return res
        except urllib.error.HTTPError as e:
            _stats["errors"] += 1
            if e.code in (429, 529): time.sleep(2 * (attempt + 1)); continue
            if e.code in (401, 422, 400): return None
            time.sleep(1.5 * (attempt + 1))
        except Exception:
            _stats["errors"] += 1
            time.sleep(1.5 * (attempt + 1))
    return None


def jev_many(texts, workers=6):
    key = api_key()
    load_cache()
    uniq = list(dict.fromkeys(texts))
    with ThreadPoolExecutor(max_workers=workers) as ex:
        res = dict(zip(uniq, ex.map(lambda t: jev(t, key), uniq)))
    save_cache()
    return res


# ------------------------------------------------------------- calibration

def cal_config():
    try: return json.loads(CAL_FILE.read_text()).get("config")
    except Exception: return None


def jev_flags(r, cfg):
    flags = []
    if cfg is None or r is None: return flags
    t = cfg
    p = r["plain_speech"]
    if 1 - p >= t["plain_speech"]["threshold"]:
        flags.append({"flag": "not plain speech", "p": round(1 - p, 3), "source": "jev",
                      "advisory": t["plain_speech"]["advisory"]})
    if r["tax_claim"] >= t["tax_claim"]["threshold"]:
        flags.append({"flag": "tax claim / tax advice", "p": round(r["tax_claim"], 3), "source": "jev",
                      "advisory": t["tax_claim"]["advisory"]})
    bad = 1 - r["tone"].get("plain", 0)
    if bad >= t["tone"]["threshold"]:
        lab = max(("jargon", "salesy"), key=lambda k: r["tone"].get(k, 0))
        flags.append({"flag": f"tone: {lab}", "p": round(bad, 3), "source": "jev",
                      "advisory": t["tone"]["advisory"]})
    return flags


def pick_threshold(pairs):
    """Best-accuracy cut; ties prefer more positives caught, then closeness to 0.5."""
    P = sum(1 for _, y in pairs if y)
    best = None
    for t in (0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9):
        tp = sum(1 for sc, y in pairs if y and sc >= t); tn = sum(1 for sc, y in pairs if not y and sc < t)
        fp = sum(1 for sc, y in pairs if not y and sc >= t); fn = P - tp
        acc = (tp + tn) / len(pairs)
        key = (round(acc, 3), tp / max(P, 1), -abs(t - 0.5))
        if best is None or key > best[0]: best = (key, t, tp, tn, fp, fn, acc)
    return best[1:]


def calibrate(rerun=False):
    data = json.loads(CAL_FILE.read_text())
    rows = data["rows"]
    res = jev_many([r["text"] for r in rows])
    if any(v is None for v in res.values()):
        print("calibration aborted: Jev errors; no thresholds written", file=sys.stderr); return 2
    out = {}
    for q in ("plain_speech", "tax_claim", "tone"):
        if q == "plain_speech":
            pairs = [(1 - res[r["text"]]["plain_speech"], r["plain"] is False) for r in rows]   # positive = bad copy
        elif q == "tax_claim":
            pairs = [(res[r["text"]]["tax_claim"], bool(r["tax_claim"])) for r in rows]
        else:
            pairs = [(1 - res[r["text"]]["tone"]["plain"], r["tone"] != "plain") for r in rows]
        P = sum(1 for _, y in pairs if y)
        t, tp, tn, fp, fn, acc = pick_threshold(pairs)
        # honest check: pick the threshold on every other row, score it on the rows it never saw
        fold = []
        for k in (0, 1):
            tr = [x for j, x in enumerate(pairs) if j % 2 == k]; te = [x for j, x in enumerate(pairs) if j % 2 != k]
            tk = pick_threshold(tr)[0]
            fold.append(sum(1 for sc, y in te if (sc >= tk) == y) / len(te))
        holdout = sum(fold) / 2
        at50 = sum(1 for sc, y in pairs if (sc >= 0.5) == y) / len(pairs)
        entry = {"threshold": t, "agreement": round(acc, 3), "agreement_at_0.5": round(at50, 3),
                 "holdout_agreement": round(holdout, 3), "tp": tp, "tn": tn, "fp": fp, "fn": fn, "n": len(pairs),
                 "advisory": min(acc, holdout) < 0.75}
        if q == "tone":  # also 3-way accuracy of the argmax choice
            ok = sum(1 for r in rows if max(res[r["text"]]["tone"], key=res[r["text"]]["tone"].get) == r["tone"])
            entry["three_way_accuracy"] = round(ok / len(rows), 3)
        out[q] = entry
    data["config"] = out
    data["model"] = _stats["model"] or MODEL
    data["calibrated_on"] = time.strftime("%Y-%m-%d")
    data["jev"] = {r["text"]: res[r["text"]] for r in rows}
    CAL_FILE.write_text(json.dumps(data, indent=1, ensure_ascii=False))
    for q, e in out.items():
        print(f"{q:13s} agreement {e['agreement']:.0%} (at 0.5: {e['agreement_at_0.5']:.0%}) "
              f"holdout {e['holdout_agreement']:.0%} threshold {e['threshold']}  tp/tn/fp/fn {e['tp']}/{e['tn']}/{e['fp']}/{e['fn']}"
              f"{'  ADVISORY-ONLY' if e['advisory'] else ''}")
    print(f"jev calls {_stats['calls']} cached {_stats['cached']} tokens {_stats['tokens']} "
          f"cost ~${_stats['tokens'] * PRICE_PER_TOK:.5f}")
    print("mismatches:")
    for r in rows:
        v = res[r["text"]]
        miss = []
        if (1 - v["plain_speech"] >= out["plain_speech"]["threshold"]) == r["plain"]: miss.append(f"plain={v['plain_speech']:.2f} label={r['plain']}")
        if (v["tax_claim"] >= out["tax_claim"]["threshold"]) != bool(r["tax_claim"]): miss.append(f"tax={v['tax_claim']:.2f} label={r['tax_claim']}")
        if ((1 - v["tone"]["plain"]) >= out["tone"]["threshold"]) != (r["tone"] != "plain"): miss.append(f"tone-plain={v['tone']['plain']:.2f} label={r['tone']}")
        if miss: print("  -", r["text"][:70], "|", "; ".join(miss))
    return 0


# ------------------------------------------------------------------ check

def rank_of(flags, solid):
    """Banned words first, then tax claims, then mechanical style, then plain-speech/tone (by probability)."""
    best = 0.0
    for f in flags:
        base = 0.0
        if f["flag"].startswith("banned"): base = 5
        elif f["flag"].startswith("tax claim"): base = 4 + f["p"]
        elif f["source"] == "rule": base = 3
        else: base = 1 + f["p"]
        if f.get("advisory"): base -= 0.5
        best = max(best, base)
    return round(best, 3)


def run_check(root, label, out_dir, baseline, no_ai):
    items, skipped, skipped_files = extract_all(root)
    cfg = cal_config()
    results = {}
    if not no_ai:
        results = jev_many([i["text"] for i in items])
    base_keys = set()
    if baseline:
        b = json.loads(Path(baseline).read_text())
        base_keys = {(f["file"], f["text"]) for f in b.get("all_strings", [])}
    findings, unchecked = [], []
    for it in items:
        flags = deterministic(it)
        r = results.get(it["text"]) if not no_ai else None
        if not no_ai:
            if r is None:
                unchecked.append(it)
            else:
                flags += jev_flags(r, cfg)
        it["new"] = (it["file"], it["text"]) not in base_keys if baseline else None
        if flags:
            solid = [f for f in flags if not f.get("advisory")]
            findings.append({**it, "flags": flags, "rank": rank_of(flags, solid), "jev": r})
    findings.sort(key=lambda f: (-f["rank"], f["file"], f["line"]))
    rep = {"label": label, "root": str(root), "strings_extracted": len(items), "findings": findings,
           "unchecked": unchecked, "skipped_counts": {k: len(v) for k, v in skipped.items()},
           "skipped_files": skipped_files,
           "skipped_samples": {k: v[:8] for k, v in skipped.items()},
           "jev": {"model": _stats["model"], "calls": _stats["calls"], "cached": _stats["cached"],
                   "errors": _stats["errors"], "input_tokens": _stats["tokens"],
                   "approx_cost_usd": round(_stats["tokens"] * PRICE_PER_TOK, 6),
                   "calibration": cfg},
           "all_strings": [{"file": i["file"], "line": i["line"], "text": i["text"]} for i in items]}
    out_dir = Path(out_dir); out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / f"{label}.json").write_text(json.dumps(rep, indent=1, ensure_ascii=False))
    (out_dir / f"{label}.md").write_text(render_md(rep, baseline is not None))
    n_flag = len(findings); n_unc = len(unchecked)
    print(f"{label}: {len(items)} strings, {n_flag} flagged, {n_unc} unchecked, "
          f"jev calls {_stats['calls']} (+{_stats['cached']} cached), ~${rep['jev']['approx_cost_usd']}")
    return 1 if n_flag else (2 if n_unc else 0)


def render_md(rep, has_base):
    L = [f"# Copy gate: {rep['label']}", "",
         f"{rep['strings_extracted']} strings extracted, {len(rep['findings'])} flagged, "
         f"{len(rep['unchecked'])} unchecked (Jev error, fail-open). Flags only; no rewrites.", ""]
    cfg = rep["jev"]["calibration"]
    if cfg:
        L.append("Jev questions: " + "; ".join(
            f"{q} thr {e['threshold']} agree {e['agreement']:.0%} (holdout {e['holdout_agreement']:.0%}){' ADVISORY' if e['advisory'] else ''}"
            for q, e in cfg.items()) + ". Advisory flags are marked (adv).")
        L.append("")
    def table(rows, title, limit=MD_LIMIT):
        if not rows: return
        groups = {}
        for f in rows: groups.setdefault(f["text"], []).append(f)
        ordered = sorted(groups.values(), key=lambda g: -g[0]["rank"])
        L.extend([f"## {title} ({len(ordered)} distinct strings)", "", "| file:line | string | flag | p |", "|---|---|---|---|"])
        for g in ordered[:limit]:
            f = g[0]
            where = f"{f['file'].replace('Sources/', '')}:{f['line']}" + (f" (+{len(g)-1})" if len(g) > 1 else "")
            flags = sorted(f["flags"], key=lambda x: -x["p"])
            s = f["text"].replace("|", "\\|")
            L.append(f"| {where} | {s[:110]} | " + "<br>".join(
                f"{fl['flag']}{' (adv)' if fl.get('advisory') else ''}" for fl in flags) + " | " +
                "<br>".join(f"{fl['p']:.2f}" for fl in flags) + " |")
        if len(ordered) > limit:
            L.append(f"\n_{len(ordered) - limit} more in the JSON._")
        L.append("")
    fnd = rep["findings"]
    if has_base:
        table([f for f in fnd if f["new"]], "New in this branch (vs baseline)")
        table([f for f in fnd if not f["new"]], "Already in baseline")
    else:
        rules = [f for f in fnd if any(x["source"] == "rule" for x in f["flags"])]
        ai = [f for f in fnd if f not in rules]
        table(rules, "Deterministic rule hits", 150)
        table(ai, "Jev flags (ranked by probability)")
    if rep["unchecked"]:
        L += ["## Unchecked by Jev", ""] + [f"- {u['file']}:{u['line']}: {u['text'][:100]}" for u in rep["unchecked"]] + [""]
    L += ["## Skipped by the extractor", "",
          ", ".join(f"{k}: {v}" for k, v in sorted(rep["skipped_counts"].items())) or "none"]
    if rep["skipped_files"]:
        L += ["", "Files skipped whole: " + ", ".join(rep["skipped_files"])]
    L += ["", "Not covered: strings built at runtime from non-literals, localised .strings files (.xcstrings source values are read) "
          "(none present), and App Store metadata (see scripts/copy-gate)."]
    j = rep["jev"]
    L += ["", f"Jev: model {j['model']}, {j['calls']} calls (+{j['cached']} cached), {j['input_tokens']} input tokens, "
          f"about ${j['approx_cost_usd']}, {j['errors']} errors."]
    return "\n".join(L) + "\n"


# ------------------------------------------------- non-localizable strings (l10n)

L10N_UI = r"(?:Text|Label|Button|Toggle|Section|Link|Picker|TextField|SecureField|Stepper|DatePicker|Menu|" \
          r"ShareLink|LabeledContent|ContentUnavailableView|navigationTitle|navigationBarTitle|alert|" \
          r"confirmationDialog|accessibilityLabel|accessibilityHint|accessibilityValue|badge|help|prompt)"
L10N_CALL = re.compile(r"\b" + L10N_UI + r"\s*\(")
L10N_VAR_DECL = re.compile(r'^\s*(?:(?:private|fileprivate|static|public|internal)\s+)*(?:let|var)\s+(\w+)\s*(?::\s*String)?\s*=\s*"((?:[^"\\]|\\.)*)"\s*$')
L10N_CONCAT = re.compile(r'"(?:[^"\\]|\\.)*"\s*\+\s*[\w(\[\.]|[\w)\]\.]\s*\+\s*"(?:[^"\\]|\\.)*"')
L10N_VERBATIM = re.compile(r'Text\(\s*verbatim:\s*"((?:[^"\\]|\\.)*)"')
L10N_TEXT_STRING = re.compile(r'Text\(\s*(?:String\(\s*(?:format:|describing:|localized:)?|"(?:[^"\\]|\\.)*"\s+as\s+String)')
PLIST_UI_KEYS = ("CFBundleDisplayName", "CFBundleName", "NSHumanReadableCopyright", "UIApplicationShortcutItemTitle",
                 "UIApplicationShortcutItemSubtitle", "CFBundleSpokenName")
PLIST_PAIR = re.compile(r"<key>(\w+)</key>\s*<string>([^<]*)</string>")


def has_words(t): return bool(re.search(r"[A-Za-z]{2,}", re.sub(r"\\\([^)]*\)", "", t)))


def l10n_scan(root):
    root = Path(root)
    items = []
    swift = [f for f in sorted((root / "Sources").rglob("*.swift")) if not SKIP_FILE_RE.search(str(f))]
    for f in swift:
        rel = str(f.relative_to(root))
        try: lines = f.read_text(errors="replace").splitlines()
        except OSError: continue
        text = "\n".join(lines)
        for i, L in enumerate(lines, 1):
            code = L.split("//")[0] if '"' not in L.split("//")[0][-1:] else L
            if "//" in L and L.strip().startswith("//"): continue
            m = L10N_VAR_DECL.match(code)
            if m and has_words(m.group(2)) and not IDENT_RE.match(m.group(2)) and " " in m.group(2).strip():
                name = m.group(1)
                used = re.search(r"\b" + L10N_UI + r"\s*\([^)\n]*(?<![\w.])" + re.escape(name) + r"\b(?!\s*:)", text)
                if used: items.append((rel, i, "string-var-in-ui", L.strip()[:110]))
            if L10N_CALL.search(code) and L10N_CONCAT.search(code):
                items.append((rel, i, "concatenation", L.strip()[:110]))
            m = L10N_VERBATIM.search(code)
            if m and has_words(m.group(1)) and not re.fullmatch(r"[\s\d\W]*(\\\([^)]*\)[\s\d\W]*)*", m.group(1)):
                items.append((rel, i, "text-verbatim-words", L.strip()[:110]))
            elif L10N_TEXT_STRING.search(code):
                items.append((rel, i, "text-from-String", L.strip()[:110]))
    for plist in sorted(root.rglob("Info.plist")):
        if any(x in plist.parts for x in ("build", ".build", "Pods", "DerivedData")): continue
        rel = str(plist.relative_to(root))
        xc = list(plist.parent.glob("InfoPlist.xcstrings")) + list(plist.parent.rglob("InfoPlist.strings"))
        txt = plist.read_text(errors="replace")
        for m in PLIST_PAIR.finditer(txt):
            k, v = m.groups()
            if (k.endswith("UsageDescription") or k in PLIST_UI_KEYS) and has_words(v) and not v.startswith("$("):
                ln = txt[:m.start()].count("\n") + 1
                items.append((rel, ln, "plist-literal" + ("" if not xc else "-has-xcstrings"), f"{k} = {v[:80]}"))
    return items


def l10n_main(root, out, show):
    items = l10n_scan(root)
    per = {}
    for rel, ln, kind, t in items: per.setdefault(rel, {}).setdefault(kind, []).append((ln, t))
    kinds = sorted({k for d in per.values() for k in d})
    has_xc = bool(list(Path(root).rglob("InfoPlist.xcstrings")))
    L = [f"# copy_gate l10n: {root}", "",
         f"{len(items)} non-localizable pattern(s) in {len(per)} file(s). InfoPlist.xcstrings present: {'yes' if has_xc else 'NO'}. "
         "Flags only; nothing rewritten. Regex heuristics: confirm each by eye.", "",
         "| file | total | " + " | ".join(kinds) + " |", "|---|---|" + "---|" * len(kinds)]
    for rel, d in sorted(per.items(), key=lambda kv: -sum(len(v) for v in kv[1].values())):
        L.append(f"| {rel} | {sum(len(v) for v in d.values())} | " + " | ".join(str(len(d.get(k, []))) for k in kinds) + " |")
    L += ["", "Totals by pattern: " + ", ".join(f"{k} {sum(len(d.get(k, [])) for d in per.values())}" for k in kinds), ""]
    if show:
        for rel, d in sorted(per.items(), key=lambda kv: -sum(len(v) for v in kv[1].values())):
            L.append(f"## {rel}")
            for k, v in d.items():
                for ln, t in v[:show]: L.append(f"- {k} :{ln}  `{t}`")
            L.append("")
    md = "\n".join(L) + "\n"
    outd = Path(out); outd.mkdir(parents=True, exist_ok=True)
    (outd / "l10n_report.md").write_text(md)
    (outd / "l10n_report.json").write_text(json.dumps([dict(file=r, line=l, kind=k, text=t) for r, l, k, t in items], indent=1))
    print("\n".join(L[:len(per) + 9 if not show else 12 + len(per)]))
    print(f"-> {outd}/l10n_report.md")
    return 1 if items else 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check")
    c.add_argument("--root", default=str(REPO)); c.add_argument("--label", default="report")
    c.add_argument("--out", default="."); c.add_argument("--baseline"); c.add_argument("--no-ai", action="store_true")
    c.add_argument("--strict", action="store_true", help="unchecked strings fail the run (exit 1)")
    sub.add_parser("calibrate")
    l = sub.add_parser("l10n")
    l.add_argument("--root", default=str(REPO)); l.add_argument("--out", default=".")
    l.add_argument("--show", type=int, default=0, help="list up to N example lines per file and pattern")
    e = sub.add_parser("extract"); e.add_argument("--root", default=str(REPO))
    a = ap.parse_args()
    if a.cmd == "calibrate": return calibrate()
    if a.cmd == "l10n": return l10n_main(a.root, a.out, a.show)
    if a.cmd == "extract":
        items, skipped, sf = extract_all(a.root)
        for i in items: print(f"{i['file']}:{i['line']}\t{i['kind']}\t{i['text']}")
        print(f"# {len(items)} extracted; skipped {({k: len(v) for k, v in skipped.items()})}; files {sf}", file=sys.stderr)
        return 0
    rc = run_check(a.root, a.label, a.out, a.baseline, a.no_ai)
    return 1 if (rc == 2 and a.strict) else rc


if __name__ == "__main__":
    sys.exit(main())
