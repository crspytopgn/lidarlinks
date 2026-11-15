#!/usr/bin/env python3
"""Reads the triangles of a binary FBX file (version 7.x, as Megascans ships
its 3D plants): positions in metres with +y up, per-corner normals and UVs.
Only what the plant baker (plant_meshes.py) needs: every Geometry's mesh,
placed by its Model's Lcl Translation / Rotation / Scaling and the file's
axis and unit settings. Needs numpy.

    python3 fbx_mesh.py FILE.fbx      # prints a summary
"""
import struct
import sys
import zlib

import numpy as np

_ARRAY = {'f': ('<f4', 4), 'd': ('<f8', 8), 'l': ('<i8', 8), 'i': ('<i4', 4), 'b': ('?', 1)}


class Node:
    __slots__ = ('name', 'props', 'children')

    def __init__(self, name, props, children):
        self.name, self.props, self.children = name, props, children

    def find(self, name):
        for c in self.children:
            if c.name == name:
                return c
        return None

    def all(self, name):
        return [c for c in self.children if c.name == name]


def _read_prop(buf, o):
    t = chr(buf[o])
    o += 1
    if t in _ARRAY:
        n, enc, clen = struct.unpack_from('<III', buf, o)
        o += 12
        raw = bytes(buf[o:o + clen])
        o += clen
        if enc == 1:
            raw = zlib.decompress(raw)
        dt, _ = _ARRAY[t]
        return np.frombuffer(raw, dtype=dt, count=n), o
    if t == 'S' or t == 'R':
        n = struct.unpack_from('<I', buf, o)[0]
        o += 4
        v = bytes(buf[o:o + n])
        return (v.decode('utf-8', 'replace') if t == 'S' else v), o + n
    fmt = {'Y': '<h', 'C': '<?', 'I': '<i', 'F': '<f', 'D': '<d', 'L': '<q'}[t]
    return struct.unpack_from(fmt, buf, o)[0], o + struct.calcsize(fmt)


def _read_node(buf, o, wide):
    if wide:
        end, nprops, _plen = struct.unpack_from('<QQQ', buf, o)
        o += 24
    else:
        end, nprops, _plen = struct.unpack_from('<III', buf, o)
        o += 12
    nlen = buf[o]
    o += 1
    if end == 0:
        return None, o
    name = bytes(buf[o:o + nlen]).decode('ascii', 'replace')
    o += nlen
    props = []
    for _ in range(nprops):
        v, o = _read_prop(buf, o)
        props.append(v)
    children = []
    while o < end:
        child, o = _read_node(buf, o, wide)
        if child is None:
            break
        children.append(child)
    return Node(name, props, children), end


def parse(path):
    buf = memoryview(open(path, 'rb').read())
    if bytes(buf[:20]) != b'Kaydara FBX Binary  ':
        raise ValueError('not a binary FBX: %s' % path)
    version = struct.unpack_from('<I', buf, 23)[0]
    wide = version >= 7500
    o = 27
    top = []
    while o < len(buf) - 13:
        node, o = _read_node(buf, o, wide)
        if node is None:
            break
        top.append(node)
    return Node('', [], top)


def _p70(node):
    out = {}
    props = node.find('Properties70') if node is not None else None
    for p in (props.all('P') if props is not None else []):
        out[p.props[0]] = p.props[4:]
    return out


def _euler_xyz(deg):
    x, y, z = np.radians(deg)
    rx = np.array([[1, 0, 0], [0, np.cos(x), -np.sin(x)], [0, np.sin(x), np.cos(x)]])
    ry = np.array([[np.cos(y), 0, np.sin(y)], [0, 1, 0], [-np.sin(y), 0, np.cos(y)]])
    rz = np.array([[np.cos(z), -np.sin(z), 0], [np.sin(z), np.cos(z), 0], [0, 0, 1]])
    return rz @ ry @ rx  # FBX's default eEulerXYZ: X first


def _layer(geo, name, data_key, index_key, poly_index, n_corners):
    """Per-corner values of a LayerElement (normals or UVs)."""
    el = geo.find(name)
    if el is None:
        return None
    data = el.find(data_key)
    if data is None:
        return None
    arr = np.asarray(data.props[0], dtype=np.float64)
    width = 2 if name == 'LayerElementUV' else 3
    arr = arr.reshape(-1, width)
    mapping = el.find('MappingInformationType').props[0]
    ref = el.find('ReferenceInformationType').props[0]
    if ref in ('IndexToDirect', 'Index'):
        idx = np.asarray(el.find(index_key).props[0], dtype=np.int64)
    else:
        idx = None
    if mapping == 'ByPolygonVertex':
        return arr[idx] if idx is not None else arr[:n_corners]
    if mapping in ('ByVertice', 'ByVertex'):
        per_vert = arr[idx] if idx is not None else arr
        return per_vert[poly_index]
    if mapping == 'AllSame':
        return np.repeat(arr[:1], n_corners, axis=0)
    raise ValueError('unsupported mapping %s' % mapping)


