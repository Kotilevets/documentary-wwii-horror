extends Node
## Noise bus between the player and enemies, and the player's scent trail.
## loudness: 0.15 crouch step, 0.5 walk, 1.0 sprint/gasp. Hearing radius of an
## enemy = loudness * HEARING_RANGE; through a wall or a shut door the loudness
## counts WALL_HEARING of itself (sound_walled).
## Scent: every step leaves a point; crouching does not help, only time
## (SCENT_LIFETIME) and hiding places that block the smell. Dogs follow the
## trail from older points to newer ones.
## Light (docs/ARCHITECTURE.md, "Свет и тень"): player_light, how well the
## boy can be seen now (0..1), the same for every enemy. 1 by day and in test
## worlds; a night level (LevelBase with a Moon) sets night_sight - open
## moonlight -, the moon's shadow leaves MOON_SHADOW of it, and lamps,
## torches, flares and fires add their own light (light_at).

signal noise_emitted(position: Vector3, loudness: float, source: Node)

const HEARING_RANGE := 14.0
## Through a log wall or a shut door an enemy hears a sound as if it were
## this much as loud: the radius he hears it in shrinks by as much
## (docs/ARCHITECTURE.md, "Слух сквозь стены").
const WALL_HEARING := 0.5
## What stops sound, for enemies' ears and for the boy's alike
## (src/audio/sound_walls.gd): the walls of buildings (group SOUND_WALLS)
## and shut doors; one room has no walls in it.
const SoundWalls := preload("res://src/audio/sound_walls.gd")
const SOUND_WALLS := SoundWalls.GROUP
const SOUND_HEIGHTS := SoundWalls.HEIGHTS
const SCENT_LIFETIME := 40.0
## Blood (Wound): a dog smells it far longer than a step.
const BLOOD_LIFETIME := 150.0
const SCENT_SPACING := 1.0
## Enough for BLOOD_LIFETIME of walking while bleeding (a drop every 1.4 m
## besides the steps); dead points go first (_trim_trail).
const SCENT_MAX_POINTS := 400
## Physics layer 6: barriers you see through (barbed wire). They stop the
## player and enemies (and the navmesh) but not sight rays (mask 1 | doors).
const SEE_THROUGH_LAYER := 1 << 5

var player: Node3D = null
## True only while an action noise is being emitted (emit_action_noise).
var noise_is_action := false
## Game time in seconds (scaled by Engine.time_scale, stops on pause).
var clock: float = 0.0
## Oldest first: {"pos": Vector3, "time": float, "seq": int}.
var scent_trail: Array[Dictionary] = []
var _seq := 0
## Act III: the boy walks openly with a pass. While cover is on, enemies do
## not grow suspicious of him (sight or footsteps) unless he is inside a
## restricted area (RestrictedZone: a depot yard).
var cover := false
## Set every frame by the Act III level while the boy stares at something
## military: a soldier who sees it grows suspicious even under cover
## (slower, STARING_RATE of the usual rate).
var staring := false
const STARING_RATE := 0.5
var _restricted := 0

## In the moon's shadow (a wall, a roof, a tree between him and the moon):
## this share of the open moonlight is left.
const MOON_SHADOW := 0.45
## Light energy x brightness of its colour that lights him fully up close.
const LIGHT_FULL := 1.0
const LIGHT_INTERVAL := 0.1
## How often the scene is searched for lamps, torches and flares.
const LIGHT_SCAN := 0.5
const SHADOW_RAY := 80.0
const LIGHT_MASK := 1 | 16  # the world and doors throw shadows; people do not
const KNEES := 0.45
## 1 = day: light does not matter. A night level sets it below 1.
var night_sight := 1.0
var moon: DirectionalLight3D = null
var player_light := 1.0
var _lights: Array[Light3D] = []
var _light_wait := 0.0
var _scan_wait := 0.0


func _process(delta: float) -> void:
	clock += delta


func _physics_process(delta: float) -> void:
	if night_sight >= 1.0:
		player_light = 1.0
		return
	_scan_wait -= delta
	if _scan_wait <= 0.0:
		_scan_wait = LIGHT_SCAN
		_scan_lights()
	_light_wait -= delta
	if _light_wait <= 0.0:
		_light_wait = LIGHT_INTERVAL
		update_light()


## Night: `sight` - how well he is seen in open moonlight (0..1).
func set_night(sight: float, moon_light: DirectionalLight3D) -> void:
	night_sight = clampf(sight, 0.0, 1.0)
	moon = moon_light
	_scan_wait = 0.0
	_light_wait = 0.0
	_scan_lights()
	update_light()


func set_day() -> void:
	night_sight = 1.0
	moon = null
	player_light = 1.0
	_lights.clear()


