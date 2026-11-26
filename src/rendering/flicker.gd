class_name Flicker
extends RefCounted
## Light that trembles without strobing, and screens swapped by a key no
## faster than the eye can bear (docs/ARCHITECTURE.md, "Вспышки и
## мерцание"). Photosensitive epilepsy: WCAG 2.2 allows at most three
## flashes in any second; the game keeps to two, and flicker that goes on
## stays under one and a half (IRIS fails four changes a second held for
## four seconds of five).
## - A light changes deeply (by more than SHIMMER of itself) only slowly:
##   sway(), under SWAY_HZ.
## - Anything faster stays within SHIMMER, peak to peak: tremble().

## Fast tremble, peak to peak, as a share of the light.
const SHIMMER := 0.05
## The faster of the two sines in sway(), Hz: three changes a second at most.
const SWAY_HZ := 1.13
## Key presses that swap the whole screen (the journal, the pause, a hiding
## place, the satchel in it, the passes) are at least this far apart, s:
## three swaps a second at most, however fast the keys are pressed.
const SWAP_GAP := 0.35

static var _last_swap_msec := -1000000


## Slow uneven sway, 0..1: two sines at 0.7 and SWAY_HZ Hz (their ratio is
## not a simple fraction, so the pattern does not soon repeat). `phase`
## shifts it, so that two lights do not sway together.
static func sway(t: float, phase: float = 0.0) -> float:
	return 0.5 + 0.25 * sin(TAU * 0.7 * t + phase) + 0.25 * sin(TAU * SWAY_HZ * t + phase * 2.3)


## Fast tremble, -0.5..0.5 (peak to peak at most 1): two sines at 7.9 and
## 12.3 Hz, a flame's flutter. Scale it by SHIMMER.
static func tremble(t: float, phase: float = 0.0) -> float:
	return 0.25 * sin(TAU * 7.9 * t + phase * 1.3) + 0.25 * sin(TAU * 12.3 * t + phase * 1.7)


## A light of `level` that dips by up to `depth` of itself in a slow sway
## and trembles by SHIMMER: level * (1 - depth * sway) * (1 + SHIMMER * tremble).
static func light(level: float, depth: float, t: float, phase: float = 0.0) -> float:
	return level * (1.0 - depth * sway(t, phase)) * (1.0 + SHIMMER * tremble(t, phase))


## May a key press swap the whole screen now? True at most once every
## SWAP_GAP s of real time, for all such keys together; a true answer counts
## as the swap. Asked only for key presses: what the game itself opens or
## closes (a document picked up, the pause on losing focus) does not wait.
static func allow_swap() -> bool:
	if not swap_ready():
		return false
	_last_swap_msec = Time.get_ticks_msec()
	return true


## Would a key press swap the screen now (allow_swap() without counting it)?
## For bots that press keys as a person does, not mashing them.
static func swap_ready() -> bool:
	return Time.get_ticks_msec() - _last_swap_msec >= roundi(SWAP_GAP * 1000.0)


## Tests: the next key press may swap at once.
static func forget_swaps() -> void:
	_last_swap_msec = -1000000
