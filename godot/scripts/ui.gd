# Secondhand 3D (c) 2026 Buggy Games YT. All rights reserved.
# HUD, dialog box, menus, map and the touch controls.
class_name UI
extends CanvasLayer

var game
var root: Control
var font: SystemFont
var post_layer: CanvasLayer
var post_rect: ColorRect
var post_mat: ShaderMaterial
var blink_rect: ColorRect
var backdrop_rect: ColorRect
var hearts: RichTextLabel
var items_lbl: Label
var hud_box: HBoxContainer
var floor_lbl: Label
var prompt_panel: PanelContainer
var prompt_lbl: Label
var toast_lbl: Label
var toast_t := 0.0
var fade_rect: ColorRect
var dlg: PanelContainer
var dlg_who: Label
var dlg_who_box: PanelContainer
var dlg_text: Label
var dlg_more: Label
var dlg_glitchy := false
var touch: Control
var map_ctl: Control
var map_name: Label
var panels := {}
var cur_panel := ""
var files_msg_lbl: Label
var slot1: Button
var slot2: Button
var name_in: LineEdit
var name_msg_lbl: Label
var confirm_box: VBoxContainer
var pause_stats_lbl: Label
var pbtn := {}
var end_stats_lbl: Label
var help_back := "pause"
var hud_key := ""

# touch state (read by the game)
var touch_mode := false
var tbtn := {"A": false, "B": false, "start": false, "select": false}
var ttap := {}
var stick := Vector2.ZERO
var stick_id := -1
var stick_origin := Vector2.ZERO
var stick_knob := Vector2.ZERO
var look_id := -1
var look_last := Vector2.ZERO
var look_acc := Vector2.ZERO
var btn_ids := {}
var unit := 1.0
const DiagScript := preload("res://scripts/diag.gd")
var diag
var safe_files_btn: Button
var touches := {}

func _ready() -> void:
	layer = 5
	font = SystemFont.new()
	font.font_names = PackedStringArray(["monospace", "Droid Sans Mono", "DejaVu Sans Mono", "Roboto Mono", "Courier New"])
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 15
	post_layer = CanvasLayer.new()
	post_layer.layer = 1
	add_child(post_layer)
	post_rect = ColorRect.new()
	post_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = load("res://shaders/post.gdshader")
	post_rect.material = post_mat
	post_rect.visible = false
	post_layer.add_child(post_rect)
	blink_rect = ColorRect.new()
	blink_rect.color = Color(0, 0, 0)
	blink_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	blink_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blink_rect.visible = false
	post_layer.add_child(blink_rect)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.show_behind_parent = true
	post_layer.add_child(backdrop)
	post_layer.move_child(backdrop, 0)
	backdrop_rect = backdrop
	root = Control.new()
	root.theme = th
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	build_hud()
	build_dialog()
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade_rect)
	root.move_child(fade_rect, dlg.get_index())
	toast_lbl = mk_label("", 20, Color(1, 1, 1))
	toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_lbl.add_theme_constant_override("outline_size", 6)
	toast_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	toast_lbl.modulate.a = 0.0
	root.add_child(toast_lbl)
	touch = TouchPad.new()
	touch.ui = self
	touch.set_anchors_preset(Control.PRESET_FULL_RECT)
	touch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch.visible = false
	root.add_child(touch)
	build_map()
	build_panels()
	diag = DiagScript.new()
	diag.ui = self
	diag.game = game
	root.add_child(diag)
	show_panel("cart")

func typing() -> bool:
	return name_in != null and name_in.has_focus()

