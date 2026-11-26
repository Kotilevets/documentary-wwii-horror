extends Node3D
## Scenery of the dream after Act I (night_dream.gd), built in code:
##   - the family's izba (interior x -2.8..2.8, z -2.3..2.3): stove, table
##     with four bowls and bread, four stools, a lamp over the table, the
##     wall clock, a window to the west, a door in the north wall;
##   - the сени behind the door: a dark passage going north (x 1..2,
##     z -2.6..-8); the dream returns the boy to the room from there;
##   - a forest pocket far to the east (x 60): where he wakes up.
## The story script changes the room between returns: set_ceiling(),
## set_table(), the lamp, block_doorway().

const ROOM_TOP := 3.0

var ceiling: CSGBox3D
## Invisible: closes the doorway for the body in the last room.
var door_block: CSGBox3D
var lamp: OmniLight3D
var window_light: OmniLight3D
## The сени lit up in the last room: the figure stands black against it.
var door_light: OmniLight3D
var clock: WallClock
var stools: Array[CSGBox3D] = []
var bowls: Array[Node3D] = []
var bread: Node3D
var _mats: Dictionary = {}
var _flicker := 0.0
var _lamp_energy := 0.9
var _flare_time := 0.0
var _t := 0.0


func _ready() -> void:
	_room()
	_passage()
	_forest()


func _process(delta: float) -> void:
	_t += delta
	if not is_instance_valid(lamp):
		return  # the room is gone: he has woken up
	# The lamp gutters slowly and trembles a little; the flare in the window
	# sways (Flicker: no strobing, docs/ARCHITECTURE.md, "Вспышки и мерцание").
	lamp.light_energy = Flicker.light(_lamp_energy, _flicker, _t)
	if _flare_time > 0.0:
		_flare_time -= delta
		window_light.light_energy = Flicker.light(2.5, 0.3, _t, 2.0) * clampf(_flare_time / 1.5, 0.0, 1.0)
	else:
		window_light.light_energy = 0.0


# --- what the story changes ------------------------------------------------------

func set_ceiling(height: float) -> void:
	ceiling.position.y = height + 0.1


## The lamp: its energy and how deep it gutters, 0..1 of it (Flicker.light).
func set_lamp(energy: float, flicker: float) -> void:
	_lamp_energy = energy
	_flicker = flicker


## A flare outside: its light sways in the window for a few seconds.
func flare(seconds: float = 6.0) -> void:
	_flare_time = seconds


## The table as it was (`stage` 0) and as it empties.
func set_table(stage: int) -> void:
	for i in bowls.size():
		bowls[i].visible = i < [4, 4, 1, 0][stage]
	bread.visible = stage == 0
	for i in stools.size():
		stools[i].visible = i < [4, 4, 2, 0][stage]
		stools[i].use_collision = stools[i].visible
	# One stool lies on its side, as if someone got up too fast.
	var fallen := stools[1]
	if stage >= 1:
		fallen.rotation = Vector3(0, 0.4, PI * 0.5)
		fallen.position.y = 0.175
	else:
		fallen.rotation = Vector3.ZERO
		fallen.position.y = 0.225


func block_doorway(on: bool) -> void:
	door_block.use_collision = on
	door_light.visible = on


# --- building --------------------------------------------------------------------

func _mat(name: String) -> StandardMaterial3D:
	if _mats.has(name):
		return _mats[name]
	var m := Surfaces.material(name)
	if m == null:
		m = StandardMaterial3D.new()
		m.albedo_color = {"shadow": Color(0.02, 0.02, 0.02), "metal": Color(0.2, 0.2, 0.2)}.get(name, Color(0.35, 0.3, 0.25))
		m.roughness = 1.0
	_mats[name] = m
	return m


func _box(size: Vector3, pos: Vector3, mat: String, collide := true, parent: Node = self) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	b.use_collision = collide
	b.material = _mat(mat)
	parent.add_child(b)
	return b


func _cyl(radius: float, height: float, pos: Vector3, mat: String, parent: Node = self, collide := false) -> CSGCylinder3D:
	var c := CSGCylinder3D.new()
	c.radius = radius
	c.height = height
	c.position = pos + Vector3.UP * height * 0.5
	c.use_collision = collide
	c.material = _mat(mat)
	parent.add_child(c)
	return c


