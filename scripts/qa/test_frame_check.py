#!/usr/bin/env python3
"""Regression tests for frame_check.py density mode (synthetic frames, no external files).

  python3 scripts/qa/test_frame_check.py
"""
import os
import sys
import tempfile
import unittest

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import frame_check as fc  # noqa: E402

W, H = 1206, 2622
CANVAS, CARD, RULE, INK = (238, 242, 250), (255, 255, 255), (213, 219, 234), (18, 27, 51)


def make_list(row_px, n=5, top=700, name="f.png", dt_suffix="", foot_px=0):
    """A grouped list card of n rows (hairline dividers, left text + right value blocks)."""
    a = np.zeros((H, W, 3), np.uint8)
    a[:] = CANVAS
    y1 = top + row_px * n + foot_px
    a[top:y1, 60:1146] = CARD
    for i in range(n):
        y = top + i * row_px
        if i:
            a[y:y + 2, 180:1146] = RULE
        m = row_px // 2
        a[y + m - 18:y + m + 18, 100:420] = INK        # label
        a[y + m - 18:y + m + 18, 800:1060] = INK       # value
    if foot_px:
        y = top + n * row_px
        a[y:y + 2, 180:1146] = RULE
        a[y + foot_px // 2 - 14:y + foot_px // 2 + 14, 450:760] = INK  # centred foot text
    path = os.path.join(tempfile.mkdtemp(prefix="fc-test-"), name + dt_suffix + ".png")
    Image.fromarray(a).save(path)
    return path


def make_day_list(layout, top=500, name="days.png", bar=False, eyebrow_only=False,
                  action_label=False, divider_before_header=False):
    """layout: list of 'H' (day header) or 'R' (64pt actionable row with ring, title, meta, hours).
    Rows are 192px (64pt) with 30px insets; dividers between consecutive rows of one day only."""
    img = Image.new("RGB", (W, H), CANVAS)
    d = ImageDraw.Draw(img)
    y = top
    d.rectangle([60, y, 1146, y + 10], fill=CARD)
    segments = []
    prev = None
    for kind in layout:
        if kind == "H":
            if divider_before_header and prev == "R":
                d.rectangle([180, y, 1146, y + 1], fill=RULE)       # group divider above the header (r8)
            y += 40
            d.rectangle([110, y, 330, y + 54], fill=INK)            # 18pt header text
            if action_label:
                d.rectangle([880, y, 1090, y + 54], fill=INK)       # trailing action label ("Review all")
            y += 54 + 30
            prev = "H"
        else:
            if prev == "R":
                d.rectangle([180, y, 1146, y + 1], fill=RULE)       # divider
            d.ellipse([108, y + 30, 108 + 66, y + 30 + 66], outline=INK, width=5)
            d.rectangle([240, y + 36, 700, y + 72], fill=INK)       # title
            d.rectangle([240, y + 132, 560, y + 162], fill=INK)     # meta (ink spans 30..162 = 132px)
            d.rectangle([1020, y + 40, 1090, y + 72], fill=INK)     # hours
            y += 192
            prev = "R"
        segments.append(y)
    end = y
    # card fill behind everything
    card = Image.new("RGB", (1086, end - top), CARD)
    base = img.crop((60, top, 1146, end))
    mask = Image.new("L", base.size, 0)
    ImageDraw.Draw(mask).rectangle([0, 0, base.size[0], base.size[1]], fill=255)
    # draw card first, then re-draw the ink on top: simplest is to paint card then replay
    img2 = Image.new("RGB", (W, H), CANVAS)
    img2.paste(card, (60, top))
    src = np.asarray(img).copy()
    dst = np.asarray(img2).copy()
    ink = (src != np.array(CANVAS)).any(axis=2)
    ink[:top] = False
    ink[end:] = False
    dst[ink] = src[ink]
    if bar:
        by = 2205
        dst[by:by + 2, 200:1000] = RULE
        dst[by + 130:by + 132, 200:1000] = RULE
        dst[by + 40:by + 90, 520:700] = INK
    path = os.path.join(tempfile.mkdtemp(prefix="fc-test-"), name)
    Image.fromarray(dst).save(path)
    return path


def run(path, dt="default"):
    return fc.analyse(path, dt, 3.0, 0.88, None)


def failed(res, prefix):
    return [c for c in res["checks"] if c["rule"].startswith(prefix) and not c["pass_"]]


class Density(unittest.TestCase):
    def test_54pt_value_rows_fail_d1_even_when_d4_exempt(self):
        # 162px = 54pt rows, like Log time in std-mockups-r2. The value-row group exempts D4 only.
        res = run(make_list(162))
        card = res["cards"][0]
        self.assertTrue(card["d4_exempt_value_rows"], "fixture should be a value-row group")
        self.assertTrue(failed(res, "D1"), "54pt rows must fail D1 (min 56pt)")
        self.assertEqual(res["verdict"], "FAIL")

    def test_54pt_rows_fail_d1_at_xxl_too(self):
        res = run(make_list(162), dt="xxl")
        self.assertTrue(failed(res, "D1"))

    def test_64pt_rows_pass_d1(self):
        res = run(make_list(192))
        self.assertFalse(failed(res, "D1"))

    def test_value_group_exempts_d4(self):
        res = run(make_list(162))
        self.assertFalse(failed(res, "D4"))

    def test_short_centred_foot_is_not_a_row(self):
        # 64pt rows plus a 44pt centred foot action: no D1 failure from the foot.
        res = run(make_list(192, n=3, foot_px=132))
        rows = res["cards"][0]["rows"]
        self.assertTrue(rows[-1]["foot"])
        self.assertFalse(failed(res, "D1"))

    def test_short_row_that_is_not_a_foot_still_fails(self):
        # a 40pt last row with left-aligned content is a real row and fails D1
        a = make_list(192, n=3)
        img = np.asarray(Image.open(a)).copy()
        y = 700 + 3 * 192
        img[y:y + 120, 60:1146] = CARD
        img[y:y + 2, 180:1146] = RULE
        img[y + 40:y + 80, 100:500] = INK
        Image.fromarray(img).save(a)
        res = run(a)
        self.assertFalse(res["cards"][0]["rows"][-1]["foot"])
        self.assertTrue(failed(res, "D1"))

    def test_ax_two_line_row_up_to_45_percent(self):
        res = run(make_list(1000, n=2, top=200), dt="ax")  # 333pt = 38% of 874pt
        self.assertFalse(failed(res, "D2"))
        res = run(make_list(1200, n=2, top=200), dt="ax")  # 400pt = 46%
        self.assertTrue(failed(res, "D2"))


class DayHeaders(unittest.TestCase):
    LAYOUT = ["H", "R", "R", "H", "R", "R"]

    def test_headers_are_not_rows_and_rows_measure_64pt(self):
        res = run(make_day_list(self.LAYOUT))
        card = res["cards"][0]
        self.assertEqual(len(card["day_headers"]), 2)
        hs = [r["h_pt"] for r in card["rows"]]
        self.assertEqual(len(hs), 4, hs)
        for h in hs:
            self.assertTrue(62 <= h <= 66, hs)
        self.assertFalse(failed(res, "D1"))

    def test_header_with_trailing_action_label_is_still_a_header(self):
        res = run(make_day_list(self.LAYOUT, action_label=True))
        card = res["cards"][0]
        self.assertEqual(len(card["day_headers"]), 2)
        hs = [float(r["h_pt"]) for r in card["rows"]]
        self.assertEqual(len(hs), 4, hs)
        self.assertTrue(all(62 <= h <= 66 for h in hs), hs)

    def test_divider_above_a_header_leaves_no_phantom_row(self):
        res = run(make_day_list(self.LAYOUT, divider_before_header=True))
        card = res["cards"][0]
        hs = [float(r["h_pt"]) for r in card["rows"]]
        self.assertEqual(len(hs), 4, hs)
        self.assertTrue(all(h > 50 for h in hs), hs)
        self.assertFalse(failed(res, "D1"))

    def test_without_header_detection_failure_mode_is_a_tall_row(self):
        # two rows split by a header but with the header's ring-less neighbour removed: a header
        # band followed by something that is not a ring must NOT be treated as a header
        res = run(make_day_list(["R", "R"]))
        self.assertEqual(res["cards"][0]["day_headers"], [])

    def test_tall_real_row_still_fails_d1(self):
        # a genuinely tall row (a 130pt block between dividers, no header) must still fail D1
        a = make_list(390, n=2, top=500)
        res = run(a)
        self.assertTrue(failed(res, "D1"))

    def test_eyebrow_in_a_question_card_is_not_a_header(self):
        a = np.zeros((H, W, 3), np.uint8)
        a[:] = CANVAS
        a[500:1100, 60:1146] = CARD
        a[560:610, 110:420] = INK            # eyebrow, left only
        a[650:700, 110:1000] = INK           # question text, wide
        a[760:850, 110:1090] = RULE          # answer chips
        path = os.path.join(tempfile.mkdtemp(prefix="fc-test-"), "q.png")
        Image.fromarray(a).save(path)
        self.assertEqual(run(path)["cards"][0]["day_headers"], [])

    def test_pinned_bar_is_detected_and_not_a_card_or_row(self):
        res = run(make_day_list(self.LAYOUT, bar=True))
        self.assertIsNotNone(res["ignored"]["pinned_bar"])
        top = res["ignored"]["pinned_bar"][0]
        for c in res["cards"]:
            self.assertLessEqual(c["bbox_px"][3], top + 2)
        self.assertFalse(failed(res, "D1"))


class ScaleAware(unittest.TestCase):
    def test_known_sizes_infer_scale(self):
        for size, want in {(1206, 2622): 3.0, (1320, 2868): 3.0, (2752, 2064): 2.0, (2064, 2752): 2.0,
                           (1398, 2034): 3.0, (2007, 2853): 3.0}.items():
            self.assertEqual(fc.infer_scale(*size)[0], want, size)

    def _ipad_list(self, row_pt=64, n=5, inset_pt=15):
        """iPad Pro 13in portrait at 2x: one grouped card, 64pt rows, dividers stopping inset_pt short."""
        w, h, sc = 2064, 2752, 2
        a = np.zeros((h, w, 3), np.uint8)
        a[:] = CANVAS
        x0, x1, top = 40, 2024, 400
        row = row_pt * sc
        a[top:top + row * n, x0:x1] = CARD
        for i in range(n):
            y = top + i * row
            if i:
                a[y:y + 2, x0 + 100:x1 - inset_pt * sc] = RULE
            a[y + row // 2 - 14:y + row // 2 + 14, x0 + 60:x0 + 420] = INK
            a[y + row // 2 - 14:y + row // 2 + 14, x1 - 260:x1 - 60] = INK
        path = os.path.join(tempfile.mkdtemp(prefix="fc-test-"), "ipad.png")
        Image.fromarray(a).save(path)
        return path

    def test_ipad_rows_are_split_at_2x(self):
        # dividers that stop 15pt short of the card edge (iPad inset-grouped) must still split rows
        res = fc.analyse(self._ipad_list(), "default", 2.0, 0.97, None, "ipad")
        rows = [float(r["h_pt"]) for r in res["cards"][0]["rows"]]
        self.assertEqual(len(rows), 5, rows)
        self.assertTrue(all(62 <= r <= 66 for r in rows), rows)

    def test_ipad_progress_track_is_not_a_divider(self):
        path = self._ipad_list(n=1)
        a = np.asarray(Image.open(path)).copy()
        a[400 + 70:400 + 76, 200:1100] = (214, 120, 20)   # coloured fill + track inside one row
        a[400 + 70:400 + 76, 1100:1500] = RULE
        Image.fromarray(a).save(path)
        res = fc.analyse(path, "default", 2.0, 0.97, None, "ipad")
        self.assertEqual(len(res["cards"][0]["rows"]) if res["cards"][0]["list_container"] else 1, 1)

    def test_dark_navy_hairlines_still_split_rows(self):
        a = np.zeros((H, W, 3), np.uint8)
        a[:] = (11, 18, 48)
        a[700:700 + 192 * 4, 60:1146] = (20, 28, 63)
        for i in range(4):
            y = 700 + i * 192
            if i:
                a[y:y + 2, 180:1146] = (42, 53, 96)
            a[y + 78:y + 114, 100:420] = (242, 244, 250)
            a[y + 78:y + 114, 800:1060] = (242, 244, 250)
        path = os.path.join(tempfile.mkdtemp(prefix="fc-test-"), "dark.png")
        Image.fromarray(a).save(path)
        rows = [float(r["h_pt"]) for r in run(path)["cards"][0]["rows"]]
        self.assertEqual(len(rows), 4, rows)
        self.assertTrue(all(63 <= r <= 65 for r in rows), rows)

    def test_density_cli_infers_scale_for_ipad(self):
        import subprocess
        out = subprocess.run([sys.executable, os.path.join(os.path.dirname(fc.__file__), "frame_check.py"),
                              "density", self._ipad_list(), "--json", os.path.join(tempfile.mkdtemp(), "o.json")],
                             capture_output=True, text=True)
        self.assertIn("1/1 frames pass", out.stdout + out.stderr)

    def test_legacy_modes_do_not_skip_ipad_frames(self):
        import json
        import subprocess
        d = tempfile.mkdtemp(prefix="fc-legacy-")
        os.replace(self._ipad_list(), os.path.join(d, "ipad13-port-list.png"))
        outd = tempfile.mkdtemp()
        subprocess.run([sys.executable, os.path.join(os.path.dirname(fc.__file__), "frame_check.py"), d, "--out", outd],
                       capture_output=True, text=True)
        rep = json.load(open(os.path.join(outd, "frame_check.json")))
        self.assertEqual(rep["skipped"], [])
        self.assertEqual(rep["frames"], 1)
        self.assertEqual(rep["results"][0]["size"], [2064, 2752])

    def test_unknown_size_is_reported_not_silently_checked(self):
        import json
        import subprocess
        d = tempfile.mkdtemp(prefix="fc-legacy-")
        Image.fromarray(np.full((900, 1800, 3), 200, np.uint8)).save(os.path.join(d, "odd.png"))
        outd = tempfile.mkdtemp()
        subprocess.run([sys.executable, os.path.join(os.path.dirname(fc.__file__), "frame_check.py"), d, "--out", outd],
                       capture_output=True, text=True)
        rep = json.load(open(os.path.join(outd, "frame_check.json")))
        self.assertTrue(any("--scale" in why for _, why in rep["skipped"]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
