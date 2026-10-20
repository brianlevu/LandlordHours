"""Save the scene as a .blend at a given state (no render).
usage: save_blend.py <out.blend> [state]
Inside Blender, change stage with: Text editor -> run 'set_state' text after editing STATE."""
import os, sys, json
sys.path.insert(0, os.path.dirname(__file__))
import bpy
import house as H, render as R

out = os.path.abspath(sys.argv[1]); state = sys.argv[2] if len(sys.argv) > 2 else 'stage2_frame40'
H.build_all(); R.setup_render(2048, 128); R.setup_camera(); catcher = R.setup_lights('light')
R.apply_state(R.STATES[state], 'built', catcher)
for fn in ('house.py', 'render.py'):
    t = bpy.data.texts.new(fn); t.from_string(open(os.path.join(os.path.dirname(__file__), fn)).read())
setter = bpy.data.texts.new('set_state.py')
setter.from_string('''# Edit STATE (stage 0-5, p 0..1) and run this text to show that construction state.
STATE = {"stage": 2, "p": 0.40}
import bpy
for ob in bpy.data.objects:
    if "stage_req" not in ob: continue
    sr, t = ob["stage_req"], ob["t"]
    if ob["kind"] == "stake": built = STATE["stage"] == 0
    elif sr < 0: built = True
    else: built = STATE["stage"] > sr or (STATE["stage"] == sr and t <= STATE.get("p", 1.0) + 1e-9)
    ob.hide_render = ob.hide_viewport = not built
''')
bpy.context.scene['blueprint_state'] = json.dumps(R.STATES[state])
bpy.ops.wm.save_as_mainfile(filepath=out)
print('SAVED', out)
