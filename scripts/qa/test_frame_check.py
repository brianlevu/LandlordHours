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


def make_tile(name, top=800, h=720):
    """One tall tile (house art block + two text lines) on the canvas, like a Rentals gallery tile."""
    img = Image.new("RGB", (W, H), CANVAS)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([60, top, 1146, top + h], radius=60, fill=CARD)
    d.rectangle([200, top + 80, 1000, top + 420], fill=(150, 160, 190))      # art
    d.rectangle([110, top + h - 220, 700, top + h - 160], fill=INK)          # name
    d.rectangle([110, top + h - 110, 520, top + h - 60], fill=INK)           # hours
    path = os.path.join(tempfile.mkdtemp(prefix="fc-test-"), name)
    img.save(path)
    return path


class RentalsGalleryCarveOut(unittest.TestCase):
    """Standard 1.4 exception: with --rentals-gallery, tiles are capped at 38% instead of D6's 20%."""

    def test_tall_card_fails_d6_on_an_ordinary_frame(self):
        self.assertTrue(failed(run(make_tile("rentals-x.png")), "D6 card"))

    def test_flag_lifts_the_card_cap_to_the_tile_cap(self):
        res = fc.analyse(make_tile("anything.png"), "default", 3.0, 0.88, None, rentals_gallery=True)
        self.assertFalse(failed(res, "D6"))
        self.assertTrue([c for c in res["checks"] if c["rule"].startswith("D6 Rentals tile") and c["pass_"]])

    def test_gallery_file_name_alone_does_not_trigger_the_carve_out(self):
        for n in ["gallery-3-dark.png", "gallery-8-bottom-light-ax3.png", "gallery-12-dark.png"]:
            self.assertTrue(failed(run(make_tile(n)), "D6 card"), n)

    def test_flag_still_fails_a_tile_over_38_percent(self):
        res = fc.analyse(make_tile("big.png", top=600, h=1100), "default", 3.0, 0.88, None, rentals_gallery=True)
        self.assertTrue(failed(res, "D6 Rentals tile"))

    def test_cli_flag_reaches_the_check(self):
        import subprocess
        path = make_tile("gallery-3-dark.png")
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "frame_check.py")
        plain = subprocess.run([sys.executable, script, "density", path], capture_output=True, text=True)
        flagged = subprocess.run([sys.executable, script, "density", "--rentals-gallery", path], capture_output=True, text=True)
        self.assertNotEqual(plain.returncode, 0, plain.stdout)
        self.assertIn("D6 Rentals tile", flagged.stdout + flagged.stderr)


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


FIX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "craft")
LIGHT = os.path.join(FIX, "today-light-L-windows-lit.png")   # real CRAFT frames, 402x874 (1px = 1pt)
DARK = os.path.join(FIX, "today-dark-L-windows-lit.png")
FULL = os.path.expanduser("~/AgentScratch/landlordhours/2026-10-24/dir-craft-final3/frames")


def run_legacy(frames, scale="1"):
    import json
    import shutil
    import subprocess
    d, outd = tempfile.mkdtemp(prefix="fc-hero-"), tempfile.mkdtemp()
    for f in frames:
        shutil.copy(f, d)
    subprocess.run([sys.executable, "-W", "ignore", os.path.join(os.path.dirname(fc.__file__), "frame_check.py"), d,
                    "--scale", scale, "--out", outd], capture_output=True, text=True)
    return json.load(open(os.path.join(outd, "frame_check.json")))["results"]


