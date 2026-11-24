extends SceneTree
## Bakes the synthesized sound placeholders (Sfx.synth) into
## assets/audio/placeholder/<kind>.res, so the game does not synthesize
## them while playing. Run after changing Sfx.synth:
##   godot --headless --path . --script res://tools/bake_sounds.gd
## The tests compare every baked file with the synthesizer, and run this
## script with `-- --check` (compare only, write nothing; exit code = number
## of stale or missing files): it runs without the autoloads, so sfx.gd must
## not name them (Stealth, ...) directly.

const SFX := preload("res://src/audio/sfx.gd")


func _init() -> void:
	var bank = JSON.parse_string(FileAccess.get_file_as_string(SFX.BANK_PATH))
	var kinds: Array[String] = []
	for id in bank:
		var k := str(bank[id].get("placeholder", ""))
		if k != "" and not kinds.has(k):
			kinds.append(k)
	var check := OS.get_cmdline_user_args().has("--check")
	if not check:
		DirAccess.make_dir_recursive_absolute(SFX.PLACEHOLDER_DIR)
	var failed := 0
	for k in kinds:
		var wav: AudioStreamWAV = SFX.synth(k)
		var path: String = SFX.PLACEHOLDER_DIR + k + ".res"
		if check:
			var baked := load(path) as AudioStreamWAV if ResourceLoader.exists(path) else null
			var same := baked != null and baked.data == wav.data and baked.loop_mode == wav.loop_mode
			if not same:
				failed += 1
			print("%s  %s" % [path, "same" if same else "STALE"])
			continue
		var err := ResourceSaver.save(wav, path)
		if err != OK:
			failed += 1
		print("%s  %.2f s  %s" % [path, wav.data.size() / 2.0 / SFX.MIX_RATE, "ok" if err == OK else "ERROR %d" % err])
	quit(failed)
