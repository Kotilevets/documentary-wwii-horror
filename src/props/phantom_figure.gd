class_name PhantomFigure
extends Node3D
## Panic lies to the eye as well as to the ear (docs/ARCHITECTURE.md, "Фигура
## краем глаза"; the ear - PhantomSounds). Above `threshold` an ordinary thing
## by the road - a coat hung on a post, a tall stump, a burnt beam - is seen
## at the edge of the view as a soldier standing there, turned to the boy,
## drawn the way fear draws them (the enemies' distortion shader). Looked at
## straight - or come up to - it is the post again.
##   It shows up only while no part of the place is in the boy's view - not
##   the thing, not the figure as panic draws it, stretched up to its head;
##   behind something counts as out of view - so he never sees it appear.
##   One at a time in a level; after one is seen through the place keeps
##   quiet for a while, and so do the others.
##   A cut takes it away at once: safety or a memory begins (sepia), or a
##   document is in his hands - the picture changes anyway.
##   Only the boy sees it: no body, no noise, no light, nothing for Stealth,
##   enemies or the navmesh; it does not move panic either - fear must not
##   feed itself in a loop. No red on it: no armband, no gorget, no mask.

signal appeared
## `looked`: seen through (looked at straight or come up to); false - gone
## unseen when the panic eased, or cut away.
signal dispelled(looked: bool)

enum Disguise { COAT_ON_POST, STUMP, BURNT_BEAM, NONE }

const GROUP := "phantom_figures"
const ENEMY := preload("res://src/ai/enemy.tscn")
## Parts of an enemy that are red or mark a kind; never on the figure. Red is
## also stripped by its shader, whatever the part is called.
const MARK_PARTS: Array[String] = ["Armband", "Gorget", "PlasterMask", "Cap"]
const RED_SHADER := "res://src/rendering/shaders/enemy_insignia.gdshader"
## The top of the helmet before distortion (enemy.tscn: Helmet).
const HELMET_TOP := 1.82
## Half the width of the place across the view: the widest thing (the
## beam's crossbar) and the figure's arms, with a margin.
const HALF_WIDTH := 0.6
## Points over the place that count for "seen": rows from the feet up to the
## head as the strongest panic would draw it, columns across the view.
const ROWS := 9
const COLUMNS := 5
## Points on the figure's axis for "looked at straight".
const AXIS_POINTS := 8
## The world and doors hide the place; people and see-through things do not.
const SIGHT_MASK := 1 | 16
## Fear drew it, and it stays drawn so: never more ordinary than this, even
## when the panic eases while he keeps it at the edge of the view.
const MIN_DRAWN := 0.5

@export var disguise: Disguise = Disguise.COAT_ON_POST
@export var threshold: float = 0.5
## Below this panic a figure nobody is looking at goes away.
@export var release: float = 0.35
@export var near: float = 6.0
@export var far: float = 35.0
## Closer than this the illusion does not hold.
@export var too_close: float = 2.5
@export var look_angle_deg: float = 10.0
@export var cooldown: float = 25.0
## After a figure is seen through, the other places in the level wait this
## long: no run of figures at every turn of the head.
@export var level_quiet: float = 20.0
## Chance to show up each time it could; a miss waits a few seconds.
@export_range(0.0, 1.0) var chance: float = 0.7

var shown := false
## The ordinary thing (null for Disguise.NONE).
var thing: GeometryInstance3D
## What panic makes of it.
var figure: Node3D

var _cool := 0.0
var _check := 0.0
var _rng := RandomNumberGenerator.new()
var _parts: Array[GeometryInstance3D] = []
## Frames (`-- --show-phantoms`): every figure stands from the start and is
## not seen through - to look at it, not to play.
var _always := false


func _ready() -> void:
	add_to_group(GROUP)
	# A document in the hands pauses the game; the figure must still go.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	thing = _build_thing()
	if thing != null:
		add_child(thing)
	figure = _build_figure()
	add_child(figure)
	figure.visible = false
	_always = OS.get_cmdline_user_args().has("--show-phantoms")