class HeroFrames(unittest.TestCase):
    """Dusk / night page, gradient, 3D house art (standard v2 section H). Real frames from dir-craft-final3."""

    def dens(self, path, **kw):
        return fc.analyse(path, "default", 1.0, 0.88, None, "custom", None, kw.get("hero_rect"))

    def test_density_reads_rows_on_the_dusk_and_night_pages(self):
        for p in (LIGHT, DARK):
            r = self.dens(p)
            self.assertNotEqual(r["verdict"], "NO_DATA", p)
            rows = r["summary"]["row_heights_pt"]
            self.assertEqual(len(rows), 2, rows)               # two full "To confirm" rows
            for h in rows:
                self.assertTrue(62.9 <= h <= 65.1, rows)       # 63.7-64.3pt at 3x; 1px = 1pt here
            self.assertEqual(r["verdict"], "PASS", r["checks"])

    def test_hero_art_is_found_and_is_not_a_card(self):
        r = self.dens(LIGHT)
        h = r["hero"]
        self.assertIsNotNone(h["art_bbox_pt"])
        self.assertFalse(h["card_edge_around_art"])
        self.assertTrue(110 <= h["art_bbox_pt"][1] <= 135)     # art top ~120pt
        self.assertTrue(h["art_bbox_pt"][2] - h["art_bbox_pt"][0] > 0.6 * 402)
        self.assertEqual([c for c in r["cards"] if c["hero"]], [])

    def test_hero_rect_overrides_detection(self):
        r = self.dens(LIGHT, hero_rect=(10, 100, 392, 430))
        self.assertEqual(r["hero"]["art_bbox_pt"], [10.0, 100.0, 392.0, 430.0])

    def test_card_with_page_edge_is_a_card_not_a_field(self):
        r = self.dens(LIGHT)
        self.assertEqual(r["ignored"]["fields"], [])
        self.assertTrue(any(c["list_container"] for c in r["cards"]))

    def test_foot_row_of_a_card_is_not_the_pinned_bar(self):
        self.assertIsNone(self.dens(DARK)["ignored"]["pinned_bar"])

    def test_token_check_ignores_page_gradient_and_art(self):
        for res in run_legacy([LIGHT, DARK]):
            self.assertEqual(res["flags"], [], res["flags"])
            self.assertIn("hero", res)
            self.assertFalse(res["tokens"]["canvas"]["flag"])

    def test_gradient_is_matched_as_a_path(self):
        self.assertLess(fc.page_dE((0xDE, 0xD5, 0xC7), "light"), fc.HERO_DE)   # was dE 15.7 from the flat canvas token
        self.assertGreater(fc.page_dE((0xEE, 0xF2, 0xFA), "light"), fc.HERO_DE)  # the plain list canvas is not the page

    def _defect(self, text=True, ring=False):
        im = Image.open(LIGHT).convert("RGB")
        a = np.asarray(im).copy()
        if text:  # textTertiary-like ink on the dusk page: < 4.5:1, not an allowed page ink
            from PIL import ImageFont
            d = ImageDraw.Draw(im)
            try:
                font = ImageFont.load_default(size=22)
            except TypeError:
                self.skipTest("Pillow too old for sized default font")
            d.rectangle([30, 540, 372, 575], fill=tuple(int(v) for v in a[560, 6]))
            d.text((110, 545), "Gutter due Friday", fill=(150, 140, 122), font=font)
        if ring:  # remove the 1pt pageCardEdge ring from the card
            b = np.asarray(im).copy()
            reg = b[600:790]
            m = np.linalg.norm(reg.astype(int) - np.array([163, 150, 111]), axis=2) < 40
            reg[m] = (244, 239, 230)
            im = Image.fromarray(b)
        p = os.path.join(tempfile.mkdtemp(prefix="fc-defect-"), "today-light-defect.png")
        im.save(p)
        return p

    def test_low_contrast_ink_on_the_dusk_page_is_caught(self):
        flags = run_legacy([self._defect()])[0]["flags"]
        self.assertTrue(any(f.startswith("text ") for f in flags), flags)
        self.assertTrue(any("ink not allowed on page" in f for f in flags), flags)

    def test_card_without_page_edge_is_caught(self):
        flags = run_legacy([self._defect(text=False, ring=True)])[0]["flags"]
        self.assertTrue(any("card floats on page" in f for f in flags), flags)

    def test_hero_in_a_card_fails_density(self):
        a = np.asarray(Image.open(LIGHT).convert("RGB")).copy()
        reg = a[96:446, 14:388].astype(int)
        page = a[96:446, 6:7].astype(int)
        m = np.linalg.norm(reg - page, axis=2) < 40
        a[96:446, 14:388][m] = (255, 255, 255)
        a[96:98, 14:388] = (163, 150, 111); a[444:446, 14:388] = (163, 150, 111)
        a[96:446, 14:16] = (163, 150, 111); a[96:446, 386:388] = (163, 150, 111)
        p = os.path.join(tempfile.mkdtemp(prefix="fc-hic-"), "today-light-card.png")
        Image.fromarray(a).save(p)
        r = self.dens(p)
        self.assertEqual(r["verdict"], "FAIL")
        self.assertTrue(any(c["rule"].startswith("H hero not in a card") and not c["pass_"] for c in r["checks"]), r["checks"])

    @unittest.skipUnless(os.path.isdir(FULL), "full-size frames not on this machine")
    def test_full_size_frames(self):
        for n in ("today-light-L-windows-lit", "today-dark-L-windows-lit"):
            r = fc.analyse(os.path.join(FULL, n + ".png"), "default", 3.0, 0.88, None, "iphone")
            rows = r["summary"]["row_heights_pt"]
            self.assertEqual(len(rows), 2)
            self.assertTrue(all(63.7 <= h <= 64.4 for h in rows), rows)
            self.assertEqual(r["verdict"], "PASS")


