extends Node3D
## Static scenery of the Act II road, built in code (CSG placeholders until
## real art): a burned village where only stoves and chimneys stand (the
## image of the "огненные деревни", ref_burned_villages), a hedge and a
## field of tripwires around a road checkpoint, barbed wire across the end
## of the field with a gap dug under it, a transit camp fence with a
## searchlight tower, gallows at the crossroads, the forest at the end.
## The road runs from z = +10 (south, start) to z = -150 (north, forest).

const PICKUP := preload("res://src/interaction/pickup.tscn")
const BREAD := preload("res://assets/data/items/bread.tres")
const BANDAGE := preload("res://assets/data/items/bandage.tres")
const SUMMONS := preload("res://assets/data/items/doc_arbeitsamt_summons.tres")
## Barbed wire across the north end of the field (_field_wire).
const FIELD_WIRE_Z := -84.0
## Half the width of the opening left in it for the road.
const ROAD_OPENING := 2.3
## Where the gap is dug under it, out in the field: farther than the camp
## guard's torch reaches from the end of his beat (docs/ARCHITECTURE.md,
## "Проходимость Акта II").
const WIRE_GAP_X := 13.0
## A haystack just past the wire, north-west of the gap: from the tower its
## shadow falls over the gap - the boy crawls in shadow; getting to the gap
## across the lit corner of the minefield is the timing.
const GAP_STACK := Vector3(11.1, 0, -86.5)
## The house he remembers (MemoryFlash) - the west one at z -26; its stove
## keeps the bread.
const MEMORY_HOUSE := Vector3(-7.5, 0, -26)

var _mats: Dictionary = {}


func _ready() -> void:
	_ground()
	_burned_village()
	_checkpoint_and_field()
	_field_wire()
	_camp()
	_gallows()
	_gunfire()
	_forest()
	_phantoms()


## Things by the road that panic makes into a figure at the edge of the view
## (PhantomFigure): a coat on a post past the burned houses, a stump at the
## far side of the field, a stump short of the forest. Placed for the game.
func _phantoms() -> void:
	var group := Node3D.new()
	group.name = "Phantoms"
	add_child(group)
	for spot in [[PhantomFigure.Disguise.COAT_ON_POST, Vector3(11.5, 0, -22)],
			[PhantomFigure.Disguise.STUMP, Vector3(28.5, 0, -50)],
			[PhantomFigure.Disguise.STUMP, Vector3(-8, 0, -141)]]:
		var ph := PhantomFigure.new()
		ph.disguise = spot[0]
		ph.position = spot[1]
		ph.rotation.y = -PI * 0.5  # the coat's broad side to the road
		group.add_child(ph)


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
		"ash": Color(0.17, 0.17, 0.17), "brick": Color(0.42, 0.4, 0.37),
		"charred": Color(0.1, 0.1, 0.1), "wood": Color(0.36, 0.3, 0.24),
		"hedge": Color(0.2, 0.21, 0.19), "bark": Color(0.22, 0.2, 0.18),
		"wire": Color(0.5, 0.5, 0.5), "board": Color(0.62, 0.6, 0.55),
		"rope": Color(0.5, 0.47, 0.42),
	}[name]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
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


## A flat thing on the ground (road, ash): a drop of blood lands on it
## (Wound.SURFACE_LAYER); nothing else collides with it.
func _surface(b: CSGBox3D) -> CSGBox3D:
	b.use_collision = true
	b.collision_layer = Wound.SURFACE_LAYER
	b.collision_mask = 0
	return b


## An invisible barrier (thicket, wire): it stops the boy, enemies and the
## navmesh, but not sound, sight or moonlight (Stealth.SEE_THROUGH_LAYER).
func _invisible(b: CSGBox3D) -> void:
	b.visible = false
	b.collision_layer = Stealth.SEE_THROUGH_LAYER
	b.collision_mask = 0


func _cyl(radius: float, height: float, pos: Vector3, mat: String, parent: Node = self) -> CSGCylinder3D:
	var c := CSGCylinder3D.new()
	c.radius = radius
	c.height = height
	c.position = pos + Vector3.UP * height * 0.5
	c.use_collision = true
	c.material = _mat(mat)
	parent.add_child(c)
	return c


func _pickup(item: ItemData, pos: Vector3) -> void:
	var p := PICKUP.instantiate()
	# A stable name: checkpoints remember taken things by their path.
	p.name = "Pickup_" + item.id
	p.set("item", item)
	p.position = pos
	add_child(p)


