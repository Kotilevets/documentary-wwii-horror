extends Node
## Sound bank: id -> recordings from assets/data/sound_bank.json.
## While a recording is not in the project, a synthesized placeholder is used
## (bark, step, breath, knock, clock, typewriter, kettle, engine...); ids
## without a placeholder (German speech) stay silent and are listed by
## missing_ids(). Placeholders are synthesized by synth() and baked into
## assets/audio/placeholder/<kind>.res (tools/bake_sounds.gd), so the game
## only loads them; a kind with no baked file is synthesized on first use.
## "loop": true in the bank - the sound repeats until its player is freed
## (wall clock, kettle); the caller owns such a player.
## Recordings come from docs/ASSETS_AND_REFS.md (Freesound, Sonniss) after
## the license is recorded there.
## Buses: everything outside the boy plays on WORLD_BUS, which a hiding
## place muffles (set_muffle); his own body ("body": true in the bank -
## breath, steps, ringing ears) and the heartbeat stay on Master, clear.
## A world sound behind a wall or a closed door from the boy goes through
## OCCLUDED_BUS (low-passed, quieter) into World (docs/ARCHITECTURE.md,
## "Звук сквозь стены"); checked OCCLUSION_INTERVAL times a second.

const BANK_PATH := "res://assets/data/sound_bank.json"
const PLACEHOLDER_DIR := "res://assets/audio/placeholder/"
const MIX_RATE := 22050
const WORLD_BUS := "World"
const BODY_BUS := "Master"
## Low-pass cutoff that means "not muffled".
const OPEN_AIR := 20000.0
const OCCLUDED_BUS := "Occluded"
## Through a log wall or a closed door: the low part only, and quieter.
const OCCLUDED_HZ := 700.0
const OCCLUDED_DB := -7.0
## What stops sound: the walls of buildings and shut doors; one room has no
## walls in it - the same rule as for enemies' ears (src/audio/sound_walls.gd).
## Rays look at the world (layer 1) and doors (layer 5); not people, the boy,
## pickups or wire (layer 6).
const SoundWalls := preload("res://src/audio/sound_walls.gd")
const OCCLUSION_MASK := SoundWalls.MASK
const OCCLUSION_INTERVAL := 0.1
## Height of the ear in front of a hiding place (a boy's head).
const HIDDEN_EAR := 1.35

## Every sound that started: tests and debug listen to it.
signal played(id: String, player: AudioStreamPlayer3D)

## Placeholder kinds whose synthesized sound repeats seamlessly.
const LOOP_KINDS := ["clock", "kettle", "wind", "ragged"]

var _bank: Dictionary = {}
var _placeholders: Dictionary = {}  # kind -> AudioStreamWAV, filled lazily
var _missing: Dictionary = {}       # id -> true
var _rng := RandomNumberGenerator.new()
## Current muffling of the World bus (tests, debug).
var muffle_hz := OPEN_AIR
var muffle_db := 0.0
var _muffle_tween: Tween = null
## World sounds playing now, checked for walls between them and the boy.
var _world_players: Array[AudioStreamPlayer3D] = []
var _occlusion_wait := 0.0


func _ready() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(BANK_PATH))
	if typeof(data) == TYPE_DICTIONARY:
		_bank = data
	else:
		push_error("Sfx: cannot read %s" % BANK_PATH)
	_ensure_world_bus()


func _ensure_world_bus() -> void:
	if AudioServer.get_bus_index(WORLD_BUS) < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, WORLD_BUS)
		AudioServer.set_bus_send(i, "Master")
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = OPEN_AIR
		AudioServer.add_bus_effect(i, lp)
		AudioServer.set_bus_effect_enabled(i, 0, false)
	# After World: a bus may only send to one before it.
	if AudioServer.get_bus_index(OCCLUDED_BUS) < 0:
		AudioServer.add_bus()
		var j := AudioServer.bus_count - 1
		AudioServer.set_bus_name(j, OCCLUDED_BUS)
		AudioServer.set_bus_send(j, WORLD_BUS)
		var wall := AudioEffectLowPassFilter.new()
		wall.cutoff_hz = OCCLUDED_HZ
		AudioServer.add_bus_effect(j, wall)
		AudioServer.set_bus_volume_db(j, OCCLUDED_DB)


## Every OCCLUSION_INTERVAL s: each world sound playing goes through the
## wall bus or not. Physics frames: the rays need the physics space.
func _physics_process(delta: float) -> void:
	_occlusion_wait -= delta
	if _occlusion_wait > 0.0:
		return
	_occlusion_wait = OCCLUSION_INTERVAL
	update_occlusion()


func update_occlusion() -> void:
	var alive: Array[AudioStreamPlayer3D] = []
	for p in _world_players:
		if is_instance_valid(p) and p.is_inside_tree():
			alive.append(p)
			p.bus = OCCLUDED_BUS if is_occluded(p.global_position) else WORLD_BUS
	_world_players = alive


