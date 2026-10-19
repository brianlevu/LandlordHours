# Blueprint house (LandlordHours 2.0 hero art)

One scripted Blender model with real construction stages. Brian approved the look on 2026-10-18.

- `blueprint_house.blend`: the model. The stage parameter controls lot → slab → framing % → roof → siding % → finished (lit windows, keys).
- `scripts/`: `house.py` builds the geometry, `render.py` renders the built and linework passes, `composite.py`, `clean_alpha.py` and `qa.py` check registration and alpha, and `save_blend.py`.
- Render: Cycles on Metal at 2048², transparent PNG. The built pass and cyan linework pass come from the same camera. In the app, draw linework BELOW the built pass.
- Python: Blender.app hung at first launch (Gatekeeper). The working route is the `bpy` 5.0.1 module in a venv (`python3 -m venv .venv && .venv/bin/pip install bpy==5.0.1`), then `.venv/bin/python scripts/render.py`.
- The full render set (about 350 MB, regenerable) lives in ~/AgentScratch/landlordhours/2026-10-18/blender/renders/. Final app assets get exported into Assets.xcassets during the build.

Known polish items: glowing lit windows, better shrubs and tree, the tree shadow smudge, and cyan contrast on light backgrounds.