# --- parts -----------------------------------------------------------------------

func _ground() -> void:
	_box(Vector3(120, 1, 200), Vector3(0, -0.5, -70), "ground")
	_surface(_box(Vector3(4, 0.02, 170), Vector3(0, 0.01, -72), "road", false))
	# Edges of the playable strip: dense forest west and east.
	for z in range(12, -152, -3):
		_cyl(0.35, 9.0, Vector3(-13 + (z % 2) * 0.6, 0, z), "bark")
		_cyl(0.35, 9.0, Vector3(31 + (z % 2) * 0.6, 0, z), "bark")
	for x in range(-13, 32, 3):
		_cyl(0.35, 9.0, Vector3(x, 0, 13), "bark")
	# The trees are drawn sparse; the strip is closed by invisible walls
	# (a thicket the boy cannot get through).
	for w in [[Vector3(1, 6, 180), Vector3(-14, 3, -72)], [Vector3(1, 6, 180), Vector3(32, 3, -72)],
			[Vector3(48, 6, 1), Vector3(9, 3, 14)], [Vector3(48, 6, 1), Vector3(9, 3, -163)]]:
		_invisible(_box(w[0], w[1], "bark"))


func _burned_village() -> void:
	var village := Node3D.new()
	village.name = "BurnedVillage"
	add_child(village)
	var bread_at := Vector3.ZERO
	for side in [-1, 1]:
		for z in [-18.0, -26.0, -34.0, -42.0]:
			var x: float = side * 7.5
			# Only the stove and the chimney are left of each house.
			_surface(_box(Vector3(5.5, 0.04, 4.5), Vector3(x, 0.02, z), "ash", false, 0.0, village))
			var stove := _box(Vector3(1.5, 1.1, 1.7), Vector3(x + side * 0.8, 0.55, z + 0.6), "brick", true, 0.0, village)
			if side == -1 and z == MEMORY_HOUSE.z:
				bread_at = _oven_mouth(stove)
			_box(Vector3(0.7, 4.4, 0.7), Vector3(x + side * 1.0, 2.2, z + 0.9), "brick", true, 0.0, village)
			_box(Vector3(3.8, 0.22, 0.22), Vector3(x - side * 0.6, 0.12, z - 1.2), "charred", true, 0.4 * side, village)
			_box(Vector3(2.6, 0.2, 0.2), Vector3(x, 0.1, z + 1.6), "charred", true, -0.8 * side, village)
	# Still smoking at the far end - gone while he remembers (present_only).
	var smoke_all := Node3D.new()
	smoke_all.name = "Smoke"
	village.add_child(smoke_all)
	for pos in [Vector3(7.5, 0.3, -42), Vector3(-7.5, 0.3, -34)]:
		var smoke := SmoulderSmoke.new()
		smoke.position = pos
		smoke_all.add_child(smoke)
	# A notice post by the road with the summons; the bread in the cold stove
	# of the house he remembers.
	_cyl(0.12, 2.4, Vector3(2.8, 0, -30), "wood", village)
	_pickup(SUMMONS, Vector3(2.8, 1.5, -29.86))
	_pickup(BREAD, bread_at)
	# A memory: one house stands again, whole.
	var mem := MemoryFlash.new()
	mem.name = "Memory"
	mem.position = MEMORY_HOUSE
	mem.present_only = smoke_all
	var focus := Marker3D.new()
	focus.position = Vector3(0, 1.3, 0)
	mem.add_child(focus)
	var ghost := Node3D.new()
	var walls := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(5.0, 2.6, 4.0)
	walls.mesh = wm
	walls.position = Vector3(0, 1.3, 0)
	ghost.add_child(walls)
	var roof := MeshInstance3D.new()
	var rm := PrismMesh.new()
	rm.size = Vector3(4.4, 1.5, 5.6)
	roof.mesh = rm
	roof.position = Vector3(0, 3.35, 0)
	roof.rotation.y = PI * 0.5
	ghost.add_child(roof)
	mem.add_child(ghost)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(18, 3, 12)
	shape.shape = bs
	shape.position = Vector3(5, 1.5, 0)
	mem.add_child(shape)
	mem.ghost = ghost
	mem.focus = focus
	village.add_child(mem)


