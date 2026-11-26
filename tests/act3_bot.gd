extends RefCounted
## Act III played by a careful runner (docs/ARCHITECTURE.md, "Проходимость
## Акта III"): the briefing, a pass picked at the dugout table, the
## checkpoint, three things remembered in the garrison without staring
## under anyone's eyes, the round-up at the exit, the interrogation held by
## the legend, the forest. He presses the player's own actions: move_forward
## with his eyes along the way, interact and move_right as input events
## (the bundle, the pass check), answer_1..3 at the interrogation. His eyes
## he turns at once (Player.look_towards), like a quick flick of the mouse.

## Close enough to a point of the way.
const ARRIVED := 0.25
## The cells he picks a place to look from.
const GRID := 0.5
## His model of who may see him (the doc, "Что бот знает лучше игрока"):
## a post's eyes reach 1 m further, a patrol's 2 m, both 8 degrees wider;
## a patrol about to turn (on a point of his round or within 3 s of it)
## may see him whichever way he faces now.
const POST_RANGE := 1.0
const PATROL_RANGE := 2.0
const ANGLE_MARGIN := 8.0
const TURN_AHEAD := 3.0
## A patrol facing further than this off his next point is still turning.
const TURNING := 10.0
## He keeps this far out of the depot yard and off a patrol's beat.
const YARD_MARGIN := 0.6
const BEAT_MARGIN := 1.5
## A place to look from is this much closer than the thing's max_distance,
## and the thing is in view from anywhere this close to it (he stops within
## ARRIVED of a point) and a little lower or higher.
const REACH_MARGIN := 1.0
const VIEW_SPREAD := 0.35
const AROUND: Array[Vector2] = [Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
		Vector2(0.7, 0.7), Vector2(-0.7, 0.7), Vector2(0.7, -0.7), Vector2(-0.7, -0.7)]
## He answers this long after the question is put.
const THINK := 1.5

var level: Node3D
var player: Player
var tree: SceneTree
var it: Interrogation
var nav_map: RID
var enemies: Array[Enemy] = []
var failed := ""
var events: Array[String] = []
## Game seconds since setup.
var clock := 0.0
var eye_height := 1.5
var head_height := 1.5

## For the checks.
var peak: Dictionary = {}
var worst: Dictionary = {}
## Frames the game took him for staring (Stealth.staring), and of them those
## when an enemy saw him (Enemy.can_see): the bot's model against the game.
var staring_frames := 0
var staring_seen := 0
var first_seen_staring := ""
var restricted_frames := 0
var briefing_seen: Array[String] = []
var briefing_done_at := -1.0
var first_step_at := -1.0
var passes_seen: Array[String] = []
var paused_while_comparing := true
var chosen := ""
var pass_in_satchel := false
var checkpoint_held := 0.0
## How far he got while the sentry looked at the pass, pushing forward all
## the while (the game freezes him there).
var checkpoint_moved := 0.0
## Target name -> [the place he looked from, game seconds there, frames he
## looked down because someone might see, where he stood when it was fixed].
var scouting: Dictionary = {}
var start_suspicion := -1.0
var pass_valid := false
var outcomes: Array[String] = []
## Seconds left on each question's timer when he answered.
var answer_left: Array[float] = []
var by_keys := 0
var detail_done_at := -1
var revealed_after := -1
var released := false
## The control: stares whatever who sees.
var free_stare := false
## The control stops when someone turns.
var stop_when_turned := false


func setup(lv: Node3D) -> void:
	level = lv
	tree = lv.get_tree()
	player = lv.get_node("Player") as Player
	it = lv.get_node("Interrogation") as Interrogation
	nav_map = (lv.get_node("Navigation") as NavigationRegion3D).get_navigation_map()
	for e in tree.get_nodes_in_group("enemies"):
		if not (e as Enemy).passive:
			enemies.append(e as Enemy)
	eye_height = player.camera.global_position.y - player.global_position.y
	head_height = player.head.global_position.y - player.global_position.y
	it.answered.connect(func(_id: String, outcome: String) -> void: outcomes.append(outcome))
	it.revealed.connect(func() -> void: revealed_after = outcomes.size())
	it.released.connect(func() -> void: released = true)