func mk_label(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func sbox(bg: Color, border: Color = Color(0, 0, 0, 0), bw := 0, radius := 0, pad := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s

# ---------------------------------------------------------------- layout
# The UI is laid out in a virtual canvas whose short side is about 420 units on phones
# (so it looks the same at any phone resolution / DPI setting), recomputed on every resize.
var last_ws := Vector2i.ZERO
var last_sa := Rect2i()
var force_mobile := false   # test hook: lay out like a phone on desktop

func is_phone() -> bool:
	return OS.has_feature("mobile") or force_mobile

func win_size() -> Vector2:
	var w := get_window()
	var ws := Vector2(w.size) if w else Vector2.ZERO
	if ws.x < 2.0 or ws.y < 2.0:
		ws = Vector2(DisplayServer.window_get_size())
	if ws.x < 2.0 or ws.y < 2.0:
		ws = Vector2(1280, 720)
	return ws

func on_resize() -> void:
	var win := get_window()
	var ws := win_size()
	var f := 1.0
	if is_phone():
		# landscape: ~420 tall x >=800 wide; portrait (if the OS ever forces it): ~800 tall
		f = clampf(minf(maxf(ws.x, ws.y) / 800.0, minf(ws.x, ws.y) / 420.0), 1.0, 6.0)
	else:
		f = clampf(minf(ws.x, ws.y) / 640.0, 1.0, 3.0)
		if OS.get_cmdline_user_args().has("scale2"):
			f = 2.0
	unit = f
	var cs := Vector2i(maxi(320, int(ws.x / f)), maxi(240, int(ws.y / f)))
	last_ws = Vector2i(ws)
	last_sa = DisplayServer.get_display_safe_area()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	if win.content_scale_size != cs:
		win.content_scale_size = cs
	relayout()
	call_deferred("relayout")

# called every frame: catches rotations / immersive-mode changes the signal can miss
func watch_size() -> void:
	var ws := Vector2i(win_size())
	if ws != last_ws or (is_phone() and DisplayServer.get_display_safe_area() != last_sa):
		if game and game.has_method("on_resize"):
			game.on_resize()
		else:
			on_resize()

var fake_cut := 0.0   # test hook: pretend a camera cutout on the left
func safe_insets() -> Array:
	if fake_cut > 0.0:
		return [fake_cut / unit, 0.0, 0.0, 0.0]
	if not OS.has_feature("mobile"):
		return [0.0, 0.0, 0.0, 0.0]
	var sa := DisplayServer.get_display_safe_area()
	var ws := win_size()
	if sa.size.x <= 0 or sa.size.y <= 0 or sa.size.x > ws.x + 1 or sa.size.y > ws.y + 1:
		return [0.0, 0.0, 0.0, 0.0]
	var k := unit
	var r := [maxf(0.0, sa.position.x) / k, maxf(0.0, sa.position.y) / k, maxf(0.0, ws.x - sa.end.x) / k, maxf(0.0, ws.y - sa.end.y) / k]
	for i in 4:
		r[i] = minf(float(r[i]), 80.0)   # never let a bogus safe area eat the screen
	return r

func vsize() -> Vector2:
	return root.get_viewport_rect().size

func relayout() -> void:
	var s := vsize()
	var ins := safe_insets()
	hud_box.position = Vector2(maxf(12.0, ins[0]), maxf(10.0, ins[1]))
	floor_lbl.position = Vector2(s.x - maxf(14.0, ins[2]) - floor_lbl.size.x, maxf(10.0, ins[1]))
	toast_lbl.position = Vector2(12, s.y * 0.22)
	toast_lbl.size = Vector2(s.x - 24, 40)
	var dw := minf(s.x * 0.92, 640.0)
	dlg.custom_minimum_size = Vector2(dw, 92)
	dlg.size = Vector2(dw, dlg.size.y)
	dlg.position = Vector2((s.x - dw) / 2.0, s.y - maxf(16.0, ins[3]) - dlg.size.y)
	prompt_panel.position = Vector2((s.x - prompt_panel.size.x) / 2.0, s.y * 0.7 - prompt_panel.size.y)
	var ms := minf(s.x * 0.86, s.y * 0.7)
	map_ctl.custom_minimum_size = Vector2(ms, ms)
	relayout_panels()
	if diag:
		diag.relayout(s, ins)
	touch.queue_redraw()

func _process(dt: float) -> void:
	watch_size()
	if toast_t > 0.0:
		toast_t -= dt
		if toast_t <= 0.0:
			var tw := create_tween()
			tw.tween_property(toast_lbl, "modulate:a", 0.0, 0.4)
	if dlg.visible:
		dlg.position.y = vsize().y - maxf(16.0, safe_insets()[3]) - dlg.size.y
		var x0 := (vsize().x - dlg.size.x) / 2.0
		if dlg_glitchy:
			var ph := fmod(Time.get_ticks_msec() / 1000.0, 3.0) / 3.0
			dlg.position.x = x0 + (3.0 if ph > 0.96 and ph < 0.97 else (-2.0 if ph >= 0.97 and ph < 0.98 else 0.0))
		else:
			dlg.position.x = x0
		dlg_more.modulate.a = 1.0 if fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.5 else 0.0
	if prompt_panel.visible:
		var s := vsize()
		prompt_panel.position = Vector2((s.x - prompt_panel.size.x) / 2.0, s.y * 0.7 - prompt_panel.size.y)
	if floor_lbl.visible:
		floor_lbl.position.x = vsize().x - maxf(14.0, safe_insets()[2]) - floor_lbl.size.x

# ---------------------------------------------------------------- HUD
func build_hud() -> void:
	hud_box = HBoxContainer.new()
	hud_box.add_theme_constant_override("separation", 14)
	hud_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud_box)
	hearts = RichTextLabel.new()
	hearts.bbcode_enabled = true
	hearts.fit_content = true
	hearts.autowrap_mode = TextServer.AUTOWRAP_OFF
	hearts.scroll_active = false
	hearts.custom_minimum_size = Vector2(10, 26)
	hearts.add_theme_font_size_override("normal_font_size", 20)
	hearts.add_theme_constant_override("outline_size", 4)
	hearts.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	hearts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_box.add_child(hearts)
	items_lbl = mk_label("", 15, Color("#e8d9a8"))
	items_lbl.add_theme_constant_override("outline_size", 4)
	items_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	hud_box.add_child(items_lbl)
	floor_lbl = mk_label("", 18, Color("#9fc6e8"))
	floor_lbl.add_theme_constant_override("outline_size", 4)
	floor_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	root.add_child(floor_lbl)
	prompt_panel = PanelContainer.new()
	prompt_panel.add_theme_stylebox_override("panel", sbox(Color(0, 0, 0, 0.6), Color("#555555"), 1, 0, 6))
	prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_lbl = mk_label("", 14, Color(1, 1, 1))
	prompt_panel.add_child(prompt_lbl)
	prompt_panel.visible = false
	root.add_child(prompt_panel)

func hud(hp: int, maxh: int, keys: int, pieces: int) -> void:
	var key := "%d|%d|%d|%d" % [hp, maxh, keys, pieces]
	if key == hud_key:
		return
	hud_key = key
	var h := ""
	for i in maxh:
		var v := hp - i * 2
		if v >= 2:
			h += "[color=#e04848]♥[/color]"
		elif v == 1:
			h += "[color=#e08888]♥[/color]"
		else:
			h += "[color=#3a1d1d]♥[/color]"
	hearts.text = h
	items_lbl.text = ("KEY ×%d  " % keys if keys > 0 else "") + "BELL %d/3" % pieces

func hud_visible(v: bool) -> void:
	hud_box.visible = v
	if v:
		hud_key = ""

func floor_tag(t: String) -> void:
	floor_lbl.text = t
	floor_lbl.reset_size()

func floor_visible(v: bool) -> void:
	floor_lbl.visible = v

func prompt(t: String) -> void:
	if t == "":
		prompt_panel.visible = false
		return
	if prompt_lbl.text != t:
		prompt_lbl.text = t
		prompt_panel.reset_size()
	prompt_panel.visible = true

func toast(t: String, dur := 2.6) -> void:
	toast_lbl.text = t
	toast_lbl.modulate.a = 1.0
	toast_t = dur

func fade(on: bool) -> void:
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", 1.0 if on else 0.0, 0.45)

func set_post(drain: float, glitch: float, tint: Vector3, t: float, blink: bool) -> void:
	var active := drain > 0.002 or glitch > 0.0 or tint.distance_to(Vector3.ONE) > 0.003
	if game and game.META.get("safe", false):
		active = false   # safe graphics: no screen-texture post effect
	post_rect.visible = active
	if active:
		post_mat.set_shader_parameter("drain", drain)
		post_mat.set_shader_parameter("glitch", glitch)
		post_mat.set_shader_parameter("tint", tint)
		post_mat.set_shader_parameter("t", t)
		post_mat.set_shader_parameter("px", unit)
	blink_rect.visible = blink
	backdrop_rect.visible = game == null or game.area == null

# ---------------------------------------------------------------- dialog
func build_dialog() -> void:
	dlg = PanelContainer.new()
	var st := sbox(Color("#17132a"), Color("#eadfc2"), 3, 7, 0)
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 10
	st.content_margin_bottom = 18
	st.shadow_color = Color(0, 0, 0, 0.45)
	st.shadow_size = 6
	st.shadow_offset = Vector2(0, 6)
	dlg.add_theme_stylebox_override("panel", st)
	dlg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dlg.add_child(vb)
	dlg_who_box = PanelContainer.new()
	var ws := sbox(Color("#e8b830"), Color(0, 0, 0, 0), 0, 3, 0)
	ws.content_margin_left = 6
	ws.content_margin_right = 6
	dlg_who_box.add_theme_stylebox_override("panel", ws)
	dlg_who_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	dlg_who_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dlg_who = mk_label("", 13, Color("#1c1206"))
	dlg_who_box.add_child(dlg_who)
	vb.add_child(dlg_who_box)
	dlg_text = mk_label("", 16, Color("#f2ecdc"))
	dlg_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dlg_text.add_theme_constant_override("shadow_offset_y", 2)
	dlg_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
	dlg_text.custom_minimum_size = Vector2(100, 40)
	vb.add_child(dlg_text)
	dlg_more = mk_label("▼", 14, Color("#e8b830"))
	dlg_more.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	dlg.visible = false
	root.add_child(dlg)
	var more_holder := Control.new()
	more_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dlg.add_child(more_holder)
	more_holder.add_child(dlg_more)
	dlg_more.position = Vector2(-4, -2)

func dialog_show(who: String, glitchy: bool) -> void:
	dlg_who.text = who
	dlg_who_box.visible = who != ""
	dlg_text.text = ""
	dlg_more.visible = false
	dlg_glitchy = glitchy
	dlg.visible = true
	relayout()

func dialog_text(t: String) -> void:
	dlg_text.text = t

func dialog_more(v: bool) -> void:
	dlg_more.visible = v
	if v:
		var mh: Control = dlg_more.get_parent()
		dlg_more.position = Vector2(mh.size.x - 4, mh.size.y - 2)

func dialog_hide() -> void:
	dlg.visible = false

# ---------------------------------------------------------------- touch
func touch_visible(v: bool) -> void:
	touch.visible = v
	if not v:
		stick_id = -1
		stick = Vector2.ZERO
		look_id = -1
		for k in tbtn:
			tbtn[k] = false
		btn_ids.clear()
	touch.queue_redraw()

func take_look() -> Vector2:
	var v := look_acc
	look_acc = Vector2.ZERO
	return v

func btn_geom() -> Dictionary:
	var s := vsize()
	var ins := safe_insets()
	var r := maxf(20.0, ins[2])
	var b := maxf(34.0, ins[3])
	var top := maxf(8.0, ins[1])
	if s.x < 560.0:
		top = maxf(40.0, ins[1] + 32.0)
	return {"A": [Vector2(s.x - r - 37.0, s.y - b - 140.0 + 37.0), 37.0], "B": [Vector2(s.x - r - 176.0 + 37.0, s.y - b - 37.0), 37.0],
		"select": Rect2(s.x / 2.0 - 7.0 - 84.0, top, 84.0, 30.0), "start": Rect2(s.x / 2.0 + 7.0, top, 84.0, 30.0)}

func hit_btn(p: Vector2) -> String:
	var g := btn_geom()
	for k in ["A", "B"]:
		if p.distance_to(g[k][0]) < g[k][1] + 10.0:
			return k
	for k in ["select", "start"]:
		if g[k].grow(8.0).has_point(p):
			return k
	return ""

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		# three-finger tap anywhere toggles the diagnostics overlay
		if e.pressed:
			if e.index == 0:
				touches.clear()
			touches[e.index] = true
			if touches.size() == 3:
				diag.toggle()
		else:
			touches.erase(e.index)
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F3:
		diag.toggle()
	if e is InputEventScreenTouch:
		if not touch_mode:
			touch_mode = true
			if game:
				game.layout_ui()
		if not touch.visible:
			return
		var p: Vector2 = e.position
		if e.pressed:
			var b := hit_btn(p)
			if b != "":
				btn_ids[e.index] = b
				tbtn[b] = true
				ttap[b] = true
			elif p.x < vsize().x * 0.45:
				stick_id = e.index
				stick_origin = p
				stick_knob = Vector2.ZERO
				stick = Vector2.ZERO
			else:
				look_id = e.index
				look_last = p
		else:
			if btn_ids.has(e.index):
				tbtn[btn_ids[e.index]] = false
				btn_ids.erase(e.index)
			if e.index == stick_id:
				stick_id = -1
				stick = Vector2.ZERO
			if e.index == look_id:
				look_id = -1
		touch.queue_redraw()
		get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag:
		if not touch.visible:
			return
		var p: Vector2 = e.position
		if e.index == stick_id:
			var d := p - stick_origin
			if d.length() > 50.0:
				d = d / d.length() * 50.0
			stick_knob = d
			stick = d / 50.0
			touch.queue_redraw()
		elif e.index == look_id:
			look_acc += p - look_last
			look_last = p
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and map_ctl.visible and e.pressed:
		if game and game.mode == "map":
			game.close_map()
			get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- map
func build_map() -> void:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.visible = false
	root.add_child(holder)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bg)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(cc)
	var mc := MapView.new()
	mc.ui = self
	mc.clip_contents = true
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(mc)
	map_ctl = mc
	map_name = mk_label("", 15, Color("#dddddd"))
	map_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_name.set_anchors_preset(Control.PRESET_TOP_WIDE)
	map_name.offset_top = 14
	holder.add_child(map_name)
	map_ctl.set_meta("holder", holder)