## Measures player_light now (tests call it after moving him).
func update_light() -> void:
	if night_sight >= 1.0:
		player_light = 1.0
		return
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		player_light = night_sight
		return
	var head := player.get_node_or_null("Head") as Node3D
	var top := head.global_position if head != null else player.global_position + Vector3.UP * 1.3
	# Light on any part of him gives him away: his shoulders, or his knees in
	# a torch beam aimed at the ground ahead. Leaning out, the shoulders stay
	# half as far out as the head (Player.shoulders).
	var shoulders: Vector3 = player.call("shoulders") if player.has_method("shoulders") else top - Vector3.UP * 0.25
	player_light = maxf(light_at(shoulders), light_at(player.global_position + Vector3.UP * KNEES))


## How lit `point` is for an enemy's eyes, 0..1.
func light_at(point: Vector3) -> float:
	if night_sight >= 1.0:
		return 1.0
	var world := get_viewport().find_world_3d()
	if world == null:
		return night_sight
	var space := world.direct_space_state
	var base := night_sight
	if moon != null and is_instance_valid(moon) and moon.is_inside_tree() \
			and _blocked(space, point, point + moon.global_transform.basis.z * SHADOW_RAY):
		base *= MOON_SHADOW
	var dark := 1.0 - base
	for l in _lights:
		if is_instance_valid(l) and l.is_inside_tree() and l.is_visible_in_tree():
			dark *= 1.0 - _light_of(space, l, point)
	return clampf(1.0 - dark, 0.0, 1.0)


## One lamp, torch, flare or fire on `point`: brighter near, nothing past its
## reach, outside its beam or behind a wall.
func _light_of(space: PhysicsDirectSpaceState3D, l: Light3D, point: Vector3) -> float:
	if l.light_energy <= 0.01:
		return 0.0
	var from := l.global_position
	var to := point - from
	var d := to.length()
	var reach := (l as OmniLight3D).omni_range if l is OmniLight3D else (l as SpotLight3D).spot_range
	if d >= reach:
		return 0.0
	var cone := 1.0
	if l is SpotLight3D and d > 0.01:
		var a := rad_to_deg((-l.global_transform.basis.z).angle_to(to / d)) / (l as SpotLight3D).spot_angle
		if a >= 1.0:
			return 0.0
		cone = 1.0 - smoothstep(0.6, 1.0, a)
	var c := l.light_color
	var bright := minf(l.light_energy * (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) / LIGHT_FULL, 1.0)
	var k := bright * sqrt(1.0 - d / reach) * cone
	if k <= 0.01 or (d > 0.05 and _blocked(space, from, point)):
		return 0.0
	return k


func _blocked(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	return not space.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, LIGHT_MASK)).is_empty()


func _scan_lights() -> void:
	_lights.clear()
	var root := get_tree().current_scene
	if root == null:
		return
	for n in root.find_children("*", "Light3D", true, false):
		if n is OmniLight3D or n is SpotLight3D:
			_lights.append(n as Light3D)


func enter_restricted() -> void:
	_restricted += 1


func exit_restricted() -> void:
	_restricted = maxi(_restricted - 1, 0)


func in_restricted() -> bool:
	return _restricted > 0


## Whether enemies may grow suspicious of the player right now.
func exposed() -> bool:
	return not cover or _restricted > 0


func reset_cover() -> void:
	cover = false
	staring = false
	_restricted = 0


func emit_noise(position: Vector3, loudness: float, source: Node = null) -> void:
	noise_emitted.emit(position, loudness, source)


## The noise of a thing done (a door, the cellar lid, the wardrobe, hay -
## docs/ARCHITECTURE.md, "Шум от действий"): heard plainly, with no wall or
## shut door between, it makes an enemy at least suspicious and he comes to
## look (Enemy._on_noise); through a wall it only adds up like a step.
## Listeners see noise_is_action == true while it is being emitted.
func emit_action_noise(position: Vector3, loudness: float, source: Node = null) -> void:
	noise_is_action = true
	noise_emitted.emit(position, loudness, source)
	noise_is_action = false


## Does an enemy (`listener`, ears at `ear_height`) hear a sound made at
## `position` through a wall (docs/ARCHITECTURE.md, "Слух сквозь стены")?
## SoundWalls.walled: not within one room (a stove, a table, an open door
## leaf, a boy in the cellar or behind the stove); otherwise a wall of a
## building or a shut door at every one of SOUND_HEIGHTS. A dog's low ear is
## taken at the top height, so a crate between him and the boy is no wall.
func sound_walled(listener: Node3D, ear_height: float, position: Vector3, exclude: Array[RID] = []) -> bool:
	var feet := listener.global_position
	return SoundWalls.walled(_space(), get_tree(), feet, feet + Vector3.UP * ear_height, position, exclude)


