extends RefCounted
## A careful player for the Act II playthrough (tests/playthrough_runner.gd,
## docs/ARCHITECTURE.md, "Проходимость Акта II").
##
## He plans his way over a grid of the level (AStarGrid2D: open ground the
## searchlight can reach costs more, so does ground in anyone's sight, so the
## way hugs shadows and cover; tripwires and walls are solid; bleeding, he
## keeps off the dog's beat) and walks it with the real controls: the move
## and crouch actions, turning to where he goes, E at things, the satchel
## (Player.use_item: the bandage, the bread); he stops and looks at a thing
## till it comes (Act.LOOK: the memory, the gallows). He does not
## stop where the beam or anyone's eyes can reach: he waits in a safe place
## until the beam and every enemy on his round leave him a clear run to the
## next safe place, then goes in one go.
##
## What he knows is what a careful player can see: the beam and its rhythm
## (the tower's own clock); where each enemy is, which way he faces and the
## round he walks; the tripwires (crouched, a boy sees a wire close by; the
## bot knows them all, which only spares it the looking). He never reads
## anyone's suspicion. For the witness route (what there is to see) he also
## knows where a memory's place is and how far the gallows strike (the
## MemoryFlash zone, DreadSight.distance), and reads from them whether the
## memory is over and whether the gallows are in his eyes: a player sees
## that on the screen, the bot cannot.
##
## Act I's escape is played by the same bot (tests/act1_escaper.gd extends
## this script): what differs there - the grid, the flare's light, the
## board floor, the dog's trail, the forest - goes through the grid fields
## (gx0..ray_top) and the hooks _near, _sight and _off_limits, which here
## give Act II's numbers.

enum Posture { CROUCHED, UPRIGHT, CRAWLING }
enum Act { NONE, PICK, CRAWL, BIND, LOOK, EAT }

## The grid: x -13.75..32.25, z -150.25..11.75, half-metre cells.
const CELL := 0.5
const X0 := -13.75
const Z0 := -150.25
const W := 92
const H := 324
## His body: a cell is free when this cylinder fits there.
const BODY := 0.32
## Never this close to a tripwire.
const MINE_CLEAR := 0.65
## Crouched near the wires (he looks for them).
const MINES_NEAR := 4.0
const KNEE := 0.3
## Prediction of the beam: a margin on the drawn cone, a slack in time.
const BEAM_MARGIN := 2.5
const BEAM_SLACK := 0.3
## Planning costs: ground the beam can reach, ground in anyone's sight.
const LIT_COST := 5.0
const GUARD_COST := 4.0

## How an enemy notices him (Enemy.can_see, Enemy._on_noise; docs/ARCHITECTURE.md,
## "Враги"). Eyes: 16 m x (0.3 + 0.7 x light), the light on a boy in the open
## moon being 0.5 (Stealth.player_light) - 10.4 m - in a 40-degree half-cone
## (view_angle_deg 80), stopped by walls and the hedge. The bot keeps a metre
## and 8 degrees more and never counts on the moon shadow.
const SIGHT_RANGE := 11.4
const SIGHT_HALF := 48.0
## Ears: walking steps carry 0.5 x 14 = 7 m, crouched ones 2.1 m.
const NEAR_UPRIGHT := 7.5
const NEAR_CROUCHED := 2.5
## Upright (twice as fast) only this far from anyone's round or post.
const UPRIGHT_FROM := 8.5
## The camp guard: his torch in front, and his eyes through the camp fence
## as if it were not there.
const TORCH_RANGE := 14.5
const TORCH_HALF := 32.0
## A dog is a watcher of its own (_dog_watcher), its numbers taken from the
## Dog itself. Ears: a walking step every 0.55 s (Player._footsteps) adds
## 0.9 x 0.5 x (1 - d/R) suspicion, R = 0.5 x 14 x hearing (14 m for the camp
## dog), and suspicion fades 0.12/s (Enemy._physics_process): walking past it
## inside about 12 m, it grows. So its ears are not a ring: feasible() adds
## up what the dog would make of every step of a run, as the game does, and
## the run is off if that would pass HEARD_MAX (it turns at 0.35). Crouched,
## its nose (smell_radius) outreaches its ears, and a ring is right. Eyes:
## view_distance x 0.65 in the moon, 7.8 m, with 0.7 m more, view_angle_deg/2
## either way of where it walks - the handler's way - with 8 degrees more.
## Nothing stops its nose and ears, nor (kept wary) its eyes.
const WALK_STEP := 0.55
const FADE := 0.12
const HEARD_MAX := 0.2
const MOON := 0.5
## Where a dog at heel is (Dog._patrol): the heel point is a metre to the
## handler's right, and the dog stands still till that point is heel_distance
## off, then trots after it - so while he walks it is at the heel point or
## up to heel_distance behind it, facing his way. Where he turns about (a
## beat's ends, a round's corners) the heel point swings round him and the
## dog trots after it, then stands facing anywhere till he is off again:
## there it is anywhere within HEEL + heel_distance of him, any way. LAG is
## a margin on both. (It is back at heel some 2 s after he is off - farther
## than _dog_loose lets it be loose; a boy in what it sees then would have
## been inside its loose reach just before, so the runs stay safe. Review
## 18.11.2026.)
const HEEL := 1.0
const LAG := 0.4
## Bleeding, he keeps his drops this far from the dog's beat.
const BLOOD_CLEAR := 11.0
## Down (crouched, lying), his lines of sight are tested both to where the
## head settles in the game (CROUCH_EYE 0.65, WireGap.CRAWL_EYE 0.3) and to
## this height (the head takes ~0.3 s to get down); upright to STAND_EYE.
const LOS_CROUCHED := 0.85
## Enemies turn by lerp_angle at 6/s (Enemy._move_towards); a turn of nearly
## half a circle can go either way - every facing is counted then.
const TURN_RATE := 6.0
const AMBIGUOUS := 0.25
## The place he stops at must stay safe this long after he gets there.
const SAFE_AFTER := 6.0
const MAX_WAIT := 120.0
## Looking at something (Act.LOOK): this long at most for it to come (the
## memory, the gallows in his eyes) before the run fails.
const LOOK_MAX := 40.0
const STEP := 0.1


