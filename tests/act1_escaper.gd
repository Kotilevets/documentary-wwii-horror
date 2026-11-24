extends "res://tests/act2_bot.gd"
## The careful player of Act I's escape (tests/playthrough_runner.gd, part
## "escape"; docs/ARCHITECTURE.md, "Побег к лесу: Акт I"): out of the izba
## and across the village to the forest past the soldier with the shepherd,
## the field gendarme and the policeman, under the flares. The same bot as in
## Act II (tests/act2_bot.gd); here only what Act I changes.
##
## - The grid: the izba, the village, the field and the forest. The column
##   test starts under the izba's ceiling (else the roof would close the
##   whole izba, the place he starts at with it); the tree trunks, which no
##   body query finds from inside them, come from the scene itself.
## - The light on him: no searchlight, but flares. The bot does not time
##   them: each cell gets the worst light any moment of a flare's burn can
##   put on a boy there (the star anywhere on its way, its light never
##   flickering down, nothing in between), with the lamps the level keeps
##   lit, and every enemy's eyes reach as far as that light lets them
##   (Enemy.sight_distance), a margin on top.
## - The boards of the izba: a moving step there may creak, which carries.
## - The dog's trail: the shepherd at its handler's heel takes up a trail 1.6
##   m from itself, and it is back along any part of his beat within 40 s -
##   so he never sets foot near that beat at all.
## - Nobody sees through walls (in Act II the camp guard does, through the
##   camp fence), the dog included: its nose and ears do not need to.
## - Where he stops. In Act II he stops only where nobody can ever notice
##   him; here there is no such place on the way - the gendarme's round and
##   the policeman's beat between them cover the whole field. So he stops
##   anywhere he will stay unnoticed SAFE_AFTER more, goes on as far as he
##   can at a time (run), and while he waits keeps an eye on STAY_AHEAD
##   seconds ahead: should somebody be coming to see him there, he slips to
##   the nearest place near by that he gets to unseen and can stay at, and
##   plans his way on from there (_dodge).

## The grid: x -24.25..24.75, z -40.25..11.75.
const A1_X0 := -24.25
const A1_Z0 := -40.25
const A1_W := 98
const A1_H := 104
## Under the izba's ceiling (2.7 m), over the stove (1.8 m).
const A1_RAY_TOP := 2.5
## A tree: a cylinder taller than this.
const TRUNK_TALL := 5.0
## A cell whose centre is farther than this off the navmesh (baked 0.4 m off
## every wall) is closed: a solid box - the second izba, the barn's crates -
## hides from both tests of _build_grid when the cell is inside it.
const OFF_NAV := 0.05
## The flare's light at its brightest (SignalFlare._process: 6 x (1 - k),
## times a flicker of at most 1).
const FLARE_ENERGY := 6.0
## Flare samples over a burn.
const FLARE_STEPS := 120
## Where the light on him is measured (Stealth.update_light): his shoulders,
## head less 0.25 (crouched 0.4, standing 1.1), and his knees (0.45).
const LIGHT_LOW := 0.4
const LIGHT_HIGH := 1.1
## Metres on an enemy's eyes, on a dog's.
const EYES_MARGIN := 1.0
const DOG_EYES_MARGIN := 0.7
## Metres on a creak's reach.
const BOARD_MARGIN := 0.4
## Metres on the dog's trail strip.
const SCENT_MARGIN := 0.2
## The game measures his light ten times a second, a step behind him.
const LIGHT_SLACK := 0.02
## The izba he starts in (IzbaA's walls), and the forest's depth he makes
## for (the ForestEdge zone is z -39..-31).
const IZBA := Rect2(-3.0, 3.5, 6.0, 5.0)
const GOAL_Z := Vector2(-38.0, -33.0)
## The forest zone begins here (z): the field is south of it.
const FOREST_FROM := -31.0
## Waiting: this far ahead nobody may be coming to notice him where he is.
const STAY_AHEAD := 4.0
## Slipping away: no farther than this (metres) from where he is.
const DODGE_R := 4.0
## A wall between a creak and an ear counts only for sure (docs/ARCHITECTURE.md,
## "Побег к лесу: Акт I", "Доски"): from the ear foreseen and this far from it
## four ways (ahead() is a step, 0.13 m, off; one forecast serves a whole
## run), to every point of the leg and this far from each four ways (he
## stops 0.22 m short of a point).
const WALL_EAR_SLACK := 0.3
const WALL_SOUND_SLACK := 0.25
const WALL_OFFSETS: Array[Vector3] = [Vector3.ZERO, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]
## A run looks this many samples ahead at most.
const SCAN_MAX := 60

