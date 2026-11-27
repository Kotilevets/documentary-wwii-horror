extends Node
## Playthrough of Act II by a careful bot (tests/act2_bot.gd; docs/ARCHITECTURE.md,
## "Проходимость Акта II"): can a careful player get through the burned
## village past the policeman on his round, round the outpost, from the field
## past the barbed wire, the searchlight, the camp guard and his dog to the
## forest - under the wire (torn, bleeding, a bandage) and by the road - and
## do the searchlight and the policeman really stop one who just walks? Can
## he, careful, also see and take everything the act has (the witness)?
## And Act I's opening with the breath on (tests/act1_hider.gd; "Прятки в
## подполе и за печью"): can a careful boy sit out the search in the cellar
## and behind the stove, and do a sob, a gasp and a breath out of time really
## give him away? And Act I's escape (tests/act1_escaper.gd; "Побег к лесу:
## Акт I"): can a careful boy get out of the izba to the forest past the
## soldier with the shepherd, the gendarme and the policeman, under the
## flares - and do walking straight there and crossing the dog's beat really
## give him away? And all of Act I in one run ("Акт I целиком"): from the
## cellar, from behind the stove, out once the squad has gone and on to the
## forest - and does the opening leave the world the escape starts from?
## And all of Act III (tests/act3_bot.gd; "Проходимость Акта III"): from the
## briefing through the pass check, the checkpoint, three things remembered
## in the garrison without staring under anyone's eyes, the round-up and the
## interrogation held by the legend, to the forest - and does staring in a
## patrol's sight really draw his eyes?
## Run:  godot --headless --path . res://tests/playthrough_runner.tscn [-- --map] [--only=gap]
## (--map also draws shots/act2_searchlight_map.png and shots/act1_escape_map.png;
## --only= runs one part: light, village, whole, witness, gap, road, camp,
## reckless, street, ears, cellar, stove, escape, act1, door, act3).
## And the door opened in the prologue ("Дверь открыта в прологе"): in the
## hay the shepherd comes along his trail and smells him out; in the cellar
## he sits out the same search, only without the knock.
## Exit code = failures + errors (tests/run_guard.gd). Game time runs x4.

const ACT2_PATH := "res://src/scenes/act2_road/act2_road.tscn"
const Bot := preload("res://tests/act2_bot.gd")
const ACT1_PATH := "res://src/scenes/act1_village/act1_village.tscn"
const Hider := preload("res://tests/act1_hider.gd")
const Escaper := preload("res://tests/act1_escaper.gd")
const ACT3_PATH := "res://src/scenes/act3_garrison/act3_garrison.tscn"
const ACT3_SCRIPT := preload("res://src/scenes/act3_garrison/act3_garrison.gd")
const Courier := preload("res://tests/act3_bot.gd")
## Act III: in the forest zone past the exit gate (ForestEdge, z -125..-119);
## where he stands on the street to stare at the trucks (the eyes control);
## his place for the drums in the whole act, and where the patrol is put
## walking south up the street to it, the place before his eyes.
const ACT3_FOREST := Vector3(0, 0, -122.5)
const ACT3_IN_SIGHT := Vector3(0, 0, -64)
const ACT3_DRUMS_AT := Vector3(8.5, 0, -64)
const ACT3_PATROL_UP := Vector3(1.5, 0, -76)
## Where the hider stands to take the things from the table (Act I izba), and
## the way he crouches to each hiding place: to the cellar (south of the hatch
## at -0.6, 5.4, between it and the table; -Z is north), and behind the stove
## (the nook at 2.1, 8.0 opens west: past the stove's west side to its mouth).
const AT_TABLE := Vector3(-1.35, 0, 6.3)
const TO_HATCH: Array[Vector3] = [Vector3(-0.6, 0, 6.5)]
const TO_NOOK: Array[Vector3] = [Vector3(0.5, 0, 6.5), Vector3(0.8, 0, 8.0)]
## Act I, the door opened in the prologue: where he stands to reach the
## latch (inside, out of the leaf's swing: it turns in about its hinge at
## 0.9, 3.6, 1.2 m wide, and at x4 a frame turns it some 16 degrees - a boy
## in its arc can be shoved through to its far side), the way from there
## out of the door and across the road to the barn (gate in its west wall at
## x 9, z -5.4..-2.6), to about 2 m from the middle of the hay (13.6, -5.2);
## and to the cellar: first a look out over the threshold, then back to the
## hatch. The look lays his trail where the shepherd stops in the doorway
## when the squad leaves (1.4, 3.9..4.1). Without it his nearest point there
## was the one laid on the way from the table (1.4, 5.5), 1.48 or 1.60 m
## from the dog as it happened to stop, and it takes a trail only nearer
## than 1.6 m ("Дверь открыта в прологе", review 8). The spot is over a
## metre from that point even if he stops 0.2 m short of it (a step nearer
## than a metre only freshens the last point), and 2 m from where the dog
## waits through the search (1.9, 2.2), so it does not take it early.
const AT_LATCH := Vector3(2.2, 0, 5.3)
const TO_BARN: Array[Vector3] = [Vector3(1.5, 0, 4.2), Vector3(1.6, 0, 2.6), Vector3(5, 0, -1.2),
		Vector3(8.6, 0, -4), Vector3(10.5, 0, -4), Vector3(12.2, 0, -4.0)]
const AT_THRESHOLD := Vector3(1.6, 0, 4.2)
const LATCH_TO_HATCH: Array[Vector3] = [Vector3(0.6, 0, 6.0), Vector3(-0.6, 0, 6.5)]
const BANDAGE_PATH := "res://assets/data/items/bandage.tres"
const BREAD_PATH := "res://assets/data/items/bread.tres"
const SPEED := 4.0
## In the forest zone (ForestEdge, z -141..-149).
const FOREST := Vector3(9, 0, -144.5)
## Act I: a point on the road by the izba, half a metre from where the
## shepherd walks south at heel (the scent control).
const ROAD := Vector3(4.5, 0, 0.5)
## Act I: in the open between the gendarme's round and the policeman's beat
## (the eyes control).
const EYES_ON := Vector3(1.5, 0, -16)

var failures := 0
var passes := 0
var _traces: Array = []  # [name, PackedVector3Array] for the map
var _map_bot: Bot = null
var _checkpoints_at: Array[Vector3] = []
var _only := ""
## tests/run_guard.gd: errors are failures, a hung run ends. Untyped, so that
## this script still loads when that one does not (and then says so: _guarded).
@onready var _guard = $RunGuard
## How each memory of the witness run ended (MemoryFlash.ended: cut off?).
var _memories: Array[bool] = []
## Act I's escape for the map: its bot and its walks.
var _escape_bot: Escaper = null
var _escape_traces: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# A level's failure path that reloads the current scene reloads the runner
	# itself: the guard sees the second load, says so and quits (the part left
	# that failure path open).
	if not _guarded():
		Engine.time_scale = 1.0
		return
	GameState.save_path = "user://test_playthrough.json"
	GameState.reset()
	await _run()
	Engine.time_scale = 1.0
	_guard.finish(passes, failures)


## Whether the run may start: not without the guard (tests/run_guard.gd did
## not load - this runner then quits at once, or it would hang at its end),
## not when the guard found this scene loaded a second time (it quits).
func _guarded() -> bool:
	if _guard == null or not _guard.has_method(&"finish"):
		print("FAIL  tests/run_guard.gd did not load: no run without the guard (a parse error above)")
		print("\n0 passed, 1 failed")
		get_tree().quit(1)
		return false
	return _guard.first_start()


func check(cond: bool, name: String, detail: Variant = "") -> void:
	if cond:
		passes += 1
		print("PASS  ", name)
	else:
		failures += 1
		print("FAIL  ", name, "  ", detail)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


const PARTS := ["light", "village", "whole", "witness", "gap", "road", "camp", "reckless", "street", "ears",
		"cellar", "stove", "escape", "act1", "door", "act3"]


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=")
	# A misspelt part would run nothing and pass.
	if _only != "" and not PARTS.has(_only):
		check(false, "--only= is one of %s" % [PARTS], _only)
		return
	if _part("light"):
		await _light_map()
	if _part("village"):
		await _route("from the village to the field", "Village", false, [], _field_plan, "Field")
	if _part("whole"):
		await _route("the whole act: the summons, under the wire", "Start", false, [], _whole_plan)
	if _part("witness"):
		await _route("the witness: everything in the act, under the wire", "Start", false, [], _witness_plan)
	if _part("gap"):
		await _route("under the wire, bandaged", "Field", false, [[BREAD_PATH, 1]], _gap_plan)
	if _part("road"):
		await _route("by the road past the guard", "Field", false, [[BREAD_PATH, 1]], _road_plan)
	if _part("camp"):
		await _route("back at the camp bleeding, no bandage", "Camp", true, [], _forest_plan)
	if _part("reckless"):
		await _reckless()
	if _part("street"):
		await _street()
	if _part("ears"):
		await _dog_ears()
	if _part("cellar"):
		await _hiding("the cellar", "CellarHatch", TO_HATCH)
	if _part("stove"):
		await _hiding("behind the stove", "StoveNook", TO_NOOK)
	if _part("escape"):
		await _escape()
		await _escape_reckless()
		await _escape_eyes()
		await _escape_scent()
	if _part("act1"):
		await _whole_act1("the cellar", "CellarHatch", TO_HATCH)
		await _whole_act1("behind the stove", "StoveNook", TO_NOOK)
	if _part("door"):
		await _door()
	if _part("act3"):
		await _act3()
		await _act3_eyes()
		await _act3_patrol()
	if OS.get_cmdline_user_args().has("--map"):
		_draw_map()
		_draw_escape_map()


## Whether part `name` runs; when it does, tests/run_guard.gd names the
## errors logged from now on with it.
func _part(name: String) -> bool:
	var run := _only == "" or _only == name
	if run:
		_guard.begin(name)
	return run


# --- a level to play -----------------------------------------------------------------