## One enemy as the bot watches him: his round (or post) and how far he
## notices a boy (set in _watcher).
class Watcher:
	var enemy: Enemy
	## The points of his round, in order (a round of two is a beat walked to
	## and fro); empty: he holds a post.
	var route: Array[Vector3] = []
	var sight_range := 0.0
	var sight_half := 0.0
	var torch := false
	var near_crouched := 0.0
	var near_upright := 0.0
	var upright_from := 0.0
	## Walls stop his eyes (the camp guard's are kept unstopped: see above).
	var occluded := true
	## The dog at his heel (the handler's watcher), or the dog this watcher is
	## (the dog's own: `enemy` is then the handler it follows, or itself).
	var dog: Dog = null
	## A dog at heel: how far right of the handler, and how far behind that
	## it may lag (0: watched from the enemy's own place).
	var heel := 0.0
	var heel_slack := 0.0
	## Metres more on every distance.
	var slack := 0.0
	## A dog: how far its ears take a walking step (0: a ring, near_upright).
	var hear_r := 0.0
	## A level whose light changes (Act I's flare): his view_distance and the
	## metres kept on top of it (_sight in tests/act1_escaper.gd).
	var eyes := 0.0
	var eyes_margin := 0.0

var level: Node3D
var player: Player
var tower: SearchlightTower
var gap: WireGap
var tree: SceneTree
var space: PhysicsDirectSpaceState3D
var lamp_pos := Vector3.ZERO
var watchers: Array[Watcher] = []
## The camp guard and his dog (blood and the dog's beat).
var guard: Watcher = null
## Free of walls and wires.
var blocked := PackedByteArray()
## Bits: 1 the beam can reach a crouched boy here, 2 upright, 4 crawling.
var lit_bits := PackedByteArray()
## Bits: 1 knee, 2 crouched head, 4 upright head, 16 lying head (each head
## with its shoulders, Enemy.sight_points) open to the lamp; 8 in range.
var open_bits := PackedByteArray()
## Where no enemy can ever notice a crouching boy, wherever on his round he
## is and whichever way he faces: the only places the bot stops at.
var safe := PackedByteArray()
var blood_zone := PackedByteArray()
var astar := AStarGrid2D.new()
## The grid in use: Act II's (the constants above) unless a level's bot sets
## its own before _build_grid (tests/act1_escaper.gd).
var gx0 := X0
var gz0 := Z0
var gw := W
var gh := H
## The column test of _build_grid: a ray from this high down to the knees.
var ray_top := 12.0

# --- what happened ---------------------------------------------------------------
var failed := ""
var events: Array[String] = []
var waited := 0.0
var longest_wait := 0.0
var max_exposure := 0.0
var walked := 0.0
## Seconds he stood still because somebody was up (searching, alarmed).
var frozen := 0.0
var bound := false
var crawled := false
## Documents he picked up and read.
var read: Array[String] = []
## What he stopped to look at and saw through (Act.LOOK), and whether he
## ate the bread he found.
var looked: Array[Vector3] = []
var ate := false
var noticed: Dictionary = {}  # enemy name -> worst state seen
## Enemy name -> could he see the boy on the frame he first turned (false:
## he heard or smelt him). The village controls tell eyes from ears by it.
var saw: Dictionary = {}
## Checkpoints the level saved on the way, in order (indices).
var saved: Array[int] = []
## Dog name -> the bot's own running count of what that dog has made of his
## steps (the sum feasible() makes, kept every frame as he really walks),
## and that count on the frame the dog turned. The dog-ears control checks
## the count runs ahead of the dog.
var ears: Dictionary = {}
var ears_when_turned: Dictionary = {}
## Enemy name -> the most suspicion he ever got from him (the closest call).
var peak: Dictionary = {}
var trace: PackedVector3Array = PackedVector3Array()
## Ignore the beam and the enemies (the reckless control runs).
var reckless := false
## Stop at the first enemy to turn (a control run need not go on).
var stop_when_noticed := false


func setup(lv: Node3D) -> void:
	level = lv
	tree = lv.get_tree()
	space = lv.get_world_3d().direct_space_state
	player = lv.get_node("Player") as Player
	# Act II's searchlight and wire (none in Act I).
	tower = lv.get_node_or_null("Layout/Camp/Tower") as SearchlightTower
	gap = lv.get_node_or_null("Layout/FieldWire/WireGap") as WireGap
	if tower != null:
		lamp_pos = tower.lamp.global_position
	elif gap != null:
		# Act II without its searchlight would pass "the beam never touches
		# him" with no beam at all.
		_fail("no searchlight in a level with the wire")
	for e in tree.get_nodes_in_group("enemies"):
		if not level.is_ancestor_of(e):
			continue
		if e is Dog:
			if (e as Dog).handler == null:
				watchers.append(_dog_watcher(e as Dog))
			continue
		var w := _watcher(e as Enemy)
		watchers.append(w)
		if w.dog != null:
			watchers.append(_dog_watcher(w.dog, w))
	_build_grid()
	for e in tree.get_nodes_in_group("enemies"):
		(e as Enemy).player_caught.connect(func(by: Enemy) -> void: _fail("caught by " + str(by.name)))
	for m in tree.get_nodes_in_group("mines"):
		if level.is_ancestor_of(m):
			(m as TripwireMine).detonated.connect(func(_m: TripwireMine) -> void: _fail("tripwire"))
	if tower != null:
		tower.alarm_raised.connect(func(at: Vector3) -> void: _fail("searchlight alarm at %s" % _v(at)))


func _watcher(e: Enemy) -> Watcher:
	var w := Watcher.new()
	w.enemy = e
	w.sight_range = SIGHT_RANGE
	w.sight_half = SIGHT_HALF
	w.near_crouched = NEAR_CROUCHED
	w.near_upright = NEAR_UPRIGHT
	w.upright_from = UPRIGHT_FROM
	if e.patrol_route != null and not e.hold_position:
		for c in e.patrol_route.get_children():
			w.route.append((c as Node3D).global_position)
	w.torch = e.has_torch and e.torch_on
	for d in tree.get_nodes_in_group("enemies"):
		if d is Dog and (d as Dog).handler == e:
			w.dog = d as Dog
	if w.dog != null:
		w.occluded = false
		guard = w
	return w


## The dog's own watcher: at its handler's heel (`handler`), or on a round of
## its own (no handler). See WALK_STEP above for where its numbers come from.
func _dog_watcher(dog: Dog, handler: Watcher = null) -> Watcher:
	var w := Watcher.new()
	w.dog = dog
	w.occluded = false
	if handler != null:
		w.enemy = handler.enemy
		w.route = handler.route
		w.heel = HEEL
		w.heel_slack = dog.heel_distance
		w.slack = LAG
	else:
		w.enemy = dog
		if dog.patrol_route != null and not dog.hold_position:
			for c in dog.patrol_route.get_children():
				w.route.append((c as Node3D).global_position)
		w.slack = LAG
	var walk := Player.STEP_WALK_NOISE * Stealth.HEARING_RANGE * dog.hearing
	w.hear_r = walk
	w.near_crouched = maxf(dog.smell_radius, Player.STEP_CROUCH_NOISE * Stealth.HEARING_RANGE * dog.hearing)
	# Upright, its ears are added up along each run (feasible); the ring is
	# only its nose, and he walks upright anywhere a run's sum allows. (Till
	# 18.11.2026 this read near_crouched before it was set: no nose upright.)
	w.near_upright = w.near_crouched
	w.sight_range = dog.view_distance * lerpf(Enemy.DARK_SIGHT, 1.0, MOON) + 0.7
	w.sight_half = dog.view_angle_deg * 0.5 + 8.0
	w.upright_from = w.near_upright + w.heel + w.heel_slack + w.slack + 1.0
	return w