## A wall of a building or a shut door between the boy's ears and `pos`
## (SoundWalls.walled: not within one room; a hedge, a tree, a haystack is no
## wall). While he hides the ear is the room in front of the hiding place
## (HideSpot.stand_point): the camera sits under the floor or behind the
## stove. The hiding place's own muffle (set_muffle) comes on top, as a wall
## would.
func is_occluded(pos: Vector3) -> bool:
	var ear := _listener()
	if ear == null or not ear.is_inside_tree():
		return false
	var from := ear.global_position
	var feet := from - Vector3.UP * HIDDEN_EAR  # a camera with no boy: a person standing
	var boy := _boy()
	if boy != null and is_instance_valid(boy) and boy.is_inside_tree():
		feet = boy.global_position
		if boy.get("is_hidden") == true:
			var spot = boy.get("current_hide_spot")  # untyped: no HideSpot in the bake tool
			if spot != null and spot.has_method("stand_point"):
				feet = spot.stand_point()
				from = feet + Vector3.UP * HIDDEN_EAR
	if from.distance_to(pos + Vector3.UP * 0.3) < 0.6:
		return false
	return SoundWalls.walled(ear.get_world_3d().direct_space_state, get_tree(), feet, from, pos)


## The boy (Stealth.player). Looked up by path: tools/bake_sounds.gd loads
## this script without the autoloads, where the name Stealth does not exist.
func _boy() -> Node3D:
	var stealth := get_node_or_null("/root/Stealth")
	return stealth.get("player") as Node3D if stealth != null else null


## The boy's camera, else the current camera.
func _listener() -> Node3D:
	var boy := _boy()
	if boy != null and is_instance_valid(boy):
		var cam := boy.get("camera") as Camera3D
		if cam != null:
			return cam
	var vp := get_viewport()
	return vp.get_camera_3d() if vp != null else null


## How the world sounds from a hiding place: low-pass cutoff (Hz) and volume
## (dB) of the World bus, reached in `time` s. OPEN_AIR, 0 - out in the open.
## A cellar under boards and earth keeps only the low thuds of boots.
func set_muffle(cutoff_hz: float, volume_db: float, time: float = 0.35) -> void:
	if _muffle_tween != null:
		_muffle_tween.kill()
		_muffle_tween = null
	if time <= 0.0:
		_apply_muffle(cutoff_hz, volume_db)
		return
	_muffle_tween = create_tween()
	_muffle_tween.tween_method(_muffle_step.bind(muffle_hz, cutoff_hz, muffle_db, volume_db),
			0.0, 1.0, time)


func is_muffled() -> bool:
	return muffle_hz < OPEN_AIR - 1.0


func _muffle_step(k: float, from_hz: float, to_hz: float, from_db: float, to_db: float) -> void:
	# The cutoff moves evenly in octaves, not in hertz.
	_apply_muffle(exp(lerpf(log(from_hz), log(to_hz), k)), lerpf(from_db, to_db, k))


func _apply_muffle(hz: float, db: float) -> void:
	muffle_hz = hz
	muffle_db = db
	var i := AudioServer.get_bus_index(WORLD_BUS)
	if i < 0:
		return
	(AudioServer.get_bus_effect(i, 0) as AudioEffectLowPassFilter).cutoff_hz = hz
	AudioServer.set_bus_effect_enabled(i, 0, is_muffled())
	AudioServer.set_bus_volume_db(i, db)


## Bus of a sound: the boy's own body on Master, the rest on World.
func bus_of(id: String) -> String:
	return BODY_BUS if bool((_bank.get(id, {}) as Dictionary).get("body", false)) else WORLD_BUS


## World, or the wall bus into it: a sound of the world, not of his body.
func is_world_bus(bus: StringName) -> bool:
	return bus == WORLD_BUS or bus == OCCLUDED_BUS


func volume_of(id: String) -> float:
	return float((_bank.get(id, {}) as Dictionary).get("volume_db", 0.0))


## Plays a sound at a world position. Returns the player or null if silent.
## `parent`: the node the player lives under (default - the current scene);
## a looping sound stops when its player or that node is freed.
func play_at(id: String, position: Vector3, volume_scale: float = 1.0,
		parent: Node = null) -> AudioStreamPlayer3D:
	var stream := stream_for(id)
	if stream == null:
		return null
	var entry: Dictionary = _bank.get(id, {})
	var p := AudioStreamPlayer3D.new()
	p.name = "Sfx_" + id
	p.stream = stream
	p.volume_db = float(entry.get("volume_db", 0.0)) + linear_to_db(maxf(volume_scale, 0.01))
	p.max_distance = float(entry.get("max_distance", 40.0))
	p.pitch_scale = _rng.randf_range(0.93, 1.07)
	p.bus = bus_of(id)
	if parent == null:
		parent = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(p)
	p.global_position = position
	# "occlude": false in the bank - a sound in his head (the memory's room).
	if p.bus == WORLD_BUS and bool(entry.get("occlude", true)):
		_world_players.append(p)
		if is_occluded(position):
			p.bus = OCCLUDED_BUS
	if not is_loop(id):
		p.finished.connect(p.queue_free)
	p.play()
	played.emit(id, p)
	return p


func is_loop(id: String) -> bool:
	return bool((_bank.get(id, {}) as Dictionary).get("loop", false))