## The mouth of the remembered house's stove, turned to the street: soot
## inside, and on its floor the bread (docs/ARCHITECTURE.md, "Голод и хлеб").
## Returns where the bread lies.
func _oven_mouth(stove: CSGBox3D) -> Vector3:
	var mouth := _box(Vector3(0.55, 0.35, 0.5), Vector3(0.575, 0.075, -0.2), "charred", false, 0.0, stove)
	mouth.operation = CSGShape3D.OPERATION_SUBTRACTION
	return stove.position + Vector3(0.52, -0.06, -0.2)


func _checkpoint_and_field() -> void:
	var cp := Node3D.new()
	cp.name = "Checkpoint"
	add_child(cp)
	# Barricade across the road and the strip west of it.
	_box(Vector3(18.6, 1.3, 0.6), Vector3(-3.7, 0.65, -62), "wood", true, 0.0, cp)
	# Hedge between the road and the field: the sentries cannot see past it.
	_box(Vector3(1.2, 2.0, 42), Vector3(5.5, 1.0, -61), "hedge", true, 0.0, cp)
	# Tripwires in the field (x 7..29, z -44..-82); a crouching boy sees them.
	var field := Node3D.new()
	field.name = "Minefield"
	add_child(field)
	var wires := [
		[Vector3(8.5, 0, -47), 0.3, 3.5], [Vector3(15, 0, -50), -0.6, 4.0],
		[Vector3(22, 0, -53), 1.2, 3.0], [Vector3(10, 0, -58), 1.6, 3.5],
		[Vector3(18, 0, -62), 0.1, 4.5], [Vector3(25, 0, -66), -1.0, 3.5],
		[Vector3(9, 0, -69), -0.4, 4.0], [Vector3(16, 0, -73), 0.9, 3.5],
		[Vector3(23, 0, -77), 0.2, 4.0], [Vector3(12, 0, -80), -1.3, 3.0],
	]
	for w in wires:
		var mine := TripwireMine.new()
		mine.position = w[0]
		mine.rotation.y = w[1]
		mine.length = w[2]
		field.add_child(mine)
	# A dead horse-cart in the field: cover, and a bandage on it.
	_box(Vector3(1.6, 0.8, 2.8), Vector3(19, 0.4, -57), "charred", true, 0.5, field)
	_pickup(BANDAGE, Vector3(19, 0.85, -57))


## Barbed wire across the north end of the field, thicket to thicket
## (docs/ARCHITECTURE.md, "Рана и бинт"). The way on is the road, left open
## in the wire right by the camp guard's beat - his torch, his dog - or a
## gap dug under the wire by the field (WireGap), where the barbs tear the
## boy's arm and he goes on bleeding. Placed for the game.
func _field_wire() -> void:
	var fence := Node3D.new()
	fence.name = "FieldWire"
	add_child(fence)
	for seg in [[-13.6, -ROAD_OPENING], [ROAD_OPENING, 31.6]]:
		var a := Vector3(seg[0], 0, FIELD_WIRE_Z)
		var b := Vector3(seg[1], 0, FIELD_WIRE_Z)
		var len := b.x - a.x
		var mid := (a + b) * 0.5
		var n := maxi(int(len / 2.5), 1)
		for i in n + 1:
			var post := a.lerp(b, float(i) / n)
			if absf(post.x - WIRE_GAP_X) < 0.9:
				continue  # no post in the way of the gap
			_box(Vector3(0.1, 1.3, 0.1), post + Vector3.UP * 0.65, "wood", true, 0.0, fence)
		for h in [0.3, 0.65, 1.0, 1.25]:
			_box(Vector3(len, 0.02, 0.02), mid + Vector3.UP * h, "wire", false, 0.0, fence)
		# Wire cannot be climbed: an invisible wall, seen and heard through.
		_invisible(_box(Vector3(len, 2.6, 0.3), mid + Vector3.UP * 1.3, "wire", true, 0.0, fence))
	# The gap: the earth scraped out under the lowest strand.
	_surface(_box(Vector3(0.9, 0.02, 1.4), Vector3(WIRE_GAP_X, 0.011, FIELD_WIRE_Z), "ash", false, 0.0, fence))
	var gap := WireGap.new()
	gap.name = "WireGap"
	gap.position = Vector3(WIRE_GAP_X, 0, FIELD_WIRE_Z)
	fence.add_child(gap)
	var stack := _box(Vector3(2.2, 1.7, 2.2), GAP_STACK + Vector3.UP * 0.85, "hedge", true, 0.3, fence)
	stack.name = "GapStack"


