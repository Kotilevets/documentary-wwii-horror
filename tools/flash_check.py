"""Flash check of rendered frames against WCAG 2.2 SC 2.3.1 (three flashes or below threshold).

  python -I tools/flash_check.py <folder of PNG frames> --fps 60 [--from S] [--to S] [--json out.json]

Frames are read in name order (Movie Maker writes f00000000.png, ...). The image is pooled into blocks of about a
third of a degree (the screen is taken as 1/3 width = 10 degrees, WCAG's proxy of a 341x256 px field at 1024x768),
so film grain averages out while a lamp, a window or the whole view flickering stays whole. For every block:
- general flash: the block's relative luminance Y (linear, Rec. 709 weights) swings between its last extreme and
  now by 0.10 or more, the darker of the two below 0.80 — one transition; a flash is a pair of them;
- red flash: the same on (R - G - B) * 320 (negative counts as 0) by more than 20, where one of the two states is a
  saturated red (R / (R + G + B) >= 0.8).
A block flashes too fast at a frame if it made more than six transitions (three flashes) in the second before.
A frame fails if such blocks cover more than 25% of some 10-degree field (a window of 1/3 x 1/3 of the screen,
moved in steps of 1/12).
Printed: the worst field's share of too-fast blocks, the most transitions a block made in a second, and the
worst seconds; the general and red counts are kept apart. Two more limits: extended flashing (IRIS and Harding:
four or more transitions a second over that area for 4 s of any 5) and the game's own margin (no more than four
transitions, two flashes, a second over that area). The exit code counts frames over any of the three."""
import argparse
import json
import pathlib
import sys

import numpy as np
from PIL import Image

LUM = 0.10       # WCAG: a change of 10% of the maximum relative luminance
DARK = 0.80      # ... where the darker state is below 0.80
RED_SAT = 0.8    # R / (R + G + B) for a saturated red
RED_STEP = 20.0  # change of (R - G - B) * 320
MAX_TRANS = 6    # three flashes = six transitions in any one second
TARGET = 4       # the game's own margin: two flashes a second (docs/ARCHITECTURE.md, «Вспышки и мерцание»)
EXT_SECONDS = 4  # IRIS / Harding extended failure: 4-6 transitions a second for 4 s of the last 5
EXT_WINDOW = 5
AREA = 0.25      # of a 10-degree field
GRID_X = 96      # blocks across the screen: 32 per 10 degrees


def linear(srgb: np.ndarray) -> np.ndarray:
    v = srgb.astype(np.float64) / 255.0
    return np.where(v <= 0.04045, v / 12.92, ((v + 0.055) / 1.055) ** 2.4)


