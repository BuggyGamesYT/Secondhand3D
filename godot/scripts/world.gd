# Secondhand 3D (c) 2026 Buggy Games YT. All rights reserved.
# Loads the baked world (geometry, materials, textures) and builds native nodes from it.
class_name World
extends RefCounted

var M: Dictionary
var bin: PackedByteArray
var tex_cache := {}
var mesh_cache := {}
var mat_cache := {}
var shader_cache := {}
var quad: QuadMesh
var rigid_people := false   # GLES3 on phones: no GPU skinning (it runs through transform feedback)
var split_mm := false       # GLES3 on phones: keep every MultiMesh at <= 256 instances (PowerVR driver bug)
var part_cache := {}
var anim_mats := []   # materials whose shader reads TIME-independent "wind" etc. (none for now)

func _init() -> void:
	M = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	bin = FileAccess.get_file_as_bytes("res://data/world.bin")
	quad = QuadMesh.new()
	quad.size = Vector2(1, 1)

func fa(r: Array) -> PackedByteArray:
	var o := int(r[0]) * 4
	return bin.slice(o, o + int(r[1]) * 4)

func tex(n: String) -> Texture2D:
	if tex_cache.has(n):
		return tex_cache[n]
	var t: Texture2D = load("res://tex/%s.png" % n)
	tex_cache[n] = t
	return t

func mesh(gi: int) -> ArrayMesh:
	if mesh_cache.has(gi):
		return mesh_cache[gi]
	var g: Dictionary = M.geos[gi]
	var a: Dictionary = g.a
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	var pos: PackedVector3Array = fa(a.position).to_vector3_array()
	arr[Mesh.ARRAY_VERTEX] = pos
	if a.has("normal"):
		arr[Mesh.ARRAY_NORMAL] = fa(a.normal).to_vector3_array()
	if a.has("uv"):
		arr[Mesh.ARRAY_TEX_UV] = fa(a.uv).to_vector2_array()
	if a.has("color"):
		arr[Mesh.ARRAY_COLOR] = fa(a.color).to_color_array()
	if a.has("skinIndex"):
		arr[Mesh.ARRAY_BONES] = fa(a.skinIndex).to_int32_array()
		var w := PackedFloat32Array()
		w.resize(pos.size() * 4)
		for i in pos.size():
			w[i * 4] = 1.0
		arr[Mesh.ARRAY_WEIGHTS] = w
	if g.has("idx"):
		arr[Mesh.ARRAY_INDEX] = fa(g.idx).to_int32_array()
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES if g.has("lines") else Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh_cache[gi] = m
	return m

# ---------------------------------------------------------------- shaders
const SHADER_PRE := "// The Compatibility renderer shades colours as stored (sRGB); Mobile/Forward shade in linear and\n// hand Color/source_color inputs over already linear. These macros give the same picture on both.\n#if CURRENT_RENDERER == RENDERER_COMPATIBILITY\n#define TO_LIN(x) dec(x)\n#define FROM_LIN(x) enc(x)\n#define VCOL(x) enc(x)\n#define SKYOUT(x) (x)\n#else\n#define TO_LIN(x) (x)\n#define FROM_LIN(x) (x)\n#define VCOL(x) (x)\n#define SKYOUT(x) enc(x)\n#endif\n"