var flare: SignalFlare
var shepherd: Dog
## The handler's watcher and the dog's own.
var handler_w: Watcher = null
var dog_w: Watcher = null
## Per cell: the worst light on him (0..1); the worst a flare alone puts on
## him; on the boards; in the dog's trail strip.
var light := PackedFloat32Array()
var flare_light := PackedFloat32Array()
var boards := PackedByteArray()
var scent_zone := PackedByteArray()
## Where no part of the strip may be: HEEL + heel_distance + trail pickup +
## SCENT_MARGIN from the handler's beat.
var scent_reach := 0.0
## The scent control walks into the strip on purpose.
var allow_scent := false
## The plan's points (make_plan): he plans on through those left after a
## dodge; the hold at the last one.
var route_points: Array[Vector3] = []
var route_hold := 0.0

# --- what happened ---------------------------------------------------------------
## The dog followed a trail at some moment; it was on one on the frame it
## first turned.
var trail_taken := false
var trail_when_turned := false
var _dog_turned := false
## The most light a flare itself put on him (Stealth._light_of, at his
## shoulders or knees) while he was out in the village or the field.
var flare_lit := 0.0
## Every cell he walked to (samples reached, dodges too).
var stepped: Array[Vector2i] = []
## Frames the game's light on him (Stealth.player_light) was above the
## bot's worst light for his cell (LIGHT_SLACK on it), and the worst gap.
var light_misses := 0
var light_gap := 0.0
## The same for a flare alone, every frame it burns: its own light on him
## (Stealth._light_of) above flare_light for his cell. The check on the whole
## light hides a flare left out of the model: the bot takes the moon as open
## everywhere, and in a moon shadow that is more than a far flare gives.
var flare_misses := 0
var flare_gap := 0.0
## Times he slipped away from where he waited.
var dodges := 0
## The start of the leg _scan is checking (INF: none - then no wall counts,
## and the boards are the end cell's): a creak may come from anywhere on
## the leg, the first step of a walk from a stop at once.
var _leg_from := Vector3.INF
## SoundWalls.walled by ear and sound point, both to 5 cm.
var _walled_seen := {}


func setup(lv: Node3D) -> void:
	gx0 = A1_X0
	gz0 = A1_Z0
	gw = A1_W
	gh = A1_H
	ray_top = A1_RAY_TOP
	flare = lv.get_node("SignalFlare") as SignalFlare
	super.setup(lv)


func _watcher(e: Enemy) -> Watcher:
	var w := super._watcher(e)
	# Handed over while the story still holds the squad's soldier (behind
	# the corner, part "act1"): his round is his patrol route all the same,
	# and ahead() keeps him off it till he walks it.
	if w.route.is_empty() and e.patrol_route != null:
		for c in e.patrol_route.get_children():
			w.route.append((c as Node3D).global_position)
	# Act II's camp guard sees through his fence; nobody here sees through a
	# wall, and nobody's beat is a blood line.
	w.occluded = true
	guard = null
	w.eyes = e.view_distance
	w.eyes_margin = EYES_MARGIN
	w.sight_half = e.view_angle_deg * 0.5 + 8.0
	w.sight_range = e.view_distance + EYES_MARGIN  # the farthest, in full light
	if w.dog != null:
		handler_w = w
		shepherd = w.dog
	return w