def pooled(path: pathlib.Path, gx: int) -> tuple:
    """(Y, red quantity, saturated red) per block of the frame."""
    img = np.asarray(Image.open(path).convert("RGB"))
    h, w, _ = img.shape
    bs = max(1, w // gx)
    gy = max(1, h // bs)
    lin = linear(img[: gy * bs, : gx * bs]).reshape(gy, bs, gx, bs, 3).mean(axis=(1, 3))
    r, g, b = lin[..., 0], lin[..., 1], lin[..., 2]
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    red = np.maximum(r - g - b, 0.0) * 320.0
    sat = r / np.maximum(r + g + b, 1e-9) >= RED_SAT
    return y, red, sat


class Swings:
    """Per-block transitions: swings of at least `step` from the running extreme (hysteresis). Before the first
    swing both the highest and the lowest value are kept; after it, the extreme of the current move."""

    def __init__(self, first: np.ndarray, step: float, flag: np.ndarray):
        self.step = step
        self.hi = first.copy()
        self.lo = first.copy()
        self.hi_flag = flag.copy()
        self.lo_flag = flag.copy()
        self.dir = np.zeros(first.shape, dtype=np.int8)  # +1: last swing rose (tracking the top), -1: fell

    def feed(self, v: np.ndarray, flag: np.ndarray, counts) -> np.ndarray:
        """Transitions completed at this frame that count (bool per block). counts(a, a_flag, b, b_flag) tells
        whether a swing between states a and b counts (the darker below 0.80; a saturated red in one of them).
        dir 0: no swing yet, hi and lo are the highest and lowest so far; +1: the last swing rose, hi is the top
        of this move; -1: it fell, lo is the bottom. A swing starts the next move at v."""
        top = v > self.hi
        bottom = v < self.lo
        self.hi = np.where(top, v, self.hi)
        self.hi_flag = np.where(top, flag, self.hi_flag)
        self.lo = np.where(bottom, v, self.lo)
        self.lo_flag = np.where(bottom, flag, self.lo_flag)
        drop = self.hi - v
        climb = v - self.lo
        fall = (self.dir >= 0) & (drop >= self.step)
        rise = (self.dir <= 0) & (climb >= self.step)
        both = fall & rise
        fall = fall & ~(both & (climb > drop))
        rise = rise & ~fall
        hit = (fall & counts(self.hi, self.hi_flag, v, flag)) | (rise & counts(self.lo, self.lo_flag, v, flag))
        swung = fall | rise
        self.dir = np.where(fall, -1, np.where(rise, 1, self.dir)).astype(np.int8)
        self.hi = np.where(swung, v, self.hi)
        self.lo = np.where(swung, v, self.lo)
        self.hi_flag = np.where(swung, flag, self.hi_flag)
        self.lo_flag = np.where(swung, flag, self.lo_flag)
        return hit


def fields(mask: np.ndarray) -> float:
    """Largest share of True blocks in a 1/3 x 1/3 window of the screen moved in steps of 1/12."""
    gy, gx = mask.shape
    wy, wx = max(1, gy // 3), max(1, gx // 3)
    sy, sx = max(1, gy // 12), max(1, gx // 12)
    c = np.pad(mask.astype(np.int32).cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    best = 0.0
    for y0 in range(0, gy - wy + 1, sy):
        for x0 in range(0, gx - wx + 1, sx):
            n = c[y0 + wy, x0 + wx] - c[y0, x0 + wx] - c[y0 + wy, x0] + c[y0, x0]
            best = max(best, n / (wy * wx))
    return best


def check(frames: list, fps: float, gx: int = GRID_X) -> dict:
    win = int(round(fps))
    y0, r0, s0 = pooled(frames[0], gx)
    gen = Swings(y0, LUM, s0)
    red = Swings(r0, RED_STEP, s0)
    hist_g, hist_r = [], []
    rows = []
    for i, f in enumerate(frames[1:], start=1):
        y, r, s = pooled(f, gx)
        tg = gen.feed(y, s, lambda a, af, b, bf: np.minimum(a, b) < DARK)
        tr = red.feed(r, s, lambda a, af, b, bf: af | bf)
        hist_g.append(tg)
        hist_r.append(tr)
        if len(hist_g) > win:
            hist_g.pop(0)
            hist_r.pop(0)
        ng = np.sum(hist_g, axis=0)
        nr = np.sum(hist_r, axis=0)
        rows.append(dict(frame=i, t=i / fps, gen_area=fields(ng > MAX_TRANS), red_area=fields(nr > MAX_TRANS),
                         gen_most=int(ng.max()), red_most=int(nr.max()),
                         over_target=max(fields(ng > TARGET), fields(nr > TARGET)),
                         busy=int(max(fields(ng >= TARGET), fields(nr >= TARGET)) > AREA)))
    bad = [r for r in rows if r["gen_area"] > AREA or r["red_area"] > AREA]
    # extended: 4 or more transitions a second over a quarter of a field for EXT_SECONDS of the last EXT_WINDOW
    ext = []
    span, need = int(round(EXT_WINDOW * fps)), int(round(EXT_SECONDS * fps))
    busy = [r["busy"] for r in rows]
    run = 0
    for k in range(len(busy)):
        run += busy[k] - (busy[k - span] if k >= span else 0)
        if run >= need:
            ext.append(rows[k]["t"])
    over = [r for r in rows if r["over_target"] > AREA]
    return dict(fps=fps, frames=len(frames), blocks=list(y0.shape), rows=rows, failing=len(bad),
                worst_gen_area=max((r["gen_area"] for r in rows), default=0.0),
                worst_red_area=max((r["red_area"] for r in rows), default=0.0),
                most_gen=max((r["gen_most"] for r in rows), default=0),
                most_red=max((r["red_most"] for r in rows), default=0),
                bad_seconds=sorted({int(r["t"]) for r in bad}),
                extended=len(ext), extended_seconds=sorted({int(x) for x in ext}),
                over_target=len(over), over_target_seconds=sorted({int(r["t"]) for r in over}))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("folder")
    ap.add_argument("--fps", type=float, required=True)
    ap.add_argument("--from", dest="t0", type=float, default=0.0)
    ap.add_argument("--to", dest="t1", type=float, default=1e9)
    ap.add_argument("--json")
    a = ap.parse_args()
    frames = sorted(pathlib.Path(a.folder).glob("*.png"))
    frames = [f for k, f in enumerate(frames) if a.t0 <= k / a.fps <= a.t1]
    if len(frames) < 2:
        print("no frames")
        return 1
    r = check(frames, a.fps)
    print("%s: %d frames at %g fps, %dx%d blocks; general: worst field %.0f%% of blocks over 3 flashes/s, at most "
          "%d transitions/s in a block; red: worst field %.0f%%, at most %d; failing frames %d%s" % (
              a.folder, r["frames"], r["fps"], r["blocks"][1], r["blocks"][0], 100 * r["worst_gen_area"],
              r["most_gen"], 100 * r["worst_red_area"], r["most_red"], r["failing"],
              (" in seconds %s" % r["bad_seconds"]) if r["failing"] else ""))
    print("  extended flashing (IRIS): %d frames%s; over the game's margin of two flashes a second: %d frames%s" % (
        r["extended"], (" in seconds %s" % r["extended_seconds"]) if r["extended"] else "",
        r["over_target"], (" in seconds %s" % r["over_target_seconds"]) if r["over_target"] else ""))
    if a.json:
        pathlib.Path(a.json).write_text(json.dumps(r, indent=1), encoding="utf-8")
    return r["failing"] + r["extended"] + r["over_target"]


if __name__ == "__main__":
    sys.exit(main())
