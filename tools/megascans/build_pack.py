#!/usr/bin/env python3
"""Bakes the plant cards of the private Megascans pack (docs/megascans-pack.md)
from a Megascans download and its catalogue.json: one 2 x 2 card atlas per
3D plant that ships billboard textures, in PACK/foliage/cards/<uid8>.png,
and the list the game reads (MegascansCards), PACK/foliage/cards.json.
Never commit the output.

    python3 build_pack.py MEGASCANS_DIR PACK_DIR [--only TITLE_WORD]

Needs numpy and Pillow. Plants already baked are kept (delete one to redo it).
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import billboard_cards  # noqa: E402

SKIP = ('log', 'stump', 'trunk', 'dead leaves', 'ivy', 'burnt')
# Typical full height in metres when the catalogue has none.
HEIGHT = {'grass': 0.7, 'fern': 0.8, 'flower': 0.6, 'rush': 0.9, 'reed': 1.8, 'shrub': 1.3}
# Title words -> (kind, height_m, golf roles); first match wins.
RULES = [
    ('giant reed', 'reed', 3.0, ['water_edge']),
    ('reed', 'reed', 1.8, ['water_edge']),
    ('bulrush', 'reed', 1.8, ['water_edge']),
    ('swamp', 'rush', 1.0, ['water_edge']),
    ('rush', 'rush', 0.8, ['water_edge', 'heath']),
    ('sedge', 'rush', 0.6, ['dune', 'water_edge']),
    ('cotton grass', 'grass', 0.4, ['heath', 'water_edge']),
    ('marram', 'grass', 0.9, ['dune', 'links_fescue']),
    ('xeric', 'grass', 0.6, ['links_fescue', 'dune', 'deep_rough']),
    ('wild grass', 'grass', 0.7, ['links_fescue', 'deep_rough', 'meadow']),
    ('dry grass', 'grass', 0.6, ['links_fescue', 'deep_rough']),
    ('thatching', 'grass', 1.0, ['deep_rough', 'meadow']),
    ('tall grass', 'grass', 1.0, ['deep_rough', 'meadow']),
    ('meadow', 'grass', 0.7, ['meadow', 'deep_rough']),
    ('velvet', 'grass', 0.6, ['meadow', 'deep_rough']),
    ('cock', 'grass', 0.9, ['meadow', 'deep_rough']),
    ('wheat', 'grass', 0.8, ['meadow']),
    ('tufted', 'grass', 0.5, ['deep_rough', 'heath']),
    ('clump', 'grass', 0.5, ['deep_rough']),
    ('fern', 'fern', 0.8, ['woodland_edge', 'heath']),
    ('poppy', 'flower', 0.6, ['meadow']),
    ('dandelion', 'flower', 0.25, ['meadow']),
    ('buttercup', 'flower', 0.3, ['meadow']),
    ('clover', 'flower', 0.15, ['meadow']),
    ('nettle', 'flower', 0.6, ['woodland_edge', 'meadow']),
    ('daffodil', 'flower', 0.4, ['meadow', 'woodland_edge']),
    ('birch', 'shrub', 1.0, ['heath', 'scrub']),
    ('willow', 'shrub', 1.2, ['scrub', 'water_edge']),
    ('shrub', 'shrub', 1.3, ['scrub']),
    ('bush', 'shrub', 1.3, ['scrub']),
]


def describe(rec):
    title = rec['title'].lower()
    for word, kind, h, roles in RULES:
        if word in title:
            break
    else:
        kind = (rec.get('plant') or {}).get('kind') or 'grass'
        kind = kind if kind in HEIGHT else 'grass'
        h, roles = HEIGHT[kind], ['deep_rough']
    given = (rec.get('plant') or {}).get('height_m')
    return kind, float(given) if given and 0.1 < float(given) < 6 and kind == 'shrub' else h, roles


def main():
    src, pack = sys.argv[1], sys.argv[2]
    only = sys.argv[4].lower() if len(sys.argv) > 4 and sys.argv[3] == '--only' else None
    cat = json.load(open(os.path.join(src, 'catalogue.json')))
    out_dir = os.path.join(pack, 'foliage', 'cards')
    os.makedirs(out_dir, exist_ok=True)
    cards = []
    for rec in cat:
        if rec.get('use') != 'plant_mesh' or any(w in rec['title'].lower() for w in SKIP):
            continue
        if only and only not in rec['title'].lower():
            continue
        d = os.path.join(src, rec['dir'])
        names = os.listdir(d) if os.path.isdir(d) else []
        if not any(n.endswith('Billboard_BaseColor.jpg') for n in names) or not any(n.endswith('Billboard_Opacity.jpg') for n in names):
            continue
        uid8 = rec['uid'][:8]
        file = 'cards/%s.png' % uid8
        path = os.path.join(pack, 'foliage', file)
        if not os.path.exists(path):
            img = billboard_cards.atlas([d])
            if img is None:
                print('no sprites:', rec['title'])
                continue
            img.save(path)
        kind, h, roles = describe(rec)
        cards.append({'uid': uid8, 'title': rec['title'], 'kind': kind, 'height_m': round(h, 2), 'roles': roles,
                      'environment': rec.get('environment', []), 'file': file})
        print('%-28s %-6s %.1f m %s' % (rec['title'], kind, h, ','.join(roles)))
    with open(os.path.join(pack, 'foliage', 'cards.json'), 'w') as f:
        json.dump({'source': 'Quixel Megascans (private pack, never redistribute)', 'cards': cards}, f, indent=1)
    print(len(cards), 'cards')


if __name__ == '__main__':
    main()