func _dog_watcher(dog: Dog, handler: Watcher = null) -> Watcher:
	var w := super._dog_watcher(dog, handler)
	w.occluded = true
	w.eyes = dog.view_distance
	w.eyes_margin = DOG_EYES_MARGIN
	w.sight_range = dog.view_distance + DOG_EYES_MARGIN
	dog_w = w
	return w


func _build_grid() -> void:
	_measure()
	super._build_grid()
	_trunks()
	_off_navmesh()
	scent_zone.resize(gw * gh)
	scent_zone.fill(0)
	if handler_w == null or shepherd == null:
		return
	scent_reach = HEEL + shepherd.heel_distance + shepherd.trail_pickup_radius + SCENT_MARGIN
	for z in gh:
		for x in gw:
			var c := Vector2i(x, z)
			if dist_to_round(handler_w, center(c)) < scent_reach:
				scent_zone[idx(c)] = 1


## The worst light on him in every cell, and where the boards are.
func _measure() -> void:
	var n := gw * gh
	light.resize(n)
	flare_light.resize(n)
	boards.resize(n)
	var lamps: Array[Light3D] = []
	for l in level.find_children("*", "Light3D", true, false):
		if l == flare.light or not (l is OmniLight3D or l is SpotLight3D) or _carried(l):
			continue
		lamps.append(l as Light3D)
	# The flare's star along a burn (SignalFlare._process), at its brightest.
	var fl := flare.light
	var luma := 0.299 * fl.light_color.r + 0.587 * fl.light_color.g + 0.114 * fl.light_color.b
	var stars := PackedVector3Array()
	var bright := PackedFloat32Array()
	for k in FLARE_STEPS + 1:
		var t := flare.burn_time * k / FLARE_STEPS
		var f := t / flare.burn_time
		var local := Vector3(sin(t) * 1.5, flare.rise_height * sqrt(minf(f * 3.0, 1.0)) - f * 6.0, 0.0)
		stars.append(flare.global_transform * (local + fl.position))
		bright.append(minf(FLARE_ENERGY * (1.0 - f) * luma / Stealth.LIGHT_FULL, 1.0))
	var reach := fl.omni_range
	var near := [Vector3.ZERO, Vector3(CELL, 0, 0), Vector3(-CELL, 0, 0), Vector3(0, 0, CELL), Vector3(0, 0, -CELL)]
	for z in gh:
		for x in gw:
			var c := Vector2i(x, z)
			var i := idx(c)
			var p := center(c)
			var worst := 0.0
			for k in stars.size():
				var s := stars[k]
				# The point nearest the star where his shoulders or knees can be
				# in this cell, a cell's margin round it as for the lamps: at
				# the edge of the flare's reach a few centimetres are a lot.
				var q := Vector3(clampf(s.x, p.x - CELL, p.x + CELL), clampf(s.y, LIGHT_LOW, LIGHT_HIGH),
						clampf(s.z, p.z - CELL, p.z + CELL))
				var d := s.distance_to(q)
				if d < reach:
					worst = maxf(worst, bright[k] * sqrt(1.0 - d / reach))
			flare_light[i] = worst
			# No moon shadow counted: the open moon everywhere.
			var dark := (1.0 - Stealth.night_sight) * (1.0 - worst)
			for l in lamps:
				var lit := 0.0
				for off in near:
					for h in [LIGHT_LOW, Stealth.KNEES, LIGHT_HIGH]:
						lit = maxf(lit, Stealth._light_of(space, l, p + off + Vector3.UP * float(h)))
				dark *= 1.0 - lit
			light[i] = 1.0 - dark
			boards[i] = 1 if BoardFloor.at(tree, p + Vector3.UP * 0.05) != null else 0