func open_map() -> void:
	var names := {"village": "MILLBROOK", "hollow": "THE HOLLOW", "b1": "THE UNDERNEATH", "b6": "THE UNDERNEATH", "b10": "THE UNDERNEATH"}
	map_name.text = names.get(game.area.id, "")
	map_ctl.get_meta("holder").visible = true
	map_ctl.visible = true
	map_ctl.queue_redraw()

func close_map() -> void:
	map_ctl.get_meta("holder").visible = false

# ---------------------------------------------------------------- panels
func panel_box(id: String, wide := 440) -> VBoxContainer:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.visible = false
	root.add_child(holder)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.78)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(bg)
	var sc := ScrollContainer.new()
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	holder.add_child(sc)
	var cc := CenterContainer.new()
	cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.add_child(cc)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", sbox(Color("#0b0b0d"), Color("#2a3a4a") if id == "end" else Color("#3a3a3a"), 2, 0, 20))
	cc.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.custom_minimum_size = Vector2(wide, 0)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	pc.add_child(vb)
	panels[id] = {"holder": holder, "vb": vb, "sc": sc, "cc": cc}
	return vb

func btn(t: String, alt: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_size_override("font_size", 15)
	if alt:
		b.add_theme_stylebox_override("normal", sbox(Color(0, 0, 0, 0), Color("#444444"), 1, 0, 10))
		b.add_theme_stylebox_override("hover", sbox(Color(1, 1, 1, 0.05), Color("#666666"), 1, 0, 10))
		b.add_theme_stylebox_override("pressed", sbox(Color(1, 1, 1, 0.1), Color("#888888"), 1, 0, 10))
		b.add_theme_stylebox_override("focus", sbox(Color(0, 0, 0, 0), Color("#1f9e8f"), 1, 0, 10))
		b.add_theme_color_override("font_color", Color("#aaaaaa"))
		b.add_theme_color_override("font_hover_color", Color("#dddddd"))
		b.add_theme_color_override("font_pressed_color", Color("#ffffff"))
		b.add_theme_color_override("font_focus_color", Color("#dddddd"))
	else:
		b.add_theme_stylebox_override("normal", sbox(Color("#dddddd"), Color(0, 0, 0, 0), 0, 0, 10))
		b.add_theme_stylebox_override("hover", sbox(Color("#eeeeee"), Color(0, 0, 0, 0), 0, 0, 10))
		b.add_theme_stylebox_override("pressed", sbox(Color("#bbbbbb"), Color(0, 0, 0, 0), 0, 0, 10))
		b.add_theme_stylebox_override("focus", sbox(Color("#dddddd"), Color("#1f9e8f"), 2, 0, 10))
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(c, Color(0, 0, 0))
	b.pressed.connect(cb)
	return b

func row(children: Array) -> HFlowContainer:
	# wraps onto a second line when the screen is narrow instead of pushing past the edge
	var h := HFlowContainer.new()
	h.alignment = FlowContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("h_separation", 10)
	h.add_theme_constant_override("v_separation", 8)
	for c in children:
		h.add_child(c)
	return h

func para(t: String, col := Color("#aaaaaa"), size := 14) -> Label:
	var l := mk_label(t, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(200, 0)
	return l

func slot_btn(cb: Callable) -> Button:
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 58)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_stylebox_override("normal", sbox(Color("#111111"), Color("#333333"), 1, 0, 12))
	b.add_theme_stylebox_override("hover", sbox(Color("#151515"), Color("#555555"), 1, 0, 12))
	b.add_theme_stylebox_override("pressed", sbox(Color("#111111"), Color("#1f9e8f"), 1, 0, 12))
	b.add_theme_stylebox_override("focus", sbox(Color("#111111"), Color("#1f9e8f"), 1, 0, 12))
	b.add_theme_font_size_override("font_size", 16)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, Color("#dddddd"))
	b.pressed.connect(cb)
	return b

