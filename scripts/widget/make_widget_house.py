#!/usr/bin/env python3
"""Composite the Blueprint house keyframes for the widget extension.

Widgets can't run the app's CoreImage linework pass, so each keyframe is flattened once:
built pass (light / dark appearance) + linework alpha x2.4 (HouseMotion.lineworkAlphaGain),
tinted drafting cyan #8FD3FF (the blueprint-hero linework, both modes). Output 480px (@3x of
160pt, the medium widget's house), palette-quantised to keep the extension small.

Usage: python3 scripts/widget/make_widget_house.py   (from the repo root)
"""
import json, os, sys
from PIL import Image

SRC = "Assets.xcassets/Blueprint/House"
DST = "Sources/Widget/WidgetAssets.xcassets/House"
KEYS = ["k00_lot","k01_slab","k02_frame010","k03_frame020","k04_frame030","k05_frame040","k06_frame050",
        "k07_frame060","k08_frame070","k09_frame080","k10_frame090","k11_frame100","k12_roof",
        "k13_siding020","k14_siding040","k15_siding060","k16_siding080","k17_siding100","k18_finished"]
DRAFT = (0x8F, 0xD3, 0xFF)
GAIN = 2.4
SIZE = 480

def lines_layer(path):
    a = Image.open(path).convert("RGBA").getchannel("A")
    a = a.point(lambda v: min(255, int(v * GAIN)))
    layer = Image.new("RGBA", a.size, DRAFT + (0,))
    layer.putalpha(a)
    return layer

def composite(built_path, lines_path):
    built = Image.open(built_path).convert("RGBA")
    out = built.copy()
    out.alpha_composite(lines_layer(lines_path).resize(built.size, Image.LANCZOS))
    out = out.resize((SIZE, SIZE), Image.LANCZOS)
    return out.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)

os.makedirs(DST, exist_ok=True)
json.dump({"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": False}},
          open(os.path.join(DST, "Contents.json"), "w"), indent=2)
total = 0
for k in KEYS:
    name = f"wg_house_{k}"
    d = os.path.join(DST, name + ".imageset"); os.makedirs(d, exist_ok=True)
    lines = f"{SRC}/bp_house_{k}_lines.imageset/bp_house_{k}_lines@3x.png"
    images = []
    for suffix, appearance in (("", None), ("-dark", "dark")):
        built = f"{SRC}/bp_house_{k}_built.imageset/bp_house_{k}_built{suffix}@3x.png"
        fn = f"{name}{suffix}@3x.png"
        composite(built, lines).save(os.path.join(d, fn), optimize=True)
        total += os.path.getsize(os.path.join(d, fn))
        entry = {"idiom": "universal", "filename": fn, "scale": "3x"}
        if appearance:
            entry["appearances"] = [{"appearance": "luminosity", "value": appearance}]
        images.append(entry)
    json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, open(os.path.join(d, "Contents.json"), "w"), indent=2)
print(f"{len(KEYS)} keyframes, {total/1024:.0f} KB")