func _camp() -> void:
	var camp := Node3D.new()
	camp.name = "Camp"
	add_child(camp)
	# Fence: posts and wire along x = -5 (road side) and across at both ends.
	var lines := [[Vector3(-5, 0, -86), Vector3(-5, 0, -118)],
			[Vector3(-5, 0, -86), Vector3(-13, 0, -86)],
			[Vector3(-5, 0, -118), Vector3(-13, 0, -118)]]
	for l in lines:
		var a: Vector3 = l[0]
		var b: Vector3 = l[1]
		var n := int(a.distance_to(b) / 2.5)
		for i in n + 1:
			var p := a.lerp(b, float(i) / n)
			_box(Vector3(0.14, 2.6, 0.14), p + Vector3.UP * 1.3, "wood", true, 0.0, camp)
		var mid := (a + b) * 0.5
		var len := a.distance_to(b)
		var rot := atan2(b.x - a.x, b.z - a.z) + PI * 0.5
		for h in [0.5, 1.1, 1.7, 2.3]:
			_box(Vector3(len, 0.02, 0.02), mid + Vector3.UP * h, "wire", false, rot, camp)
		# The wire is a barrier: an invisible wall the boy cannot climb.
		_invisible(_box(Vector3(len, 2.6, 0.1), mid + Vector3.UP * 1.3, "wire", true, rot, camp))
	# Barracks behind the fence.
	for z in [-92.0, -102.0, -112.0]:
		_box(Vector3(5, 2.6, 8), Vector3(-10, 1.3, z), "wood", true, 0.0, camp).add_to_group(Stealth.SOUND_WALLS)
	var tower := SearchlightTower.new()
	tower.name = "Tower"
	tower.position = Vector3(-7.5, 0, -100)
	tower.rotation.y = -PI * 0.5  # sweeps east: across the road and the field
	camp.add_child(tower)
	# Cover in the field east of the road: haystacks and a stone heap.
	for c in [Vector3(9, 0, -92), Vector3(16, 0, -99), Vector3(7, 0, -107),
			Vector3(20, 0, -110), Vector3(12, 0, -116)]:
		_box(Vector3(2.2, 1.7, 2.2), c + Vector3.UP * 0.85, "hedge", true, 0.3, camp)


func _gallows() -> void:
	var g := Node3D.new()
	g.name = "Gallows"
	g.position = Vector3(4.5, 0, -128)
	add_child(g)
	_box(Vector3(0.22, 3.4, 0.22), Vector3(-1.4, 1.7, 0), "wood", true, 0.0, g)
	_box(Vector3(0.22, 3.4, 0.22), Vector3(1.4, 1.7, 0), "wood", true, 0.0, g)
	_box(Vector3(3.2, 0.22, 0.22), Vector3(0, 3.35, 0), "wood", true, 0.0, g)
	# Ropes, empty. No bodies: the place says enough (CLAUDE.md, 6.4).
	for x in [-0.7, 0.0, 0.7]:
		_box(Vector3(0.03, 0.9, 0.03), Vector3(x, 2.8, 0), "rope", false, 0.0, g)
	# The sign on the post. Its text is a historical document - only the
	# author enters it (ref text_status "pending"); the board stays blank.
	_box(Vector3(0.7, 0.45, 0.03), Vector3(-1.4, 1.6, 0.14), "board", false, 0.0, g)
	var sight := DreadSight.new()
	sight.name = "Sight"
	sight.position = Vector3(0, 2.2, 0.6)
	g.add_child(sight)
	# Crossroads.
	_surface(_box(Vector3(60, 0.02, 4), Vector3(9, 0.01, -128), "road", false))


## Distant gunfire beyond the camp, east over the fields and north past the
## forest (GunfireAmbience): heard, never seen.
func _gunfire() -> void:
	var g := GunfireAmbience.new()
	g.name = "Gunfire"
	add_child(g)
	for p in [Vector3(-95, 0, -105), Vector3(115, 0, -60), Vector3(30, 0, -290)]:
		var m := Marker3D.new()
		m.position = p
		g.add_child(m)


func _forest() -> void:
	for z in [-152.0, -156.0, -160.0]:
		for x in range(-12, 32, 3):
			_cyl(0.32, 10.0, Vector3(x + fmod(z, 2.0), 0, z), "bark")
