# Dev only (e2e.sh): osm_for_place.py place.json out_op.json writes the OSM map for the box
# the game asks Overpass for, from the OSM API (split into tiles when too big), as an Overpass answer.
import json, sys, math, urllib.request, subprocess, os
p = json.load(open(sys.argv[1]))
lat, lon = float(p['lat']), float(p['lon'])
box = p.get('box', [])
if p.get('golf') and len(box) == 4:
    s, n, w, e = float(box[0]) - .002, float(box[1]) + .002, float(box[2]) - .003, float(box[3]) + .003
else:
    dl = 1500 / 111320.0; do = dl / math.cos(math.radians(lat))
    s, n, w, e = lat - dl, lat + dl, lon - do, lon + do
UA = {'User-Agent': 'openlinks2003-dev-bench'}
def tile(s, w, n, e, depth=0):
    u = f'https://api.openstreetmap.org/api/0.6/map.json?bbox={w},{s},{e},{n}'
    try:
        return [json.loads(urllib.request.urlopen(urllib.request.Request(u, headers=UA), timeout=180).read())]
    except urllib.error.HTTPError as ex:
        if ex.code == 400 and depth < 3:
            ms, mw = (s + n) / 2, (w + e) / 2
            out = []
            for a in [(s, w, ms, mw), (s, mw, ms, e), (ms, w, n, mw), (ms, mw, n, e)]:
                out += tile(*a, depth + 1)
            return out
        raise
parts = tile(s, w, n, e)
els = {}
for d in parts:
    for x in d['elements']:
        els[(x['type'], x['id'])] = x
merged = {'elements': list(els.values())}
tmp = sys.argv[2] + '.map.json'
json.dump(merged, open(tmp, 'w'))
subprocess.run(['python3', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'osm2overpass.py'), tmp, sys.argv[2]], check=True)
print('ok', len(parts), 'tiles', len(els), 'elements')
