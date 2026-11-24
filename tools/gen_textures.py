"""Procedural, tileable surface textures for the prototype (own work, no
external sources): albedo + normal map, 512x512, grey (the game is black
and white; the post-process takes luminance only).

Run from the project root:  python -I tools/gen_textures.py
Output: assets/textures/procedural/<name>_albedo.png, <name>_normal.png
Registered in docs/ASSETS_AND_REFS.md (procedural, generated here).
Every pattern is periodic, so the textures tile without seams."""
import pathlib
import sys

import numpy as np
from PIL import Image, ImageDraw

N = 512
OUT = pathlib.Path("assets/textures/procedural")
FY = np.fft.fftfreq(N)[:, None]
FX = np.fft.fftfreq(N)[None, :]
YY, XX = np.mgrid[0:N, 0:N].astype(np.float32)


def fbm(seed, beta=2.0, kx=1.0, ky=1.0, lo=0.0):
    """Periodic noise with a 1/f^beta spectrum. kx / ky > 1 suppress
    variation along that axis (features stretched along it)."""
    rng = np.random.default_rng(seed)
    w = rng.standard_normal((N, N))
    f = np.sqrt((FX * kx) ** 2 + (FY * ky) ** 2)
    f[0, 0] = 1.0
    amp = 1.0 / f ** (beta / 2.0)
    amp[f < lo] = 0.0
    spec = np.fft.fft2(w) * amp
    spec[0, 0] = 0.0
    r = np.real(np.fft.ifft2(spec))
    return ((r - r.mean()) / (r.std() + 1e-9)).astype(np.float32)


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def voronoi(seed, count, ax=1.0):
    """Distances to the nearest and second nearest of `count` points,
    wrapped (periodic). ax < 1 stretches the cells along x."""
    rng = np.random.default_rng(seed)
    p = rng.uniform(0, N, (count, 2)).astype(np.float32)
    d1 = np.full((N, N), 1e9, np.float32)
    d2 = np.full((N, N), 1e9, np.float32)
    idx = np.zeros((N, N), np.int32)
    for i, (px, py) in enumerate(p):
        dx = np.abs(XX - px)
        dx = np.minimum(dx, N - dx) * ax
        dy = np.abs(YY - py)
        dy = np.minimum(dy, N - dy)
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < d1
        d2 = np.where(closer, d1, np.minimum(d2, d))
        idx = np.where(closer, i, idx)
        d1 = np.where(closer, d, d1)
    return d1, d2, idx


def normal_map(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
    n = np.dstack([-dx, dy, np.ones_like(h)])  # OpenGL style: green is up
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).round().astype(np.uint8)


def save(name, albedo, height, strength):
    a = (np.clip(albedo, 0, 1) * 255).round().astype(np.uint8)
    Image.fromarray(np.dstack([a, a, a]), "RGB").save(OUT / f"{name}_albedo.png")
    Image.fromarray(normal_map(height, strength), "RGB").save(OUT / f"{name}_normal.png")
    print(f"{name}: mean {albedo.mean():.3f}")


def wrapped_lines(seed, count, length, width, alpha):
    """Scratches: random short lines drawn with wrap-around."""
    rng = np.random.default_rng(seed)
    img = Image.new("F", (N, N), 0.0)
    d = ImageDraw.Draw(img)
    for _ in range(count):
        x, y = rng.uniform(0, N, 2)
        a = rng.uniform(0, np.pi)
        l = rng.uniform(length * 0.3, length)
        x2, y2 = x + np.cos(a) * l, y + np.sin(a) * l
        for ox in (-N, 0, N):
            for oy in (-N, 0, N):
                d.line([(x + ox, y + oy), (x2 + ox, y2 + oy)], fill=alpha, width=width)
    return np.asarray(img, np.float32)


# --- surfaces ------------------------------------------------------------------

