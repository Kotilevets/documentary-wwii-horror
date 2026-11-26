extends LevelBase
## Act I vertical slice: night village. The opening "Invasion" in the izba,
## then the escape to the forest edge. Shared logic and debug arguments are
## in LevelBase; Act I adds:
##   --skip-intro                         start after the invasion (door broken in)
##   --intro-scale=<0.05..1>              shorten the opening's timings

@onready var invasion: InvasionSequence = $Invasion
@onready var gunfire: GunfireAmbience = $Gunfire


func _start_story(full: bool) -> void:
	if full:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--intro-scale="):
				var k := clampf(arg.get_slice("=", 1).to_float(), 0.05, 1.0)
				invasion.prologue_time *= k
				invasion.warning_time *= k
				invasion.search_time *= k
				invasion.linger_time *= k
				invasion.look_back_time *= k
				invasion.sniff_every *= k
		invasion.beat_changed.connect(_on_invasion_beat)
		invasion.start()
	else:
		invasion.skip()
		gunfire.active = true


## Distant shots begin once the squad has gone from the izba: further down
## the village and beyond it they are still at it. Not before - the
## prologue is the last quiet evening.
func _on_invasion_beat(b: InvasionSequence.Beat) -> void:
	if b == InvasionSequence.Beat.ESCAPE:
		gunfire.active = true


## Caught after the squad has left: the reload skips the opening.
func _resume_checkpoint() -> bool:
	return invasion.beat == InvasionSequence.Beat.ESCAPE
