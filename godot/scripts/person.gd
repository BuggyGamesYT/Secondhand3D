# Secondhand 3D (c) 2026 Buggy Games YT. All rights reserved.
# Rounded people on a bone rig: one skinned mesh per person, animated procedurally.
class_name Person
extends Node3D

class PB:
	var idx := 0
	var rotation := Vector3.ZERO
	var position := Vector3.ZERO
	var scale := Vector3.ONE
	var yxz := false

var skel: Skeleton3D
var mi: MeshInstance3D
var eyes: MeshInstance3D
var eyes_lit: Material
var pal := ""
var rec: Dictionary
var bones := {}
var hips: PB
var spine: PB
var chest: PB
var neck: PB
var head: PB
var shL: PB
var elL: PB
var haL: PB
var shR: PB
var elR: PB
var haR: PB
var thL: PB
var knL: PB
var ftL: PB
var thR: PB
var knR: PB
var ftR: PB
var walk := 0.0
var mv := 0.0
var t := 0.0
var flinch := 0.0
var crouch := 0.0
var arm_busy := false
var hunch := 0.0
var is_bell := false
var w: World
static var eye_mats := {}

func setup(world: World, palname: String, sc := 1.0, opacity := -1.0) -> Person:
	w = world
	pal = palname
	rec = w.M.people[palname]
	t = randf() * 6.0
	hunch = float(rec.hunch)
	is_bell = bool(rec.bell)
	skel = Skeleton3D.new()
	add_child(skel)
	for b in rec.bones:
		var i := skel.add_bone(b.n)
		if b.parent != null:
			skel.set_bone_parent(i, skel.find_bone(b.parent))
		var p := Vector3(b.p[0], b.p[1], b.p[2])
		skel.set_bone_rest(i, Transform3D(Basis(), p))
		var pb := PB.new()
		pb.idx = i
		pb.position = p
		bones[b.n] = pb
	skel.reset_bone_poses()
	hips = bones.hips; spine = bones.spine; chest = bones.chest; neck = bones.neck; head = bones.head
	shL = bones.shL; elL = bones.elL; haL = bones.haL; shR = bones.shR; elR = bones.elR; haR = bones.haR
	thL = bones.thL; knL = bones.knL; ftL = bones.ftL; thR = bones.thR; knR = bones.knR; ftR = bones.ftR
	shL.yxz = true
	shR.yxz = true
	mi = MeshInstance3D.new()
	mi.mesh = w.mesh(int(rec.geo))
	var bm: Material = w.material(int(rec.mat))
	if opacity > 0.0:
		var sm := ShaderMaterial.new()
		sm.shader = w.lit_shader({"tex": true, "vc": true, "alpha": true})
		sm.set_shader_parameter("tex", w.tex("atlas"))
		sm.set_shader_parameter("opacity", opacity)
		bm = sm
	mi.material_override = bm
	skel.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = skel.create_skin_from_rest_transforms()
	mi.extra_cull_margin = 1.5
	var ha := attach("head")
	eyes = MeshInstance3D.new()
	eyes.mesh = w.mesh(int(rec.eyesGeo))
	eyes_lit = w.material(int(rec.eyesMat))
	eyes.material_override = eyes_lit
	ha.add_child(eyes)
	if bool(rec.kid):
		head.scale = Vector3.ONE * 1.16
	if is_bell:
		var hb := attach("haR")
		var bell := MeshInstance3D.new()
		bell.mesh = w.mesh(int(rec.bellGeo))
		bell.material_override = bm
		bell.position = Vector3(rec.bellPos[0], rec.bellPos[1], rec.bellPos[2])
		hb.add_child(bell)
		for k in rec.pose:
			var v: Array = rec.pose[k]
			bones[k].rotation = Vector3(v[0], v[1], v[2])
	scale = Vector3.ONE * sc
	apply()
	return self

func attach(bone: String) -> BoneAttachment3D:
	var a := BoneAttachment3D.new()
	skel.add_child(a)
	a.bone_name = bone
	return a

func apply() -> void:
	for k in bones:
		var b: PB = bones[k]
		skel.set_bone_pose_rotation(b.idx, Basis.from_euler(b.rotation, EULER_ORDER_YXZ if b.yxz else EULER_ORDER_XYZ).get_rotation_quaternion())
	skel.set_bone_pose_position(hips.idx, hips.position)
	skel.set_bone_pose_scale(head.idx, head.scale)

func set_eyes(col: Color) -> void:
	var key := col.to_html()
	if not eye_mats.has(key):
		eye_mats[key] = w.unshaded_mat(col)
	eyes.material_override = eye_mats[key]

func anim(dt: float, speed: float) -> void:
	t += dt
	var target := clampf(speed / 4.6, 0.0, 1.0)
	var run := clampf((speed - 5.0) / 2.4, 0.0, 1.0)
	mv = lerpf(mv, target, minf(1.0, dt * 8.0))
	if speed > 0.1:
		walk += dt * (4.4 + speed * 1.05)
	else:
		walk = lerpf(walk, roundf(walk / PI) * PI, minf(1.0, dt * 5.0))
	var m := mv
	var s := sin(walk)
	var c := cos(walk)
	var idle := 1.0 - m
	var br := sin(t * 1.7)
	var amp := (0.52 + run * 0.3) * m
	thL.rotation.x = -s * amp - run * 0.08
	thR.rotation.x = s * amp - run * 0.08
	knL.rotation.x = m * (0.1 + maxf(0.0, c) * (0.8 + run * 0.6)) + idle * 0.03
	knR.rotation.x = m * (0.1 + maxf(0.0, -c) * (0.8 + run * 0.6)) + idle * 0.03
	ftL.rotation.x = -(thL.rotation.x + knL.rotation.x) * 0.75
	ftR.rotation.x = -(thR.rotation.x + knR.rotation.x) * 0.75
	thL.rotation.z = 0.02
	thR.rotation.z = -0.02
	hips.position.y = 0.92 - absf(s) * 0.035 * m - run * 0.05 + br * 0.003 * idle - crouch
	hips.rotation = Vector3(0.0, s * 0.14 * m, c * 0.03 * m)
	spine.rotation = Vector3(0.04 * m + run * 0.2 + hunch, -s * 0.2 * m, 0.0)
	chest.rotation = Vector3(br * 0.018 * idle, 0.0, 0.0)
	neck.rotation = Vector3(-(0.04 * m + run * 0.2) * 0.7 - hunch * 0.6, s * 0.08 * m, 0.0)
	var sw := (0.5 + run * 0.35) * m
	shL.rotation = Vector3(s * sw, 0.0, 0.11 + idle * br * 0.012 + run * 0.12)
	elL.rotation.x = -(0.16 + m * 0.28 + run * 0.75) - maxf(0.0, -s) * 0.3 * m
	haL.rotation.x = 0.0
	if not arm_busy and not is_bell:
		shR.rotation = Vector3(-s * sw, 0.0, -0.11 - idle * br * 0.012 - run * 0.12)
		elR.rotation.x = -(0.16 + m * 0.28 + run * 0.75) - maxf(0.0, s) * 0.3 * m
		haR.rotation.x = 0.0
	if flinch > 0.0:
		var f := sin(minf(1.0, flinch) * PI) * 1.0
		spine.rotation.x -= f * 0.4
		neck.rotation.x -= f * 0.35
		shL.rotation.z += f * 0.7
		if not arm_busy:
			shR.rotation.z -= f * 0.7
		knL.rotation.x += f * 0.3
		knR.rotation.x += f * 0.3
		flinch = maxf(0.0, flinch - dt * 3.2)
