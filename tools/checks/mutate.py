"""Deliberate breakages (docs/ARCHITECTURE.md, "Проверка", "Каталоги поломок"): each mutant of a catalogue in
tools/checks/mutants/ changes the code the way a real mistake would, and the run named for it must fail.

    python -I tools/checks/mutate.py spotted              # all mutants of mutants/spotted.py
    python -I tools/checks/mutate.py spotted A21 A30      # just these
    python -I tools/checks/mutate.py spotted --dry        # only check that every edit still applies
    python -I tools/checks/mutate.py --list               # the catalogues
    python -I tools/checks/mutate.py --restore            # put back the files of a run that was killed

A catalogue is a Python file with
    RUN = {"args": ["res://tests/test_runner.tscn", "--", "--only=_test_spotted"], "timeout": 600}
    MUTANTS = [{"name": "A1 what the mistake is", "edits": [("src/ai/enemy.gd", "old text", "new text")]}, ...]
Edits are exact text, each found exactly once (after the mutant's earlier edits to that file), written with "\\n"
(a file kept in CRLF gets its own endings). Instead of (old, new) an edit can be ("file", {"git": "rev"}) - the
whole file as it was in that revision - or ("file", {"copy": "files/name.txt"}) - a file next to the catalogue.
A mutant can also have "run" (its own run instead of RUN), "bake": True (rebake the sound placeholders after the
edit, tools/bake_sounds.gd), "env" (environment for the run), "stale": "why" (kept for the record, not run),
"parse_ok": True (a script that does not parse is the point - the guard's own checks, mutants/guard.py: judged
by the exit code alone, and only a timeout makes it BROKEN) and "survives": "why" (a known survivor the docs
explain - an equivalent mutant, or a breakage this run is not meant to see: reported KNOWN, not counted; caught,
it says so). Any other key, such as "note", is for the reader.
A run: "verdict": "checks" (default) - a mutant is caught when a check fails or the run exits non-zero, and the
control must pass at least one check, fail none and log no error before its first check; "exit" - caught when
the run exits non-zero, and the control needs only exit 0 (a probe such as tools/heart_sync_probe.gd that prints
no checks). "godot_args" replaces the default --headless (the heart probe needs a real audio driver:
["--display-driver", "headless", "--audio-driver", "WASAPI"]). "controls": N - the control N times, all green
(the heart probe on a real driver: one green run proves little).

Every touched file (and the baked placeholders, when a mutant bakes) is copied at the start - in memory and to
.godot/mutate_backup/ - and put back by bytes after each mutant and at the end. A run killed from outside cannot
put them back: the next start then refuses until --restore has. The control runs on the good code must be green
first. A run that does not parse, does not end in time or whose bake fails is BROKEN, not caught: the mutant
proves nothing. Exit code = SURVIVED + BROKEN (+ files not restored)."""
import argparse
import json
import pathlib
import runpy
import shutil
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import common  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent
CATALOGUES = HERE / "mutants"
PLACEHOLDERS = "assets/audio/placeholder"
BAKE = ["--headless", "--path", ".", "--script", "res://tools/bake_sounds.gd"]
BACKUP = ".godot/mutate_backup"


def load(name: str) -> tuple:
    path = pathlib.Path(name)
    if not path.suffix:
        path = CATALOGUES / (name + ".py")
    cat = runpy.run_path(str(path))
    return path, cat["RUN"], cat["MUTANTS"]


def endings(good: bytes, text: str) -> bytes:
    b = text.encode("utf-8")
    return b.replace(b"\n", b"\r\n") if b"\r\n" in good else b


def apply(project: pathlib.Path, cat_path: pathlib.Path, good: dict, edits: list, rev_text) -> dict:
    """The files of one mutant, mutated in memory; raises ValueError naming the edit that no longer applies."""
    out = {}
    for edit in edits:
        f = edit[0]
        cur = out.get(f, good[f])
        if isinstance(edit[1], dict):
            spec = edit[1]
            if "git" in spec:
                out[f] = rev_text(spec["git"], f)
            else:
                out[f] = (cat_path.parent / spec["copy"]).read_bytes()
            continue
        old, new = endings(good[f], edit[1]), endings(good[f], edit[2])
        n = cur.count(old)
        if n != 1:
            raise ValueError("%s: found %d times: %r" % (f, n, edit[1][:70]))
        out[f] = cur.replace(old, new)
    return out


