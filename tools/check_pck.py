"""Check what went into an exported Godot pack (.pck, format 4).

Usage:  python -I tools/check_pck.py build/windows/game.pck [--list]

Reads the pack directory without Godot and checks two things:
  - everything the game loads by path at run time is inside (JSON data,
    baked sound placeholders, materials, textures);
  - nothing that must stay out of the build is inside (tests, tools, docs,
    shots, references, test scenes).
Prints a summary by folder; --list prints every path. Exit code = number
of problems.
"""
import collections
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Folders that must not reach the player.
FORBIDDEN = ("tests/", "tools/", "docs/", "shots/", "assets/refs/",
             "src/scenes/test/", "build/")


def read_pck(path: Path) -> list[str]:
    with path.open("rb") as f:
        if f.read(4) != b"GDPC":
            raise ValueError(f"{path}: not a Godot pack (no GDPC magic)")
        fmt, _major, _minor, _patch, flags = struct.unpack("<5I", f.read(20))
        if fmt < 3:
            raise ValueError(f"{path}: pack format {fmt} is not supported")
        if flags & 1:
            raise ValueError(f"{path}: the pack directory is encrypted")
        f.read(8)  # base offset of the files
        if fmt >= 3:
            (dir_offset,) = struct.unpack("<Q", f.read(8))
            f.seek(dir_offset)
        (count,) = struct.unpack("<I", f.read(4))
        paths = []
        for _ in range(count):
            (n,) = struct.unpack("<I", f.read(4))
            p = f.read(n).rstrip(b"\0").decode("utf-8")
            f.read(8 + 8 + 16 + 4)  # offset, size, md5, flags
            paths.append(p.removeprefix("res://"))
        return paths


def expected_files() -> list[str]:
    """Files loaded by path at run time; the pack must have each of them
    (text resources may be exported as `<path>.remap`)."""
    out = []
    for p in sorted((ROOT / "assets/data").rglob("*.json")):
        out.append(p.relative_to(ROOT).as_posix())
    for folder, ext in (("assets/audio/placeholder", ".res"),
                        ("assets/materials", ".tres"),
                        ("assets/data/items", ".tres")):
        for p in sorted((ROOT / folder).glob("*" + ext)):
            out.append(p.relative_to(ROOT).as_posix())
    return out


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    paths = read_pck(Path(sys.argv[1]))
    have = set(paths)
    problems = 0

    for p in expected_files():
        if p not in have and p + ".remap" not in have:
            print("MISSING  ", p)
            problems += 1
    for p in paths:
        if p.startswith(FORBIDDEN):
            print("FORBIDDEN", p)
            problems += 1

    groups = collections.Counter(p.rsplit("/", 1)[0] if "/" in p else "."
                                 for p in paths)
    print(f"{len(paths)} files in the pack")
    for g, n in sorted(groups.items()):
        print(f"  {n:4d}  {g}")
    if "--list" in sys.argv:
        for p in paths:
            print(p)
    print("problems:", problems)
    return problems


if __name__ == "__main__":
    sys.exit(main())
