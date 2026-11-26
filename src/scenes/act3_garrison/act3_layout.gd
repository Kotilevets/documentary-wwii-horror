extends Node3D
## Static scenery of Act III "Партизанский отряд", built in code (CSG
## placeholders until real art). From south to north (z decreasing):
## the detachment's dugout (sepia, z 4..12), a forest path, the checkpoint
## with a barrier (z -44), the garrison street with a fenced depot yard and
## a machine-gun nest, the exit gate (z -104), a field and the forest.
## The office of the interrogation stands apart (x 80, z -60): a closed
## room, the desk lamp, a portrait, a kettle on a stove, a typewriter.
## Layout of a real garrison and GFP office: [НЕ ПОДТВЕРЖДЕНО], generic.

var _mats: Dictionary = {}
var _barrier_pole: Node3D
var _barrier_block: CSGBox3D
var _fire: OmniLight3D
var _t := 0.0
var barrier_open := false


func _ready() -> void:
	_ground()
	_dugout()
	_forest_path()
	_checkpoint()
	_garrison()
	_yard()
	_exit_and_forest()
	_office()


func _process(delta: float) -> void:
	_t += delta
	if _fire != null:
		_fire.light_energy = Flicker.light(1.95, 0.35, _t, 1.0)  # sways, never strobes (Flicker)


## The barrier lifts; the way into the garrison opens.
func open_barrier() -> void:
	if barrier_open:
		return
	barrier_open = true
	_barrier_block.use_collision = false
	create_tween().tween_property(_barrier_pole, "rotation:z", deg_to_rad(80), 1.6) \
			.set_trans(Tween.TRANS_SINE)
	Sfx.play_at("door_creak", _barrier_pole.global_position)


# --- materials -------------------------------------------------------------------

func _mat(name: String) -> StandardMaterial3D:
	if _mats.has(name):
		return _mats[name]
	var textured := Surfaces.material(name)
	if textured != null:
		_mats[name] = textured
		return textured
	var c: Color = {
		"ground": Color(0.32, 0.31, 0.29), "road": Color(0.45, 0.44, 0.42),
		"earth": Color(0.26, 0.24, 0.21), "log": Color(0.33, 0.28, 0.22),
		"wood": Color(0.36, 0.3, 0.24), "bark": Color(0.22, 0.2, 0.18),
		"wire": Color(0.5, 0.5, 0.5), "stone": Color(0.4, 0.39, 0.37),
		"plank": Color(0.42, 0.37, 0.3), "paint": Color(0.5, 0.5, 0.48),
		"truck": Color(0.2, 0.21, 0.2), "tyre": Color(0.07, 0.07, 0.07),
		"metal": Color(0.18, 0.18, 0.18), "sand": Color(0.5, 0.47, 0.4),
		"paper": Color(0.85, 0.84, 0.8), "plaster": Color(0.55, 0.54, 0.5),
		"canvas": Color(0.46, 0.45, 0.42), "shadow": Color(0.12, 0.12, 0.12),
		"roof": Color(0.3, 0.29, 0.27),
	}[name]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0 if name != "metal" else 0.5
	_mats[name] = m
	return m


func _box(size: Vector3, pos: Vector3, mat: String, collide := true, rot_y := 0.0, parent: Node = self) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	b.rotation.y = rot_y
	b.use_collision = collide
	b.material = _mat(mat)
	parent.add_child(b)
	return b


func _cyl(radius: float, height: float, pos: Vector3, mat: String, parent: Node = self, collide := true) -> CSGCylinder3D:
	var c := CSGCylinder3D.new()
	c.radius = radius
	c.height = height
	c.position = pos + Vector3.UP * height * 0.5
	c.use_collision = collide
	c.material = _mat(mat)
	parent.add_child(c)
	return c


## An invisible barrier: it stops the boy, enemies and the navmesh, but not
## sound, sight or moonlight (Stealth.SEE_THROUGH_LAYER).
func _wall(size: Vector3, pos: Vector3) -> void:
	_invisible(_box(size, pos, "bark"))


