class_name RuntimeNavRegion
extends NavigationRegion3D
## Bakes the navigation mesh at runtime from the level's static colliders
## (CSG with use_collision, StaticBody3D) on physics layers 1 and 6 (wire), so the
## player and enemies are not carved out. CSG builds its geometry a few
## frames after the scene enters the tree, hence the delay.
## When the level gets real art, bake in the editor and drop this script.

signal baked

@export var settle_frames: int = 5
@export var agent_radius: float = 0.4
@export var agent_height: float = 1.8
@export var cell_size: float = 0.1

var is_baked := false


func _ready() -> void:
	add_to_group("runtime_nav")
	_bake.call_deferred()


func _bake() -> void:
	for i in settle_frames:
		await get_tree().physics_frame
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1 | Stealth.SEE_THROUGH_LAYER
	nm.agent_radius = agent_radius
	nm.agent_height = agent_height
	nm.agent_max_climb = 0.3
	nm.cell_size = cell_size
	nm.cell_height = 0.1
	var source := collect_source(nm, get_parent())
	NavigationServer3D.bake_from_source_geometry_data(nm, source)
	navigation_mesh = nm
	# The region reaches the map asynchronously; big levels take several
	# frames. Wait until the map answers with a point of this mesh.
	var probe := Vector3.ZERO
	if nm.get_polygon_count() > 0:
		probe = to_global(nm.get_vertices()[nm.get_polygon(0)[0]])
	var map := get_navigation_map()
	for i in 600:
		await get_tree().physics_frame
		if nm.get_polygon_count() == 0:
			break
		if (NavigationServer3D.map_get_iteration_id(map) > 0
				and NavigationServer3D.map_get_closest_point(map, probe).distance_to(probe) < 0.5):
			break
	is_baked = true
	baked.emit()


## The source geometry under `root`, collected by hand. CSG goes in through its
## collision shape (CSGShape3D.bake_collision_shape - the faces physics already
## has). Everything else - `root` itself and every other node under it - goes
## through the engine's own parsers, node by node from a temporary group
## (SOURCE_GEOMETRY_GROUPS_EXPLICIT): StaticBody3D shapes, a GridMap's
## collision, NavigationObstacle3D, any parser a plugin registers - read on the
## CPU, as before; the mesh parsers do nothing for static colliders. Left to
## the engine, CSG is parsed from its visible meshes read back from the
## RenderingServer ("had to parse RenderingServer meshes at runtime" in every
## log), which blocks rendering on a real GPU.
static func collect_source(nm: NavigationMesh, root: Node) -> NavigationMeshSourceGeometryData3D:
	var source := NavigationMeshSourceGeometryData3D.new()
	var mask := nm.geometry_collision_mask
	var group := "nav_source_%d" % root.get_instance_id()
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "", true, false))
	var csgs: Array[CSGShape3D] = []
	var others: Array[Node] = []
	for n in nodes:
		if n is CSGShape3D:
			var csg := n as CSGShape3D
			if csg.is_root_shape() and csg.use_collision and (csg.collision_layer & mask) != 0:
				csgs.append(csg)
		else:
			others.append(n)
	for n in others:
		n.add_to_group(group)
	var only := nm.duplicate() as NavigationMesh
	only.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_EXPLICIT
	only.geometry_source_group_name = group
	# Parsed even when nothing in the group adds geometry: the parse also sets
	# the root's transform, the space the CSG faces below are added in.
	NavigationServer3D.parse_source_geometry_data(only, source, root)
	for n in others:
		n.remove_from_group(group)
	for csg in csgs:
		# Empty for a CSG with nothing left after subtraction or not built yet.
		var faces := csg.bake_collision_shape().get_faces()
		if not faces.is_empty():
			source.add_faces(faces, csg.global_transform)
	return source
