#!/usr/bin/env python3
"""Tests for motion_check.py (synthetic series; one ffmpeg round trip when ffmpeg exists).  python3 scripts/qa/test_motion_check.py"""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import motion_check as mc  # noqa: E402


def make(n=150, drop=(10, 40), fade_at=45, fade_len=11, cut_at=None, still_drop=False):
    rng = np.random.default_rng(1)
    lot = np.full((n, 30, 30), 100, np.uint8)
    if not still_drop:
        for i in range(drop[0], drop[1] + 1):
            lot[i] = np.clip(100 + rng.integers(-30, 30, (30, 30)), 0, 255)  # moving timber: many changed pixels, same mean
    if cut_at:
        lot[cut_at:] = 200  # a hard cut: mean luma doubles in one frame
    win = np.full(n, 40.0)
    for k in range(fade_len):
        win[fade_at + k] = 40 + (k + 1) * 10
    win[fade_at + fade_len:] = 40 + fade_len * 10
    return lot, win


def verdicts(rep):
    return {c["rule"]: c["verdict"] for c in rep["checks"]}


class Series(unittest.TestCase):
    def test_good_run_passes_everything(self):
        lot, win = make()
        v = verdicts(mc.analyse_series(lot, win))
        self.assertEqual(v, {"drop_frames": "PASS", "hard_cuts": "PASS", "windows_fade": "PASS", "order": "PASS"})

    def test_short_drop_fails(self):
        lot, win = make(drop=(10, 20))
        self.assertEqual(verdicts(mc.analyse_series(lot, win))["drop_frames"], "FAIL")

    def test_no_motion_is_a_fail_not_a_pass(self):
        lot, win = make(still_drop=True)
        rep = mc.analyse_series(lot, win)
        self.assertEqual(rep["drop_frames"], 0)
        self.assertEqual(verdicts(rep)["drop_frames"], "FAIL")
        self.assertEqual(verdicts(rep)["order"], "BLOCKED")

    def test_hard_cut_outside_crossfade_fails_and_inside_is_exempt(self):
        lot, win = make(cut_at=100)
        self.assertEqual(verdicts(mc.analyse_series(lot, win))["hard_cuts"], "FAIL")
        lot, win = make(cut_at=43)  # inside the 0.30 s clip-out window that starts when the drop ends
        self.assertEqual(verdicts(mc.analyse_series(lot, win))["hard_cuts"], "PASS")
        lot, win = make(cut_at=100)
        self.assertEqual(verdicts(mc.analyse_series(lot, win, sheet_dismiss=100 / 30.0))["hard_cuts"], "PASS")

    def test_fade_length_window(self):
        for ln, want in ((8, "FAIL"), (9, "PASS"), (14, "PASS"), (15, "FAIL")):
            lot, win = make(fade_len=ln)
            self.assertEqual(verdicts(mc.analyse_series(lot, win))["windows_fade"], want, ln)

    def test_order_fails_when_windows_come_first(self):
        lot, win = make(fade_at=15)
        self.assertEqual(verdicts(mc.analyse_series(lot, win))["order"], "FAIL")

    def test_scene_start_needs_half_a_second(self):
        lot, win = make()
        self.assertEqual(verdicts(mc.analyse_series(lot, win, scene_start=3.0))["order"], "PASS")
        self.assertEqual(verdicts(mc.analyse_series(lot, win, scene_start=2.0))["order"], "FAIL")

    def test_missing_window_box_is_blocked(self):
        lot, _ = make()
        v = verdicts(mc.analyse_series(lot, None))
        self.assertEqual((v["windows_fade"], v["order"]), ("BLOCKED", "BLOCKED"))

    def test_too_few_frames_blocked(self):
        self.assertEqual(verdicts(mc.analyse_series(np.zeros((2, 4, 4), np.uint8), None))["frames"], "BLOCKED")

    def test_reduce_motion_wants_no_clip_and_a_linear_fade(self):
        lot, win = make(still_drop=True, fade_at=20, fade_len=12)
        v = verdicts(mc.analyse_series(lot, win, reduce_motion=True))
        self.assertEqual((v["drop_frames"], v["windows_fade"]), ("PASS", "PASS"))
        lot, win = make()
        self.assertEqual(verdicts(mc.analyse_series(lot, win, reduce_motion=True))["drop_frames"], "FAIL")


@unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "ffmpeg not installed")
class Decode(unittest.TestCase):
    def test_round_trip_and_blocked_cases(self):
        d = tempfile.mkdtemp(prefix="mc-")
        lot, _ = make(n=60, drop=(5, 30), fade_at=42, fade_len=10)
        for i in range(len(lot)):
            frame = np.full((64, 64, 3), 128, np.uint8)
            frame[8:40, 8:40] = lot[i][:, :, None][:32, :32] if lot.shape[1] >= 32 else 128
            Image.fromarray(frame).save(os.path.join(d, f"f{i:03d}.png"))
        mp4 = os.path.join(d, "t.mp4")
        subprocess.run(["ffmpeg", "-v", "error", "-framerate", "30", "-i", os.path.join(d, "f%03d.png"), "-pix_fmt", "yuv420p", mp4], check=True)
        g, fps = mc.decode(mp4, (0, 0, 1, 1))
        self.assertEqual(len(g), 60)
        self.assertAlmostEqual(fps, 30, delta=0.5)
        with self.assertRaises(ValueError):
            mc.decode(os.path.join(d, "missing.mp4"), (0, 0, 1, 1))
        open(os.path.join(d, "bad.mp4"), "wb").write(b"not a video")
        with self.assertRaises(ValueError):
            mc.decode(os.path.join(d, "bad.mp4"), (0, 0, 1, 1))
        self.assertEqual(mc.main([os.path.join(d, "missing.mp4")]), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