class HeroMode(unittest.TestCase):
    def test_state_comes_from_the_last_token(self):
        self.assertEqual(fc.frame_state("today-dark-L-windows-lit.png"), "lit")
        self.assertEqual(fc.frame_state("today-dark-L-windows-dark.png"), "unlit")
        self.assertEqual(fc.frame_state("just-started-light-L-workLamp-off.png"), "unlit")
        self.assertIsNone(fc.frame_state("today-dark-L.png"))

    def test_p99_contrast_and_report(self):
        rep, _ = fc.hero_frame_report(LIGHT, "default", 1.0)
        self.assertGreater(rep["p99_contrast"], 3.0)
        self.assertEqual([c["verdict"] for c in rep["checks"] if c["rule"] == "p99_contrast"], ["PASS"])
        self.assertIn("saturation_share", rep)

    def test_blocked_without_art(self):
        p = os.path.join(tempfile.mkdtemp(), "plain.png")
        Image.fromarray(np.full((874, 402, 3), (238, 242, 250), np.uint8)).save(p)
        rep, _ = fc.hero_frame_report(p, "default", 1.0)
        self.assertEqual(rep["checks"][0]["verdict"], "BLOCKED")

    def test_window_delta(self):
        d = tempfile.mkdtemp()
        lit, unlit = os.path.join(d, "half-light-L-windows-lit.png"), os.path.join(d, "half-light-L-windows-dark.png")
        a = np.full((100, 100, 3), 60, np.uint8)
        Image.fromarray(a).save(unlit)
        b = a.copy(); b[20:40, 20:40] = 200
        Image.fromarray(b).save(lit)
        boxes = [[0.2, 0.2, 0.4, 0.4]]
        self.assertEqual(fc.window_delta(lit, unlit, boxes)["verdict"], "PASS")
        self.assertEqual(fc.window_delta(lit, unlit, None)["verdict"], "BLOCKED")
        same = os.path.join(d, "copy.png")
        Image.fromarray(b).save(same)
        self.assertEqual(fc.window_delta(lit, same, boxes)["verdict"], "FAIL")   # identical bytes: state not captured
        dim = os.path.join(d, "dim.png")
        c = a.copy(); c[20:40, 20:40] = 62
        Image.fromarray(c).save(dim)
        self.assertEqual(fc.window_delta(dim, unlit, boxes)["verdict"], "FAIL")