func lit_shader(o: Dictionary) -> Shader:
	var key := JSON.stringify(o)
	if shader_cache.has(key):
		return shader_cache[key]
	var modes := PackedStringArray()
	modes.append("cull_disabled" if o.get("dbl", false) else "cull_back")
	if o.get("unshaded", false):
		modes.append("unshaded")
	else:
		modes.append("diffuse_lambert")
		modes.append("specular_schlick_ggx")
	if o.get("add", false):
		modes.append("blend_add")
	if o.get("nodepth", false):
		modes.append("depth_draw_never")
	if o.get("nofog", false):
		modes.append("fog_disabled")
	if o.get("pull", false) or o.get("bb", false):
		modes.append("skip_vertex_transform")
	var c := "// Secondhand 3D (c) 2026 Buggy Games YT. All rights reserved.\nshader_type spatial;\nrender_mode " + ", ".join(modes) + ";\n"
	c += "vec3 dec(vec3 x) { return x * (x * (x * 0.305306011 + 0.682171111) + 0.012522878); }\n"
	c += "vec3 enc(vec3 x) { return max(vec3(1.055) * pow(max(x, vec3(0.0)), vec3(0.416666667)) - vec3(0.055), vec3(0.0)); }\n"
	c += SHADER_PRE
	c += "global uniform vec3 hemi_sky;\nglobal uniform vec3 hemi_ground;\n"
	c += "uniform vec4 albedo : source_color = vec4(1.0);\nuniform float opacity = 1.0;\n"
	if o.get("tex", false):
		c += "uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, %s;\n" % ("repeat_disable" if o.get("clamp", false) else "repeat_enable")
	c += "uniform vec3 emis : source_color = vec3(0.0);\nuniform float rough = 1.0;\nuniform float spec = 0.0;\nvarying vec3 vWN;\n"
	# the Compatibility renderer treats ALBEDO/EMISSION as sRGB: keep everything in that space (the TO_LIN/FROM_LIN macros make Mobile shade in linear instead)
	c += "void vertex() {\n"
	var wind := int(o.get("wind", 0))
	if wind == 1:
		c += "\tvec3 ip = MODEL_MATRIX[3].xyz;\n\tVERTEX.x += sin(TIME * 1.3 + ip.x * 0.2 + VERTEX.y) * 0.035 * VERTEX.y;\n"
	elif wind == 2:
		c += "\tvec3 ip = MODEL_MATRIX[3].xyz;\n\tfloat sw = sin(TIME * 1.9 + ip.x * 0.37 + ip.z * 0.23) * 0.5 + sin(TIME * 3.1 + ip.x * 0.9) * 0.2;\n\tVERTEX.x += sw * 0.09 * VERTEX.y * 3.0;\n\tVERTEX.z += sw * 0.05 * VERTEX.y * 3.0;\n"
	c += "\tvWN = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;\n"
	if o.get("bb", false):
		c += "\tvec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));\n"
		c += "\tVERTEX = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz + VERTEX * sc;\n"
	elif o.get("pull", false):
		c += "\tVERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz * 0.996;\n\tNORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);\n"
	c += "}\nvoid fragment() {\n\tvec4 c = albedo;\n"
	if o.get("tex", false):
		c += "\tc *= texture(tex, UV);\n"
	if o.get("vc", false):
		c += "\tc.rgb *= VCOL(COLOR.rgb);\n"
	c += "\tALBEDO = c.rgb;\n"
	if not o.get("unshaded", false):
		c += "\tROUGHNESS = rough;\n\tSPECULAR = spec;\n\tvec3 n = dot(vWN, vWN) > 1e-8 ? normalize(vWN) : vec3(0.0, 1.0, 0.0);\n\tif (!FRONT_FACING) n = -n;\n"
		c += "\tEMISSION = FROM_LIN(TO_LIN(c.rgb) * mix(hemi_ground, hemi_sky, clamp(n.y * 0.5 + 0.5, 0.0, 1.0)) + TO_LIN(emis));\n"
	if o.get("alpha", false):
		c += "\tALPHA = clamp(c.a * opacity, 0.0, 1.0);\n"
	c += "}\n"
	var sh := Shader.new()
	sh.code = c
	shader_cache[key] = sh
	return sh

func _lum(hex: String) -> float:
	var col := Color(hex)
	return col.r * 0.3 + col.g * 0.59 + col.b * 0.11

var _shader_files := {}
func shader_file(n: String) -> Shader:
	if not _shader_files.has(n):
		_shader_files[n] = load("res://shaders/%s.gdshader" % n)
	return _shader_files[n]

