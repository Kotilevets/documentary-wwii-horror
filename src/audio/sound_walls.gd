extends RefCounted
## What stops sound: one rule for what the boy hears (Sfx.is_occluded) and
## what enemies hear of him (Stealth.sound_walled) - docs/ARCHITECTURE.md,
## "Звук сквозь стены" and "Слух сквозь стены".
##   Walls: colliders in GROUP - the walls of buildings (the izba, the barn,
##   barracks, the dugout, the houses of the garrison, the office, the room of
##   the dream) - and a door's panel while the door is shut (its parent's
##   blocks_sound()). Everything else on the way lets sound through: hedges,
##   haystacks, trees, posts, carts, sandbags, a wardrobe's body.
##   One room - no walls: an ear and a sound over the same board floor
##   (group "board_floors": the izba, the dream room, the office) are never
##   walled off; a stove, a table or an open door leaf in it are not walls
##   between them.
##   A sound is walled off only if a wall stands in the way at every one of
##   HEIGHTS above its point (a table or a bench over him is not a wall).
## Preloaded, with no class_name and no autoload names: tools/bake_sounds.gd
## loads Sfx - and so this script - without either.

const GROUP := "sound_walls"
## Layers a ray looks at: the world and doors.
const MASK := 1 | 16
const HEIGHTS: Array[float] = [0.3, 1.1]
## How many other things one ray looks past before it gives up on a wall.
const HOPS := 6
## The last metres before a sound's point are not counted: a sound on a wall
## or a door (a knock, the latch) is heard on both sides of it.
const CUT := 0.25
## A board floor counts for sounds up to this height above it.
const ROOM_HEIGHT := 3.0


## Is a sound made at `pos` (on the ground) walled off from an ear at `ear`
## whose feet stand at `feet`? An ear lower than the top of HEIGHTS (a dog,
## a crouching boy) is taken at that height, so a crate next to it is no wall.
static func walled(space: PhysicsDirectSpaceState3D, tree: SceneTree, feet: Vector3, ear: Vector3,
		pos: Vector3, exclude: Array[RID] = []) -> bool:
	if space == null:
		return false
	var room := room_at(tree, pos)
	if room != null and room == room_at(tree, feet):
		return false
	var top: float = HEIGHTS[HEIGHTS.size() - 1]
	var from := Vector3(ear.x, maxf(ear.y, feet.y + top), ear.z)
	for h in HEIGHTS:
		if not between(space, from, pos + Vector3.UP * h, exclude):
			return false
	return true


## A wall or a shut door between `a` and `b`, the last `cut` metres before `b`
## not counted; anything else on the way is looked past.
static func between(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3,
		exclude: Array[RID] = [], cut: float = CUT) -> bool:
	var d := b - a
	if space == null or d.length() <= cut + 0.05:
		return false
	var past: Array[RID] = exclude.duplicate()
	var q := PhysicsRayQueryParameters3D.create(a, b - d.normalized() * cut, MASK)
	for i in HOPS:
		q.exclude = past
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return false
		if stops(hit.get("collider")):
			return true
		past.append(hit["rid"] as RID)
	return false


## A wall of a building, or the panel of a door that is shut.
static func stops(collider: Object) -> bool:
	if not (collider is Node):
		return false
	var n := collider as Node
	if n.is_in_group(GROUP):
		return true
	var door := n.get_parent()
	return door != null and door.has_method("blocks_sound") and bool(door.call("blocks_sound"))


## The board floor (a room) under `point` - up to ROOM_HEIGHT above it - or
## null (out of doors, an earth floor).
static func room_at(tree: SceneTree, point: Vector3) -> Node:
	if tree == null:
		return null
	for f in tree.get_nodes_in_group("board_floors"):
		var n := f as Node3D
		if n == null or not (n.get("size") is Vector3):
			continue
		var size: Vector3 = n.get("size")
		var local := n.global_transform.affine_inverse() * point
		if absf(local.x) <= size.x * 0.5 and absf(local.z) <= size.z * 0.5 \
				and local.y >= -0.5 and local.y <= ROOM_HEIGHT:
			return n
	return null
