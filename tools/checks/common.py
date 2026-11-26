"""Shared bits of the checks (docs/ARCHITECTURE.md, "Проверка"): where Godot and the project are, how to run
Godot and read what a run printed. Standard library only; paths come from arguments or the environment, never
from one machine."""
import glob
import os
import pathlib
import re
import shutil
import subprocess
import sys

PROJECT = pathlib.Path(__file__).resolve().parents[2]

# Lines a run prints (tests/test_runner.gd, tests/run_guard.gd).
FAIL_LINE = re.compile(r"^FAIL  ", re.M)
PASS_LINE = re.compile(r"^PASS  ", re.M)
SUMMARY = re.compile(r"^(\d+) passed, (\d+) failed", re.M)
PARSE_ERROR = "Parse Error"
SCRIPT_ERROR = "SCRIPT ERROR"
# An error Godot logs ("ERROR: ...", "SCRIPT ERROR: ..."): before the first check, tests/run_guard.gd was not
# listening yet (autoloads, loading the scene).
ERROR_LINE = re.compile(r"^(?:SCRIPT |USER |SHADER )?ERROR: ")


def godot_path(given: str | None = None) -> str:
    """Godot 4.7.2: --godot, else $GODOT, else `godot` on PATH, else the usual install places. A path is made
    absolute: the runs start in the project folder (or a fresh copy of it), not here."""
    for cand in (given, os.environ.get("GODOT")):
        if cand:
            if os.sep in cand or (os.altsep and os.altsep in cand):
                return str(pathlib.Path(cand).resolve())
            return shutil.which(cand) or cand
    for name in ("godot", "godot4", "Godot"):
        found = shutil.which(name)
        if found:
            return found
    patterns = []
    local = os.environ.get("LOCALAPPDATA")
    if local:  # winget
        patterns.append(os.path.join(local, "Microsoft", "WinGet", "Packages", "GodotEngine.GodotEngine_*",
                                     "Godot_v*_console.exe"))
    patterns += ["/Applications/Godot.app/Contents/MacOS/Godot", "/usr/local/bin/godot*", "/usr/bin/godot*"]
    for pat in patterns:
        hits = sorted(glob.glob(pat))
        if hits:
            return hits[-1]
    sys.exit("Godot not found: pass --godot PATH or set GODOT")


def run_godot(godot: str, args: list, project: pathlib.Path, timeout: float, env: dict | None = None) -> tuple:
    """(exit code or "timeout", everything printed). A timeout kills the whole process tree."""
    e = dict(os.environ)
    if env:
        e.update(env)
    proc = subprocess.Popen([godot, *args], cwd=project, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=e)
    try:
        out, _ = proc.communicate(timeout=timeout)
        return proc.returncode, out.decode("utf-8", "replace")
    except subprocess.TimeoutExpired:
        if os.name == "nt":
            subprocess.run(["taskkill", "/F", "/T", "/PID", str(proc.pid)], capture_output=True)
        proc.kill()
        out, _ = proc.communicate()
        return "timeout", out.decode("utf-8", "replace")


def scan(out: str) -> dict:
    """What a run printed: checks passed and failed, the summary line, script and parse errors, and errors logged
    before the first check."""
    m = SUMMARY.findall(out)
    startup = 0
    for line in out.splitlines():
        if line.startswith(("PASS  ", "FAIL  ")):
            break
        startup += bool(ERROR_LINE.match(line))
    return {
        "pass": len(PASS_LINE.findall(out)),
        "fail": len(FAIL_LINE.findall(out)),
        "summary": "%s passed, %s failed" % m[-1] if m else "no summary",
        "script_errors": out.count(SCRIPT_ERROR) - out.count(SCRIPT_ERROR + ": " + PARSE_ERROR),
        "parse_errors": out.count(PARSE_ERROR),
        "startup_errors": startup,
        "fails": [l[6:] for l in out.splitlines() if l.startswith("FAIL  ")],
    }


def green(code, s: dict) -> bool:
    """A run is green only if it ended by itself with 0, printed its summary, and no error of any kind: no script
    or parse error anywhere, no other error before its first check."""
    return code == 0 and s["fail"] == 0 and s["script_errors"] == 0 and s["parse_errors"] == 0 \
        and s["startup_errors"] == 0 and s["summary"] != "no summary"


def common_args(parser) -> None:
    parser.add_argument("--godot", help="the Godot 4.7.2 binary (default: $GODOT, PATH, the usual install places)")
    parser.add_argument("--project", type=pathlib.Path, default=PROJECT, help="the project folder (default: this one)")