## Act II brought back at checkpoint `at` (as after a capture), the navmesh
## baked, the bot's grid built.
func _level(at: String, bleeding: bool, items: Array) -> Node3D:
	PanicSystem.reset()
	Perception.reset()
	Stealth.clear_scent()
	Stealth.reset_cover()
	Inventory.clear()
	var lv := (load(ACT2_PATH) as PackedScene).instantiate()
	lv.play_intro = false
	lv.next_level = ""
	var at_index: int = (lv.checkpoints as Array).find(at)
	LevelBase._checkpoint = {"scene": ACT2_PATH, "index": at_index, "items": items, "documents": [],
			"taken": [], "hunger": 0.65, "bleeding": bleeding, "bled_for": 20.0 if bleeding else 0.0}
	LevelBase._resume_after_intro = at_index >= 0
	add_child(lv)
	var nav := lv.get_node("Navigation") as RuntimeNavRegion
	var t0 := Time.get_ticks_msec()
	while not nav.is_baked and Time.get_ticks_msec() - t0 < 15000:
		await get_tree().physics_frame
	await frames(2)
	return lv


func _done_with(lv: Node3D) -> void:
	Engine.time_scale = 1.0
	lv._ending = true
	lv.queue_free()
	await frames(3)
	LevelBase._checkpoint = {}
	LevelBase._resume_after_intro = false
	Inventory.clear()
	TraumaEcho.forget_all()  # the next part's echoes do not depend on the order


# --- the light of the searchlight ------------------------------------------------------

## Where the beam reaches; that the bot's prediction is the tower's own beam;
## that a boy brought back to a checkpoint is never in it.
func _light_map() -> void:
	var lv := await _level("Field", false, [])
	var bot := Bot.new()
	var t0 := Time.get_ticks_msec()
	bot.setup(lv)
	print("grid built in %d ms" % (Time.get_ticks_msec() - t0))
	_map_bot = bot
	var tower := bot.tower
	var player := bot.player
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(false)
	# Prediction against the tower: the beam's direction, and every moment
	# the tower itself finds the boy in the beam.
	tower.exposure_needed = 1.0e9
	var worst_axis := 0.0
	var missed: Array = []
	var lit_frames := 0
	Engine.time_scale = SPEED
	# The gap's near side (lit standing up), where Camp was before 17.11.2026
	# (lit), the open field by the camp and on to the gallows.
	var probes: Array[Vector3] = [bot.gap.side_point(1.0), Vector3(10, 0, -89.5),
			Vector3(16, 0, -104), Vector3(14, 0, -123)]
	for probe in probes:
		player.global_position = Vector3(probe.x, 0.0, probe.z)
		await frames(2)
		var c := bot.cell_of(probe)
		# Two whole sweeps of game time (the game runs SPEED times faster).
		var t := 0.0
		while t < 2.0 * tower.sweep_period:
			await get_tree().physics_frame
			t += Bot.frame_time()
			var actual := -tower.lamp.global_basis.z
			worst_axis = maxf(worst_axis, rad_to_deg(actual.angle_to(bot.beam_axis(bot.yaw_at(tower._t)))))
			if tower.in_beam(player):
				lit_frames += 1
				if not bot.lit_at(c, Bot.Posture.UPRIGHT, tower._t):
					missed.append([probe, snappedf(tower._t, 0.01)])
	Engine.time_scale = 1.0
	check(worst_axis < 0.5, "the bot's beam is the tower's beam", worst_axis)
	print("beam: the tower found the boy in %d frames at %d probes" % [lit_frames, probes.size()])
	check(lit_frames > 100 and missed.is_empty(),
			"every moment the tower finds the boy in its beam, the bot saw it coming", [lit_frames, missed.slice(0, 5)])
	# The numbers for the docs.
	var gap_c := bot.cell_of(bot.gap.side_point(1.0))
	print("beam: the gap's near side is lit %.1f s of every %.0f s (upright), under the wire %.1f s"
			% [bot.lit_seconds(gap_c, Bot.Posture.UPRIGHT), tower.sweep_period,
			bot.lit_seconds(bot.cell_of(bot.gap.global_position), Bot.Posture.CRAWLING)])
	var reach := 0
	var free := 0
	for i in bot.gw * bot.gh:
		if bot.blocked[i] == 0:
			free += 1
			if (bot.lit_bits[i] & 1) != 0:
				reach += 1
	print("beam: reaches %d m2 of open ground (crouched)" % int(reach * Bot.CELL * Bot.CELL))
	# A boy brought back to a checkpoint is in shadow (never in the beam):
	# else he is lit before he can move and caught again, and again.
	var lit_at: Array = []
	for name in lv.checkpoints:
		var m := lv.get_node("Spawns/" + name) as Node3D
		_checkpoints_at.append(m.global_position)
		var c := bot.cell_of(m.global_position)
		for posture in [Bot.Posture.CROUCHED, Bot.Posture.UPRIGHT]:
			if not bot.dark(c, posture):
				lit_at.append("%s %s %.1f s per sweep" % [name, Bot.Posture.keys()[posture],
						bot.lit_seconds(c, posture)])
	check(lit_at.is_empty(), "every checkpoint is out of the searchlight's reach", lit_at)
	await _done_with(lv)


# --- routes ---------------------------------------------------------------------------

func _gap_plan(bot: Bot, lv: Node3D) -> Array[Dictionary]:
	var s := bot.begin()
	var bandage := lv.get_node("Layout/Pickup_bandage") as Pickup
	if not (bot.add_pick(s, bandage) and bot.add_crawl(s) and bot.add_path(s, FOREST, true)):
		return []
	bot.bind_after_crawl(s)
	bot.finish(s)
	return s


## From the Village checkpoint (brought back there as after a capture: the
## policeman 4 m ahead, his back to him) to the Field checkpoint.
func _field_plan(bot: Bot, lv: Node3D) -> Array[Dictionary]:
	var s := bot.begin()
	if not bot.add_path(s, (lv.get_node("Spawns/Field") as Node3D).global_position, false):
		return []
	bot.finish(s)
	return s


## The act from its first step: the summons on the post by the policeman's
## round, the field (saved there), the bandage, under the wire, the forest.
func _whole_plan(bot: Bot, lv: Node3D) -> Array[Dictionary]:
	var s := bot.begin()
	var summons := lv.get_node("Layout/Pickup_doc_arbeitsamt_summons") as Pickup
	var field := (lv.get_node("Spawns/Field") as Node3D).global_position
	var bandage := lv.get_node("Layout/Pickup_bandage") as Pickup
	if not (bot.add_pick(s, summons) and bot.add_path(s, field, false) and bot.add_pick(s, bandage)
			and bot.add_crawl(s) and bot.add_path(s, FOREST, true)):
		return []
	bot.bind_after_crawl(s)
	bot.finish(s)
	return s


## The act missing nothing (docs/ARCHITECTURE.md, "Проходимость Акта II",
## "свидетель"): the memory at the ruin, seen through; the bread from that
## house's stove, taken crouched and eaten at the next safe place; the
## summons; the field; the bandage; under the wire; the gallows, looked at
## from a safe place on his way till they are in his eyes; the forest.
func _witness_plan(bot: Bot, lv: Node3D) -> Array[Dictionary]:
	var s := bot.begin()
	var mem := lv.get_node("Layout/BurnedVillage/Memory") as MemoryFlash
	_memories.clear()
	mem.ended.connect(func(cut: bool) -> void: _memories.append(cut))
	var zone := mem.find_children("*", "CollisionShape3D", false, false)[0] as CollisionShape3D
	var box := zone.global_position
	var half := (zone.shape as BoxShape3D).size * 0.5
	var focus := mem.focus.global_position
	# Inside the place (with his body), farther than it asks, near enough to
	# see the house.
	var to_remember := func(p: Vector3) -> bool:
		var d := Vector2(p.x - focus.x, p.z - focus.z).length()
		return absf(p.x - box.x) < half.x - 0.6 and absf(p.z - box.z) < half.z - 0.6 \
				and d >= mem.min_distance + 1.0 and d <= 8.0
	var remembered := func() -> bool: return mem.used and not mem.active
	var sight := lv.get_node("Layout/Gallows/Sight") as DreadSight
	var to_see := func(p: Vector3) -> bool:
		return Vector2(p.x - sight.global_position.x, p.z - sight.global_position.z).length() <= sight.distance - 2.0
	var seeing := func() -> bool: return sight.looking
	var bread := lv.get_node("Layout/Pickup_bread") as Pickup
	var summons := lv.get_node("Layout/Pickup_doc_arbeitsamt_summons") as Pickup
	var field := (lv.get_node("Spawns/Field") as Node3D).global_position
	var bandage := lv.get_node("Layout/Pickup_bandage") as Pickup
	if not (bot.add_look(s, focus, 1.0, to_remember, false, remembered) and bot.add_pick(s, bread, false)):
		return []
	var took_bread := s.size() - 1
	if not (bot.add_pick(s, summons) and bot.add_path(s, field, false) and bot.add_pick(s, bandage)
			and bot.add_crawl(s)):
		return []
	var crawled := s.size() - 1
	if not bot.add_path(s, FOREST, true):
		return []
	bot.bind_after_crawl(s)
	if not bot.look_on_the_way(s, crawled, sight.global_position, 0.5, to_see, true, seeing):
		return []
	if not bot.at_next_stop(s, took_bread, Bot.Act.EAT, 1.5):
		bot.events.append("nowhere to stop and eat after the bread")
		return []
	bot.finish(s)
	return s


func _road_plan(bot: Bot, _lv: Node3D) -> Array[Dictionary]:
	var s := bot.begin()
	if not bot.add_path(s, FOREST, false):
		return []
	bot.finish(s)
	return s


func _forest_plan(bot: Bot, _lv: Node3D) -> Array[Dictionary]:
	var s := bot.begin()
	if not bot.add_path(s, FOREST, bot.player.wound.bleeding):
		return []
	bot.finish(s)
	return s