func teardown() -> void:
	release_all()


func release_all() -> void:
	for a in ["move_forward", "crouch", "sprint", "hold_breath"]:
		Input.action_release(a)


func _fail(why: String) -> void:
	if failed == "":
		failed = why
		events.append("FAILED at %.1f s: %s" % [clock, why])
	release_all()


static func frame_time() -> float:
	return Engine.time_scale / Engine.physics_ticks_per_second


func _v(p: Vector3) -> String:
	return "(%.1f, %.1f)" % [p.x, p.z]


# --- one frame -------------------------------------------------------------------------

func _frame() -> void:
	await tree.physics_frame
	clock += frame_time()
	# A reloaded scene leaves the tree at once and is freed only later.
	if not is_instance_valid(level) or not level.is_inside_tree():
		_fail("the level is gone: the scene was reloaded")
		return
	_watch()


func _watch() -> void:
	var seen_by := ""
	for en in enemies:
		var key := str(en.name)
		peak[key] = maxf(float(peak.get(key, 0.0)), en.suspicion)
		if int(en.state) > int(worst.get(key, 0)):
			worst[key] = int(en.state)
			events.append("%.1f s: %s %s, he at %s" % [clock, key, Enemy.State.keys()[en.state],
					_v(player.global_position)])
			if stop_when_turned:
				_fail("%s turned" % key)
		if seen_by == "" and en.can_see(player):
			seen_by = key
	if Stealth.staring:
		staring_frames += 1
		if seen_by != "":
			staring_seen += 1
			if first_seen_staring == "":
				first_seen_staring = "%s at %.1f s, he at %s" % [seen_by, clock, _v(player.global_position)]
	if Stealth.in_restricted():
		restricted_frames += 1
	var line := (level.get_node("Overlay/Caption") as Label).text
	if line != "" and not briefing_seen.has(line):
		briefing_seen.append(line)


func seconds(t: float) -> void:
	var left := t
	while left > 0.0 and failed == "":
		await _frame()
		left -= frame_time()


func wait_until(done: Callable, limit: float, what: String) -> bool:
	var t := 0.0
	while failed == "" and not done.call():
		if t > limit:
			_fail("waited %.0f s for %s" % [t, what])
			return false
		await _frame()
		t += frame_time()
	return failed == ""


## A key pressed and let go as input events (what the pass check and the
## interrogation listen to; Input.action_press makes no event). Whole
## process frames: the pass check holds the tree paused.
func _press_event(action: String) -> void:
	# A person, not a key masher: a key that swaps the whole screen waits
	# until Flicker would let it (docs/ARCHITECTURE.md, "Вспышки и мерцание").
	if action in ["interact", "ui_cancel", "ui_accept", "archive_journal", "inventory"]:
		while not Flicker.swap_ready():
			await tree.process_frame
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await tree.process_frame
		await tree.process_frame


# --- walking ---------------------------------------------------------------------------

## Walks the navmesh to `to`; stops early once `until` holds.
func walk_to(to: Vector3, until: Callable = Callable()) -> bool:
	var path := NavigationServer3D.map_get_path(nav_map, player.global_position, to, true)
	if path.is_empty():
		_fail("no way from %s to %s" % [_v(player.global_position), _v(to)])
		return false
	var end := path[path.size() - 1]
	if Vector2(end.x - to.x, end.z - to.z).length() > 0.5:
		_fail("the way to %s ends at %s" % [_v(to), _v(end)])
		return false
	for pt in path:
		if not await walk_straight(pt, until):
			return false
		if until.is_valid() and until.call():
			break
	Input.action_release("move_forward")
	return failed == ""