## The wall of a building: it stops sound for enemies' ears
## (Stealth.SOUND_WALLS); hedges, sandbags, fences and furniture do not.
func _sound_wall(b: CSGShape3D) -> CSGShape3D:
	b.add_to_group(Stealth.SOUND_WALLS)
	return b


func _invisible(b: CSGBox3D) -> void:
	b.visible = false
	b.collision_layer = Stealth.SEE_THROUGH_LAYER
	b.collision_mask = 0


func _fence(a: Vector3, b: Vector3, parent: Node) -> void:
	var n := maxi(int(a.distance_to(b) / 2.5), 1)
	for i in n + 1:
		_box(Vector3(0.14, 2.2, 0.14), a.lerp(b, float(i) / n) + Vector3.UP * 1.1, "wood", true, 0.0, parent)
	var mid := (a + b) * 0.5
	var rot := atan2(b.x - a.x, b.z - a.z) + PI * 0.5
	for h in [0.5, 1.1, 1.7]:
		_box(Vector3(a.distance_to(b), 0.02, 0.02), mid + Vector3.UP * h, "wire", false, rot, parent)
	# Barbed wire: an invisible wall the boy cannot climb (see-through).
	var w := CSGBox3D.new()
	w.size = Vector3(a.distance_to(b), 2.2, 0.1)
	w.position = mid + Vector3.UP * 1.1
	w.rotation.y = rot
	w.use_collision = true
	w.collision_layer = Stealth.SEE_THROUGH_LAYER
	w.collision_mask = 0
	w.visible = false
	parent.add_child(w)


# --- parts -----------------------------------------------------------------------

func _ground() -> void:
	_box(Vector3(120, 1, 170), Vector3(5, -0.5, -55), "ground")
	_box(Vector3(3, 0.02, 150), Vector3(0, 0.01, -65), "road", false)
	# Edges of the playable area: forest and thicket (invisible walls).
	_wall(Vector3(1, 6, 60), Vector3(-7, 3, -15))
	_wall(Vector3(1, 6, 60), Vector3(7, 3, -15))
	_wall(Vector3(16, 6, 1), Vector3(0, 3, 13))
	_wall(Vector3(1, 6, 92), Vector3(-16, 3, -89))
	_wall(Vector3(1, 6, 92), Vector3(28, 3, -89))
	_wall(Vector3(46, 6, 1), Vector3(6, 3, -135))
	for z in range(12, -44, -3):
		_cyl(0.3, 9.0, Vector3(-6.4 + (z % 2) * 0.5, 0, z), "bark")
		_cyl(0.3, 9.0, Vector3(6.4 - (z % 2) * 0.5, 0, z), "bark")
	for z in range(-46, -134, -4):
		_cyl(0.32, 9.0, Vector3(-15.4, 0, z), "bark")
		_cyl(0.32, 9.0, Vector3(27.4, 0, z), "bark")


