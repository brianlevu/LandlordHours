#!/usr/bin/env python3
"""Tests for asset_check.py on a synthetic Craft.xcassets (PNG stand-ins, --allow-png).  python3 scripts/qa/test_asset_check.py"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asset_check as ac  # noqa: E402


def still(seed, size=1206, left=200, right=1000, ground=0.92):
    a = np.zeros((size, size, 4), np.uint8)
    top, bot = 300, int(size * ground)
    a[top:bot, left:right, :3] = (80 + seed * 3 % 120, 120, 60 + seed * 7 % 100)
    a[top:bot, left:right, 3] = 255
    a[top:bot, left - 1, :3] = a[top:bot, left, :3]   # a 1px half-alpha edge with the same colour: no fringe
    a[top:bot, left - 1, 3] = 128
    return a


def build(root, mutate=None, extra_sets=()):
    xc = os.path.join(root, "Assets.xcassets", "Craft")
    seed = 0
    names = []
    for st in ac.STAGES:
        names += [f"craft_{st}", f"craft_{st}-unlit", f"craft_thumb_{st}"]
    names += list(extra_sets)
    for n in names:
        d = os.path.join(xc, n + ".imageset")
        os.makedirs(d)
        thumb = n.startswith("craft_thumb")
        imgs = []
        for dark in (False, True):
            for sc in (("2x", "3x") if thumb else ("3x",)):
                seed += 1
                px = ac.THUMB_PX[sc] if thumb else ac.STILL_PX
                a = still(seed, px)
                fn = f"{n}-{'d' if dark else 'a'}{sc}.png"
                if mutate:
                    a = mutate(n, dark, sc, a)
                Image.fromarray(a).save(os.path.join(d, fn))
                e = dict(filename=fn, idiom="universal", scale=sc)
                if dark:
                    e["appearances"] = [dict(appearance="luminosity", value="dark")]
                imgs.append(e)
        json.dump(dict(images=imgs, info=dict(version=1, author="xcode")), open(os.path.join(d, "Contents.json"), "w"))
    return xc


def run(**kw):
    root = tempfile.mkdtemp(prefix="asset-")
    xc = build(root, kw.get("mutate"), kw.get("extra", ()))
    R = ac.check(xc, os.path.join(root, "none"), allow_png=True, allow_future=kw.get("future", False))
    return {r["rule"]: r for r in R.rows}, R


class Contract(unittest.TestCase):
    def test_good_set_passes_everything_but_clips(self):
        rows, R = run()
        for rule in ("stages", "files", "hashes", "camera pin", "fringe", "reserved", "budget stills"):
            self.assertEqual(rows[rule]["verdict"], "PASS", (rule, rows[rule]))
        self.assertEqual(rows["clips"]["verdict"], "FAIL")   # fails closed: no clips supplied

    def test_missing_folder_is_blocked(self):
        R = ac.check("/nonexistent/Craft", None)
        self.assertEqual(R.rows[0]["verdict"], "BLOCKED")

    def test_missing_dark_entry(self):
        root = tempfile.mkdtemp()
        xc = build(root)
        p = os.path.join(xc, "craft_half.imageset", "Contents.json")
        d = json.load(open(p))
        d["images"] = [i for i in d["images"] if "appearances" not in i]
        json.dump(d, open(p, "w"))
        rows = {r["rule"]: r for r in ac.check(xc, None, allow_png=True).rows}
        self.assertEqual(rows["stages"]["verdict"], "FAIL")
        self.assertIn("craft_half", rows["stages"]["detail"])

    def test_png_needs_allow_png(self):
        root = tempfile.mkdtemp()
        xc = build(root)
        rows = {r["rule"]: r for r in ac.check(xc, None).rows}
        self.assertEqual(rows["files"]["verdict"], "FAIL")

    def test_identical_lit_and_unlit_fail(self):
        def same(n, dark, sc, a):
            return still(1) if n in ("craft_half", "craft_half-unlit") else a
        rows, _ = run(mutate=same)
        self.assertEqual(rows["hashes"]["verdict"], "FAIL")
        self.assertIn("half", rows["hashes"]["detail"])

    def test_camera_drift_and_ground_line_fail(self):
        rows, _ = run(mutate=lambda n, d, sc, a: still(5, left=260, right=1060) if n == "craft_complete" and not d else a)
        self.assertEqual(rows["camera pin"]["verdict"], "FAIL")
        rows, _ = run(mutate=lambda n, d, sc, a: still(5, ground=0.80) if n == "craft_started" and not d else a)
        self.assertEqual(rows["camera pin"]["verdict"], "FAIL")
        self.assertIn("lowest opaque row", rows["camera pin"]["detail"])

    def test_wrong_size_and_missing_alpha(self):
        rows, _ = run(mutate=lambda n, d, sc, a: still(2, 1000) if n == "craft_half" and not d else a)
        self.assertEqual(rows["files"]["verdict"], "FAIL")
        self.assertIn("1000x1000", rows["files"]["detail"])

        def noalpha(n, dark, sc, a):
            return a if n != "craft_framing" else a  # alpha is stripped when saving below
        root = tempfile.mkdtemp()
        xc = build(root)
        f = os.path.join(xc, "craft_framing.imageset", "craft_framing-a3x.png")
        Image.open(f).convert("RGB").save(f)
        r = {x["rule"]: x for x in ac.check(xc, None, allow_png=True).rows}
        self.assertIn("no alpha channel", r["files"]["detail"])

    def test_bad_fringe_is_caught(self):
        def dark_fringe(n, dark, sc, a):
            if n == "craft_half" and not dark:
                a = a.copy()
                a[300:1108, 199, :3] = 0   # a black halo on the half-alpha edge
            return a
        rows, _ = run(mutate=dark_fringe)
        self.assertEqual(rows["fringe"]["verdict"], "FAIL")
        self.assertIn("craft_half", rows["fringe"]["detail"])

    def test_reserved_names(self):
        rows, _ = run(extra=("craft_slots_roof",))
        self.assertEqual(rows["reserved"]["verdict"], "FAIL")
        rows, _ = run(extra=("craft_slots_roof",), future=True)
        self.assertNotIn("reserved", rows)

    def test_oversize_still_fails(self):
        def noisy(n, dark, sc, a):
            if n == "craft_half" and not dark:
                a = a.copy()
                a[..., :3] = np.random.default_rng(3).integers(0, 255, a[..., :3].shape, dtype=np.uint8)
            return a
        rows, _ = run(mutate=noisy)
        self.assertEqual(rows["files"]["verdict"], "FAIL")
        self.assertIn("KB", rows["files"]["detail"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