## Straight to `to`, eyes along the way at his own height.
func walk_straight(to: Vector3, until: Callable = Callable()) -> bool:
	Input.action_release("crouch")
	var stuck := 0.0
	var last := player.global_position
	while failed == "":
		if until.is_valid() and until.call():
			Input.action_release("move_forward")
			return true
		var here := player.global_position
		if Vector2(to.x - here.x, to.z - here.z).length() < ARRIVED:
			return true
		player.look_towards(Vector3(to.x, player.head.global_position.y, to.z))
		Input.action_press("move_forward")
		if first_step_at < 0.0:
			first_step_at = clock
		await _frame()
		stuck = stuck + frame_time() if player.global_position.distance_to(last) < 0.002 else 0.0
		last = player.global_position
		if stuck > 1.5:
			_fail("stuck at %s going to %s" % [_v(here), _v(to)])
	Input.action_release("move_forward")
	return false


# --- the act -----------------------------------------------------------------------------

## The whole act, from the briefing to the forest (the caller waits for the
## end card).
func play(forest: Vector3) -> bool:
	if not await wait_until(func() -> bool:
			return level.fade.modulate.a < 0.05 and level.caption.text == "", 60.0, "the briefing"):
		return false
	briefing_done_at = clock
	events.append("%.1f s: the briefing is over" % clock)
	if not await take_pass():
		return false
	if not await through_checkpoint():
		return false
	for t in level.scout_targets():
		if not await scout(t, 180.0):
			return false
	if not await to_round_up():
		return false
	if not await interrogate():
		return false
	if not await wait_until(func() -> bool:
			return level.stage == level.Stage.RELEASED and not player.is_seated and level.fade.modulate.a < 0.05,
			20.0, "being let go"):
		return false
	events.append("%.1f s: released at %s" % [clock, _v(player.global_position)])
	if not await walk_to(forest):
		return false
	events.append("%.1f s: in the forest at %s" % [clock, _v(player.global_position)])
	return failed == ""


## The dugout: to the table, the bundle, leaf through to a pass that holds.
func take_pass() -> bool:
	var bundle := level.get_node("Bundle") as Node3D
	# North of the table (it stands at z 9..9.8), facing it.
	if not await walk_to(Vector3(bundle.global_position.x, 0, 10.4)):
		return false
	player.look_towards(bundle.global_position)
	await seconds(0.3)
	var ui := level.get_node("PassCheckUI") as PassCheckUI
	await _press_event("interact")
	if not ui.is_open:
		_fail("the bundle did not open the pass check (from %s)" % _v(player.global_position))
		return false
	for _i in ui.candidates().size():
		paused_while_comparing = paused_while_comparing and tree.paused
		var shown: Dictionary = ui.candidates()[ui.index]
		passes_seen.append(str(shown.get("id", "")))
		if PassRules.is_valid(shown, ui.data):
			await _press_event("interact")
			break
		await _press_event("move_right")
	if ui.is_open:
		_fail("no pass taken (saw %s)" % [passes_seen])
		return false
	chosen = level.chosen_pass
	pass_in_satchel = Inventory.has_item("forged_pass")
	events.append("%.1f s: took %s after %s" % [clock, chosen, passes_seen])
	return failed == ""


## To the barrier; pushes on while the sentry looks at the pass - the game
## holds him; through.
func through_checkpoint() -> bool:
	var at_barrier := func() -> bool: return level.stage >= level.Stage.CHECKPOINT
	if not await walk_to(Vector3(0, 0, -42.3), at_barrier):
		return false
	if level.stage < level.Stage.CHECKPOINT:
		_fail("walked to the barrier and nobody stopped him")
		return false
	release_all()
	var t0 := clock
	var held_at := player.global_position
	# An impatient player keeps pressing forward: the game must hold him.
	Input.action_press("move_forward")
	while failed == "" and level.stage == level.Stage.CHECKPOINT:
		checkpoint_moved = maxf(checkpoint_moved, Vector2(player.global_position.x - held_at.x,
				player.global_position.z - held_at.z).length())
		if clock - t0 > 10.0:
			Input.action_release("move_forward")
			_fail("waited 10 s for the sentry's verdict")
			return false
		await _frame()
	Input.action_release("move_forward")
	if not await wait_until(func() -> bool:
			return level.stage == level.Stage.GARRISON and level.layout.barrier_open, 10.0, "the barrier"):
		return false
	checkpoint_held = clock - t0
	# The navmesh was baked with the barrier down: straight under it.
	if not await walk_straight(Vector3(0, 0, -47.0)):
		return false
	events.append("%.1f s: through the checkpoint (held %.1f s, pushing on moved him %.3f m)" % [clock,
			checkpoint_held, checkpoint_moved])
	return failed == ""


