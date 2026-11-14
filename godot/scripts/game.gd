# Secondhand 3D (c) 2026 Buggy Games YT. All rights reserved.
# Contact: BuggysFanMail@gmail.com
extends Node

const TAU_ := PI * 2.0
const SAVE_PATH := "user://save.json"
const META_PATH := "user://meta.json"
const BOOT_PATH := "user://boot.cfg"
const GL := "#%&@!?/\\|*$▓░▒"
const CELL := 18.0

var W: World
var ui: UI
var sfx: Sfx
var world_root: Node3D
var cam: Camera3D
var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var lamp_light: OmniLight3D
var lantern: OmniLight3D
var post: ShaderMaterial

var META := {}
var SAVED = null
var S = null
var mode := "title"
var now := 0.0
var shake := 0.0
var a_consumed := false
var area = null
var AREAS := {}
var persons: Array = []
var built := false
var switching := false

# ---------------------------------------------------------------- utils
static func angdiff(a: float, b: float) -> float:
	var d := fmod(b - a, TAU_)
	if d > PI:
		d -= TAU_
	if d < -PI:
		d += TAU_
	return d

static func smooth(a: float, b: float, v: float) -> float:
	var t := clampf((v - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func rnd(a: float, b: float) -> float:
	return randf_range(a, b)

func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func later(s: float, f: Callable) -> void:
	get_tree().create_timer(s).timeout.connect(f)

# ---------------------------------------------------------------- save
func read_json(p: String):
	if not FileAccess.file_exists(p):
		return null
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())

func write_json(p: String, v) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(v))

func new_run(n: String) -> Dictionary:
	return {"v": 1, "name": n, "hp": 6, "maxHearts": 3, "pieces": 0, "keys": 0, "pages": {}, "flags": {}, "deaths": 0, "playMs": 0, "area": "village", "spawn": "start", "taken": {}}

func save() -> void:
	if S == null:
		return
	write_json(SAVE_PATH, S)
	SAVED = S

func save_meta() -> void:
	write_json(META_PATH, META)

func mins_played() -> int:
	return maxi(1, roundi((float(S.playMs) if S != null else 0.0) / 60000.0))

func flag(k: String) -> bool:
	return S != null and bool(S.flags.get(k, false))

func taken(k: String) -> bool:
	return S != null and bool(S.taken.get(k, false))

func C() -> int:
	if S == null:
		return 0
	if S.area != "village" and S.area != "hollow":
		return 3
	if flag("bellRung"):
		return 3
	if int(S.pieces) >= 3:
		return 2
	if int(S.pieces) >= 1:
		return 1
	return 0

func local_time() -> String:
	var d := Time.get_time_dict_from_system()
	var h: int = d.hour
	var ap := "PM" if h >= 12 else "AM"
	h = h % 12
	if h == 0:
		h = 12
	return "%d:%02d %s" % [h, d.minute, ap]

func fmt(s: String) -> String:
	return s.replace("{N}", S.name if S != null else "PLAYER").replace("{T}", local_time()).replace("{M}", str(mins_played())).replace("{P}", str(S.pages.size() if S != null else 0))

func corrupt(s: String, amt: float) -> String:
	if amt <= 0.0:
		return s
	var o := ""
	for ch in s:
		o += GL[randi() % GL.length()] if (ch != " " and randf() < amt) else ch
	return o

func PREV() -> String:
	return META.endName if (META.ended and META.endName != "") else "Wren"

# ---------------------------------------------------------------- setup
func _ready() -> void:
	randomize()
	get_tree().auto_accept_quit = true
	get_tree().quit_on_go_back = false
	var m = read_json(META_PATH)
	META = {"ended": false, "endName": "", "endMins": 0, "endDeaths": 0, "slot1Taps": 0, "muted": false, "sens": 1.0, "inv": false, "gfx": "auto"}
	if m is Dictionary:
		META.merge(m, true)
	SAVED = read_json(SAVE_PATH)
	boot_check()
	sfx = Sfx.new()
	add_child(sfx)
	sfx.set_mute(bool(META.muted))
	setup_scene()
	ui = UI.new()
	ui.game = self
	add_child(ui)
	apply_quality()
	get_viewport().size_changed.connect(on_resize)
	on_resize()
	layout_ui()
	W = World.new()
	if OS.get_cmdline_user_args().size() > 0:
		test_hook.call_deferred(OS.get_cmdline_user_args())

# a run that never reached "ok" counts as a graphics crash and steps quality down next time
var crashes := 0
func boot_check() -> void:
	var cf := ConfigFile.new()
	if cf.load(BOOT_PATH) == OK:
		crashes = int(cf.get_value("boot", "crashes", 0))
		if bool(cf.get_value("boot", "running", false)):
			crashes += 1
	cf.set_value("boot", "crashes", crashes)
	cf.set_value("boot", "running", true)
	cf.save(BOOT_PATH)
	later(20.0, boot_ok)

func boot_ok() -> void:
	var cf := ConfigFile.new()
	cf.set_value("boot", "crashes", crashes if mode != "play" else 0)
	cf.set_value("boot", "running", false)
	cf.save(BOOT_PATH)

func setup_scene() -> void:
	world_root = Node3D.new()
	add_child(world_root)
	cam = Camera3D.new()
	cam.near = 0.1
	cam.far = 260.0
	cam.fov = 60.0
	world_root.add_child(cam)
	cam.current = true
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0, 0, 0)
	env.ambient_light_energy = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.037
	env.tonemap_white = 16.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = 1.0
	env.fog_depth_begin = 0.0
	env.fog_depth_end = 100.0
	env.fog_depth_curve = 1.6
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env.sky = sky
	var we := WorldEnvironment.new()
	we.environment = env
	world_root.add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 36.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.5
	world_root.add_child(sun)
	lamp_light = OmniLight3D.new()
	lamp_light.omni_range = 11.0
	lamp_light.omni_attenuation = 1.6
	lamp_light.light_energy = 0.0
	world_root.add_child(lamp_light)
	lantern = OmniLight3D.new()
	lantern.omni_range = 16.0
	lantern.omni_attenuation = 1.4
	lantern.light_energy = 0.0
	world_root.add_child(lantern)

# ---------------------------------------------------------------- quality (adaptive, like the browser build)
const QL := [[0.55, 0], [0.65, 1024], [0.75, 1024], [0.85, 2048], [1.0, 2048]]
var q_level := 2
var q_max := 4
var q_acc := 0.0
var q_n := 0
var q_cool := 2.0
var q_good := 0

func init_quality() -> void:
	var mobile := OS.has_feature("mobile")
	q_max = 3 if mobile else 4
	q_level = 2 if mobile else 3
	if crashes > 0:
		q_max = maxi(0, q_max - crashes)
		q_level = maxi(0, mini(q_level, q_max) - crashes)
	var gq: String = META.get("gfx", "auto")
	if gq == "low":
		q_max = 1
		q_level = mini(q_level, 1)

var q_inited := false
func apply_quality() -> void:
	if not q_inited:
		q_inited = true
		init_quality()
	var q: Array = QL[q_level]
	get_viewport().scaling_3d_scale = q[0]
	var want: bool = q[1] > 0
	sun.shadow_enabled = want
	if want:
		RenderingServer.directional_shadow_atlas_set_size(q[1], true)
	get_viewport().msaa_3d = Viewport.MSAA_2X if q_level >= 2 else Viewport.MSAA_DISABLED

func quality_tick(raw: float) -> void:
	if mode != "play" or raw > 0.25:
		return
	q_cool -= raw
	q_acc += raw
	q_n += 1
	if q_n < 60:
		return
	var avg := q_acc / q_n * 1000.0
	q_acc = 0.0001
	q_n = 0
	if q_cool > 0.0:
		return
	if avg > 23.0 and q_level > 0:
		q_level -= 1
		q_good = 0
		q_cool = 2.5
		apply_quality()
	elif avg < 17.5 and q_level < q_max:
		q_good += 1
		if q_good >= 6:
			q_level += 1
			q_good = 0
			q_cool = 4.0
			apply_quality()
	else:
		q_good = 0

func on_resize() -> void:
	var sz := DisplayServer.window_get_size()
	cam.fov = 76.0 if sz.x < sz.y else 60.0
	if ui:
		ui.on_resize()

# ---------------------------------------------------------------- input
var keys_tap := {}
var held := {"A": false, "B": false, "start": false, "select": false}
var prev_held := {"A": false, "B": false, "start": false, "select": false}
var pressed := {"A": false, "B": false, "start": false, "select": false}
var released := {"A": false, "B": false}
var inp := {"mx": 0.0, "mz": 0.0, "lookX": 0.0, "lookY": 0.0}
var mlx := 0.0
var mly := 0.0
var mouse_down := false
var last_look_input := -10.0
const KEYMAP := {KEY_J: "A", KEY_Z: "A", KEY_K: "B", KEY_X: "B", KEY_SPACE: "B", KEY_ENTER: "start", KEY_KP_ENTER: "start", KEY_ESCAPE: "start", KEY_P: "start", KEY_TAB: "select", KEY_M: "select"}

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		var k: int = e.physical_keycode
		if KEYMAP.has(k):
			keys_tap[KEYMAP[k]] = true
			get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and e.device != InputEvent.DEVICE_ID_EMULATION:
		if e.button_index == MOUSE_BUTTON_LEFT:
			mouse_down = e.pressed
			if e.pressed and mode == "play" and not ui.touch_mode and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not OS.has_feature("mobile"):
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif e is InputEventMouseMotion and e.device != InputEvent.DEVICE_ID_EMULATION and not ui.touch_mode:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or mouse_down:
			mlx += e.relative.x
			mly += e.relative.y
	elif e is InputEventJoypadButton and e.pressed:
		var b: int = e.button_index
		if b == JOY_BUTTON_A:
			keys_tap["A"] = true
		elif b == JOY_BUTTON_B or b == JOY_BUTTON_X:
			keys_tap["B"] = true
		elif b == JOY_BUTTON_START:
			keys_tap["start"] = true
		elif b == JOY_BUTTON_BACK:
			keys_tap["select"] = true

func kp(k: int) -> bool:
	return Input.is_physical_key_pressed(k)

func poll_input() -> void:
	var mx := 0.0
	var mzv := 0.0
	var typing: bool = ui.typing()
	if not typing:
		if kp(KEY_A) or kp(KEY_LEFT): mx -= 1.0
		if kp(KEY_D) or kp(KEY_RIGHT): mx += 1.0
		if kp(KEY_W) or kp(KEY_UP): mzv -= 1.0
		if kp(KEY_S) or kp(KEY_DOWN): mzv += 1.0
	var h := {"A": false, "B": false, "start": false, "select": false}
	if not typing:
		for k in KEYMAP:
			if kp(k):
				h[KEYMAP[k]] = true
	for k in keys_tap:
		if keys_tap[k]:
			h[k] = true
	keys_tap.clear()
	for k in ui.tbtn:
		if ui.tbtn[k]:
			h[k] = true
	for k in ui.ttap:
		if ui.ttap[k]:
			h[k] = true
	ui.ttap.clear()
	var lx := 0.0
	var ly := 0.0
	if not typing:
		if kp(KEY_Q): lx -= 9.0
		if kp(KEY_E): lx += 9.0
	mx += ui.stick.x
	mzv += ui.stick.y
	for d in Input.get_connected_joypads():
		var dz := func(v: float) -> float: return 0.0 if absf(v) < 0.18 else v
		mx += dz.call(Input.get_joy_axis(d, JOY_AXIS_LEFT_X))
		mzv += dz.call(Input.get_joy_axis(d, JOY_AXIS_LEFT_Y))
		lx += dz.call(Input.get_joy_axis(d, JOY_AXIS_RIGHT_X)) * 14.0
		ly += dz.call(Input.get_joy_axis(d, JOY_AXIS_RIGHT_Y)) * 10.0
		if Input.is_joy_button_pressed(d, JOY_BUTTON_A): h.A = true
		if Input.is_joy_button_pressed(d, JOY_BUTTON_B) or Input.is_joy_button_pressed(d, JOY_BUTTON_X): h.B = true
		if Input.is_joy_button_pressed(d, JOY_BUTTON_START): h.start = true
		if Input.is_joy_button_pressed(d, JOY_BUTTON_BACK): h.select = true
		if Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_UP): mzv -= 1.0
		if Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_DOWN): mzv += 1.0
		if Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_LEFT): mx -= 1.0
		if Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_RIGHT): mx += 1.0
	var l := Vector2(mx, mzv).length()
	if l > 1.0:
		mx /= l
		mzv /= l
	inp.mx = mx
	inp.mz = mzv
	var sens := float(META.sens)
	var tl: Vector2 = ui.take_look()
	inp.lookX = (mlx * 0.0032 + tl.x * 0.009 + lx * 0.004) * sens
	inp.lookY = (mly * 0.0026 + tl.y * 0.006 + ly * 0.004) * sens * (-1.0 if META.inv else 1.0)
	if mlx != 0.0 or mly != 0.0 or tl != Vector2.ZERO or lx != 0.0 or ly != 0.0:
		last_look_input = now
	mlx = 0.0
	mly = 0.0
	for k in h:
		pressed[k] = h[k] and not prev_held[k]
		held[k] = h[k]
	released.A = not h.A and prev_held.A
	released.B = not h.B and prev_held.B
	prev_held = h

# ---------------------------------------------------------------- areas
func villageH(x: float, z: float) -> float:
	var r := Vector2(x, z * 1.15).length()
	var m := smooth(30, 46, r) * (1.0 - smooth(8, 19, z))
	var h := (sin(x * 0.11 + 1.3) * sin(z * 0.093 + 0.4) * 1.0 + sin(x * 0.21 + z * 0.17 + 2.1) * 0.35 + sin(x * 0.05 - z * 0.07) * 0.7 + 0.45) * m
	h *= 1.0 - 0.7 * (1.0 - smooth(4, 11, Vector2(x + 48, z + 48).length()))
	h += smooth(60, 88, absf(x)) * 9.0 + smooth(-60, -88, z) * 9.0
	h = lerpf(h, -2.6, smooth(21, 31, z))
	h += smooth(78, 96, z) * 6.5
	return h