## A dog at heel whose handler, in `pose`, is turning about or near a point
## of his round where he turns: the dog may be anywhere round him, any way.
static func _dog_loose(w: Watcher, pose: Array) -> bool:
	if bool(pose[3]) or absf(wrapf(float(pose[2]) - float(pose[1]), -PI, PI)) > 0.05:
		return true
	var g: Vector3 = pose[0]
	var r := w.heel + w.heel_slack + w.slack + 0.35
	for q in w.route:
		if Vector2(q.x - g.x, q.z - g.z).length() < r:
			return true
	return w.route.is_empty()


static func near_of(w: Watcher, posture: int) -> float:
	return w.near_upright if posture == Posture.UPRIGHT else w.near_crouched


## The farthest `w` can notice anything.
static func reach_of(w: Watcher) -> float:
	return maxf(maxf(w.sight_range, TORCH_RANGE if w.torch else 0.0), w.near_upright) \
			+ w.heel + w.heel_slack + w.slack


## Distance from `p` to the round or post of `w`, on the ground.
static func dist_to_round(w: Watcher, p: Vector3) -> float:
	if w.route.is_empty():
		var g := w.enemy.global_position
		return Vector2(p.x - g.x, p.z - g.z).length()
	var best := INF
	var n := w.route.size()
	for k in (n if n > 2 else 1):
		best = minf(best, _dist_to_segment(p, w.route[k], w.route[(k + 1) % n]))
	return best


func _fail(why: String) -> void:
	if failed == "":
		failed = why
		events.append("FAIL " + why)


# --- the grid --------------------------------------------------------------------

func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori((p.x - gx0) / CELL), floori((p.z - gz0) / CELL))


func center(c: Vector2i) -> Vector3:
	return Vector3(gx0 + (c.x + 0.5) * CELL, 0.0, gz0 + (c.y + 0.5) * CELL)


func inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < gw and c.y < gh


func idx(c: Vector2i) -> int:
	return c.y * gw + c.x


func _build_grid() -> void:
	var shape := CylinderShape3D.new()
	shape.radius = BODY
	shape.height = 0.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1 | IzbaDoor.DOOR_LAYER | Stealth.SEE_THROUGH_LAYER
	var down := PhysicsRayQueryParameters3D.new()
	down.collision_mask = q.collision_mask
	var mines: Array[TripwireMine] = []
	for m in tree.get_nodes_in_group("mines"):
		if level.is_ancestor_of(m):
			mines.append(m as TripwireMine)
	var n := gw * gh
	# Packed arrays are values: each resized by name.
	blocked.resize(n)
	lit_bits.resize(n)
	open_bits.resize(n)
	blood_zone.resize(n)
	safe.resize(n)
	blocked.fill(0)
	lit_bits.fill(0)
	open_bits.fill(0)
	blood_zone.fill(0)
	safe.fill(1)
	var poses: Array = []
	for w in watchers:
		poses.append(_round_poses(w))
	var dog_a := Vector3.ZERO
	var dog_b := Vector3.ZERO
	if guard != null:
		var beat_a := guard.route[0]
		var beat_b := guard.route[guard.route.size() - 1]
		dog_a = Vector3(beat_a.x + 1.0, 0, beat_a.z + 2.0)
		dog_b = Vector3(beat_b.x + 1.0, 0, beat_b.z - 2.0)
	for z in gh:
		for x in gw:
			var c := Vector2i(x, z)
			var i := idx(c)
			var p := center(c)
			q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.5)
			# A shape query finds a CSG mesh only from outside it (the faces
			# turned away are skipped): a cell whose centre is inside a cart,
			# a haystack or the wire's thin wall is found from above instead.
			var b := not space.intersect_shape(q, 1).is_empty()
			if not b:
				down.from = p + Vector3.UP * ray_top
				down.to = p + Vector3.UP * 0.12
				b = not space.intersect_ray(down).is_empty()
			if not b:
				for m in mines:
					if m._distance_to_wire(p) < MINE_CLEAR:
						b = true
						break
			blocked[i] = 1 if b else 0
			if guard != null:
				blood_zone[i] = 1 if _dist_to_segment(p, dog_a, dog_b) < BLOOD_CLEAR else 0
			if not b:
				for k in watchers.size():
					var w := watchers[k]
					if dist_to_round(w, p) > reach_of(w) + 1.0:
						continue
					for pose in poses[k]:
						if danger(w, p, pose, Posture.CROUCHED):
							safe[i] = 0
							break
					if safe[i] == 0:
						break
			if tower == null or Vector2(p.x - lamp_pos.x, p.z - lamp_pos.z).length() > tower.beam_range + 1.0:
				continue
			var ob := 8
			var heights := [KNEE, Player.CROUCH_EYE, Player.STAND_EYE]
			for k in 3:
				if _open(p + Vector3.UP * float(heights[k]), k > 0):
					ob |= 1 << k
			if _open(p + Vector3.UP * WireGap.CRAWL_EYE, true):
				ob |= 16
			open_bits[i] = ob
			var knee := (ob & 1) != 0 and _ever(p + Vector3.UP * KNEE)
			var lb := 0
			if knee or ((ob & 2) != 0 and _ever(p + Vector3.UP * Player.CROUCH_EYE)):
				lb |= 1
			if knee or ((ob & 4) != 0 and _ever(p + Vector3.UP * Player.STAND_EYE)):
				lb |= 2
			if knee or ((ob & 16) != 0 and _ever(p + Vector3.UP * WireGap.CRAWL_EYE)):
				lb |= 4
			lit_bits[i] = lb
	astar.region = Rect2i(0, 0, gw, gh)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar.update()


## Every pose he can be in on his round, as [where, facing from, facing to,
## any facing]: along each leg facing along it, at each point turning from
## the leg in to the leg out (a turn of nearly half a circle: every way), and
## where he stands now. A post: the way he faces there.
func _round_poses(w: Watcher) -> Array:
	var e := w.enemy
	var poses: Array = [[e.global_position, e.rotation.y, e.rotation.y, false]]
	var n := w.route.size()
	if n == 0:
		return poses
	var first := w.route[0] - e.global_position
	if Vector2(first.x, first.z).length() > 0.35:
		poses.append([e.global_position, e.rotation.y, atan2(-first.x, -first.z), false])
	for k in n:
		var a := w.route[k]
		var b := w.route[(k + 1) % n]
		var c := w.route[(k + 2) % n]
		var yaw_ab := atan2(-(b - a).x, -(b - a).z)
		var yaw_bc := atan2(-(c - b).x, -(c - b).z)
		var steps := maxi(int(a.distance_to(b)), 1)
		for s in steps + 1:
			poses.append([a.lerp(b, float(s) / steps), yaw_ab, yaw_ab, false])
		var turn := wrapf(yaw_bc - yaw_ab, -PI, PI)
		poses.append([b, yaw_ab, yaw_bc, absf(turn) > PI - AMBIGUOUS])
	return poses