## A place to look at `t` from and the look itself: eyes on it only while
## nobody may see him, eyes on the ground otherwise.
func scout(t: GazeTarget, limit: float) -> bool:
	var at := find_vantage(t)
	if at.x == INF:
		_fail("no place to look at %s from" % t.name)
		return false
	if not await walk_to(at):
		return false
	release_all()
	var t0 := clock
	var down := 0
	var kept: Dictionary = {}
	while not t.done and failed == "":
		if clock - t0 > limit:
			_fail("could not remember %s in %.0f s from %s, stood at %s; eyes down for %s; held %.2f" % [t.name, limit,
					_v(at), _v(player.global_position), kept, t.held])
			return false
		var who := "" if free_stare else may_be_seen()
		if who != "":
			kept[who] = int(kept.get(who, 0)) + 1
		if who == "":
			player.look_towards(t.global_position)
		else:
			down += 1
			var ahead := Vector3(t.global_position.x - player.global_position.x, 0,
					t.global_position.z - player.global_position.z).normalized()
			player.look_towards(player.head.global_position + ahead * 1.2 + Vector3.DOWN * 1.4)
		await _frame()
	scouting[str(t.name)] = [at, clock - t0, down, player.global_position]
	events.append("%.1f s: remembered %s from %s in %.1f s (eyes down %d frames)" % [clock, t.name, _v(at),
			clock - t0, down])
	return failed == ""


## The control: from `at`, eyes on `t` whoever looks, once the patrol has
## him in sight close by.
func stare_in_sight(t: GazeTarget, patrol: Enemy, close: float, limit: float) -> bool:
	free_stare = true
	release_all()
	var t0 := clock
	if not await wait_until(func() -> bool:
			return patrol.can_see(player) and patrol.global_position.distance_to(player.global_position) < close,
			limit, "the patrol to come close"):
		return false
	events.append("%.1f s: %s sees him at %.1f m; eyes on %s" % [clock, patrol.name,
			patrol.global_position.distance_to(player.global_position), t.name])
	while not t.done and failed == "" and clock - t0 < limit:
		player.look_towards(t.global_position)
		await _frame()
	return true


## The exit gate: the round-up takes him to the office.
func to_round_up() -> bool:
	var taken := func() -> bool: return level.stage == level.Stage.INTERROGATION
	if not await walk_to(Vector3(0, 0, -101.6), taken):
		return false
	release_all()
	if level.stage != level.Stage.INTERROGATION:
		_fail("walked through the exit gate and nobody stopped him")
		return false
	events.append("%.1f s: rounded up at %s" % [clock, _v(player.global_position)])
	return failed == ""


## The office: eyes on the typewriter till it lets him go, then on the
## investigator; each question answered THINK seconds after it is put, with
## the answer that keeps the legend and what he said before.
func interrogate() -> bool:
	if not await wait_until(func() -> bool: return it.running and player.is_seated, 15.0, "the interrogation"):
		return false
	start_suspicion = it.suspicion
	pass_valid = it.pass_valid
	var detail := it.details_root.get_node("Typewriter") as GazeTarget
	var face := it.investigator.global_position + Vector3.UP * 1.62
	var asked_q := -1
	var asked_at := 0.0
	var answered_q := -1
	var t0 := clock
	while it.running and failed == "":
		if clock - t0 > 120.0:
			_fail("the interrogation did not end in 120 s")
			return false
		if not detail.done:
			player.look_towards(detail.global_position)
		else:
			if detail_done_at < 0:
				detail_done_at = outcomes.size()
			player.look_towards(face)
		if not it._waiting and it.q_index != asked_q:
			asked_q = it.q_index
			asked_at = clock
		if asked_q >= 0 and asked_q != answered_q and not it._waiting and clock - asked_at >= THINK:
			var q: Dictionary = it.questions()[asked_q]
			var pick := -1
			for i in (q.get("answers", []) as Array).size():
				if it.evaluate(q, i) == "consistent":
					pick = i
					break
			if pick < 0:
				_fail("no answer to %s keeps the legend" % q.get("id", ""))
				return false
			answer_left.append(it.time_left)
			var before := outcomes.size()
			answered_q = asked_q
			await _press_event("answer_%d" % (pick + 1))
			if outcomes.size() == before + 1:
				by_keys += 1
			continue
		await _frame()
	return failed == ""