func make_area(id: String) -> Dictionary:
	var d: Dictionary = W.M.areas[id]
	var A := {"id": id, "tags": {}, "cols": [], "circ": [], "inter": [], "npcs": [], "foes": [], "items": [], "spawns": {}, "triggers": [], "torches": [],
		"near": [], "lod": [], "fog": d.fog, "song": d.song if d.song != null else "", "bend": float(d.bend) if d.bend != null else 0.0, "light": d.light,
		"lantern": d.lantern, "floor": d.floor, "bounds": d.bounds, "update": Callable(), "onEnter": Callable(), "map": Callable(), "warm": false}
	for c in d.cols:
		A.cols.append({"x0": float(c[0]), "x1": float(c[1]), "z0": float(c[2]), "z1": float(c[3]), "low": int(c[4]) == 1, "off": int(c[5]) == 1})
	for c in d.circ:
		A.circ.append({"x": float(c[0]), "z": float(c[1]), "r": float(c[2]), "low": int(c[3]) == 1})
	for k in d.spawns:
		var sp: Dictionary = d.spawns[k]
		A.spawns[k] = {"x": float(sp.x), "z": float(sp.z), "yaw": float(sp.yaw)}
	var extra := {}
	A.root = W.build(d.root, A.tags, extra)
	A.root.visible = false
	world_root.add_child(A.root)
	A.near = extra.get("near", [])
	for k in extra.get("lod", {}):
		var L: Array = extra["lod"][k]
		if L[0] and L[1]:
			A.lod.append(L)
			L[1].visible = false
	var i := 0
	for t in d.torches:
		A.torches.append({"x": float(t.x), "z": float(t.z), "y": float(t.y), "col": Color(t.col), "ph": float(t.ph), "fl": A.tags.get("tfl_%d" % i), "gl": A.tags.get("tgl_%d" % i)})
		i += 1
	A.height = func(_x: float, _z: float) -> float: return 0.0
	AREAS[id] = A
	return A

func add_inter(A: Dictionary, x: float, z: float, r: float, label: String, fn: Callable, cond := Callable()) -> Dictionary:
	var it := {"x": x, "z": z, "r": r, "label": label, "fn": fn, "cond": cond, "npc": null}
	A.inter.append(it)
	return it

func sign_at(A: Dictionary, x: float, z: float, text) -> void:
	add_inter(A, x, z, 1.8, "Read", func() -> void: say(text.call() if text is Callable else text))

func make_person(pal: String, sc := 1.0, opacity := -1.0) -> Person:
	var p := Person.new().setup(W, pal, sc, opacity)
	persons.append(p)
	return p

func npc(A: Dictionary, id: String, pal: String, x: float, z: float, ry: float, talk: Callable, sc := 1.0, opacity := -1.0) -> Dictionary:
	var m := make_person(pal, sc, opacity)
	m.position = Vector3(x, A.height.call(x, z), z)
	m.rotation.y = ry
	A.root.add_child(m)
	var n := {"id": id, "mesh": m, "x": x, "z": z, "ry": ry, "baseRy": ry, "talk": talk, "t": randf() * 5.0, "facePlayer": 0.0}
	A.npcs.append(n)
	var it := add_inter(A, x, z, 2.0, "Talk", npc_talk_fn(n, talk))
	it.npc = n
	return n

func npc_talk_fn(n: Dictionary, talk: Callable) -> Callable:
	return func() -> void:
		n.facePlayer = 1.2
		talk.call(n)

func glow_node(col: Color, size: float, op: float) -> MeshInstance3D:
	var m := ShaderMaterial.new()
	m.shader = W.lit_shader({"unshaded": true, "bb": true, "add": true, "alpha": true, "nodepth": true, "nofog": true, "tex": true, "clamp": true, "dbl": true})
	m.set_shader_parameter("tex", W.tex("glow"))
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("opacity", op)
	m.render_priority = 1
	var mi := MeshInstance3D.new()
	mi.mesh = W.quad
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * size
	return mi

func pickup(A: Dictionary, type: String, x: float, z: float, o := {}) -> Dictionary:
	var tags := W.prefab("pickup_" + type)
	var m: Node3D = tags["_root"]
	if type == "container":
		m.scale = Vector3.ONE * 1.6
	m.position = Vector3(x, 0.8, z)
	A.root.add_child(m)
	var it := {"type": type, "x": x, "z": z, "mesh": m, "t": randf() * 6.0, "gone": false, "flag": o.get("flag", ""), "n": o.get("n", 0), "cond": o.get("cond", Callable())}
	A.items.append(it)
	return it

func spawn_pickup(type: String, x: float, z: float, o := {}) -> Dictionary:
	return pickup(area, type, x, z, o)

func chest_at(A: Dictionary, x: float, z: float, give: Callable, fl: String) -> Dictionary:
	var g: Node3D = A.tags["chest_" + fl]
	var c := {"x": x, "z": z, "g": g, "lid": g.get_node("lid"), "flag": fl, "open": false}
	var it := add_inter(A, x, z, 1.9, "Open", chest_fn(c, give))
	c.inter = it
	return c

func chest_fn(c: Dictionary, give: Callable) -> Callable:
	return func() -> void:
		if taken(c.flag):
			say([["", "Empty."]])
			return
		S.taken[c.flag] = 1
		c.open = true
		c.lid.rotation.x = -1.6
		sfx.play("chest")
		give.call()
		save()

func build_world() -> void:
	if built:
		return
	built = true
	build_player()
	statue.mesh = make_person("statue", 1.02)
	build_village()
	build_hollow()
	build_b1()
	build_b6()
	build_b10()
	build_lakebed()

# ---------- MILLBROOK
func build_village() -> void:
	var A := make_area("village")
	A.height = func(x: float, z: float) -> float: return 0.3 if (absf(x) < 1.3 and z > 21.0 and z < 42.2) else villageH(x, z)
	var T: Dictionary = A.tags
	A.water = T.water
	A.bellWhole = T.bellWhole
	A.bellBroken = T.bellBroken
	A.hatch = T.hatch
	A.tv = T.tv
	A.lamps = []
	A.lampGlow = []
	A.elderWin = []
	for i in 6:
		A.lamps.append(T["lamp_%d" % i])
		A.lampGlow.append(T["lampglow_%d" % i])
	for i in 4:
		if T.has("elderwin_%d" % i):
			A.elderWin.append(T["elderwin_%d" % i])
	A.winC = false
	add_inter(A, 0, 39.0, 2.0, "Look", bell_talk)
	add_inter(A, 0, 41.3, 1.6, "Go down", act_hatch, func() -> bool: return flag("bellRung"))
	A.ghost = make_person("wren", 0.95)
	A.ghost.position = Vector3(2.6, -1.9, 41)
	A.ghost.rotation.y = PI
	A.ghost.shR.rotation.x = -2.6
	A.root.add_child(A.ghost)
	add_inter(A, 0, -3, 2.2, "Look", act_plinth)
	sign_at(A, 3.2, 5, func(): return [["", fmt("WELCOME HOME, {N}."), 0.05]] if C() >= 2 else [["", "MILLBROOK. Population: 4."]])
	sign_at(A, -12, -5, [["", "The Elder's house. Knock if you're lost."]])
	sign_at(A, -22, -20, [["", "THE HOLLOW: follow the path northwest."], ["", "Someone scratched underneath: \"W went in. W came out different.\""]])
	sign_at(A, 2.2, 20.4, func(): return [["", "THE DOCK. Mind the edge."], ["", "Below, in smaller letters: \"it waves back.\"", 0.04]] if C() >= 1 else [["", "THE DOCK. Mind the edge."]])
	add_inter(A, -12.2, 9, 1.8, "Knock", act_knock)
	A.page2 = pickup(A, "page", -11.4, 11.2, {"n": 2, "flag": "page2", "cond": func() -> bool: return C() >= 1})
	add_inter(A, -48 + 2.6, -48 + 2.6, 2.4, "Enter", act_enter_hollow)
	npc(A, "elder", "elder", -9.5, -6.5, 0.6, func(_n): talk_elder())
	npc(A, "shop", "shop", 13, -7.6, -0.2, func(_n): talk_shop())
	npc(A, "kid", "kid", 6, 7, -0.8, func(_n): talk_kid(), 0.72)
	npc(A, "fisher", "fisher", -6, 21.6, PI, func(_n): talk_fisher())
	A.onEnter = village_enter
	A.update = village_update
	A.map = "village"

func act_hatch() -> void:
	sfx.play("stairs")
	go_area("b1", "start")

func act_plinth() -> void:
	if C() == 0:
		say([["", "A stone statue of a child holding a little bell."], ["", "The plaque is worn smooth. You can only read a \"W\"."]])
	else:
		say([["", "The plinth is empty."], ["", "There are stone footprints in the grass, heading your way.", 0.05]])

func act_knock() -> void:
	var c := C()
	if c == 0:
		say([["", "Locked. Boards nailed across the door."], ["", "The mailbox says W. The rest of the name is scratched off."]])
	elif c == 1:
		say([["", "Locked."], ["", "You can hear a TV inside. It's playing this game."], ["", "Someone in there is at the lake part.", 0.03]])
	else:
		say([["", "Locked."], ["", "The TV inside says your name."], ["", fmt("\"{N}? Is that you? It's {T}. Come inside.\""), 0.06]])

func act_enter_hollow() -> void:
	if flag("hollowDone"):
		say([["", "The hollow is quiet now. Something still breathes inside."]])
		return
	sfx.play("door")
	go_area("hollow", "entry")

# ---------- THE HOLLOW
func unlock_fn(door: Dictionary) -> Callable:
	return func() -> void:
		if int(S.keys) > 0:
			S.keys = int(S.keys) - 1
			S.taken[door.flag] = 1
			sfx.play("unlock")
			save()
		else:
			sfx.play("lock")
			say([["", "Locked. You need a key."]])

func act_hollow_exit() -> void:
	sfx.play("door")
	go_area("village", "hollowGate")

func give_key() -> void:
	S.keys = int(S.keys) + 1
	sfx.play("key")
	say([["", "You got a SMALL KEY."]])

func act_leave_hollow() -> void:
	S.flags.hollowDone = true
	save()
	sfx.play("warp")
	go_area("village", "hollowGate")

func build_hollow() -> void:
	var A := make_area("hollow")
	var T: Dictionary = A.tags
	A.rooms = {"r0": [0, 0], "r1": [0, -1], "r2": [1, -1], "r3": [1, -2], "r4": [0, -2], "rb": [0, -3]}
	A.doors = []
	var d: Dictionary = W.M.areas.hollow
	var i := 0
	for dd in d.doors:
		var door := {"flag": dd.flag, "type": dd.type, "mesh": T["door_%d" % i], "col": A.cols[int(d.colTags["door_%d" % i])], "x": float(dd.x), "z": float(dd.z), "open": false, "y": 0.0}
		A.doors.append(door)
		if dd.type == "locked":
			add_inter(A, door.x, door.z, 2.2, "Unlock", unlock_fn(door), func() -> bool: return not door.open)
		i += 1
	sign_at(A, 3, 4, [["", "THE HOLLOW."], ["", "Something grew here that should have stayed a seed."]])
	A.triggers.append({"x0": -1.5, "x1": 1.5, "z0": 8.6, "z1": 10.0, "fn": act_hollow_exit})
	A.r1chest = chest_at(A, 0, -18, give_key, "hk1")
	sign_at(A, 16, -11.5, [["", "Push the stone onto the plate."], ["", "If it gets stuck, leave the room and it will reset."]])
	A.block = {"home": [18.0, -18.0], "x": 18.0, "z": -18.0, "mesh": T.block, "col": A.cols[int(d.colTags.block)], "push": 0.0, "moving": 0.0, "from": [0.0, 0.0], "to": [0.0, 0.0]}
	chest_at(A, 22, -40, func() -> void: give_page(3), "page3")
	sign_at(A, -4, -31, [["", "IT IS LISTENING."], ["", "Hit it in the eye when it looks at you."]])
	A.boss = {"g": T.boss, "eyeG": T.eyeG, "lidT": T.lidT, "lidB": T.lidB, "pupil": T.pupil, "state": "sleep", "t": 0.0, "cycle": 0, "spikes": []}
	var bf := {"type": "boss", "x": 0.0, "z": -57.0, "r": 1.9, "hp": 8, "mesh": T.boss, "mats": [], "flash": 0.0, "dead": false}
	collect_mats(bf)
	A.boss.f = bf
	A.portal = T.portal
	add_inter(A, 0, -51, 2.0, "Leave", act_leave_hollow, func() -> bool: return taken("piece1"))
	A.bossFight = false
	A.curRoom = ""
	A.onEnter = hollow_enter
	A.update = hollow_update
	A.map = "hollow"

# ---------- THE UNDERNEATH
func build_b1() -> void:
	var A := make_area("b1")
	A.figs = []
	var xs := [0.62, -1.05, 1.18, -0.37]
	var k := 0
	for z in [-16.0, -30.0, -46.0, -58.0]:
		var f := make_person("shadow")
		f.position = Vector3(xs[k], 0, z)
		A.root.add_child(f)
		f.set_eyes(Color("#e8e8e8"))
		A.figs.append({"mesh": f, "gone": false, "z": z})
		k += 1
	pickup(A, "page", 1.6, -40, {"n": 7, "flag": "page7"})
	add_inter(A, 0, -69, 1.8, "Go down", act_b1_down)
	A.onEnter = func() -> void: place_statue_behind(10.0)
	A.update = b1_update

func act_b1_down() -> void:
	sfx.play("stairs")
	floor_skip()

func talk_woman(_n) -> void:
	say([["WOMAN", "Everything goes. All of it."], ["WOMAN", "We can't keep looking at it every day."], ["WOMAN", "Especially that game. Take it. Please. One dollar."]], woman_after)

func woman_after() -> void:
	if not flag("b6"):
		S.flags.b6 = true
		save()
		sfx.play("secret")
		ui.toast("Somewhere behind you, stairs open.")

func talk_buyer(_n) -> void:
	say([["???", "One dollar? For an old game with no box?"], ["???", "Somebody wrote on the label. SECONDHAND."], ["???", "...okay. Deal."], ["", "The kid holding the cartridge looks a little like you."]])

func act_b6_down() -> void:
	sfx.play("stairs")
	floor_skip2()

func b6_update(_dt: float) -> void:
	area.stairs.visible = flag("b6")
	area.stairsFrame.visible = flag("b6")

func build_b6() -> void:
	var A := make_area("b6")
	add_inter(A, 0.2, -2.4, 1.8, "Look", func() -> void: say([["", "A grey cartridge. No box."], ["", fmt("The label says {N} in marker.")], ["", "It's warm, like somebody was just holding it.", 0.04]]))
	add_inter(A, -8, 0, 1.8, "Read", func() -> void: say([["", "A cardboard box: \"GAMES $1 EACH. EVERYTHING MUST GO.\""]]))
	npc(A, "woman", "woman", 4.5, -4, 0.3, talk_woman)
	npc(A, "buyer", "player", -3, 2.5, PI * 0.9, talk_buyer, 1.0, 0.55)
	A.stairs = A.tags.stairs
	A.stairsFrame = A.tags.stairsFrame
	add_inter(A, 0, 8, 1.8, "Go down", act_b6_down, func() -> bool: return flag("b6"))
	A.update = b6_update