## A torch or anything else an enemy carries: it moves with him.
func _carried(n: Node) -> bool:
	var at := n.get_parent()
	while at != null and at != level:
		if at is Enemy:
			return true
		at = at.get_parent()
	return false


## The trees: a cell is closed within his body of a trunk.
func _trunks() -> void:
	for t in level.find_children("*", "CSGCylinder3D", true, false):
		var cyl := t as CSGCylinder3D
		if cyl.height < TRUNK_TALL or not cyl.use_collision:
			continue
		var at := cyl.global_position
		var r := cyl.radius + BODY
		var lo := cell_of(at - Vector3(r, 0, r))
		var hi := cell_of(at + Vector3(r, 0, r))
		for z in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var c := Vector2i(x, z)
				var p := center(c)
				if inside(c) and Vector2(p.x - at.x, p.z - at.z).length() < r:
					blocked[idx(c)] = 1


func _off_navmesh() -> void:
	var map := level.get_world_3d().navigation_map
	for z in gh:
		for x in gw:
			var c := Vector2i(x, z)
			var i := idx(c)
			if blocked[i] == 1:
				continue
			var p := center(c)
			var q := NavigationServer3D.map_get_closest_point(map, p)
			if Vector2(q.x - p.x, q.z - p.z).length() > OFF_NAV or absf(q.y - p.y) > 0.6:
				blocked[i] = 1


func _sight(w: Watcher, p: Vector3) -> float:
	var c := cell_of(p)
	if w.eyes <= 0.0 or not inside(c):
		return w.sight_range
	return maxf(w.eyes * lerpf(Enemy.DARK_SIGHT, 1.0, light[idx(c)]), minf(Enemy.CLOSE_SIGHT, w.eyes)) \
			+ w.eyes_margin


## On the boards a moving step may creak (Player.CREAK_NOISE), and every step
## is louder (BOARD_NOISE): counted as if every step creaked. A wall between
## (the game's own rule, SoundWalls.walled) halves it, as in Enemy._on_noise -
## for a man on his round, and only for sure (_leg_walled); a dog at heel,
## known only within its slack, gets no wall.
func _near(w: Watcher, p: Vector3, g: Vector3, posture: int, moving: bool) -> float:
	var base := near_of(w, posture)
	var c := cell_of(p)
	if not moving or not inside(c) or not _leg_on_boards(p):
		return base
	var hearing := w.dog.hearing if w.hear_r > 0.0 else w.enemy.hearing
	var step := Player.STEP_WALK_NOISE if posture == Posture.UPRIGHT else Player.STEP_CROUCH_NOISE
	var loud := maxf(Player.CREAK_NOISE, step * Player.BOARD_NOISE)
	var reach := loud * Stealth.HEARING_RANGE * hearing + BOARD_MARGIN
	var behind := loud * Stealth.WALL_HEARING * Stealth.HEARING_RANGE * hearing + BOARD_MARGIN
	var d := Vector2(p.x - g.x, p.z - g.z).length()
	# The wall decides only between the two reaches.
	if (reach > base and w.heel == 0.0 and w.slack == 0.0 and d >= behind and d < reach
			and _leg_walled(g, w.enemy.eye_height, p)):
		reach = behind
	return maxf(base, reach)


## Is the leg he walks to `p` on the boards: its end cell, or its start
## (_leg_from) or middle, each within WALL_SOUND_SLACK four ways?
func _leg_on_boards(p: Vector3) -> bool:
	if boards[idx(cell_of(p))] == 1:
		return true
	if _leg_from == Vector3.INF:
		return false
	for at: Vector3 in [_leg_from, (_leg_from + p) * 0.5]:
		for b in WALL_OFFSETS:
			if BoardFloor.at(tree, at + b * WALL_SOUND_SLACK + Vector3.UP * 0.05) != null:
				return true
	return false