## Play route `name` from checkpoint `at` (or "Start") to the forest - or,
## with `goal`, until that checkpoint is saved.
func _route(name: String, at: String, bleeding: bool, items: Array, make: Callable, goal := "") -> void:
	var lv := await _level(at, bleeding, items)
	var bot := Bot.new()
	bot.setup(lv)
	var finished := [false]
	lv.slice_finished.connect(func() -> void: finished[0] = true)
	var goal_index: int = (lv.checkpoints as Array).find(goal) if goal != "" else -1
	var arrived := func() -> bool:
		return lv.checkpoint_index >= goal_index if goal_index >= 0 else finished[0]
	var s: Array[Dictionary] = make.call(bot, lv)
	check(not s.is_empty(), "%s: there is a way" % name, bot.events)
	if s.is_empty():
		await _done_with(lv)
		return
	var lit_run := 0
	for smp in s:
		if not smp["dark"]:
			lit_run += 1
	var clock0 := Stealth.clock
	Engine.time_scale = SPEED
	var walked_through := await bot.run(s, 600.0)
	if walked_through:
		await bot.wait_for(arrived, 15.0)
	bot.release_all()
	var took := Stealth.clock - clock0
	var p := bot.player
	print("--- %s: %.0f s, walked %.0f m, waited %.0f s (longest %.0f s), frozen %.0f s, beam exposure %.2f, drops %d, bound %s"
			% [name, took, bot.walked, bot.waited, bot.longest_wait, bot.frozen, bot.max_exposure,
			p.wound.drops, bot.bound])
	var closest := ""
	for key in bot.peak:
		if float(bot.peak[key]) > 0.0:
			closest += " %s %.2f" % [key, float(bot.peak[key])]
	print("      most suspicion:", closest if closest != "" else " none")
	for e in bot.events:
		print("      ", e)
	check(arrived.call() and bot.failed == "", "%s: a careful player gets to %s"
			% [name, ("the %s checkpoint, saved" % goal) if goal != "" else "the forest"],
			[bot.failed, Bot._v(p.global_position), lv.checkpoint_index])
	check(bot.noticed.is_empty(), "%s: nobody so much as turns to look" % name, bot.noticed)
	# Stricter than turning (0.35): the bot's own margin on a dog's ears. A
	# closer call than that is luck, not care.
	var worst := 0.0
	for key in bot.peak:
		worst = maxf(worst, float(bot.peak[key]))
	check(worst <= Bot.HEARD_MAX, "%s: nobody's suspicion gets past %.1f" % [name, Bot.HEARD_MAX], bot.peak)
	# Not "no alarm" (0.7 s in the beam): a careful player waits it out and is
	# never in it at all - else his waiting is luck, not the beam's rhythm.
	check(bot.max_exposure == 0.0, "%s: the beam never touches him" % name, bot.max_exposure)
	if name.contains("under the wire"):
		check(bot.crawled and bot.bound, "%s: crawled under the wire, bound the wound" % name,
				[bot.crawled, bot.bound])
	if name.begins_with("the whole act"):
		check(bot.read.has("act2_arbeitsamt_summons") and GameState.archive.has("act2_arbeitsamt_summons"),
				"%s: took the summons off the post and read it" % name, [bot.read, GameState.archive])
		# Saved there on the way, not just some later point (Camp is on the way too).
		var field: int = (lv.checkpoints as Array).find("Field")
		check(field >= 0 and bot.saved.has(field), "%s: saved at the field on the way" % name,
				[field, bot.saved])
	if name.begins_with("the witness"):
		check(_memories.size() == 1 and not _memories[0], "%s: the memory came once and ended by itself, never cut off" % name,
				_memories)
		check(bot.events.has("took bread") and bot.ate and not Inventory.has_item("bread"),
				"%s: took the bread from the stove and ate it" % name, bot.events)
		check(bot.read.has("act2_arbeitsamt_summons"), "%s: took the summons off the post and read it" % name,
				bot.read)
		var sight := lv.get_node("Layout/Gallows/Sight") as DreadSight
		check(sight.seen and bot.looked.has(sight.global_position),
				"%s: saw the gallows, looking at them himself" % name, [sight.seen, bot.looked])
	_traces.append([name, bot.trace])
	await _done_with(lv)


## The control: straight across the open field, upright, beam or no beam.
## The searchlight must stop him - else the careful runs prove nothing.
func _reckless() -> void:
	var lv := await _level("Camp", false, [])
	var bot := Bot.new()
	bot.reckless = true
	bot.setup(lv)
	var s := bot.begin()
	var finished := [false]
	lv.slice_finished.connect(func() -> void: finished[0] = true)
	if bot.add_path(s, FOREST, false):
		bot.finish(s)
		Engine.time_scale = SPEED
		if await bot.run(s, 120.0):
			await bot.wait_end(finished, 15.0)
	bot.release_all()
	print("--- reckless: ", bot.failed)
	check(bot.failed.begins_with("searchlight alarm") and not finished[0],
			"walking straight across the open field the searchlight finds him", [bot.failed, finished[0]])
	_traces.append(["reckless", bot.trace])
	await _done_with(lv)


## The control for the dog's ears: upright to and fro 8-9 m off the camp
## dog's way (x 5.5 against its heel at x -2.2), the searchlight off. Its
## eyes (7.8 m) and the guard's (10.4 m, 40 degrees) do not reach him there,
## nor do the guard's ears (7 m): the dog must turn by ear. And the bot's own
## count of what it heard must have passed HEARD_MAX first - else the careful
## runs' "the dog hardly hears him" is only the bot's word.
func _dog_ears() -> void:
	var lv := await _level("Camp", false, [])
	var tower := lv.get_node("Layout/Camp/Tower")
	tower.set_process(false)
	tower.set_physics_process(false)
	var player := lv.get_node("Player") as Player
	player.global_position = Vector3(5.5, 0.0, -90.0)
	await frames(2)
	var bot := Bot.new()
	bot.reckless = true
	bot.stop_when_noticed = true
	bot.setup(lv)
	var s := bot.begin()
	var ok := true
	for k in 6:
		ok = ok and bot.add_path(s, Vector3(5.5, 0.0, -104.0 if k % 2 == 0 else -92.0), false)
	if ok:
		bot.finish(s)
		Engine.time_scale = SPEED
		await bot.run(s, 120.0)
	bot.release_all()
	var at_turn: float = bot.ears_when_turned.get("CampDog", -1.0)
	print("--- alongside the dog: %s, saw %s, the bot's count when it turned %.2f"
			% [bot.failed, bot.saw, at_turn])
	check(bot.failed == "noticed by CampDog" and not bot.saw.get("CampDog", true) and at_turn >= Bot.HEARD_MAX,
			"walking upright alongside the camp dog, it hears him - and the bot's count said so first",
			[bot.failed, bot.saw, at_turn])
	_traces.append(["dog ears", bot.trace])
	await _done_with(lv)


## The controls for the village: upright straight up the street, the
## policeman or no policeman. He must turn - else the careful runs through
## the village prove nothing. From behind he hears the boy long before he
## could see him, so the second run makes him deaf: then only his eyes can
## stop the boy, and the careful runs keep out of his sight, not only out of
## earshot.
func _street() -> void:
	for deaf: bool in [false, true]:
		var lv := await _level("Start", false, [])
		if deaf:
			(lv.get_node("VillagePolizei") as Enemy).hearing = 0.0
		var bot := Bot.new()
		bot.reckless = true
		bot.stop_when_noticed = true
		bot.setup(lv)
		var s := bot.begin()
		if bot.add_path(s, Vector3(0, 0, -40), false):
			bot.finish(s)
			Engine.time_scale = SPEED
			if await bot.run(s, 120.0):
				# Up the street and not yet seen: stay there; he comes this way.
				await bot.wait_for(func() -> bool: return not bot.noticed.is_empty(), 60.0)
		bot.release_all()
		var how := "by eye, deaf" if deaf else "by ear"
		print("--- up the street (%s): %s, %s" % [how, bot.failed, bot.saw])
		if deaf:
			check(bot.noticed.has("VillagePolizei") and bot.saw.get("VillagePolizei", false),
					"walking up the street the policeman, deaf, sees him", [bot.failed, bot.saw])
		else:
			check(bot.noticed.has("VillagePolizei"), "walking up the street the policeman turns",
					[bot.failed, bot.noticed])
		_traces.append(["street", bot.trace])
		await _done_with(lv)


# --- Act I: hiding in the izba ----------------------------------------------------------