func build_b10() -> void:
	var A := make_area("b10")
	A.height = func(_x: float, _z: float) -> float: return 0.3
	A.wrenNpc = npc(A, "wren", "wren", 0, -11.2, 0, func(_n) -> void: talk_wren())
	var gl := glow_node(Color("#8fb8ff"), 3.2, 0.35)
	gl.position.y = 1.1
	A.wrenNpc.mesh.add_child(gl)
	A.update = b10_update

func build_lakebed() -> void:
	var A := make_area("lakebed")
	A.surface = A.tags.surface
	A.me = make_person("player")
	A.me.position = Vector3(0.5, 0, 2)
	A.root.add_child(A.me)
	A.wren = make_person("wren")
	A.wren.position = Vector3(0, 7.2, 0)
	A.root.add_child(A.wren)

# ---------------------------------------------------------------- story text
const PAGES := {2: ["JUNE 5.", "there's a kid in the village who says my name over and over. it's kind of funny."],
	3: ["JUNE 9.", "the statue moved. i KNOW it moved. i turned around and it was closer."],
	7: ["JULY 2.", "LAKE TRIP SATURDAY!!! i'll finish the game when i get back."]}

func give_page(n: int) -> void:
	S.pages[str(n)] = 1
	sfx.play("page")
	save()
	say([["", "You found a page from a diary. (" + str(S.pages.size()) + " of 3)"], ["WREN", PAGES[n][0] + "  " + PAGES[n][1]]])

func talk_elder() -> void:
	var c := C()
	var Wn := PREV()
	if not flag("metElder"):
		S.flags.metElder = true
		save()
		say([["ELDER", "Ah, a new face. What was your name again?"], ["ELDER", fmt("{N}. Hm. That's not the name I remember.")],
			["ELDER", "Never mind. The old bell at the end of the dock broke into three pieces."],
			["ELDER", "One of them fell into THE HOLLOW. The dead tree up the path to the northwest."],
			["ELDER", "The other two... I don't know. Somebody had them once."],
			["ELDER", "Bring the pieces to the bell. Then everything can go back to how it was."], ["ELDER", "Press SELECT if you get lost. And keep an eye on the statue."]])
		return
	if c == 0:
		say([["ELDER", "The Hollow is northwest. Follow the path past the trees."], ["ELDER", "Swing your sword with B. Hold it, then let go, to spin."]])
	elif c == 1:
		say([["ELDER", "You found one. Good, good."], ["ELDER", "Did the statue move? I could swear it was on its plinth this morning."], ["ELDER", fmt("Don't let it get behind you, {N}.")]])
	elif c == 2:
		say([["ELDER", fmt("Your hands are shaking, {N}.")], ["ELDER", fmt("It's {T} where you are. Shouldn't you be asleep?"), 0.0], ["ELDER", Wn + " used to play this late too."], ["ELDER", "Ring the bell. " + Wn + " wants to be let out."], ["ELDER", "I mean. " + Wn + " wants it fixed."], ["ELDER", "Same thing.", 0.2]])
	else:
		say([["ELDER", "You rang it."], ["ELDER", fmt("Go down, {N}. All the way down. Someone is waiting at the bottom."), 0.1]])

func talk_kid() -> void:
	var c := C()
	var Wn := PREV()
	if c == 0:
		say([["KID", "Wanna know a secret?"], ["KID", "If you stand at the end of the dock, you can see someone under the water."], ["KID", "They wave sometimes."]])
	elif c == 1:
		say([["KID", fmt("{N}! {N}! {N}!")], ["KID", "...sorry. I just like saying it."], ["KID", "Nobody new ever comes here."]])
	else:
		say([["KID", Wn + " used to play with me every day."], ["KID", "Then " + Wn + " stopped coming."], ["KID", fmt("You've been here {M} minutes. Are you going to stop coming too?"), 0.03]])

func talk_shop() -> void:
	var c := C()
	if c == 0:
		say([["SHOPKEEPER", "Shop's closed. Been closed for a while."], ["SHOPKEEPER", fmt("Somebody wrote in my ledger: WREN FOUND {P} OF 3 PAGES.")], ["SHOPKEEPER", "Pages of what, I wonder."]])
	elif c == 1:
		say([["SHOPKEEPER", fmt("We don't get many new players, {N}.")], ["SHOPKEEPER", "Last one never finished."]])
	else:
		say([["SHOPKEEPER", "You bought this at a yard sale, didn't you?"], ["SHOPKEEPER", "One dollar. No box. Name on the label in marker."], ["SHOPKEEPER", "That's how it always gets passed on.", 0.04]])

func talk_fisher() -> void:
	var c := C()
	if c == 0:
		say([["FISHER", "Don't fish off the dock."], ["FISHER", "Something under there takes the bait and gives it back."]])
	elif c == 1:
		say([["FISHER", "It gave my hook back again today."], ["FISHER", "There was a hair tie on it. A kid's."]])
	elif c == 2:
		say([["FISHER", "The water's colder than it should be."], ["FISHER", fmt("It's {T}, {N}. Nobody swims at {T}."), 0.05]])
	else:
		say([["FISHER", "..."], ["FISHER", "It's not waving anymore. It's pointing at you.", 0.08]])

func bell_talk() -> void:
	if flag("bellRung"):
		say([["", "The bell is whole. The water under the dock is moving."]])
		return
	if int(S.pieces) < 3:
		say([["", "An old bell, cracked open."], ["", "Pieces are missing. (" + str(int(S.pieces)) + " of 3)"]])
		return
	say([["", "You fit the three pieces together."], ["", "Ring the bell?"]], ring_bell)

func ring_bell() -> void:
	S.flags.bellRung = true
	save()
	var V: Dictionary = AREAS.village
	V.bellWhole.visible = true
	V.bellBroken.visible = false
	V.hatch.visible = true
	sfx.play("bell", false)
	later(2.4, func() -> void: sfx.play("bell", true))
	shake = 0.6
	glitch_kick(0.9)
	later(2.6, bell_after)

func bell_after() -> void:
	if area == null:
		return
	apply_light()
	set_song()
	ui.toast("Something opened under the dock.")

func talk_wren() -> void:
	if not flag("metWren"):
		ending()

# ---------------------------------------------------------------- dialog
var dlg = null
signal dlg_done

func say(lines: Array, cb := Callable()) -> void:
	dlg = {"lines": lines, "i": -1, "cb": cb, "txt": "", "shown": 0.0, "done": false}
	next_line()

func say_p(lines: Array) -> void:
	say(lines, func() -> void: dlg_done.emit())
	await dlg_done

func next_line() -> void:
	dlg.i += 1
	if dlg.i >= dlg.lines.size():
		var cb: Callable = dlg.cb
		dlg = null
		ui.dialog_hide()
		a_consumed = true
		if cb.is_valid():
			cb.call()
		return
	var L: Array = dlg.lines[dlg.i]
	var who: String = L[0]
	var text: String = L[1]
	var c := C()
	var a: float = float(L[2]) if L.size() > 2 else (0.012 * c if (c >= 2 and who != "" and who != "WREN") else 0.0)
	dlg.txt = corrupt(fmt(text), a)
	dlg.shown = 0.0
	dlg.done = false
	ui.dialog_show(corrupt(who, a * 2.0) if who != "" else "", a > 0.02)
	sfx.play("blip")

func dlg_update(dt: float) -> void:
	if dlg == null:
		return
	if not dlg.done:
		dlg.shown += dt * 48.0
		if dlg.shown >= dlg.txt.length():
			dlg.shown = float(dlg.txt.length())
			dlg.done = true
			ui.dialog_more(true)
		ui.dialog_text(dlg.txt.substr(0, int(dlg.shown)))
	if pressed.A or pressed.B:
		if not dlg.done:
			dlg.shown = float(dlg.txt.length())
		else:
			next_line()

# ---------------------------------------------------------------- player + world state
var P := {"x": 0.0, "z": 0.0, "y": 0.0, "face": 0.0, "speed": 0.0, "inv": 0.0, "kbx": 0.0, "kbz": 0.0, "kbt": 0.0, "swingT": -1.0, "spinT": -1.0, "bT": 0.0,
	"ready": false, "hitSet": [], "wx": 0.0, "wz": 0.0, "stepPh": 0.0}
var pm: Person
var sword: Node3D
var blade: MeshInstance3D
var blade_m: Material
var blade_hot: Material
var back: Node3D
var trail: MeshInstance3D
var ring: MeshInstance3D
var blob: MeshInstance3D
var cam_yaw := 0.0
var cam_pitch := 0.34
var cam_dist := 6.2
var cam_override := Callable()

func build_player() -> void:
	pm = make_person("player")
	var SW: Dictionary = W.M.prefabs.sword
	var ga := pm.attach("haR")
	sword = Node3D.new()
	sword.position = Vector3(0, -0.07, 0.01)
	ga.add_child(sword)
	blade_m = W.material(int(SW.bladeMat))
	blade_hot = W.unshaded_mat(Color(1, 1, 1))
	blade = MeshInstance3D.new()
	blade.mesh = W.mesh(int(SW.blade))
	blade.material_override = blade_m
	sword.add_child(blade)
	var hilt := MeshInstance3D.new()
	hilt.mesh = W.mesh(int(SW.hilt))
	hilt.material_override = W.material(int(SW.hiltMat))
	sword.add_child(hilt)
	var gold := MeshInstance3D.new()
	gold.mesh = W.mesh(int(SW.goldGeo))
	gold.material_override = W.material(int(SW.goldMat))
	gold.position.z = 0.1
	sword.add_child(gold)
	sword.visible = false
	var ca := pm.attach("chest")
	back = Node3D.new()
	back.position = Vector3(0.02, 0.08, -0.15)
	back.rotation = Vector3(0, 0, 0.55)
	ca.add_child(back)
	var sh := MeshInstance3D.new()
	sh.mesh = W.mesh(int(SW.sheathGeo))
	sh.material_override = W.material(int(SW.sheathMat))
	sh.scale = Vector3(1, 1, 0.5)
	sh.position.y = -0.18
	back.add_child(sh)
	var bh := MeshInstance3D.new()
	bh.mesh = hilt.mesh
	bh.material_override = hilt.material_override
	bh.rotation.x = -PI / 2.0
	bh.position.y = 0.3
	back.add_child(bh)
	var bg := MeshInstance3D.new()
	bg.mesh = gold.mesh
	bg.material_override = gold.material_override
	bg.position.y = 0.23
	back.add_child(bg)
	var trm := ShaderMaterial.new()
	trm.shader = W.lit_shader({"unshaded": true, "add": true, "alpha": true, "nodepth": true, "nofog": true, "vc": true, "dbl": true})
	trm.set_shader_parameter("opacity", 0.0)
	trm.render_priority = 2
	trail = MeshInstance3D.new()
	trail.mesh = W.mesh(int(W.M.prefabs.trailGeo))
	trail.material_override = trm
	trail.position.y = 1.2
	trail.visible = false
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pm.add_child(trail)
	ring = MeshInstance3D.new()
	ring.mesh = W.mesh(int(W.M.prefabs.ringGeo))
	ring.material_override = trm.duplicate()
	ring.rotation.x = PI / 2.0
	ring.position.y = 1.15
	ring.visible = false
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pm.add_child(ring)
	var bm := ShaderMaterial.new()
	bm.shader = W.lit_shader({"unshaded": true, "alpha": true, "tex": true, "clamp": true, "nodepth": true, "pull": true})
	bm.set_shader_parameter("tex", W.tex("blob"))
	bm.set_shader_parameter("opacity", 0.55)
	blob = MeshInstance3D.new()
	var pl := PlaneMesh.new()
	pl.size = Vector2(0.95, 0.95)
	blob.mesh = pl
	blob.material_override = bm
	blob.position.y = 0.02
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pm.add_child(blob)

static func ease3(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)

func sword_pose() -> void:
	trail.visible = false
	ring.visible = false
	if P.swingT >= 0.0:
		var t: float = P.swingT / 0.24
		var e := ease3(t)
		pm.spine.rotation.y = lerpf(-0.6, 0.6, e)
		pm.hips.rotation.y = lerpf(-0.2, 0.25, e)
		pm.shR.rotation = Vector3(-1.45 + sin(e * PI) * 0.1, lerpf(-1.25, 0.75, e), -0.15)
		pm.elR.rotation.x = lerpf(-1.0, -0.12, e)
		pm.haR.rotation.x = 0.2
		sword.rotation = Vector3(lerpf(1.2, 1.45, e), 0, 0)
		pm.shL.rotation = Vector3(0.35, 0, 0.35)
		pm.elL.rotation.x = -0.6
		pm.neck.rotation.y = -pm.spine.rotation.y * 0.5
		trail.visible = true
		trail.material_override.set_shader_parameter("opacity", 0.6 * maxf(0.0, 1.0 - t * 0.9) * minf(1.0, t * 6.0))
		var rz: float = PI / 2.0 - (pm.spine.rotation.y + pm.hips.rotation.y + pm.shR.rotation.y) - 0.15
		trail.basis = Basis.from_euler(Vector3(PI / 2.0, 0, rz), EULER_ORDER_XYZ)
	elif P.spinT >= 0.0:
		var t: float = P.spinT / 0.42
		pm.spine.rotation.y = -0.35
		pm.shR.rotation = Vector3(-1.5, -1.3, -0.1)
		pm.elR.rotation.x = -0.08
		pm.haR.rotation.x = 0.1
		sword.rotation = Vector3(1.5, 0, 0)
		pm.shL.rotation = Vector3(-0.5, 0, 0.45)
		pm.elL.rotation.x = -0.9
		pm.spine.rotation.x = 0.18
		pm.crouch = 0.1
		ring.visible = true
		ring.material_override.set_shader_parameter("opacity", 0.35 * sin(minf(1.0, t) * PI))
	elif P.bT > 0.25:
		pm.spine.rotation.y = -0.55
		pm.hips.rotation.y = -0.15
		pm.crouch = 0.06
		pm.shR.rotation = Vector3(-0.55, -0.95, -0.25)
		pm.elR.rotation.x = -1.2
		pm.haR.rotation.x = 0.3
		sword.rotation = Vector3(0.6, 0, 0)
		pm.shL.rotation = Vector3(-0.5, 0, 0.3)
		pm.elL.rotation.x = -0.9
	else:
		pm.crouch = maxf(0.0, pm.crouch - 0.02)

