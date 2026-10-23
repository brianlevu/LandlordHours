#!/usr/bin/env python3
"""frame_check.py - measured checks on captured frames.

Mode `density` enforces the [measured] density rules of docs/design/DESIGN-STANDARD.md
section 2 (D1, D2, D4, D6, plus D3 when --items-present is given). Frames are 3x
iPhone captures; pt = px / 3.

  python3 scripts/qa/frame_check.py density FRAME.png [FRAME2.png ...] [--json out.json]

Per frame it reports: row heights (rows split by hairline dividers inside a card),
largest card's share of the viewport, complete list rows above the fold, and the
share of empty bands inside each card. Exit code 1 if any frame FAILS.

Method (PIL + numpy, no model):
  1. Canvas colour = the pixel at x=4 on each pixel row. A pixel row is a CARD row
     when probe columns near both gutters differ from the canvas by dE76 > 2.5;
     consecutive card rows (gaps <= 3px closed) form a card bbox.
  2. A card is the HERO when its fill is saturated blue and dark (blueprint).
  3. Dividers: inside a card, pixel rows where >= 50% of the card width differs from
     the card fill and the band is <= 5px thick. Rows are the spans between card
     edges and dividers. A row is complete only if both bounds are above the fold.
  4. Empty band share: rows (within the card, x inset 16pt) whose pixels are all
     card fill or canvas (dE <= 3), as a share of card height. Hero excluded.
  5. Fold = top of the floating tab bar (default 88% of frame height).

Verdict rules (pt = px/3, viewport = frame height / 3):
  D1  list row height 56-88pt (default Dynamic Type only; XXL/AX rows reflow)
  D2  list row share of viewport <= 12% (default, XXL), <= 30% (AX)
  D3  items above fold >= 5 (default) / >= 4 (XXL), only when --items-present >= 5
  D4  empty bands <= 35% of a non-hero card
  D6  non-hero card share <= 20%, hero <= 40%. A grouped list container (a card
      split into rows by dividers) is judged by D1/D2 per row, not D6.
Info only (not in verdict): gutter_pt vs 20, since mockups predate the standard.
Not measured here: D7 text lines per row, D3c AX hero variant, D5/D8/D10 (grep rules).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys

import numpy as np
from PIL import Image

SCALE = 3.0
D1_MIN, D1_MAX = 56.0, 88.0
D2_DEFAULT, D2_AX = 0.12, 0.30
D4_MAX = 0.35
D6_CARD, D6_HERO = 0.20, 0.40
FOLD_FRAC = 0.88


def rgb_to_lab(a: np.ndarray) -> np.ndarray:
    c = a.astype(np.float64) / 255.0
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    m = np.array([[0.4124564, 0.3575761, 0.1804375],
                  [0.2126729, 0.7151522, 0.0721750],
                  [0.0193339, 0.1191920, 0.9503041]])
    xyz = c @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]),
                     200 * (f[..., 1] - f[..., 2])], axis=-1)


def runs(mask: np.ndarray, min_len: int = 1, close_gap: int = 0):
    idx = np.flatnonzero(mask)
    if idx.size == 0:
        return []
    out, start, prev = [], idx[0], idx[0]
    for i in idx[1:]:
        if i - prev - 1 > close_gap:
            out.append((start, prev + 1))
            start = i
        prev = i
    out.append((start, prev + 1))
    return [(a, b) for a, b in out if b - a >= min_len]


def detect_dt(name: str) -> str:
    n = name.lower()
    if re.search(r"ax\d?(?![a-z])", n):
        return "ax"
    if "xxl" in n:
        return "xxl"
    return "default"


def analyse(path: str, dt: str, scale: float, fold_frac: float, items_present: int | None):
    img = Image.open(path).convert("RGB")
    W, H = img.size
    a = np.asarray(img)
    lab = rgb_to_lab(a)
    vp_pt = H / scale
    fold = int(H * fold_frac)
    canvas = lab[:, 4, :]  # per-row canvas colour
    probes = [int(40 * scale), W - int(40 * scale)]
    diff = np.zeros(H, dtype=bool)
    both = np.ones(H, dtype=bool)
    for px in probes:
        band = lab[:, px - 3:px + 3, :]
        d = np.linalg.norm(band - canvas[:, None, :], axis=2)
        both &= (d > 2.5).mean(axis=1) > 0.8
    top_skip = int(62 * scale)  # status bar / dynamic island
    both[:top_skip] = False
    both[fold:] = False  # the floating tab bar owns everything below the fold
    card_rows = runs(both, min_len=int(40 * scale), close_gap=3)
    cards = []
    for (y0, y1) in card_rows:
        # horizontal extent: sample at mid-height of the card
        ym = (y0 + y1) // 2
        row_d = np.linalg.norm(lab[ym] - canvas[ym], axis=1) > 2.5
        xs = np.flatnonzero(row_d)
        # edges: outermost columns that are contiguous with probe columns
        x0 = probes[0]
        while x0 > 0 and np.linalg.norm(lab[ym, x0 - 1] - canvas[ym]) > 4.5:
            x0 -= 1
        x1 = probes[1]
        while x1 < W - 1 and np.linalg.norm(lab[ym, x1 + 1] - canvas[ym]) > 4.5:
            x1 += 1
        x1 += 1
        # refine top/bottom with columns just past the corner radius (exact edges)
        cols = [x0 + int(22 * scale), x1 - int(22 * scale)]
        def inside(y):
            return all(np.linalg.norm(lab[y, cx] - canvas[y]) > 2.5 for cx in cols)
        while y0 > top_skip and inside(y0 - 1):
            y0 -= 1
        while y1 < fold and inside(y1):
            y1 += 1
        # card fill: modal colour of the interior
        inner = a[y0:y1, x0 + 6:x1 - 6].reshape(-1, 3)
        vals, counts = np.unique((inner // 4), axis=0, return_counts=True)
        fill_rgb = (vals[counts.argmax()] * 4 + 2).astype(np.uint8)
        fill_lab = rgb_to_lab(fill_rgb[None, :])[0]
        r, g, b = [int(v) for v in fill_rgb]
        hero = (b >= 120 and b - r >= 80 and (b - r) / max(b, 1) > 0.6)
        cards.append(dict(y0=int(y0), y1=int(y1), x0=int(x0), x1=int(x1), fill=fill_lab,
                          hero=bool(hero)))

    res_cards, all_rows, flags = [], [], []
    for c in cards:
        y0, y1, x0, x1 = c["y0"], min(c["y1"], H), c["x0"], c["x1"]
        cut = c["y1"] >= fold - 2
        vis_y1 = min(y1, fold) if cut else y1
        band = lab[y0:vis_y1, x0 + 3:x1 - 3, :]
        div_rows = []
        n = band.shape[0]
        off = 4
        if not c["hero"] and n > 2 * off + 2:
            # divider candidate at y: differs from both y-off and y+off across >= 50% of the width
            cand = np.zeros(n, dtype=bool)
            ys = np.arange(off, n - off)
            d_up = np.linalg.norm(band[ys] - band[ys - off], axis=2) > 2.5
            d_dn = np.linalg.norm(band[ys] - band[ys + off], axis=2) > 2.5
            # hairline dividers run to the card's trailing edge; progress tracks and
            # text do not, so require the last 24px of the row to differ too
            tail = (d_up[:, -24:].mean(axis=1) >= 0.9) & (d_dn[:, -24:].mean(axis=1) >= 0.9)
            cand[ys] = (d_up.mean(axis=1) >= 0.5) & (d_dn.mean(axis=1) >= 0.5) & tail
            for (a0, a1) in runs(cand, close_gap=1):
                if a1 - a0 <= 4 and a0 > 8 and n - a1 > 8:
                    div_rows.append(y0 + (a0 + a1) // 2)
        bounds = [y0] + div_rows + [y1]
        rows = []
        for i in range(len(bounds) - 1):
            top, bot = bounds[i], bounds[i + 1]
            complete = bot <= fold and not (i == len(bounds) - 2 and cut)
            rows.append(dict(y0=top, y1=bot, h_pt=round((bot - top) / scale, 1), complete=bool(complete)))
        is_list = len(div_rows) >= 1
        # empty bands: rows inside card (x inset 16pt) all card fill or canvas
        ix0, ix1 = x0 + int(16 * scale), x1 - int(16 * scale)
        empty_share = None
        if not c["hero"] and ix1 > ix0:
            iy0, iy1 = y0 + int(16 * scale), vis_y1 - (0 if cut else int(16 * scale))
            if iy1 > iy0:
                reg = lab[iy0:iy1, ix0:ix1, :]
                near_fill = np.linalg.norm(reg - c["fill"], axis=2) <= 3
                near_canvas = np.linalg.norm(reg - canvas[iy0:iy1, None, :], axis=2) <= 3
                empty_row = (near_fill | near_canvas).all(axis=1)
                empty_share = round(float(empty_row.sum() / (vis_y1 - y0)), 3)
            else:
                empty_share = 0.0
        h_pt = (y1 - y0) / scale
        vis_pt = (vis_y1 - y0) / scale
        res_cards.append(dict(
            bbox_px=[c["x0"], y0, c["x1"], y1], hero=c["hero"], list_container=is_list,
            height_pt=round(h_pt, 1), visible_height_pt=round(vis_pt, 1),
            viewport_share=round(vis_pt / vp_pt, 3), cut_by_fold=bool(cut),
            empty_band_share=empty_share, rows=rows if is_list else [],
            gutter_pt=round(c["x0"] / scale, 1)))
        if is_list:
            all_rows += rows

    checks = []

    def chk(rule, ok, detail):
        checks.append(dict(rule=rule, pass_=bool(ok), detail=detail))

    done = [r for r in all_rows if r["complete"]]
    if dt == "default" and done:
        bad = [r["h_pt"] for r in done if not (D1_MIN <= r["h_pt"] <= D1_MAX)]
        chk("D1 row height 56-88pt", not bad,
            f"rows {[float(r['h_pt']) for r in done]}" + (f"; out of range {[float(b) for b in bad]}" if bad else ""))
    lim = D2_AX if dt == "ax" else D2_DEFAULT
    if done:
        worst = max(r["h_pt"] for r in done) / vp_pt
        chk(f"D2 item share <= {int(lim * 100)}%", worst <= lim, f"largest row {worst:.1%}")
    non_hero_items = [c for c in res_cards if not c["hero"] and not c["list_container"]]
    for c in non_hero_items:
        chk("D6 card share <= 20%", c["viewport_share"] <= D6_CARD,
            f"card at y={c['bbox_px'][1]} is {c['viewport_share']:.1%} ({c['visible_height_pt']}pt)")
    for c in res_cards:
        if c["hero"]:
            chk("D6 hero share <= 40%", c["viewport_share"] <= D6_HERO,
                f"hero {c['viewport_share']:.1%}")
        if c["empty_band_share"] is not None:
            chk("D4 empty bands <= 35%", c["empty_band_share"] <= D4_MAX,
                f"card at y={c['bbox_px'][1]} empty {c['empty_band_share']:.1%}")
    n_items = len(done)
    if items_present is not None and items_present >= 5:
        need = 4 if dt in ("xxl", "ax") else 5
        chk(f"D3 items above fold >= {need}", n_items >= need, f"{n_items} complete rows above fold")

    verdict = "PASS" if all(c["pass_"] for c in checks) and checks else ("FAIL" if checks else "NO_DATA")
    return dict(
        frame=path, size_px=[W, H], viewport_pt=[round(W / scale, 1), round(vp_pt, 1)], dynamic_type=dt,
        fold_px=fold, cards=res_cards,
        summary=dict(
            row_heights_pt=[r["h_pt"] for r in all_rows if r["complete"]],
            largest_card_share=max([c["viewport_share"] for c in res_cards], default=0.0),
            largest_non_list_card_share=max([c["viewport_share"] for c in res_cards if not c["list_container"] and not c["hero"]], default=0.0),
            items_above_fold=n_items,
            max_empty_band_share=max([c["empty_band_share"] or 0 for c in res_cards], default=0.0),
            gutter_pt_info=(res_cards[0]["gutter_pt"] if res_cards else None)),
        checks=checks, verdict=verdict)


def _j(o):
    if isinstance(o, np.integer):
        return int(o)
    if isinstance(o, np.floating):
        return float(o)
    raise TypeError(type(o))


def cmd_density(args) -> int:
    results = []
    for f in args.frames:
        dt = args.dt if args.dt != "auto" else detect_dt(os.path.basename(f))
        results.append(analyse(f, dt, args.scale, args.fold, args.items_present))
    if args.json:
        with open(args.json, "w") as fh:
            json.dump(results, fh, indent=2, default=_j)
    else:
        print(json.dumps(results, indent=2, default=_j))
    for r in results:
        s = r["summary"]
        fails = [c["rule"] for c in r["checks"] if not c["pass_"]]
        print(f"{r['verdict']:7} {os.path.basename(r['frame'])} rows={[float(x) for x in s['row_heights_pt']]} "
              f"maxcard={s['largest_card_share']:.0%} items={s['items_above_fold']} "
              f"empty={s['max_empty_band_share']:.0%}" + (f" fails={fails}" if fails else ""),
              file=sys.stderr if not args.json else sys.stdout)
    n_fail = sum(r["verdict"] == "FAIL" for r in results)
    line = f"density: {len(results) - n_fail}/{len(results)} frames pass, {n_fail} fail"
    print(line, file=sys.stderr if not args.json else sys.stdout)
    return 1 if n_fail else 0


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="mode", required=True)
    d = sub.add_parser("density", help="measured density rules (standard section 2)")
    d.add_argument("frames", nargs="+")
    d.add_argument("--json", help="write JSON here (default: stdout)")
    d.add_argument("--dt", choices=["auto", "default", "xxl", "ax"], default="auto",
                   help="Dynamic Type of the frame; auto reads _ax3 / xxl from the file name")
    d.add_argument("--scale", type=float, default=SCALE, help="px per pt (default 3)")
    d.add_argument("--fold", type=float, default=FOLD_FRAC, help="fold as a fraction of frame height (tab bar top)")
    d.add_argument("--items-present", type=int, help="items that exist in the screen's data; enables D3")
    d.set_defaults(fn=cmd_density)
    args = p.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