func build_panels() -> void:
	# cartridge
	var vb := panel_box("cart")
	var cart := CartArt.new()
	cart.ui = self
	cart.custom_minimum_size = Vector2(210, 206)
	cart.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(cart)
	vb.add_child(para("Same yard sale. Same dollar. This time the cartridge is heavier, like there's more inside it."))
	vb.add_child(row([btn("Insert cartridge", false, func() -> void: game.on_insert())]))
	vb.add_child(para("Headphones on. Best played at night.\nA game by Buggy Games YT", Color("#555555"), 11))
	# files
	vb = panel_box("files")
	vb.add_child(para("SELECT A FILE", Color("#cccccc"), 16))
	slot1 = slot_btn(func() -> void: game.on_slot1())
	slot2 = slot_btn(func() -> void: game.on_slot2())
	vb.add_child(slot1)
	vb.add_child(slot2)
	files_msg_lbl = para("", Color("#d64541"), 13)
	files_msg_lbl.custom_minimum_size = Vector2(200, 20)
	vb.add_child(files_msg_lbl)
	vb.add_child(row([btn("Controls", true, _help_from_files), btn("Erase cartridge", true, func() -> void: confirm_box.visible = true)]))
	safe_files_btn = btn("Safe graphics: off", true, func() -> void:
		game.toggle_safe()
		sync_safe())
	vb.add_child(row([safe_files_btn]))
	confirm_box = VBoxContainer.new()
	confirm_box.add_child(para("Erase every file on the cartridge?"))
	confirm_box.add_child(row([btn("Erase", false, func() -> void: game.on_erase()), btn("Keep", true, func() -> void: confirm_box.visible = false)]))
	confirm_box.visible = false
	vb.add_child(confirm_box)
	# name
	vb = panel_box("name")
	vb.add_child(para("ENTER YOUR NAME", Color("#cccccc"), 16))
	name_in = LineEdit.new()
	name_in.max_length = 8
	name_in.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_in.placeholder_text = "NAME"
	name_in.add_theme_font_size_override("font_size", 22)
	name_in.custom_minimum_size = Vector2(240, 48)
	name_in.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	name_in.add_theme_stylebox_override("normal", sbox(Color(0, 0, 0), Color("#555555"), 1, 0, 8))
	name_in.add_theme_stylebox_override("focus", sbox(Color(0, 0, 0), Color("#888888"), 1, 0, 8))
	name_in.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	name_in.text_changed.connect(_upper_name)
	name_in.text_submitted.connect(func(_t: String) -> void: submit_name())
	vb.add_child(name_in)
	name_msg_lbl = para("", Color("#d64541"), 13)
	vb.add_child(name_msg_lbl)
	vb.add_child(row([btn("Start", false, submit_name), btn("Back", true, func() -> void: game.show_files())]))
	# pause
	vb = panel_box("pause")
	vb.add_child(para("PAUSED", Color("#cccccc"), 16))
	pause_stats_lbl = para("")
	vb.add_child(pause_stats_lbl)
	pbtn.resume = btn("Resume", false, func() -> void: game.on_pause_button("resume"))
	pbtn.sound = btn("Sound: on", true, func() -> void: game.on_pause_button("sound"))
	pbtn.sens = btn("Camera speed: normal", true, func() -> void: game.on_pause_button("sens"))
	pbtn.inv = btn("Invert camera: off", true, func() -> void: game.on_pause_button("inv"))
	pbtn.gfx = btn("Graphics: auto", true, func() -> void: game.on_pause_button("gfx"))
	pbtn.safe = btn("Safe graphics: off", true, func() -> void: game.on_pause_button("safe"))
	pbtn.help = btn("Controls", true, _help_from_pause)
	pbtn.quit = btn("Save & quit", true, func() -> void: game.on_pause_button("quit"))
	vb.add_child(row([pbtn.resume, pbtn.sound]))
	vb.add_child(row([pbtn.sens, pbtn.inv]))
	vb.add_child(row([pbtn.gfx, pbtn.safe]))
	vb.add_child(row([pbtn.help, pbtn.quit]))
	# help
	vb = panel_box("help")
	vb.add_child(para("CONTROLS", Color("#cccccc"), 16))
	var help := Label.new()
	help.text = "• Phone: left thumb anywhere on the left side to move, drag on the right side to look, A and B buttons, START and SELECT at the top.\n• A: talk, read, open. Hold A while walking to run.\n• B: sword. Hold B, then let go: spin attack.\n• START: pause.   SELECT: map.\n• Keyboard: WASD or arrows walk, mouse or Q/E turn the camera, J/Z = A, K/X/Space = B, Enter/Esc = START, Tab/M = SELECT.\n• Controllers work too.\n• The statue only moves when you're not looking at it. Keep it on screen."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_color", Color("#bbbbbb"))
	help.custom_minimum_size = Vector2(200, 0)
	vb.add_child(help)
	vb.add_child(row([btn("OK", false, func() -> void: show_panel(help_back))]))
	vb.add_child(para("Engine: Godot Engine, MIT license, (c) the Godot Engine contributors.", Color("#555555"), 10))
	# end
	vb = panel_box("end")
	var t := Label.new()
	t.text = "SECONDHAND"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", Color("#eeeeee"))
	t.add_theme_color_override("font_shadow_color", Color("#d64541"))
	t.add_theme_constant_override("shadow_offset_x", -2)
	t.add_theme_constant_override("shadow_offset_y", 0)
	vb.add_child(t)
	vb.add_child(para("THANK YOU FOR PLAYING, WREN.", Color("#cccccc"), 16))
	vb.add_child(para("Wren went home.\nYou're the one under the dock now."))
	end_stats_lbl = para("")
	vb.add_child(end_stats_lbl)
	vb.add_child(row([btn("Back to the files", false, func() -> void: game.show_files())]))
	vb.add_child(para("A game by Buggy Games YT\n© 2026 Buggy Games YT. All rights reserved.", Color("#555555"), 11))
	relayout_panels()

