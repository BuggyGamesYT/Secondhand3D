# Secondhand 3D (c) 2026 Buggy Games YT. All rights reserved.
# Diagnostics: a small on-screen overlay (FPS, graphics info, recent errors) and a log file in user://.
# Toggle: hold SELECT, tap with three fingers, or press F3.
extends Control

const LOG_PATH := "user://diag.log"
const PREV_PATH := "user://diag_prev.log"

# ------------------------------------------------------------ logger (called from any thread)
class ErrLog extends Logger:
	var mutex := Mutex.new()
	var lines: Array[String] = []
	var errors: Array[String] = []
	var err_count := 0
	var file: FileAccess
	var t0 := Time.get_ticks_msec()

	func open() -> void:
		if FileAccess.file_exists(LOG_PATH):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(LOG_PATH), ProjectSettings.globalize_path(PREV_PATH))
		file = FileAccess.open(LOG_PATH, FileAccess.WRITE)

	func add(s: String, is_err := false) -> void:
		var st := "[%7.2f] %s" % [(Time.get_ticks_msec() - t0) / 1000.0, s]
		mutex.lock()
		lines.append(st)
		if lines.size() > 400:
			lines = lines.slice(lines.size() - 300)
		if is_err:
			err_count += 1
			errors.append(st)
			if errors.size() > 12:
				errors = errors.slice(errors.size() - 12)
		if file and (file.get_length() < 400000 or is_err):
			file.store_line(st)
			file.flush()
		mutex.unlock()

	func _log_message(message: String, error: bool) -> void:
		var m := message.strip_edges()
		if m != "":
			add(m, error)

	func _log_error(function: String, f: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		var kind := "WARNING" if error_type == ERROR_TYPE_WARNING else ("SHADER ERROR" if error_type == ERROR_TYPE_SHADER else "ERROR")
		var msg := rationale if rationale != "" else code
		add("%s: %s (%s:%d %s)" % [kind, msg, f.get_file(), line, function], error_type != ERROR_TYPE_WARNING)

	func snapshot_errors() -> Array[String]:
		mutex.lock()
		var e := errors.duplicate()
		mutex.unlock()
		return e

	func text() -> String:
		mutex.lock()
		var s := "\n".join(lines)
		mutex.unlock()
		return s

static var elog: ErrLog

static func start() -> void:
	if elog != null:
		return
	elog = ErrLog.new()
	elog.open()
	OS.add_logger(elog)
	elog.add("Secondhand 3D %s | %s | %s %s" % [ProjectSettings.get_setting("application/config/version", ""), OS.get_name(), OS.get_model_name(), OS.get_version()])

static func note(s: String) -> void:
	if elog:
		elog.add(s)

static func prev_log() -> String:
	if not FileAccess.file_exists(PREV_PATH):
		return ""
	return FileAccess.get_file_as_string(PREV_PATH)

# ------------------------------------------------------------ overlay
var ui
var game
var panel: PanelContainer
var lbl: Label
var copy_btn: Button
var safe_btn: Button
var acc := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.78)
	sb.border_color = Color("#1f9e8f")
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	lbl = Label.new()
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color("#c8f0e8"))
	lbl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	lbl.custom_minimum_size = Vector2(300, 0)
	vb.add_child(lbl)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	vb.add_child(h)
	copy_btn = _b("Copy log")
	copy_btn.pressed.connect(_copy)
	h.add_child(copy_btn)
	safe_btn = _b("Safe graphics")
	safe_btn.pressed.connect(func() -> void:
		if game: game.toggle_safe()
		refresh())
	h.add_child(safe_btn)
	var close := _b("Close")
	close.pressed.connect(func() -> void: visible = false)
	h.add_child(close)
	visible = false

func _b(t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_size_override("font_size", 12)
	b.focus_mode = Control.FOCUS_NONE
	return b

func relayout(s: Vector2, ins: Array) -> void:
	if panel == null:
		return
	var w := minf(s.x - ins[0] - ins[2] - 16.0, 520.0)
	lbl.custom_minimum_size.x = maxf(200.0, w - 16.0)
	panel.size = Vector2(w, 0)
	panel.position = Vector2(ins[0] + 8.0, ins[1] + 8.0)

func toggle() -> void:
	visible = not visible
	if visible:
		refresh()
		note("diagnostics overlay opened")

func _copy() -> void:
	var t := "=== this run ===\n" + elog.text()
	var p := prev_log()
	if p != "":
		t += "\n\n=== previous run ===\n" + p.right(6000)
	DisplayServer.clipboard_set(t)
	copy_btn.text = "Copied!"
	get_tree().create_timer(1.5).timeout.connect(func() -> void: copy_btn.text = "Copy log")

func _process(dt: float) -> void:
	if not visible:
		return
	acc += dt
	if acc >= 0.5:
		acc = 0.0
		refresh()

func info_text() -> String:
	var rm := str(RenderingServer.get_current_rendering_method())
	var drv := str(RenderingServer.get_current_rendering_driver_name())
	var t := "FPS %d   draws %d   %s/%s\n" % [Engine.get_frames_per_second(), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), rm, drv]
	t += "GPU: %s / %s\n%s\n" % [RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version()]
	var w := get_window()
	t += "window %s  ui %s  x%.2f  safe %s\n" % [str(w.size), str(w.content_scale_size), ui.unit if ui else 1.0, str(DisplayServer.get_display_safe_area())]
	if game:
		t += game.quality_text() + "\n"
	t += "vmem %.0f MB   static %.0f MB\n" % [Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1e6, OS.get_static_memory_usage() / 1e6]
	t += "log: %s\n" % ProjectSettings.globalize_path(LOG_PATH)
	var errs := elog.snapshot_errors() if elog else []
	t += "errors: %d%s" % [elog.err_count if elog else 0, "" if errs.is_empty() else "\n" + "\n".join(errs.slice(maxi(0, errs.size() - 6)))]
	return t

func refresh() -> void:
	lbl.text = info_text()
	if game:
		safe_btn.text = "Safe graphics: " + ("on" if game.META.get("safe", false) else "off")