static func _dist_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (ap - ab * t).length()


func _open(point: Vector3, body := false) -> bool:
	# The tower's own test (SearchlightTower.in_beam): world and doors block;
	# a head counts with its shoulders (Enemy.sight_points), the knee alone.
	var pts := Enemy.sight_points(lamp_pos, point) if body else PackedVector3Array([point])
	for pt in pts:
		var q := PhysicsRayQueryParameters3D.create(lamp_pos, pt, 1 | IzbaDoor.DOOR_LAYER)
		if space.intersect_ray(q).is_empty():
			return true
	return false


## Direction of the beam at the sweep angle `yaw` (radians).
func beam_axis(yaw: float) -> Vector3:
	var b := tower.global_basis * Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(-tower.tilt_down))
	return b * Vector3.FORWARD


## Sweep angle at tower time `t` (SearchlightTower._physics_process).
func yaw_at(t: float) -> float:
	return deg_to_rad(tower.sweep_amplitude) * sin(TAU * t / tower.sweep_period)


## Can the beam reach `point` at some moment of its sweep (occlusion aside)?
func _ever(point: Vector3) -> bool:
	var to := point - lamp_pos
	if to.length() > tower.beam_range:
		return false
	var local := tower.global_basis.inverse() * to
	var az := atan2(-local.x, -local.z)
	var a := deg_to_rad(tower.sweep_amplitude)
	return rad_to_deg(beam_axis(clampf(az, -a, a)).angle_to(to)) <= tower.beam_angle + BEAM_MARGIN


## Is cell `c` lit at tower time `t` for a boy in `posture` (with margins)?
func lit_at(c: Vector2i, posture: int, t: float) -> bool:
	if not inside(c):
		return false
	var ob := open_bits[idx(c)]
	if (ob & 8) == 0:
		return false
	var points: Array[float] = []
	if (ob & 1) != 0:
		points.append(KNEE)
	if posture == Posture.CROUCHED and (ob & 2) != 0:
		points.append(Player.CROUCH_EYE)
	elif posture == Posture.UPRIGHT and (ob & 4) != 0:
		points.append(Player.STAND_EYE)
	elif posture == Posture.CRAWLING and (ob & 16) != 0:
		points.append(WireGap.CRAWL_EYE)
	var p := center(c)
	for h in points:
		var to := p + Vector3.UP * h - lamp_pos
		if to.length() > tower.beam_range:
			continue
		for dt in [-BEAM_SLACK, 0.0, BEAM_SLACK]:
			if rad_to_deg(beam_axis(yaw_at(t + dt)).angle_to(to)) <= tower.beam_angle + BEAM_MARGIN:
				return true
	return false


## Never lit in this posture, here and in the four cells next to it (he
## stands within a quarter metre of a cell's centre; the cone itself has
## BEAM_MARGIN on it).
func dark(c: Vector2i, posture: int) -> bool:
	var bit := 4 if posture == Posture.CRAWLING else (2 if posture == Posture.UPRIGHT else 1)
	for d in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var n: Vector2i = c + d
		if inside(n) and (lit_bits[idx(n)] & bit) != 0:
			return false
	return true


## A place to stop and wait: in shadow and out of everyone's reach.
func stop_at(c: Vector2i, posture: int) -> bool:
	return dark(c, posture) and inside(c) and safe[idx(c)] == 1


## Seconds per sweep the beam can light cell `c` in `posture`.
func lit_seconds(c: Vector2i, posture: int) -> float:
	var lit_t := 0.0
	var n := 280
	for k in n:
		if lit_at(c, posture, tower.sweep_period * k / n):
			lit_t += tower.sweep_period / n
	return lit_t


# --- planning --------------------------------------------------------------------

## A way from `from` to `to` (cells), or [] when there is none.
func plan(from: Vector2i, to: Vector2i, bleeding: bool) -> Array[Vector2i]:
	for z in gh:
		for x in gw:
			var c := Vector2i(x, z)
			var i := idx(c)
			var solid := blocked[i] == 1 or (bleeding and blood_zone[i] == 1) or _off_limits(i)
			if c == from or c == to:
				solid = blocked[i] == 1 and c != from
			astar.set_point_solid(c, solid)
			var w := 1.0
			if not reckless:
				if (lit_bits[i] & 1) != 0:
					w += LIT_COST
				if safe[i] == 0:
					w += GUARD_COST
			astar.set_point_weight_scale(c, w)
	var path: Array[Vector2i] = []
	path.assign(astar.get_id_path(from, to))
	return path


## A sample of the plan: where he is to be, how long it takes to get there
## from the one before, how long he stays, in what posture, doing what.
func sample(c: Vector2i, p: Vector3, dt: float, posture: int, act: int = Act.NONE, hold: float = 0.0,
		virtual: bool = false) -> Dictionary:
	return {"c": c, "p": p, "dt": dt, "posture": posture, "act": act, "hold": hold,
			"virtual": virtual, "dark": false, "stop": false, "arg": null, "stand": true}


func begin() -> Array[Dictionary]:
	var p := player.global_position
	var s: Array[Dictionary] = [sample(cell_of(p), Vector3(p.x, 0, p.z), 0.0, Posture.CROUCHED)]
	return s


func _posture_at(p: Vector3) -> int:
	if reckless:
		return Posture.UPRIGHT
	for w in watchers:
		if dist_to_round(w, p) < w.upright_from:
			return Posture.CROUCHED
	for m in tree.get_nodes_in_group("mines"):
		if level.is_ancestor_of(m) and (m as TripwireMine)._distance_to_wire(p) < MINES_NEAR:
			return Posture.CROUCHED
	return Posture.UPRIGHT


static func speed_of(pl: Player, posture: int) -> float:
	return pl.walk_speed if posture == Posture.UPRIGHT else pl.crouch_speed


