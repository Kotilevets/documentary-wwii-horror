extends Node
## The guard of a test run (docs/ARCHITECTURE.md, "Проверка"). A child of the
## runner in tests/test_runner.tscn, flow_runner.tscn and
## playthrough_runner.tscn, with a script of its own, so that it still works
## when the runner's script does not:
## - the runner did not load (a parse error, or the project was never
##   imported): Godot would sit idle for ever - the guard says so and quits 1;
## - every error logged from now until finish() - a script error,
##   push_error, an engine or shader error, not a warning - is a failure,
##   named with the group it happened in (a script error mid-test does not
##   stop the run: the function ends there, its caller goes on, and only the
##   log would show it). Errors before this node is ready (autoloads, loading
##   the scene) it cannot see: tools/checks/run_suites.py counts those;
## - a run still going after `deadline` seconds of real time (an await that
##   never comes back) fails and quits instead of hanging;
## - the scene loaded a second time (a level's failure path reloaded the
##   current scene, and that was the runner: found 19.11.2026 with a failed
##   Act III interrogation, mutation P52) fails and quits: the deadline and
##   the errors would start afresh and the run would go round for ever.
## The runner starts only if first_start() and ends through
## finish(passes, failures): the summary line, then quit with failures +
## errors, at most 125 (an exit code is one byte on Linux and macOS: 256
## would be 0; the summary has the true count).

## Seconds of real time the whole run may take.
@export var deadline := 1800.0

var _errors := _Errors.new()
var _t0 := 0
var _done := false
var _again := false
## Set when the first guard of this run is ready: the script stays loaded
## when its scene is reloaded, so a second guard finds it set.
static var _loaded := false


## Collects every error Godot logs, from any thread.
class _Errors extends Logger:
	var lines: Array[String] = []
	var group := ""
	var _m := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		# push_error() is logged from the engine's C++: the script line is the
		# top of the script backtrace.
		var where := "%s:%d" % [file, line]
		for bt in script_backtraces:
			if bt.get_frame_count() > 0:
				where = "%s:%d" % [bt.get_frame_file(0), bt.get_frame_line(0)]
				break
		var kind := "a script error" if error_type == ERROR_TYPE_SCRIPT else \
				("a shader error" if error_type == ERROR_TYPE_SHADER else "an error")
		var what := rationale if rationale != "" else code
		_m.lock()
		lines.append("%s in %s: %s (%s)" % [kind, group if group != "" else "no group", what, where])
		_m.unlock()

	func set_group(g: String) -> void:
		_m.lock()
		group = g
		_m.unlock()

	func taken() -> Array[String]:
		var out: Array[String] = []
		_m.lock()
		out.append_array(lines)
		_m.unlock()
		return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _loaded:
		_again = true
		_done = true
		print("FAIL  run guard: the runner's scene was loaded a second time - a level's failure path reloaded"
				+ " the current scene, the runner itself; the results before it are lost")
		print("\n0 passed, 1 failed")
		get_tree().quit(1)
		return
	_loaded = true
	_t0 = Time.get_ticks_msec()
	OS.add_logger(_errors)
	await get_tree().process_frame
	if not get_parent().has_method(&"check"):
		print("FAIL  run guard: the runner's script did not load in ", get_tree().current_scene.scene_file_path,
				" - a parse error above, or the project was never imported (godot --headless --path . --import)")
		print("\n0 passed, 1 failed")
		_done = true
		get_tree().quit(1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		OS.remove_logger(_errors)


## False when this is the scene loaded a second time: the guard has said so
## and quits, and the runner must not start.
func first_start() -> bool:
	return not _again


## The group (a _test_* function, a playthrough part) that runs from now on:
## errors are named with it.
func begin(group: String) -> void:
	_errors.set_group(group)


func end(_group: String) -> void:
	_errors.set_group("")


## Errors logged so far.
func errors() -> int:
	return _errors.taken().size()


## The end of the run: each error as a failure, the summary, and quit with
## failures + errors (at most 125).
func finish(passes: int, failures: int) -> void:
	if _done:
		return
	_done = true
	var errs := _errors.taken()
	for e in errs:
		print("FAIL  run guard: ", e)
	print("\n%d passed, %d failed" % [passes, failures + errs.size()])
	get_tree().quit(mini(failures + errs.size(), 125))


func _process(_delta: float) -> void:
	if _done or Time.get_ticks_msec() - _t0 < deadline * 1000.0:
		return
	var p := get_parent()
	print("FAIL  run guard: the run is still going after %d s of real time, in %s" % [deadline,
			_errors.group if _errors.group != "" else "no group"])
	finish(int(p.get(&"passes")), int(p.get(&"failures")) + 1)