## The opening of Act I played through with the breath on, hiding in the
## izba's `spot_name` (IzbaA/<spot_name>): the prologue, the flare, the knock,
## the search, the escape. Then the three controls: not holding the breath (a
## sob) and holding it without a sip on the heartbeat (a gasp) - each must
## give him away, else "not found" proves nothing; and letting go between
## heartbeats - an exhale, never a sip, else the heartbeat proves nothing.
## Where an exhale is loud enough to be grabbed for (behind the stove, not in
## the cellar) the exhale must be what he is caught on; else it must be heard.
func _hiding(where: String, spot_name: String, route: Array[Vector3]) -> void:
	# The scene's own timings: the level would take --intro-scale from the
	# same command line and shorten the prologue under the hider.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--intro-scale="):
			check(false, "%s runs at the scene's own timings (no --intro-scale)" % where, arg)
			return
	var h := await _hide(Hider.Breath.CAREFUL, spot_name, route)
	print("--- %s: %s; hid in %s, the soldier %.2f m from it, checked %d times, longest %.1f s, dust %d, held %.1f s, least air %.2f, sips %d, peak %s" % [
			where, h.failed, h.hid_at, h.closest, h.checks, h.checked, h.dust, h.held, h.min_air,
			h.sounds.count("sip"), h.peak])
	for e in h.events:
		print("    ", e)
	var order: Array[int] = [InvasionSequence.Beat.PROLOGUE, InvasionSequence.Beat.INVASION,
			InvasionSequence.Beat.KNOCK, InvasionSequence.Beat.SEARCH, InvasionSequence.Beat.LEAVE,
			InvasionSequence.Beat.LINGER, InvasionSequence.Beat.RETURN, InvasionSequence.Beat.ESCAPE]
	check(h.beats == order, "%s: the opening runs its beats in order to the escape" % where, h.beats)
	var prologue := InvasionSequence.Beat.PROLOGUE
	check(h.read.has(h.notice_doc) and h.bag.has("bread") and h.took.size() == 2
			and h.took.values().all(func(b: int) -> bool: return b == prologue),
			"%s: read the notice and took the bread in the prologue" % where, [h.read, h.bag, h.took])
	check(h.hid_at == InvasionSequence.Beat.INVASION, "%s: hid when the flare went up, before the knock" % where,
			h.hid_at)
	if bool(h.spot_info["under_floor"]):
		# His body (0.3 m) over the lid (0.9 m square): boots on the hatch.
		check(h.closest < 0.75 and h.dust > 0,
				"%s: the soldier searched the izba right over him" % where, [h.closest, h.dust])
	else:
		check(h.checks >= 1 and h.checked >= float(h.spot_info["check_time"]) - 0.1,
				"%s: the soldier looked in with his torch for the whole check (%.0f s)" % [where, float(h.spot_info["check_time"])],
				[h.checks, h.checked])
	var loud := h.sounds.filter(func(k: String) -> bool: return k != "sip")
	check(loud.is_empty() and h.sounds.has("sip"),
			"%s: no sob, no gasp, no breath out of time; sips on the heartbeat" % where, h.sounds)
	var turned := h.worst.keys().filter(func(k: String) -> bool: return int(h.worst[k]) != Enemy.State.PATROL)
	var calm := h.peak.values().all(func(v: float) -> bool: return v < Enemy.SUSPICIOUS_AT)
	check(h.failed == "" and turned.is_empty() and calm,
			"%s: not found, nobody even turned" % where, [h.failed, h.worst, h.peak])
	check(h.still_hidden and h.beats.has(InvasionSequence.Beat.ESCAPE), "%s: sat out the search to the escape" % where,
			[h.still_hidden, h.failed])

	var sob := await _hide(Hider.Breath.NEVER, spot_name, route)
	print("--- control %s, no breath held: %s, heard %s, %s" % [where, sob.failed, sob.heard, sob.events])
	check(_given_away(sob, "sob"),
			"control %s: not holding the breath, a sob gives him away" % where,
			[sob.failed, sob.gave_away, sob.heard.slice(0, 3), sob.sounds])
	var gasp := await _hide(Hider.Breath.NO_SIPS, spot_name, route)
	print("--- control %s, held without sips: %s, heard %s, %s" % [where, gasp.failed, gasp.heard, gasp.events])
	check(_given_away(gasp, "gasp"),
			"control %s: holding the breath without sips, a gasp gives him away" % where,
			[gasp.failed, gasp.gave_away, gasp.heard.slice(0, 3), gasp.sounds])
	# An exhale heard through the place's damping (BreathControl._make_sound),
	# against the grab (Enemy._on_noise: 0.3 at most 2.5 m away).
	var grabbed := 0.45 * (1.0 - 0.5 * float(h.spot_info["damping"])) >= 0.3
	var off := await _hide(Hider.Breath.OFF_BEAT, spot_name, route, not grabbed)
	print("--- control %s, let go between heartbeats: %s, heard %s, %s" % [where, off.failed, off.heard, off.events])
	if grabbed:
		check(not off.sounds.has("sip") and _given_away(off, "exhale"),
				"control %s: letting go between heartbeats, never a sip, an exhale gives him away" % where,
				[off.failed, off.gave_away, off.heard.slice(0, 3), off.sounds])
	else:
		check(off.sounds.has("exhale") and not off.sounds.has("sip") and not off.worst.is_empty(),
				"control %s: letting go between heartbeats near them, an exhale, never a sip, and he is heard" % where,
				[off.failed, off.worst, off.sounds])


## Caught, and `sound` gave him away. Under the floor he can only be grabbed
## on the sound itself (Enemy._on_noise; the dog cannot smell him through
## the hatch). Elsewhere he may be found slowly - heard, then smelled out by
## the dog, then pulled out by the soldier it barks for: the first breath
## sound anyone heard is what gave him away.
func _given_away(h: Hider, sound: String) -> bool:
	if h.caught_by == "" or h.heard.is_empty() or h.heard[0] != sound:
		return false
	return h.gave_away == sound or not bool(h.spot_info["under_floor"])


## Act I from the start (the prologue on), played by a hider breathing `mode`
## who hides in IzbaA/<spot_name>, crouching along `route`.
func _hide(mode: int, spot_name: String, route: Array[Vector3], stop_when_turned := false) -> Hider:
	PanicSystem.reset()
	Perception.reset()
	Stealth.clear_scent()
	Stealth.reset_cover()
	Inventory.clear()
	LevelBase._checkpoint = {}
	LevelBase._resume_after_intro = false
	var lv := (load(ACT1_PATH) as PackedScene).instantiate()
	lv.next_level = ""
	add_child(lv)
	await frames(2)
	var h := Hider.new()
	h.setup(lv, mode)
	h.stop_when_turned = stop_when_turned
	var izba := lv.get_node("IzbaA")
	h.notice_doc = (izba.get_node("RegistrationNotice") as Pickup).item.document_id
	Engine.time_scale = SPEED
	var spot := izba.get_node(spot_name) as HideSpot
	# Copied now: the level (and the place) is gone by the time it is checked.
	h.spot_info = {"under_floor": spot.under_floor, "check_time": spot.check_time,
			"damping": spot.noise_damping}
	await h.play(izba.get_node("RegistrationNotice") as Pickup, izba.get_node("Bread") as Pickup,
			spot, AT_TABLE, route, 4.0)
	Engine.time_scale = 1.0
	h.teardown()
	if get_tree().paused:
		# A run that ended with the document open: the next must not start paused.
		get_tree().paused = false
		h.events.append("the tree was left paused")
	h.still_hidden = h.player.is_hidden
	h.dust = h.player.dust_falls
	for item in Inventory.items():
		h.bag.append(item.id)
	await _done_with(lv)
	return h



# --- Act I: the escape to the forest ------------------------------------------------------

## Act I at the escape, as after a capture then (docs/ARCHITECTURE.md,
## "Сцена «Вторжение»", 8): the opening skipped (invasion.skip()), the boy in the
## izba by the table, the door open, the squad gone, the patrols on their
## rounds, the flares on; the navmesh baked.
func _act1_escape() -> Node3D:
	PanicSystem.reset()
	Perception.reset()
	Stealth.clear_scent()
	Stealth.reset_cover()
	Inventory.clear()
	LevelBase._checkpoint = {}
	LevelBase._resume_after_intro = false
	var lv := (load(ACT1_PATH) as PackedScene).instantiate()
	lv.play_intro = false
	lv.next_level = ""
	add_child(lv)
	var nav := lv.get_node("Navigation") as RuntimeNavRegion
	var t0 := Time.get_ticks_msec()
	while not nav.is_baked and Time.get_ticks_msec() - t0 < 15000:
		await get_tree().physics_frame
	await frames(2)
	return lv


## The careful escape (docs/ARCHITECTURE.md, "Побег к лесу: Акт I").
func _escape() -> void:
	var lv := await _act1_escape()
	var bot := Escaper.new()
	var t0 := Time.get_ticks_msec()
	bot.setup(lv)
	print("escape: grid built in %d ms" % (Time.get_ticks_msec() - t0))
	_escape_bot = bot
	var invasion := lv.get_node("Invasion") as InvasionSequence
	var door := lv.get_node("IzbaDoor") as IzbaDoor
	check(invasion.beat == InvasionSequence.Beat.ESCAPE and door.is_open and Escaper.in_izba(bot.player.global_position),
			"the escape: it starts at the escape, in the izba, the door open",
			[invasion.beat, door.is_open, Bot._v(bot.player.global_position)])
	var finished := [false]
	lv.slice_finished.connect(func() -> void: finished[0] = true)
	var s := bot.escape_plan()
	check(not s.is_empty(), "the escape: there is a way", bot.events)
	if s.is_empty():
		await _done_with(lv)
		return
	var clock0 := Stealth.clock
	Engine.time_scale = SPEED
	if await bot.run(s, 600.0):
		await bot.wait_end(finished, 15.0)
	bot.release_all()
	var took := Stealth.clock - clock0
	var p := bot.player
	var caption := (lv.get_node("Overlay/Caption") as Label).text
	var nearest := INF
	for q in bot.trace:
		nearest = minf(nearest, bot.from_beat(q))
	print("--- the escape: %.0f s, walked %.0f m, waited %.0f s (longest %.0f s), frozen %.0f s, slipped away %d times, nearest the dog's beat %.2f m, creaks %d, flare light on him %.2f"
			% [took, bot.walked, bot.waited, bot.longest_wait, bot.frozen, bot.dodges, nearest, p.creaks, bot.flare_lit])
	var closest := ""
	for key in bot.peak:
		if float(bot.peak[key]) > 0.0:
			closest += " %s %.2f" % [key, float(bot.peak[key])]
	print("      most suspicion:", closest if closest != "" else " none")
	for e in bot.events:
		print("      ", e)
	check(finished[0] and bot.failed == "" and caption.contains("Конец Акта I"),
			"the escape: a careful boy gets to the forest, and the act ends there",
			[bot.failed, Bot._v(p.global_position), finished[0], caption.left(40)])
	check(bot.noticed.is_empty(), "the escape: nobody so much as turns to look", bot.noticed)
	var worst := 0.0
	for key in bot.peak:
		worst = maxf(worst, float(bot.peak[key]))
	check(worst <= Bot.HEARD_MAX, "the escape: nobody's suspicion gets past %.1f" % Bot.HEARD_MAX, bot.peak)
	# Every cell he walked to (dodges too) off the strip; and where he really
	# went (the trace cuts corners) never within the dog's reach of the beat:
	# HEEL + heel_distance + pickup (the strip is SCENT_MARGIN wider).
	var in_strip := bot.stepped.filter(func(c: Vector2i) -> bool: return bot.scent_zone[bot.idx(c)] == 1)
	var pickup := bot.scent_reach - Escaper.SCENT_MARGIN
	check(not bot.stepped.is_empty() and in_strip.is_empty() and nearest > pickup and not bot.trail_taken,
			"the escape: never a step where the shepherd could find his trail, and it never took one",
			[bot.stepped.size(), in_strip.size(), nearest, pickup, bot.trail_taken])
	# The light the bot plans by is the worst there can be: never below the
	# game's own on him, any frame of the run - the whole of it, and a flare's
	# alone (the whole hides a flare left out: the bot's open moon is more than
	# a moon shadow and a far flare together).
	check(bot.flare_lit > 0.05 and bot.light_misses == 0 and bot.flare_misses == 0,
			"the escape: a flare lit him out in the village or the field (%.2f), never more than the bot's worst light" % bot.flare_lit,
			[bot.flare_lit, bot.light_misses, bot.light_gap, bot.flare_misses, bot.flare_gap])
	_escape_traces.append(["escape", bot.trace])
	await _done_with(lv)


