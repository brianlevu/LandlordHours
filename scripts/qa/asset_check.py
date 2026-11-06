#!/usr/bin/env python3
"""asset_check.py - the CRAFT house asset contract (standard H.3, NOTES-standard-v2.md item 4).

  python3 scripts/qa/asset_check.py [--xcassets Assets.xcassets/Craft] [--clips Sources/Resources/Craft]
                                    [--allow-png] [--allow-future] [--lamp-box x0,y0,x1,y1] [--json out.json]

Prints one line per check and exits 1 on any FAIL or BLOCKED (fails closed: a missing folder, an unreadable image or an
undecodable clip is BLOCKED, never a pass).
  stages      started, frame70, framing, half, complete each have imagesets craft_<stage> and craft_<stage>-unlit with an
              Any and a Dark entry at 3x universal, and craft_thumb_<stage> with Any/Dark at 2x and 3x
  files       format HEIC (PNG only with --allow-png), 1206x1206 stills, 240 (2x) and 360 (3x) thumbs, an alpha channel,
              <= 450 KB per still, <= 40 KB per thumb, <= 10 MB of stills, <= 14 MB for the whole set (clips included)
  clips       present, HEVC tagged hvc1, 60 frames at 30 fps, <= 1.5 MB (alpha cannot be confirmed through ffprobe: INFO)
  hashes      sha256(lit) != sha256(unlit) and sha256(Any) != sha256(Dark) per stage
  camera pin  opaque bbox left and right edges within +-4 px across all 20 stills; lowest opaque row at 92% +-1% of 1206
  fringe      edge pixels (alpha 0.1-0.9): luminance within 10% of the mean of the opaque pixels around them; a still
              FAILS when more than 2% of its edge pixels are off; the worst 5 are printed
  clip ends   first frame vs craft_frame70 and last frame vs craft_framing: mean dE <= 2 over the opaque house pixels
              (lamp box excluded with --lamp-box); ffmpeg returns no alpha, so only pixels opaque in the still are compared
  reserved    no craft_slots_*, craft_*_build_* or second style prefix (anything else starting craft_ outside the contract)
              until section F.1 is built; --allow-future turns this off
Conservative readings: the 2% fringe tolerance, "Dark entry" = an appearances luminosity dark image, HEIC is decoded with sips.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

STAGES = ["started", "frame70", "framing", "half", "complete"]
STILL_PX, THUMB_PX = 1206, {"2x": 240, "3x": 360}
STILL_MAX_KB, THUMB_MAX_KB = 450, 40
STILLS_MAX_MB, SET_MAX_MB, CLIP_MAX_MB = 10, 14, 1.5
PIN_PX, GROUND = 4, (0.91, 0.93)
FRINGE_BAD_SHARE, FRINGE_TOL = 0.02, 0.10
CLIP_DE = 2.0


class Report:
    def __init__(self):
        self.rows = []

    def add(self, rule, verdict, detail):
        self.rows.append(dict(rule=rule, verdict=verdict, detail=detail))

    @property
    def bad(self):
        return [r for r in self.rows if r["verdict"] in ("FAIL", "BLOCKED")]


def sha(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def imageset_entries(setdir):
    """[(filename, scale, dark)] from Contents.json."""
    try:
        with open(os.path.join(setdir, "Contents.json")) as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None
    out = []
    for im in data.get("images", []):
        dark = any(a.get("appearance") == "luminosity" and a.get("value") == "dark" for a in im.get("appearances", []))
        out.append((im.get("filename"), im.get("scale"), dark, im.get("idiom")))
    return out


def load_rgba(path):
    """RGBA numpy array; HEIC through sips. Raises ValueError when unreadable."""
    p, tmp = path, None
    try:
        if path.lower().endswith((".heic", ".heif")):
            if not shutil.which("sips"):
                raise ValueError("sips not available to decode HEIC")
            tmp = tempfile.mkdtemp(prefix="asset-check-")
            p = os.path.join(tmp, "x.png")
            r = subprocess.run(["sips", "-s", "format", "png", path, "--out", p], capture_output=True, text=True)
            if r.returncode != 0 or not os.path.exists(p):
                raise ValueError("sips could not decode " + os.path.basename(path))
        with Image.open(p) as im:
            has_alpha = im.mode in ("RGBA", "LA", "PA") or "transparency" in im.info
            return np.asarray(im.convert("RGBA")), has_alpha, im.size
    except (OSError, ValueError) as e:
        raise ValueError(f"{os.path.basename(path)}: {e}")
    finally:
        if tmp:
            shutil.rmtree(tmp, ignore_errors=True)


def fringe(rgba):
    """(share of edge pixels off by > 10%, worst 5 [(y, x, deviation)])."""
    a = rgba[..., 3].astype(np.float64) / 255
    rgb = rgba[..., :3].astype(np.float64) / 255
    lum = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
    edge = (a > 0.1) & (a < 0.9)
    if not edge.any():
        return 0.0, []
    opaque = (a >= 0.9).astype(np.float64)

    def box(x, r=2):
        c = np.pad(x, r)
        k = 2 * r + 1
        cs = c.cumsum(0).cumsum(1)
        cs = np.pad(cs, ((1, 0), (1, 0)))
        return cs[k:, k:] - cs[:-k, k:] - cs[k:, :-k] + cs[:-k, :-k]
    num, den = box(opaque * lum), box(opaque)
    ys, xs = np.nonzero(edge & (den > 0))
    if len(ys) == 0:
        return 0.0, []
    mean = num[ys, xs] / den[ys, xs]
    dev = np.abs(lum[ys, xs] - mean) / np.maximum(mean, 0.02)
    order = np.argsort(-dev)[:5]
    return float((dev > FRINGE_TOL).mean()), [(int(ys[i]), int(xs[i]), round(float(dev[i]), 3)) for i in order]


def opaque_box(rgba):
    m = rgba[..., 3] > 127
    if not m.any():
        return None
    ys, xs = np.nonzero(m)
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def rgb_lab(a):
    c = a.astype(np.float64) / 255
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    m = np.array([[0.4124564, 0.3575761, 0.1804375], [0.2126729, 0.7151522, 0.0721750], [0.0193339, 0.1191920, 0.9503041]])
    xyz = c @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], axis=-1)


def check(xcassets, clips_dir, allow_png=False, allow_future=False, lamp_box=None):
    R = Report()
    if not os.path.isdir(xcassets):
        R.add("assets", "BLOCKED", f"{xcassets} does not exist")
        return R
    sets = {d[:-9]: os.path.join(xcassets, d) for d in sorted(os.listdir(xcassets)) if d.endswith(".imageset")}
    wanted = {}
    for st in STAGES:
        wanted[f"craft_{st}"] = ("still", st, "lit")
        wanted[f"craft_{st}-unlit"] = ("still", st, "unlit")
        wanted[f"craft_thumb_{st}"] = ("thumb", st, "lit")
    files = {}  # (name, variant) -> path ; variant like "any3x" / "dark3x"
    for name, (kind, st, state) in wanted.items():
        if name not in sets:
            R.add("stages", "FAIL", f"missing imageset {name}")
            continue
        ent = imageset_entries(sets[name])
        if ent is None:
            R.add("stages", "BLOCKED", f"{name}: unreadable Contents.json")
            continue
        scales = ["3x"] if kind == "still" else ["2x", "3x"]
        for sc in scales:
            for dark in (False, True):
                hit = [e for e in ent if e[1] == sc and e[2] == dark and e[3] in ("universal", None)]
                if not hit or not hit[0][0]:
                    R.add("stages", "FAIL", f"{name}: no {'Dark' if dark else 'Any'} entry at {sc} universal")
                    continue
                path = os.path.join(sets[name], hit[0][0])
                if not os.path.exists(path):
                    R.add("stages", "FAIL", f"{name}: {hit[0][0]} listed but missing")
                    continue
                files[(name, ("dark" if dark else "any") + sc)] = path
    if not any(r["rule"] == "stages" for r in R.rows):
        R.add("stages", "PASS", f"{len(wanted)} imagesets, every Any/Dark entry present")

    # reserved names
    if not allow_future:
        known = set(wanted)
        odd = [n for n in sets if n.startswith("craft") and n not in known]
        slots = [n for n in odd if re.match(r"craft_slots_|craft_.*_build_", n)]
        R.add("reserved", "FAIL" if odd else "PASS",
              f"reserved or unknown names present: {odd} (slots/build: {slots}); section F.1 is not built yet" if odd else "none")

    # per-file contract
    arr, total_still, total_all, bad = {}, 0, 0, []
    for (name, var), path in sorted(files.items()):
        kind = wanted[name][0]
        ext = os.path.splitext(path)[1].lower()
        size = os.path.getsize(path)
        total_all += size
        if kind == "still":
            total_still += size
        if ext not in (".heic", ".png") or (ext == ".png" and not allow_png):
            bad.append(f"{name}/{var}: format {ext} (HEIC expected{', PNG needs --allow-png' if ext == '.png' else ''})")
        lim = (STILL_MAX_KB if kind == "still" else THUMB_MAX_KB) * 1024
        if size > lim:
            bad.append(f"{name}/{var}: {size // 1024} KB > {lim // 1024} KB")
        try:
            rgba, has_alpha, (w, h) = load_rgba(path)
        except ValueError as e:
            R.add("files", "BLOCKED", str(e))
            continue
        want = STILL_PX if kind == "still" else THUMB_PX[var[-2:]]
        if (w, h) != (want, want):
            bad.append(f"{name}/{var}: {w}x{h}, want {want}x{want}")
        if not has_alpha:
            bad.append(f"{name}/{var}: no alpha channel")
        arr[(name, var)] = rgba
    if not any(r["rule"] == "files" and r["verdict"] == "BLOCKED" for r in R.rows) and files:
        R.add("files", "FAIL" if bad else "PASS", "; ".join(bad[:12]) + (f" (+{len(bad) - 12} more)" if len(bad) > 12 else "")
              if bad else f"{len(files)} files: format, size, alpha and byte budgets OK")
    R.add("budget stills", "PASS" if total_still <= STILLS_MAX_MB * 2 ** 20 else "FAIL", f"{total_still / 2 ** 20:.1f} MB of {STILLS_MAX_MB} MB")

    # clips
    clips = []
    if clips_dir and os.path.isdir(clips_dir):
        clips = sorted(os.path.join(clips_dir, f) for f in os.listdir(clips_dir) if f.lower().endswith((".mov", ".mp4")))
    if not clips:
        R.add("clips", "FAIL", f"no .mov/.mp4 clip found in {clips_dir}")
    for c in clips:
        total_all += os.path.getsize(c)
        pr = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-count_frames", "-show_entries",
                             "stream=codec_name,codec_tag_string,nb_read_frames,r_frame_rate,pix_fmt", "-of", "json", c],
                            capture_output=True, text=True) if shutil.which("ffprobe") else None
        if pr is None or pr.returncode != 0:
            R.add("clips", "BLOCKED", f"{os.path.basename(c)}: ffprobe unavailable or failed")
            continue
        s = (json.loads(pr.stdout).get("streams") or [{}])[0]
        probs = []
        if s.get("codec_name") != "hevc" or s.get("codec_tag_string") != "hvc1":
            probs.append(f"codec {s.get('codec_name')}/{s.get('codec_tag_string')}, want hevc/hvc1")
        if s.get("nb_read_frames") != "60":
            probs.append(f"{s.get('nb_read_frames')} frames, want 60")
        if s.get("r_frame_rate") != "30/1":
            probs.append(f"{s.get('r_frame_rate')} fps, want 30")
        if os.path.getsize(c) > CLIP_MAX_MB * 2 ** 20:
            probs.append(f"{os.path.getsize(c) / 2 ** 20:.2f} MB > {CLIP_MAX_MB} MB")
        R.add("clips", "FAIL" if probs else "PASS", f"{os.path.basename(c)}: " + ("; ".join(probs) if probs else "hevc hvc1, 60 frames, 30 fps, within budget"))
    R.add("budget set", "PASS" if total_all <= SET_MAX_MB * 2 ** 20 else "FAIL", f"{total_all / 2 ** 20:.1f} MB of {SET_MAX_MB} MB")
    R.add("clip alpha", "INFO", "ffprobe cannot confirm HEVC-with-alpha; confirm with AVAssetTrack or a device capture")

    # hashes
    hb = []
    for st in STAGES:
        for sc in ("any3x", "dark3x"):
            a_, b_ = files.get((f"craft_{st}", sc)), files.get((f"craft_{st}-unlit", sc))
            if a_ and b_ and sha(a_) == sha(b_):
                hb.append(f"{st} {sc}: lit == unlit")
        a_, b_ = files.get((f"craft_{st}", "any3x")), files.get((f"craft_{st}", "dark3x"))
        if a_ and b_ and sha(a_) == sha(b_):
            hb.append(f"{st}: Any == Dark")
    R.add("hashes", "FAIL" if hb else "PASS", "; ".join(hb) if hb else "lit != unlit and Any != Dark for every stage")

    # camera pin, fringe (stills at 3x)
    stills = {k: v for k, v in arr.items() if wanted[k[0]][0] == "still"}
    if stills:
        boxes = {k: opaque_box(v) for k, v in stills.items()}
        miss = [f"{k[0]}/{k[1]}" for k, b in boxes.items() if b is None]
        ok = {k: b for k, b in boxes.items() if b}
        pin = []
        if ok:
            lefts, rights = [b[0] for b in ok.values()], [b[2] for b in ok.values()]
            if max(lefts) - min(lefts) > 2 * PIN_PX:
                pin.append(f"left edge spread {max(lefts) - min(lefts)} px (allowed +-{PIN_PX} about the median)")
            if max(rights) - min(rights) > 2 * PIN_PX:
                pin.append(f"right edge spread {max(rights) - min(rights)} px")
            for k, b in ok.items():
                g = b[3] / STILL_PX
                if not (GROUND[0] <= g <= GROUND[1]):
                    pin.append(f"{k[0]}/{k[1]}: lowest opaque row at {g:.3f} of 1206 (want {GROUND[0]}-{GROUND[1]})")
        if miss:
            pin.append("fully transparent: " + ", ".join(miss))
        R.add("camera pin", "FAIL" if pin else "PASS", "; ".join(pin[:8]) if pin else f"{len(ok)} stills pinned within +-{PIN_PX} px, ground at 92%")
        worst_all, bad_fr = [], []
        for k, v in stills.items():
            share, worst = fringe(v)
            worst_all += [(d, f"{k[0]}/{k[1]} ({x},{y})") for y, x, d in worst]
            if share > FRINGE_BAD_SHARE:
                bad_fr.append(f"{k[0]}/{k[1]}: {share:.1%} of edge pixels off by > 10%")
        worst_all.sort(reverse=True)
        R.add("fringe", "FAIL" if bad_fr else "PASS",
              ("; ".join(bad_fr[:6]) if bad_fr else "alpha edges match the adjacent opaque luminance") +
              " | worst 5: " + ", ".join(f"{n} {d:.0%}" for d, n in worst_all[:5]))

    # clip ends
    for c in clips if shutil.which("ffmpeg") else []:
        app = "dark" if "dark" in os.path.basename(c).lower() else "any"
        for which, ref_name, sel in (("first", "craft_frame70", "select=eq(n\\,0)"), ("last", "craft_framing", "select=eq(n\\,59)")):
            ref = arr.get((ref_name, app + "3x"))
            if ref is None:
                R.add("clip ends", "BLOCKED", f"{os.path.basename(c)} {which}: no {ref_name} {app} still")
                continue
            tmp = tempfile.mkdtemp(prefix="asset-clip-")
            try:
                out = os.path.join(tmp, "f.png")
                r = subprocess.run(["ffmpeg", "-v", "error", "-i", c, "-vf", sel, "-frames:v", "1", out], capture_output=True)
                if r.returncode != 0 or not os.path.exists(out):
                    R.add("clip ends", "BLOCKED", f"{os.path.basename(c)} {which}: cannot decode a frame")
                    continue
                fr = np.asarray(Image.open(out).convert("RGB").resize((ref.shape[1], ref.shape[0])))
            finally:
                shutil.rmtree(tmp, ignore_errors=True)
            mask = ref[..., 3] >= 250
            if lamp_box:
                x0, y0, x1, y1 = [int(v * ref.shape[1 if i % 2 == 0 else 0]) for i, v in enumerate(lamp_box)]
                mask[y0:y1, x0:x1] = False
            if not mask.any():
                R.add("clip ends", "BLOCKED", f"{ref_name}: no opaque pixels")
                continue
            de = np.linalg.norm(rgb_lab(fr[mask]) - rgb_lab(ref[..., :3][mask]), axis=1).mean()
            R.add("clip ends", "PASS" if de <= CLIP_DE else "FAIL", f"{os.path.basename(c)} {which} frame vs {ref_name}: mean dE {de:.2f} (max {CLIP_DE})")
    return R


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--xcassets", default="Assets.xcassets/Craft")
    ap.add_argument("--clips", default="Sources/Resources/Craft")
    ap.add_argument("--allow-png", action="store_true")
    ap.add_argument("--allow-future", action="store_true")
    ap.add_argument("--lamp-box", help="x0,y0,x1,y1 frame fractions excluded from the clip-end comparison")
    ap.add_argument("--json")
    a = ap.parse_args(argv)
    lamp = [float(v) for v in a.lamp_box.split(",")] if a.lamp_box else None
    R = check(a.xcassets, a.clips, a.allow_png, a.allow_future, lamp)
    for r in R.rows:
        print(f"{r['verdict']:8} {r['rule']}: {r['detail']}")
    if a.json:
        json.dump(R.rows, open(a.json, "w"), indent=1)
    print(f"asset_check: {len(R.bad)} FAIL/BLOCKED", file=sys.stderr)
    return 1 if R.bad else 0


if __name__ == "__main__":
    sys.exit(main())