def ground():
    low, mid, fine = fbm(1, 2.4), fbm(2, 1.8), fbm(3, 0.8)
    wet = smooth(0.6, 1.4, fbm(4, 2.6))
    d1, d2, _ = voronoi(5, 90)
    stones = smooth(5.0, 2.0, d1) * (fbm(6, 1.0) > 0.9)
    h = 0.5 * low + 0.3 * mid + 0.15 * fine + 1.5 * stones
    alb = 0.32 + 0.05 * low + 0.03 * mid + 0.025 * fine - 0.08 * wet + 0.12 * stones
    save("ground", alb, h, 1.2)


def road():
    low, streak, fine = fbm(11, 2.2), fbm(12, 1.6, kx=6.0), fbm(13, 0.8)
    d1, _, _ = voronoi(14, 160)
    peb = smooth(3.5, 1.0, d1) * (fbm(15, 1.0) > 0.4)
    h = 0.4 * low + 0.35 * streak + 0.15 * fine + 1.2 * peb
    alb = 0.45 + 0.04 * low + 0.035 * streak + 0.02 * fine + 0.08 * peb
    save("road", alb, h, 1.0)


def logs():
    per = 128  # four logs per tile
    t = (YY % per) / per
    u = 2 * t - 1
    prof = np.sqrt(np.clip(1 - u ** 2, 0, 1))
    gap = smooth(0.86, 0.97, np.abs(u))
    log_i = (YY // per).astype(int)
    shade = np.array([0.0, 0.03, -0.025, 0.015])[log_i % 4]
    grain = fbm(21, 1.6, kx=14.0) * 0.6 + fbm(22, 1.0, kx=30.0) * 0.4
    d1, _, _ = voronoi(23, 14)
    knots = smooth(9.0, 2.0, d1 * np.where((YY % per > 30) & (YY % per < 98), 1, 9))
    h = prof * 2.0 + 0.08 * grain - 0.4 * knots - 1.5 * gap
    alb = (0.27 + 0.13 * prof + 0.035 * grain + shade - 0.1 * knots) * (1 - gap) + 0.07 * gap
    save("logs", alb, h, 3.0)


def planks():
    per = 64  # eight boards per tile
    board = (XX // per).astype(int)
    s = (XX % per) / per
    gap = (s < 0.05).astype(np.float32)
    rng = np.random.default_rng(31)
    shade = rng.uniform(-0.04, 0.04, N // per)[board]
    grain = fbm(32, 1.5, ky=16.0) * 0.6 + fbm(33, 0.9, ky=40.0) * 0.4
    joints = rng.integers(0, N, N // per)[board]
    joint = (np.abs(YY - joints) < 1.5).astype(np.float32)
    nails = np.zeros((N, N), np.float32)
    for b in range(N // per):
        for ny in (joints[0, b * per] + 12, joints[0, b * per] - 12):
            cy, cx = ny % N, b * per + per // 2
            dy = np.minimum(np.abs(YY - cy), N - np.abs(YY - cy))
            nails += smooth(3.0, 1.5, np.sqrt(dy ** 2 + (XX - cx) ** 2))
    h = 0.1 * grain - 1.5 * gap - 0.8 * joint + 0.2 * nails
    alb = (0.4 + 0.04 * grain + shade - 0.12 * joint) * (1 - gap) + 0.06 * gap - 0.15 * nails
    save("planks", alb, h, 3.0)


def bark():
    # Pine bark: long plates split by deep vertical furrows.
    d1, d2, idx = voronoi(43, 60, ax=2.2)
    rng = np.random.default_rng(44)
    plate_shade = rng.uniform(-0.03, 0.03, 60)[idx]
    furrow = smooth(4.0, 0.5, d2 - d1)
    rough = fbm(41, 1.8, ky=5.0)
    fine = fbm(42, 1.0, ky=8.0)
    h = smooth(0.0, 12.0, d2 - d1) + 0.3 * rough + 0.1 * fine - 1.0 * furrow
    alb = (0.24 + plate_shade + 0.03 * rough + 0.015 * fine) * (1 - furrow) + 0.06 * furrow
    save("bark", alb, h, 2.5)


def plaster():
    stain, grain = fbm(51, 2.6), fbm(52, 0.7)
    ridge = np.abs(fbm(53, 2.2))
    cracks = smooth(0.035, 0.0, ridge) * (fbm(54, 2.5) > 0.3)
    chips = smooth(1.3, 1.6, fbm(55, 2.0))
    h = 0.2 * grain - 1.5 * cracks - 0.8 * chips
    alb = 0.56 + 0.05 * stain + 0.015 * grain - 0.25 * cracks - 0.12 * chips
    save("plaster", alb, h, 1.5)


def brick():
    course, length = 32, 128
    row = (YY // course).astype(int)
    xs = XX + (row % 2) * (length // 2)
    col = (xs // length).astype(int) % (N // length)
    mortar_y = (YY % course) < 4
    mortar_x = (xs % length) < 4
    mortar = (mortar_y | mortar_x).astype(np.float32)
    rng = np.random.default_rng(61)
    shade = rng.uniform(-0.06, 0.06, (N // course, N // length))[row % (N // course), col]
    grain = fbm(62, 1.0)
    soot = smooth(0.3, 1.5, fbm(63, 2.6))
    h = (1 - mortar) * (1.0 + 0.1 * grain) - 0.2 * mortar
    alb = (0.42 + shade + 0.03 * grain) * (1 - mortar) + 0.55 * mortar - 0.15 * soot
    save("brick", alb, h, 2.0)


def metal():
    mottle, fine = fbm(71, 2.4), fbm(72, 0.8)
    scratches = wrapped_lines(73, 140, 60, 1, 1.0)
    h = 0.1 * fine - 0.6 * scratches
    alb = 0.2 + 0.035 * mottle + 0.01 * fine + 0.12 * scratches
    save("metal", alb, h, 1.0)


def burlap():
    weave = np.sin(XX * 2 * np.pi / 6) * np.sin(YY * 2 * np.pi / 6)
    fiber = fbm(81, 1.0, kx=3.0)
    per = 128
    u = 2 * ((YY % per) / per) - 1
    bulge = np.sqrt(np.clip(1 - u ** 2, 0, 1))
    seam = smooth(0.88, 0.98, np.abs(u))
    h = 0.15 * weave + 0.1 * fiber + 1.5 * bulge - 1.0 * seam
    alb = (0.42 + 0.06 * bulge + 0.025 * weave + 0.02 * fiber) * (1 - 0.6 * seam)
    save("burlap", alb, h, 2.0)


def canvas():
    weave = np.sin(XX * 2 * np.pi / 4) * np.sin(YY * 2 * np.pi / 4)
    folds = fbm(91, 2.4, kx=4.0)
    h = 0.1 * weave + 1.2 * folds
    alb = 0.45 + 0.012 * weave + 0.04 * folds
    save("canvas", alb, h, 1.5)


def charred():
    # Burnt wood: small blocks elongated along the grain.
    d1, d2, idx = voronoi(101, 240, ax=0.45)
    crack = smooth(2.0, 0.4, d2 - d1)
    rng = np.random.default_rng(102)
    cell = rng.uniform(-0.025, 0.03, 240)[idx]
    ash = smooth(1.2, 1.8, fbm(103, 2.0))
    dome = smooth(0.0, 9.0, d2 - d1)
    h = 1.2 * dome - 1.5 * crack
    alb = (0.09 + cell + 0.02 * dome) * (1 - crack) + 0.02 * crack + 0.16 * ash
    save("charred", alb, h, 2.5)


def thatch():
    strands = fbm(111, 1.2, ky=40.0)
    clumps = fbm(112, 2.0, ky=8.0)
    per = 128
    course = smooth(0.85, 1.0, (YY % per) / per)
    h = 0.5 * strands + 0.4 * clumps - 1.2 * course
    alb = 0.46 + 0.05 * strands + 0.04 * clumps - 0.18 * course
    save("thatch", alb, h, 2.5)


def foliage():
    leaves = fbm(121, 1.6)
    big = fbm(122, 2.6)
    holes = smooth(0.4, -0.6, leaves + 0.5 * big)
    h = leaves + 0.5 * big - 2.0 * holes
    alb = 0.28 + 0.05 * leaves + 0.03 * big - 0.16 * holes
    save("foliage", alb, h, 1.5)


ALL = [ground, road, logs, planks, bark, plaster, brick, metal, burlap, canvas, charred, thatch, foliage]

# --- materials -------------------------------------------------------------------
# Name used by the levels -> (texture, albedo tint, repeats per metre, world
# triplanar). World triplanar needs no UVs and has no seams between blocks;
# moving parts (door, barrier pole) use local triplanar so the texture
# does not swim. Loaded by src/rendering/surfaces.gd.
MATERIALS = {
    "ground": ("ground", 1.0, 0.25, True),
    "earth": ("ground", 0.85, 0.25, True),
    "ash": ("ground", 0.55, 0.25, True),
    "road": ("road", 1.0, 0.33, True),
    "logs": ("logs", 1.0, 1.0, True),
    "log": ("logs", 0.95, 1.0, True),
    "planks": ("planks", 1.0, 0.8, True),
    "wood": ("planks", 0.95, 0.8, True),
    "plank": ("planks", 1.0, 0.8, True),
    "door_planks": ("planks", 1.05, 0.8, False),
    "bark": ("bark", 1.0, 0.7, True),
    "hedge": ("foliage", 1.0, 0.6, True),
    "brick": ("brick", 1.0, 0.8, True),
    "stove": ("plaster", 1.0, 0.5, True),
    "plaster": ("plaster", 1.0, 0.5, True),
    "board": ("plaster", 1.0, 0.5, True),
    "paint": ("plaster", 0.9, 0.5, False),
    "stone": ("plaster", 0.72, 1.0, True),
    "charred": ("charred", 1.0, 1.0, True),
    "roof": ("thatch", 1.0, 0.8, True),
    "metal": ("metal", 1.0, 1.0, True),
    "truck": ("metal", 1.0, 0.5, True),
    "sand": ("burlap", 1.0, 1.0, True),
    "canvas": ("canvas", 1.0, 0.5, True),
}
ROUGH = {"metal": 0.55, "truck": 0.6, "charred": 0.9}
MAT_DIR = pathlib.Path("assets/materials")


def write_materials():
    MAT_DIR.mkdir(parents=True, exist_ok=True)
    for name, (tex, tint, rep, world) in MATERIALS.items():
        t = f"{tint:g}"
        (MAT_DIR / f"{name}.tres").write_text(f"""[gd_resource type="StandardMaterial3D" load_steps=3 format=3]

[ext_resource type="Texture2D" path="res://assets/textures/procedural/{tex}_albedo.png" id="1_albedo"]
[ext_resource type="Texture2D" path="res://assets/textures/procedural/{tex}_normal.png" id="2_normal"]

[resource]
albedo_color = Color({t}, {t}, {t}, 1)
albedo_texture = ExtResource("1_albedo")
roughness = {ROUGH.get(name, 1.0)}
normal_enabled = true
normal_texture = ExtResource("2_normal")
uv1_scale = Vector3({rep:g}, {rep:g}, {rep:g})
uv1_triplanar = true
uv1_world_triplanar = {"true" if world else "false"}
""", encoding="utf-8")
    print(f"{len(MATERIALS)} materials")


def write_import_settings():
    """Mipmaps on (textures seen at a distance), VRAM compression, normal
    maps marked as such."""
    for png in OUT.glob("*.png"):
        imp = png.with_suffix(".png.import")
        if imp.exists():
            continue
        normal = 1 if png.stem.endswith("_normal") else 0
        imp.write_text(f"""[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://{png.as_posix()}"

[params]

compress/mode=2
compress/high_quality=false
compress/normal_map={normal}
mipmaps/generate=true
detect_3d/compress_to=0
""", encoding="utf-8")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    only = sys.argv[1:]
    for f in ALL:
        if not only or f.__name__ in only:
            f()
    write_materials()
    write_import_settings()