func _process(delta: float) -> void:
	var p := Stealth.player as Player
	if p == null or not is_instance_valid(p) or not p.is_inside_tree():
		if shown:
			_hide_figure(false)
		return
	if _always:
		if not shown:
			_show_figure(p)
		_keep_drawn()
		return
	if shown and _cut():
		_hide_figure(false)
		return
	if get_tree().paused:
		return
	_cool = maxf(_cool - delta, 0.0)
	var cam := p.camera
	if shown:
		_keep_drawn()
		var d := cam.global_position.distance_to(global_position)
		if d < too_close or looked_at(cam):
			_hide_figure(true)
		elif not _holds() and not in_view(cam):
			_hide_figure(false)
		return
	if _cool > 0.0 or not _holds() or PanicSystem.level < threshold:
		return
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.25
	try_show(p)


## Shows the figure if it may: panic, distance, nobody else shown, the place
## not in view. Returns whether it did (tests call it directly).
func try_show(p: Player) -> bool:
	if shown or _cool > 0.0 or PanicSystem.level < threshold or not _holds():
		return false
	for other in get_tree().get_nodes_in_group(GROUP):
		if other != self and (other as PhantomFigure).shown:
			return false
	var cam := p.camera
	var d := cam.global_position.distance_to(global_position)
	if d < near or d > far or in_view(cam):
		return false
	if _rng.randf() > chance:
		_cool = 4.0
		return false
	_show_figure(p)
	return true


## Is any part of the place in the camera's view with nothing in between?
## The place is the thing and the figure as the strongest panic would draw
## it (taller than the thing), across the view; the thing itself does not
## hide the place - it is the place.
func in_view(cam: Camera3D) -> bool:
	var across := (global_position - cam.global_position).cross(Vector3.UP)
	across = across.normalized() if across.length() > 0.001 else Vector3.RIGHT
	var top := drawn_height(HELMET_TOP, 1.0)
	for r in ROWS:
		var y := lerpf(0.05, top, float(r) / float(ROWS - 1))
		for c in COLUMNS:
			var s := lerpf(-HALF_WIDTH, HALF_WIDTH, float(c) / float(COLUMNS - 1))
			var point := global_position + Vector3.UP * y + across * s
			if cam.is_position_in_frustum(point) and _clear_sight(cam, point):
				return true
	return false


## Looked at straight: a point of the figure's axis as it is drawn now - from
## the feet to the top of the stretched head - within `look_angle_deg` of the
## middle of the view, nothing in between.
func looked_at(cam: Camera3D) -> bool:
	var from := cam.global_position
	var ahead := -cam.global_transform.basis.z
	var top := drawn_height(HELMET_TOP, drawn_distortion())
	var limit := deg_to_rad(look_angle_deg)
	for i in AXIS_POINTS:
		var point := global_position + Vector3.UP * lerpf(0.1, top, float(i) / float(AXIS_POINTS - 1))
		var to := point - from
		if to.length() < 0.01:
			return true
		if ahead.angle_to(to) <= limit and _clear_sight(cam, point):
			return true
	return false


## How strongly the figure is drawn: as panic draws the enemies, but never
## weaker than MIN_DRAWN.
func drawn_distortion() -> float:
	return maxf(clampf(Perception.distortion, 0.0, 1.0), MIN_DRAWN)


## How high a point of the body `h` above the feet is drawn at distortion `d`
## (enemy_distort.gdshaderinc, dix_distort_world; Enemy.drawn_point).
static func drawn_height(h: float, d: float) -> float:
	var head := smoothstep(1.35, 1.6, h)
	return h * (1.0 + 0.55 * d) + head * (h - 1.35) * 1.1 * d


## Panic may keep a figure: high enough, and no cut.
func _holds() -> bool:
	return PanicSystem.level >= release and not _cut()


## A cut in the picture: safety or a memory begins (sepia), or a document is
## in his hands (no distortion then: the figure would be an ordinary man).
func _cut() -> bool:
	return Perception.is_suppressed() or Perception.in_safe_zone() or Perception.sepia > 0.0