func _room() -> void:
	var r := Node3D.new()
	r.name = "Room"
	add_child(r)
	_box(Vector3(6.2, 0.2, 5.2), Vector3(0, -0.1, 0), "planks", true, r)
	var boards := BoardFloor.new()
	boards.name = "Boards"
	boards.size = Vector3(6.0, 1.0, 5.0)
	r.add_child(boards)
	ceiling = _box(Vector3(6.2, 0.2, 5.2), Vector3(0, 2.7, 0), "logs", true, r)
	ceiling.name = "Ceiling"
	ceiling.add_to_group(Stealth.SOUND_WALLS)
	# Walls: south and east whole; north with the door (x 1..2); west with
	# the window (z -0.4..0.4, y 1.2..1.8).
	_box(Vector3(6.2, ROOM_TOP, 0.3), Vector3(0, 1.5, 2.45), "logs", true, r).add_to_group(Stealth.SOUND_WALLS)
	_box(Vector3(0.3, ROOM_TOP, 5.2), Vector3(2.95, 1.5, 0), "logs", true, r).add_to_group(Stealth.SOUND_WALLS)
	_box(Vector3(4.1, ROOM_TOP, 0.3), Vector3(-1.05, 1.5, -2.45), "logs", true, r).add_to_group(Stealth.SOUND_WALLS)
	_box(Vector3(1.1, ROOM_TOP, 0.3), Vector3(2.55, 1.5, -2.45), "logs", true, r).add_to_group(Stealth.SOUND_WALLS)
	_box(Vector3(1.0, 1.0, 0.3), Vector3(1.5, 2.5, -2.45), "logs", true, r).add_to_group(Stealth.SOUND_WALLS)
	_box(Vector3(0.3, ROOM_TOP, 2.2), Vector3(-2.95, 1.5, -1.5), "logs", true, r).add_to_group(Stealth.SOUND_WALLS)
	_box(Vector3(0.3, ROOM_TOP, 2.2), Vector3(-2.95, 1.5, 1.5), "logs", true, r).add_to_group(Stealth.SOUND_WALLS)
	_box(Vector3(0.3, 1.2, 0.8), Vector3(-2.95, 0.6, 0), "logs", true, r).add_to_group(Stealth.SOUND_WALLS)
	_box(Vector3(0.3, 1.2, 0.8), Vector3(-2.95, 2.4, 0), "logs", true, r).add_to_group(Stealth.SOUND_WALLS)
	door_block = _box(Vector3(1.0, 2.0, 0.1), Vector3(1.5, 1.0, -2.3), "logs", false, r)
	door_block.name = "DoorBlock"
	door_block.visible = false
	door_light = OmniLight3D.new()
	door_light.name = "DoorLight"
	door_light.position = Vector3(1.5, 1.6, -4.6)
	door_light.light_energy = 3.0
	door_light.omni_range = 5.0
	door_light.shadow_enabled = true
	door_light.visible = false
	r.add_child(door_light)
	# Stove in the corner, the table with the family's places.
	_box(Vector3(1.4, 1.8, 1.4), Vector3(2.0, 0.9, 1.5), "stove", true, r)
	_box(Vector3(1.4, 0.06, 0.8), Vector3(-1.4, 0.72, 1.0), "planks", true, r)
	for leg in [Vector3(-2.0, 0, 0.7), Vector3(-0.8, 0, 0.7), Vector3(-2.0, 0, 1.3), Vector3(-0.8, 0, 1.3)]:
		_box(Vector3(0.07, 0.69, 0.07), leg + Vector3.UP * 0.345, "planks", false, r)
	for pos in [Vector3(-1.85, 0.75, 0.8), Vector3(-0.95, 0.75, 0.8),
			Vector3(-1.85, 0.75, 1.2), Vector3(-0.95, 0.75, 1.2)]:
		bowls.append(_cyl(0.09, 0.05, pos, "wood", r))
	bread = _box(Vector3(0.24, 0.1, 0.15), Vector3(-1.4, 0.8, 1.0), "wood", false, r)
	for pos in [Vector3(-2.4, 0.225, 1.0), Vector3(-0.4, 0.225, 1.0),
			Vector3(-1.4, 0.225, 0.2), Vector3(-1.4, 0.225, 1.85)]:
		stools.append(_box(Vector3(0.34, 0.45, 0.34), pos, "planks", true, r))
	lamp = OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.position = Vector3(-1.4, 1.5, 1.0)
	lamp.light_color = Color(1, 0.8, 0.55)
	lamp.light_energy = _lamp_energy
	lamp.omni_range = 6.5
	lamp.shadow_enabled = true
	r.add_child(lamp)
	window_light = OmniLight3D.new()
	window_light.name = "FlareLight"
	window_light.position = Vector3(-4.5, 2.2, 0)
	window_light.light_energy = 0.0
	window_light.omni_range = 9.0
	window_light.shadow_enabled = true
	r.add_child(window_light)
	clock = WallClock.new()
	clock.name = "WallClock"
	clock.slow_rate = 0.55
	clock.position = Vector3(-1.4, 1.75, 2.26)
	clock.rotation.y = PI
	r.add_child(clock)


func _passage() -> void:
	var p := Node3D.new()
	p.name = "Passage"
	add_child(p)
	_box(Vector3(1.4, 0.2, 5.6), Vector3(1.5, -0.1, -5.3), "planks", true, p)
	_box(Vector3(1.4, 0.2, 5.6), Vector3(1.5, 2.4, -5.3), "planks", true, p)
	_box(Vector3(0.2, 2.5, 5.6), Vector3(0.8, 1.25, -5.3), "planks", true, p)
	_box(Vector3(0.2, 2.5, 5.6), Vector3(2.2, 1.25, -5.3), "planks", true, p)
	_box(Vector3(1.4, 2.5, 0.2), Vector3(1.5, 1.25, -8.2), "planks", true, p)


func _forest() -> void:
	var f := Node3D.new()
	f.name = "Forest"
	f.position = Vector3(60, 0, 0)
	add_child(f)
	_box(Vector3(30, 1, 30), Vector3(0, -0.5, 0), "ground", true, f)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for i in 26:
		var a := rng.randf() * TAU
		var d := rng.randf_range(2.5, 12.0)
		var at := Vector3(cos(a) * d, 0, sin(a) * d)
		_cyl(rng.randf_range(0.18, 0.32), rng.randf_range(9.0, 13.0), at, "bark", f)
		# Fir crowns: dark cones up the trunk.
		for k in 3:
			var cone := CSGCylinder3D.new()
			cone.cone = true
			cone.radius = 1.8 - k * 0.45
			cone.height = 2.6
			cone.position = at + Vector3.UP * (4.5 + k * 1.9)
			cone.material = _mat("hedge")
			f.add_child(cone)
	var dawn := OmniLight3D.new()
	dawn.name = "Dawn"
	dawn.position = Vector3(0, 14, -4)
	dawn.light_energy = 1.4
	dawn.omni_range = 40.0
	f.add_child(dawn)