def load(path):
    """Triangles of every mesh: (positions (n, 3, 3), normals (n, 3, 3),
    uvs (n, 3, 2)), in metres, +y up, UV v down (image rows)."""
    root = parse(path)
    gs = _p70(root.find('GlobalSettings'))
    unit = float(gs.get('UnitScaleFactor', [1.0])[0]) / 100.0  # FBX units are cm x factor
    up_axis = int(gs.get('UpAxis', [1])[0])
    up_sign = int(gs.get('UpAxisSign', [1])[0])
    front_axis = int(gs.get('FrontAxis', [2])[0])
    front_sign = int(gs.get('FrontAxisSign', [1])[0])
    coord_axis = int(gs.get('CoordAxis', [0])[0])
    coord_sign = int(gs.get('CoordAxisSign', [1])[0])
    # Columns: the file's axes that become our x, y, z.
    axes = np.zeros((3, 3))
    axes[0, coord_axis] = coord_sign
    axes[1, up_axis] = up_sign
    axes[2, front_axis] = front_sign
    objects = root.find('Objects')
    conns = root.find('Connections')
    models = {}
    for m in objects.all('Model'):
        models[m.props[0]] = m
    geo_parent = {}
    for c in (conns.all('C') if conns is not None else []):
        if c.props[0] == 'OO':
            geo_parent.setdefault(c.props[1], c.props[2])
    pos_out, nor_out, uv_out = [], [], []
    for geo in objects.all('Geometry'):
        verts = geo.find('Vertices')
        pvi = geo.find('PolygonVertexIndex')
        if verts is None or pvi is None:
            continue
        v = np.asarray(verts.props[0], dtype=np.float64).reshape(-1, 3)
        raw = np.asarray(pvi.props[0], dtype=np.int64)
        ends = raw < 0
        poly_index = np.where(ends, ~raw, raw)
        n_corners = len(raw)
        nor = _layer(geo, 'LayerElementNormal', 'Normals', 'NormalsIndex', poly_index, n_corners)
        uv = _layer(geo, 'LayerElementUV', 'UV', 'UVIndex', poly_index, n_corners)
        if nor is None:
            nor = np.tile([0.0, 0.0, 1.0], (n_corners, 1))
        if uv is None:
            uv = np.zeros((n_corners, 2))
        # The model's transform.
        m = models.get(geo_parent.get(geo.props[0]))
        p = _p70(m)
        t = np.array(p.get('Lcl Translation', [0, 0, 0])[:3], dtype=np.float64)
        r = _euler_xyz(np.array(p.get('Lcl Rotation', [0, 0, 0])[:3], dtype=np.float64))
        pre = _euler_xyz(np.array(p.get('PreRotation', [0, 0, 0])[:3], dtype=np.float64))
        s = np.array(p.get('Lcl Scaling', [1, 1, 1])[:3], dtype=np.float64)
        rot = pre @ r
        world = (v * s) @ rot.T + t
        nworld = (nor / np.where(s == 0, 1, s)) @ rot.T
        # Fan-triangulate each polygon.
        starts = np.concatenate([[0], np.nonzero(ends)[0][:-1] + 1])
        stops = np.nonzero(ends)[0] + 1
        tri = []
        for a, b in zip(starts, stops):
            for k in range(a + 1, b - 1):
                tri.append((a, k, k + 1))
        if not tri:
            continue
        tri = np.array(tri)
        pos_out.append(world[poly_index[tri]])
        nor_out.append(nworld[tri])
        uv_out.append(uv[tri])
    if not pos_out:
        raise ValueError('no meshes in %s' % path)
    pos = np.concatenate(pos_out) @ axes.T * unit
    nor = np.concatenate(nor_out) @ axes.T
    nor /= np.maximum(np.linalg.norm(nor, axis=-1, keepdims=True), 1e-9)
    uv = np.concatenate(uv_out)
    uv[..., 1] = 1.0 - uv[..., 1]
    # The change of axes may mirror: keep the triangles facing their normals.
    if np.linalg.det(axes) < 0:
        pos = pos[:, ::-1]
        nor = nor[:, ::-1]
        uv = uv[:, ::-1]
    return pos.astype(np.float32), nor.astype(np.float32), uv.astype(np.float32)


if __name__ == '__main__':
    for f in sys.argv[1:]:
        p, n, u = load(f)
        flat = p.reshape(-1, 3)
        print('%s: %d tris, min %s max %s, uv %s..%s' % (f.split('/')[-1], len(p), flat.min(0).round(3),
                                                         flat.max(0).round(3), u.reshape(-1, 2).min(0).round(3),
                                                         u.reshape(-1, 2).max(0).round(3)))
