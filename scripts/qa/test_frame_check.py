#!/usr/bin/env python3
"""Regression tests for frame_check.py density mode (synthetic frames, no external files).

  python3 scripts/qa/test_frame_check.py
"""
import os
import sys
import tempfile
import unittest

import numpy as np
from PIL import Image

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


if __name__ == "__main__":
    unittest.main(verbosity=2)
