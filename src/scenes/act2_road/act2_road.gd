extends LevelBase
## Act II vertical slice "Дорога (Свидетель)" (CLAUDE.md, 3): night road
## north from the village. Through the burned village past a police
## patrol; around the road checkpoint through a field of tripwires; past
## the transit camp and its searchlight; the gallows at the crossroads; the
## forest. Layout is built by act2_layout.gd.
## Checkpoints (LevelBase.checkpoints): the burned village, the field, the
## haystack mid-field past the wire, in its shadow (out of the searchlight's
## reach: tests/playthrough_runner.gd). After the camp there is nothing left to be caught by but the camp
## guard himself, and the gallows stand in his sight - no checkpoint there.


func _start_story(full: bool) -> void:
	if not full:
		return
	# Out of black, with the act's title.
	fade.modulate.a = 1.0
	caption.text = "Акт II. Дорога"
	var t := create_tween()
	t.tween_interval(2.5)
	t.tween_callback(func() -> void: caption.text = "")
	t.tween_property(fade, "modulate:a", 0.0, 2.5)
