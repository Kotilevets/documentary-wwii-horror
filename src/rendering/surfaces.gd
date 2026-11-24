class_name Surfaces
extends RefCounted
## Textured surfaces by the names the levels use ("logs", "ground",
## "plaster"...): StandardMaterial3D files in assets/materials/, made by
## tools/gen_textures.py from procedural textures (own work, see
## docs/ASSETS_AND_REFS.md). World-space triplanar mapping: CSG blocks
## need no UVs and neighbouring blocks have no seams. Grey only - the
## colour rule stays with the post-process and ColorMask.

const DIR := "res://assets/materials/"


## The material for `name`, or null when the surface has no texture
## (wire, rope, paper: they stay flat colours).
static func material(name: String) -> StandardMaterial3D:
	var path := DIR + name + ".tres"
	if ResourceLoader.exists(path):
		return load(path) as StandardMaterial3D
	return null