## A wall or a shut door between an ear at `ear` and a sound made at
## `position` (on the ground), at every one of SOUND_HEIGHTS - rooms aside.
func walled_off(ear: Vector3, position: Vector3, exclude: Array[RID] = []) -> bool:
	for h in SOUND_HEIGHTS:
		if not sound_wall_between(ear, position + Vector3.UP * h, exclude):
			return false
	return true


## A wall of a building or a shut door between `a` and `b` (SoundWalls.between).
func sound_wall_between(a: Vector3, b: Vector3, exclude: Array[RID] = [], cut: float = SoundWalls.CUT) -> bool:
	return SoundWalls.between(_space(), a, b, exclude, cut)


func stops_sound(collider: Object) -> bool:
	return SoundWalls.stops(collider)


## The room (board floor) `point` is in, or null - out of doors, an earth floor.
func room_at(point: Vector3) -> Node:
	return SoundWalls.room_at(get_tree(), point)


func _space() -> PhysicsDirectSpaceState3D:
	var world := get_viewport().find_world_3d()
	return world.direct_space_state if world != null else null


func lay_scent(position: Vector3) -> void:
	# Standing still keeps the spot fresh - a step's, never a drop's (a drop
	# lives from when it fell).
	if not scent_trail.is_empty() and not scent_trail[-1].get("blood", false) \
			and (scent_trail[-1]["pos"] as Vector3).distance_to(position) < SCENT_SPACING:
		scent_trail[-1]["time"] = clock
		return
	_seq += 1
	scent_trail.append({"pos": position, "time": clock, "seq": _seq})
	_trim_trail()


## The boy climbing into a hiding place by himself (HideSpot.interact): his
## trail runs on to where he stood and into the place. Steps are laid a metre
## apart (SCENT_SPACING), and without these two points the trail would end up
## to a metre short of where he climbed in: a dog on it would stop there and
## sniff the place from farther than it should (docs/ARCHITECTURE.md, "Враги",
## the trail; "Дверь открыта в прологе"). The point in the place is marked
## "into": from where his hand reached it the place may be a little over
## Dog.MAX_TRAIL_GAP away (the hay from the far edge of reach), and the
## trail must not break there.
func scent_into(stood: Vector3, place: Vector3) -> void:
	for pos: Vector3 in [stood, place]:
		if not scent_trail.is_empty() and not scent_trail[-1].get("blood", false) \
				and (scent_trail[-1]["pos"] as Vector3).is_equal_approx(pos):
			scent_trail[-1]["time"] = clock
			continue
		_seq += 1
		scent_trail.append({"pos": pos, "time": clock, "seq": _seq})
	scent_trail[-1]["into"] = true
	_trim_trail()


## A drop of blood (Wound.drop): a point of the same trail, laid apart from
## the steps (never merged with one), that lives BLOOD_LIFETIME and that a
## dog picks up from farther (Dog.blood_pickup_radius, blood_near).
func lay_blood(position: Vector3) -> void:
	_seq += 1
	scent_trail.append({"pos": position, "time": clock, "seq": _seq, "blood": true})
	_trim_trail()


## Over SCENT_MAX_POINTS: the cold points go first, then the oldest.
func _trim_trail() -> void:
	if scent_trail.size() <= SCENT_MAX_POINTS:
		return
	scent_trail.assign(scent_trail.filter(scent_live))
	while scent_trail.size() > SCENT_MAX_POINTS:
		scent_trail.pop_front()


## Is a trail point still there to smell?
func scent_live(pt: Dictionary) -> bool:
	var life := BLOOD_LIFETIME if pt.get("blood", false) else SCENT_LIFETIME
	return clock - float(pt["time"]) <= life


## The freshest live scent point within `radius` of `position`, or {}.
func freshest_scent_near(position: Vector3, radius: float) -> Dictionary:
	for i in range(scent_trail.size() - 1, -1, -1):
		var pt: Dictionary = scent_trail[i]
		if scent_live(pt) and (pt["pos"] as Vector3).distance_to(position) < radius:
			return pt
	return {}


## The freshest live drop of blood within `radius` of `position`, or {}.
func blood_near(position: Vector3, radius: float) -> Dictionary:
	for i in range(scent_trail.size() - 1, -1, -1):
		var pt: Dictionary = scent_trail[i]
		if pt.get("blood", false) and scent_live(pt) \
				and (pt["pos"] as Vector3).distance_to(position) < radius:
			return pt
	return {}


## The next live point laid after point number `seq`, or {} at the end.
func scent_after(seq: int) -> Dictionary:
	for pt in scent_trail:
		if int(pt["seq"]) > seq and scent_live(pt):
			return pt
	return {}


func clear_scent() -> void:
	scent_trail.clear()
