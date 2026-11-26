class_name SignalFlare
extends Node3D
## Signal flare fired over the village at intervals: a red (stencil 1) star
## with a red light. Scares the player a little.

## Seconds of dark between two flares: the count stands while one burns, so
## one goes up every interval + burn_time (20 s; docs/ARCHITECTURE.md, "Свет
## и тень").
@export var interval: float = 14.0
@export var first_delay: float = 3.0
@export var rise_height: float = 35.0
@export var burn_time: float = 6.0
@export var panic_spike: float = 0.08
## Fires on its own (see `interval`). The invasion sequence keeps it
## off during the prologue and launches the first flare itself.
@export var autofire: bool = true

@onready var star: MeshInstance3D = $Star
@onready var light: OmniLight3D = $Star/Light

var _timer: float
var _burn: float = -1.0


func _ready() -> void:
	_timer = first_delay
	star.visible = false
	light.light_energy = 0.0


func _process(delta: float) -> void:
	if _burn >= 0.0:
		_burn += delta
		var k := _burn / burn_time
		star.position = Vector3(sin(_burn) * 1.5, rise_height * sqrt(minf(k * 3.0, 1.0)) - k * 6.0, 0.0)
		light.light_energy = Flicker.light(6.0 * (1.0 - k), 0.15, _burn)  # sways, never strobes (Flicker)
		if k >= 1.0:
			_burn = -1.0
			star.visible = false
			light.light_energy = 0.0
		return
	if not autofire:
		return
	_timer -= delta
	if _timer <= 0.0:
		launch()


func launch() -> void:
	_timer = interval
	_burn = 0.0
	star.visible = true
	PanicSystem.spike(panic_spike)
