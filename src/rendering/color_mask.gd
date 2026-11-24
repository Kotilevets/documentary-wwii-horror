class_name ColorMask
extends Node
## Marks the parent object for selective color (CLAUDE.md, section 2).
## Put this node inside an object; on _ready it writes the stencil value into
## every StandardMaterial3D / CSG material below the parent.
##   RED (1)         - blood, Nazi armbands, SS collar tabs, cap bands, flares
##   INTERACTIVE (2) - latches, cellar hatches, food, bandages, documents
## ShaderMaterials are skipped: such shaders must declare
## `stencil_mode write, compare_always, N;` themselves.

enum Channel { RED = 1, INTERACTIVE = 2 }

const RED_ALBEDO := Color(0.62, 0.05, 0.04)
const INTERACTIVE_ALBEDO := Color(0.30, 0.46, 0.44)

@export var channel: Channel = Channel.INTERACTIVE
## The marked copies (_marked): one per source material, channel and tint.
## Alike objects share it, and it outlives them: a copy held by one node
## alone made Godot 4.7.2 print `ERROR: Parameter "material" is null` when
## the node went while its mesh stayed - a sub-resource of a loaded scene,
## like the izba door's latch (docs/repro/godot_mesh_free_material_null).
## Shared: never change a marked material in place.
static var _copies := {}
## Replace albedo with the canonical color of the channel.
@export var tint_albedo: bool = true


func _ready() -> void:
	var target := get_parent()
	if target != null:
		apply(target, channel, tint_albedo)


static func apply(root: Node, ch: int, tint: bool = true) -> void:
	for node in _walk(root):
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.material_override != null:
				mi.material_override = _marked(mi.material_override, ch, tint)
			elif mi.mesh != null:
				for s in mi.mesh.get_surface_count():
					var m := mi.get_active_material(s)
					mi.set_surface_override_material(s, _marked(m, ch, tint))
		elif node is CSGPrimitive3D:
			var csg := node as CSGPrimitive3D
			csg.material = _marked(csg.material, ch, tint)


## Stencil value written by a material (0 when unmarked).
static func channel_of(material: Material) -> int:
	if material is BaseMaterial3D:
		var bm := material as BaseMaterial3D
		if bm.stencil_mode == BaseMaterial3D.STENCIL_MODE_CUSTOM \
				and (bm.stencil_flags & BaseMaterial3D.STENCIL_FLAG_WRITE) != 0:
			return bm.stencil_reference
	return 0


static func _marked(material: Material, ch: int, tint: bool) -> Material:
	if material is ShaderMaterial:
		push_warning("ColorMask: ShaderMaterial must write stencil %d itself" % ch)
		return material
	var key := "%d/%d/%d" % [material.get_instance_id() if material != null else 0, ch, int(tint)]
	var made := _copies.get(key) as Material
	if made != null:
		return made
	var bm: BaseMaterial3D
	if material is BaseMaterial3D:
		bm = (material as BaseMaterial3D).duplicate()
	else:
		bm = StandardMaterial3D.new()
	bm.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	bm.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
	bm.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
	bm.stencil_reference = ch
	if tint:
		bm.albedo_color = RED_ALBEDO if ch == Channel.RED else INTERACTIVE_ALBEDO
	_copies[key] = bm
	return bm


static func _walk(root: Node) -> Array[Node]:
	var out: Array[Node] = [root]
	for child in root.get_children():
		if child is ColorMask:
			continue
		out.append_array(_walk(child))
	return out