var statue := {"mesh": null, "x": 0.0, "z": -3.0, "active": false, "steps": 0, "grindT": 0.0, "moving": false}

func place_statue_on_plinth() -> void:
	var m: Person = statue.mesh
	reparent_to(m, AREAS.village.root)
	m.position = Vector3(0, 0.72, -3)
	m.rotation.y = 0
	m.set_eyes(Color("#2a2a2a"))
	m.eyes.material_override = m.eyes_lit
	statue.active = false

func reparent_to(n: Node, p: Node) -> void:
	if n.get_parent() == p:
		return
	if n.get_parent():
		n.get_parent().remove_child(n)
	p.add_child(n)

func place_statue_behind(dist := -1.0) -> void:
	var d := dist if dist > 0.0 else maxf(9.0, 22.0 - statue.steps * 1.5)
	var m: Person = statue.mesh
	reparent_to(m, area.root)
	m.set_eyes(Color("#ff2020") if C() >= 3 else Color("#2a2a2a"))
	var bk := cam_yaw
	for i in 24:
		var a := bk + rnd(-0.9, 0.9)
		var r := d + rnd(-2, 2)
		var x: float = P.x + sin(a) * r
		var z: float = P.z + cos(a) * r
		if not free_spot(x, z, 0.6) or not in_bounds(x, z):
			continue
		statue.x = x
		statue.z = z
		statue.active = true
		m.position = Vector3(x, area.height.call(x, z), z)
		return
	statue.x = P.x + sin(bk) * d
	statue.z = P.z + cos(bk) * d
	statue.active = true
	m.position = Vector3(statue.x, 0, statue.z)

func in_bounds(x: float, z: float) -> bool:
	var b = area.bounds
	return b == null or (x > b[0] and x < b[1] and z > b[2] and z < b[3])

func free_spot(x: float, z: float, r: float) -> bool:
	for c in area.cols:
		if not c.off and x > c.x0 - r and x < c.x1 + r and z > c.z0 - r and z < c.z1 + r:
			return false
	for c in area.circ:
		if Vector2(x - c.x, z - c.z).length() < c.r + r:
			return false
	return true

func solve(o: Dictionary, r: float) -> void:
	for c in area.circ:
		var dx: float = o.x - c.x
		var dz: float = o.z - c.z
		var d := sqrt(dx * dx + dz * dz)
		var m: float = c.r + r
		if d < m and d > 1e-6:
			o.x = c.x + dx / d * m
			o.z = c.z + dz / d * m
	for b in area.cols:
		if b.off:
			continue
		var cx := clampf(o.x, b.x0, b.x1)
		var cz := clampf(o.z, b.z0, b.z1)
		var dx: float = o.x - cx
		var dz: float = o.z - cz
		var d2 := dx * dx + dz * dz
		if d2 >= r * r:
			continue
		if d2 > 1e-10:
			var d := sqrt(d2)
			o.x = cx + dx / d * r
			o.z = cz + dz / d * r
		else:
			var l: float = o.x - b.x0
			var rr: float = b.x1 - o.x
			var t: float = o.z - b.z0
			var bb: float = b.z1 - o.z
			var m := minf(minf(l, rr), minf(t, bb))
			if m == l:
				o.x = b.x0 - r
			elif m == rr:
				o.x = b.x1 + r
			elif m == t:
				o.z = b.z0 - r
			else:
				o.z = b.z1 + r

func seg_hit(ax: float, az: float, bx: float, bz: float, pad := 0.15) -> float:
	var best := 1.0
	var dx := bx - ax
	var dz := bz - az
	for b in area.cols:
		if b.off or b.low:
			continue
		var x0: float = b.x0 - pad
		var x1: float = b.x1 + pad
		var z0: float = b.z0 - pad
		var z1: float = b.z1 + pad
		if ax > x0 and ax < x1 and az > z0 and az < z1:
			continue
		var t0 := 0.0
		var t1 := 1.0
		if absf(dx) < 1e-9:
			if ax < x0 or ax > x1:
				continue
		else:
			var a := (x0 - ax) / dx
			var c := (x1 - ax) / dx
			if a > c:
				var tmp := a; a = c; c = tmp
			t0 = maxf(t0, a)
			t1 = minf(t1, c)
		if absf(dz) < 1e-9:
			if az < z0 or az > z1:
				continue
		else:
			var a := (z0 - az) / dz
			var c := (z1 - az) / dz
			if a > c:
				var tmp := a; a = c; c = tmp
			t0 = maxf(t0, a)
			t1 = minf(t1, c)
		if t0 <= t1 and t0 < best:
			best = t0
	var L2 := dx * dx + dz * dz
	if L2 > 1e-9:
		for c in area.circ:
			if c.r < 0.9 or c.low:
				continue
			var r: float = c.r + pad
			var fx: float = ax - c.x
			var fz: float = az - c.z
			var bq := 2.0 * (fx * dx + fz * dz)
			var cq := fx * fx + fz * fz - r * r
			if cq < 0.0:
				continue
			var disc := bq * bq - 4.0 * L2 * cq
			if disc < 0.0:
				continue
			var t := (-bq - sqrt(disc)) / (2.0 * L2)
			if t >= 0.0 and t < best:
				best = t
	return best

# ---------------------------------------------------------------- lighting / music / area switching
const SUN_DIR := Vector3(-0.42, 0.78, 0.46)
const SUN_TOP := Vector3(0.12, 1, 0.18)
const SUN_LOW := Vector3(-0.75, 0.28, 0.6)
const SUN_MOON := Vector3(0.3, 0.7, -0.6)
var base_bg := Color(0, 0, 0)

static func hx(v: int) -> Color:
	return Color.hex((v << 8) | 0xff)

func apply_light() -> void:
	var c := C()
	var L: String = area.light
	var bg := 0x000000
	var f1 := 40.0
	var hI := 1.0
	var hC := 0xcfe3ff
	var hG := 0x4a3a2a
	var sI := 1.4
	var sC := 0xfff1d6
	var lan := 0.0
	var lanC := 0xffc890
	var top := 0x000000
	var sun_amt := 0.0
	var cloud := 0.0
	var sd := SUN_DIR
	if L == "day":
		if c == 0:
			bg = 0xa8cce4; top = 0x3a78c4; f1 = 110; hI = 1.25; hG = 0x5a4a32; sI = 2.3; sC = 0xfff0d8; sun_amt = 1; cloud = 1
		elif c == 1:
			bg = 0x9aa2ac; top = 0x5a6878; f1 = 85; hI = 1.05; sI = 1.2; sC = 0xe8e0d0; hC = 0xb8c4d0; sun_amt = 0.25; cloud = 1.6
		elif c == 2:
			bg = 0x7a3c46; top = 0x24162e; f1 = 62; hI = 0.7; hC = 0xb090c0; hG = 0x302030; sI = 1.1; sC = 0xff7050; lan = 6; sun_amt = 1.2; cloud = 0.6; sd = SUN_LOW
		else:
			bg = 0x080a12; top = 0x010206; f1 = 38; hI = 0.4; hC = 0x5070a0; hG = 0x101018; sI = 0.35; sC = 0x8090ff; lan = 10; lanC = 0x9fb8ff; sun_amt = 0; cloud = 0.25; sd = SUN_MOON
	else:
		bg = int(area.fog[0])
		f1 = float(area.fog[2])
		sd = SUN_TOP
		if L == "dungeon":
			hI = 1.1; hC = 0xd8c0a0; hG = 0x564434; sI = 0.5; sC = 0xd8c8a8; lan = 22
		elif L == "under":
			hI = 0.85; hC = 0x7090d0; hG = 0x182030; sI = 0.2; sC = 0x6080ff; lan = 16; lanC = 0xa8c0ff
		elif L == "mem":
			hI = 0.85; hC = 0xc8c0b0; hG = 0x302820; sI = 0.9; sC = 0xd8c8b0
		elif L == "void":
			hI = 0.7; hC = 0x8090a0; sI = 0.2; lan = 12; lanC = 0xc0d0ff
		elif L == "water":
			hI = 0.9; hC = 0x60c0d0; hG = 0x103020; sI = 0.8; sC = 0x90e0ff
	sd = sd.normalized()
	var bgc := hx(bg)
	base_bg = bgc
	env.fog_light_color = bgc
	env.fog_depth_end = f1 * (1.25 if L == "day" else 1.1)
	env.fog_depth_curve = 1.5
	if L == "day":
		env.background_mode = Environment.BG_SKY
		sky_mat.set_shader_parameter("hor", bgc)
		sky_mat.set_shader_parameter("top", hx(top))
		sky_mat.set_shader_parameter("sunamt", sun_amt)
		sky_mat.set_shader_parameter("cloud", cloud)
		sky_mat.set_shader_parameter("sundir", sd)
		sky_mat.set_shader_parameter("suncol", hx(sC))
		sky_mat.set_shader_parameter("noise", W.tex("noise"))
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = bgc
	var hs := hx(hC).srgb_to_linear()
	var hg := hx(hG).srgb_to_linear()
	var k := hI / PI * LIGHT_K
	RenderingServer.global_shader_parameter_set("hemi_sky", Vector3(hs.r, hs.g, hs.b) * k)
	RenderingServer.global_shader_parameter_set("hemi_ground", Vector3(hg.r, hg.g, hg.b) * k)
	sun.light_color = hx(sC)
	sun.light_energy = sI / PI * LIGHT_K
	sun.basis = Basis.looking_at(-sd, Vector3.UP if absf(sd.y) < 0.99 else Vector3.FORWARD)
	lantern.light_energy = lan / PI * LIGHT_K
	lantern.light_color = hx(lanC)
	post_bg = bgc
	for wk in ["water", "surface"]:
		if area.has(wk):
			area[wk].material_override.set_shader_parameter("fogc", bgc)

const LIGHT_K := 1.0
var post_bg := Color(0, 0, 0)

func bend_for() -> float:
	var c := C()
	if area.id == "village":
		return [0.0, 0.8, 1.8, 2.7][c]
	if area.id == "hollow":
		return c * 0.45
	return area.bend

func set_song(name := "") -> void:
	if area == null:
		return
	var n: String = name if name != "" else area.song
	if area.id == "village" and C() >= 3:
		n = "under"
	if area.id == "hollow" and area.bossFight:
		n = "boss"
	if n != "":
		sfx.set_song(n, bend_for())
	else:
		sfx.stop_music()

func go_area(id: String, spawn, no_fade := false) -> void:
	if switching:
		return
	switching = true
	if not no_fade:
		ui.fade(true)
		await wait(0.42)
	if area != null:
		area.root.visible = false
		for f in area.foes:
			if f.mesh and is_instance_valid(f.mesh) and f.type != "boss":
				f.mesh.queue_free()
		area.foes = []
	area = AREAS[id]
	area.root.visible = true
	reparent_to(pm, area.root)
	var sp
	if spawn is Dictionary:
		sp = spawn
	else:
		sp = area.spawns.get(spawn, area.spawns.get("start", {"x": 0.0, "z": 0.0, "yaw": 0.0}))
	P.x = float(sp.x)
	P.z = float(sp.z)
	P.face = float(sp.get("yaw", 0.0)) + PI
	cam_yaw = float(sp.get("yaw", 0.0))
	cam_pitch = 0.34
	P.kbt = 0.0
	P.swingT = -1.0
	P.spinT = -1.0
	P.inv = 0.0
	statue.active = false
	if statue.mesh and statue.mesh.get_parent():
		statue.mesh.get_parent().remove_child(statue.mesh)
	S.area = id
	S.check = {"area": id, "x": P.x, "z": P.z, "yaw": cam_yaw}
	if id == "village" or id == "hollow" or id == "b1":
		save()
	ui.floor_tag(area.floor)
	apply_light()
	if area.onEnter.is_valid():
		area.onEnter.call()
	set_song()
	cam_snap = true
	switching = false
	if not no_fade:
		ui.fade(false)
	layout_ui()

# ---------------------------------------------------------------- particles
var parts: Array = []
var part_pool: Array = []
var part_mats := {}

func puff(x: float, y: float, z: float, col: String, n := 8, sp := 3.0) -> void:
	if not part_mats.has(col):
		part_mats[col] = W.unshaded_mat(Color(col))
	for i in n:
		var m: MeshInstance3D = part_pool.pop_back() if part_pool.size() > 0 else null
		if m == null:
			m = MeshInstance3D.new()
			m.mesh = W.mesh(int(W.M.prefabs.partGeo))
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.material_override = part_mats[col]
		m.position = Vector3(x, y, z)
		m.scale = Vector3.ONE
		reparent_to(m, area.root)
		parts.append({"m": m, "vx": rnd(-sp, sp), "vy": rnd(1, sp * 1.4), "vz": rnd(-sp, sp), "t": rnd(0.4, 0.8)})

func parts_update(dt: float) -> void:
	var i := parts.size() - 1
	while i >= 0:
		var p: Dictionary = parts[i]
		p.t -= dt
		p.vy -= 9.0 * dt
		var m: MeshInstance3D = p.m
		m.position.x += p.vx * dt
		m.position.y = maxf(0.05, m.position.y + p.vy * dt)
		m.position.z += p.vz * dt
		m.scale = Vector3.ONE * maxf(0.01, p.t * 1.8)
		m.rotation.x += dt * 5.0
		if p.t <= 0.0:
			if m.get_parent():
				m.get_parent().remove_child(m)
			part_pool.append(m)
			parts.remove_at(i)
		i -= 1

# ---------------------------------------------------------------- foes
var white_mat: Material

func collect_mats(f: Dictionary) -> void:
	f.mats = []
	var stack: Array = [f.mesh]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and not (n.material_override is ShaderMaterial and str(n.material_override.shader.code).contains("blend_add")):
			f.mats.append([n, n.material_override])
		for ch in n.get_children():
			stack.append(ch)

func mk_foe(type: String, x: float, z: float, room: String) -> Dictionary:
	var tags := W.prefab("foe_" + type)
	var g: Node3D = tags["_root"]
	var f := {"type": type, "x": x, "z": z, "room": room, "hp": 2 if type == "crawler" else 1, "r": 0.5 if type == "crawler" else 0.4, "mesh": g, "vx": 0.0, "vz": 0.0,
		"t": rnd(0, 2), "stun": 0.0, "cd": rnd(1, 2), "lunge": 0.0, "flash": 0.0, "mats": [], "dead": false, "legs": []}
	if type == "crawler":
		for i in 6:
			f.legs.append([tags["leg_%d" % i], i])
	collect_mats(f)
	g.position = Vector3(x, 0, z)
	area.root.add_child(g)
	area.foes.append(f)
	return f

