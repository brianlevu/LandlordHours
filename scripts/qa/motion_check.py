#!/usr/bin/env python3
"""motion_check.py - the signature motion of the log flow, measured from a screen capture (standard H.6, 5.1 item 10).

  python3 scripts/qa/motion_check.py VIDEO.mp4 [--lot x0,y0,x1,y1] [--window-box x0,y0,x1,y1]
                                     [--crossfades START:DUR,...] [--sheet-dismiss T] [--scene-start T]
                                     [--reduce-motion] [--json out.json] [--series]

Decodes a 30 fps CFR capture with ffmpeg (grayscale, the lot region only) and prints, per frame, the mean luma of the
lot and the number of pixels that changed since the previous frame ("t:luma/changed", the dir-craft-final2 method).
  drop_frames   longest run of consecutive frames with >= 40 changed pixels in the lot            PASS >= 24
  hard_cuts     frames whose lot mean luma steps > 25% from the previous frame, outside the two crossfade windows
                (clip-in 0.20 s from the start of the drop run, clip-out 0.30 s from its end; override with
                --crossfades) and the sheet dismiss (--sheet-dismiss T, +-0.3 s)                   PASS 0
  windows_fade  after the drop run ends, the luma of --window-box (frame fractions) rises monotonically for 9-14
                frames (0.30-0.47 s)                                                               PASS present
                with --reduce-motion (or a name containing -rm): the drop run must be ABSENT and the fade linear
  order         drop end < windows start; with --scene-start also scene start >= windows end + 0.5 s
Every check fails closed: no video, no frames, no --window-box = BLOCKED. Exit 1 on any FAIL or BLOCKED.
Needs ffmpeg and numpy. Conservative readings: "changed" is |delta| > 6/255; the default lot is x 0-1, y 0.10-0.55.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys

import numpy as np

CHANGED_MIN = 40       # pixels that must change for a frame to count as moving
PIXEL_DELTA = 6        # |delta| of 8-bit luma that counts as a changed pixel
DROP_MIN_FRAMES = 24
HARD_CUT = 0.25
FADE_FRAMES = (9, 14)
CLIP_IN, CLIP_OUT = 0.20, 0.30


def frac_box(s, default):
    return [float(v) for v in s.split(",")] if s else list(default)


def decode(path, box, fps=30):
    """Gray frames of the box region as an (n, h, w) uint8 array. Fails closed (ValueError) on any decode problem."""
    if shutil.which("ffmpeg") is None or shutil.which("ffprobe") is None:
        raise ValueError("ffmpeg/ffprobe not installed")
    if not os.path.exists(path):
        raise ValueError(f"no such file {path}")
    pr = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height,r_frame_rate",
                         "-of", "csv=p=0", path], capture_output=True, text=True)
    try:
        w, h, rate = pr.stdout.strip().split(",")
        w, h = int(w), int(h)
        num, den = rate.split("/")
        src_fps = float(num) / float(den)
    except ValueError:
        raise ValueError(f"unreadable video: {pr.stderr.strip() or pr.stdout.strip()}")
    x0, y0, x1, y1 = box
    cw, ch = max(2, int((x1 - x0) * w)) // 2 * 2, max(2, int((y1 - y0) * h)) // 2 * 2
    vf = f"crop={cw}:{ch}:{int(x0 * w)}:{int(y0 * h)}"
    if abs(src_fps - fps) > 0.5:
        vf = f"fps={fps}," + vf  # a VFR / odd-rate capture is resampled; the report says so
    p = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-vf", vf, "-pix_fmt", "gray", "-f", "rawvideo", "-"],
                       capture_output=True)
    if p.returncode != 0 or not p.stdout:
        raise ValueError("ffmpeg decode failed: " + p.stderr.decode(errors="replace")[:200])
    n = len(p.stdout) // (cw * ch)
    return np.frombuffer(p.stdout[: n * cw * ch], np.uint8).reshape(n, ch, cw), src_fps


def longest_run(flags):
    best = (0, 0, -1)  # length, start, end
    i = 0
    while i < len(flags):
        if flags[i]:
            j = i
            while j + 1 < len(flags) and flags[j + 1]:
                j += 1
            if j - i + 1 > best[0]:
                best = (j - i + 1, i, j)
            i = j + 1
        else:
            i += 1
    return best


def analyse_series(lot, win, fps=30.0, crossfades=None, sheet_dismiss=None, scene_start=None, reduce_motion=False):
    """lot: (n,h,w) gray frames of the lot; win: (n,) mean luma of the window box or None. Returns the report."""
    n = len(lot)
    out = dict(frames=n, fps=fps, checks=[])

    def chk(rule, verdict, detail):
        out["checks"].append(dict(rule=rule, verdict=verdict, detail=detail))
    if n < 3:
        chk("frames", "BLOCKED", f"only {n} frames decoded")
        return out
    f = lot.astype(np.int16)
    changed = np.zeros(n, int)
    changed[1:] = (np.abs(f[1:] - f[:-1]) > PIXEL_DELTA).reshape(n - 1, -1).sum(axis=1)
    luma = lot.reshape(n, -1).mean(axis=1)
    out["series"] = [f"{i / fps:.2f}:{luma[i]:.1f}/{int(changed[i])}" for i in range(n)]
    length, s, e = longest_run(changed >= CHANGED_MIN)
    out["drop_frames"], out["drop_run"] = length, [s, e]
    if reduce_motion:
        chk("drop_frames", "PASS" if length < DROP_MIN_FRAMES else "FAIL",
            f"{length} moving frames in a row; Reduce Motion captures must not contain the clip run (< {DROP_MIN_FRAMES})")
    else:
        chk("drop_frames", "PASS" if length >= DROP_MIN_FRAMES else "FAIL",
            f"longest run of frames with >= {CHANGED_MIN} changed pixels is {length} ({length / fps:.2f} s), need >= {DROP_MIN_FRAMES}")
    # hard cuts: mean luma step > 25% between consecutive frames, outside declared crossfade windows
    if crossfades is None:
        crossfades = [] if length == 0 else [(s / fps, CLIP_IN), ((e + 1) / fps, CLIP_OUT)]
    cuts = []
    for i in range(1, n):
        t = i / fps
        prev = max(luma[i - 1], 1.0)
        if abs(luma[i] - luma[i - 1]) / prev > HARD_CUT:
            if any(a - 1 / fps <= t <= a + d + 1 / fps for a, d in crossfades):
                continue
            if sheet_dismiss is not None and abs(t - sheet_dismiss) <= 0.3:
                continue
            cuts.append(round(t, 2))
    out["hard_cuts"] = cuts
    chk("hard_cuts", "PASS" if not cuts else "FAIL",
        f"{len(cuts)} hard cut(s) at {cuts}" if cuts else "none outside the declared crossfades")
    # windows fade
    wstart = wend = None
    if win is None:
        chk("windows_fade", "BLOCKED", "no --window-box given")
    else:
        after = 0  # the first rise anywhere: a fade that starts before the clip ends is an order FAIL, not "absent"
        rise = np.diff(win[after:])
        k = j = 0
        i = 0
        while i < len(rise):  # first run of rising frames that climbs >= 3 luma levels (smaller wobble is noise)
            if rise[i] > 0.05:
                jj = i
                while jj < len(rise) and rise[jj] > 0.05:
                    jj += 1
                if rise[i:jj].sum() >= 3.0:
                    k, j = i, jj
                    break
                i = jj
            else:
                i += 1
        nfade = j - k
        wstart, wend = after + k + 1, after + j  # first and last frame that is brighter than its predecessor
        out["windows_fade_frames"] = nfade
        if reduce_motion:
            seg = win[wstart:wend + 1]
            lin = False
            if len(seg) >= 3 and seg[-1] > seg[0]:
                t_ = np.arange(len(seg))
                r = np.corrcoef(t_, seg)[0, 1]
                lin = bool(r ** 2 >= 0.98)
            chk("windows_fade", "PASS" if (nfade >= 2 and lin) else "FAIL", f"{nfade}-frame fade, linear={lin} (Reduce Motion needs a linear fade)")
        else:
            ok = FADE_FRAMES[0] <= nfade <= FADE_FRAMES[1]
            chk("windows_fade", "PASS" if ok else "FAIL",
                f"windows luma rises monotonically for {nfade} frames ({nfade / fps:.2f} s) after the clip; want {FADE_FRAMES[0]}-{FADE_FRAMES[1]}")
    # order
    if win is None or length == 0:
        chk("order", "BLOCKED", "needs both a drop run and --window-box")
    else:
        ok = e < wstart if wstart is not None else False
        detail = f"drop ends at frame {e} ({e / fps:.2f} s), windows start at frame {wstart} ({wstart / fps:.2f} s)"
        if scene_start is not None:
            ok2 = scene_start >= wend / fps + 0.5
            detail += f"; scene starts {scene_start:.2f} s, windows end {wend / fps:.2f} s (+0.5 s needed)"
            ok = ok and ok2
        chk("order", "PASS" if ok else "FAIL", detail)
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("video")
    ap.add_argument("--lot", help="x0,y0,x1,y1 frame fractions of the lot region (default 0,0.10,1,0.55)")
    ap.add_argument("--window-box", help="x0,y0,x1,y1 frame fractions of the window boxes (enables windows_fade and order)")
    ap.add_argument("--crossfades", help="START:DUR,... in seconds, overrides the derived clip-in/clip-out windows")
    ap.add_argument("--sheet-dismiss", type=float, help="time (s) of the sheet dismiss; +-0.3 s is excluded from hard_cuts")
    ap.add_argument("--scene-start", type=float, help="time (s) the ambient scene starts (section F.2)")
    ap.add_argument("--reduce-motion", action="store_true")
    ap.add_argument("--series", action="store_true", help="print the per-frame series")
    ap.add_argument("--json")
    a = ap.parse_args(argv)
    rm = a.reduce_motion or "-rm" in os.path.basename(a.video)
    cf = None
    if a.crossfades:
        cf = [tuple(float(v) for v in p.split(":")) for p in a.crossfades.split(",")]
    try:
        lot, fps = decode(a.video, frac_box(a.lot, (0, 0.10, 1, 0.55)))
        win = None
        if a.window_box:
            wf, _ = decode(a.video, frac_box(a.window_box, (0, 0, 1, 1)))
            win = wf.reshape(len(wf), -1).mean(axis=1)
    except ValueError as err:
        print(f"BLOCKED  decode: {err}")
        return 1
    if abs(fps - 30) > 0.5:
        print(f"note: capture is {fps:.2f} fps; resampled to 30 (the spec wants a 30 fps CFR capture)")
    rep = analyse_series(lot, win, 30.0, cf, a.sheet_dismiss, a.scene_start, rm)
    if a.series:
        print(" ".join(rep["series"]))
    for c in rep["checks"]:
        print(f"{c['verdict']:8} {c['rule']}: {c['detail']}")
    if a.json:
        json.dump(rep, open(a.json, "w"), indent=1)
    return 1 if any(c["verdict"] in ("FAIL", "BLOCKED") for c in rep["checks"]) else 0


if __name__ == "__main__":
    sys.exit(main())
