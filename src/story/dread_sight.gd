class_name DreadSight
extends Marker3D
## Something the boy should not have seen (CLAUDE.md, 3, Act II: gallows
## with signs). Looking at it - within `distance`, in the middle of the
## view, nothing in between - raises panic; the first time it is a jolt.
## Panic rises "при виде сцен насилия" (GAMEPLAY_AND_SHADERS.md, 2).
## The scene itself is shown without naturalism: what is seen is left to
## the place, not to bodies.

signal witnessed

@export var distance: float = 26.0
@export var look_dot: float = 0.93
@export var first_spike: float = 0.3
@export var panic_rate: float = 0.25

var seen := false
var looking := false


func _physics_process(delta: float) -> void:
	var p := Stealth.player as Player
	looking = p != null and not p.is_hidden and _looks_at(p)
	if not looking:
		return
	PanicSystem.apply_continuous(panic_rate, delta)
	if not seen:
		seen = true
		PanicSystem.spike(first_spike)
		witnessed.emit()


func _looks_at(p: Player) -> bool:
	var cam := p.camera.global_transform
	var to := global_position - cam.origin
	if to.length() > distance:
		return false
	if (-cam.basis.z).dot(to.normalized()) < look_dot:
		return false
	var q := PhysicsRayQueryParameters3D.create(cam.origin, global_position, 1)
	q.exclude = [p.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()
