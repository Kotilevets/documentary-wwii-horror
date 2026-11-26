"""The three test runs (docs/ARCHITECTURE.md, "Проверка"): units, the flow through the game, the playthrough bots.
A run is green only when it ends by itself with 0, prints its summary, nothing in it printed a script or parse
error, and no error was logged before its first check (tests/run_guard.gd counts errors inside Godot from the
moment its scene is ready; this is the check from outside - for errors before that, and for a runner that does
not load at all). Each run has a time limit: a hung run is red, not waited for forever.

    python -I tools/checks/run_suites.py                    # the three runs in this project
    python -I tools/checks/run_suites.py --suites units     # one of them
    python -I tools/checks/run_suites.py --fresh            # as after a clone: HEAD exported into an empty
                                                            # folder, imported, then the three runs there
With --fresh the runs keep their user data (user://) in the temporary folder too: APPDATA, XDG_DATA_HOME and
XDG_CONFIG_HOME point into it (checked on Windows; macOS may keep its own place).
Exit code = the number of red steps. Logs go to --logs (default: a new temporary folder, printed at the end)."""
import argparse
import io
import pathlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import common  # noqa: E402

SUITES = {
    "units": (["res://tests/test_runner.tscn"], 2400),
    "flow": (["res://tests/flow_runner.tscn"], 900),
    "playthrough": (["res://tests/playthrough_runner.tscn"], 3600),
}


def export_head(project: pathlib.Path, into: pathlib.Path) -> int:
    """HEAD as a stranger gets it from GitHub: only the committed files, with their committed line endings."""
    tar = subprocess.run(["git", "-C", str(project), "archive", "--format=tar", "HEAD"], capture_output=True,
                         check=True).stdout
    with tarfile.open(fileobj=io.BytesIO(tar)) as t:
        if hasattr(tarfile, "data_filter"):  # Python 3.12, 3.11.4+, 3.10.12+
            t.extractall(into, filter="data")
        else:
            t.extractall(into)
    return sum(1 for p in into.rglob("*") if p.is_file())


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    common.common_args(ap)
    ap.add_argument("--suites", default="units,flow,playthrough", help="comma-separated: units, flow, playthrough")
    ap.add_argument("--fresh", action="store_true", help="export HEAD into an empty folder and import it first")
    ap.add_argument("--keep", action="store_true", help="(with --fresh) keep the exported folder")
    ap.add_argument("--logs", type=pathlib.Path, help="folder for the logs (default: a new temporary one)")
    a = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8", line_buffering=True)
    godot = common.godot_path(a.godot)
    project = a.project.resolve()
    logs = a.logs or pathlib.Path(tempfile.mkdtemp(prefix="wwii-checks-"))
    logs.mkdir(parents=True, exist_ok=True)
    names = [s for s in a.suites.split(",") if s]
    unknown = set(names) - set(SUITES)
    if unknown:
        sys.exit("unknown suite: %s" % ", ".join(sorted(unknown)))
    red = 0
    steps = []
    work = project
    env = None
    tmp = None
    try:
        if a.fresh:
            tmp = pathlib.Path(tempfile.mkdtemp(prefix="wwii-fresh-"))
            work = tmp / "project"
            work.mkdir()
            n = export_head(project, work)
            print("exported HEAD: %d files into %s" % (n, work))
            user = tmp / "user"
            user.mkdir()
            env = {"APPDATA": str(user), "XDG_DATA_HOME": str(user / "data"), "XDG_CONFIG_HOME": str(user / "config")}
            steps.append(("import", ["--headless", "--path", ".", "--import"], 900))
        steps += [(s, ["--headless", "--path", "."] + SUITES[s][0], SUITES[s][1]) for s in names]
        for name, args, limit in steps:
            t0 = time.time()
            code, out = common.run_godot(godot, args, work, limit, env)
            (logs / (name + ".log")).write_text(out, encoding="utf-8", newline="\n")
            s = common.scan(out)
            if name == "import":
                ok = code == 0 and s["parse_errors"] == 0
            else:
                ok = common.green(code, s)
            red += not ok
            print("== %-12s %s  exit %s in %d s; %s; script errors %d, parse errors %d, errors before the first "
                  "check %d" % (name, "green" if ok else "RED  ", code, time.time() - t0, s["summary"],
                                s["script_errors"], s["parse_errors"], s["startup_errors"]))
            for f in s["fails"][:12]:
                print("     FAIL " + f[:160])
        if tmp is not None:
            kept = sorted(p.relative_to(tmp).as_posix() for p in (tmp / "user").rglob("*.json"))
            print("user data of the runs: %s" % (", ".join(kept) or "none"))
    finally:
        if tmp is not None and not a.keep:
            shutil.rmtree(tmp, ignore_errors=True)
    print("logs: %s" % logs)
    print("%s: %d red of %d" % ("ALL GREEN" if not red else "RED", red, len(steps)))
    return red


if __name__ == "__main__":
    sys.exit(main())
