extends RefCounted
## How long the frames of one part of the game took, for the run log ("game: frames";
## docs/ARCHITECTURE.md, "Метки в журнале запуска"): a histogram of 0.25 ms bins up to
## 200 ms (a longer frame goes to the last bin) and the worst frame exactly. The memory
## stays the same however long the part lasts. GameState loads it with preload.

const BIN_MS := 0.25
const BINS := 800

var count := 0
var worst := 0.0
var _bins := PackedInt32Array()


func _init() -> void:
	_bins.resize(BINS)


## One frame of `ms` milliseconds.
func add(ms: float) -> void:
	_bins[clampi(int(ms / BIN_MS), 0, BINS - 1)] += 1
	count += 1
	worst = maxf(worst, ms)


## The frame time `q` of the frames do not exceed (0.5 - the median, 0.95 - the 95th
## percentile), to 0.25 ms: the middle of the bin where that share is reached, never more
## than the worst frame; in the last bin - the worst frame itself.
func percentile(q: float) -> float:
	if count == 0:
		return 0.0
	var need := maxi(1, ceili(q * count))
	var seen := 0
	for i in BINS:
		seen += _bins[i]
		if seen >= need:
			return worst if i == BINS - 1 else minf((i + 0.5) * BIN_MS, worst)
	return worst


## "21540 frames, median 16.6 ms, 95% 17.1 ms, worst 48.3 ms".
func summary() -> String:
	return "%d frames, median %.1f ms, 95%% %.1f ms, worst %.1f ms" % [count, percentile(0.5),
			percentile(0.95), worst]