# --- who may see him, where to look from -------------------------------------------------

## The first enemy who, by the bot's model, may see him now ("" - nobody).
func may_be_seen() -> String:
	var head := player.head.global_position
	for en in enemies:
		var far := en.global_position.distance_to(head)
		if en.state != Enemy.State.PATROL:
			# Looking about, coming over: anywhere he can see.
			if far <= en.view_distance + PATROL_RANGE:
				return str(en.name)
			continue
		if _is_patrol(en):
			if far > en.view_distance + PATROL_RANGE:
				continue
			if _in_cone(en, head, ANGLE_MARGIN) or _turns_soon(en):
				return str(en.name)
			continue
		if _cone_sees(en, head, POST_RANGE):
			return str(en.name)
	return ""


static func _is_patrol(en: Enemy) -> bool:
	return not en.hold_position and en.patrol_route != null and en.patrol_route.get_child_count() > 0


## On a point of his round, there within TURN_AHEAD seconds, or still
## swinging round towards the next one (the turn after the wait takes a few
## frames): he turns.
static func _turns_soon(en: Enemy) -> bool:
	if en._wait > 0.0:
		return true
	var point := (en.patrol_route.get_child(en._route_idx) as Node3D).global_position
	var dir := Vector3(point.x - en.global_position.x, 0, point.z - en.global_position.z)
	if dir.length() < en.walk_speed * TURN_AHEAD + 0.35:
		return true
	var fwd := -en.global_transform.basis.z
	fwd.y = 0.0
	return fwd.angle_to(dir) > deg_to_rad(TURNING)


static func _in_cone(en: Enemy, head: Vector3, margin: float) -> bool:
	var eye := en.global_position + Vector3.UP * en.eye_height
	var fwd := -en.global_transform.basis.z
	return rad_to_deg(fwd.angle_to((head - eye).normalized())) <= en.view_angle_deg * 0.5 + margin


## As Enemy.can_see, with the margins and without the light (light only
## shortens the eyes). The game looks at his head and shoulders
## (Enemy.sight_points); the bot counts himself seen if any line to those
## points or around them (VIEW_SPREAD aside, 10 cm lower) is clear.
func _cone_sees(en: Enemy, head: Vector3, extra: float) -> bool:
	var eye := en.global_position + Vector3.UP * en.eye_height
	if eye.distance_to(head) > en.view_distance + extra:
		return false
	if not _in_cone(en, head, ANGLE_MARGIN):
		return false
	# The game's points (head, shoulders), each also VIEW_SPREAD around and
	# 10 cm lower: he may stand a little off the point.
	for point in Enemy.sight_points(eye, head):
		for dy in [0.0, -0.1]:
			for d in AROUND:
				var q := PhysicsRayQueryParameters3D.create(eye, point + Vector3(d.x * VIEW_SPREAD, dy, d.y * VIEW_SPREAD),
						1 | IzbaDoor.DOOR_LAYER)
				q.exclude = [en.get_rid()]
				if level.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
					return true
	return false


## The ground's top under `c` (the navmesh point `nav_y` is above it).
func _ground_at(c: Vector3, nav_y: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(c.x, nav_y + 0.5, c.z), Vector3(c.x, nav_y - 1.5, c.z), 1)
	q.exclude = [player.get_rid()]
	var hit := level.get_world_3d().direct_space_state.intersect_ray(q)
	return nav_y if hit.is_empty() else (hit.position as Vector3).y


