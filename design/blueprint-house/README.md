# Blueprint house (LandlordHours 2.0 hero art)

One scripted Blender model with real construction stages. Brian approved the look on 2026-10-18.

- `blueprint_house.blend`: the model. The stage parameter controls lot → slab → framing % → roof → siding % → finished (lit windows, keys).
- `scripts/`: `house.py` builds the geometry, `render.py` renders the built and linework passes, `composite.py`, `clean_alpha.py` and `qa.py` check registration and alpha, and `save_blend.py`.
- Render: Cycles on Metal at 2048², transparent PNG. The built pass and cyan linework pass come from the same camera. In the app, draw linework BELOW the built pass.
- Python: Blender.app hung at first launch (Gatekeeper). The working route is the `bpy` 5.0.1 module in a venv (`python3 -m venv .venv && .venv/bin/pip install bpy==5.0.1`), then `.venv/bin/python scripts/render.py`.
- The full render set (about 350 MB, regenerable) lives in ~/AgentScratch/landlordhours/2026-10-18/blender/renders/. Final app assets get exported into Assets.xcassets during the build.

## WP-A production assets (2026-10-19)

The app assets in `Assets.xcassets/Blueprint/` are generated, not hand-made:

```
scripts/render_all.sh ~/AgentScratch/landlordhours/<date>/wp-a/renders        # tools, 19 house keyframes, confirm-row anim
.venv/bin/python scripts/post.py --renders <renders>/final --tool-renders <renders>/tools \
    --catalog ../../Assets.xcassets/Blueprint --masters exports --manifest exports/manifest.json
.venv/bin/python scripts/qa_wp_a.py ../../Assets.xcassets/Blueprint <qa_dir>
```

- `render.py KEYFRAMES`: k00 lot, k01 slab, k02–k11 framing 10–100%, k12 roof, k13–k17 siding 20–100%, k18 finished/lit.
  Each has a built pass (Any = light lighting, Dark = dark lighting) and a linework pass,
  same camera, 320 pt square, @2x/@3x. WP-A change: draw linework ABOVE built. A structure-mask pass cuts the built
  structure out of the linework, so the future house now shows over the lot and slab (drawn below, the lawn hid its lower storey)
  but never over built parts. Linework is an alpha-only template image tinted by the `bp_drafting` colour (Any #8FD3FF, Dark #60A8E6).
- `tools.py`: the 11 category tools, modelled in Blender with the house materials and light rig. 36 pt and 56 pt imagesets,
  Any/Dark; 1024 masters in `exports/tools/`.
- Confirm animation: `render.py --anim --row-only` renders 24 overlay frames (30 fps) of one clapboard row sliding in, with
  the rest of the house as a camera holdout, so each frame is registered to the hero canvas; draw them over the
  `k14_siding040` keyframe.
- `exports/manifest.json` lists every asset with its construction state for the house renderer (WP-H).

Polish done in WP-A: lit windows (emission 9 plus a bloom baked from a window-mask pass), lumpy clay shrubs and a fuller tree
kept inside the lot, catcher shadows limited to the lot plinth through shadow linking (no off-lot smudge), and linework
re-inked to the exact brand tokens.

Measured 2026-10-19 (`scripts/measure_size.sh`): Blueprint adds 9.5 MB to the universal Assets.car, 6.2 MB to an iPhone @3x
thinned download and 3.3 MB to an iPad @2x one. Render times on the Mini (Metal): built 40 s, linework 36 s, mask 19 s per
keyframe at 1920; tools 6 s each at 1024; confirm-row frames 12 s at 1440; about 65 min for the whole set.