func foe_flash(f: Dictionary, on: bool) -> void:
	if white_mat == null:
		white_mat = W.unshaded_mat(Color(1, 1, 1))
	for pair in f.mats:
		if is_instance_valid(pair[0]):
			pair[0].material_override = white_mat if on else pair[1]

func kill_foe_mesh(f: Dictionary) -> void:
	if f.mesh and is_instance_valid(f.mesh):
		f.mesh.queue_free()

func hit_foe(f: Dictionary, dmg: int, fx: float, fz: float) -> void:
	if f.type == "boss":
		hit_boss(f, dmg)
		return
	f.hp -= dmg
	f.flash = 0.12
	foe_flash(f, true)
	sfx.play("hit")
	var dx: float = f.x - fx
	var dz: float = f.z - fz
	var d := Vector2(dx, dz).length()
	if d == 0.0:
		d = 1.0
	f.vx = dx / d * 9.0
	f.vz = dz / d * 9.0
	f.stun = 0.35
	f.lunge = 0.0
	if f.hp <= 0:
		f.dead = true
		sfx.play("kill")
		puff(f.x, 0.6, f.z, "#3a2418" if f.type == "crawler" else "#b8ffd8", 10)
		kill_foe_mesh(f)
		if randf() < 0.3 and int(S.hp) < int(S.maxHearts) * 2:
			spawn_pickup("heart", f.x, f.z)

func foes_update(dt: float) -> void:
	for f in area.foes:
		if f.dead:
			continue
		if f.flash > 0.0:
			f.flash -= dt
			if f.flash <= 0.0:
				foe_flash(f, false)
		if f.type == "boss":
			continue
		f.t += dt
		var dx: float = P.x - f.x
		var dz: float = P.z - f.z
		var d := Vector2(dx, dz).length()
		if d == 0.0:
			d = 1.0
		var g: Node3D = f.mesh
		if f.stun > 0.0:
			f.stun -= dt
			f.x += f.vx * dt
			f.z += f.vz * dt
			f.vx *= 0.88
			f.vz *= 0.88
		elif f.type == "crawler":
			f.cd -= dt
			if f.lunge > 0.0:
				f.lunge -= dt
				f.x += f.vx * dt
				f.z += f.vz * dt
			elif d < 12.0:
				var wob := sin(f.t * 3.0) * 0.6
				var ax := dx / d
				var az := dz / d
				f.x += (ax + -az * wob) * 2.4 * dt
				f.z += (az + ax * wob) * 2.4 * dt
				if d < 3.0 and f.cd <= 0.0:
					f.lunge = 0.28
					f.vx = ax * 8.0
					f.vz = az * 8.0
					f.cd = rnd(1.4, 2.2)
					sfx.play("skitter", 1.0)
				if randf() < dt * 2.0:
					sfx.play("skitter", 0.4)
			g.rotation.y = atan2(dx, dz)
			g.position.y = absf(sin(f.t * 12.0)) * 0.05
			for L in f.legs:
				var ph: float = f.t * 16.0 + L[1] * 2.1
				L[0].rotation.y = sin(ph) * 0.35
				L[0].rotation.z = (-1.0 if L[1] < 3 else 1.0) * maxf(0.0, cos(ph)) * 0.25
		else:
			if d < 14.0:
				f.x += dx / d * 1.7 * dt
				f.z += dz / d * 1.7 * dt
			var c0: Node3D = g.get_child(0)
			var c1: Node3D = g.get_child(1)
			c0.position.y = 1.1 + sin(f.t * 3.0) * 0.25
			c1.position.y = c0.position.y
			c0.rotation.y += dt * 3.0
		var o := {"x": f.x, "z": f.z}
		solve(o, f.r)
		f.x = o.x
		f.z = o.z
		g.position.x = f.x
		g.position.z = f.z
		if d < f.r + 0.45 and f.stun <= 0.0:
			hurt(1, f.x, f.z)
	var i: int = area.foes.size() - 1
	while i >= 0:
		if area.foes[i].dead and area.foes[i].type != "boss":
			area.foes.remove_at(i)
		i -= 1

# ---------------------------------------------------------------- the Hollow logic
func hollow_enter() -> void:
	var A: Dictionary = area
	A.curRoom = ""
	A.r1chest.g.visible = taken("r1clear")
	A.r1chest.inter.cond = func() -> bool: return taken("r1clear")
	for d in A.doors:
		d.open = door_should_open(d)
		d.y = -4.0 if d.open else 0.0
		d.mesh.position.y = d.y + (4.2 - 0.8) / 2.0
		d.col.off = d.open
	A.bossFight = false
	reset_boss()
	A.portal.visible = taken("piece1")

func door_should_open(d: Dictionary) -> bool:
	if d.type == "boss":
		return not area.bossFight
	return taken(d.flag)

func room_at(x: float, z: float) -> String:
	var gx := roundi(x / CELL)
	var gy := roundi(z / CELL)
	for id in area.rooms:
		var r: Array = area.rooms[id]
		if r[0] == gx and r[1] == gy:
			return id
	return ""

func hollow_update(dt: float) -> void:
	var A: Dictionary = area
	var room := room_at(P.x, P.z)
	if room != "" and room != A.curRoom:
		A.curRoom = room
		for f in A.foes:
			if f.type != "boss" and f.room != room:
				f.dead = true
				kill_foe_mesh(f)
		var r: Array = A.rooms[room]
		var cx: float = r[0] * CELL
		var cz: float = r[1] * CELL
		S.check = {"area": "hollow", "x": P.x, "z": P.z, "yaw": cam_yaw}
		if not S.has("seen"):
			S.seen = {}
		S.seen[room] = 1
		if room == "r1" and not taken("r1clear"):
			mk_foe("crawler", cx - 4, cz - 3, room)
			mk_foe("crawler", cx + 4, cz - 4, room)
			mk_foe("crawler", cx, cz - 6, room)
		if room == "r2" and not taken("r2solved"):
			reset_block()
		if room == "r3":
			mk_foe("wisp", cx - 4, cz - 4, room)
			mk_foe("wisp", cx + 3, cz - 6, room)
		if room == "r4":
			mk_foe("crawler", cx - 5, cz - 5, room)
			mk_foe("crawler", cx + 5, cz - 5, room)
			if not taken("r4h"):
				S.taken.r4h = 1
				spawn_pickup("heart", cx - 6, cz + 5)
				spawn_pickup("heart", cx + 6, cz + 5)
	if room == "r1" and not taken("r1clear") and A.curRoom == "r1":
		var left := 0
		for f in A.foes:
			if f.room == "r1" and not f.dead:
				left += 1
		if left == 0:
			S.taken.r1clear = 1
			save()
			sfx.play("secret")
			A.r1chest.g.visible = true
			puff(0, 0.8, -18, "#e8c23a", 12)
			ui.toast("A chest appeared.")
	for d in A.doors:
		var want := door_should_open(d)
		if want != d.open:
			d.open = want
			sfx.play("gate")
		var ty := -4.0 if d.open else 0.0
		d.y = lerpf(d.y, ty, minf(1.0, dt * 5.0))
		d.mesh.position.y = d.y + (4.2 - 0.8) / 2.0
		d.col.off = d.open and d.y < -2.0
		if not d.open and d.y > -1.0:
			d.col.off = false
	block_update(dt)
	boss_update(dt)

func reset_block() -> void:
	var b: Dictionary = area.block
	b.x = b.home[0]
	b.z = b.home[1]
	b.moving = 0.0
	sync_block()

func sync_block() -> void:
	var b: Dictionary = area.block
	b.mesh.position = Vector3(b.x, 0.9, b.z)
	b.col.x0 = b.x - 0.98
	b.col.x1 = b.x + 0.98
	b.col.z0 = b.z - 0.98
	b.col.z1 = b.z + 0.98

func block_update(dt: float) -> void:
	var b: Dictionary = area.block
	if taken("r2solved"):
		b.x = 22.0
		b.z = -22.0
		sync_block()
		return
	if b.moving > 0.0:
		b.moving -= dt
		var t: float = 1.0 - maxf(0.0, b.moving) / 0.32
		b.x = lerpf(b.from[0], b.to[0], t)
		b.z = lerpf(b.from[1], b.to[1], t)
		sync_block()
		if b.moving <= 0.0:
			b.x = b.to[0]
			b.z = b.to[1]
			sync_block()
			if is_equal_approx(b.x, 22.0) and is_equal_approx(b.z, -22.0):
				S.taken.r2solved = 1
				save()
				sfx.play("secret")
				ui.toast("Click.")
		return
	var dx: float = P.x - b.x
	var dz: float = P.z - b.z
	var dir = null
	if absf(dz) < 0.75 and dx < -1.2 and dx > -1.7 and P.wx > 0.6:
		dir = [1, 0]
	elif absf(dz) < 0.75 and dx > 1.2 and dx < 1.7 and P.wx < -0.6:
		dir = [-1, 0]
	elif absf(dx) < 0.75 and dz < -1.2 and dz > -1.7 and P.wz > 0.6:
		dir = [0, 1]
	elif absf(dx) < 0.75 and dz > 1.2 and dz < 1.7 and P.wz < -0.6:
		dir = [0, -1]
	if dir != null:
		b.push += dt
		if b.push > 0.3:
			b.push = 0.0
			var nx: float = b.x + dir[0] * 2.0
			var nz: float = b.z + dir[1] * 2.0
			if nx >= 12.0 and nx <= 24.0 and nz >= -24.0 and nz <= -12.0:
				b.from = [b.x, b.z]
				b.to = [nx, nz]
				b.moving = 0.32
				sfx.play("push")
	else:
		b.push = 0.0

func remove_boss_circ() -> void:
	var keep := []
	for c in area.circ:
		if not (c.x == 0.0 and c.z == -57.0):
			keep.append(c)
	area.circ = keep

func reset_boss() -> void:
	var B: Dictionary = area.boss
	if taken("bossDead"):
		B.g.visible = false
		remove_boss_circ()
		area.portal.visible = taken("piece1")
		return
	var has := false
	for c in area.circ:
		if c.x == 0.0 and c.z == -57.0:
			has = true
	if not has:
		area.circ.append({"x": 0.0, "z": -57.0, "r": 1.8, "low": false})
	B.g.visible = true
	B.g.position.y = 0.0
	B.f.hp = 8
	B.f.dead = false
	B.state = "sleep"
	B.t = 0.0
	B.cycle = 0
	set_lids(0.0)
	for s in B.spikes:
		s.m.queue_free()
		s.sp.queue_free()
	B.spikes = []

func set_lids(open: float) -> void:
	var B: Dictionary = area.boss
	B.lidT.position.y = 0.35 + open * 0.5
	B.lidB.position.y = -0.35 - open * 0.5

var spike_mark_mat: ShaderMaterial

func boss_update(dt: float) -> void:
	var B: Dictionary = area.boss
	if taken("bossDead"):
		if B.state == "dying":
			B.t += dt
			B.g.position.y = -B.t * 2.4
			B.g.rotation.z = sin(B.t * 30.0) * 0.03
			if B.t > 2.6:
				B.state = "gone"
				B.g.visible = false
		area.portal.visible = taken("piece1")
		area.portal.rotation.y += dt * 1.5
		return
	if B.state == "sleep":
		if P.z < -47.2:
			area.bossFight = true
			B.state = "closed"
			B.t = 2.2
			if not area.foes.has(B.f):
				area.foes.append(B.f)
			B.f.dead = false
			sfx.play("roar")
			shake = 0.5
			ui.toast("THE ROOTED ONE")
			set_song()
		return
	var fast: bool = B.f.hp <= 4
	var g: Node3D = B.g
	g.rotation.y = lerpf(g.rotation.y, g.rotation.y + angdiff(g.rotation.y, atan2(P.x - 0.0, P.z + 57.0)), minf(1.0, dt * 1.5))
	B.t -= dt
	if B.state == "closed":
		set_lids(0.0)
		if B.t <= 0.0:
			B.state = "roots"
			B.t = 1.0
			B.cycle += 1
			var pts := [[P.x, P.z]]
			for i in (4 if fast else 2):
				pts.append([clampf(P.x + rnd(-4, 4), -7.5, 7.5), clampf(P.z + rnd(-4, 4), -62, -46.5)])
			if spike_mark_mat == null:
				spike_mark_mat = ShaderMaterial.new()
				spike_mark_mat.shader = W.lit_shader({"unshaded": true, "alpha": true, "tex": true, "clamp": true, "nodepth": true, "pull": true})
				spike_mark_mat.set_shader_parameter("tex", W.tex("blob"))
				spike_mark_mat.set_shader_parameter("opacity", 0.9)
			for pp in pts:
				var mk := MeshInstance3D.new()
				var pl := PlaneMesh.new()
				pl.size = Vector2(1.8, 1.8)
				mk.mesh = pl
				mk.material_override = spike_mark_mat.duplicate()
				mk.position = Vector3(pp[0], 0.03, pp[1])
				mk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				area.root.add_child(mk)
				var sp := MeshInstance3D.new()
				sp.mesh = W.mesh(int(W.M.prefabs.spikeGeo))
				sp.material_override = W.material(int(W.M.prefabs.spikeMat))
				sp.position = Vector3(pp[0], -1.3, pp[1])
				sp.rotation.y = randf() * 6.0
				area.root.add_child(sp)
				B.spikes.append({"m": mk, "sp": sp, "x": pp[0], "z": pp[1], "t": 0.0, "hit": false, "op": 0.9})
			sfx.play("grind")
			var crawlers := 0
			for f in area.foes:
				if f.type == "crawler":
					crawlers += 1
			if B.cycle % 2 == 0 and crawlers < 3:
				mk_foe("crawler", -5, -50, "rb")
				mk_foe("crawler", 5, -50, "rb")
	elif B.state == "roots":
		if B.t <= 0.0:
			B.state = "open"
			B.t = 2.0 if fast else 2.6
			sfx.play("roar")
	elif B.state == "open":
		set_lids(1.0)
		B.pupil.position.x = clampf(P.x * 0.03, -0.15, 0.15)
		if B.t <= 0.0:
			B.state = "closed"
			B.t = 2.0 if fast else 2.8
	var i: int = B.spikes.size() - 1
	while i >= 0:
		var s: Dictionary = B.spikes[i]
		s.t += dt
		var sp: Node3D = s.sp
		if s.t > 1.0:
			sp.position.y = minf(0.0, -1.3 + (s.t - 1.0) * 14.0)
			if not s.hit and s.t > 1.05 and Vector2(P.x - s.x, P.z - s.z).length() < 1.0:
				s.hit = true
				hurt(2, s.x, s.z)
			if s.t < 1.1:
				sfx.play("clank")
		if s.t > 1.8:
			sp.position.y -= dt * 8.0
			s.op *= 0.9
			s.m.material_override.set_shader_parameter("opacity", s.op)
		if s.t > 2.3:
			s.m.queue_free()
			sp.queue_free()
			B.spikes.remove_at(i)
		i -= 1