## The control: upright, straight to the forest, minding nobody. Somebody
## must notice him - else the careful escape proves nothing.
func _escape_reckless() -> void:
	var lv := await _act1_escape()
	var bot := Escaper.new()
	bot.reckless = true
	bot.stop_when_noticed = true
	bot.setup(lv)
	var finished := [false]
	lv.slice_finished.connect(func() -> void: finished[0] = true)
	var s := bot.begin()
	if bot.add_path(s, bot.forest_goal(bot.player.global_position), false):
		bot.finish(s)
		Engine.time_scale = SPEED
		if await bot.run(s, 120.0):
			await bot.wait_end(finished, 15.0)
	bot.release_all()
	print("--- the escape, reckless: %s, saw %s" % [bot.failed, bot.saw])
	check(bot.failed.begins_with("noticed by") and not finished[0],
			"control, the escape: walking straight to the forest somebody notices him",
			[bot.failed, bot.noticed, finished[0]])
	_escape_traces.append(["escape reckless", bot.trace])
	await _done_with(lv)


## The control for the eyes in the village: the shepherd at the door has
## the reckless walk at once, so here the soldier and his dog are taken off,
## the gendarme and the policeman are deaf (else his steps give him away
## first), and he stands upright in the open between the gendarme's round
## and the policeman's beat (EYES_ON). One of them must see him within a
## minute (the gendarme walks a round in 37 s, coming his way on each) -
## else "nobody turns" in the field says nothing of their eyes.
func _escape_eyes() -> void:
	var lv := await _act1_escape()
	_take_off(lv, ["SoldierRoad", "Shepherd"])
	for n in ["Feldgendarm", "Polizei"]:
		(lv.get_node(n) as Enemy).hearing = 0.0
	var player := lv.get_node("Player") as Player
	player.global_position = EYES_ON
	await frames(2)
	var bot := Escaper.new()
	bot.reckless = true
	bot.stop_when_noticed = true
	bot.setup(lv)
	bot.release_all()
	Engine.time_scale = SPEED
	var t := 0.0
	while bot.failed == "" and t < 60.0:
		await bot._seconds(0.5)
		t += 0.5
	print("--- the escape, standing in the village before deaf eyes: %s after %.0f s, saw %s" % [bot.failed, t, bot.saw])
	var eyes := ["Feldgendarm", "Polizei"].any(func(n: String) -> bool: return bool(bot.saw.get(n, false)))
	check(eyes, "control, the escape: standing in the open between the gendarme and the policeman, deaf, one of them sees him",
			[bot.failed, bot.saw])
	await _done_with(lv)


## Enemies of the level `lv` taken off for a control: out of the bot's sight
## and the game's.
func _take_off(lv: Node, names: Array) -> void:
	for n in names:
		var e := lv.get_node(n) as Enemy
		e.remove_from_group("enemies")
		e.process_mode = Node.PROCESS_MODE_DISABLED
		e.visible = false


## The control for the strip: the careful bot, let into the strip, out of
## the door to the road (ROAD) and back to where he started, then waiting
## there. Eyes and ears never have him (the bot minds them as ever); the
## shepherd must find his trail - else keeping off the strip is a needless
## care. The gendarme and the policeman are taken off for it: the control is
## the dog's, and the gendarme's round passes the door.
func _escape_scent() -> void:
	var lv := await _act1_escape()
	_take_off(lv, ["Feldgendarm", "Polizei"])
	var bot := Escaper.new()
	bot.stop_when_noticed = true
	bot.setup(lv)
	Engine.time_scale = SPEED
	var home := bot.player.global_position
	bot.allow_scent = true
	var s := bot.make_plan([ROAD, Vector3(home.x, 0.0, home.z)], 0.0)
	if not s.is_empty() and await bot.run(s, 300.0):
		bot.allow_scent = false
		await bot.hold_out(func() -> bool: return not bot.noticed.is_empty(), 90.0)
	bot.release_all()
	var dog := str(bot.shepherd.name) if bot.shepherd != null else "?"
	print("--- the escape, across the dog's beat: %s, saw %s, on the trail when it turned %s, slipped away %d times"
			% [bot.failed, bot.saw, bot.trail_when_turned, bot.dodges])
	for e in bot.events:
		print("      ", e)
	# The run stops on the first frame anybody turns, so a dog in `noticed`
	# turned on that frame (its bark turns the soldier on the same frame).
	var unseen := bot.saw.values().all(func(v: bool) -> bool: return not v)
	check(bot.failed.begins_with("noticed by") and bot.noticed.has(dog) and bot.trail_when_turned and unseen,
			"control, the escape: out to the dog's beat and back, the shepherd finds his trail, nobody sees him",
			[bot.failed, bot.noticed, bot.saw, bot.trail_when_turned, bot.trail_taken])
	_escape_traces.append(["escape scent", bot.trace])
	await _done_with(lv)


# --- Act I whole: the opening and the escape in one run ---------------------------------

## What the escape starts from (docs/ARCHITECTURE.md, "Акт I целиком"): what
## invasion.skip() makes, and the opening must leave behind it.
func _escape_state(lv: Node) -> Dictionary:
	var inv := lv.get_node("Invasion") as InvasionSequence
	var soldier := inv.soldier
	var out := {
		"beat": InvasionSequence.Beat.keys()[inv.beat],
		"door open": inv.door.is_open,
		"enemies open the door": inv.door.enemies_can_open,
		"flares on their own": inv.flare.autofire,
		"door angle": snappedf(inv.door.rotation_degrees.y, 1.0),
		"prologue sepia": inv.prologue_zone.active,
		# The zone's effect, not only its flag: the opening leaves it by
		# another way (set_active with the boy inside it) than skip() does.
		"in a safe zone": Perception.in_safe_zone(),
		"gunfire": (lv.get_node("Gunfire") as GunfireAmbience).active,
		"torch": soldier.torch_on,
		"soldier at a post": soldier.hold_position,
		"soldier scripted": soldier.has_script_route(),
		"soldier searches": soldier.searches_hiding_spots,
		"dog at his heel": inv.dog.handler == soldier,
		"dog at a post": inv.dog.hold_position,
	}
	for e in get_tree().get_nodes_in_group("enemies"):
		if lv.is_ancestor_of(e):
			var en := e as Enemy
			out[str(en.name)] = [en.is_visible_in_tree(), en.process_mode != Node.PROCESS_MODE_DISABLED,
					Enemy.State.keys()[en.state]]
	return out