func _help_from_files() -> void:
	help_back = "files"
	show_panel("help")

func _help_from_pause() -> void:
	help_back = "pause"
	show_panel("help")

func _upper_name(t: String) -> void:
	var u := t.to_upper()
	if u != t:
		var cp := name_in.caret_column
		name_in.text = u
		name_in.caret_column = cp

func relayout_panels() -> void:
	var s := vsize()
	var ins := safe_insets()
	for id in panels:
		var vb: VBoxContainer = panels[id].vb
		vb.custom_minimum_size.x = clampf(s.x - ins[0] - ins[2] - 32.0 - 40.0, 160.0, 400.0)
		# keep the panel inside the safe area (camera cutout / rounded corners)
		var sc: ScrollContainer = panels[id].sc
		sc.offset_left = ins[0]
		sc.offset_top = ins[1]
		sc.offset_right = -ins[2]
		sc.offset_bottom = -ins[3]
		panels[id].cc.custom_minimum_size = Vector2.ZERO

func submit_name() -> void:
	name_in.release_focus()
	game.on_name_submit(name_in.text)

func show_panel(id: String) -> void:
	relayout_panels()
	for k in panels:
		panels[k].holder.visible = k == id
	cur_panel = id
	if id == "name":
		name_in.call_deferred("grab_focus")

