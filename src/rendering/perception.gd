extends Node
## Perception Distortion (docs/GAMEPLAY_AND_SHADERS.md, sections 2-4).
## distortion = PanicLevel * IllusionFactor, forced to 0 while a real document
## is being inspected. Also blends B&W <-> sepia when the player is in a safe
## zone. Writes the global shader parameters g_distortion and g_sepia.

signal distortion_changed(value: float)

## Act III "prozrenie": 1.0 = monsters, 0.0 = ordinary people.
var illusion_factor: float = 1.0
## Smoothed value actually sent to shaders.
var distortion: float = 0.0
var sepia: float = 0.0

@export var distortion_rate: float = 1.6
@export var sepia_rate: float = 0.6

var _suppressions: int = 0
var _safe_zones: int = 0
var _illusion_tween: Tween


func _ready() -> void:
	# Keep blending while the game is paused for document inspection.
	process_mode = Node.PROCESS_MODE_ALWAYS


func push_suppression() -> void:
	_suppressions += 1


func pop_suppression() -> void:
	_suppressions = maxi(_suppressions - 1, 0)


func is_suppressed() -> bool:
	return _suppressions > 0


func enter_safe_zone() -> void:
	_safe_zones += 1


func exit_safe_zone() -> void:
	_safe_zones = maxi(_safe_zones - 1, 0)


## Reality breaks in: sepia drops to zero at once instead of fading.
func cut_sepia() -> void:
	sepia = 0.0
	RenderingServer.global_shader_parameter_set("g_sepia", 0.0)


func in_safe_zone() -> bool:
	return _safe_zones > 0


func set_illusion_factor(value: float, duration: float = 0.0) -> void:
	if _illusion_tween != null:
		_illusion_tween.kill()
	if duration <= 0.0:
		illusion_factor = clampf(value, 0.0, 1.0)
		return
	_illusion_tween = create_tween()
	_illusion_tween.tween_property(self, "illusion_factor", clampf(value, 0.0, 1.0), duration)


func target_distortion() -> float:
	if is_suppressed():
		return 0.0
	return clampf(PanicSystem.level * illusion_factor, 0.0, 1.0)


func reset() -> void:
	_suppressions = 0
	_safe_zones = 0
	illusion_factor = 1.0
	distortion = 0.0
	sepia = 0.0


func _process(delta: float) -> void:
	var before := distortion
	distortion = move_toward(distortion, target_distortion(), distortion_rate * delta)
	sepia = move_toward(sepia, 1.0 if in_safe_zone() else 0.0, sepia_rate * delta)
	if not is_equal_approx(before, distortion):
		distortion_changed.emit(distortion)
	RenderingServer.global_shader_parameter_set("g_distortion", distortion)
	RenderingServer.global_shader_parameter_set("g_sepia", sepia)