func material(mi: int, sprite := false) -> Material:
	var key := str(mi) + ("s" if sprite else "")
	if mat_cache.has(key):
		return mat_cache[key]
	var r: Dictionary = M.mats[mi]
	var m := ShaderMaterial.new()
	var k: String = r.key
	var t: String = r.type
	if r.has("terrain"):
		var T: Dictionary = r.terrain
		m.shader = shader_file("terrain")
		m.set_shader_parameter("tA", tex(T.tA))
		m.set_shader_parameter("tB", tex(T.tB))
		m.set_shader_parameter("tC", tex(T.tC))
		m.set_shader_parameter("tD", tex(T.tD))
		m.set_shader_parameter("tSplat", tex(T.splat))
		m.set_shader_parameter("tNoise", tex("noise"))
		m.set_shader_parameter("uSc", Vector4(T.sc[0], T.sc[1], T.sc[2], T.sc[3]))
		m.set_shader_parameter("uBox", Vector4(T.box[0], T.box[1], T.box[2], T.box[3]))
		m.set_shader_parameter("cA", Color(T.cA))
		m.set_shader_parameter("cB", Color(T.cB))
		m.set_shader_parameter("cC", Color(T.cC))
		m.set_shader_parameter("cD", Color(T.cD))
	elif k == "sh3d-water":
		m.shader = shader_file("water")
		m.set_shader_parameter("albedo", Color(r.color))
		m.set_shader_parameter("opacity", float(r.op))
		m.set_shader_parameter("nmap", tex("waterN"))
		m.set_shader_parameter("rep", Vector2(r.nrep[0], r.nrep[1]))
		m.set_shader_parameter("two_sided", int(r.side) == 2)
		if int(r.side) == 2:
			# lakebed surface is seen from below
			var sh := Shader.new()
			sh.code = shader_file("water").code.replace("cull_back", "cull_disabled")
			m.shader = sh
	else:
		var o := {}
		o["dbl"] = int(r.side) != 0 or sprite
		o["tex"] = r.map != null
		o["vc"] = bool(r.vc)
		o["alpha"] = bool(r.tr) or float(r.op) < 1.0
		if t == "SpriteMaterial" or sprite:
			o["unshaded"] = true
			o["bb"] = true
			o["nofog"] = bool(r.add)
			o["clamp"] = true
			o["alpha"] = true
			o["nodepth"] = true
		if t == "MeshBasicMaterial" or t == "LineBasicMaterial":
			o["unshaded"] = true
		if bool(r.add):
			o["add"] = true
			o["nodepth"] = true
		if not bool(r.dw):
			o["nodepth"] = true
		if bool(r.po):
			o["pull"] = true
		if k == "sh3d-fol":
			o["wind"] = 1
		elif k == "sh3d-grass" or k == "sh3d-flower":
			o["wind"] = 2
		if r.map != null and (r.map == "glow" or r.map == "flame" or r.map == "blob"):
			o["clamp"] = true
		m.shader = lit_shader(o)
		m.set_shader_parameter("albedo", Color(r.color))
		m.set_shader_parameter("opacity", float(r.op))
		if r.map != null:
			m.set_shader_parameter("tex", tex(r.map))
		if r.has("emis"):
			m.set_shader_parameter("emis", Color(r.emis))
		if r.has("shin"):
			m.set_shader_parameter("rough", clampf(pow(2.0 / (float(r.shin) + 2.0), 0.25), 0.2, 1.0))
			var sc := Color(r.spec).srgb_to_linear()
			m.set_shader_parameter("spec", clampf((sc.r * 0.3 + sc.g * 0.59 + sc.b * 0.11) * 0.7, 0.0, 0.6))
		if o.get("alpha", false):
			m.render_priority = 1 if o.get("add", false) else 0
	mat_cache[key] = m
	return m