## The detachment's dugout: log walls, a fire, a table with the passes.
func _dugout() -> void:
	var d := Node3D.new()
	d.name = "Dugout"
	add_child(d)
	_sound_wall(_box(Vector3(0.4, 2.3, 8.4), Vector3(-2.8, 1.15, 8), "log", true, 0.0, d))
	_sound_wall(_box(Vector3(0.4, 2.3, 8.4), Vector3(2.8, 1.15, 8), "log", true, 0.0, d))
	_sound_wall(_box(Vector3(6, 2.3, 0.4), Vector3(0, 1.15, 12.2), "log", true, 0.0, d))
	_sound_wall(_box(Vector3(2.4, 2.3, 0.4), Vector3(-1.8, 1.15, 3.8), "log", true, 0.0, d))
	_sound_wall(_box(Vector3(2.4, 2.3, 0.4), Vector3(1.8, 1.15, 3.8), "log", true, 0.0, d))
	_sound_wall(_box(Vector3(6, 0.4, 8.8), Vector3(0, 2.5, 8), "earth", true, 0.0, d))
	# Bunks along the west wall.
	_box(Vector3(1.1, 0.5, 3.2), Vector3(-2.0, 0.25, 9.5), "plank", true, 0.0, d)
	# Fire on stones.
	for i in 7:
		var a := TAU * i / 7.0
		_box(Vector3(0.18, 0.14, 0.18), Vector3(-0.9 + cos(a) * 0.32, 0.07, 6.6 + sin(a) * 0.32), "stone", false, a, d)
	_box(Vector3(0.35, 0.08, 0.1), Vector3(-0.9, 0.12, 6.6), "log", false, 0.6, d)
	_box(Vector3(0.35, 0.08, 0.1), Vector3(-0.9, 0.12, 6.6), "log", false, -0.7, d)
	_fire = OmniLight3D.new()
	_fire.position = Vector3(-0.9, 0.45, 6.6)
	_fire.light_color = Color(1.0, 0.85, 0.65)
	_fire.omni_range = 7.0
	_fire.light_energy = 1.6
	_fire.shadow_enabled = true
	d.add_child(_fire)
	# Table and bench; the passes lie on the table (Act3Garrison/Bundle).
	_box(Vector3(1.4, 0.06, 0.8), Vector3(1.4, 0.75, 9.4), "plank", true, 0.0, d)
	_box(Vector3(1.2, 0.72, 0.6), Vector3(1.4, 0.36, 9.4), "plank", true, 0.0, d)
	_box(Vector3(1.3, 0.42, 0.3), Vector3(1.4, 0.21, 8.6), "plank", true, 0.0, d)


func _forest_path() -> void:
	_box(Vector3(1.6, 0.02, 40), Vector3(0, 0.012, -16), "earth", false)
	# Fallen trunks and bushes along the path.
	_box(Vector3(4.0, 0.5, 0.5), Vector3(-3.5, 0.25, -12), "bark", true, 0.3)
	_box(Vector3(1.8, 1.2, 1.8), Vector3(3.8, 0.6, -24), "bark", true, 0.4)
	_box(Vector3(2.2, 1.0, 1.6), Vector3(-4.0, 0.5, -33), "bark", true, -0.2)


## The checkpoint: wire across the path, a barrier pole, a sentry hut.
func _checkpoint() -> void:
	var cp := Node3D.new()
	cp.name = "Checkpoint"
	add_child(cp)
	_fence(Vector3(-15.5, 0, -44), Vector3(-1.8, 0, -44), cp)
	_fence(Vector3(1.8, 0, -44), Vector3(27.5, 0, -44), cp)
	_box(Vector3(0.25, 1.2, 0.25), Vector3(-1.8, 0.6, -44), "paint", true, 0.0, cp)
	_box(Vector3(0.25, 1.2, 0.25), Vector3(1.8, 0.6, -44), "paint", true, 0.0, cp)
	_barrier_pole = Node3D.new()
	_barrier_pole.name = "Pole"
	_barrier_pole.position = Vector3(-1.8, 1.1, -44)
	cp.add_child(_barrier_pole)
	_box(Vector3(3.8, 0.1, 0.1), Vector3(1.9, 0, 0), "paint", false, 0.0, _barrier_pole)
	_barrier_block = _box(Vector3(3.4, 2.2, 0.3), Vector3(0, 1.1, -44), "paint", true, 0.0, cp)
	_invisible(_barrier_block)
	_sound_wall(_box(Vector3(1.8, 2.3, 1.8), Vector3(-4.2, 1.15, -46.5), "plank", true, 0.0, cp))  # sentry hut