class MidwordBreaks(unittest.TestCase):
    @staticmethod
    def L(text, y, x=100, w=600, h=40):
        return dict(text=text, x=x, y=y, w=w, h=h)

    def test_hyphen_break_is_caught(self):
        hits = fc.midword_breaks([self.L("Notifica-", 100), self.L("tions", 150)])
        self.assertEqual([(a, b) for a, b, _ in hits], [("Notifica-", "tions")])

    def test_clean_wrap_is_not_flagged(self):
        self.assertEqual(fc.midword_breaks([self.L("Material", 100), self.L("participation", 150)]), [])

    def test_hyphen_before_capital_or_digit_is_not_a_break(self):
        self.assertEqual(fc.midword_breaks([self.L("Self-", 100), self.L("Employed", 150)]), [])

    def test_short_compound_prefix_is_not_a_break(self):
        self.assertEqual(fc.midword_breaks([self.L("Apple's on-", 100), self.L("device model", 150)]), [])

    def test_far_apart_lines_are_not_joined(self):
        self.assertEqual(fc.midword_breaks([self.L("Notifica-", 100), self.L("tions", 900)]), [])

    def test_other_column_is_not_joined(self):
        self.assertEqual(fc.midword_breaks([self.L("Notifica-", 100, x=50, w=200), self.L("tions", 150, x=700, w=200)]), [])



def make_tab(title_top_pt, content_top_pt, name, subtitle=False, title=True, back_circle=False):
    """A tab frame: canvas, a 25pt title ink block at title_top_pt (x 20-160pt), optional subtitle line, and a white
    card from content_top_pt. Optionally a back circle under the title's left edge (header furniture)."""
    s = 3
    a = np.zeros((H, W, 3), np.uint8)
    a[:] = CANVAS
    if title:
        t0 = int(title_top_pt * s)
        a[t0:t0 + 75, 60:480] = INK
        if back_circle:
            a[t0 + 60:t0 + 100, 30:150] = (226, 232, 245)
    if subtitle:
        s0 = int((title_top_pt + 31) * s)
        a[s0:s0 + 36, 60:400] = (74, 80, 104)
    c0 = int(content_top_pt * s)
    a[c0:c0 + 600, 60:1146] = CARD
    path = os.path.join(tempfile.mkdtemp(prefix="fc-consist-"), name + ".png")
    Image.fromarray(a).save(path)
    return path


class Consistency(unittest.TestCase):
    def test_same_header_passes(self):
        ms = [fc.header_metrics(make_tab(80, 130, f"t{i}"), 3.0) for i in range(4)]
        checks, ok = fc.consistency_verdict(ms)
        self.assertTrue(ok, checks)
        self.assertAlmostEqual(ms[0]["title_baseline_pt"], 105.0, delta=0.5)
        self.assertAlmostEqual(ms[0]["gap_pt"], 25.0, delta=0.5)

    def test_baseline_off_by_2pt_fails_s2(self):
        ms = [fc.header_metrics(make_tab(80, 130, "a"), 3.0), fc.header_metrics(make_tab(82, 132, "b"), 3.0)]
        checks, ok = fc.consistency_verdict(ms)
        self.assertFalse(ok)
        s2 = next(c for c in checks if c["rule"].startswith("S2"))
        self.assertFalse(s2["pass_"])
        self.assertAlmostEqual(s2["spread_pt"], 2.0, delta=0.4)

    def test_baseline_within_1pt_passes_s2(self):
        ms = [fc.header_metrics(make_tab(80, 130, "a"), 3.0), fc.header_metrics(make_tab(80.67, 130.67, "b"), 3.0)]
        s2 = next(c for c in fc.consistency_verdict(ms)[0] if c["rule"].startswith("S2"))
        self.assertTrue(s2["pass_"], s2)

    def test_gap_off_by_3pt_fails_s3(self):
        ms = [fc.header_metrics(make_tab(80, 130, "a"), 3.0), fc.header_metrics(make_tab(80, 133, "b"), 3.0)]
        checks, ok = fc.consistency_verdict(ms)
        s3 = next(c for c in checks if c["rule"].startswith("S3"))
        self.assertFalse(s3["pass_"])

    def test_missing_title_fails_s1(self):
        ms = [fc.header_metrics(make_tab(80, 130, "a"), 3.0), fc.header_metrics(make_tab(80, 300, "b", title=False), 3.0)]
        s1 = next(c for c in fc.consistency_verdict(ms)[0] if c["rule"].startswith("S1"))
        self.assertFalse(s1["pass_"])
        self.assertEqual(s1["detail"], ["b.png"])

    def test_subtitle_is_header_not_content(self):
        m = fc.header_metrics(make_tab(80, 160, "sub", subtitle=True), 3.0)
        self.assertAlmostEqual(m["title_baseline_pt"], 105.0, delta=0.5)
        self.assertAlmostEqual(m["last_baseline_pt"], 123.0, delta=0.7)  # subtitle bottom
        self.assertAlmostEqual(m["content_top_pt"], 160.0, delta=0.5)

    def test_back_circle_is_not_content(self):
        m = fc.header_metrics(make_tab(80, 140, "back", back_circle=True), 3.0)
        self.assertAlmostEqual(m["content_top_pt"], 140.0, delta=0.5)

    def test_hero_frame_skips_gap_rule(self):
        ms = [fc.header_metrics(make_tab(80, 130, "a"), 3.0), fc.header_metrics(make_tab(80, 200, "today"), 3.0)]
        _, ok = fc.consistency_verdict(ms, no_gap={"today.png"})
        self.assertTrue(ok)
        _, ok2 = fc.consistency_verdict(ms)
        self.assertFalse(ok2)