# simple helpers for runtime-made materials
func unshaded_mat(col: Color, alpha := false, add := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = lit_shader({"unshaded": true, "alpha": alpha or add, "add": add, "nodepth": add})
	m.set_shader_parameter("albedo", col)
	return m

func lit_mat(col: Color, rough := 1.0, spec := 0.0, emis := Color(0, 0, 0)) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = lit_shader({})
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("spec", spec)
	m.set_shader_parameter("emis", emis)
	return m

# ---------------------------------------------------------------- nodes
const UNIQUE_PREFIX := ["lamp_", "lampglow_", "tv", "tfl_", "tgl_", "elderwin_"]

func build(n: Dictionary, tags: Dictionary, extra: Dictionary = {}) -> Node3D:
	var node: Node3D
	var t: String = n.t
	if t == "g":
		node = Node3D.new()
	elif t == "m" or t == "l":
		var mi := MeshInstance3D.new()
		mi.mesh = mesh(int(n.g))
		mi.material_override = material(int(n.m))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if int(n.get("cs", 0)) == 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node = mi
	elif t == "s":
		var si := MeshInstance3D.new()
		si.mesh = quad
		si.material_override = material(int(n.m), true)
		si.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		si.extra_cull_margin = 2.0
		node = si
	elif t == "i":
		var cnt := int(n.cnt)
		var mmi: GeometryInstance3D
		if split_mm and cnt > 256:
			mmi = _split_multimesh(n, cnt)
		else:
			var mmi1 := MultiMeshInstance3D.new()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = int(n.get("ucol", 0)) == 1
			mm.mesh = mesh(int(n.g))
			mm.instance_count = cnt
			mm.buffer = fa(n.buf).to_float32_array()
			mmi1.multimesh = mm
			mmi1.material_override = material(int(n.m))
			mmi1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if int(n.get("cs", 0)) == 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi = mmi1
		node = mmi
		if n.has("near"):
			if not extra.has("near"):
				extra["near"] = []
			extra["near"].append([mmi, float(n.cx), float(n.cz)])
		if n.has("lod"):
			if not extra.has("lod"):
				extra["lod"] = {}
			var lid: String = n.lod
			var idx := lid.substr(1)
			if not extra["lod"].has(idx):
				extra["lod"][idx] = [null, null, float(n.cx), float(n.cz)]
			extra["lod"][idx][0 if lid[0] == "h" else 1] = mmi
	else:
		node = Node3D.new()
	var p: Array = n.p
	var q: Array = n.q
	var s: Array = n.s
	node.transform = Transform3D(Basis(Quaternion(q[0], q[1], q[2], q[3])) * Basis.from_scale(Vector3(s[0], s[1], s[2])), Vector3(p[0], p[1], p[2]))
	if int(n.get("v", 1)) == 0:
		node.visible = false
	if n.has("n"):
		var nm: String = n.n
		node.name = nm
		tags[nm] = node
		if node is GeometryInstance3D:
			for pre in UNIQUE_PREFIX:
				if nm.begins_with(pre):
					node.material_override = node.material_override.duplicate()
					break
	if n.has("c"):
		for ch in n.c:
			node.add_child(build(ch, tags, extra))
	return node

# a big MultiMesh as several <=256-instance ones under one empty parent (callers only toggle .visible)
func _split_multimesh(n: Dictionary, cnt: int) -> GeometryInstance3D:
	var holder := MultiMeshInstance3D.new()   # empty holder (no multimesh) keeps the node type
	var buf := fa(n.buf).to_float32_array()
	var ucol := int(n.get("ucol", 0)) == 1
	var stride := 12 + (4 if ucol else 0)
	var mat := material(int(n.m))
	var cs := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if int(n.get("cs", 0)) == 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var i := 0
	while i < cnt:
		var k := mini(256, cnt - i)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = ucol
		mm.mesh = mesh(int(n.g))
		mm.instance_count = k
		mm.buffer = buf.slice(i * stride, (i + k) * stride)
		var part := MultiMeshInstance3D.new()
		part.multimesh = mm
		part.material_override = mat
		part.cast_shadow = cs
		holder.add_child(part)
		i += k
	holder.cast_shadow = cs
	return holder

# a skinned person mesh (one bone per vertex, weight 1) cut into rigid pieces, one per bone,
# with vertices moved into that bone's rest space: looks identical, needs no GPU skinning
func person_parts(geo: int, bone_rest: Array) -> Array:
	if part_cache.has(geo):
		return part_cache[geo]
	var g: Dictionary = M.geos[geo]
	var a: Dictionary = g.a
	var pos: PackedVector3Array = fa(a.position).to_vector3_array()
	var nor: PackedVector3Array = fa(a.normal).to_vector3_array() if a.has("normal") else PackedVector3Array()
	var uv: PackedVector2Array = fa(a.uv).to_vector2_array() if a.has("uv") else PackedVector2Array()
	var col: PackedColorArray = fa(a.color).to_color_array() if a.has("color") else PackedColorArray()
	var si: PackedInt32Array = fa(a.skinIndex).to_int32_array()
	var idx: PackedInt32Array = fa(g.idx).to_int32_array() if g.has("idx") else PackedInt32Array()
	if idx.is_empty():
		idx.resize(pos.size())
		for i in pos.size():
			idx[i] = i
	var per := {}   # bone -> [remap dict, positions, normals, uvs, colors, indices]
	for t in range(0, idx.size(), 3):
		var b := si[idx[t] * 4]
		if not per.has(b):
			per[b] = [{}, PackedVector3Array(), PackedVector3Array(), PackedVector2Array(), PackedColorArray(), PackedInt32Array()]
		var P: Array = per[b]
		var off: Vector3 = bone_rest[b] if b < bone_rest.size() else Vector3.ZERO
		for j in 3:
			var v := idx[t + j]
			var rm: Dictionary = P[0]
			if not rm.has(v):
				rm[v] = P[1].size()
				P[1].append(pos[v] - off)
				if not nor.is_empty(): P[2].append(nor[v])
				if not uv.is_empty(): P[3].append(uv[v])
				if not col.is_empty(): P[4].append(col[v])
			P[5].append(rm[v])
	var out := []
	for b in per:
		var P: Array = per[b]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = P[1]
		if not nor.is_empty(): arr[Mesh.ARRAY_NORMAL] = P[2]
		if not uv.is_empty(): arr[Mesh.ARRAY_TEX_UV] = P[3]
		if not col.is_empty(): arr[Mesh.ARRAY_COLOR] = P[4]
		arr[Mesh.ARRAY_INDEX] = P[5]
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.append([b, m])
	part_cache[geo] = out
	return out

func prefab(name: String) -> Dictionary:
	var tags := {}
	var root := build(M.prefabs[name], tags)
	tags["_root"] = root
	return tags
