"""Self-test of tools/flash_check.py on synthetic frames: each case must pass or fail as stated
(docs/ARCHITECTURE.md, «Вспышки и мерцание»). The frames go to a temporary folder, removed after.
Usage: python -I tools/flash_check_selftest.py [path to flash_check.py]"""
import importlib.util
import math
import pathlib
import shutil
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
src = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "flash_check.py"
spec = importlib.util.spec_from_file_location("flash_check", src)
FC = importlib.util.module_from_spec(spec)
spec.loader.exec_module(FC)

W, H, FPS, SEC = 480, 270, 60, 3
FIELD = (W // 3) * (H // 3)


def square(share):
    """A square covering `share` of one 10-degree field, in the screen's middle."""
    side = int(math.sqrt(share * FIELD))
    x0, y0 = (W - side) // 2, (H - side) // 2
    return slice(y0, y0 + side), slice(x0, x0 + side)


def case(name, frame_at, sec=SEC):
    d = pathlib.Path(tempfile.mkdtemp(prefix="flash_selftest_"))
    for k in range(FPS * sec):
        Image.fromarray(frame_at(k / FPS, k).astype(np.uint8)).save(d / ("f%08d.png" % k))
    r = FC.check(sorted(d.glob("*.png")), FPS)
    shutil.rmtree(d)
    return r


def flicker(hz, share, lo, hi, rgb=(1, 1, 1), shape="sine"):
    ys, xs = square(share)

    def at(t, k):
        img = np.full((H, W, 3), 20, dtype=np.float64)
        if shape == "sine":
            s = 0.5 + 0.5 * math.sin(2 * math.pi * hz * t)
        else:
            s = 1.0 if (t * hz) % 1.0 < 0.5 else 0.0
        v = lo + (hi - lo) * s
        img[ys, xs] = [v * c for c in rgb]
        return img
    return at


def grain(t, k):
    rng = np.random.default_rng(k)
    return np.clip(100 + rng.normal(0, 40, (H, W, 1)).repeat(3, axis=2), 0, 255)


def one_cut(t, k):
    v = 230 if 1.0 <= t < 1.2 else 20
    return np.full((H, W, 3), v, dtype=np.float64)


# name, frames, seconds, (general fail, red fail, over the two-flash margin, extended)
CASES = [
    ("5 Hz over 40% of a field", flicker(5.0, 0.4, 40, 120), 3, (True, False, True, False)),
    ("2.5 Hz over 40% of a field", flicker(2.5, 0.4, 40, 120), 3, (False, False, True, False)),
    ("3 Hz over 40% of a field (exactly three)", flicker(3.0, 0.4, 40, 120, shape="square"), 3, (False, False, True, False)),
    ("3.6 Hz over 40% of a field", flicker(3.6, 0.4, 40, 120, shape="square"), 3, (True, False, True, False)),
    ("1.5 Hz over 40% of a field", flicker(1.5, 0.4, 40, 120), 3, (False, False, False, False)),
    ("2.2 Hz over 40% of a field for 6 s", flicker(2.2, 0.4, 40, 120), 6, (False, False, True, True)),
    ("5 Hz over 10% of a field", flicker(5.0, 0.1, 40, 120), 3, (False, False, False, False)),
    ("5 Hz too shallow (delta Y 0.035)", flicker(5.0, 0.4, 60, 80), 3, (False, False, False, False)),
    ("5 Hz bright (darker state above 0.80)", flicker(5.0, 0.4, 235, 255), 3, (False, False, False, False)),
    ("grain over the whole screen", grain, 3, (False, False, False, False)),
    ("one cut to white and back", one_cut, 3, (False, False, False, False)),
    ("5 Hz dim saturated red over 40% of a field", flicker(5.0, 0.4, 40, 140, rgb=(1, 0, 0)), 3, (False, True, True, False)),
]

bad = 0
for name, fn, sec, want in CASES:
    r = case(name.replace(" ", "_").replace("%", "pc").replace("(", "").replace(")", "").replace(".", "_"), fn, sec)
    got = (r["worst_gen_area"] > FC.AREA, r["worst_red_area"] > FC.AREA, r["over_target"] > 0, r["extended"] > 0)
    ok = got == want
    bad += not ok
    print("%-44s %s  general %3.0f%% (most %2d/s)  red %3.0f%% (most %2d/s)  margin %s extended %s  want %s" % (
        name, "ok  " if ok else "FAIL", 100 * r["worst_gen_area"], r["most_gen"], 100 * r["worst_red_area"],
        r["most_red"], got[2], got[3], want))
print("self-test:", "passed" if bad == 0 else "%d cases wrong" % bad)
sys.exit(bad)
