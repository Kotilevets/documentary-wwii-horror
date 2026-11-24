extends Node
## End-to-end run through the game with real scene changes:
## menu -> Act I -> the dream -> Act II (+ pause: restart the act) -> Act III ->
## epilogue -> menu (+ pause: back to the menu). The unit tests set
## next_level = "" and never change scenes; this catches what they skip.
## Run:  godot --headless --path . res://tests/flow_runner.tscn
## Exit code = number of failures. Game time runs x6.
##
## The driver moves itself under the root so that it outlives the scene
## changes it causes.

const MENU := "res://src/ui/main_menu.tscn"
const EPILOGUE := "res://src/scenes/epilogue/epilogue.tscn"
const DREAM := "res://src/scenes/interlude_night/night_dream.tscn"

var failures := 0
var passes := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_adopt.call_deferred()


func _adopt() -> void:
	var tree := get_tree()
	get_parent().remove_child(self)
	tree.root.add_child(self)
	await _run()
	Engine.time_scale = 1.0
	print("\n%d passed, %d failed" % [passes, failures])
	get_tree().quit(failures)


func check(cond: bool, name: String, detail: Variant = "") -> void:
	if cond:
		passes += 1
		print("PASS  ", name)
	else:
		failures += 1
		print("FAIL  ", name, "  ", detail)


func current_path() -> String:
	var s := get_tree().current_scene
	return s.scene_file_path if s != null else ""


## Wait (real time) until the current scene is `path` (and, if given, a
## different instance than `old_id`: a reload).
func wait_scene(path: String, timeout: float = 20.0, old_id: int = 0) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout * 1000.0:
		var s := get_tree().current_scene
		if current_path() == path and s.is_node_ready() and s.get_instance_id() != old_id:
			for i in 3:
				await get_tree().process_frame
			return true
		await get_tree().process_frame
	return false


func _run() -> void:
	GameState.save_path = "user://test_flow.json"
	GameState.reset()
	Engine.time_scale = 6.0
	get_tree().change_scene_to_file(MENU)
	check(await wait_scene(MENU), "the main menu opens")
	var menu := get_tree().current_scene
	check(not menu.continue_button.visible, "a first start offers no «Продолжить»")
	menu.start_act(0)

	for i in GameState.ACTS.size():
		var path: String = GameState.ACTS[i].scene
		check(await wait_scene(path), "%s loads" % GameState.ACTS[i].title, current_path())
		var level := get_tree().current_scene as LevelBase
		check(level != null and level.is_in_group("levels"), "%s is a level" % GameState.ACTS[i].title)
		check(GameState.reached == i + 1 and GameState.last_act == i, "progress marks act %d" % (i + 1),
				[GameState.reached, GameState.last_act])
		check(not get_tree().paused, "the act starts unpaused")
		if i == 1:
			# Pause, restart the act: the same act again, unpaused.
			PauseMenu.open()
			check(get_tree().paused and PauseMenu.is_open, "Esc-pause opens in the act")
			var old_id := level.get_instance_id()
			PauseMenu.restart_act()
			check(await wait_scene(path, 20.0, old_id), "«Начать акт заново» reloads the act")
			check(not get_tree().paused and not PauseMenu.is_open, "and the game runs again")
			level = get_tree().current_scene as LevelBase
		# The act's ending leads to the next scene by itself.
		if i == 1:
			# Paused on the end card, the next scene waits for the game to go on
			# (until 20.11.2026 its 5 s ran under the pause menu).
			var card := [false]
			level.slice_finished.connect(func() -> void: card[0] = true)
			level._on_reached_forest()
			var t0 := Time.get_ticks_msec()
			while not card[0] and Time.get_ticks_msec() - t0 < 20000:
				await get_tree().process_frame
			PauseMenu.open()
			var t1 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t1 < 2500:  # 15 s of game time at x6
				await get_tree().process_frame
			check(card[0] and current_path() == path and PauseMenu.is_open and get_tree().paused,
					"paused on the end card, the next act waits", current_path())
			check(level.caption.text.begins_with("Конец Акта II. Дорога"),
					"the end card of Act II reads like the others", level.caption.text)
			PauseMenu.close()
		else:
			level._on_reached_forest()
		if i == 0:
			check(await wait_scene(DREAM), "after the village comes the night (the dream)", current_path())
			var dream := get_tree().current_scene as LevelBase
			check(dream.is_in_group("levels") and GameState.reached == 2 and GameState.last_act == 1,
					"the dream opens Act II for «Продолжить»", [GameState.reached, GameState.last_act])
			dream._on_reached_forest()

	check(await wait_scene(EPILOGUE), "after Act III comes the epilogue", current_path())
	check(GameState.finished and GameState.reached == GameState.ACTS.size(), "the game is marked finished")
	var ep := get_tree().current_scene
	ep.show_summary()
	ep._to_menu.pressed.emit()
	check(await wait_scene(MENU), "the epilogue returns to the menu")
	menu = get_tree().current_scene
	check(menu.continue_button.visible and menu.continue_button.text.contains("Акт III"),
			"«Продолжить» now leads to Act III", menu.continue_button.text)
	var open := true
	for b in menu.act_buttons:
		open = open and not b.disabled
	check(open, "every act can be chosen after the game")

	# From an act back to the menu through the pause.
	menu.start_act(1)
	check(await wait_scene(GameState.ACTS[1].scene), "an act chosen from the menu loads")
	PauseMenu.open()
	PauseMenu.to_main_menu()
	check(await wait_scene(MENU), "«Главное меню» from the pause")
	check(not get_tree().paused and not PauseMenu.is_open, "the menu is not paused")
	GameState.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_flow.json"))
