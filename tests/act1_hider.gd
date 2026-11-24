extends RefCounted
## A careful player at the opening of Act I (docs/ARCHITECTURE.md, "Прятки в
## подполе и за печью"): in the prologue he reads the notice and takes the
## bread from the table; when the flare goes up he creeps to his hiding place
## (the cellar, behind the stove) and hides; there he holds his breath while
## anyone is near and lets it go for a sip only just after a heartbeat. The controls are a player's: move_forward,
## crouch, interact and hold_breath as input; the look is turned at once
## (Player.look_towards), as with a jerk of the mouse.
## What he knows: the heartbeat (a player hears it and sees the vignette), the
## air (the frame darkens, g_air) and how far the nearest enemy is - exactly,
## where a player guesses it from the steps and the torch in the slits. He
## lets go at the first physics frame after the beat: up to one frame (0.067
## game s at x4) late, never early - a player errs both ways.
## The controls (Breath): NEVER holds his breath; NO_SIPS holds while anyone
## is near and never lets go for a sip; OFF_BEAT does as CAREFUL, but lets go
## halfway between two heartbeats.

enum Breath { CAREFUL, NEVER, NO_SIPS, OFF_BEAT }

## Hold the breath while anyone is nearer than this: BreathControl's threat
## radius (6 m) and a metre to spare.
const HOLD_FROM := 7.0
## Let go for a sip when the air is below this...
const SIP_BELOW := 0.65
## ...within this many game seconds after a heartbeat, and inside the breath
## window (PanicSystem.beat_window: +-0.16 s calm, +-0.073 s at 165 bpm).
const AFTER_BEAT := 0.07
## OFF_BEAT lets go this close to the middle between two beats (in shares of
## the beat): 0.35..0.65 is never in the window (at most 0.2 of the beat each
## side), and the band (>= 0.109 s at 165 bpm) is longer than a frame at x4.
const MID_BEAT := 0.15
const ARRIVED := 0.2

var level: Node3D
var player: Player
var breath: BreathControl
var seq: InvasionSequence
var soldier: Enemy
var tree: SceneTree
var mode: int = Breath.CAREFUL
## End the run as soon as any enemy turns (a control that only has to show
## he was heard).
var stop_when_turned := false

var failed := ""
## The run is over (teardown): no sound is his any more.
var stopped := false
var caught_by := ""
## The breath sound he was caught on: a capture while the enemies are still
## hearing that sound (BreathControl emits it, then the noise; "" - caught
## some other way).
var gave_away := ""
var _sound_now := ""
var _heard: Callable
## The breath sounds an enemy heard (some suspicion rose on it), in order.
## The first is what put them on to him: found slowly (heard, then the dog
## smells him out and barks for the soldier, Enemy._check_target_spot), he
## is caught on no sound at all, but the first one heard gave him away.
var heard: Array[String] = []
## Each enemy's suspicion just before the sound (by instance id).
var _before: Dictionary = {}
var events: Array[String] = []
## Breath sounds he made (BreathControl.sound_made), but the pant.
var sounds: Array[String] = []
var beats: Array[int] = []
var read: Array[String] = []
## What he took, by item id -> the beat he took it in.
var took: Dictionary = {}
## The beat he hid at (-1: never).
var hid_at := -1
## How near the soldier came to the hiding place while he was in it.
var closest := INF
## How often a searcher checked his hiding place (HideSpot.searched), and the
## longest check in game seconds (to HideSpot.search_ended).
var checks := 0
var checked := 0.0
var _check_from := -1.0
## The hiding place's numbers (the runner fills them in): under_floor,
## check_time, damping.
var spot_info: Dictionary = {}
## Game seconds since setup, by the physics clock.
var clock := 0.0
## Seconds he held his breath in hiding; the least air he had.
var held := 0.0
var min_air := 1.0
## Each enemy's highest suspicion and worst state.
var peak: Dictionary = {}
var worst: Dictionary = {}
## Filled in by the runner at the end: the notice's document, still in the
## cellar, how often dust fell on him, what is in his satchel.
var notice_doc := ""
var still_hidden := false
var dust := 0
var bag: Array[String] = []


