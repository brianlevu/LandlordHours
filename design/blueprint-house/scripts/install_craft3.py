"""Copy Craft pass-3 renders into the app catalog (images + clips only; never touches Swift).

usage: python3 install_craft3.py --stills DIR/renders/stills --clips DIR/renders/anim --repo /path/to/LandlordHours
- Stills: craft_<stage>_<v>.png -> Assets.xcassets/Craft/craft_<stage>.imageset/
          craft_<stage>-unlit_<v>.png -> Assets.xcassets/Craft/craft_<stage>-unlit.imageset/ (Contents.json written if new)
- Clips:  craft_build_{light,dark}.mov -> Sources/Resources/Craft/
"""
import argparse, json, os, shutil

ST = ['started', 'frame70', 'framing', 'half', 'complete']

def contents(name):
    return {"images": [
        {"filename": f"{name}_light.png", "idiom": "universal", "scale": "3x"},
        {"appearances": [{"appearance": "luminosity", "value": "dark"}], "filename": f"{name}_dark.png", "idiom": "universal", "scale": "3x"}],
        "info": {"author": "xcode", "version": 1}}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--stills', required=True); ap.add_argument('--clips', default=''); ap.add_argument('--repo', required=True)
    a = ap.parse_args()
    cat = os.path.join(a.repo, 'Assets.xcassets', 'Craft')
    for st in ST:
        for suf in ('', '-unlit'):
            name = f'craft_{st}{suf}'
            d = os.path.join(cat, name + '.imageset'); os.makedirs(d, exist_ok=True)
            cj = os.path.join(d, 'Contents.json')
            if not os.path.exists(cj):
                with open(cj, 'w') as f:
                    f.write(json.dumps(contents(name), indent=2) + '\n')
            for v in ('light', 'dark'):
                shutil.copyfile(os.path.join(a.stills, f'{name}_{v}.png'), os.path.join(d, f'{name}_{v}.png'))
                print('installed', name, v)
    if a.clips:
        res = os.path.join(a.repo, 'Sources', 'Resources', 'Craft')
        for v in ('light', 'dark'):
            shutil.copyfile(os.path.join(a.clips, f'craft_build_{v}.mov'), os.path.join(res, f'craft_build_{v}.mov'))
            print('installed clip', v)

if __name__ == '__main__':
    main()
