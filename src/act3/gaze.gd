class_name Gaze
extends RefCounted
## Where the boy is looking. Shared by the interrogation (details of the
## room) and the scouting in the garrison.


## True if the camera looks at `point`: in range, within a cone wide
## enough to cover `radius` at that distance, nothing of the world between.
static func looks_at(camera: Camera3D, point: Vector3, radius: float, max_distance: float = 30.0) -> bool:
	var from := camera.global_position
	var to := point - from
	var d := to.length()
	if d > max_distance or d < 0.01:
		return false
	var half := maxf(atan2(radius, d), deg_to_rad(3.0))
	if (-camera.global_transform.basis.z).angle_to(to / d) > half:
		return false
	var q := PhysicsRayQueryParameters3D.create(from, point, 1)
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit.position as Vector3).distance_to(point) < radius