## Recording if present, else placeholder, else null (and remembered as missing).
func stream_for(id: String) -> AudioStream:
	var entry: Dictionary = _bank.get(id, {})
	var files: Array = []
	for f in entry.get("files", []):
		if ResourceLoader.exists(f):
			files.append(f)
	if not files.is_empty():
		var rec := load(files[_rng.randi() % files.size()]) as AudioStream
		if entry.get("loop", false) and "loop" in rec:
			rec.set("loop", true)  # Ogg / MP3 recordings
		return rec
	_missing[id] = true
	var kind: String = entry.get("placeholder", "")
	if kind == "":
		return null
	if not _placeholders.has(kind):
		_placeholders[kind] = placeholder(kind)
	return _placeholders[kind]


## The baked placeholder of a kind, or a freshly synthesized one.
static func placeholder(kind: String) -> AudioStreamWAV:
	var path := PLACEHOLDER_DIR + kind + ".res"
	if ResourceLoader.exists(path):
		return load(path) as AudioStreamWAV
	return synth(kind)


func missing_ids() -> Array:
	return _missing.keys()


func bank_ids() -> Array:
	return _bank.keys()


# --- placeholders ----------------------------------------------------------------

static func synth(kind: String) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	match kind:
		"bark":
			# Two harsh bursts: noisy formant around 450 Hz.
			for burst in 2:
				var n := int(0.16 * MIX_RATE)
				for i in n:
					var t := float(i) / MIX_RATE
					var env := sin(PI * t / 0.16) * exp(-t * 6.0)
					var tone := sin(TAU * (520.0 - 600.0 * t) * t)
					samples.append((0.6 * tone + 0.5 * rng.randf_range(-1, 1)) * env)
				for i in int(0.09 * MIX_RATE):
					samples.append(0.0)
		"step":
			for i in int(0.09 * MIX_RATE):
				var t := float(i) / MIX_RATE
				samples.append((rng.randf_range(-1, 1) * 0.5 + sin(TAU * 70.0 * t)) * exp(-t * 45.0) * 0.6)
		"knock":
			# Three heavy knocks on wood.
			for k in 3:
				for i in int(0.07 * MIX_RATE):
					var t := float(i) / MIX_RATE
					samples.append((sin(TAU * 95.0 * t) + rng.randf_range(-0.6, 0.6)) * exp(-t * 40.0) * 0.9)
				for i in int(0.22 * MIX_RATE):
					samples.append(0.0)
		"creak":
			for i in int(0.7 * MIX_RATE):
				var t := float(i) / MIX_RATE
				var f := 180.0 + 90.0 * sin(TAU * 1.3 * t) + 40.0 * sin(TAU * 7.0 * t)
				var saw := fmod(t * f, 1.0) * 2.0 - 1.0
				samples.append(saw * sin(PI * t / 0.7) * 0.25)
		"blast":
			# A dull boom: low thump plus a burst of noise.
			var prev := 0.0
			for i in int(1.4 * MIX_RATE):
				var t := float(i) / MIX_RATE
				prev = lerpf(prev, rng.randf_range(-1, 1), 0.08)
				var thump := sin(TAU * (55.0 - 20.0 * t) * t) * exp(-t * 3.0)
				samples.append((thump * 0.9 + prev * 2.2 * exp(-t * 2.2)) * 0.8)
		"ring":
			# Ringing in the ears after the blast.
			for i in int(3.0 * MIX_RATE):
				var t := float(i) / MIX_RATE
				samples.append(sin(TAU * 3400.0 * t) * 0.18 * exp(-t * 0.8) * minf(t * 8.0, 1.0))
		"crack", "shatter":
			# Dry cracks: short bright noise ticks; "shatter" adds a falling
			# clatter of small pieces.
			var n := 1 if kind == "crack" else 14
			for k in n:
				var dur := rng.randf_range(0.03, 0.07)
				var prev := 0.0
				for i in int(dur * MIX_RATE):
					var t := float(i) / MIX_RATE
					var x := rng.randf_range(-1, 1)
					samples.append((x - prev) * exp(-t * 60.0) * (0.9 if k == 0 else 0.5))
					prev = x
				for i in int(rng.randf_range(0.02, 0.09) * MIX_RATE):
					samples.append(0.0)
		"clock":
			# Tick - tock of a wall clock, one beat a second (2 s loop).
			for beat in 2:
				var n := int(1.0 * MIX_RATE)
				var f := 2300.0 if beat == 0 else 1750.0
				var prev := 0.0
				for i in n:
					var t := float(i) / MIX_RATE
					var x := rng.randf_range(-1, 1)
					var click := (x - prev) * exp(-t * 900.0) * 0.3
					prev = x
					var ring := sin(TAU * f * t) * exp(-t * 160.0) * 0.35
					var body := sin(TAU * 420.0 * t) * exp(-t * 60.0) * 0.25
					samples.append(click + ring + body)
		"typewriter":
			# A line of keys at an uneven pace, the bell, the carriage return.
			var keys := rng.randi_range(8, 11)
			for k in keys:
				var prev := 0.0
				for i in int(0.05 * MIX_RATE):
					var t := float(i) / MIX_RATE
					var x := rng.randf_range(-1, 1)
					var strike := (x - prev) * exp(-t * 300.0) * 0.4
					prev = x
					var thud := sin(TAU * 170.0 * t) * exp(-t * 70.0) * 0.4
					samples.append(strike + thud)
				for i in int(rng.randf_range(0.05, 0.19) * MIX_RATE):
					samples.append(0.0)
			for i in int(0.6 * MIX_RATE):
				var t := float(i) / MIX_RATE
				samples.append((sin(TAU * 2050.0 * t) + 0.4 * sin(TAU * 5330.0 * t)) * exp(-t * 7.0) * 0.3)
			for k in 12:
				for i in int(0.03 * MIX_RATE):
					var t := float(i) / MIX_RATE
					samples.append(rng.randf_range(-1, 1) * exp(-t * 200.0) * 0.35)
			for i in int(0.12 * MIX_RATE):
				var t := float(i) / MIX_RATE
				samples.append((sin(TAU * 140.0 * t) + rng.randf_range(-0.5, 0.5)) * exp(-t * 40.0) * 0.7)
		"kettle":
			# Quiet simmer: soft hiss that breathes, small bubbles. The last
			# 0.3 s is cross-faded into the start, so the 3 s loop has no seam.
			var raw := PackedFloat32Array()
			var total := int(3.3 * MIX_RATE)
			var lp := 0.0
			for i in total:
				var t := float(i) / MIX_RATE
				lp = lerpf(lp, rng.randf_range(-1, 1), 0.35)
				raw.append(lp * 0.16 * (0.75 + 0.25 * sin(TAU * 0.7 * t)))
			for b in 26:
				var at := rng.randi_range(0, total - int(0.05 * MIX_RATE))
				var f := rng.randf_range(300.0, 750.0)
				for i in int(0.04 * MIX_RATE):
					var t := float(i) / MIX_RATE
					raw[at + i] += sin(TAU * (f + 4000.0 * t) * t) * exp(-t * 90.0) * 0.18
			var fade := int(0.3 * MIX_RATE)
			var n := total - fade
			for i in n:
				if i < fade:
					var w := float(i) / fade
					samples.append(raw[i] * w + raw[n + i] * (1.0 - w))
				else:
					samples.append(raw[i])
		"lid":
			# The kettle lid rattles: a few metallic ticks.
			for k in rng.randi_range(4, 6):
				for i in int(0.06 * MIX_RATE):
					var t := float(i) / MIX_RATE
					var f := rng.randf_range(2600.0, 3400.0)
					samples.append((sin(TAU * f * t) * 0.5 + rng.randf_range(-0.3, 0.3)) * exp(-t * 80.0) * 0.5)
				for i in int(rng.randf_range(0.02, 0.07) * MIX_RATE):
					samples.append(0.0)
		"shot", "burst":
			# Gunfire heard from far off: a sharp crack, a short low body and
			# an echo rolling back off the forest (two returns and a tail).
			# "burst" is a short machine-gun burst, seven shots under one echo.
			var n_shots := 1 if kind == "shot" else 7
			var gap := 0.075
			var count := int((2.2 + gap * (n_shots - 1)) * MIX_RATE)
			samples.resize(count)
			var lp := 0.0
			var prev := 0.0
			for i in count:
				var t := float(i) / MIX_RATE
				var x := rng.randf_range(-1, 1)
				lp = lerpf(lp, x, 0.04)
				var v := 0.0
				for k in n_shots:
					var tk := t - k * gap
					if tk < 0.0:
						break
					v += (x - prev) * exp(-tk * 220.0) * 0.8
					v += lp * 4.0 * exp(-tk * 22.0)
				var te := t - (n_shots - 1) * gap
				if te > 0.0:
					var env := 0.55 * exp(-pow((te - 0.28) / 0.09, 2.0)) 							+ 0.35 * exp(-pow((te - 0.7) / 0.2, 2.0)) 							+ 0.25 * exp(-te * 1.6) * minf(te * 10.0, 1.0)
					v += lp * 3.0 * env
				prev = x
				samples[i] = v
		"boot":
			# A heavy boot on earth: a low heel thud, dull grit under the sole,
			# then the sole itself.
			var g1 := 0.0
			var g2 := 0.0
			for i in int(0.24 * MIX_RATE):
				var t := float(i) / MIX_RATE
				g1 = lerpf(g1, rng.randf_range(-1, 1), 0.09)
				g2 = lerpf(g2, g1, 0.09)
				var x := sin(TAU * (82.0 - 60.0 * t) * t) * exp(-t * 26.0)
				x += g2 * 5.0 * exp(-t * 30.0)
				if t > 0.06:
					x += g2 * 3.5 * exp(-(t - 0.06) * 40.0)
				samples.append(x * 0.8)
		"boot_board":
			# A boot on floorboards: a hollow, damped knock - boards are not
			# a drum, the ring dies fast under the noise of the wood.
			var g1 := 0.0
			var g2 := 0.0
			for i in int(0.3 * MIX_RATE):
				var t := float(i) / MIX_RATE
				g1 = lerpf(g1, rng.randf_range(-1, 1), 0.15)
				g2 = lerpf(g2, g1, 0.15)
				var x := sin(TAU * 104.0 * t) * exp(-t * 24.0) * 0.8
				x += sin(TAU * 181.0 * t) * exp(-t * 34.0) * 0.4
				x += sin(TAU * 297.0 * t) * exp(-t * 46.0) * 0.2
				x += g2 * 4.0 * exp(-t * 35.0)
				if t > 0.07:
					var te := t - 0.07
					x += (sin(TAU * 112.0 * te) * 0.3 + g2 * 1.6) * exp(-te * 30.0)
				samples.append(x * 0.75)
		"board_light":
			# A boy's foot on floorboards: a lighter, higher knock than a boot,
			# the boards ringing briefly under the noise of the wood.
			var g1 := 0.0
			var g2 := 0.0
			for i in int(0.18 * MIX_RATE):
				var t := float(i) / MIX_RATE
				g1 = lerpf(g1, rng.randf_range(-1, 1), 0.2)
				g2 = lerpf(g2, g1, 0.2)
				var x := sin(TAU * 150.0 * t) * exp(-t * 34.0) * 0.6
				x += sin(TAU * 262.0 * t) * exp(-t * 48.0) * 0.3
				x += g2 * 3.0 * exp(-t * 45.0)
				samples.append(x * 0.7)
		"floorcreak":
			# A floorboard giving under weight: a low dragging creak.
			var dur := 0.45
			for i in int(dur * MIX_RATE):
				var t := float(i) / MIX_RATE
				var f := 140.0 - 50.0 * t / dur + 12.0 * sin(TAU * 5.0 * t)
				var saw := fmod(t * f, 1.0) * 2.0 - 1.0
				var grain := 0.6 + 0.4 * sin(TAU * 23.0 * t)
				samples.append(saw * grain * sin(PI * t / dur) * 0.3)
		"paw":
			# A dog's paw: a soft, dull pad; a faint tick of claws.
			var g1 := 0.0
			var g2 := 0.0
			for i in int(0.09 * MIX_RATE):
				var t := float(i) / MIX_RATE
				var n := rng.randf_range(-1, 1)
				g1 = lerpf(g1, n, 0.07)
				g2 = lerpf(g2, g1, 0.07)
				samples.append(g2 * 9.0 * exp(-t * 50.0) * 0.6 + n * exp(-t * 600.0) * 0.06)
		"sniff":
			# A big dog sniffing along a wall: four quick short draws of air
			# through the nose, then a soft snort out. Kept low, a muffled
			# snuffle more than a hiss: it has to come through a log wall
			# (the Occluded bus cuts above 700 Hz).
			var g1 := 0.0
			var g2 := 0.0
			var h := 0.0
			for i in int(0.62 * MIX_RATE):
				var t := float(i) / MIX_RATE
				var n := rng.randf_range(-1, 1)
				g1 = lerpf(g1, n, 0.1)
				g2 = lerpf(g2, g1, 0.1)
				h = lerpf(h, n, 0.4)
				var air := g2 * 5.0 + (h - g1) * 0.35
				var env := 0.0
				for k in 4:
					var ts := t - 0.03 - 0.085 * k
					if ts > 0.0 and ts < 0.06:
						env += sin(PI * ts / 0.06) * (1.0 - 0.12 * k)
				var snort := 0.0
				if t > 0.42:
					var te := t - 0.42
					snort = minf(te * 40.0, 1.0) * exp(-te * 14.0) * 0.55
				samples.append(air * (env * 1.3 + snort))
		"wind":
			# Wind over open ground: a low rumble swelling in gusts, a faint
			# howl riding on the strong ones. 10 s loop; the last 1.5 s is
			# cross-faded into the start.
			var total := int(11.5 * MIX_RATE)
			var rumble := PackedFloat32Array()
			var howl := PackedFloat32Array()
			rumble.resize(total)
			howl.resize(total)
			var lp1 := 0.0
			var lp2 := 0.0
			var y1 := 0.0
			var y2 := 0.0
			var peak_r := 0.0
			var peak_h := 0.0
			for i in total:
				var t := float(i) / MIX_RATE
				var gust := 0.55 + 0.25 * sin(TAU * t / 5.75 + 0.7) + 0.2 * sin(TAU * t / 2.3 + 2.1)
				var n := rng.randf_range(-1, 1)
				var a := 0.015 + 0.05 * gust
				lp1 = lerpf(lp1, n, a)
				lp2 = lerpf(lp2, lp1, a)
				rumble[i] = lp2 * gust
				peak_r = maxf(peak_r, absf(rumble[i]))
				# Two-pole resonator, its pitch rising with the gust.
				var w := TAU * (380.0 + 140.0 * gust) / MIX_RATE
				var r := 0.997
				var y := (1.0 - r) * n + 2.0 * r * cos(w) * y1 - r * r * y2
				y2 = y1
				y1 = y
				howl[i] = y * maxf(gust - 0.6, 0.0)
				peak_h = maxf(peak_h, absf(howl[i]))
			var raw := PackedFloat32Array()
			raw.resize(total)
			for i in total:
				raw[i] = rumble[i] / maxf(peak_r, 1e-6) * 0.6 + howl[i] / maxf(peak_h, 1e-6) * 0.12
			var fade := int(1.5 * MIX_RATE)
			var n_out := total - fade
			for i in n_out:
				if i < fade:
					var k := float(i) / fade
					samples.append(raw[i] * k + raw[n_out + i] * (1.0 - k))
				else:
					samples.append(raw[i])
		"engine":
			# A truck far off: a low uneven rumble that comes and goes, with
			# a gear change in the middle. Heavily low-passed - it is far.
			var dur := 5.5
			var phase := 0.0
			var lp := 0.0
			var lp2 := 0.0
			var amp := 1.0
			for i in int(dur * MIX_RATE):
				var t := float(i) / MIX_RATE
				var rpm := 34.0 + 6.0 * sin(TAU * 0.3 * t)
				if t > 2.6 and t < 3.0:
					rpm -= 12.0 * sin(PI * (t - 2.6) / 0.4)
				phase += TAU * rpm / MIX_RATE
				# Uneven firing: the strength wanders from stroke to stroke.
				amp = clampf(amp + rng.randf_range(-0.004, 0.004), 0.6, 1.3)
				var x := amp * (sin(phase) + 0.6 * sin(2.0 * phase + 0.4) + 0.35 * sin(3.0 * phase + 1.1))
				x += rng.randf_range(-0.8, 0.8)
				lp = lerpf(lp, x, 0.06)
				lp2 = lerpf(lp2, lp, 0.06)
				var env := minf(t / 1.6, 1.0) * minf((dur - t) / 2.2, 1.0)
				samples.append(lp2 * env * 0.4)
		"room":
			# Memory of the house before: a clock ticking softly, the stove
			# crackling, a warm low hum. No voices until they are recorded.
			var dur := 9.0
			var lp := 0.0
			var next_crackle := 0.4
			var crackle_left := 0
			for i in int(dur * MIX_RATE):
				var t := float(i) / MIX_RATE
				lp = lerpf(lp, rng.randf_range(-1, 1), 0.02)
				var x := lp * 0.5
				var beat := fmod(t, 1.0)
				x += sin(TAU * (2100.0 if int(t) % 2 == 0 else 1700.0) * beat) * exp(-beat * 170.0) * 0.12
				if t >= next_crackle:
					crackle_left = int(rng.randf_range(0.004, 0.012) * MIX_RATE)
					next_crackle = t + rng.randf_range(0.08, 0.7)
				if crackle_left > 0:
					x += rng.randf_range(-1, 1) * 0.3
					crackle_left -= 1
				var env := minf(t / 1.5, 1.0) * minf((dur - t) / 2.5, 1.0)
				samples.append(x * env)
		"grab":
			# A hand closing on a coarse collar: a sharp rustle of cloth, a
			# second tug, and the dull jolt of a body pulled up short.
			var lo := 0.0
			var lo2 := 0.0
			for i in int(0.5 * MIX_RATE):
				var t := float(i) / MIX_RATE
				var n := rng.randf_range(-1, 1)
				lo = lerpf(lo, n, 0.35)
				lo2 = lerpf(lo2, lo, 0.05)
				var cloth_env := minf(t / 0.008, 1.0) * exp(-t * 14.0)
				if t > 0.14:
					cloth_env += 0.45 * minf((t - 0.14) / 0.01, 1.0) * exp(-(t - 0.14) * 11.0)
				var x := (lo - lo2) * cloth_env * 1.6
				if t > 0.03:
					var tj := t - 0.03
					x += sin(TAU * (95.0 - 40.0 * tj) * tj) * exp(-tj * 20.0) * 0.8
				samples.append(x)
		"pant":
			# Out of breath: a quick rasping breath in through the mouth, then
			# a harder breath out with a trace of voice in it.
			var lp := 0.0
			var lp2 := 0.0
			for i in int(0.62 * MIX_RATE):
				var t := float(i) / MIX_RATE
				lp = lerpf(lp, rng.randf_range(-1, 1), 0.3)
				lp2 = lerpf(lp2, lp, 0.3)
				var env_in := sin(PI * t / 0.22) * 0.55 if t < 0.22 else 0.0
				var env_out := 0.0
				if t > 0.26:
					var k := (t - 0.26) / 0.36
					env_out = minf(k * 6.0, 1.0) * exp(-k * 3.0)
				var voice := sin(TAU * 210.0 * t + 0.4 * sin(TAU * 7.0 * t)) * 0.12 * env_out
				samples.append(lp * 1.2 * env_in + lp2 * 2.2 * env_out + voice)
		"hatch":
			# The cellar lid: its hinge drags a short low creak as it lifts,
			# then the heavy boards drop back into the floor with a dull thud.
			var g1 := 0.0
			var g2 := 0.0
			for i in int(0.85 * MIX_RATE):
				var t := float(i) / MIX_RATE
				g1 = lerpf(g1, rng.randf_range(-1, 1), 0.12)
				g2 = lerpf(g2, g1, 0.12)
				var x := 0.0
				if t < 0.38:
					var f := 120.0 - 35.0 * t / 0.38 + 9.0 * sin(TAU * 6.0 * t)
					var saw := fmod(t * f, 1.0) * 2.0 - 1.0
					x += saw * (0.55 + 0.45 * sin(TAU * 19.0 * t)) * sin(PI * t / 0.38) * 0.22
				if t > 0.5:
					var te := t - 0.5
					x += sin(TAU * (78.0 - 25.0 * te) * te) * exp(-te * 18.0) * 0.9
					x += sin(TAU * 143.0 * te) * exp(-te * 30.0) * 0.3
					x += g2 * 4.5 * exp(-te * 28.0)
				samples.append(x * 0.8)
		"hay":
			# Dry hay pushed aside: a dense crackle of stalks, in a few waves
			# as he burrows in, no tone at all.
			var lp := 0.0
			var prev := 0.0
			var dur := 0.75
			for i in int(dur * MIX_RATE):
				var t := float(i) / MIX_RATE
				var x := rng.randf_range(-1, 1)
				lp = lerpf(lp, x, 0.35)
				var hiss := lp - prev * 0.7  # thin out the lows: stalks, not wind
				prev = lp
				var waves := 0.45 + 0.55 * absf(sin(TAU * 2.6 * t + 0.8 * sin(TAU * 1.1 * t)))
				var crackle := 1.0 + (3.0 if rng.randf() < 0.012 else 0.0)
				samples.append(hiss * waves * crackle * sin(PI * t / dur) * 0.5)
		"gutgrowl":
			# A hungry stomach: a low gurgle sliding in pitch, broken into
			# bubbles, a second and a bit.
			var dur := 1.15
			var phase := 0.0
			var lp := 0.0
			for i in int(dur * MIX_RATE):
				var t := float(i) / MIX_RATE
				var f := 95.0 + 70.0 * sin(TAU * 0.9 * t) + 25.0 * sin(TAU * 5.3 * t)
				phase += TAU * f / MIX_RATE
				lp = lerpf(lp, rng.randf_range(-1, 1), 0.05)
				var bubbles := 0.55 + 0.45 * absf(sin(TAU * 6.5 * t + 2.0 * sin(TAU * 1.7 * t)))
				var env := sin(PI * t / dur) * (0.7 + 0.3 * sin(TAU * 2.1 * t))
				samples.append((sin(phase) * 0.6 + sin(phase * 2.0) * 0.15 + lp * 1.5) * bubbles * env * 0.8)
		"gutrumble":
			# What he feels before it: a low gurgling swell under the ribs,
			# with harmonics so small speakers still carry it.
			var dur := 1.2
			var phase := 0.0
			var lp := 0.0
			for i in int(dur * MIX_RATE):
				var t := float(i) / MIX_RATE
				phase += TAU * (70.0 + 12.0 * sin(TAU * 1.3 * t)) / MIX_RATE
				lp = lerpf(lp, rng.randf_range(-1, 1), 0.04)
				var env := minf(t / 0.2, 1.0) * minf((dur - t) / 0.15, 1.0) * (0.75 + 0.25 * sin(TAU * 3.0 * t))
				var tone := sin(phase) * 0.5 + sin(phase * 2.0) * 0.3 + sin(phase * 3.0) * 0.15
				samples.append((tone + lp * 1.2) * env * 0.6)
		"chew":
			# Dry bread chewed with the mouth shut: soft crunches in a row.
			var dur := 1.8
			var lp := 0.0
			for i in int(dur * MIX_RATE):
				var t := float(i) / MIX_RATE
				var env := exp(-fmod(t, 0.36) * 18.0) * minf((dur - t) / 0.1, 1.0)
				lp = lerpf(lp, rng.randf_range(-1, 1), 0.4)
				var crunch := lp * (1.0 + (2.0 if rng.randf() < 0.02 else 0.0))
				samples.append(crunch * env * 0.45)
		"hiss":
			# Pain: a sharp breath in through the teeth - sibilant air,
			# quick to start, a third of a second.
			var dur := 0.4
			var lp := 0.0
			for i in int(dur * MIX_RATE):
				var t := float(i) / MIX_RATE
				var x := rng.randf_range(-1, 1)
				lp = lerpf(lp, x, 0.12)
				var env := minf(t / 0.02, 1.0) * exp(-t * 6.5) * (1.0 + 0.4 * sin(PI * t / dur))
				samples.append((x - lp) * env * 0.8)
		"thump":
			# A door leaf slamming into a body: a dull low blow muffled by a
			# quilted coat, a slap of cloth on the wood, no ring.
			var g1 := 0.0
			var g2 := 0.0
			for i in int(0.28 * MIX_RATE):
				var t := float(i) / MIX_RATE
				var n := rng.randf_range(-1, 1)
				g1 = lerpf(g1, n, 0.12)
				g2 = lerpf(g2, g1, 0.12)
				var x := sin(TAU * (100.0 - 45.0 * t) * t) * exp(-t * 20.0) * 0.8
				x += sin(TAU * 61.0 * t) * exp(-t * 13.0) * 0.45
				x += g2 * 4.0 * exp(-t * 38.0)
				x += n * exp(-t * 260.0) * 0.18
				samples.append(x * 0.7)
		"tear":
			# Cloth ripping on a barb: a crackle of breaking threads.
			var dur := 0.32
			var lp := 0.0
			for i in int(dur * MIX_RATE):
				var t := float(i) / MIX_RATE
				var x := rng.randf_range(-1, 1)
				lp = lerpf(lp, x, 0.35)
				var threads := 1.0 if rng.randf() < 0.18 else 0.25
				var env := minf(t / 0.01, 1.0) * (1.0 - t / dur)
				samples.append(lp * threads * env * 0.9)
		"wirescrape":
			# Barbed wire shaken and dragging over a quilted coat: a dull
			# metallic ring, scraping in jerks as he pulls himself along.
			var dur := 1.4
			var lp := 0.0
			for i in int(dur * MIX_RATE):
				var t := float(i) / MIX_RATE
				var ring := (sin(TAU * 910.0 * t) * 0.5 + sin(TAU * 1370.0 * t) * 0.35
						+ sin(TAU * 2215.0 * t) * 0.2) * exp(-t * 3.0)
				lp = lerpf(lp, rng.randf_range(-1, 1), 0.2)
				var pulls := maxf(sin(TAU * 2.4 * t), 0.0)
				samples.append(ring * 0.35 + lp * pulls * 0.9 * minf((dur - t) / 0.2, 1.0))
		"wrap":
			# A strip of cloth torn off, then wound tight round the arm.
			var dur := 1.6
			var lp := 0.0
			for i in int(dur * MIX_RATE):
				var t := float(i) / MIX_RATE
				var x := rng.randf_range(-1, 1)
				lp = lerpf(lp, x, 0.3)
				var v := 0.0
				if t < 0.28:
					v = lp * (1.0 if rng.randf() < 0.2 else 0.3) * (1.0 - t / 0.28)
				else:
					var u := t - 0.28
					v = lp * 0.5 * maxf(sin(TAU * 1.9 * u), 0.0) * minf((dur - t) / 0.15, 1.0)
				samples.append(v)
		"ragged":
			# His own breath held back in fear: four shallow uneven breaths, in and
			# out through the mouth, shaking (a tremor of 11 Hz), no voice in them.
			# Starts and ends in silence: the loop has no seam.
			var lp := 0.0
			var parts := [[0.26, 0.38, 0.55], [0.32, 0.22, 0.45], [0.2, 0.42, 0.5], [0.36, 0.2, 0.4]]
			for part: Array in parts:
				var dur := float(part[0])
				var bright := float(part[1])
				var amp := float(part[2])
				for i in int(dur * MIX_RATE):
					var t := float(i) / MIX_RATE
					lp = lerpf(lp, rng.randf_range(-1, 1), bright)
					var env := pow(sin(PI * t / dur), 1.5) * (0.55 + 0.45 * sin(TAU * 11.0 * t))
					samples.append(lp * env * amp)
				for i in int(0.06 * MIX_RATE):
					samples.append(0.0)
		"catch":
			# A catch of breath: a sharp gulp of air in that stops dead in the
			# throat, with a small dull knock where it stops.
			var lp := 0.0
			var stop := 0.11
			for i in int(0.22 * MIX_RATE):
				var t := float(i) / MIX_RATE
				lp = lerpf(lp, rng.randf_range(-1, 1), 0.45)
				var env := minf(t / 0.004, 1.0) * (1.0 - 0.4 * t / stop) if t < stop else maxf(1.0 - (t - stop) / 0.008, 0.0) * 0.6
				var knock := 0.0
				if t >= stop:
					var u := t - stop
					knock = sin(TAU * 140.0 * u) * exp(-u * 80.0) * 0.35
				samples.append(lp * env * 0.8 + knock)
		"sip":
			# A quiet held-back breath in through the nose: soft, dark air.
			var lp := 0.0
			var lp2 := 0.0
			for i in int(0.5 * MIX_RATE):
				var t := float(i) / MIX_RATE
				lp = lerpf(lp, rng.randf_range(-1, 1), 0.14)
				lp2 = lerpf(lp2, lp, 0.3)
				var env := sin(PI * minf(t / 0.6, 0.5)) if t < 0.3 else maxf(1.0 - (t - 0.3) / 0.2, 0.0)
				samples.append(lp2 * env * 1.6)
		"breath", "sob", "gasp":
			var dur := {"breath": 0.6, "sob": 0.45, "gasp": 0.5}[kind] as float
			var prev := 0.0
			for i in int(dur * MIX_RATE):
				var t := float(i) / MIX_RATE
				var env := sin(PI * t / dur)
				if kind == "sob":
					env *= 0.6 + 0.4 * sin(TAU * 9.0 * t)
				if kind == "gasp":
					env = minf(t * 25.0, 1.0) * exp(-t * 4.0)
				# Low-passed noise sounds like air.
				prev = lerpf(prev, rng.randf_range(-1, 1), 0.25)
				samples.append(prev * env * 0.7)
	# No clipping: a placeholder that overshoots is scaled down to 0.9.
	var peak := 0.0
	for x in samples:
		peak = maxf(peak, absf(x))
	if peak > 0.9:
		for i in samples.size():
			samples[i] *= 0.9 / peak
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	if kind in LOOP_KINDS:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav
