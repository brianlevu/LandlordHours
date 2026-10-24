"""Fetch CC0 Poly Haven assets (data only: jpg/png/hdr/gltf/bin). Never executes anything downloaded."""
import json, os, sys, urllib.request
OUT = os.environ.get('LH_CC0_DIR', os.path.expanduser('~/AgentScratch/landlordhours/2026-10-24/dir-craft2/downloads'))
LOG = os.path.join(OUT, 'manifest.jsonl')
def get(url, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if os.path.exists(dst) and os.path.getsize(dst) > 0: return
    req = urllib.request.Request(url, headers={'User-Agent': 'lh-craft2-asset-fetch'})
    with urllib.request.urlopen(req, timeout=120) as r, open(dst, 'wb') as f: f.write(r.read())
def api(path):
    req = urllib.request.Request('https://api.polyhaven.com/' + path, headers={'User-Agent': 'lh-craft2-asset-fetch'})
    return json.load(urllib.request.urlopen(req, timeout=60))
def rec(aid, kind, files):
    info = api('info/' + aid)
    with open(LOG, 'a') as f:
        f.write(json.dumps(dict(id=aid, kind=kind, name=info.get('name'), authors=list(info.get('authors', {}).keys()),
            page='https://polyhaven.com/a/' + aid, license='CC0 1.0', files=files)) + '\n')
def model(aid, res='1k', extra_maps=()):
    d = api('files/' + aid); g = d['gltf'][res]['gltf']; base = os.path.join(OUT, aid); files = [g['url']]
    get(g['url'], os.path.join(base, os.path.basename(g['url'])))
    for rel, v in g['include'].items():
        get(v['url'], os.path.join(base, rel)); files.append(v['url'])
    for m in extra_maps:
        u = d[m][res]['jpg']['url'] if 'jpg' in d[m][res] else d[m][res]['png']['url']
        get(u, os.path.join(base, 'textures', os.path.basename(u))); files.append(u)
    rec(aid, 'model', files)
def tex(aid, res='1k', maps=('Diffuse', 'nor_gl', 'Rough', 'AO')):
    d = api('files/' + aid); base = os.path.join(OUT, aid); files = []
    for m in maps:
        if m not in d: continue
        u = d[m][res]['jpg']['url']; get(u, os.path.join(base, os.path.basename(u))); files.append(u)
    rec(aid, 'texture', files)
def hdri(aid, res='2k'):
    d = api('files/' + aid); u = d['hdri'][res]['hdr']['url']
    get(u, os.path.join(OUT, aid, os.path.basename(u))); rec(aid, 'hdri', [u])
if __name__ == '__main__':
    kind, aid = sys.argv[1], sys.argv[2]
    res = sys.argv[3] if len(sys.argv) > 3 else None
    extra = sys.argv[4].split(',') if len(sys.argv) > 4 else ()
    if kind == 'model': model(aid, res or '1k', extra)
    elif kind == 'tex': tex(aid, res or '1k')
    else: hdri(aid, res or '2k')
    print('ok', kind, aid)