## The gaze's own ray (Gaze.looks_at): nothing of the world between, or what
## is hit lies within the thing's radius.
func _clear_line(from: Vector3, to: Vector3, radius: float) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := level.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit.position as Vector3).distance_to(to) < radius


## The thing in view from `eye` and from around it (VIEW_SPREAD aside, 10 cm
## lower, 5 cm higher).
func _in_view_around(eye: Vector3, t: GazeTarget) -> bool:
	for dy in [-0.1, 0.05]:
		for d in AROUND:
			var from := eye + Vector3(d.x * VIEW_SPREAD, dy, d.y * VIEW_SPREAD)
			if not _clear_line(from, t.global_position, t.radius):
				return false
	return true


func _in_yard(p: Vector3, margin: float) -> bool:
	var zone := level.get_node("YardZone") as Area3D
	var box := (zone.get_node("Shape") as CollisionShape3D).shape as BoxShape3D
	var c := zone.global_position
	return absf(p.x - c.x) < box.size.x * 0.5 + margin and absf(p.z - c.z) < box.size.z * 0.5 + margin


## Within BEAT_MARGIN of a patrol's round (he does not stand in the way).
func _on_beat(p: Vector3) -> bool:
	for en in enemies:
		if not _is_patrol(en):
			continue
		var n := en.patrol_route.get_child_count()
		for i in n:
			var a := (en.patrol_route.get_child(i) as Node3D).global_position
			var b := (en.patrol_route.get_child((i + 1) % n) as Node3D).global_position
			var closest := Geometry3D.get_closest_point_to_segment(Vector3(p.x, 0, p.z), Vector3(a.x, 0, a.z),
					Vector3(b.x, 0, b.z))
			if closest.distance_to(Vector3(p.x, 0, p.z)) < BEAT_MARGIN:
				return true
	return false


## Some post's eyes are on his head at `head` or anywhere VIEW_SPREAD around
## it (he stops within ARRIVED of the place he walks to).
func _post_watches_around(head: Vector3) -> bool:
	for en in enemies:
		if not en.hold_position:
			continue
		for d in AROUND:
			if _cone_sees(en, head + Vector3(d.x * VIEW_SPREAD, 0.0, d.y * VIEW_SPREAD), POST_RANGE):
				return true
	return false


## The nearest cell of the navmesh he may look at `t` from: out of the yard
## and off a patrol's beat, the thing in reach and in view at his eye
## height, and no post's eyes on him there. Vector3(INF, ...) - none.
func find_vantage(t: GazeTarget) -> Vector3:
	var reach := t.max_distance - REACH_MARGIN
	var here := player.global_position
	var found: Array = []
	var x := t.global_position.x - reach
	while x <= t.global_position.x + reach:
		var z := t.global_position.z - reach
		while z <= t.global_position.z + reach:
			var c := Vector3(snappedf(x, GRID), 0.0, snappedf(z, GRID))
			z += GRID
			var on := NavigationServer3D.map_get_closest_point(nav_map, c)
			if Vector2(on.x - c.x, on.z - c.z).length() > 0.1:
				continue
			# His feet are on the ground; the navmesh lies 0.2-0.4 m above it
			# (enemy.gd, _next_path_point).
			var feet := _ground_at(c, on.y)
			var eye := Vector3(c.x, feet + eye_height, c.z)
			if eye.distance_to(t.global_position) > reach or _in_yard(c, YARD_MARGIN) or _on_beat(c):
				continue
			if not _in_view_around(eye, t):
				continue
			if not _post_watches_around(Vector3(c.x, feet + head_height, c.z)):
				found.append([Vector2(c.x - here.x, c.z - here.z).length(), Vector3(c.x, on.y, c.z)])
		x += GRID
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	# The nearest one he can walk to.
	for f in found.slice(0, 20):
		var at: Vector3 = f[1]
		var path := NavigationServer3D.map_get_path(nav_map, here, at, true)
		if not path.is_empty() and path[path.size() - 1].distance_to(at) < 0.3:
			return at
	return Vector3(INF, 0, 0)