## Walk to `to`. Returns false when there is no way.
func add_path(s: Array[Dictionary], to: Vector3, bleeding: bool) -> bool:
	var from: Vector2i = s[s.size() - 1]["c"]
	var cells := plan(from, cell_of(to), bleeding)
	if cells.is_empty():
		events.append("no way from %s to %s" % [_v(center(from)), _v(to)])
		return false
	var prev: Vector3 = s[s.size() - 1]["p"]
	for k in range(1, cells.size()):
		var p := center(cells[k])
		var posture := _posture_at(p)
		# A haystack's shadow hides a crouching boy, hardly a standing one
		# (the lamp is high): in a shadow like that he goes crouched.
		if posture == Posture.UPRIGHT and not reckless and not dark(cells[k], Posture.UPRIGHT) \
				and dark(cells[k], Posture.CROUCHED):
			posture = Posture.CROUCHED
		s.append(sample(cells[k], p, prev.distance_to(p) / speed_of(player, posture), posture))
		prev = p
	return true


## Walk up to `pickup` and take it - standing (he reaches over a cart, up to
## a post) or, `stand` false, crouched (into a stove's mouth half a metre off
## the ground, five metres off a policeman's round).
func add_pick(s: Array[Dictionary], pickup: Pickup, stand := true) -> bool:
	var target := pickup.global_position
	var best := Vector2i(-1, -1)
	var best_d := INF
	var around := cell_of(target)
	for dz in range(-4, 5):
		for dx in range(-4, 5):
			var c := around + Vector2i(dx, dz)
			if not inside(c) or blocked[idx(c)] == 1 or _off_limits(idx(c)):
				continue
			var p := center(c)
			var d := Vector2(p.x - target.x, p.z - target.z).length()
			if d < 0.5 or d > 1.5 or d >= best_d:
				continue
			# What his interact ray would find from there.
			var eye := p + Vector3.UP * (Player.STAND_EYE if stand else Player.CROUCH_EYE)
			var q := PhysicsRayQueryParameters3D.create(eye, eye + (target - eye).normalized() * 2.0, 9)
			q.collide_with_areas = true
			q.exclude = [player.get_rid()]
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and hit["collider"] == pickup:
				best = c
				best_d = d
	if best.x < 0:
		events.append("nowhere to reach %s from" % pickup.name)
		return false
	var last := _arrive(s, best, false)
	if last.is_empty():
		return false
	last["act"] = Act.PICK
	last["hold"] = 0.8
	last["arg"] = pickup
	last["stand"] = stand
	if not stand:
		last["posture"] = Posture.CROUCHED
		_retime(s)
	return true


## Walk to cell `c`: the sample he stands at there - a fresh one even when he
## is there already, so that an act never lands on the sample before ({}: no
## way).
func _arrive(s: Array[Dictionary], c: Vector2i, bleeding: bool) -> Dictionary:
	var n := s.size()
	if not add_path(s, center(c), bleeding):
		return {}
	if s.size() == n:
		var last := s[n - 1]
		s.append(sample(c, last["p"], 0.0, int(last["posture"])))
	return s[s.size() - 1]


## The last sample's walk, timed for its posture.
func _retime(s: Array[Dictionary]) -> void:
	var k := s.size() - 1
	if k > 0:
		s[k]["dt"] = (s[k - 1]["p"] as Vector3).distance_to(s[k]["p"]) / speed_of(player, int(s[k]["posture"]))


## Stop and look at `at`, crouched: at least `hold` seconds, and on until
## `done` says what he looks at has come (LOOK_MAX at most). He looks only
## from a place to stop at (stop_at: there nobody notices him however long
## he stays, so the wait for it to come is safe too) that `where` allows (a
## Callable on a ground point) - with nothing in between when `clear` (the
## world's line of sight from his eyes, as DreadSight tests it) - the
## nearest one to where he is.
func add_look(s: Array[Dictionary], at: Vector3, hold: float, where: Callable, clear: bool,
		done: Callable, bleeding := false) -> bool:
	var from: Vector3 = s[s.size() - 1]["p"]
	var best := Vector2i(-1, -1)
	var best_d := INF
	for z in gh:
		for x in gw:
			var c := Vector2i(x, z)
			var i := idx(c)
			if blocked[i] == 1 or (bleeding and blood_zone[i] == 1) or _off_limits(i) \
					or not stop_at(c, Posture.CROUCHED):
				continue
			var p := center(c)
			var d := from.distance_to(p)
			if d >= best_d or not where.call(p):
				continue
			if clear:
				var eye := p + Vector3.UP * Player.CROUCH_EYE
				var q := PhysicsRayQueryParameters3D.create(eye, at, 1)
				q.exclude = [player.get_rid()]
				if not space.intersect_ray(q).is_empty():
					continue
			best = c
			best_d = d
	if best.x < 0:
		events.append("nowhere to see %s from" % _v(at))
		return false
	var last := _arrive(s, best, bleeding)
	if last.is_empty():
		return false
	last["act"] = Act.LOOK
	last["posture"] = Posture.CROUCHED
	last["hold"] = hold
	last["arg"] = {"at": at, "done": done}
	_retime(s)
	return true


## Look at `at` as add_look does, but from a place to stop at already on his
## way (after sample `after`): the first one `where` allows and, when
## `clear`, with nothing in between. A place picked off the way may have no
## clear run to it at all; one on the way he gets to anyway. False: none.
func look_on_the_way(s: Array[Dictionary], after: int, at: Vector3, hold: float, where: Callable,
		clear: bool, done: Callable) -> bool:
	for k in range(after + 1, s.size()):
		var smp := s[k]
		if smp["virtual"] or int(smp["act"]) != Act.NONE or not stop_at(smp["c"], Posture.CROUCHED):
			continue
		var p: Vector3 = smp["p"]
		if not where.call(p):
			continue
		if clear:
			var eye := p + Vector3.UP * Player.CROUCH_EYE
			var q := PhysicsRayQueryParameters3D.create(eye, at, 1)
			q.exclude = [player.get_rid()]
			if not space.intersect_ray(q).is_empty():
				continue
		smp["act"] = Act.LOOK
		smp["posture"] = Posture.CROUCHED
		smp["hold"] = hold
		smp["arg"] = {"at": at, "done": done}
		smp["dt"] = (s[k - 1]["p"] as Vector3).distance_to(p) / speed_of(player, Posture.CROUCHED)
		return true
	events.append("nowhere on the way to see %s from" % _v(at))
	return false


## Give the first place to stop after sample `after` that has nothing else
## to do act `act`, held `hold` seconds. False: there is none.
func at_next_stop(s: Array[Dictionary], after: int, act: int, hold: float) -> bool:
	for k in range(after + 1, s.size()):
		var smp := s[k]
		if not smp["virtual"] and int(smp["act"]) == Act.NONE and stop_at(smp["c"], int(smp["posture"])):
			smp["act"] = act
			smp["hold"] = hold
			return true
	return false