def save_backup(project: pathlib.Path, good: dict, baked: dict) -> pathlib.Path:
    """The good bytes on disk too, before the first mutant is written: a killed run leaves them behind."""
    b = project / BACKUP
    b.mkdir(parents=True)
    names = {}
    for i, (f, data) in enumerate(sorted(good.items())):
        names[f] = "%03d_%s" % (i, pathlib.PurePosixPath(f).name)
        (b / names[f]).write_bytes(data)
    (b / "placeholders").mkdir()
    for n, data in baked.items():
        (b / "placeholders" / n).write_bytes(data)
    (b / "manifest.json").write_text(json.dumps({"files": names, "placeholders": sorted(baked) if baked else None},
                                                indent=1), encoding="utf-8")
    return b


def restore_backup(project: pathlib.Path) -> int:
    """--restore: the files of a run that was killed, back from the backup; the backup then goes."""
    b = project / BACKUP
    if not b.exists():
        print("no backup in %s: nothing to restore" % b)
        return 0
    man = json.loads((b / "manifest.json").read_text(encoding="utf-8"))
    for f, n in man["files"].items():
        data = (b / n).read_bytes()
        if (project / f).read_bytes() != data:
            (project / f).write_bytes(data)
            print("restored", f)
    if man["placeholders"] is not None:
        ph = project / PLACEHOLDERS
        for p in ph.iterdir():
            if p.is_file() and p.name not in man["placeholders"]:
                p.unlink()
                print("removed", p.relative_to(project).as_posix())
        for n in man["placeholders"]:
            data = (b / "placeholders" / n).read_bytes()
            if not (ph / n).exists() or (ph / n).read_bytes() != data:
                (ph / n).write_bytes(data)
                print("restored", PLACEHOLDERS + "/" + n)
    shutil.rmtree(b)
    print("restored by bytes from %s; backup removed" % b)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("catalogue", nargs="?")
    ap.add_argument("only", nargs="*", help="mutant ids (the first word of the name)")
    ap.add_argument("--dry", action="store_true", help="only check that every edit applies; Godot is not run")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--restore", action="store_true", help="put back the files of a run that was killed")
    common.common_args(ap)
    a = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8", line_buffering=True)
    project = a.project.resolve()
    if a.restore:
        return restore_backup(project)
    if a.list or not a.catalogue:
        for p in sorted(CATALOGUES.glob("*.py")):
            _, run, ms = load(str(p))
            stale = sum(1 for m in ms if m.get("stale"))
            known = sum(1 for m in ms if m.get("survives"))
            print("%-14s %3d mutants%s%s  %s" % (p.stem, len(ms), (", %d stale" % stale) if stale else "",
                                                 (", %d known survivors" % known) if known else "",
                                                 " ".join(run["args"])))
        return 0
    if (project / BACKUP).exists():
        print("%s exists: an earlier run was killed and its mutant may still be in the files. Look at what it holds"
              " (manifest.json), then: python -I tools/checks/mutate.py --restore" % (project / BACKUP))
        return 2
    cat_path, run, mutants = load(a.catalogue)
    chosen = [m for m in mutants if not a.only or m["name"].split()[0] in a.only]
    if a.only and len(chosen) != len(set(a.only)):
        print("no such mutant:", sorted(set(a.only) - {m["name"].split()[0] for m in chosen}))
        return 2
    files = sorted({e[0] for m in chosen for e in m["edits"]})
    good = {f: (project / f).read_bytes() for f in files}

    revs = {}

    def rev_text(rev: str, f: str) -> bytes:
        import subprocess
        if (rev, f) not in revs:
            revs[(rev, f)] = subprocess.run(["git", "-C", str(project), "show", "%s:%s" % (rev, f)],
                                            capture_output=True, check=True).stdout
        return revs[(rev, f)]

    # Every edit must apply to the code as it is now; a stale catalogue says so instead of passing.
    planned = []
    bad = 0
    for m in chosen:
        if m.get("stale"):
            print("%-44s STALE    %s" % (m["name"][:44], m["stale"]))
            continue
        try:
            planned.append((m, apply(project, cat_path, good, m["edits"], rev_text)))
        except ValueError as e:
            bad += 1
            print("%-44s NO MATCH %s" % (m["name"][:44], e))
    if bad:
        print("%d mutant(s) no longer apply to the code: fix the catalogue (or mark them stale, saying why)" % bad)
        return bad
    if a.dry:
        print("dry: %d mutants apply, %d stale" % (len(planned), len(chosen) - len(planned)))
        return 0

    godot = common.godot_path(a.godot)
    bakes = any(m.get("bake") for m, _ in planned)
    baked = {p.name: p.read_bytes() for p in (project / PLACEHOLDERS).iterdir() if p.is_file()} if bakes else {}

    def restore() -> None:
        for f, b in good.items():
            if (project / f).read_bytes() != b:
                (project / f).write_bytes(b)
        if bakes:
            for p in (project / PLACEHOLDERS).iterdir():
                if p.is_file() and p.name not in baked:
                    p.unlink()
            for n, b in baked.items():
                if (project / PLACEHOLDERS / n).read_bytes() != b:
                    (project / PLACEHOLDERS / n).write_bytes(b)

    def go(r: dict, env: dict | None) -> tuple:
        # "godot_args" replaces --headless (a probe on a real audio driver: --display-driver headless
        # --audio-driver WASAPI).
        return common.run_godot(godot, r.get("godot_args", ["--headless"]) + ["--path", "."] + r["args"],
                                project, r.get("timeout", 600), env)

    counts = {"CAUGHT": 0, "SURVIVED": 0, "KNOWN": 0, "BROKEN": 0}
    left = []
    backup = save_backup(project, good, baked)
    try:
        # A control for each run the chosen mutants use (not for RUN when none of them does).
        seen = []
        for m, _ in planned:
            key = (m.get("run", run), m.get("env") or {})
            if key not in seen:
                seen.append(key)
        for r, env in seen:
            for i in range(r.get("controls", 1)):
                code, out = go(r, env)
                s = common.scan(out)
                ok = code == 0 and s["script_errors"] == 0 and s["parse_errors"] == 0 and \
                    (r.get("verdict") == "exit" or (s["fail"] == 0 and s["pass"] > 0 and s["startup_errors"] == 0))
                print("control %s%s: exit %s, %s, errors %d, before the first check %d" % (
                    " ".join(r["args"]), " (%d of %d)" % (i + 1, r["controls"]) if "controls" in r else "", code,
                    s["summary"], s["script_errors"] + s["parse_errors"], s["startup_errors"]))
                if not ok:
                    print("the control run on the good code is not green: no mutant is run", s["fails"][:5])
                    return 1
        for m, mutated in planned:
            r = m.get("run", run)
            for f, b in mutated.items():
                (project / f).write_bytes(b)
            if m.get("bake"):
                bcode, bout = common.run_godot(godot, BAKE, project, 300)
                bs = common.scan(bout)
                if bcode != 0 or bs["script_errors"] or bs["parse_errors"]:
                    restore()
                    counts["BROKEN"] += 1
                    print("%-44s BROKEN   the bake failed: exit %s, script errors %d, parse errors %d" % (
                        m["name"][:44], bcode, bs["script_errors"], bs["parse_errors"]))
                    continue
            code, out = go(r, m.get("env"))
            restore()
            s = common.scan(out)
            if code == "timeout" or (s["parse_errors"] and not m.get("parse_ok")):
                verdict = "BROKEN"
            elif m.get("parse_ok") or r.get("verdict") == "exit":
                verdict = "CAUGHT" if code != 0 else "SURVIVED"
            else:
                verdict = "CAUGHT" if s["fail"] or code != 0 else "SURVIVED"
            if verdict == "SURVIVED" and m.get("survives"):
                verdict = "KNOWN"
            counts[verdict] += 1
            if verdict == "CAUGHT":
                why = s["fails"][:3] + (["(caught, though known to survive: %s)" % m["survives"]]
                                        if m.get("survives") else [])
            elif verdict == "KNOWN":
                why = "known to survive: " + m["survives"]
            elif verdict == "BROKEN":
                why = "timeout" if code == "timeout" else "parse errors %d" % s["parse_errors"]
            else:
                why = "every check passed"
            print("%-44s %-8s exit %s, script errors %d: %s" % (m["name"][:44], verdict, code, s["script_errors"],
                                                                [w[:90] for w in why] if isinstance(why, list) else why))
    finally:
        restore()
        left = [f for f, b in good.items() if (project / f).read_bytes() != b]
        if bakes:
            left += [PLACEHOLDERS + "/" + n for n, b in baked.items()
                     if not (project / PLACEHOLDERS / n).exists() or (project / PLACEHOLDERS / n).read_bytes() != b]
        if not left:
            shutil.rmtree(backup, ignore_errors=True)
        print("restored by bytes: %s" % ("all" if not left else "NOT " + ", ".join(left) +
                                         " (the good bytes are in %s)" % backup))
    print("caught %d of %d (survived %d, known survivors %d, broken %d)" % (
        counts["CAUGHT"], len(planned), counts["SURVIVED"], counts["KNOWN"], counts["BROKEN"]))
    return counts["SURVIVED"] + counts["BROKEN"] + len(left)


if __name__ == "__main__":
    sys.exit(main())