class ConsistencyAX(unittest.TestCase):
    def test_title_after_back_chevron_at_ax3_is_found(self):
        """Settings at AX3: a back chevron leads the row and the title is ~66pt of ink (was read as 'no title')."""
        s = 3
        a = np.zeros((H, W, 3), np.uint8)
        a[:] = CANVAS
        t0 = 80 * s
        a[t0 + 10 * s:t0 + 52 * s, 20 * s:64 * s] = (226, 232, 245)       # the back circle
        a[t0 + 22 * s:t0 + 40 * s, 36 * s:46 * s] = INK                   # the chevron
        a[t0:t0 + 66 * s, 76 * s:330 * s] = INK                           # the AX3 title glyphs
        a[(80 + 100) * s:(80 + 300) * s, 60:1146] = CARD
        path = os.path.join(tempfile.mkdtemp(prefix="fc-ax-"), "settings-ax3.png")
        Image.fromarray(a).save(path)
        m = fc.header_metrics(path, 3.0)
        self.assertIsNotNone(m["title_baseline_pt"], "the title after the chevron must be found")
        self.assertAlmostEqual(m["title_baseline_pt"], 146.0, delta=0.7)
        self.assertAlmostEqual(m["content_top_pt"], 180.0, delta=0.5)


class ConsistencyDark(unittest.TestCase):
    def test_dark_frame_reads_light_ink(self):
        s = 3
        a = np.zeros((H, W, 3), np.uint8)
        a[:] = (11, 18, 48)                       # night canvas #0B1230
        a[80 * s:80 * s + 75, 60:480] = (242, 244, 250)   # textPrimary title, 25pt
        a[130 * s:430 * s, 60:1146] = (20, 28, 63)        # card #141C3F
        path = os.path.join(tempfile.mkdtemp(prefix="fc-dark-"), "inbox-dark.png")
        Image.fromarray(a).save(path)
        m = fc.header_metrics(path, 3.0)
        self.assertEqual(m["theme"], "dark")
        self.assertAlmostEqual(m["title_baseline_pt"], 105.0, delta=0.5)
        self.assertAlmostEqual(m["content_top_pt"], 130.0, delta=0.5)