func hit_boss(f: Dictionary, dmg: int) -> void:
	var B: Dictionary = area.boss
	if B.state != "open":
		sfx.play("clank")
		puff(P.x + sin(P.face) * 1.5, 1.2, P.z + cos(P.face) * 1.5, "#ffffff", 4, 2)
		return
	f.hp -= dmg
	f.flash = 0.15
	foe_flash(f, true)
	sfx.play("bossHit")
	shake = 0.25
	glitch_kick(0.25)
	P.kbx = -sin(P.face) * 7.0
	P.kbz = -cos(P.face) * 7.0
	P.kbt = 0.18
	B.state = "closed"
	B.t = 1.6
	if f.hp <= 0:
		f.dead = true
		B.state = "dying"
		B.t = 0.0
		S.taken.bossDead = 1
		area.bossFight = false
		sfx.play("roar")
		shake = 1.2
		glitch_kick(1.0)
		for s in B.spikes:
			s.m.queue_free()
			s.sp.queue_free()
		B.spikes = []
		for o in area.foes:
			if o.type == "crawler":
				o.dead = true
				kill_foe_mesh(o)
				puff(o.x, 0.5, o.z, "#3a2418")
		remove_boss_circ()
		spawn_pickup("container", -1.6, -53, {"flag": "hc1"})
		spawn_pickup("piece", 1.6, -53, {"flag": "piece1"})
		save()
		set_song()

# ---------------------------------------------------------------- statue
func statue_seen() -> bool:
	if blink_t > 0.0:
		return false
	var in_view := false
	var vp := get_viewport().get_visible_rect().size
	for y in [0.4, 1.0, 1.6]:
		var p := Vector3(statue.x, y + area.height.call(statue.x, statue.z), statue.z)
		if cam.is_position_behind(p):
			continue
		var s := cam.unproject_position(p)
		if s.x > -vp.x * 0.01 and s.x < vp.x * 1.01 and s.y > -vp.y * 0.01 and s.y < vp.y * 1.01:
			in_view = true
			break
	if not in_view:
		return false
	return seg_hit(cam.global_position.x, cam.global_position.z, statue.x, statue.z, 0.0) >= 0.999

func statue_update(dt: float) -> void:
	if not statue.active or dlg != null or mode != "play":
		statue.moving = false
		return
	var seen := statue_seen()
	var dx: float = P.x - statue.x
	var dz: float = P.z - statue.z
	var d := Vector2(dx, dz).length()
	if d == 0.0:
		d = 1.0
	if not seen:
		var c := C()
		var sp := (3.3 if c == 1 else (4.1 if c == 2 else 4.6)) if area.id == "village" else 4.4
		var o := {"x": statue.x + dx / d * sp * dt, "z": statue.z + dz / d * sp * dt}
		solve(o, 0.4)
		statue.x = o.x
		statue.z = o.z
		statue.mesh.rotation.y = atan2(dx, dz)
		statue.moving = true
		statue.grindT -= dt
		if statue.grindT <= 0.0 and d < 26.0:
			statue.grindT = 0.4
			sfx.play("grind")
	else:
		statue.moving = false
	statue.mesh.position = Vector3(statue.x, area.height.call(statue.x, statue.z), statue.z)
	if d < 0.95:
		hurt(2, statue.x, statue.z, true)
		sfx.play("sting")
		glitch_kick(0.8)
		statue.steps += 1
		statue.active = false
		later(1.2, statue_respawn)

func statue_respawn() -> void:
	if area != null and (area.id == "village" or area.id == "b1") and mode != "files" and mode != "title" and mode != "end":
		place_statue_behind()

# ---------------------------------------------------------------- player
func hurt(n: int, fx: float, fz: float, big := false) -> void:
	if P.inv > 0.0 or mode != "play" or god:
		return
	S.hp = int(S.hp) - n
	P.inv = 1.0
	sfx.play("hurt")
	pm.flinch = 1.0
	shake = maxf(shake, 0.6 if big else 0.3)
	var dx: float = P.x - fx
	var dz: float = P.z - fz
	var d := Vector2(dx, dz).length()
	if d == 0.0:
		d = 1.0
	P.kbx = dx / d * (11.0 if big else 8.0)
	P.kbz = dz / d * (11.0 if big else 8.0)
	P.kbt = 0.22
	P.swingT = -1.0
	P.spinT = -1.0
	P.bT = 0.0
	P.ready = false
	if int(S.hp) <= 0:
		die()
	elif int(S.hp) <= 2:
		sfx.play("lowhp")

var god := false

func die() -> void:
	mode = "dead"
	S.deaths = int(S.deaths) + 1
	S.hp = 0
	ui.toast(corrupt(PREV().to_upper() + " DIDN'T GET TO CONTINUE", 0.06) if C() >= 2 else "GAME OVER", 3.0)
	sfx.play("static", 0.6)
	await wait(2.6)
	S.hp = int(S.maxHearts) * 2
	var ch = S.get("check", {"area": S.area})
	if area.id == "hollow":
		area.bossFight = false
		reset_boss()
	mode = "play"
	if ch.has("x"):
		await go_area(ch.area, {"x": float(ch.x), "z": float(ch.z), "yaw": float(ch.yaw)})
	else:
		await go_area(ch.area, "start")
	save()

func player_update(dt: float) -> void:
	var fx := -sin(cam_yaw)
	var fz := -cos(cam_yaw)
	var rx := cos(cam_yaw)
	var rz := -sin(cam_yaw)
	var wx: float = rx * inp.mx + fx * -inp.mz
	var wz: float = rz * inp.mx + fz * -inp.mz
	var wl := Vector2(wx, wz).length()
	var mag := minf(1.0, wl)
	P.wx = wx / wl * mag if mag > 0.05 else 0.0
	P.wz = wz / wl * mag if mag > 0.05 else 0.0
	if not held.A:
		a_consumed = false
	var running: bool = held.A and not a_consumed and mag > 0.3
	var sp := (7.4 if running else 4.6) * mag
	if P.swingT >= 0.0: sp *= 0.35
	if P.spinT >= 0.0: sp *= 0.6
	if P.bT > 0.25: sp *= 0.55
	if P.kbt > 0.0:
		P.kbt -= dt
		P.x += P.kbx * dt
		P.z += P.kbz * dt
	elif mag > 0.05:
		P.x += P.wx / mag * sp * dt
		P.z += P.wz / mag * sp * dt
		if P.bT < 0.25 and P.spinT < 0.0:
			P.face += angdiff(P.face, atan2(P.wx, P.wz)) * minf(1.0, dt * 14.0)
	var o := {"x": P.x, "z": P.z}
	solve(o, 0.4)
	P.x = o.x
	P.z = o.z
	P.speed = 0.0 if P.kbt > 0.0 else sp
	P.y = lerpf(P.y, area.height.call(P.x, P.z), minf(1.0, dt * 14.0))
	if sp > 0.5:
		P.stepPh += dt * sp * 0.55
		if P.stepPh > 1.0:
			P.stepPh -= 1.0
			var surf := "stone"
			if area.light == "day":
				surf = "wood" if P.y > 0.1 else ("dirt" if (absf(P.x) < 7.0 and P.z > -10.0 and P.z < 21.0) else "grass")
			elif area.id == "b10" or area.id == "lakebed":
				surf = "wood"
			elif area.id == "b6":
				surf = "grass"
			sfx.play("step", surf, 1.0 if running else 0.7)
	if pressed.B and P.swingT < 0.0 and P.spinT < 0.0:
		P.swingT = 0.0
		P.hitSet = []
		sfx.play("swing")
		P.bT = 0.001
	if held.B and P.bT > 0.0:
		P.bT += dt
		if P.bT > 0.3 and P.bT - dt <= 0.3:
			sfx.play("charge")
		if P.bT > 0.75 and not P.ready:
			P.ready = true
			sfx.play("chargeReady")
			puff(P.x, 1.0, P.z, "#ffffff", 5, 1.5)
	if released.B:
		if P.ready:
			P.spinT = 0.0
			P.hitSet = []
			sfx.play("spin")
		P.bT = 0.0
		P.ready = false
	if P.swingT >= 0.0:
		P.swingT += dt
		sword.visible = true
		back.visible = false
		pm.arm_busy = true
		if P.swingT > 0.03 and P.swingT < 0.22:
			sword_hits(2.1, 1.15, 1)
		if P.swingT > 0.26:
			P.swingT = -1.0
	if P.spinT >= 0.0:
		P.spinT += dt
		var t: float = P.spinT / 0.42
		sword.visible = true
		back.visible = false
		pm.arm_busy = true
		P.face += dt * TAU_ / 0.42
		sword_hits(2.7, 9.0, 2)
		if randf() < 0.5:
			puff(P.x + sin(P.face + 1.3) * 1.8, 1.0, P.z + cos(P.face + 1.3) * 1.8, "#dfe6ee", 1, 0.5)
		if t >= 1.0:
			P.spinT = -1.0
	if P.swingT < 0.0 and P.spinT < 0.0:
		if P.bT > 0.25:
			sword.visible = true
			back.visible = false
			pm.arm_busy = true
			blade.material_override = blade_hot if (P.ready and sin(now * 30.0) > 0.0) else blade_m
		else:
			sword.visible = false
			back.visible = true
			pm.arm_busy = false
	if P.inv > 0.0:
		P.inv -= dt
		pm.visible = sin(now * 40.0) > -0.3 or P.inv <= 0.0
	else:
		pm.visible = true
	if P.bT <= 0.25 and blade.material_override != blade_m:
		blade.material_override = blade_m
	pm.position = Vector3(P.x, P.y, P.z)
	pm.rotation.y = P.face
	pm.anim(dt, P.speed)
	sword_pose()

func sword_hits(rng: float, arc: float, dmg: int) -> void:
	for f in area.foes:
		if f.dead or P.hitSet.has(f):
			continue
		var dx: float = f.x - P.x
		var dz: float = f.z - P.z
		var d := Vector2(dx, dz).length()
		if d > rng + f.r:
			continue
		if arc < 4.0 and absf(angdiff(P.face, atan2(dx, dz))) > arc:
			continue
		P.hitSet.append(f)
		hit_foe(f, dmg, P.x, P.z)
	if statue.active and not P.hitSet.has(statue) and Vector2(statue.x - P.x, statue.z - P.z).length() < rng + 0.3:
		P.hitSet.append(statue)
		sfx.play("clank")
		puff(statue.x, 1.2, statue.z, "#ffffff", 5, 2)

func items_update(dt: float) -> void:
	for it in area.items:
		if it.gone:
			continue
		var show: bool = (it.flag == "" or not taken(it.flag)) and (not it.cond.is_valid() or it.cond.call())
		it.mesh.visible = show
		if not show:
			continue
		it.t += dt
		it.mesh.rotation.y += dt * 2.0
		it.mesh.position.y = 0.8 + sin(it.t * 3.0) * 0.12 + area.height.call(it.x, it.z)
		if Vector2(P.x - it.x, P.z - it.z).length() < 1.0:
			it.gone = true
			it.mesh.queue_free()
			if it.flag != "":
				S.taken[it.flag] = 1
			if it.type == "heart":
				S.hp = mini(int(S.maxHearts) * 2, int(S.hp) + 2)
				sfx.play("heart")
			elif it.type == "page":
				give_page(int(it.n))
			elif it.type == "container":
				S.maxHearts = int(S.maxHearts) + 1
				S.hp = int(S.maxHearts) * 2
				sfx.play("heart")
				say([["", "You got a HEART CONTAINER! Your life went up."]])
			elif it.type == "piece":
				S.pieces = maxi(int(S.pieces), 1)
				sfx.play("shard")
				glitch_kick(0.5)
				save()
				say([["", "You got a BELL PIECE! 1 of 3."], ["", "SAVING..."], ["", "SAVE 1: WREN", 0], ["", fmt("SAVE 2: {N}. Done.")]], piece_after)
			save()
	var keep := []
	for it in area.items:
		if not it.gone:
			keep.append(it)
	area.items = keep

func piece_after() -> void:
	sfx.play("static", 0.3)
	glitch_kick(0.6)

var inter_target = null

func inter_update() -> void:
	var best = null
	var bd := 1e9
	for it in area.inter:
		if it.cond.is_valid() and not it.cond.call():
			continue
		var dx: float = it.x - P.x
		var dz: float = it.z - P.z
		var d := Vector2(dx, dz).length()
		if d > it.r:
			continue
		var ang := absf(angdiff(P.face, atan2(dx, dz)))
		var score := d + (1.5 if ang > 1.6 else 0.0)
		if score < bd:
			bd = score
			best = it
	inter_target = best
	if best != null and dlg == null:
		ui.prompt("A  " + best.label)
	else:
		ui.prompt("")
	if best != null and pressed.A and dlg == null:
		a_consumed = true
		if best.npc != null:
			best.npc.facePlayer = 1.0
		best.fn.call()

func triggers_update() -> void:
	for t in area.triggers:
		if P.x > t.x0 and P.x < t.x1 and P.z > t.z0 and P.z < t.z1:
			t.fn.call()
			break

# ---------------------------------------------------------------- village / underneath logic
var last_c := -1
var whisper_t := 30.0

func village_enter() -> void:
	var A: Dictionary = area
	var c := C()
	A.bellWhole.visible = flag("bellRung")
	A.bellBroken.visible = not flag("bellRung")
	A.hatch.visible = flag("bellRung")
	if c == 0:
		place_statue_on_plinth()
	else:
		place_statue_behind(20.0 if (c == 1 and not flag("statueSeen")) else -1.0)
	S.flags.statueSeen = c >= 1 or flag("statueSeen")
	last_c = c

var copying := false
func copy_event() -> void:
	if copying:
		return
	copying = true
	S.flags.copied = true
	statue.active = false
	sfx.play("static", 0.5)
	glitch_kick(0.7)
	await say_p([["", "SAVING..."], ["", "SAVE 1: WREN. BELL PIECES: 2.", 0.04], ["", "COPYING SAVE 1 INTO SAVE 2...", 0.08], ["", "Done."]])
	S.pieces = 3
	save()
	sfx.play("shard")
	glitch_kick(1.0)
	shake = 0.5
	await say_p([["", "You got 2 BELL PIECES. 3 of 3."], ["", "You didn't find these.", 0.15]])
	apply_light()
	set_song()
	last_c = C()
	place_statue_behind(16.0)
	copying = false