## A wall for sure between an ear `eye` over `g` and the whole leg from
## _leg_from to `p`: every point of it, CELL / 2 apart, each moved
## WALL_SOUND_SLACK four ways, from the ear and the ear moved WALL_EAR_SLACK
## four ways. One gap - a window, the doorway - and it is not.
func _leg_walled(g: Vector3, eye: float, p: Vector3) -> bool:
	if _leg_from == Vector3.INF:
		return false
	var n := maxi(1, ceili(Vector2(p.x - _leg_from.x, p.z - _leg_from.z).length() / (CELL * 0.5)))
	for i in n + 1:
		var at := _leg_from.lerp(p, float(i) / n)
		for b in WALL_OFFSETS:
			for a in WALL_OFFSETS:
				if not _walled_at(g + a * WALL_EAR_SLACK, eye, at + b * WALL_SOUND_SLACK):
					return false
	return true


## SoundWalls.walled for an ear `eye` over `feet` and a sound at `s`, both
## taken to 5 cm and remembered.
func _walled_at(feet: Vector3, eye: float, s: Vector3) -> bool:
	var fq := Vector3i((feet * 20.0).round())
	var sq := Vector3i((s * 20.0).round())
	var key := [fq, sq, roundi(eye * 20.0)]
	if _walled_seen.has(key):
		return bool(_walled_seen[key])
	if _walled_seen.size() > 200000:
		_walled_seen.clear()
	var f := Vector3(fq) / 20.0
	var walled := Stealth.SoundWalls.walled(space, tree, f, f + Vector3.UP * eye, Vector3(sq) / 20.0)
	_walled_seen[key] = walled
	return walled


func _off_limits(i: int) -> bool:
	return not reckless and not allow_scent and scent_zone.size() > i and scent_zone[i] == 1


func _frame() -> void:
	await super._frame()
	if shepherd != null and is_instance_valid(shepherd):
		if shepherd.trail_seq >= 0:
			trail_taken = true
		if noticed.has(str(shepherd.name)) and not _dog_turned:
			_dog_turned = true
			trail_when_turned = shepherd.trail_seq >= 0
	var at := player.global_position
	var c := cell_of(at)
	if inside(c) and Stealth.player_light > light[idx(c)] + LIGHT_SLACK:
		light_misses += 1
		light_gap = maxf(light_gap, Stealth.player_light - light[idx(c)])
	if flare._burn >= 0.0:
		var top := player.head.global_position - Vector3.UP * 0.25
		var now := maxf(Stealth._light_of(space, flare.light, top),
				Stealth._light_of(space, flare.light, at + Vector3.UP * Stealth.KNEES))
		if inside(c) and now > flare_light[idx(c)] + LIGHT_SLACK:
			flare_misses += 1
			flare_gap = maxf(flare_gap, now - flare_light[idx(c)])
		if not in_izba(at) and at.z > FOREST_FROM:
			flare_lit = maxf(flare_lit, now)


func _reach(smp: Dictionary) -> bool:
	stepped.append(smp["c"])
	return await super._reach(smp)


static func in_izba(p: Vector3) -> bool:
	return IZBA.has_point(Vector2(p.x, p.z))