## Up to the gap, under the wire to the other side.
func add_crawl(s: Array[Dictionary]) -> bool:
	var from_side := gap.side_of(s[s.size() - 1]["p"])
	var a := gap.side_point(from_side)
	var b := gap.side_point(-from_side)
	var last := _arrive(s, cell_of(a), false)
	if last.is_empty():
		return false
	last["act"] = Act.CRAWL
	last["posture"] = Posture.UPRIGHT  # he crawls from standing: quicker
	if s.size() > 1:
		last["dt"] = s[s.size() - 2]["p"].distance_to(last["p"]) / speed_of(player, Posture.UPRIGHT)
	# Lying down: the head goes down in LIE_TIME (WireGap._crawl), after the
	# few frames _do takes to stand and turn to the fork.
	last["hold"] = WireGap.LIE_TIME + 0.25
	var n := 8
	for k in range(1, n + 1):
		var p := a.lerp(b, float(k) / n)
		p.y = 0.0
		s.append(sample(cell_of(p), p, gap.crawl_time / n, Posture.CRAWLING, Act.NONE,
				WireGap.LIE_TIME if k == n else 0.0, true))
	return true


## Bind the wound at the first safe place after the crawl.
func bind_after_crawl(s: Array[Dictionary]) -> void:
	var after := -1
	for k in s.size():
		if s[k]["virtual"]:
			after = k
	at_next_stop(s, after, Act.BIND, Wound.BIND_TIME + 0.3)


## Mark where he may stop: in shadow, out of everyone's reach, not under the
## wire. ("dark" in a sample: a stop; the beam is not checked there.)
func finish(s: Array[Dictionary]) -> void:
	for k in s.size():
		var smp := s[k]
		smp["stop"] = k == 0 or reckless or (not smp["virtual"] and smp["act"] != Act.CRAWL
				and stop_at(smp["c"], posture_at(smp)))
		smp["dark"] = smp["stop"] or (not smp["virtual"] and dark(smp["c"], posture_at(smp)))


## How he is at a sample: as he walks there, but standing up to take a thing
## standing (_do: he reaches over a cart).
static func posture_at(smp: Dictionary) -> int:
	return Posture.UPRIGHT if int(smp["act"]) == Act.PICK and bool(smp["stand"]) else int(smp["posture"])


# --- the enemies, ahead of time ------------------------------------------------------

## Where `w` is and which way he faces every STEP seconds for `seconds` ahead,
## as poses (see _round_poses) - a turn from one step to the next sweeps the
## arc between; [] when he is off his round (something is up: stay put).
func ahead(w: Watcher, seconds: float) -> Array:
	var e := w.enemy
	if e.state != Enemy.State.PATROL or not e.is_visible_in_tree():
		return []
	if w.dog != null and w.dog.state != Enemy.State.PATROL:
		return []
	var pos := e.global_position
	var yaw := e.rotation.y
	var n := int(ceil(seconds / STEP)) + 1
	var out: Array = []
	if w.route.is_empty():
		for k in n:
			out.append([pos, yaw, yaw, false])
		return out
	var at := e._route_idx
	var wait := e._wait
	var either_way := false
	var turn := 1.0 - exp(-TURN_RATE * STEP)
	for k in n:
		var was := yaw
		if wait > 0.0:
			wait -= STEP
			out.append([pos, was, yaw, false])
			continue
		var to := w.route[at] - pos
		to.y = 0.0
		if to.length() < 0.35:
			at = (at + 1) % w.route.size()
			wait = e.wait_at_point
			out.append([pos, was, yaw, false])
			continue
		var want := atan2(-to.x, -to.z)
		var left := absf(wrapf(want - yaw, -PI, PI))
		if left > PI - AMBIGUOUS:
			either_way = true
		elif left < 0.2:
			either_way = false
		yaw = lerp_angle(yaw, want, turn)
		pos += to.normalized() * minf(e.walk_speed * STEP, to.length())
		out.append([pos, was, yaw, either_way])
	return out


## Would `w` in `pose` notice a boy at `p` in `posture`: close enough to hear
## him, or with the boy in his eyes (in the cone his facing swept, in range,
## nothing between them), or in his torch?
func danger(w: Watcher, p: Vector3, pose: Array, posture: int, moving := false) -> bool:
	var g: Vector3 = pose[0]
	if w.heel == 0.0:
		return _notices(w, p, g, float(pose[1]), float(pose[2]), bool(pose[3]), w.slack, posture, moving)
	# A dog at heel (see HEEL): loose round a turning handler, else at the
	# heel point or behind it, facing his way - three places 0.8 m apart,
	# each with LAG on it.
	if _dog_loose(w, pose):
		return _notices(w, p, g, 0.0, 0.0, true, w.heel + w.heel_slack + w.slack, posture, moving)
	var yaw := float(pose[2])
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	for k in 3:
		var at := g + right * w.heel - fwd * (w.heel_slack * k * 0.5)
		if _notices(w, p, at, yaw, yaw, false, w.slack, posture, moving):
			return true
	return false


## Would a watcher standing at `g`, his facing sweeping from `a` to `b` (or
## any way), notice a boy at `p`, with `slack` metres more on every distance?
## `moving`: the boy is walking there (his steps), not standing.
func _notices(w: Watcher, p: Vector3, g: Vector3, a: float, b: float, any_way: bool, slack: float,
		posture: int, moving := false) -> bool:
	var to := Vector3(p.x - g.x, 0.0, p.z - g.z)
	var d := to.length() - slack
	if d < _near(w, p, g, posture, moving):
		return true
	var sight := _sight(w, p)
	if to.length() < 0.01 or d >= maxf(sight, TORCH_RANGE if w.torch else 0.0):
		return false
	var off := 0.0 if any_way else _off_arc(atan2(-to.x, -to.z), a, b)
	if not ((d < sight and off < w.sight_half) or (w.torch and d < TORCH_RANGE and off < TORCH_HALF)):
		return false
	if not w.occluded:
		return true
	# A dog's eyes are lower than its handler's: it looks under what his do
	# not (a slanting beam, a cart). Both are tried.
	if w.hear_r > 0.0 and _seen_from(g + Vector3.UP * w.dog.eye_height, p, posture):
		return true
	return _seen_from(g + Vector3.UP * w.enemy.eye_height, p, posture)


## Degrees from `bearing` to the arc a facing swept from `a` to `b` (the short
## way round, as lerp_angle turns); 0 inside it.
static func _off_arc(bearing: float, a: float, b: float) -> float:
	var span := wrapf(b - a, -PI, PI)
	var t := wrapf(bearing - a, -PI, PI)
	if (span >= 0.0 and t >= 0.0 and t <= span) or (span < 0.0 and t <= 0.0 and t >= span):
		return 0.0
	return rad_to_deg(minf(absf(t), absf(wrapf(bearing - b, -PI, PI))))