## The keys whose values differ, with both.
static func _state_diff(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	for key in a:
		if not b.has(key) or str(a[key]) != str(b[key]):
			out.append([key, a[key], b.get(key, "-")])
	for key in b:
		if not a.has(key):
			out.append([key, "-", b[key]])
	return out


## Act I from its first frame to the beat `until`, as the careful hider
## plays it in IzbaA/<spot_name> (crouching to it along `route`): a fresh
## level. {"lv", "h", "spot", "finished", "opened"}; {} - not at the scene's
## own timings.
func _act1_opening(where: String, spot_name: String, route: Array[Vector3],
		until := InvasionSequence.Beat.ESCAPE) -> Dictionary:
	# The level takes --intro-scale from the same command line (as _hiding).
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--intro-scale="):
			check(false, "act1, %s runs at the scene's own timings (no --intro-scale)" % where, arg)
			return {}
	PanicSystem.reset()
	Perception.reset()
	Stealth.clear_scent()
	Stealth.reset_cover()
	Inventory.clear()
	LevelBase._checkpoint = {}
	LevelBase._resume_after_intro = false
	var lv := (load(ACT1_PATH) as PackedScene).instantiate()
	lv.next_level = ""
	add_child(lv)
	await frames(2)
	var finished := [false]
	lv.slice_finished.connect(func() -> void: finished[0] = true)
	var h := Hider.new()
	h.setup(lv, Hider.Breath.CAREFUL)
	var izba := lv.get_node("IzbaA")
	var notice := izba.get_node("RegistrationNotice") as Pickup
	h.notice_doc = notice.item.document_id
	var spot := izba.get_node(spot_name) as HideSpot
	Engine.time_scale = SPEED
	var opened := await h.play(notice, izba.get_node("Bread") as Pickup, spot, AT_TABLE, route, 0.0, until)
	return {"lv": lv, "h": h, "spot": spot, "finished": finished, "opened": opened}


## The end of a run of the opening: keys let go, the speed back, no pause.
func _act1_close(h: Hider, bot: Escaper) -> void:
	bot.release_all()
	h.teardown()
	Engine.time_scale = 1.0
	if get_tree().paused:
		get_tree().paused = false
		h.events.append("the tree was left paused")


## Act I from its first frame to the end card (docs/ARCHITECTURE.md, "Акт I
## целиком"): the careful hider sits the search out in IzbaA/<spot_name>;
## once the soldier has walked out (LINGER: he only stands behind the corner,
## and comes back for a look - "Ложный уход") the escaper builds his grid,
## comes out when he may and makes for the forest.
func _whole_act1(where: String, spot_name: String, route: Array[Vector3]) -> void:
	# What the escape part starts from, for comparison: a level at the escape.
	var skip_lv := await _act1_escape()
	var skipped := _escape_state(skip_lv)
	await _done_with(skip_lv)
	var run := await _act1_opening(where, spot_name, route, InvasionSequence.Beat.LINGER)
	if run.is_empty():
		return
	var lv: Node3D = run["lv"]
	var h: Hider = run["h"]
	var spot: HideSpot = run["spot"]
	var finished: Array = run["finished"]
	var player := h.player
	var state := {}  # the world when the escape begins
	var bot := Escaper.new()
	var out_after := -1.0
	var out_beat := -1
	var came_out := false
	var hidden_for := 0.0
	if bool(run["opened"]):
		var t0 := Time.get_ticks_msec()
		bot.setup(lv)
		print("act1, %s: grid built in %d ms as the soldier lingers" % [where, Time.get_ticks_msec() - t0])
		# Still hidden he breathes as the hider does; out when he may. Nobody
		# tells him the soldier will come back: the rule (everybody on his
		# round) keeps him in.
		var since := Stealth.clock
		var escape_at := -1.0
		while player.is_hidden and h.failed == "" and bot.failed == "":
			if escape_at < 0.0 and h.seq.beat == InvasionSequence.Beat.ESCAPE:
				escape_at = Stealth.clock
				state = _escape_state(lv)
			if not Input.is_action_pressed("hold_breath") and bot.may_come_out(spot):
				hidden_for = Stealth.clock - since
				out_beat = h.seq.beat
				if await bot.come_out(spot):
					came_out = true
					out_after = Stealth.clock - escape_at if escape_at >= 0.0 else -1.0
				break
			if Stealth.clock - since > 120.0:
				bot._fail("never came out of %s" % spot_name)
				break
			await h._frame()
	var ran := -1.0
	if came_out and bot.failed == "" and h.failed == "":
		var clock0 := Stealth.clock
		var s := bot.escape_plan()
		if s.is_empty():
			bot._fail("no way to the forest from %s" % Bot._v(player.global_position))
		elif await bot.run(s, 600.0):
			await bot.wait_end(finished, 15.0)
		ran = Stealth.clock - clock0
	_act1_close(h, bot)
	var caption := (lv.get_node("Overlay/Caption") as Label).text
	var nearest := INF
	for q in bot.trace:
		nearest = minf(nearest, bot.from_beat(q))
	print("--- act1, %s: %s / %s; hid at %s, held %.1f s, least air %.2f, sips %d; out %.1f s after the escape began; to the forest in %.0f s, walked %.0f m, waited %.0f s, slipped away %d times, nearest the dog's beat %.2f m, flare light on him %.2f"
			% [where, h.failed, bot.failed, InvasionSequence.Beat.keys()[maxi(h.hid_at, 0)], h.held, h.min_air,
			h.sounds.count("sip"), out_after, ran, bot.walked, bot.waited, bot.dodges, nearest, bot.flare_lit])
	for e in h.events:
		print("      ", e)
	for e in bot.events:
		print("      ", e)
	var order: Array[int] = [InvasionSequence.Beat.PROLOGUE, InvasionSequence.Beat.INVASION,
			InvasionSequence.Beat.KNOCK, InvasionSequence.Beat.SEARCH, InvasionSequence.Beat.LEAVE,
			InvasionSequence.Beat.LINGER, InvasionSequence.Beat.RETURN, InvasionSequence.Beat.ESCAPE]
	var prologue := InvasionSequence.Beat.PROLOGUE
	var loud := h.sounds.filter(func(k: String) -> bool: return k != "sip")
	check(h.beats == order and h.read.has(h.notice_doc) and h.took.size() == 2
			and h.took.values().all(func(b: int) -> bool: return b == prologue)
			and h.hid_at == InvasionSequence.Beat.INVASION and loud.is_empty() and h.sounds.has("sip"),
			"act1, %s: the notice and the bread in the prologue, hidden at the flare; the whole act no sob, no gasp, no breath out of time" % where,
			[h.beats, h.read, h.took, h.hid_at, h.sounds])
	var diff := _state_diff(state, skipped)
	check(diff.is_empty(), "act1, %s: at the escape the world is what invasion.skip() makes it" % where, diff)
	check(came_out and out_beat == InvasionSequence.Beat.ESCAPE and out_after >= 0.0,
			"act1, %s: he comes out of the hiding place once the squad has gone - not while the soldier lingers behind the corner or looks back in" % where,
			[h.failed, bot.failed, hidden_for, _beat(out_beat), out_after])
	check(finished[0] and h.failed == "" and bot.failed == "" and caption.contains("Конец Акта I"),
			"act1, %s: from the first evening to the forest, and the act ends there" % where,
			[h.failed, bot.failed, Bot._v(player.global_position), finished[0], caption.left(40)])
	var turned := h.worst.keys().filter(func(k: String) -> bool: return int(h.worst[k]) != Enemy.State.PATROL)
	var calm := h.peak.values().all(func(v: float) -> bool: return v < Enemy.SUSPICIOUS_AT)
	var worst := 0.0
	for key in bot.peak:
		worst = maxf(worst, float(bot.peak[key]))
	check(turned.is_empty() and bot.noticed.is_empty() and calm and worst <= Bot.HEARD_MAX,
			"act1, %s: nobody so much as turns the whole act; out of hiding nobody's suspicion past %.1f" % [where, Bot.HEARD_MAX],
			[h.worst, bot.noticed, h.peak, bot.peak])
	var in_strip := bot.stepped.filter(func(c: Vector2i) -> bool: return bot.scent_zone[bot.idx(c)] == 1)
	var pickup := bot.scent_reach - Escaper.SCENT_MARGIN
	check(not bot.stepped.is_empty() and in_strip.is_empty() and nearest > pickup and not bot.trail_taken,
			"act1, %s: never a step where the shepherd could find his trail, and it never took one" % where,
			[bot.stepped.size(), in_strip.size(), nearest, pickup, bot.trail_taken])
	# Whether a flare catches him on the way is the opening's timing, not the
	# bot's: only printed here; the part "escape" asks for it (docs/ARCHITECTURE.md,
	# "Акт I целиком").
	check(bot.light_misses == 0 and bot.flare_misses == 0,
			"act1, %s: the light on him never more than the bot's worst light, the flare's own too (a flare lit him %.2f)" % [where, bot.flare_lit],
			[bot.flare_lit, bot.light_misses, bot.light_gap, bot.flare_misses, bot.flare_gap])
	_escape_traces.append(["act1 " + spot_name, bot.trace])
	await _done_with(lv)



# --- Act I: the door opened in the prologue ------------------------------------------------

## The boy opens the door himself in the prologue (docs/ARCHITECTURE.md,
## "Дверь открыта в прологе"): the squad comes at once and, the door being
## open, goes in without knocking. Into the hay across the road: the shepherd
## takes his trail at the izba, walks it into the barn and smells him out;
## back into the cellar: he sits the search out.
func _door() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--intro-scale="):
			check(false, "door runs at the scene's own timings (no --intro-scale)", arg)
			return
	for to_hay: bool in [true, false]:
		var where := "door, into the hay" if to_hay else "door, into the cellar"
		var r := await _door_run(to_hay)
		var h: Hider = r["h"]
		print("--- %s: %s; opened at %.1f s (%s -> %s), hid at %.1f s; the dog took a trail at %.1f s at %s, alert at %s, nearest the place %.2f m; first turned at %.1f s; caught by '%s', in the place %s; the soldier %.2f m from it, dust %d, held %.1f s, least air %.2f, sips %d, heard %s, peak %s"
				% [where, h.failed, float(r["opened_at"]), _beat(int(r["opened_in"])), _beat(int(r["after_open"])),
				float(r["hid_at"]), float(r["trail_at"]), Bot._v(r["took_trail"]), Bot._v(r["dog_alert"]),
				float(r["dog_nearest"]), float(r["turned_at"]), h.caught_by, r["in_place"], h.closest, h.dust, h.held, h.min_air,
				h.sounds.count("sip"), h.heard, h.peak])
		for e in h.events:
			print("    ", e)
		var prologue := InvasionSequence.Beat.PROLOGUE
		# The knock can only be missed where the squad reaches the door: in
		# the hay he is found before it does (the barking stops the soldier's
		# approach), so there "no knock" would hold whatever the door did.
		check(int(r["opened_in"]) == prologue and int(r["after_open"]) == InvasionSequence.Beat.INVASION
				and float(r["opened_at"]) < float(r["prologue_time"])
				and (to_hay or not h.beats.has(InvasionSequence.Beat.KNOCK))
				and h.took.size() == 2 and h.took.values().all(func(b: int) -> bool: return b == prologue),
				("%s: the notice and the bread, then the door cuts the prologue short: the squad comes at once"
				+ ("" if to_hay else " and goes in without knocking")) % where,
				[_beat(int(r["opened_in"])), _beat(int(r["after_open"])), r["opened_at"], h.beats, h.took])
		var loud := h.sounds.filter(func(k: String) -> bool: return k != "sip")
		# Nobody turned before the shepherd took his trail: none of his steps,
		# creaks or the hay or the lid gave him away (h.heard is his breath only).
		var unseen := not bool(r["turned_on_way"]) and float(r["trail_at"]) >= 0.0 \
				and float(r["turned_at"]) >= float(r["trail_at"])
		var took: Vector3 = r["took_trail"]
		if to_hay:
			check(float(r["hid_at"]) >= 0.0 and unseen and h.heard.is_empty() and loud.is_empty(),
					"%s: unseen and unheard on the way and in the hay - nobody turns till the shepherd takes his trail; no sob, no gasp" % where,
					[r["hid_at"], r["turned_on_way"], r["trail_at"], r["turned_at"], h.heard, h.sounds])
			check(Vector2(took.x - 1.5, took.z - 3.5).length() < 4.5
					and int(r["trail_beat"]) == InvasionSequence.Beat.INVASION and bool(r["trail_at_heel"])
					and bool(r["trail_in_barn"]),
					"%s: the shepherd takes his trail at heel as the squad comes up to the izba, and walks it into the barn" % where,
					[Bot._v(took), _beat(int(r["trail_beat"])), r["trail_at_heel"], r["trail_in_barn"]])
			# Whoever its barking brings first (Dog.bark -> Enemy.alert_to with
			# the place): a man pulls him out, not the dog's teeth.
			check(_in_barn(r["dog_alert"]) and h.caught_by != "" and h.caught_by != "Shepherd" and bool(r["in_place"]),
					"%s: it smells him out in the hay, and a man its barking brings pulls him out" % where,
					[Bot._v(r["dog_alert"]), h.failed, h.caught_by, r["in_place"]])
		else:
			var order: Array[int] = [prologue, InvasionSequence.Beat.INVASION, InvasionSequence.Beat.SEARCH,
					InvasionSequence.Beat.LEAVE, InvasionSequence.Beat.LINGER, InvasionSequence.Beat.RETURN,
					InvasionSequence.Beat.ESCAPE]
			check(h.beats == order and h.failed == "" and h.still_hidden and unseen and h.heard.is_empty()
					and loud.is_empty() and h.sounds.has("sip"),
					"%s: sat the search out to the escape; nobody turns till the shepherd takes his trail, no breath of his heard, sips on the heartbeat only" % where,
					[h.beats, h.failed, h.still_hidden, r["turned_on_way"], r["trail_at"], r["turned_at"], h.heard, h.sounds])
			check(h.closest < 0.75 and h.dust > 0, "%s: the soldier searched the izba right over him" % where,
					[h.closest, h.dust])
			# No knock: the squad goes out while his steps in the room are still
			# fresh, and the shepherd, going to its handler, crosses them.
			check(int(r["trail_beat"]) == InvasionSequence.Beat.LEAVE and float(r["dog_nearest"]) < 1.0
					and r["dog_alert"] == Vector3.INF and float(h.peak.get("Shepherd", 0.0)) < 1.0,
					"%s: going out the shepherd takes his fresh trail to the hatch, and the cellar keeps his smell in" % where,
					[_beat(int(r["trail_beat"])), r["dog_nearest"], Bot._v(r["dog_alert"]), h.peak.get("Shepherd")])


## Inside the barn (12, -4: walls x 9..15, z -6.5..-1.5).
static func _in_barn(p: Vector3) -> bool:
	return absf(p.x - 12.0) < 2.8 and absf(p.z + 4.0) < 2.3


static func _beat(b: int) -> String:
	return InvasionSequence.Beat.keys()[b] if b >= 0 else "-"


## One run of the door part: the careful hider takes the notice and the
## bread, opens the door, then makes for the hay (upright) or back to the
## cellar (crouched), hides and holds his breath; watched till he is caught
## or 4 s into the escape.
func _door_run(to_hay: bool) -> Dictionary:
	PanicSystem.reset()
	Perception.reset()
	Stealth.clear_scent()
	Stealth.reset_cover()
	Inventory.clear()
	LevelBase._checkpoint = {}
	LevelBase._resume_after_intro = false
	var lv := (load(ACT1_PATH) as PackedScene).instantiate()
	lv.next_level = ""
	add_child(lv)
	await frames(2)
	var h := Hider.new()
	h.setup(lv, Hider.Breath.CAREFUL)
	var izba := lv.get_node("IzbaA")
	var notice := izba.get_node("RegistrationNotice") as Pickup
	h.notice_doc = notice.item.document_id
	var door := lv.get_node("IzbaDoor") as IzbaDoor
	var dog := lv.get_node("Shepherd") as Dog
	var spot := (lv.get_node("Barn/HayHide") if to_hay else izba.get_node("CellarHatch")) as HideSpot
	var r := {"h": h, "prologue_time": h.seq.prologue_time, "opened_in": -1, "after_open": -1, "opened_at": -1.0,
			"hid_at": -1.0, "turned_on_way": false, "trail_at": -1.0, "took_trail": Vector3.INF,
			"turned_at": -1.0, "dog_alert": Vector3.INF, "in_place": false, "dog_nearest": INF,
			"trail_beat": -1, "trail_at_heel": false, "trail_in_barn": false}
	Engine.time_scale = SPEED
	var ok := await h.walk(AT_TABLE, false)
	if ok:
		ok = await h.take(notice)
	if ok:
		ok = await h.take(izba.get_node("Bread") as Pickup)
	if ok:
		ok = await h.walk(AT_LATCH, false)
	if ok:
		await h.seconds(0.3)
		h.player.look_towards(door.latch.global_position)
		await h._frame()
		r["opened_in"] = int(h.seq.beat)
		r["opened_at"] = h.clock
		await h._press_event("interact")
		r["after_open"] = int(h.seq.beat)
		if not door.is_open:
			h._fail("the door would not open from %s" % Bot._v(h.player.global_position))
		# Lets the leaf swing in (IzbaDoor.open_time 0.8 s) before stepping past it.
		await h.seconds(0.5)
		ok = h.failed == ""
	if ok and not to_hay:
		# A look out at the squad coming up the road, then back to the cellar.
		ok = await h.walk(AT_THRESHOLD, true)
		if ok:
			h.player.look_towards(Vector3(6, 1.5, 18))
			await h.seconds(1.0)
			ok = h.failed == ""
	for p in (TO_BARN if to_hay else LATCH_TO_HATCH):
		if ok:
			ok = await h.walk(p, not to_hay)
	if ok:
		ok = await h.hide_in(spot)
	if ok:
		r["hid_at"] = h.clock
		r["turned_on_way"] = not h.worst.is_empty()
	var escape_at := -1.0
	while ok and h.failed == "" and h.clock < 240.0:
		var was_in := h.player.is_hidden and h.player.current_hide_spot == spot
		await h._frame()
		if h.caught_by != "":
			r["in_place"] = was_in
			break
		if float(r["trail_at"]) < 0.0 and dog.trail_seq >= 0:
			r["trail_at"] = h.clock
			r["took_trail"] = dog.global_position
			r["trail_beat"] = int(h.seq.beat)
			r["trail_at_heel"] = dog.handler != null
		if dog.trail_seq >= 0 and _in_barn(dog.global_position):
			r["trail_in_barn"] = true
		if float(r["turned_at"]) < 0.0 and get_tree().get_nodes_in_group("enemies").any(
				func(e: Node) -> bool: return (e as Enemy).state != Enemy.State.PATROL):
			r["turned_at"] = h.clock
		if (r["dog_alert"] as Vector3) == Vector3.INF and dog.state == Enemy.State.ALERT:
			r["dog_alert"] = dog.global_position
		if h.player.is_hidden:
			var d := dog.global_position - spot.global_position
			r["dog_nearest"] = minf(float(r["dog_nearest"]), Vector2(d.x, d.z).length())
		if escape_at < 0.0 and h.seq.beat == InvasionSequence.Beat.ESCAPE:
			escape_at = h.clock
		if escape_at >= 0.0 and h.clock - escape_at >= 4.0:
			break
	if ok and h.failed == "" and escape_at < 0.0:
		h._fail("neither caught nor at the escape after %.0f s" % h.clock)
	Engine.time_scale = 1.0
	h.teardown()
	if get_tree().paused:
		get_tree().paused = false
		h.events.append("the tree was left paused")
	h.still_hidden = h.player.is_hidden
	h.dust = h.player.dust_falls
	await _done_with(lv)
	return r


# --- the map ----------------------------------------------------------------------------

## Top view, north up: grey - walls, trees, wire, tripwires; yellow - ground
## the beam can reach (crouched); pink - in reach of some enemy somewhere on
## his round; white - safe; the careful routes in colour, the controls in
## black and red; checkpoints green, the tower black.
func _draw_map() -> void:
	var bot := _map_bot
	if bot == null:
		print("map: needs the light part (no --only, or --only=light)")
		return
	var k := 4
	var img := _grid_image(bot, k)
	var colors := {"from the village": Color(0.55, 0.33, 0.12), "the whole act": Color(0.85, 0.45, 0.1),
			"the witness": Color(0.0, 0.55, 0.5),
			"under the wire": Color(0.1, 0.3, 0.85), "by the road": Color(0.1, 0.6, 0.85),
			"back at the camp": Color(0.5, 0.2, 0.75), "reckless": Color(0, 0, 0), "street": Color(0.8, 0.1, 0.1),
			"dog ears": Color(0.4, 0.4, 0.0)}
	for r in _traces.size():
		var col := Color(0.3, 0.3, 0.3)
		for key in colors:
			if str(_traces[r][0]).begins_with(key):
				col = colors[key]
		_plot(img, bot, k, _traces[r][1], col, 2)
	for p in _checkpoints_at:
		_plot(img, bot, k, PackedVector3Array([p]), Color(0.1, 0.65, 0.2), 8)
	_plot(img, bot, k, PackedVector3Array([bot.lamp_pos]), Color(0, 0, 0), 8)
	# North (the forest) at the top: the grid's z grows southwards already.
	var err := img.save_png("res://shots/act2_searchlight_map.png")
	print("map: shots/act2_searchlight_map.png ", error_string(err))


## Act I's escape, top view, north up: grey - walls and trees; brown - the
## boards; blue - the dog's trail strip; pink - in reach of some enemy
## somewhere on his round (under the worst flare); white - safe; the careful
## escape in green, the reckless control in black, the scent control in red;
## the whole act from the cellar in dark blue, from behind the stove in purple.
func _draw_escape_map() -> void:
	var bot := _escape_bot
	if bot == null:
		print("map: the escape map needs the escape part (no --only, or --only=escape)")
		return
	var k := 6
	var img := _grid_image(bot, k)
	var colors := {"escape reckless": Color(0, 0, 0), "escape scent": Color(0.8, 0.1, 0.1),
			"escape": Color(0.1, 0.6, 0.2), "act1 CellarHatch": Color(0.1, 0.2, 0.6),
			"act1 StoveNook": Color(0.55, 0.2, 0.6)}
	for tr in _escape_traces:
		var col := Color(0.3, 0.3, 0.3)
		for key in colors:
			if str(tr[0]) == key:
				col = colors[key]
		_plot(img, bot, k, tr[1], col, 2)
	var err := img.save_png("res://shots/act1_escape_map.png")
	print("map: shots/act1_escape_map.png ", error_string(err))


## A bot's grid, `k` pixels a cell, north up (its z grows southwards).
func _grid_image(bot: Bot, k: int) -> Image:
	var img := Image.create(bot.gw * k, bot.gh * k, false, Image.FORMAT_RGB8)
	var escaper := bot as Escaper
	for z in bot.gh:
		for x in bot.gw:
			var i := z * bot.gw + x
			var col := Color(0.97, 0.97, 0.95)
			if bot.blocked[i] == 1:
				col = Color(0.45, 0.45, 0.45)
			elif escaper != null and escaper.boards[i] == 1:
				col = Color(0.8, 0.68, 0.5)
			elif escaper != null and escaper.scent_zone[i] == 1:
				col = Color(0.75, 0.85, 0.97)
			elif (bot.lit_bits[i] & 1) != 0:
				col = Color(0.98, 0.86, 0.55)
			elif bot.safe[i] == 0:
				col = Color(0.93, 0.8, 0.85)
			img.fill_rect(Rect2i(x * k, z * k, k, k), col)
	return img


## Points on a bot's grid image, `size` pixels each.
func _plot(img: Image, bot: Bot, k: int, points: PackedVector3Array, col: Color, size: int) -> void:
	for p in points:
		var px := int((p.x - bot.gx0) / Bot.CELL * k)
		var pz := int((p.z - bot.gz0) / Bot.CELL * k)
		if px >= 0 and pz >= 0 and px < img.get_width() and pz < img.get_height():
			img.fill_rect(Rect2i(px - size / 2, pz - size / 2, size, size), col)


# --- Act III ---------------------------------------------------------------------------

## Act III from its first frame (`intro`: with the briefing), the navmesh baked.
func _act3_level(intro: bool) -> Node3D:
	PanicSystem.reset()
	Perception.reset()
	Stealth.clear_scent()
	Stealth.reset_cover()
	Inventory.clear()
	LevelBase._checkpoint = {}
	LevelBase._resume_after_intro = false
	ACT3_SCRIPT._saved = {}
	var lv := (load(ACT3_PATH) as PackedScene).instantiate()
	lv.play_intro = intro
	lv.next_level = ""
	add_child(lv)
	var nav := lv.get_node("Navigation") as RuntimeNavRegion
	var t0 := Time.get_ticks_msec()
	while not nav.is_baked and Time.get_ticks_msec() - t0 < 15000:
		await get_tree().physics_frame
	await frames(2)
	return lv


func _act3_close(lv: Node3D, bot: Courier) -> void:
	bot.teardown()
	Engine.time_scale = 1.0
	get_tree().paused = false
	await _done_with(lv)
	ACT3_SCRIPT._saved = {}


## All of Act III by the careful runner (docs/ARCHITECTURE.md, "Проходимость
## Акта III").
func _act3() -> void:
	var lv := await _act3_level(true)
	var finished := [false]
	lv.slice_finished.connect(func() -> void: finished[0] = true)
	var bot := Courier.new()
	bot.setup(lv)
	# A failed interrogation reloads the current scene - here, the runner.
	var office := lv.interrogation as Interrogation
	office.failed.disconnect(lv._on_failed)
	office.failed.connect(func() -> void: bot._fail("the interrogation failed: the suspicion reached 1"))
	# So does a capture after he is let go (LevelBase._on_caught). A capture in
	# the garrison still leads to the office, as in the game.
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		en.player_caught.disconnect(lv._on_caught)
		en.player_caught.connect(func(by: Enemy) -> void:
			if lv.stage == lv.Stage.RELEASED:
				bot._fail("caught by %s after he was let go" % by.name)
			else:
				lv._on_caught(by))
	Engine.time_scale = SPEED
	if await bot.play(ACT3_FOREST):
		await bot.wait_until(func() -> bool: return finished[0], 20.0, "the end card")
	var card := (lv.get_node("Overlay/Caption") as Label).text
	var briefing: Array = (lv.briefing as Dictionary).get("briefing", [])
	var told := true
	for line in briefing:
		told = told and bot.briefing_seen.has(str(line))
	var chosen: Dictionary = PassRules.find(lv.pass_data, bot.chosen)
	var calm := true
	var stirred: Array = []
	for key in bot.peak:
		if float(bot.peak[key]) > 0.001 or int(bot.worst.get(key, 0)) != Enemy.State.PATROL:
			calm = false
			stirred.append([key, snappedf(float(bot.peak[key]), 0.001), Enemy.State.keys()[int(bot.worst.get(key, 0))]])
	var left_paused := get_tree().paused
	var legend: Dictionary = Interrogation.load_data().get("legend", {})
	var seen_text := " ".join(PackedStringArray(bot.briefing_seen)).to_lower()
	var legend_told := legend.size() == 4
	for key in legend:
		var word := str(legend[key]).split(" ")[0].to_lower()
		legend_told = legend_told and seen_text.contains(word.left(word.length() - 1) if word.length() > 4 else word)
	var own_place := bot.scouting.size() == 3
	for key in bot.scouting:
		var sc: Array = bot.scouting[key]
		var at: Vector3 = sc[0]
		var stood: Vector3 = sc[3]
		own_place = own_place and float(sc[1]) > 0.0 and Vector2(stood.x - at.x, stood.z - at.z).length() < 0.6
	var in_time := not bot.answer_left.is_empty()
	for left in bot.answer_left:
		in_time = in_time and float(left) > 0.0
	print("\n--- act3: the whole act ---")
	for e in bot.events:
		print("  ", e)
	for key in bot.scouting:
		var sc: Array = bot.scouting[key]
		print("  %s from %s: %.1f s, eyes down %d frames" % [key, bot._v(sc[0]), sc[1], sc[2]])
	print("  passes seen %s, took %s; checkpoint held %.1f s, moved %.3f m pushing on; staring %d frames, under eyes %d; in the yard %d frames"
			% [bot.passes_seen, bot.chosen, bot.checkpoint_held, bot.checkpoint_moved, bot.staring_frames,
			bot.staring_seen, bot.restricted_frames])
	print("  interrogation from %.2f, pass valid %s; outcomes %s; time left %s; typewriter after %d answers; shell fell after %d"
			% [bot.start_suspicion, bot.pass_valid, bot.outcomes, bot.answer_left, bot.detail_done_at,
			bot.revealed_after])
	print("  peaks %s; act took %.0f s of game time" % [bot.peak, bot.clock])
	check(bot.failed == "" and not left_paused, "act3: played through to the forest, nothing left paused",
			[bot.failed, left_paused])
	check(briefing.size() == 3 and told and legend_told and bot.briefing_done_at >= 0.0,
			"act3: all three lines of the briefing were on screen, the legend among them", bot.briefing_seen)
	check(bot.paused_while_comparing and bot.passes_seen.size() >= 2 and not chosen.is_empty()
			and PassRules.is_valid(chosen, lv.pass_data) and bot.pass_in_satchel,
			"act3: the bundle opens the paused pass check; he leafs to a pass that holds and takes it",
			[bot.passes_seen, bot.chosen])
	check(bot.checkpoint_held >= 2.0 and bot.checkpoint_moved < 0.05 and lv.layout.barrier_open,
			"act3: held at the checkpoint though he pushes on, then the barrier lifts",
			[bot.checkpoint_held, bot.checkpoint_moved])
	check(lv.scouted.size() == 3 and own_place,
			"act3: the trucks, the drums and the gun nest remembered, each from its own place", [lv.scouted, bot.scouting])
	check(bot.staring_frames > 0 and bot.staring_seen == 0,
			"act3: never stared where an enemy saw him (%d frames staring)" % bot.staring_frames, bot.first_seen_staring)
	check(calm and bot.peak.size() == 6, "act3: nobody turned, nobody's suspicion above 0", stirred)
	check(bot.restricted_frames == 0, "act3: never in the depot yard", bot.restricted_frames)
	check(absf(bot.start_suspicion - ACT3_SCRIPT.SUSPICION_DETAINED) < 0.01 and bot.pass_valid,
			"act3: rounded up at the exit: the interrogation starts light, the pass holds", bot.start_suspicion)
	check(bot.outcomes == ["consistent", "consistent", "consistent", "consistent", "consistent"]
			and bot.by_keys == 5 and in_time, "act3: five answers by keys, each in time, all keep the legend",
			[bot.outcomes, bot.by_keys, bot.answer_left])
	check(bot.detail_done_at >= 0 and bot.revealed_after >= 1 and bot.revealed_after < 5 and bot.released,
			"act3: the typewriter pulls him out, the shell falls before the last answer, he is let go",
			[bot.detail_done_at, bot.revealed_after, bot.released])
	check(finished[0] and card.contains("Конец Акта III") and card.contains("3 из 3"),
			"act3: in the forest the act ends; the card counts 3 of 3", card)
	await _act3_close(lv, bot)


## The control: the same runner stares at the trucks from the street while
## the patrol comes up it towards him. He must be noticed - or "nobody
## turned" says nothing about staring.
func _act3_eyes() -> void:
	var lv := await _act3_level(false)
	var bot := Courier.new()
	bot.setup(lv)
	lv._debug_arg("garrison", "")
	bot.player.global_position = ACT3_IN_SIGHT
	await frames(2)
	var trucks := lv.get_node("Scout/Trucks") as GazeTarget
	var patrol := lv.get_node("StreetPatrol") as Enemy
	bot.stop_when_turned = true
	Engine.time_scale = SPEED
	await bot.stare_in_sight(trucks, patrol, 8.0, 60.0)
	var turned := int(bot.worst.get("StreetPatrol", 0)) >= Enemy.State.SUSPICIOUS
	var left_paused := get_tree().paused
	print("\n--- act3, control: staring in the patrol's sight ---")
	for e in bot.events:
		print("  ", e)
	print("  staring %d frames, under eyes %d (first: %s); trucks held %.2f, done %s; patrol peak %.2f"
			% [bot.staring_frames, bot.staring_seen, bot.first_seen_staring, trucks.held, trucks.done,
			float(bot.peak.get("StreetPatrol", 0.0))])
	check(turned and bot.staring_seen > 0 and bot.failed.contains("turned") and not left_paused,
			"act3, control: staring at the trucks in the patrol's sight - the patrol turns", [bot.failed, bot.peak])
	await _act3_close(lv, bot)


## The careful runner at his place for the drums while the patrol walks up
## the street to it, the place before his eyes (docs/ARCHITECTURE.md,
## "Проходимость Акта III", «Прогон «патрульный идёт к нему»»). The whole
## act meets the patrol there only by its timing.
func _act3_patrol() -> void:
	var lv := await _act3_level(false)
	var bot := Courier.new()
	bot.setup(lv)
	lv._debug_arg("garrison", "")
	var drums := lv.get_node("Scout/Drums") as GazeTarget
	var patrol := lv.get_node("StreetPatrol") as Enemy
	bot.player.global_position = ACT3_DRUMS_AT
	# On his way back to the first point of his round, facing it.
	patrol.global_position = ACT3_PATROL_UP
	patrol.rotation.y = PI
	patrol._route_idx = 0
	patrol._wait = 0.0
	await frames(2)
	var eyes := patrol.sight_distance()
	Engine.time_scale = SPEED
	await bot.scout(drums, 60.0)
	var sc: Array = bot.scouting.get("Drums", [])
	var down := int(sc[2]) if sc.size() > 2 else -1
	var saw := int(bot.seen_frames.get("StreetPatrol", 0))
	var left_paused := get_tree().paused
	print("\n--- act3: the patrol walks up the street to his place ---")
	for e in bot.events:
		print("  ", e)
	print("  the patrol's eyes reach %.1f m; he saw him %d frames; eyes down %d frames; staring %d frames, under eyes %d (first: %s); patrol peak %.2f"
			% [eyes, saw, down, bot.staring_frames, bot.staring_seen, bot.first_seen_staring,
			float(bot.peak.get("StreetPatrol", 0.0))])
	check(bot.failed == "" and drums.done and saw > 0 and down > 0 and bot.staring_frames > 0
			and bot.staring_seen == 0 and float(bot.peak.get("StreetPatrol", 0.0)) == 0.0 and not left_paused,
			"act3, the patrol walks up the street to his place: eyes down while he sees him, then the drums",
			[bot.failed, saw, down, bot.staring_seen, bot.first_seen_staring, bot.peak])
	await _act3_close(lv, bot)
