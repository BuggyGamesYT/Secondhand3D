# Secondhand 3D (c) 2026 Buggy Games YT. All rights reserved.
# Sound: pre-rendered synth effects and songs (rendered from the game's own synth definitions).
class_name Sfx
extends Node

const GAPS := {"blip": 0.03, "menu": 0.05, "swing": 0.04, "charge": 0.3, "chargeReady": 0.2, "spin": 0.15, "hit": 0.03, "clank": 0.06, "kill": 0.03,
	"bossHit": 0.05, "roar": 0.8, "hurt": 0.1, "chest": 0.4, "grind": 0.2, "push": 0.15, "gate": 0.3, "sting": 0.3, "static": 0.05, "door": 0.2, "lock": 0.4,
	"stairs": 0.2, "step": 0.08, "skitter": 0.07, "drip": 0.3, "lowhp": 0.3, "warp": 0.5, "tv": 1.0}
const VARIANTS := {"blip": 4, "swing": 2, "grind": 2, "drip": 3, "skitter": 3}
const SONG_BENDS := {"title": [0.0, 1.4], "village": [0.0, 0.8, 1.8], "hollow": [0.0, 0.45, 0.9, 1.35], "boss": [0.0], "under": [1.6, 2.7], "mem": [1.0], "void": [0.6, 2.6]}

var streams := {}
var pool: Array[AudioStreamPlayer] = []
var pool_i := 0
var last_at := {}
var mus_a: AudioStreamPlayer
var mus_b: AudioStreamPlayer
var cur_song := ""
var cur_key := ""
var muted := false
var amb := {}
var amb_target := {"water": 0.0, "wind": 0.0, "hum": 0.0}
var amb_drips := 0.0
var next_drip := 0.0
var clock := 0.0

func _ready() -> void:
	var idx := AudioServer.get_bus_index("Master")
	var comp := AudioEffectCompressor.new()
	comp.threshold = -16.0
	comp.ratio = 4.0
	comp.attack_us = 4000.0
	comp.release_ms = 200.0
	AudioServer.add_bus_effect(idx, comp)
	for i in 14:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)
	mus_a = AudioStreamPlayer.new()
	mus_b = AudioStreamPlayer.new()
	add_child(mus_a)
	add_child(mus_b)
	for n in ["water", "wind", "hum"]:
		var p := AudioStreamPlayer.new()
		var st: AudioStreamOggVorbis = load("res://audio/amb_%s.ogg" % n)
		st.loop = true
		p.stream = st
		p.volume_db = -80.0
		add_child(p)
		amb[n] = p

func _stream(n: String) -> AudioStream:
	if not streams.has(n):
		streams[n] = load("res://audio/%s.ogg" % n)
	return streams[n]

func play(name: String, arg = null, vol := 1.0) -> void:
	if muted:
		return
	var gap: float = GAPS.get(name, 0.0)
	if gap > 0.0:
		if last_at.has(name) and clock - last_at[name] < gap:
			return
		last_at[name] = clock
	var file := "sfx_" + name
	if name == "static":
		var d: float = arg if arg != null else 0.5
		var best := 0.12
		for c in [0.12, 0.3, 0.6, 2.4]:
			if absf(c - d) < absf(best - d):
				best = c
		file = "sfx_static_%s" % str(best)
	elif name == "step":
		file = "sfx_step_%s_%d" % [arg, randi() % 3]
	elif name == "bell":
		file = "sfx_bell_rev" if arg else "sfx_bell"
	elif VARIANTS.has(name):
		file = "sfx_%s_%d" % [name, randi() % VARIANTS[name]]
	if name == "skitter" or name == "drip":
		vol *= arg if arg != null else 1.0
	elif name == "step":
		vol *= 0.7
	var p := pool[pool_i]
	pool_i = (pool_i + 1) % pool.size()
	p.stream = _stream(file)
	p.volume_db = linear_to_db(maxf(vol, 0.0001))
	p.play()

func set_song(name: String, bend: float) -> void:
	if name == "":
		stop_music()
		return
	var bends: Array = SONG_BENDS.get(name, [0.0])
	var best: float = bends[0]
	for b in bends:
		if absf(b - bend) < absf(best - bend):
			best = b
	var key := "mus_%s_%s" % [name, str(int(best)) if best == floorf(best) else str(best)]
	if key == cur_key:
		return
	var frac := 0.0
	if cur_song == name and mus_a.playing and mus_a.stream:
		frac = mus_a.get_playback_position() / maxf(1.0, mus_a.stream.get_length())
	cur_song = name
	cur_key = key
	var st: AudioStreamOggVorbis = _stream(key)
	st.loop = true
	var tmp := mus_b
	mus_b = mus_a
	mus_a = tmp
	mus_a.stream = st
	mus_a.volume_db = -60.0
	mus_a.play(frac * st.get_length())
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mus_a, "volume_db", 0.0, 0.8)
	if mus_b.playing:
		tw.tween_property(mus_b, "volume_db", -60.0, 1.0)
		tw.chain().tween_callback(mus_b.stop)

func stop_music() -> void:
	cur_song = ""
	cur_key = ""
	for p in [mus_a, mus_b]:
		if p.playing:
			var tw := create_tween()
			tw.tween_property(p, "volume_db", -60.0, 1.0)
			tw.tween_callback(p.stop)

func ambient(water: float, wind: float, hum: float, drips := 0.0) -> void:
	amb_target.water = water
	amb_target.wind = wind
	amb_target.hum = hum
	amb_drips = drips

func ambient_off() -> void:
	ambient(0.0, 0.0, 0.0, 0.0)

func set_mute(m: bool) -> void:
	muted = m
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), m)

func _process(dt: float) -> void:
	clock += dt
	for n in amb:
		var p: AudioStreamPlayer = amb[n]
		var v: float = amb_target[n]
		var cur := db_to_linear(p.volume_db) if p.playing else 0.0
		var nv := lerpf(cur, v, minf(1.0, dt * 2.0))
		if nv > 0.002:
			if not p.playing:
				p.play(randf() * 5.0)
			p.volume_db = linear_to_db(nv)
		elif p.playing and v <= 0.0:
			p.stop()
	if amb_drips > 0.0 and clock > next_drip:
		next_drip = clock + randf_range(0.8, 3.2) / amb_drips
		play("drip", randf_range(0.4, 1.0))