## Nothing but the thing between the camera and `point`: the thing standing
## there is the place being seen.
func _clear_sight(cam: Camera3D, point: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, point, SIGHT_MASK)
	var p := Stealth.player as CollisionObject3D
	if p != null:
		q.exclude = [p.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit["collider"] == thing


func _show_figure(p: Player) -> void:
	shown = true
	# Turned to the boy.
	var at := p.global_position
	at.y = global_position.y
	if at.distance_to(global_position) > 0.01:
		figure.look_at(at, Vector3.UP)
	for gi in _parts:
		gi.set_instance_shader_parameter("feet_origin", global_position)
	_keep_drawn()
	figure.visible = true
	if thing != null:
		# Gone from the view, but its shadow stays where it was.
		thing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	appeared.emit()


## The shader draws it at g_distortion * grotesque: lift grotesque so that
## the figure is never drawn weaker than MIN_DRAWN.
func _keep_drawn() -> void:
	var g := maxf(1.0, MIN_DRAWN / maxf(Perception.distortion, 0.01))
	for gi in _parts:
		gi.set_instance_shader_parameter("grotesque", g)


func _hide_figure(looked: bool) -> void:
	shown = false
	figure.visible = false
	if thing != null:
		thing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_cool = cooldown if looked else 6.0
	if is_inside_tree():
		var quiet := level_quiet if looked else 6.0
		for other in get_tree().get_nodes_in_group(GROUP):
			var f := other as PhantomFigure
			if f != self:
				f._cool = maxf(f._cool, quiet)
	dispelled.emit(looked)


## The figure: the body of a soldier as the enemies are drawn, without what
## is red or marks a kind (armband, gorget, plaster mask, cap).
func _build_figure() -> Node3D:
	var enemy := ENEMY.instantiate()
	var visual := enemy.get_node("Visual") as Node3D
	enemy.remove_child(visual)
	enemy.free()
	visual.name = "Figure"
	var strip: Array[GeometryInstance3D] = []
	for n in visual.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if MARK_PARTS.has(String(gi.name)) or is_red(gi):
			strip.append(gi)
			continue
		gi.owner = null
		# A shadow would show up in the view before the figure does.
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_parts.append(gi)
	for gi in strip:
		gi.get_parent().remove_child(gi)
		gi.free()
	visual.owner = null
	return visual


## Is this part drawn with the enemies' red (the stencil the post-process
## keeps red)?
static func is_red(gi: GeometryInstance3D) -> bool:
	var mats: Array[Material] = [gi.material_override]
	var mi := gi as MeshInstance3D
	if mi != null and mi.mesh != null:
		for s in mi.mesh.get_surface_count():
			mats.append(mi.get_active_material(s))
	for m in mats:
		var sm := m as ShaderMaterial
		if sm != null and sm.shader != null and sm.shader.resource_path == RED_SHADER:
			return true
	return false


## The ordinary thing, solid like any post: CSG on the world layer.
func _build_thing() -> GeometryInstance3D:
	if disguise == Disguise.NONE:
		return null
	var root := CSGCombiner3D.new()
	root.name = "Thing"
	root.use_collision = true
	match disguise:
		Disguise.COAT_ON_POST:
			# Broad side to local +Z: turn the node to face the way people pass.
			_part(root, Vector3(0.12, 1.8, 0.12), Vector3(0, 0.9, 0), "wood")
			_part(root, Vector3(0.66, 0.07, 0.07), Vector3(0, 1.45, 0), "wood")
			# A coat hung on the crossbar by its shoulders, hanging full.
			_part(root, Vector3(0.52, 0.95, 0.3), Vector3(0, 0.98, 0.02), "canvas")
			_part(root, Vector3(0.36, 0.3, 0.26), Vector3(0, 0.38, 0.02), "canvas")
		Disguise.STUMP:
			var stump := CSGCylinder3D.new()
			stump.radius = 0.24
			stump.height = 1.6
			stump.sides = 9
			stump.position = Vector3(0, 0.8, 0)
			stump.material = Surfaces.material("bark")
			root.add_child(stump)
			_part(root, Vector3(0.5, 0.09, 0.09), Vector3(0.28, 1.25, 0), "bark", 0.5)
		Disguise.BURNT_BEAM:
			_part(root, Vector3(0.2, 1.9, 0.2), Vector3(0, 0.95, 0), "charred")
			_part(root, Vector3(0.9, 0.16, 0.16), Vector3(0.1, 1.5, 0), "charred", -0.15)
	return root


func _part(root: Node3D, size: Vector3, pos: Vector3, mat: String, roll := 0.0) -> void:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	b.rotation.z = roll
	b.material = Surfaces.material(mat)
	root.add_child(b)