func hide_title() -> void:
	show_panel("")

func set_files(a: String, asub: String, b: String, bsub: String) -> void:
	slot1.text = a + "\n     " + asub
	slot2.text = b + "\n     " + bsub
	files_msg_lbl.text = ""
	confirm_box.visible = false

func files_msg(t: String) -> void:
	files_msg_lbl.text = t

func show_name() -> void:
	name_in.text = ""
	name_msg_lbl.text = ""
	show_panel("name")

func name_msg(t: String) -> void:
	name_msg_lbl.text = t

func pause_stats(t: String) -> void:
	pause_stats_lbl.text = t

func sync_pause() -> void:
	var M: Dictionary = game.META
	pbtn.sound.text = "Sound: " + ("off" if M.muted else "on")
	var s := float(M.sens)
	pbtn.sens.text = "Camera speed: " + ("slow" if s < 0.8 else ("fast" if s > 1.2 else "normal"))
	pbtn.inv.text = "Invert camera: " + ("on" if M.inv else "off")
	pbtn.gfx.text = "Graphics: " + ("battery saver" if M.get("gfx", "auto") == "low" else "auto")
	pbtn.safe.text = "Safe graphics: " + ("on" if M.get("safe", false) else "off")

func sync_safe() -> void:
	var on: bool = game.META.get("safe", false)
	if safe_files_btn:
		safe_files_btn.text = "Safe graphics: " + ("on" if on else "off")
	if pbtn.has("safe"):
		pbtn.safe.text = "Safe graphics: " + ("on" if on else "off")

func end_stats(t: String) -> void:
	end_stats_lbl.text = t