func setup(lv: Node3D, breath_mode: int) -> void:
	level = lv
	tree = lv.get_tree()
	mode = breath_mode
	player = lv.get_node("Player") as Player
	breath = player.get_node("BreathControl") as BreathControl
	seq = lv.get_node("Invasion") as InvasionSequence
	soldier = seq.soldier
	beats.append(int(seq.beat))
	seq.beat_changed.connect(func(b: InvasionSequence.Beat) -> void:
		beats.append(int(b))
		events.append("beat %s" % InvasionSequence.Beat.keys()[b]))
	breath.sound_made.connect(func(kind: String, loudness: float) -> void:
		# Once he has stopped playing, nothing is his: _fail and teardown let
		# go of every key, and that release would count as a sip on a beat
		# and as an exhale off it (still holding when the run is over).
		if kind == "pant" or failed != "" or stopped:
			return
		sounds.append(kind)
		if loudness > 0.0:
			_sound_now = kind  # until the enemies have heard it (below)
			_before = _suspicions()
		if kind != "sip":
			events.append("%s %.2f in %s" % [kind, loudness, beat_name()]))
	# Connected after every enemy: runs once they have all heard the noise.
	_heard = func(_p: Vector3, _l: float, _s: Node) -> void:
		if _sound_now != "":
			var now := _suspicions()
			if now.keys().any(func(id: int) -> bool: return float(now[id]) > float(_before.get(id, 1.0))):
				heard.append(_sound_now)
		_sound_now = ""
	Stealth.noise_emitted.connect(_heard)
	for e in tree.get_nodes_in_group("enemies"):
		(e as Enemy).player_caught.connect(func(by: Enemy) -> void:
			if caught_by == "":
				caught_by = str(by.name)
				gave_away = _sound_now
			_fail("caught by %s in %s" % [by.name, beat_name()]))


func _suspicions() -> Dictionary:
	var out := {}
	for e in tree.get_nodes_in_group("enemies"):
		out[e.get_instance_id()] = (e as Enemy).suspicion
	return out


func teardown() -> void:
	stopped = true
	release_all()
	if _heard.is_valid() and Stealth.noise_emitted.is_connected(_heard):
		Stealth.noise_emitted.disconnect(_heard)


func beat_name() -> String:
	return InvasionSequence.Beat.keys()[seq.beat]


func _fail(why: String) -> void:
	if failed == "":
		failed = why
		events.append("FAILED: " + why)
	release_all()


func release_all() -> void:
	for a in ["move_forward", "crouch", "sprint", "hold_breath"]:
		Input.action_release(a)


## Game seconds a physics frame moves on (the runner speeds the game up).
static func frame_time() -> float:
	return Engine.time_scale / Engine.physics_ticks_per_second


# --- one frame -------------------------------------------------------------------------

func _frame() -> void:
	if player.is_hidden:
		_breathe()
	else:
		Input.action_release("hold_breath")
	await tree.physics_frame
	clock += frame_time()
	if player.is_hidden:
		var c := player.current_hide_spot.global_position
		var s := soldier.global_position
		closest = minf(closest, Vector2(s.x - c.x, s.z - c.z).length())
		min_air = minf(min_air, breath.air)
		if breath.holding:
			held += frame_time()
	for e in tree.get_nodes_in_group("enemies"):
		var en := e as Enemy
		var key := str(en.name)
		peak[key] = maxf(float(peak.get(key, 0.0)), en.suspicion)
		if int(en.state) > int(worst.get(key, 0)):
			worst[key] = int(en.state)
			events.append("%s %s in %s" % [key, Enemy.State.keys()[en.state], beat_name()])
			if stop_when_turned:
				_fail("%s turned" % key)


## The breath in hiding, decided before BreathControl reads the button in
## this same physics frame.
func _breathe() -> void:
	var near := breath.nearest_enemy_distance() < HOLD_FROM
	match mode:
		Breath.NEVER:
			Input.action_release("hold_breath")
		Breath.NO_SIPS:
			# Holds while they are near and lets go when they are gone - but
			# knows nothing of the heartbeat.
			if near:
				Input.action_press("hold_breath")
			else:
				Input.action_release("hold_breath")
		Breath.OFF_BEAT:
			var between := absf(PanicSystem.beat_phase - 0.5) < MID_BEAT
			if Input.is_action_pressed("hold_breath"):
				if between and (not near or breath.air < SIP_BELOW):
					Input.action_release("hold_breath")
			elif near:
				Input.action_press("hold_breath")
		_:
			var since_beat := PanicSystem.beat_phase * PanicSystem.beat_period()
			var just_beat := since_beat <= minf(AFTER_BEAT, PanicSystem.beat_window())
			if Input.is_action_pressed("hold_breath"):
				# Let go only just after a beat: near them when the air runs
				# low (a sip), away from everyone to breathe.
				if just_beat and (not near or breath.air < SIP_BELOW):
					Input.action_release("hold_breath")
			elif near:
				Input.action_press("hold_breath")


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