func _garrison() -> void:
	var g := Node3D.new()
	g.name = "Garrison"
	add_child(g)
	# Village houses taken as quarters: log walls, a gable roof.
	for z in [-52.0, -62.0, -72.0, -82.0]:
		_house(Vector3(-9, 0, z), g)
	for z in [-52.0, -88.0]:
		_house(Vector3(6.5, 0, z), g)
	# The commandant's office: plastered, two storeys.
	_sound_wall(_box(Vector3(7, 5, 8), Vector3(-9.5, 2.5, -95), "plaster", true, 0.0, g))
	# Machine-gun nest at the street corner: a ring of sandbags.
	var nest := Node3D.new()
	nest.name = "GunNest"
	nest.position = Vector3(-4.5, 0, -88)
	g.add_child(nest)
	for i in 9:
		var a := lerpf(-PI * 0.8, PI * 0.8, i / 8.0)
		_box(Vector3(0.8, 0.8, 0.45), Vector3(sin(a) * 1.3, 0.4, -cos(a) * 1.3), "sand", true, -a, nest)
	_box(Vector3(0.08, 0.08, 1.1), Vector3(0, 0.95, -1.0), "metal", false, 0.0, nest)
	_box(Vector3(0.2, 0.18, 0.4), Vector3(0, 0.92, -0.4), "metal", false, 0.0, nest)


func _house(at: Vector3, parent: Node) -> void:
	_sound_wall(_box(Vector3(5, 3, 6), at + Vector3(0, 1.5, 0), "log", true, 0.0, parent))
	var roof := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(5.6, 1.6, 6.4)
	roof.mesh = prism
	roof.material_override = _mat("roof")
	roof.position = at + Vector3(0, 3.8, 0)
	parent.add_child(roof)


## The depot yard behind wire: trucks, fuel drums. A restricted zone.
func _yard() -> void:
	var y := Node3D.new()
	y.name = "Yard"
	add_child(y)
	_fence(Vector3(11, 0, -62), Vector3(25, 0, -62), y)
	_fence(Vector3(25, 0, -62), Vector3(25, 0, -82), y)
	_fence(Vector3(25, 0, -82), Vector3(11, 0, -82), y)
	_fence(Vector3(11, 0, -82), Vector3(11, 0, -74), y)
	_fence(Vector3(11, 0, -70), Vector3(11, 0, -62), y)
	for x in [15.5, 19.5]:
		var t := Node3D.new()
		t.position = Vector3(x, 0, -67)
		y.add_child(t)
		_box(Vector3(2.0, 1.1, 2.0), Vector3(0, 1.25, -2.0), "truck", true, 0.0, t)
		_box(Vector3(2.1, 0.5, 3.6), Vector3(0, 0.95, 0.8), "truck", true, 0.0, t)
		_box(Vector3(2.1, 1.3, 3.6), Vector3(0, 1.85, 0.8), "canvas", false, 0.0, t)
		for wz in [-2.0, 0.0, 1.8]:
			for wx in [-1.0, 1.0]:
				var w := _cyl(0.42, 0.3, Vector3(wx, 0.42, wz), "tyre", t, false)
				w.rotation.z = PI * 0.5
				w.position = Vector3(wx, 0.42, wz)
	for i in 8:
		_cyl(0.3, 0.9, Vector3(20.5 + (i % 4) * 0.65, 0, -77.5 - floorf(i / 4.0) * 0.65), "metal", y)
	_sound_wall(_box(Vector3(4, 2.6, 3), Vector3(15, 1.3, -78.5), "plank", true, 0.0, y))  # depot shed


func _exit_and_forest() -> void:
	var e := Node3D.new()
	e.name = "Exit"
	add_child(e)
	_fence(Vector3(-15.5, 0, -104), Vector3(-2.0, 0, -104), e)
	_fence(Vector3(2.0, 0, -104), Vector3(27.5, 0, -104), e)
	_box(Vector3(0.3, 2.6, 0.3), Vector3(-2.0, 1.3, -104), "wood", true, 0.0, e)
	_box(Vector3(0.3, 2.6, 0.3), Vector3(2.0, 1.3, -104), "wood", true, 0.0, e)
	for z in [-126.0, -129.0, -132.0]:
		for x in range(-14, 28, 3):
			_cyl(0.32, 10.0, Vector3(x + fmod(z, 2.0), 0, z), "bark")


