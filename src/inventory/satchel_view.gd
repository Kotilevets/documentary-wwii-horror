class_name SatchelView
extends Node3D
## Diegetic inventory: the satchel is opened (Tab) and its contents are laid
## out as 3D objects in front of the camera. No text, no icons; all items are
## blue-green because they are interactive.
##   In a hiding place the slits are drawn over the whole view, so there he
## looks into the satchel instead of out through the gaps: the camera shows
## only LAYER (Player._update_rummage) - he cannot watch the room meanwhile.
## A little grey light from the gaps falls on his hands; behind, the dark.
##   One thing is picked (left / right - the strafe keys): it lies closer and
## higher than the rest. "Use" (the interact key) uses it (Player.use_item):
## a document is read, bread eaten; what is no use now is shaken - no text.
## Several of a kind lie as a little stack.

const SPACING := 0.16
## Render layer of the satchel and its things (layer 20) - see the header.
const LAYER := 1 << 19
## How many of a kind are shown in a stack at most.
const STACK_SHOWN := 3

var is_open := false
## Index of the picked thing in Inventory.items().
var selected := 0

## One holder per kind of thing, in the order of Inventory.items().
var _holders: Array[Node3D] = []
var _shake: Tween = null
## Shown only while rummaging in a hiding place (set_rummaging).
var _glow: OmniLight3D
var _dark: MeshInstance3D


func _ready() -> void:
	Inventory.changed.connect(_on_inventory_changed)
	_glow = OmniLight3D.new()
	_glow.name = "GapLight"
	_glow.position = Vector3(0.0, 0.35, 0.05)
	_glow.omni_range = 1.0
	_glow.light_energy = 0.12
	_glow.light_cull_mask = LAYER
	_glow.layers = LAYER
	_glow.visible = false
	add_child(_glow)
	_dark = MeshInstance3D.new()
	_dark.name = "Dark"
	var quad := QuadMesh.new()
	quad.size = Vector2(8.0, 6.0)
	_dark.mesh = quad
	_dark.position = Vector3(0.0, 0.0, -2.0)
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color.BLACK
	_dark.material_override = black
	_dark.layers = LAYER
	_dark.visible = false
	add_child(_dark)


## In a hiding place he looks into the satchel (Player._update_rummage): the
## light from the gaps on his hands, the dark behind.
func set_rummaging(on: bool) -> void:
	if _glow != null:
		_glow.visible = on
		_dark.visible = on


## Held low in the view whatever the FOV: panic narrows it (tunnel vision),
## and the satchel must not slip out of the bottom of the frame.
func _process(_delta: float) -> void:
	var cam := get_parent() as Camera3D
	if is_open and cam != null:
		position.y = -absf(position.z) * tan(deg_to_rad(cam.fov) * 0.5) * 0.65


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	is_open = true
	_rebuild()
	visible = true


func close() -> void:
	is_open = false
	visible = false
	_clear()


## Picks the next thing to the right (`dir` 1) or left (-1), round the end.
func select_step(dir: int) -> void:
	var n := _holders.size()
	if n == 0:
		return
	selected = wrapi(selected + dir, 0, n)
	_place()


func selected_item() -> ItemData:
	var items := Inventory.items()
	if items.is_empty():
		return null
	return items[clampi(selected, 0, items.size() - 1)]


## The picked thing is of no use now: it is shaken, like a head.
func refuse() -> void:
	if selected >= _holders.size():
		return
	var h := _holders[selected]
	if _shake != null:
		_shake.kill()
	h.rotation.y = 0.0
	_shake = create_tween()
	for a in [0.25, -0.25, 0.15, 0.0]:
		_shake.tween_property(h, "rotation:y", a, 0.07)


func _on_inventory_changed() -> void:
	if is_open:
		_rebuild()


func _clear() -> void:
	if _shake != null:
		_shake.kill()
		_shake = null
	for c in get_children():
		if c == _glow or c == _dark:
			continue
		remove_child(c)
		c.queue_free()
	_holders.clear()


func _rebuild() -> void:
	_clear()
	var cloth := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.7, 0.32)
	cloth.mesh = plane
	cloth.rotation_degrees.x = 60.0
	cloth.position = Vector3(0, -0.04, 0)
	var cloth_mat := StandardMaterial3D.new()
	cloth_mat.albedo_color = Color(0.2, 0.2, 0.2)
	cloth.material_override = cloth_mat
	cloth.layers = LAYER
	add_child(cloth)

	var items := Inventory.items()
	for i in items.size():
		var item := items[i]
		var holder := Node3D.new()
		holder.name = "Item_" + item.id
		add_child(holder)
		_holders.append(holder)
		for k in mini(Inventory.count(item.id), STACK_SHOWN):
			var mi := MeshInstance3D.new()
			mi.mesh = item.mesh if item.mesh != null else BoxMesh.new()
			mi.scale = Vector3.ONE * 0.6
			# A stack: each one a little higher and further back.
			mi.position = Vector3(0.012 * k, 0.03 * k, -0.02 * k)
			mi.rotation_degrees = Vector3(60.0, 12.0 * (i % 3 - 1) + 7.0 * k, 0.0)
			mi.layers = LAYER
			holder.add_child(mi)
			ColorMask.apply(mi, ColorMask.Channel.INTERACTIVE)
	selected = clampi(selected, 0, maxi(items.size() - 1, 0))
	_place()


## Lays the holders out in a row; the picked one closer and higher.
func _place() -> void:
	var start := -SPACING * (_holders.size() - 1) * 0.5
	for i in _holders.size():
		var picked := i == selected
		_holders[i].position = Vector3(start + SPACING * i, 0.035 if picked else 0.0, 0.06 if picked else 0.02)
		_holders[i].scale = Vector3.ONE * (1.2 if picked else 1.0)