# --- what he does ----------------------------------------------------------------------

func walk(to: Vector3, crouched: bool) -> bool:
	if crouched:
		Input.action_press("crouch")
	else:
		Input.action_release("crouch")
	var stuck := 0.0
	var last := player.global_position
	while failed == "":
		var here := player.global_position
		if Vector2(to.x - here.x, to.z - here.z).length() < ARRIVED:
			Input.action_release("move_forward")
			return true
		player.look_towards(Vector3(to.x, player.head.global_position.y, to.z))
		Input.action_press("move_forward")
		await _frame()
		stuck = stuck + frame_time() if player.global_position.distance_to(last) < 0.002 else 0.0
		last = player.global_position
		if stuck > 1.5:
			_fail("stuck at %s going to %s" % [here, to])
	Input.action_release("move_forward")
	return false


func take(pickup: Pickup) -> bool:
	Input.action_release("move_forward")
	await seconds(0.3)
	var item := pickup.item
	var what := str(pickup.name)
	var beat := int(seq.beat)
	player.look_towards(pickup.global_position)
	await _frame()
	if failed != "":
		return false
	await _press_event("interact")
	if not Inventory.items().has(item):
		_fail("could not take %s from %s" % [what, player.global_position])
		return false
	took[item.id] = beat
	events.append("took %s in %s" % [item.id, InvasionSequence.Beat.keys()[beat]])
	if player.archive_ui.is_open:
		# A document: the world stops while he reads it; E puts it away.
		read.append(item.document_id)
		for _f in 10:
			await tree.process_frame
		await _press_event("interact")
		if player.archive_ui.is_open:
			_fail("the document would not close")
			return false
	await seconds(0.2)
	return failed == ""


func hide_in(spot: HideSpot) -> bool:
	Input.action_release("move_forward")
	spot.searched.connect(func(_by: Node) -> void:
		checks += 1
		_check_from = clock)
	spot.search_ended.connect(func(_by: Node) -> void:
		if _check_from >= 0.0:
			checked = maxf(checked, clock - _check_from)
		_check_from = -1.0)
	await _frame()
	# At the middle of the place (its shape), as a player puts the cross on it.
	var shape := spot.get_node_or_null("Shape") as Node3D
	player.look_towards(shape.global_position if shape != null else spot.global_position)
	await _frame()
	if failed != "":
		return false
	var beat := int(seq.beat)
	await _press_event("interact")
	if not player.is_hidden:
		_fail("could not get into %s from %s" % [spot.name, player.global_position])
		return false
	hid_at = beat
	events.append("hid in %s in %s" % [spot.name, beat_name()])
	return true


## The opening as a careful player plays it: the table in the prologue, the
## hiding place at the flare (crouched, along `route`), the breath through
## the search, until the beat `until` (the escape) and `after_escape`
## seconds more.
func play(notice: Pickup, bread: Pickup, spot: HideSpot, at_table: Vector3, route: Array[Vector3],
		after_escape: float, until := InvasionSequence.Beat.ESCAPE) -> bool:
	if not await walk(at_table, false):
		return false
	if not await take(notice):
		return false
	if not await take(bread):
		return false
	if not await wait_until(func() -> bool: return seq.beat != InvasionSequence.Beat.PROLOGUE,
			60.0, "the flare"):
		return false
	for point in route:
		if not await walk(point, true):
			return false
	if not await hide_in(spot):
		return false
	if not await wait_until(func() -> bool: return int(seq.beat) >= int(until),
			180.0, "the beat %s" % InvasionSequence.Beat.keys()[until]):
		return false
	await seconds(after_escape)
	return failed == ""


## A key pressed and let go as an input event (what the document view listens
## to: Input.action_press makes no event).
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