# ---------------------------------------------------------------- drawing helpers (inner controls)
class TouchPad extends Control:
	var ui
	func _draw() -> void:
		var s := size
		var ins: Array = ui.safe_insets()
		var hint_c := Vector2(maxf(40.0, ins[0]) + 55.0, s.y - maxf(40.0, ins[3]) - 55.0)
		if ui.stick_id < 0:
			draw_arc(hint_c, 55.0, 0, TAU, 48, Color(0.78, 0.78, 0.78, 0.22), 2.0)
		else:
			draw_circle(ui.stick_origin, 60.0, Color(0.27, 0.27, 0.29, 0.3))
			draw_arc(ui.stick_origin, 60.0, 0, TAU, 48, Color(0.78, 0.78, 0.78, 0.35), 2.0)
			draw_circle(ui.stick_origin + ui.stick_knob, 27.0, Color(0.82, 0.82, 0.84, 0.55))
		var g: Dictionary = ui.btn_geom()
		var f: Font = ui.font
		for k in ["A", "B"]:
			var c: Vector2 = g[k][0]
			var on: bool = ui.tbtn[k]
			draw_circle(c, 37.0, Color(0.9, 0.27, 0.31, 0.85) if on else Color(0.59, 0.12, 0.16, 0.5))
			draw_arc(c, 37.0, 0, TAU, 48, Color(0.78, 0.78, 0.78, 0.4), 2.0)
			draw_string(f, c + Vector2(-8, 8), k, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1))
		for k in ["select", "start"]:
			var r: Rect2 = g[k]
			var on: bool = ui.tbtn[k]
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.78, 0.78, 0.78, 0.5) if on else Color(0.24, 0.24, 0.25, 0.7)
			sb.border_color = Color(0.78, 0.78, 0.78, 0.3)
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(12)
			draw_style_box(sb, r)
			var txt: String = k.to_upper()
			var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string(f, Vector2(r.position.x + (r.size.x - tw) / 2.0, r.position.y + 19.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0) if on else Color(0.73, 0.73, 0.73))

