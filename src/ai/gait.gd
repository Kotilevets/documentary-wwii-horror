class_name Gait
extends Node
## Walk of an enemy or a dog (docs/ARCHITECTURE.md, "Шаги и походка").
## Legs and arms swing in step with the distance actually covered, so a
## figure that a scene moves by hand (the dream) walks too, and one held by
## a table or a wall does not tread on the spot. Every footfall is heard:
## boots on the ground, a hollow knock on boards (BoardFloor) and now and
## then a creak, light paws for a dog. The boy hears them coming while he
## hides; the enemies do not take them for his noise (Stealth is not told).
## Boots on the boards over a cellar shed dust on him
## (Player.boards_overhead).

signal stepped(at: Vector3, on_boards: bool)

enum Body { HUMAN, DOG }

## Footfalls farther than this from the boy are not played (saves players;
## they would be inaudible anyway).
const HEAR_RADIUS := 32.0
## A jump longer than this in one frame is a teleport, not a walk.
const TELEPORT := 1.0
## Below this speed (m/s) he is standing, not walking.
const STAND_SPEED := 0.25
## A step on boards that also creaks.
const CREAK_CHANCE := 0.35

## Distance per footfall and swing of the legs (rad) at walk and run.
const HUMAN := {"stride": [0.7, 1.15], "swing": [0.32, 0.62], "arm": 0.75, "bob": [0.02, 0.045]}
const DOG := {"stride": [0.45, 0.9], "swing": [0.4, 0.75], "arm": 0.0, "bob": [0.012, 0.03]}

var body: Body = Body.HUMAN
var walk_speed := 1.3
var run_speed := 3.4
## Footfalls so far (tests, debug).
var steps := 0
## Current swing of the legs, rad (0 = standing).
var swing := 0.0
## Smoothed horizontal speed, m/s.
var speed := 0.0

var _host: Node3D
var _visual: Node3D
var _visual_rest := Vector3.ZERO
var _limbs: Array[Dictionary] = []
var _last := Vector3.ZERO
var _has_last := false
var _phase := 0.0
var _rested := false
var _rng := RandomNumberGenerator.new()


func setup(host: Node3D, visual: Node3D, kind: Body, walk: float, run: float) -> void:
	_host = host
	_visual = visual
	body = kind
	walk_speed = walk
	run_speed = maxf(run, walk + 0.1)
	_visual_rest = visual.position
	_limbs.clear()
	if kind == Body.HUMAN:
		_limb("LegL", 1.0, 1.0)
		_limb("LegR", -1.0, 1.0)
		_limb("ArmL", -1.0, HUMAN["arm"])
		_limb("ArmR", 1.0, HUMAN["arm"])
		# The armband is sewn on the left sleeve: it swings with that arm.
		_limb("Armband", -1.0, HUMAN["arm"], "ArmL")
	else:
		# Trot: diagonal pairs together.
		_limb("LegFL", 1.0, 1.0)
		_limb("LegBR", 1.0, 1.0)
		_limb("LegFR", -1.0, 1.0)
		_limb("LegBL", -1.0, 1.0)


## A limb swinging about the top of its own mesh (hip, shoulder), or of the
## mesh named `pivot_of`.
func _limb(node_name: String, sign_: float, scale_: float, pivot_of := "") -> void:
	var n := _visual.get_node_or_null(node_name) as Node3D
	if n == null:
		return
	var src := n
	if pivot_of != "":
		src = _visual.get_node_or_null(pivot_of) as Node3D
		if src == null:
			return
	var top := 0.0
	if src is MeshInstance3D and (src as MeshInstance3D).mesh != null:
		top = (src as MeshInstance3D).mesh.get_aabb().end.y
	var pivot := src.transform * Vector3(0, top, 0)
	_limbs.append({"node": n, "rest": n.transform, "pivot": pivot, "sign": sign_, "scale": scale_})


func _params() -> Dictionary:
	return HUMAN if body == Body.HUMAN else DOG


func _physics_process(delta: float) -> void:
	if _host == null or delta <= 0.0 or not _host.is_inside_tree():
		return
	var pos := _host.global_position
	if not _has_last:
		_last = pos
		_has_last = true
		return
	var d := Vector2(pos.x - _last.x, pos.z - _last.z).length()
	_last = pos
	if d > TELEPORT:
		return
	speed = lerpf(speed, d / delta, clampf(delta * 10.0, 0.0, 1.0))
	var p := _params()
	var run_k := clampf(inverse_lerp(walk_speed, run_speed, speed), 0.0, 1.0)
	var walking := speed >= STAND_SPEED
	var target := lerpf(p["swing"][0], p["swing"][1], run_k) if walking else 0.0
	swing = move_toward(swing, target, delta * 2.5)
	var before := floori(_phase)
	_phase += d / lerpf(p["stride"][0], p["stride"][1], run_k)
	if walking and floori(_phase) != before:
		_footfall(pos, run_k)
	_pose(p)


## Legs apart at each footfall, passing each other between them; the body
## lowest on the footfall.
func _pose(p: Dictionary) -> void:
	if swing == 0.0 and _rested:
		return
	_rested = swing == 0.0
	var c := cos(_phase * PI)
	for l in _limbs:
		var angle: float = swing * float(l["sign"]) * float(l["scale"]) * c
		var pivot: Vector3 = l["pivot"]
		(l["node"] as Node3D).transform = Transform3D(Basis(Vector3.RIGHT, angle), pivot) \
				* Transform3D(Basis(), -pivot) * (l["rest"] as Transform3D)
	var swing_max: float = p["swing"][1]
	var bob: float = lerpf(p["bob"][0], p["bob"][1], clampf(swing / swing_max, 0.0, 1.0))
	_visual.position = _visual_rest + Vector3.UP * bob * (1.0 - absf(c)) * signf(swing)


func _footfall(at: Vector3, run_k: float) -> void:
	steps += 1
	var boards := BoardFloor.at(get_tree(), at + Vector3.UP * 0.05) != null
	stepped.emit(at, boards)
	var loud := lerpf(0.6, 1.0, run_k)
	var p := Stealth.player as Node3D
	if p == null or p.global_position.distance_to(at) <= HEAR_RADIUS:
		if body == Body.DOG:
			Sfx.play_at("step_paw", at, loud)
		else:
			Sfx.play_at("step_boot_board" if boards else "step_boot", at, loud)
			if boards and _rng.randf() < CREAK_CHANCE:
				Sfx.play_at("floor_creak", at, 0.8)
	if boards and body == Body.HUMAN and p is Player:
		(p as Player).boards_overhead(at, loud)