class ConsistencyGroups(unittest.TestCase):
    def _args(self, **kw):
        import argparse
        base = dict(frames=[], hero=None, sheet=None, sheet_task=None, sheet_item=None, detail=None, scale=3.0)
        base.update(kw)
        return argparse.Namespace(**base)

    def test_sheet_kinds_are_compared_within_their_kind(self):
        # task sheets agree with each other; the item sheet sits elsewhere: still a PASS (no cross-kind check)
        t1, t2 = make_tab(90, 140, "task1"), make_tab(90, 140, "task2")
        item = make_tab(84, 150, "item")
        g = fc.consistency_groups(self._args(frames=[make_tab(80, 130, "inbox")], sheet_task=[t1, t2], sheet_item=[item]))
        self.assertEqual(set(g), {"tabs", "sheet-task", "sheet-item"})
        for name, (ms, nogap) in g.items():
            _, ok = fc.consistency_verdict(ms, no_gap=nogap)
            self.assertTrue(ok, name)

    def test_drift_inside_a_kind_fails(self):
        g = fc.consistency_groups(self._args(frames=[make_tab(80, 130, "inbox")],
                                             sheet_task=[make_tab(90, 140, "a"), make_tab(93, 143, "b")]))
        _, ok = fc.consistency_verdict(g["sheet-task"][0])
        self.assertFalse(ok)

    def test_old_sheet_flag_is_task(self):
        g = fc.consistency_groups(self._args(frames=[make_tab(80, 130, "inbox")], sheet=[make_tab(90, 140, "a")]))
        self.assertIn("sheet-task", g)


class ConsistencyBackCircleXXL(unittest.TestCase):
    def test_wide_back_circle_hanging_below_a_descenderless_title_is_header(self):
        s = 3
        a = np.zeros((H, W, 3), np.uint8)
        a[:] = CANVAS
        a[79 * s:107 * s, 80 * s:240 * s] = INK                  # "iCloud" at XXL, no descenders
        a[92 * s:120 * s, 12 * s:78 * s] = (226, 232, 245)        # the back circle at XXL, 66pt wide
        a[133 * s:400 * s, 60:1146] = CARD
        path = os.path.join(tempfile.mkdtemp(prefix="fc-back-"), "icloud-xxl.png")
        Image.fromarray(a).save(path)
        m = fc.header_metrics(path, 3.0)
        self.assertAlmostEqual(m["content_top_pt"], 133.0, delta=0.5)
        self.assertAlmostEqual(m["gap_pt"], 26.0, delta=0.7)


class ConsistencyColumn(unittest.TestCase):
    def test_band_b_frame_is_measured_as_its_content_column(self):
        """iPad (standard 1.27 IP1): --column measures the centred 672pt column exactly as if the frame had
        been cropped to it, so the phone's trailing slot and gutters apply (real 13" Records: header end
        147.5 on the whole frame, 139.0 in the column)."""
        s, wpt, hpt = 2, 1032, 1376
        inset = (wpt - 672) // 2
        a = np.zeros((hpt * s, wpt * s, 3), np.uint8)
        a[:] = CANVAS
        a[30 * s:hpt * s, 0:6 * s] = (200, 40, 40)                                      # off-column marks
        t0 = 113
        a[t0 * s:(t0 + 25) * s, (inset + 20) * s:(inset + 140) * s] = INK
        a[(t0 + 51) * s:(t0 + 300) * s, (inset + 20) * s:(inset + 652) * s] = CARD
        d = tempfile.mkdtemp(prefix="fc-col-")
        wide, crop = os.path.join(d, "wide.png"), os.path.join(d, "crop.png")
        Image.fromarray(a).save(wide)
        Image.fromarray(a[:, inset * s:(wpt - inset) * s]).save(crop)
        col, ref = fc.header_metrics(wide, 2.0, column_pt=672), fc.header_metrics(crop, 2.0)
        for k in ("title_baseline_pt", "header_end_pt", "content_top_pt", "gap_pt"):
            self.assertEqual(col[k], ref[k], k)
        self.assertAlmostEqual(col["content_top_pt"], 164.0, delta=0.5)
        # A frame narrower than the column is measured whole.
        self.assertEqual(fc.header_metrics(crop, 2.0, column_pt=700)["gap_pt"], ref["gap_pt"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