func village_update(dt: float) -> void:
	var A: Dictionary = area
	var c := C()
	if c != last_c:
		last_c = c
		apply_light()
		set_song()
		if c >= 3:
			statue.mesh.set_eyes(Color("#ff2020"))
	A.water.material_override.set_shader_parameter("albedo", hx(0x101828 if c >= 3 else (0x3a2a40 if c == 2 else 0x2d5f86)))
	A.water.material_override.set_shader_parameter("fogc", base_bg)
	var gh: Person = A.ghost
	gh.visible = c >= 1 or Vector2(P.x, P.z - 40.0).length() < 4.0
	gh.position.y = -1.9 + sin(now * 0.7) * 0.1
	gh.shR.rotation.z = 0.0 if c >= 3 else sin(now * 2.2) * 0.5
	gh.shR.rotation.x = -1.5 if c >= 3 else -2.6
	gh.rotation.y = atan2(P.x - 2.6, P.z - 41.0) if c >= 3 else PI
	A.tv.material_override.set_shader_parameter("albedo", hx(0x8aa8ff if randf() < 0.3 else 0x4a6aff) if c >= 1 else hx(0x14141a))
	if c >= 1 and Vector2(P.x + 13.0, P.z - 9.0).length() < 7.0 and randf() < dt * 0.3:
		sfx.play("tv")
	for i in A.lamps.size():
		var off := c >= 3 and randf() < 0.05
		A.lamps[i].material_override.set_shader_parameter("albedo", hx((0x000000 if off else 0xffd27a) if c >= 2 else 0x8a8a78))
		A.lampGlow[i].material_override.set_shader_parameter("opacity", 0.75 if (c >= 2 and not off) else 0.0)
	if A.winC != (c >= 3):
		A.winC = c >= 3
		for w in A.elderWin:
			w.material_override.set_shader_parameter("albedo", Color("#08080a") if c >= 3 else Color("#ffd47a"))
	if int(S.pieces) == 1 and not flag("copied") and Vector2(P.x, P.z).length() < 15.0 and mode == "play" and dlg == null:
		copy_event()
	for n in A.npcs:
		n.mesh.visible = c < 3 or n.id == "elder" or n.id == "fisher"
	if c >= 2:
		whisper_t -= dt
		if whisper_t <= 0.0:
			whisper_t = rnd(35, 70)
			ui.toast(fmt(["{N}?", "It's {T}.", "{M} minutes.", "Behind you."][randi() % 4]), 1.4)
			sfx.play("static", 0.12)
	sfx.ambient(clampf((P.z - 2.0) / 22.0, 0.0, 1.0) * (0.6 if c >= 3 else 1.0), 0.35 + c * 0.15, 0.4 if c >= 3 else 0.0)

func b1_update(_dt: float) -> void:
	var lines := ["{N}?", "It's {T}. Somebody upstairs should be asleep.", "You have played for {M} minutes. We counted.", "Don't look at the statue, {N}. Look at me."]
	var i := 0
	for f in area.figs:
		var m: Person = f.mesh
		if not f.gone:
			m.rotation.y = atan2(P.x - m.position.x, P.z - m.position.z)
			if Vector2(P.x - m.position.x, P.z - f.z).length() < 5.0:
				f.gone = true
				m.visible = false
				sfx.play("static", 0.3)
				glitch_kick(0.5)
				puff(m.position.x, 1, f.z, "#09090c", 12)
				ui.toast(fmt(lines[i]), 2.4)
		i += 1
	sfx.ambient(0.0, 0.0, 0.7, 0.6)

func b10_update(_dt: float) -> void:
	var w: Dictionary = area.wrenNpc
	w.mesh.position.y = 0.3 + sin(now) * 0.03
	sfx.ambient(0.3, 0.0, 0.5)

func floor_skip() -> void:
	mode = "cut"
	for f in ["B2", "B3", "B4", "B5"]:
		ui.floor_tag(f)
		sfx.play("static", 0.15)
		glitch_kick(0.5)
		await wait(0.38)
	mode = "play"
	await go_area("b6", "start")
	ui.toast("B6 · the yard sale")

func floor_skip2() -> void:
	mode = "cut"
	for f in ["B7", "B8", "B9", "B9", "B9"]:
		ui.floor_tag(f)
		sfx.play("static", 0.2)
		glitch_kick(0.7)
		await wait(0.42)
	mode = "play"
	await go_area("b10", "start")

# ---------------------------------------------------------------- ending
func ending() -> void:
	S.flags.metWren = true
	mode = "cut"
	P.speed = 0.0
	await say_p([["???", "Oh."], ["???", "You can see me."], ["WREN", "This was my file. Save one. I was on the lake part. I was so close to the end."],
		["WREN", "You came all the way down. Nobody ever came all the way down."],
		["WREN", "The summer I got this, I went swimming at the real lake."], ["WREN", "The cartridge never left my shelf after that."],
		["WREN", "Then someone sold it at a yard sale. And now you have it, {N}."],
		["WREN", "I've been waiting so long. Can I go home now?"]])
	sfx.play("bell", false)
	sfx.stop_music()
	await wait(1.6)
	var m: Person = statue.mesh
	reparent_to(m, area.root)
	m.set_eyes(Color("#ff2020"))
	var bx: float = P.x - sin(P.face) * 1.3
	var bz: float = P.z - cos(P.face) * 1.3
	m.position = Vector3(bx, 0.3, bz)
	m.rotation.y = P.face
	await say_p([["", "Don't turn around.", 0]])
	await say_p([["WREN", "Thank you, {N}."], ["WREN", "I'm going home now."], ["WREN", "It's your turn to wait under the dock."], ["WREN", "Don't worry. Someone always finds the cartridge eventually."]])
	var y0 := cam_yaw
	var y1: float = P.face + 0.15
	var st := {"t": 0.0, "done": false}
	cam_override = func(dt: float) -> void:
		st.t += dt / 1.5
		var k := minf(1.0, st.t)
		var e := k * k * (3.0 - 2.0 * k)
		var yaw := lerpf(y0, y0 + angdiff(y0, y1), e)
		var d := lerpf(cam_dist, 2.4, e)
		cam.position = Vector3(P.x + sin(yaw) * d, 1.7, P.z + cos(yaw) * d)
		cam.look_at(Vector3(lerpf(P.x, bx, e), 1.5, lerpf(P.z, bz, e)))
		if k >= 1.0:
			st.done = true
	while not st.done:
		await get_tree().process_frame
	sfx.play("sting")
	glitch_kick(1.0)
	shake = 0.8
	await wait(0.9)
	sfx.play("static", 2.4)
	ui.fade(true)
	await wait(1.2)
	cam_override = Callable()
	await go_area("lakebed", {"x": 0.0, "z": 2.0, "yaw": 0.0}, true)
	pm.visible = false
	if pm.get_parent():
		pm.get_parent().remove_child(pm)
	var L: Dictionary = area
	L.me.visible = true
	L.wren.position = Vector3(0, 7.2, -9)
	var wt := {"t": 0.0}
	cam_override = func(dt: float) -> void:
		wt.t += dt
		cam.position = Vector3(3.2, 1.3, 6.5)
		cam.look_at(Vector3(0, 3.2, -1))
		var wr: Person = L.wren
		wr.position.z = -9.0 + minf(18.0, wt.t * 2.4)
		wr.rotation.y = 0.0
		wr.anim(dt, 2.4)
		var me: Person = L.me
		me.rotation.y = PI * 0.85 + sin(wt.t * 0.6) * 0.1
		me.position.y = 0.1 + sin(wt.t * 0.8) * 0.08
		me.shL.rotation.z = -0.4 + sin(wt.t) * 0.1
		me.shR.rotation.z = 0.4 - sin(wt.t) * 0.1
		L.surface.position.y = 7.4 + sin(wt.t * 1.4) * 0.05
	sfx.set_song("void", 2.6)
	ui.fade(false)
	await wait(1.8)
	ui.toast(fmt("SAVE 1: {N}"), 2.4)
	await wait(2.6)
	ui.toast("UNDER THE DOCK", 2.6)
	await wait(3.4)
	ui.fade(true)
	await wait(0.9)
	cam_override = Callable()
	META.ended = true
	META.endName = S.name
	META.endMins = mins_played()
	META.endDeaths = S.deaths
	save_meta()
	S.done = true
	save()
	mode = "end"
	sfx.set_song("title", 1.6)
	sfx.ambient_off()
	ui.end_stats("Time: " + str(mins_played()) + " min · Deaths: " + str(int(S.deaths)) + " · Pages: " + str(S.pages.size()) + " of 3")
	ui.show_panel("end")
	layout_ui()
	ui.fade(false)

# ---------------------------------------------------------------- corruption fx
var glitch_v := 0.0
var burst_t := 20.0
var blink_t := 0.0
var blink_next := 12.0
var fx_drain := 0.0
var fx_tint := Vector3.ONE

func glitch_kick(v: float) -> void:
	glitch_v = maxf(glitch_v, v)

func fx_update(dt: float) -> void:
	var c := C()
	var id: String = area.id
	var drain := 0.0
	var tint := Vector3.ONE
	var rate := 0.0
	if id == "village":
		drain = [0.0, 0.12, 0.35, 0.5][c]
		tint = Vector3(1.06, 0.88, 0.96) if c == 2 else (Vector3(0.82, 0.9, 1.15) if c == 3 else Vector3.ONE)
		rate = [0.0, 45.0, 18.0, 9.0][c]
	elif id == "hollow":
		drain = c * 0.1
		rate = 40.0 if c > 0 else 0.0
	elif id == "b1":
		drain = 0.5; tint = Vector3(0.85, 0.92, 1.15); rate = 7.0
	elif id == "b6":
		drain = 0.55; tint = Vector3(1.12, 1.0, 0.82); rate = 12.0
	elif id == "b10":
		drain = 0.3; rate = 14.0
	elif id == "lakebed":
		drain = 0.2; rate = 0.0
	fx_drain = lerpf(fx_drain, drain, minf(1.0, dt * 2.0))
	fx_tint = fx_tint.lerp(tint, minf(1.0, dt * 2.0))
	if rate > 0.0 and mode == "play":
		burst_t -= dt
		if burst_t <= 0.0:
			burst_t = rnd(rate * 0.6, rate * 1.4)
			glitch_kick(rnd(0.3, 0.8))
			sfx.play("static", 0.12)
	glitch_v = maxf(0.0, glitch_v - dt * 2.2)
	if blink_t > 0.0:
		blink_t -= dt
	if ((id == "village" and c >= 2) or id == "b1") and statue.active and mode == "play" and dlg == null:
		blink_next -= dt
		if blink_next <= 0.0:
			blink_next = rnd(8, 15)
			blink_t = 0.14
	ui.set_post(fx_drain, glitch_v if glitch_v > 0.02 else 0.0, fx_tint, now, blink_t > 0.0)

# ---------------------------------------------------------------- camera
var cam_pos := Vector3.ZERO
var cam_snap := true

func camera_update(dt: float) -> void:
	if cam_override.is_valid():
		cam_override.call(dt)
		return
	if mode == "play" and dlg == null:
		cam_yaw -= inp.lookX
		cam_pitch = clampf(cam_pitch + inp.lookY, -0.2, 1.15)
	if now - last_look_input > 1.6 and P.speed > 1.0 and mode == "play":
		var d := angdiff(cam_yaw, P.face + PI)
		if absf(d) < 2.3:
			cam_yaw += d * minf(1.0, dt * 0.9)
	var tx: float = P.x
	var ty: float = P.y + 1.35
	var tz: float = P.z
	var cp := cos(cam_pitch)
	var px := tx + sin(cam_yaw) * cp * cam_dist
	var pz := tz + cos(cam_yaw) * cp * cam_dist
	var py := ty + sin(cam_pitch) * cam_dist
	var t := seg_hit(tx, tz, px, pz, 0.3)
	if t < 1.0:
		var k := maxf(0.15, t - 0.05)
		px = tx + (px - tx) * k
		pz = tz + (pz - tz) * k
		py = ty + (py - ty) * maxf(k, 0.4)
	py = maxf(py, area.height.call(px, pz) + 0.35)
	if area.light == "dungeon" or area.light == "under":
		py = minf(py, 4.0)
	var target := Vector3(px, py, pz)
	if cam_snap or cam_pos.distance_to(target) > 8.0:
		cam_pos = target
		cam_snap = false
	else:
		cam_pos = cam_pos.lerp(target, minf(1.0, dt * 14.0))
	cam.position = cam_pos
	if shake > 0.0:
		shake -= dt
		cam.position.x += rnd(-1, 1) * shake * 0.25
		cam.position.y += rnd(-1, 1) * shake * 0.25
	cam.look_at(Vector3(tx, ty + 0.15, tz))

# ---------------------------------------------------------------- HUD + panels
func layout_ui() -> void:
	var playing := mode == "play" or mode == "dead" or mode == "cut"
	ui.touch_visible(ui.touch_mode and mode == "play")
	ui.hud_visible(playing and area != null and area.id != "lakebed")
	ui.floor_visible(playing)
	if not playing:
		ui.prompt("")
	if mode != "play" and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func open_pause() -> void:
	mode = "pause"
	ui.pause_stats("Bell pieces: %d of 3 · Keys: %d\nDiary pages: %d of 3 · Deaths: %d\nTime: %d min" % [int(S.pieces), int(S.keys), S.pages.size(), int(S.deaths), mins_played()])
	ui.sync_pause()
	ui.show_panel("pause")
	layout_ui()
	sfx.play("menu")

func close_pause() -> void:
	mode = "play"
	ui.show_panel("")
	layout_ui()

func open_map() -> void:
	mode = "map"
	ui.open_map()
	layout_ui()
	sfx.play("menu")

func close_map() -> void:
	mode = "play"
	ui.close_map()
	layout_ui()

# ---------------------------------------------------------------- files / name / start
func show_files() -> void:
	mode = "files"
	if area != null:
		area.root.visible = false
	area = null
	dlg = null
	ui.dialog_hide()
	cam_override = Callable()
	SAVED = read_json(SAVE_PATH)
	var s1 := ""
	var s1s := ""
	if META.ended:
		s1 = "1  " + str(META.endName)
		s1s = "UNDER THE DOCK"
	else:
		s1 = "1  WREN"
		s1s = "THE LAKE · 2 BELL PIECES · 99:59"
	var s2 := ""
	var s2s := ""
	if SAVED is Dictionary and not SAVED.get("done", false):
		s2 = "2  " + str(SAVED.name)
		var an: String = {"village": "MILLBROOK", "hollow": "THE HOLLOW"}.get(SAVED.area, "THE UNDERNEATH")
		s2s = "%s · %d BELL PIECES · %d MIN" % [an, int(SAVED.pieces), maxi(1, roundi(float(SAVED.playMs) / 60000.0))]
	else:
		s2 = "2  NEW FILE"
		s2s = "NEXT PLAYER" if META.ended else "EMPTY"
	ui.set_files(s1, s1s, s2, s2s)
	ui.show_panel("files")
	layout_ui()
	sfx.set_song("title", 1.4 if META.ended else 0.0)
	sfx.ambient_off()