## The office (x 80, z -60): the boy on a stool faces east, the desk, the
## investigator behind it. Interrogation details are GazeTargets in the
## scene (Office/Details); here only the furniture.
func _office() -> void:
	var o := Node3D.new()
	o.name = "Office"
	o.position = Vector3(80, 0, -60)
	add_child(o)
	_box(Vector3(5, 0.2, 5), Vector3(0, -0.1, 0), "plank", true, 0.0, o)
	var boards := BoardFloor.new()
	boards.name = "Boards"
	boards.size = Vector3(4.4, 1.0, 4.4)
	o.add_child(boards)
	_sound_wall(_box(Vector3(5, 0.2, 5), Vector3(0, 3.1, 0), "plaster", true, 0.0, o))
	_sound_wall(_box(Vector3(0.2, 3, 5), Vector3(-2.3, 1.5, 0), "plaster", true, 0.0, o))
	_sound_wall(_box(Vector3(0.2, 3, 5), Vector3(2.3, 1.5, 0), "plaster", true, 0.0, o))
	_sound_wall(_box(Vector3(5, 3, 0.2), Vector3(0, 1.5, -2.3), "plaster", true, 0.0, o))
	_sound_wall(_box(Vector3(5, 3, 0.2), Vector3(0, 1.5, 2.3), "plaster", true, 0.0, o))
	# Door behind the boy, a shuttered window on the north wall.
	_box(Vector3(0.05, 2.0, 0.9), Vector3(-2.18, 1.0, 0.6), "wood", false, 0.0, o)
	_box(Vector3(1.0, 0.8, 0.05), Vector3(0.6, 1.7, -2.18), "wood", false, 0.0, o)
	# Desk, chair behind it, the boy's stool.
	_box(Vector3(0.8, 0.05, 1.5), Vector3(0.3, 0.76, 0), "wood", true, 0.0, o)
	_box(Vector3(0.7, 0.72, 0.1), Vector3(0.3, 0.37, -0.7), "wood", true, 0.0, o)
	_box(Vector3(0.7, 0.72, 0.1), Vector3(0.3, 0.37, 0.7), "wood", true, 0.0, o)
	_box(Vector3(0.45, 0.05, 0.45), Vector3(1.75, 0.46, 0.4), "wood", false, 0.0, o)
	_cyl(0.18, 0.45, Vector3(-1.45, 0, 0), "wood", o, false)
	# Papers on the desk: the forms of the case (blank, as the documents
	# themselves are entered by the author).
	_box(Vector3(0.21, 0.01, 0.3), Vector3(0.15, 0.79, 0.35), "paper", false, 0.2, o)
	_box(Vector3(0.21, 0.01, 0.3), Vector3(0.25, 0.795, 0.25), "paper", false, -0.1, o)
	# Desk lamp: a metal shade on a stem.
	_cyl(0.07, 0.03, Vector3(0.1, 0.785, -0.45), "metal", o, false)
	_box(Vector3(0.02, 0.3, 0.02), Vector3(0.1, 0.95, -0.45), "metal", false, 0.0, o)
	var shade := CSGCylinder3D.new()
	shade.radius = 0.11
	shade.height = 0.14
	shade.cone = true
	shade.material = _mat("metal")
	shade.position = Vector3(0.05, 1.12, -0.45)
	# Apex towards the investigator, the open side at the boy: he looks
	# straight into the bulb.
	shade.rotation.z = deg_to_rad(-65)
	o.add_child(shade)
	var bulb := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.07
	bm.height = 0.05
	bulb.mesh = bm
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1, 1, 0.97)
	bulb.material_override = glow
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bulb.position = Vector3(-0.015, 1.095, -0.45)
	bulb.rotation.z = deg_to_rad(-65)
	o.add_child(bulb)
	var lamp := SpotLight3D.new()
	lamp.name = "LampLight"
	lamp.position = Vector3(0.0, 1.1, -0.45)
	lamp.rotation = Vector3(deg_to_rad(-8), deg_to_rad(90), 0)  # at the boy
	lamp.light_color = Color(1.0, 0.97, 0.9)
	lamp.light_energy = 6.0
	lamp.spot_range = 5.0
	lamp.spot_angle = 38.0
	lamp.shadow_enabled = true
	o.add_child(lamp)
	var spill := OmniLight3D.new()
	spill.name = "LampSpill"
	spill.position = Vector3(0.35, 1.0, -0.4)
	spill.light_energy = 0.9
	spill.omni_range = 3.2
	spill.shadow_enabled = true
	o.add_child(spill)
	# Iron stove in the corner; the kettle on it is a GazeTarget's object.
	_box(Vector3(0.5, 0.6, 0.5), Vector3(1.3, 0.3, 1.5), "metal", true, 0.0, o)
	_cyl(0.06, 2.4, Vector3(1.3, 0.6, 1.65), "metal", o, false)
	var kettle := Node3D.new()
	kettle.name = "Kettle"
	kettle.position = Vector3(1.3, 0.6, 1.5)
	o.add_child(kettle)
	_cyl(0.1, 0.13, Vector3.ZERO, "metal", kettle, false)
	Sfx.play_at("kettle_simmer", kettle.global_position + Vector3.UP * 0.1, 1.0, kettle)
	_cyl(0.04, 0.03, Vector3(0, 0.13, 0), "metal", kettle, false)
	var spout := _box(Vector3(0.03, 0.03, 0.12), Vector3(0, 0.08, -0.13), "metal", false, 0.0, kettle)
	spout.rotation.x = deg_to_rad(35)
	_box(Vector3(0.02, 0.1, 0.12), Vector3(0, 0.2, 0), "metal", false, 0.0, kettle)
	# Wall clock behind the investigator, to the boy's right: the same tick
	# as at home; the nightmare slows it down (WallClock.stretch_with_illusion).
	var clock := WallClock.new()
	clock.name = "WallClock"
	clock.stretch_with_illusion = true
	clock.position = Vector3(2.16, 2.0, 0.95)
	clock.rotation.y = -PI * 0.5
	o.add_child(clock)
	# Typewriter on the desk, turned to the investigator.
	var tw := Node3D.new()
	tw.name = "Typewriter"
	tw.position = Vector3(0.3, 0.785, 0.45)
	o.add_child(tw)
	_box(Vector3(0.26, 0.08, 0.32), Vector3(0, 0.04, 0), "metal", false, 0.0, tw)
	var keys := _box(Vector3(0.12, 0.05, 0.28), Vector3(0.09, 0.09, 0), "shadow", false, 0.0, tw)
	keys.rotation.z = deg_to_rad(-15)
	var roller := _cyl(0.025, 0.34, Vector3(-0.08, 0.1, 0), "metal", tw, false)
	roller.rotation.x = PI * 0.5
	roller.position = Vector3(-0.08, 0.13, 0)
	_box(Vector3(0.01, 0.2, 0.21), Vector3(-0.1, 0.24, 0), "paper", false, 0.0, tw)
	# Portrait on the wall behind the investigator, to the boy's left.
	# A generic dark bust in a frame: whose portrait it is, is left to the
	# author ([НЕ ПОДТВЕРЖДЕНО]); no recognisable face is drawn.
	var pr := Node3D.new()
	pr.name = "Portrait"
	pr.position = Vector3(2.17, 1.95, -1.2)
	o.add_child(pr)
	_box(Vector3(0.04, 0.72, 0.56), Vector3.ZERO, "wood", true, 0.0, pr)
	_box(Vector3(0.02, 0.62, 0.46), Vector3(-0.02, 0, 0), "canvas", false, 0.0, pr)
	var head := CSGSphere3D.new()
	head.radius = 0.09
	head.scale = Vector3(0.3, 1.2, 1.0)
	head.material = _mat("shadow")
	head.position = Vector3(-0.035, 0.06, 0)
	pr.add_child(head)
	_box(Vector3(0.01, 0.2, 0.36), Vector3(-0.035, -0.2, 0), "shadow", false, 0.0, pr)
