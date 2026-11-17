// Turns a downloaded Sketchfab glb into one game-ready prop: metal/rough
// materials, every part baked into a single mesh (CourseProps.mesh reads
// the first MeshInstance only), simplified to a triangle budget, textures
// cut to a size cap, then turned, scaled and stood on y = 0.
//
//   node process.mjs IN.glb OUT.glb '{"tris":8000,"tex":1024,"fit":{"axis":"x","metres":1.83},"yaw":90,"drop":["name substring"]}'
// More options: "dropMaterials" (parts whose material name has one of these
// substrings), "alphaTex" (size cap for the cut-out png textures),
// "footCentre" (stand it on the middle of its lowest 3 %, not its bounds).
import { NodeIO, Document } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { metalRough, simplify, weld, prune, dedup, textureCompress, flatten, join, transformPrimitive, getBounds } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';
import sharp from 'sharp';
import { mat4 } from 'gl-matrix';

const [inp, out, optsJson] = process.argv.slice(2);
const o = JSON.parse(optsJson || '{}');
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(inp);
const root = doc.getRoot();
await doc.transform(metalRough(), flatten());

// Bake every node's world matrix into its primitives and gather them in one mesh.
const scene = root.getDefaultScene() || root.listScenes()[0];
const merged = doc.createMesh('prop');
for (const node of root.listNodes()) {
	const mesh = node.getMesh();
	if (!mesh) continue;
	if ((o.drop || []).some((d) => (node.getName() + '/' + mesh.getName()).includes(d))) { node.setMesh(null); continue; }
	const m = node.getWorldMatrix();
	for (const prim of mesh.listPrimitives()) {
		// Parts by material name: fine spines and the like that vanish at
		// game distances but cost most of the triangles.
		const matName = prim.getMaterial() ? prim.getMaterial().getName() : '';
		if ((o.dropMaterials || []).some((d) => matName.includes(d))) continue;
		const p = prim.clone();
		// Only the first uv set and no tangents: Godot makes its own.
		for (const sem of p.listSemantics()) if (sem === 'TANGENT' || /^TEXCOORD_[1-9]/.test(sem)) p.setAttribute(sem, null);
		transformPrimitive(p, m);
		merged.addPrimitive(p);
	}
	node.setMesh(null);
}
for (const n of root.listNodes()) n.dispose();
const node = doc.createNode('prop').setMesh(merged);
scene.addChild(node);
await doc.transform(join({ keepNamed: false }), weld());

// Turn about y, then scale so the named axis spans the given metres.
const yaw = (o.yaw || 0) * Math.PI / 180;
const turn = mat4.fromYRotation(mat4.create(), yaw);
if (o.pitch) mat4.multiply(turn, mat4.fromXRotation(mat4.create(), o.pitch * Math.PI / 180), turn);
for (const p of merged.listPrimitives()) transformPrimitive(p, turn);
let b = getBounds(node);
const ax = { x: 0, y: 1, z: 2 }[o.fit.axis];
const s = o.fit.metres / (b.max[ax] - b.min[ax]);
b = getBounds(node);
let cx = (b.min[0] + b.max[0]) / 2, cz = (b.min[2] + b.max[2]) / 2;
if (o.footCentre) {
	// Stood on the middle of its foot (a plant's trunk, not its spread of
	// arms), where the game's obstacles put it.
	let n = 0, sx = 0, sz = 0;
	const cut = b.min[1] + (b.max[1] - b.min[1]) * 0.03;
	for (const p of merged.listPrimitives()) {
		const a = p.getAttribute('POSITION');
		for (let i = 0; i < a.getCount(); i++) {
			const v = a.getElement(i, [0, 0, 0]);
			if (v[1] <= cut) { sx += v[0]; sz += v[2]; n++; }
		}
	}
	if (n > 0) { cx = sx / n; cz = sz / n; }
}
const place = mat4.create();
mat4.scale(place, place, [s, s, s]);
mat4.translate(place, place, [-cx, -b.min[1], -cz]);
for (const p of merged.listPrimitives()) transformPrimitive(p, place);

// Godot ignores KHR_materials_specular and _ior (metalRough sets ior 1000 to
// stand in for spec/gloss); drop both, and the specular textures.
for (const mat of root.listMaterials()) mat.setExtension('KHR_materials_specular', null).setExtension('KHR_materials_ior', null);
// Parts to show as polished steel (club heads the author left white).
for (const mat of root.listMaterials()) {
	if ((o.chrome || []).some((c) => mat.getName().includes(c))) {
		mat.setBaseColorTexture(null).setBaseColorFactor([0.72, 0.73, 0.75, 1]).setMetallicFactor(1).setRoughnessFactor(0.22).setMetallicRoughnessTexture(null);
	}
}
// Triangle budget.
await MeshoptSimplifier.ready;
const tris = () => merged.listPrimitives().reduce((t, p) => t + (p.getIndices() ? p.getIndices().getCount() : p.getAttribute('POSITION').getCount()) / 3, 0);
if (o.tris && tris() > o.tris) await doc.transform(simplify({ simplifier: MeshoptSimplifier, ratio: o.tris / tris(), error: o.error || 0.01 }));
await doc.transform(prune(), dedup(), textureCompress({ encoder: sharp, targetFormat: 'jpeg', resize: [o.tex || 1024, o.tex || 1024], quality: 88 }));
// Any png left (sketchfab's alpha slot) becomes jpeg unless a blended or
// cut-out material reads its alpha.
const needAlpha = new Set();
for (const mat of root.listMaterials()) if (mat.getAlphaMode() !== 'OPAQUE' && mat.getBaseColorTexture()) needAlpha.add(mat.getBaseColorTexture());
for (const tex of root.listTextures()) {
	if (tex.getMimeType() !== 'image/png' || needAlpha.has(tex)) continue;
	tex.setImage(new Uint8Array(await sharp(tex.getImage()).flatten().jpeg({ quality: 88 }).toBuffer())).setMimeType('image/jpeg').setURI('');
}
// Cut-out textures keep their alpha as png, cut to their own cap.
if (o.alphaTex) {
	for (const tex of root.listTextures()) {
		if (tex.getMimeType() !== 'image/png') continue;
		const [w, h] = tex.getSize();
		if (Math.max(w, h) <= o.alphaTex) continue;
		const k = o.alphaTex / Math.max(w, h);
		tex.setImage(new Uint8Array(await sharp(tex.getImage()).resize(Math.round(w * k), Math.round(h * k)).png({ compressionLevel: 9, palette: true }).toBuffer()));
	}
}
for (const ext of root.listExtensionsUsed()) if (['KHR_materials_specular', 'KHR_materials_ior'].includes(ext.extensionName)) ext.dispose();
b = getBounds(node);
console.log(JSON.stringify({ tris: tris(), size: [0, 1, 2].map((i) => +(b.max[i] - b.min[i]).toFixed(3)), materials: root.listMaterials().length }));
await io.write(out, doc);