## The enemy's own lines of sight (Enemy.can_see): to the head and both
## shoulders; world and doors block, one clear line and he is seen. Down,
## both the game's head and the raised one (LOS_CROUCHED) are tried: the bot
## sees at least what the game does, whatever shape the cover has.
func _seen_from(eye: Vector3, p: Vector3, posture: int) -> bool:
	var heights: Array[float] = [Player.STAND_EYE]
	if posture != Posture.UPRIGHT:
		heights = [WireGap.CRAWL_EYE if posture == Posture.CRAWLING else Player.CROUCH_EYE, LOS_CROUCHED]
	for y in heights:
		for point in Enemy.sight_points(eye, p + Vector3.UP * y):
			var q := PhysicsRayQueryParameters3D.create(eye, point, 1 | IzbaDoor.DOOR_LAYER)
			if space.intersect_ray(q).is_empty():
				return true
	return false


# --- what a level changes (tests/act1_escaper.gd) ---------------------------------------

## How near `w`, foreseen at `g`, hears a boy at `p` in `posture` (`moving`:
## walking there, not standing): here the watcher's own ring.
func _near(w: Watcher, _p: Vector3, _g: Vector3, posture: int, _moving: bool) -> float:
	return near_of(w, posture)


## How far `w` sees a boy at `p`: here the light on him is the moon's
## everywhere, and the range his own.
func _sight(w: Watcher, _p: Vector3) -> float:
	return w.sight_range


## A cell (index) he must not set foot on, beyond walls and wires: none here.
func _off_limits(_i: int) -> bool:
	return false


## The end of the run starting at `k`: the next place he may stop.
static func leg_end(s: Array[Dictionary], k: int) -> int:
	var m := k + 1
	while m < s.size() - 1 and not s[m]["stop"]:
		m += 1
	return m


## Can he go from sample k to sample m now, and stay there a while? Every
## moment of the run is checked against the beam and every enemy - from
## leaving one sample to leaving the next, at the next one (half a metre on).
func feasible(s: Array[Dictionary], k: int, m: int) -> bool:
	if reckless:
		return true
	var span := 0.0
	for j in range(k + 1, m + 1):
		span += float(s[j]["dt"]) + float(s[j]["hold"])
	var last := m == s.size() - 1
	var horizon := span + (0.0 if last else SAFE_AFTER) + 1.0
	var aheads: Array = []
	# What each dog has made of him so far (see WALK_STEP).
	var heard: Array = []
	for w in watchers:
		var a := ahead(w, horizon)
		if a.is_empty():
			return false
		aheads.append(a)
		heard.append(w.dog.suspicion if w.hear_r > 0.0 else 0.0)
	var t0 := tower._t if tower != null else 0.0
	var tau := 0.0
	for j in range(k + 1, m + 1):
		var smp := s[j]
		var from := tau
		tau += float(smp["dt"])
		var until := tau + float(smp["hold"]) + (0.0 if j < m or last else SAFE_AFTER)
		var posture := posture_at(smp)
		var t := from
		while true:
			if not smp["dark"] and t >= tau - BEAM_SLACK and lit_at(smp["c"], posture, t0 + t):
				return false
			var at := int(t / STEP)
			var next := minf(t + STEP, until)
			for i in watchers.size():
				var w := watchers[i]
				var a: Array = aheads[i]
				var pose: Array = a[mini(at, a.size() - 1)]
				if danger(w, smp["p"], pose, posture, t < tau):
					return false
				if w.hear_r > 0.0:
					var gain := 0.0
					if posture == Posture.UPRIGHT and t < tau:
						gain = dog_hears(w, smp["p"], pose)
					heard[i] = maxf(float(heard[i]) + (gain - FADE) * (next - t), 0.0)
					if heard[i] > HEARD_MAX:
						return false
			if t >= until:
				break
			t = next
		tau += float(smp["hold"])
	return true


## Suspicion a second a dog (watcher `w`, its handler in `pose`) would get
## from a boy walking upright at `p`: from the nearest place it may be.
func dog_hears(w: Watcher, p: Vector3, pose: Array) -> float:
	var g: Vector3 = pose[0]
	var d := INF
	if w.heel == 0.0:
		d = Vector2(p.x - g.x, p.z - g.z).length() - w.slack
	elif _dog_loose(w, pose):
		d = Vector2(p.x - g.x, p.z - g.z).length() - (w.heel + w.heel_slack + w.slack)
	else:
		var yaw := float(pose[2])
		var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		for k in 3:
			var at := g + right * w.heel - fwd * (w.heel_slack * k * 0.5)
			d = minf(d, Vector2(p.x - at.x, p.z - at.z).length() - w.slack)
	if d >= w.hear_r:
		return 0.0
	return 0.9 * Player.STEP_WALK_NOISE * (1.0 - maxf(d, 0.0) / w.hear_r) / WALK_STEP


# --- walking it ------------------------------------------------------------------

func _frame() -> void:
	# The tremor before a growl: hold the breath, as a careful player does
	# (docs/ARCHITECTURE.md, "Голод и хлеб") - else the growl is an action
	# noise the camp dog hears at five metres.
	if player.hunger != null and player.hunger.tremor > 0.0:
		Input.action_press("hold_breath")
	else:
		Input.action_release("hold_breath")
	await tree.physics_frame
	if tower != null:
		max_exposure = maxf(max_exposure, tower.exposure)
	var cp := int(level.get("checkpoint_index"))
	if cp >= 0 and not saved.has(cp):
		saved.append(cp)
	var walking := not player.is_crouching and player.is_on_floor() \
			and Vector2(player.velocity.x, player.velocity.z).length() > 0.3
	for w in watchers:
		if w.hear_r <= 0.0:
			continue
		var pose := [w.enemy.global_position, w.enemy.rotation.y, w.enemy.rotation.y, false]
		var gain := dog_hears(w, player.global_position, pose) if walking else 0.0
		var dog := str(w.dog.name)
		ears[dog] = maxf(float(ears.get(dog, 0.0)) + (gain - FADE) * frame_time(), 0.0)
	for e in tree.get_nodes_in_group("enemies"):
		var en := e as Enemy
		var key := str(en.name)
		peak[key] = maxf(float(peak.get(key, 0.0)), en.suspicion)
		if en.state != Enemy.State.PATROL:
			if not saw.has(key):
				saw[key] = en.can_see(player)
				ears_when_turned[key] = float(ears.get(key, 0.0))
			if int(noticed.get(key, 0)) < int(en.state):
				noticed[key] = int(en.state)
				events.append("%s %s at %s" % [key, Enemy.State.keys()[en.state], _v(player.global_position)])
				if stop_when_noticed:
					_fail("noticed by %s" % key)


## Game seconds a physics frame moves on: the runner speeds the game up
## (Engine.time_scale), and every wait here is in the game's own time - the
## time the beam, the guard and Stealth.clock run in.
static func frame_time() -> float:
	return Engine.time_scale / Engine.physics_ticks_per_second