## Where in the forest he makes for: the nearest cell to `from`, deep in the
## zone, he may stand on - a place to stop if there is one.
func forest_goal(from: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_safe := false
	for z in gh:
		for x in gw:
			var c := Vector2i(x, z)
			var p := center(c)
			var i := idx(c)
			if p.z < GOAL_Z.x or p.z > GOAL_Z.y or blocked[i] == 1 or _off_limits(i):
				continue
			var ok := stop_at(c, Posture.CROUCHED)
			if (best_safe and not ok) or (ok == best_safe and from.distance_to(p) >= from.distance_to(best)):
				continue
			best = p
			best_safe = ok
	return best


## Out of the door and to the forest; he stays there till the slice ends
## (forest_calm_needed, and a second: the last run is checked with it).
func escape_plan() -> Array[Dictionary]:
	var goal := forest_goal(player.global_position)
	if goal == Vector3.INF:
		events.append("no place in the forest")
		return []
	return make_plan([goal], float(level.get("forest_calm_needed")) + 1.0)


## From where he is through `points` in turn, staying `hold` at the last.
func make_plan(points: Array[Vector3], hold: float) -> Array[Dictionary]:
	route_points = points.duplicate()
	route_hold = hold
	return _plan_through(points, hold)


func _plan_through(points: Array[Vector3], hold: float) -> Array[Dictionary]:
	var s := begin()
	s[0]["wp"] = 0
	for w in points.size():
		var n := s.size()
		if not add_path(s, points[w], false):
			return []
		for j in range(n, s.size()):
			s[j]["wp"] = w
	s[s.size() - 1]["hold"] = hold
	finish(s)
	return s


# --- walking it: stops in time, not in place -------------------------------------------

func run(s: Array[Dictionary], time_limit: float) -> bool:
	if reckless:
		return await super.run(s, time_limit)
	var started := Stealth.clock
	var way := s
	var k := 0
	var waiting := 0.0
	var cornered := false
	while k < way.size() - 1:
		if failed != "":
			return false
		var up := _anyone_up()
		var last := way.size() - 1
		var m := k if up else _scan(way, k, float(way[last]["hold"]))
		if m > k:
			_waited(waiting)
			waiting = 0.0
			cornered = false
			for j in range(k + 1, m + 1):
				if not await _reach(way[j]):
					return false
			k = m
			continue
		if not up and not _can_stay():
			var away := _dodge()
			if not away.is_empty():
				_waited(waiting)
				waiting = 0.0
				dodges += 1
				events.append("slipped from %s to %s" % [_v(player.global_position), _v(away[away.size() - 1]["p"])])
				for j in range(1, away.size()):
					if not await _reach(away[j]):
						return false
				# The way on numbers its points from the ones left: they are
				# the route now (else a second dodge would count from the old).
				route_points = route_points.slice(int(way[k + 1]["wp"]))
				way = _plan_through(route_points, route_hold)
				if way.is_empty():
					_fail("no way on from %s" % _v(player.global_position))
					return false
				k = 0
				continue
			if not cornered:
				cornered = true
				events.append("nowhere to slip to at %s" % _v(player.global_position))
		stop()
		_crouch(true)
		var dt: float = await _pause()
		waiting += dt
		if up:
			frozen += dt
		if waiting > MAX_WAIT or Stealth.clock - started > time_limit:
			_fail("no clear run at %s (waited %.0f s) to %s" % [_v(player.global_position), waiting,
					_v(way[mini(k + 1, way.size() - 1)]["p"])])
			return false
	stop()
	_crouch(true)
	return failed == ""


## Stay about here until `done` says so or `seconds` run out, slipping away
## from anyone coming.
func hold_out(done: Callable, seconds: float) -> void:
	var left := seconds
	while left > 0.0 and failed == "" and not done.call():
		if not _anyone_up() and not _can_stay():
			var away := _dodge()
			if not away.is_empty():
				dodges += 1
				events.append("slipped from %s to %s" % [_v(player.global_position), _v(away[away.size() - 1]["p"])])
				for j in range(1, away.size()):
					if not await _reach(away[j]):
						return
		stop()
		_crouch(true)
		left -= await _pause()


# --- out of a hiding place (part "act1") ------------------------------------------------

## Off his round while the story walks him or holds him at a post - the
## squad's soldier behind the corner and on his look back in
## (docs/ARCHITECTURE.md, "Ложный уход"): [] - stay put, as for anyone up.
func ahead(w: Watcher, seconds: float) -> Array:
	if w.enemy.has_script_route() or (w.enemy.hold_position and not w.route.is_empty()):
		return []
	return super.ahead(w, seconds)

## May he come out of `spot` now (docs/ARCHITECTURE.md, "Акт I целиком")?
## Nobody up and everybody on his round (not walked or held by the story:
## ahead); nobody near enough to hear the lid
## (HideSpot.use_noise, crouched: Player.CAREFUL - walls not counted,
## BOARD_MARGIN on it, a dog at heel its lag behind the handler too); and
## where he comes out - where he got in (Player.exit_hide_spot) - clear for
## SAFE_AFTER, as any stop. The breath is the hider's business: the caller
## asks only with the key let go.
func may_come_out(spot: HideSpot) -> bool:
	if _anyone_up():
		return false
	var at: Vector3 = player._return_transform.origin
	var loud := spot.use_noise * Player.CAREFUL
	var lid := spot.global_position
	var aheads: Array = []
	var heard: Array = []
	for w in watchers:
		var a := ahead(w, SAFE_AFTER + 1.0)
		if a.is_empty():
			return false
		aheads.append(a)
		heard.append(0.0)
		if loud > 0.0:
			var hearing := w.dog.hearing if w.hear_r > 0.0 else w.enemy.hearing
			var g: Vector3 = (a[0] as Array)[0]
			var r := loud * Stealth.HEARING_RANGE * hearing + BOARD_MARGIN + w.heel + w.heel_slack + w.slack
			if Vector2(lid.x - g.x, lid.z - g.z).length() < r:
				return false
	return _clear(Vector3(at.x, 0.0, at.z), Posture.CROUCHED, 0.0, SAFE_AFTER, false, aheads, heard)


## Out of `spot`, crouched (the lid half as loud), with a press of the key as
## a player does it.
func come_out(spot: HideSpot) -> bool:
	stop()
	_crouch(true)
	await _press_event("interact")
	if player.is_hidden:
		_fail("could not get out of %s" % spot.name)
		return false
	events.append("came out of %s at %s" % [spot.name, _v(player.global_position)])
	return failed == ""


## Wait STEP or a little more: whole frames. Returns the game seconds it took.
func _pause() -> float:
	var t := 0.0
	while t < STEP and failed == "":
		await _frame()
		t += frame_time()
	return maxf(t, frame_time())


func _waited(waiting: float) -> void:
	if waiting > 0.0:
		waited += waiting
		longest_wait = maxf(longest_wait, waiting)
		events.append("waited %.1f s at %s" % [waiting, _v(player.global_position)])


## The farthest sample after `k` (SCAN_MAX at most) he can walk to from here
## now, every moment of the way unnoticed, and stay at unnoticed SAFE_AFTER
## more - the last one of `seq`, `last_hold` (when not negative); `k` when
## there is none. As feasible() in Act II, the dogs' ears added up on the way.
func _scan(seq: Array[Dictionary], k: int, last_hold := -1.0) -> int:
	var last := mini(seq.size() - 1, k + SCAN_MAX)
	var total := 0.0
	for j in range(k + 1, last + 1):
		total += float(seq[j]["dt"])
	var horizon := total + maxf(SAFE_AFTER, last_hold) + 1.0
	var aheads: Array = []
	var heard: Array = []
	for w in watchers:
		var a := ahead(w, horizon)
		if a.is_empty():
			return k
		aheads.append(a)
		heard.append(w.dog.suspicion if w.hear_r > 0.0 else 0.0)
	var arrive: Array[float] = []
	var heard_at: Array = []
	var tau := 0.0
	var reach := k
	for j in range(k + 1, last + 1):
		var smp := seq[j]
		var from := tau
		tau += float(smp["dt"])
		var here := player.global_position
		_leg_from = Vector3(here.x, 0.0, here.z) if j == k + 1 else (seq[j - 1]["p"] as Vector3)
		var ok := _clear(smp["p"], posture_at(smp), from, tau, true, aheads, heard)
		_leg_from = Vector3.INF
		if not ok:
			break
		reach = j
		arrive.append(tau)
		heard_at.append(heard.duplicate())
	for j in range(reach, k, -1):
		var stay := last_hold if j == seq.size() - 1 and last_hold >= 0.0 else SAFE_AFTER
		var t0: float = arrive[j - k - 1]
		if _clear(seq[j]["p"], Posture.CROUCHED, t0, t0 + stay, false, aheads,
				(heard_at[j - k - 1] as Array).duplicate()):
			return j
	return k


## Is a boy at `p` in `posture` unnoticed from `from` to `until` (seconds
## from now), walking there (on his way to it) or still? `heard`: what each
## dog has made of him so far, carried on.
func _clear(p: Vector3, posture: int, from: float, until: float, moving: bool, aheads: Array,
		heard: Array) -> bool:
	var t := from
	while true:
		var at := int(t / STEP)
		var next := minf(t + STEP, until)
		for i in watchers.size():
			var w := watchers[i]
			var a: Array = aheads[i]
			var pose: Array = a[mini(at, a.size() - 1)]
			if danger(w, p, pose, posture, moving):
				return false
			if w.hear_r > 0.0:
				var gain := dog_hears(w, p, pose) if moving and posture == Posture.UPRIGHT else 0.0
				heard[i] = maxf(float(heard[i]) + (gain - FADE) * (next - t), 0.0)
				if heard[i] > HEARD_MAX:
					return false
		if t >= until:
			break
		t = next
	return true


## Can he stay crouched where he is STAY_AHEAD more? (Somebody off his round:
## nothing to foresee - he keeps still.)
func _can_stay() -> bool:
	var aheads: Array = []
	var heard: Array = []
	for w in watchers:
		var a := ahead(w, STAY_AHEAD + 1.0)
		if a.is_empty():
			return true
		aheads.append(a)
		heard.append(0.0)
	var p := player.global_position
	return _clear(Vector3(p.x, 0.0, p.z), Posture.CROUCHED, 0.0, STAY_AHEAD, false, aheads, heard)


## The nearest place within DODGE_R he gets to unnoticed, crouched, and can
## stay at SAFE_AFTER: the walk there as samples ([]: none).
func _dodge() -> Array[Dictionary]:
	var here := player.global_position
	var from := cell_of(here)
	var r := int(DODGE_R / CELL)
	var cands: Array = []
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := from + Vector2i(dx, dz)
			var d := Vector2(dx, dz).length() * CELL
			if c == from or d > DODGE_R or not inside(c) or blocked[idx(c)] == 1 or _off_limits(idx(c)):
				continue
			cands.append([d, c])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	# The grid's solid cells are what the last plan() made them, with its
	# flags (allow_scent may have changed since): set the window afresh.
	for dz in range(-3 * r, 3 * r + 1):
		for dx in range(-3 * r, 3 * r + 1):
			var c := from + Vector2i(dx, dz)
			if inside(c):
				astar.set_point_solid(c, blocked[idx(c)] == 1 or _off_limits(idx(c)))
	var was_solid := astar.is_point_solid(from) if inside(from) else false
	if inside(from):
		astar.set_point_solid(from, false)
	var best: Array[Dictionary] = []
	for cand in cands:
		var cells: Array[Vector2i] = []
		cells.assign(astar.get_id_path(from, cand[1]))
		if cells.size() < 2 or cells.size() > 3 * r:
			continue
		var s: Array[Dictionary] = [sample(from, Vector3(here.x, 0.0, here.z), 0.0, Posture.CROUCHED)]
		var prev := Vector3(here.x, 0.0, here.z)
		for k in range(1, cells.size()):
			var p := center(cells[k])
			s.append(sample(cells[k], p, prev.distance_to(p) / speed_of(player, Posture.CROUCHED), Posture.CROUCHED))
			prev = p
		if _scan(s, 0) == s.size() - 1:
			best = s
			break
	if inside(from):
		astar.set_point_solid(from, was_solid)
	return best


## The distance from `p` to the strip's middle: the handler's beat.
func from_beat(p: Vector3) -> float:
	return dist_to_round(handler_w, p) if handler_w != null else INF
