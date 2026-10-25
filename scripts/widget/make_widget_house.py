#!/usr/bin/env python3
"""Cut the crafted-house thumbnails the widget extension draws (standard §H.5, plan package I).

The widget extension cannot read the app's asset catalog, and the art lane has not rendered the
house-only `craft_thumb_<stage>` set yet. So each widget thumbnail is cut here from the five lit
and five unlit stills (Assets.xcassets/Craft, dusk = Any, night = Dark):

  1. crop the pinned camera square around the house,
  2. dissolve the lot's soil block and the lawn's far edges (soft mask), so the house stands on a
     pool of lawn with a contact shadow, no plinth,
  3. resize to 360px (@3x of the 120pt widget thumbnail), save as HEIC with alpha.

The same crop is used for every stage, so the early stages read small by their own art, as in
the app's skyline. Output: Sources/Widget/WidgetAssets.xcassets/House/wg_thumb_<stage>[-unlit].
When the art lane ships the real `craft_thumb_*` renders, switch SRC_THUMB on and drop the mask.

Usage (repo root): ~/AgentScratch/landlordhours/2026-10-22/venv/bin/python scripts/widget/make_widget_house.py
Needs Pillow + numpy and macOS `sips` (HEIC with alpha).
"""
import json, os, subprocess, tempfile
import numpy as np
from PIL import Image

SRC = "Assets.xcassets/Craft"
DST = "Sources/Widget/WidgetAssets.xcassets/House"
STAGES = ["started", "frame70", "framing", "half", "complete"]
BOX = (80, 20, 960, 900)     # the house's bounding square in the 1206px still (house only, standard H.5)
NIGHT_UNLIT_GAIN = 3.4        # linear gain on the unlit night art so it clears 3:1 against the night page
SIZE = 360                    # 120pt @3x


def smooth(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


def run(*args):
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def cut(heic_path, tmp, lift=False):
    png = os.path.join(tmp, "in.png")
    run("sips", "-s", "format", "png", heic_path, "--out", png)
    crop = Image.open(png).convert("RGBA").crop(BOX)
    w, h = crop.size
    yy, xx = np.mgrid[0:h, 0:w]
    xx, yy = xx / w, yy / h
    d = np.sqrt(((xx - 0.50) / 0.62) ** 2 + ((yy - 0.50) / 0.58) ** 2)
    mask = smooth((1.0 - d) / 0.26) * (1 - smooth((yy - 0.80) / 0.17))
    arr = np.array(crop)
    if lift:
        lin = (arr[:, :, :3] / 255.0) ** 2.2 * NIGHT_UNLIT_GAIN
        arr[:, :, :3] = (np.clip(lin, 0, 1) ** (1 / 2.2) * 255).astype(np.uint8)
    arr[:, :, 3] = (arr[:, :, 3] * mask).astype(np.uint8)
    return Image.fromarray(arr).resize((SIZE, SIZE), Image.LANCZOS)


def main():
    os.makedirs(DST, exist_ok=True)
    json.dump({"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": False}},
              open(os.path.join(DST, "Contents.json"), "w"), indent=2)
    total = 0
    with tempfile.TemporaryDirectory() as tmp:
        for stage in STAGES:
            for lit in (True, False):
                base = f"craft_{stage}" + ("" if lit else "-unlit")
                name = f"wg_thumb_{stage}" + ("" if lit else "-unlit")
                d = os.path.join(DST, name + ".imageset")
                os.makedirs(d, exist_ok=True)
                images = []
                for appearance in ("light", "dark"):
                    src = f"{SRC}/{base}.imageset/{base}_{appearance}.heic"
                    out_png = os.path.join(tmp, "out.png")
                    cut(src, tmp, lift=(not lit and appearance == 'dark')).save(out_png)
                    fn = f"{name}{'-dark' if appearance == 'dark' else ''}@3x.heic"
                    run("sips", "-s", "format", "heic", "-s", "formatOptions", "85", out_png, "--out", os.path.join(d, fn))
                    total += os.path.getsize(os.path.join(d, fn))
                    entry = {"idiom": "universal", "filename": fn, "scale": "3x"}
                    if appearance == "dark":
                        entry["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
                    images.append(entry)
                json.dump({"images": images, "info": {"author": "xcode", "version": 1}},
                          open(os.path.join(d, "Contents.json"), "w"), indent=2)
    print(f"{len(STAGES) * 4} thumbnails, {total / 1024:.0f} KB")


if __name__ == "__main__":
    main()