class CartArt extends Control:
	var ui
	func _draw() -> void:
		var w := 210.0
		var h := 190.0
		var o := Vector2((size.x - w) / 2.0, 0)
		draw_rect(Rect2(o + Vector2(22, h - 2), Vector2(w - 44, 12)), Color("#4d4d52"))
		var body := StyleBoxFlat.new()
		body.bg_color = Color("#7f7f85")
		body.set_corner_radius_all(6)
		body.corner_radius_bottom_left = 3
		body.corner_radius_bottom_right = 3
		body.shadow_color = Color(0, 0, 0, 0.6)
		body.shadow_size = 14
		body.shadow_offset = Vector2(0, 10)
		draw_style_box(body, Rect2(o, Vector2(w, h)))
		var x := 0.0
		while x < w:
			draw_rect(Rect2(o + Vector2(x, 0), Vector2(minf(6.0, w - x), 22)), Color("#7a7a80"))
			if x + 6.0 < w:
				draw_rect(Rect2(o + Vector2(x + 6.0, 0), Vector2(minf(3.0, w - x - 6.0), 22)), Color("#66666b"))
			x += 9.0
		draw_set_transform(o + Vector2(w / 2.0, 34 + (h - 56) / 2.0), deg_to_rad(-1.2))
		var lw := w - 40.0
		var lh := h - 56.0
		draw_rect(Rect2(Vector2(-lw / 2.0, -lh / 2.0), Vector2(lw, lh)), Color("#efe6cf"))
		draw_rect(Rect2(Vector2(-22, -lh / 2.0 - 6.0), Vector2(44, 14)), Color(1, 1, 0.9, 0.55))
		var f: Font = ui.font
		draw_set_transform(o + Vector2(w / 2.0, 34 + (h - 56) / 2.0), deg_to_rad(-5.2))
		var t := "SECONDHAND 3D"
		var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		draw_string(f, Vector2(-tw / 2.0, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("#1a1a1a"))
		draw_string(f, Vector2(-tw / 2.0 + 1.0, 1.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("#1a1a1a"))
		draw_set_transform(o + Vector2(w / 2.0, 34 + (h - 56) / 2.0), deg_to_rad(-1.2))
		var s2 := "don't play this"
		var sw := f.get_string_size(s2, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(f, Vector2(-sw / 2.0, 22), s2, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#8a7a5a"))
		draw_set_transform(o + Vector2(w / 2.0 + lw / 2.0 - 4.0, 34 + lh - 22.0), deg_to_rad(14))
		draw_circle(Vector2.ZERO, 15.0, Color("#ffd23f"))
		draw_string(f, Vector2(-9, 5), "$1", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#333333"))
		draw_set_transform(Vector2.ZERO, 0)

class MapView extends Control:
	var ui
	func arrow(c: Vector2, a: float, col: Color, k: float) -> void:
		var pts := PackedVector2Array([Vector2(0, -7), Vector2(5, 5), Vector2(-5, 5)])
		var rot := -a + PI
		var out := PackedVector2Array()
		for p in pts:
			out.append(c + p.rotated(rot) * k)
		draw_colored_polygon(out, col)
	func _draw() -> void:
		var g = ui.game
		var sz := size.x
		var k := sz / 256.0
		draw_rect(Rect2(Vector2.ZERO, size), Color("#0b0b0d"))
		var f: Font = ui.font
		var A = g.area
		if A == null:
			return
		if A.map is String and A.map == "village":
			var X := func(x: float) -> float: return (x + 64.0) * 2.0 * k
			var Z := func(z: float) -> float: return (z + 64.0) * 2.0 * k
			draw_rect(Rect2(0, 0, sz, sz), Color("#1d3320"))
			for i in 90:
				var a := i * 2.4
				var r := 70.0 + float((i * 37) % 50)
				var x := cos(a) * r
				var z := sin(a) * r * 0.8 - 10.0
				if z < 17.0:
					draw_rect(Rect2(X.call(x) - 3 * k, Z.call(z) - 3 * k, 6 * k, 6 * k), Color("#12301a"))
			draw_rect(Rect2(0, Z.call(24), sz, sz - Z.call(24)), Color("#101828") if g.C() >= 3 else Color("#24506e"))
			draw_rect(Rect2(0, Z.call(19), sz, Z.call(24) - Z.call(19)), Color("#c8b48a"))
			draw_line(Vector2(X.call(0), Z.call(-22)), Vector2(X.call(0), Z.call(21)), Color("#a8926c"), 4 * k)
			draw_line(Vector2(X.call(-8), Z.call(-8)), Vector2(X.call(-46), Z.call(-46)), Color("#a8926c"), 4 * k)
			draw_rect(Rect2(X.call(-1.25), Z.call(21), 5 * k, Z.call(42) - Z.call(21)), Color("#7a5a38"))
			draw_rect(Rect2(X.call(0) - 3 * k, Z.call(39.6) - 3 * k, 6 * k, 6 * k), Color("#c9a24a"))
			for h in [[-13, -11, 6, 5], [13, -11, 6, 5], [-15, 9, 5, 5], [15, 9, 5, 5], [0, -24, 7, 5], [-26, -12, 5, 5], [26, -10, 5, 5]]:
				draw_rect(Rect2(X.call(h[0] - h[2] / 2.0), Z.call(h[1] - h[3] / 2.0), h[2] * 2 * k, h[3] * 2 * k), Color("#8a7a6a"))
			draw_rect(Rect2(X.call(0) - 2 * k, Z.call(-3) - 2 * k, 4 * k, 4 * k), Color("#aaaaaa"))
			draw_circle(Vector2(X.call(-48), Z.call(-48)), 6 * k, Color("#3a3028"))
			var fs := int(9 * k)
			_ctext(f, "HOLLOW", Vector2(X.call(-48), Z.call(-48) + 16 * k), fs, Color("#dddddd"))
			_ctext(f, "DOCK", Vector2(X.call(0) + 18 * k, Z.call(32)), fs, Color("#dddddd"))
			if g.C() >= 2 and g.statue.active:
				_ctext(f, "W", Vector2(X.call(g.statue.x), Z.call(g.statue.z) + 3 * k), fs, Color("#c01818"))
			arrow(Vector2(X.call(g.P.x), Z.call(g.P.z)), g.P.face, Color("#ffe066"), k)
		elif A.map is String and A.map == "hollow":
			var seen: Dictionary = g.S.get("seen", {})
			var X := func(gx: float) -> float: return (80.0 + gx * 60.0) * k
			var Y := func(gy: float) -> float: return (200.0 + gy * 50.0) * k
			for id in A.rooms:
				if not seen.has(id):
					continue
				var r: Array = A.rooms[id]
				var rc := Rect2(X.call(r[0]) - 26 * k, Y.call(r[1]) - 21 * k, 52 * k, 42 * k)
				draw_rect(rc, Color("#4a6a4a") if id == A.curRoom else Color("#2a3a2a"))
				draw_rect(rc, Color("#6a8a6a"), false, 2 * k)
				if id == "rb":
					_ctext(f, "BOSS", Vector2(X.call(r[0]), Y.call(r[1]) + 4 * k), int(12 * k), Color("#666666") if g.taken("bossDead") else Color("#c01818"))
			for d in A.doors:
				if not seen.has(g.room_at(d.x + 1, d.z + 1)) and not seen.has(g.room_at(d.x - 1, d.z - 1)):
					continue
				var col := Color("#9a9a6a") if d.open else (Color("#e8c23a") if d.type == "locked" else Color("#888888"))
				draw_rect(Rect2(X.call(d.x / 18.0) - 4 * k, Y.call(d.z / 18.0) - 4 * k, 8 * k, 8 * k), col)
			arrow(Vector2(X.call(g.P.x / 18.0), Y.call(g.P.z / 18.0)), g.P.face, Color("#ffe066"), k)
			draw_string(f, Vector2(8 * k, 16 * k), "KEYS " + str(int(g.S.keys)), HORIZONTAL_ALIGNMENT_LEFT, -1, int(10 * k), Color("#dddddd"))
		else:
			var n := 32
			var cs := sz / n
			for yy in n:
				for xx in n:
					var v := randf() * 60.0 / 255.0
					draw_rect(Rect2(xx * cs, yy * cs, cs + 1, cs + 1), Color(v, v, v))
			_ctext(f, "NO MAP", Vector2(sz / 2.0, 120 * k), int(16 * k), Color("#9fc6e8"))
			_ctext(f, g.fmt("KEEP GOING, {N}"), Vector2(sz / 2.0, 144 * k), int(16 * k), Color("#9fc6e8"))
		draw_rect(Rect2(Vector2.ZERO, size), Color("#555555"), false, 2.0)
	func _ctext(f: Font, t: String, p: Vector2, fs: int, col: Color) -> void:
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, p - Vector2(w / 2.0, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