func _seconds(t: float) -> void:
	var left := t
	while left > 0.0 and failed == "":
		await _frame()
		left -= frame_time()


func _crouch(on: bool) -> void:
	if on:
		Input.action_press("crouch")
	else:
		Input.action_release("crouch")


func stop() -> void:
	Input.action_release("move_forward")


func release_all() -> void:
	for a in ["move_forward", "crouch", "sprint", "hold_breath"]:
		Input.action_release(a)


func _anyone_up() -> bool:
	for e in tree.get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en.is_visible_in_tree() and en.state != Enemy.State.PATROL:
			return true
	return false


## Walk the plan. Returns true when he got to the end of it.
func run(s: Array[Dictionary], time_limit: float) -> bool:
	var started := Stealth.clock
	var k := 0
	while k < s.size() - 1:
		if failed != "":
			return false
		var m := leg_end(s, k)
		var waiting := 0.0
		while not feasible(s, k, m) or (not reckless and _anyone_up()):
			if _anyone_up():
				frozen += STEP
			stop()
			_crouch(true)
			await _seconds(STEP)
			waiting += STEP
			if failed != "":
				return false
			if waiting > MAX_WAIT or Stealth.clock - started > time_limit:
				var span := 0.0
				for j in range(k + 1, m + 1):
					span += float(s[j]["dt"]) + float(s[j]["hold"])
				_fail("no clear run at %s (waited %.0f s) to %s: %d steps, %.1f s" % [
						_v(player.global_position), waiting, _v(s[m]["p"]), m - k, span])
				return false
		if waiting > 0.0:
			waited += waiting
			longest_wait = maxf(longest_wait, waiting)
			events.append("waited %.1f s at %s" % [waiting, _v(player.global_position)])
		var j := k + 1
		while j <= m:
			var smp := s[j]
			if smp["virtual"]:
				j += 1
				continue
			if not await _reach(smp):
				return false
			if smp["act"] != Act.NONE and not await _do(smp):
				return false
			if smp["act"] == Act.CRAWL:
				while j + 1 < s.size() and s[j + 1]["virtual"]:
					j += 1
			j += 1
		k = m
	stop()
	return failed == ""


## Drive towards sample `smp` until he is there.
func _reach(smp: Dictionary) -> bool:
	var target: Vector3 = smp["p"]
	_crouch(smp["posture"] == Posture.CROUCHED)
	var stuck := 0.0
	var last := player.global_position
	while true:
		if failed != "":
			stop()
			return false
		var here := player.global_position
		var to := Vector2(target.x - here.x, target.z - here.z)
		if to.length() < 0.22:
			return true
		player.look_towards(Vector3(target.x, player.head.global_position.y, target.z))
		Input.action_press("move_forward")
		await _frame()
		trace.append(player.global_position)
		var moved := player.global_position.distance_to(last)
		walked += moved
		last = player.global_position
		stuck = stuck + frame_time() if moved < 0.002 else 0.0
		if stuck > 1.5:
			stop()
			_fail("stuck at %s going to %s" % [_v(here), _v(target)])
			return false
	return true


func _do(smp: Dictionary) -> bool:
	stop()
	match int(smp["act"]):
		Act.PICK:
			var pickup := smp["arg"] as Pickup
			_crouch(not bool(smp["stand"]))
			await _seconds(0.45)
			player.look_towards(pickup.global_position)
			await _frame()
			if not player.try_interact():
				_fail("could not take %s" % pickup.name)
				return false
			events.append("took %s" % pickup.item.id)
			if player.archive_ui.is_open:
				# A document: the world stops while he reads it (ArchiveUI);
				# E puts it away, as a player does.
				read.append(pickup.item.document_id)
				for _f in 10:
					await tree.process_frame
				await _press_event("interact")
				if player.archive_ui.is_open:
					_fail("the document would not close")
					return false
			await _seconds(0.2)
		Act.CRAWL:
			_crouch(false)
			await _frame()
			await _frame()
			player.look_towards(gap.global_position + Vector3.UP * 0.2)
			await _frame()
			if not player.try_interact():
				_fail("could not get under the wire at %s" % _v(player.global_position))
				return false
			while gap.busy and failed == "":
				await _frame()
			crawled = true
			events.append("crawled under the wire, bleeding %s" % player.wound.bleeding)
		Act.BIND:
			var bandage: ItemData = null
			for item in Inventory.items():
				if item.id == "bandage":
					bandage = item
			if bandage != null and player.wound.bleeding:
				if not player.use_item(bandage):
					_fail("the bandage would not go on")
					return false
				while player.wound.is_binding() and failed == "":
					await _frame()
				bound = not player.wound.bleeding
				events.append("bound the wound at %s" % _v(player.global_position))
		Act.LOOK:
			var look: Dictionary = smp["arg"]
			var at: Vector3 = look["at"]
			var done: Callable = look["done"]
			_crouch(int(smp["posture"]) == Posture.CROUCHED)
			var held := 0.0
			while failed == "" and (held < float(smp["hold"]) or not done.call()):
				if held > LOOK_MAX:
					_fail("looked at %s from %s for %.0f s: it never came" % [
							_v(at), _v(player.global_position), held])
					return false
				# Every frame: his head is still going down as he crouches.
				player.look_towards(at)
				await _frame()
				held += frame_time()
			if failed != "":
				return false
			looked.append(at)
			events.append("looked at %s from %s for %.1f s" % [_v(at), _v(player.global_position), held])
		Act.EAT:
			var bread: ItemData = null
			for item in Inventory.items():
				if item.id == "bread":
					bread = item
			if bread == null or not player.use_item(bread):
				_fail("could not eat the bread at %s" % _v(player.global_position))
				return false
			ate = true
			events.append("ate the bread at %s" % _v(player.global_position))
			await _seconds(float(smp["hold"]) - 0.3)
	return failed == ""


## A key pressed and let go as an input event (what the document view
## listens to: Input.action_press makes no event).
func _press_event(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await tree.process_frame
	await tree.process_frame
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await tree.process_frame
	await tree.process_frame


## Stand still (crouched) until `done` says so or `seconds` run out.
func wait_for(done: Callable, seconds: float) -> void:
	stop()
	_crouch(true)
	var left := seconds
	while left > 0.0 and failed == "" and not done.call():
		await _frame()
		left -= frame_time()


## Stand still until the level is over (the forest) or `seconds` run out.
func wait_end(finished: Array, seconds: float) -> void:
	stop()
	var left := seconds
	while left > 0.0 and failed == "" and not finished[0]:
		await _frame()
		left -= frame_time()


static func _v(p: Vector3) -> String:
	return "(%.1f, %.1f)" % [p.x, p.z]