func on_insert() -> void:
	sfx.play("ok")
	show_files()

func on_slot1() -> void:
	sfx.play("static", 0.3)
	if META.ended:
		ui.files_msg("You can't load that file. You're still in it.")
		return
	META.slot1Taps = int(META.slot1Taps) + 1
	save_meta()
	ui.files_msg(["This isn't your file.", "Please don't.", "SAVE 1 is at the lake. It's been at the lake for a long time."][mini(2, int(META.slot1Taps) - 1)])

func on_slot2() -> void:
	sfx.play("ok")
	if SAVED is Dictionary and not SAVED.get("done", false):
		S = SAVED
		start_game(false)
		return
	ui.show_name()

func on_name_submit(raw: String) -> void:
	var n := ""
	for ch in raw.strip_edges().to_upper():
		if (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == " ":
			n += ch
	n = n.substr(0, 8)
	if n == "":
		ui.name_msg("Type a name.")
		return
	if n == "WREN" or (META.ended and n == META.endName):
		ui.name_msg("That name is taken.")
		sfx.play("static", 0.3)
		return
	S = new_run(n)
	save()
	start_game(true)

func on_erase() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	META = {"ended": false, "endName": "", "slot1Taps": 0, "muted": META.muted, "sens": META.sens, "inv": META.inv, "gfx": META.get("gfx", "auto"), "endMins": 0, "endDeaths": 0}
	save_meta()
	sfx.play("static", 0.6)
	show_files()

func on_pause_button(id: String) -> void:
	match id:
		"resume":
			close_pause()
		"sound":
			META.muted = not META.muted
			sfx.set_mute(META.muted)
			save_meta()
		"sens":
			var s := float(META.sens)
			META.sens = 1.0 if s < 0.8 else (0.6 if s > 1.2 else 1.5)
			save_meta()
		"inv":
			META.inv = not META.inv
			save_meta()
		"gfx":
			META.gfx = "low" if META.get("gfx", "auto") == "auto" else "auto"
			save_meta()
			q_max = 1 if META.gfx == "low" else (3 if OS.has_feature("mobile") else 4)
			q_level = mini(q_level, q_max)
			if META.gfx == "auto":
				q_level = mini(2, q_max)
			apply_quality()
		"quit":
			save()
			show_files()
	ui.sync_pause()

func start_game(fresh: bool) -> void:
	build_world()
	ui.show_panel("")
	mode = "play"
	layout_ui()
	statue.steps = 0
	last_c = -1
	S.hp = maxi(int(S.get("hp", 0)), 2)
	if not S.has("flags") or S.flags is Array:
		S.flags = {}
	if not S.has("taken") or S.taken is Array:
		S.taken = {}
	if not S.has("pages") or S.pages is Array:
		S.pages = {}
	var a: String = S.area
	var sp = "start"
	if S.has("check") and S.check is Dictionary and S.check.get("area", "") == a:
		sp = {"x": float(S.check.x), "z": float(S.check.z), "yaw": float(S.check.yaw)}
	if not a in ["village", "hollow", "b1"]:
		a = "b1"
		sp = "start"
	if fresh:
		a = "village"
		sp = "start"
	await go_area(a, sp)
	if fresh:
		say([["", "The cartridge clicks into place."], ["", fmt("SAVE 1: " + str(META.endName) + " · UNDER THE DOCK") if META.ended else "SAVE 1: WREN · THE LAKE", 0.03], ["", fmt("SAVE 2: {N} · NEW")], ["", "Find the Elder near the middle of the village."]])

# ---------------------------------------------------------------- main loop
var dlg_cool := 0.0

func npcs_update(dt: float) -> void:
	var c := C()
	for n in area.npcs:
		n.t += dt
		var dx: float = P.x - n.x
		var dz: float = P.z - n.z
		var d := Vector2(dx, dz).length()
		if n.facePlayer > 0.0:
			n.facePlayer -= dt
		var look: bool = d < 3.5 or n.facePlayer > 0.0 or c >= 2
		var want: float = atan2(dx, dz) if look else n.baseRy + sin(n.t * 0.4) * 0.35
		var m: Person = n.mesh
		m.rotation.y += angdiff(m.rotation.y, want) * minf(1.0, dt * (20.0 if c >= 2 else 5.0))
		m.anim(dt, 0.0)
		m.head.rotation.x = 0.25 if c >= 3 else sin(n.t * 1.3) * 0.04

var near_t := 0.0
const LAMPC := Color(1.0, 0.75, 0.44)

func world_fx(dt: float) -> void:
	var best_d := 1e9
	var bpos := Vector3.ZERO
	var bc := Color.WHITE
	var bi := 0.0
	var found := false
	for t in area.torches:
		var fl := 0.75 + sin(now * 13.0 + t.ph) * 0.12 + sin(now * 23.7 + t.ph * 2.0) * 0.08 + sin(now * 5.3 + t.ph) * 0.05
		if t.fl:
			t.fl.scale = Vector3(0.32 * (0.9 + fl * 0.15), 0.55 * fl, 1.0)
		if t.gl:
			t.gl.material_override.set_shader_parameter("opacity", 0.32 + fl * 0.22)
		var d: float = (t.x - P.x) * (t.x - P.x) + (t.z - P.z) * (t.z - P.z)
		if d < best_d:
			best_d = d
			bpos = Vector3(t.x, t.y, t.z)
			bc = t.col
			bi = 7.0 * fl
			found = true
	if area.id == "village" and C() >= 2:
		for i in area.lamps.size():
			if float(area.lampGlow[i].material_override.get_shader_parameter("opacity")) <= 0.0:
				continue
			var l: Node3D = area.lampGlow[i]
			var d: float = (l.position.x - P.x) * (l.position.x - P.x) + (l.position.z - P.z) * (l.position.z - P.z)
			if d < best_d:
				best_d = d
				bpos = Vector3(l.position.x, 2.6, l.position.z)
				bc = LAMPC
				bi = 9.0
				found = true
	if found and best_d < 400.0:
		lamp_light.position = bpos
		lamp_light.light_color = bc
		lamp_light.light_energy = bi * clampf(1.3 - sqrt(best_d) / 20.0, 0.0, 1.0) / PI * LIGHT_K
	else:
		lamp_light.light_energy = 0.0
	near_t -= dt
	if near_t <= 0.0:
		near_t = 0.25
		for e in area.near:
			var dx: float = e[1] - P.x
			var dz: float = e[2] - P.z
			e[0].visible = dx * dx + dz * dz < 900.0
		for L in area.lod:
			var dx: float = L[2] - P.x
			var dz: float = L[3] - P.z
			var nr := dx * dx + dz * dz < 42.0 * 42.0
			L[0].visible = nr
			L[1].visible = not nr

func step(dt: float) -> void:
	if mode == "play" and dlg == null:
		S.playMs = float(S.playMs) + dt * 1000.0
	var had_dlg := dlg != null
	dlg_update(dt)
	if had_dlg and dlg == null:
		dlg_cool = 0.2
	if dlg_cool > 0.0:
		dlg_cool -= dt
	if mode == "play" and dlg == null and not switching:
		player_update(dt)
		if dlg_cool <= 0.0:
			inter_update()
		else:
			ui.prompt("")
		items_update(dt)
		triggers_update()
		foes_update(dt)
		statue_update(dt)
	else:
		if pm:
			pm.anim(dt, 0.0)
			if area.id != "lakebed" and pm.get_parent() == area.root:
				pm.visible = true
		ui.prompt("")
		statue.moving = false
	if area == null:
		return
	npcs_update(dt)
	if area.update.is_valid():
		area.update.call(dt)
	if area == null:
		return
	parts_update(dt)
	fx_update(dt)
	camera_update(dt)
	lantern.position = Vector3(P.x + sin(P.face) * 0.2, P.y + 2.3, P.z + cos(P.face) * 0.2)
	world_fx(dt)
	if S != null:
		ui.hud(int(S.hp), int(S.maxHearts), int(S.keys), int(S.pieces))

func _process(delta: float) -> void:
	var raw := delta
	var dt := clampf(delta, 0.001, 0.05)
	now += dt
	poll_input()
	if mode == "play" and dlg == null and not switching:
		if pressed.start:
			open_pause()
		elif pressed.select:
			open_map()
	elif mode == "pause" and pressed.start:
		close_pause()
	elif mode == "map" and (pressed.select or pressed.start or pressed.B):
		close_map()
	if area != null and (mode == "play" or mode == "dead" or mode == "cut"):
		step(dt)
	elif area == null:
		ui.set_post(0.0, 0.0, Vector3.ONE, now, false)
	var want3d := area == null
	if get_viewport().disable_3d != want3d:
		get_viewport().disable_3d = want3d
	for p in persons:
		if p.is_visible_in_tree():
			p.apply()
	quality_tick(raw)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if sh_back() == 0:
			get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if mode == "play" and dlg == null and S != null:
			open_pause()
		if S != null and mode != "files" and mode != "title":
			save()
		boot_ok()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		if S != null and mode != "files" and mode != "title":
			save()
		boot_ok()

func sh_back() -> int:
	if mode == "map":
		close_map()
		return 1
	if mode == "pause":
		if ui.cur_panel == "help":
			ui.show_panel("pause")
			return 1
		close_pause()
		return 1
	if mode == "play" and dlg == null:
		open_pause()
		return 1
	if mode == "play" or mode == "cut" or mode == "dead":
		return 1
	if mode == "files" and ui.cur_panel != "files":
		show_files()
		return 1
	if mode == "end":
		show_files()
		return 1
	return 0

# ---------------------------------------------------------------- test hook (desktop only: --  <cmd>)
func test_hook(args: PackedStringArray) -> void:
	var cmd := args[0]
	var out := args[1] if args.size() > 1 else "/tmp/shot"
	if cmd == "menus":
		var sn := func(n: String) -> void:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out + "_" + n + ".png")
		await wait(0.5)
		await sn.call("cart")
		on_insert()
		await wait(0.3)
		await sn.call("files")
		on_slot1()
		await wait(0.2)
		await sn.call("files2")
		on_slot2()
		await wait(0.3)
		ui.name_in.text = "BUGGY"
		await sn.call("name")
		ui.submit_name()
		while area == null or switching:
			await get_tree().process_frame
		await wait(1.5)
		await sn.call("intro")
		while dlg != null:
			next_line()
		ui.touch_mode = true
		layout_ui()
		ui.stick_id = 0
		ui.stick_origin = Vector2(150, 500)
		ui.stick_knob = Vector2(30, -20)
		ui.tbtn["B"] = true
		ui.touch.queue_redraw()
		await wait(0.3)
		await sn.call("touch")
		get_tree().quit()
		return
	if not cmd.begins_with("shot"):
		return
	god = true
	await get_tree().process_frame
	ui.hide_title()
	S = new_run("BUGGY")
	start_game(true)
	while switching or area == null:
		await get_tree().process_frame
	await wait(0.4)
	while dlg != null:
		next_line()
	var snap := func(n: String) -> void:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out + "_" + n + ".png")
	var tp := func(x: float, z: float, yaw: float, w := 1.0) -> void:
		P.x = x; P.z = z; cam_yaw = yaw; cam_snap = true
		await wait(w)
	for step_ in args.slice(2):
		var a := step_.split(":")
		match a[0]:
			"tp":
				await tp.call(float(a[1]), float(a[2]), float(a[3]), float(a[4]) if a.size() > 4 else 1.0)
			"snap":
				await snap.call(a[1])
			"swing":
				keys_tap["B"] = true
				await wait(float(a[1]))
			"spin":
				ui.tbtn["B"] = true
				await wait(1.0)
				ui.tbtn["B"] = false
				await wait(float(a[1]))
			"area":
				await go_area(a[1], a[2] if a.size() > 2 else "start")
				await wait(1.0)
			"pieces":
				S.pieces = int(a[1])
				if a.size() > 2: S.flags.copied = true
				apply_light(); set_song()
			"bell":
				S.flags.bellRung = true
				S.pieces = 3
				AREAS.village.bellWhole.visible = true
				AREAS.village.bellBroken.visible = false
				AREAS.village.hatch.visible = true
				apply_light()
			"wait":
				await wait(float(a[1]))
			"pitch":
				cam_pitch = float(a[1])
			"dist":
				cam_dist = float(a[1])
			"map":
				open_map()
				await wait(0.3)
				await snap.call(a[1])
				close_map()
			"pause":
				open_pause()
				await wait(0.3)
				await snap.call(a[1])
				close_pause()
			"say":
				say([["ELDER", "Ah, a new face. What was your name again?"]])
				await wait(1.5)
				await snap.call(a[1])
				dlg = null
				ui.dialog_hide()
			"ending":
				ending()
				for i in 60:
					await wait(0.25)
					if dlg != null:
						next_line()
					if area != null and area.id == "lakebed":
						break
				await wait(float(a[1]))
				await snap.call("ending")
			"files":
				show_files()
				await wait(0.5)
				await snap.call(a[1])
			"touch":
				ui.touch_mode = true
				layout_ui()
			"god":
				god = true
			"look":
				var lp := Vector3(float(a[1]), float(a[2]), float(a[3]))
				var lt := Vector3(float(a[4]), float(a[5]), float(a[6]))
				cam_override = func(_dt: float) -> void:
					cam.position = lp
					cam.look_at(lt)
				await wait(0.5)
			"touchtest":
				ui.touch_mode = true
				layout_ui()
				await wait(0.2)
				var e := InputEventScreenTouch.new()
				e.position = Vector2(1000, 600)
				e.pressed = true
				e.index = 0
				Input.parse_input_event(e)
				await wait(0.2)
				print("TOUCH vsize=", ui.vsize(), " look_id=", ui.look_id, " look_last=", ui.look_last, " tbtn=", ui.tbtn, " win=", DisplayServer.window_get_size(), " cs=", get_window().content_scale_size)
			"dbg":
				print("DBG area=", area.id, " fps=", Engine.get_frames_per_second(), " draws=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " objs=", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), " prims=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), " vmem=", Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1e6)
			"nolook":
				cam_override = Callable()
	get_tree().quit()
