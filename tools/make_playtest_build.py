"""Builds the playtest builds from build/windows/game.pck (docs/playtest/README.md).

    python -I tools/make_playtest_build.py [--date YYYY-MM-DD] [--units N] [--playthrough N] [--flow N]
                                           [--godot PATH] [--macos-zip PATH | --no-mac]
                                           [--linux-zip PATH | --no-linux]

No export templates (a download of about 1.3 GB, the author's decision): the builds run
the official Godot 4.7.2 binaries with the game pack (signed on Windows and macOS). The project's tests run on
the same engine, but on the sources (--path .); the pack is built from them and checked by
loading every scene (docs/playtest/AUTHOR_NOTES.md, section 8).

Windows: the game exe is the official Godot binary under another name, with the pack next
to it under the same name. Godot loads <exe name>.pck from its own folder by itself, so the
tester just double-clicks Игра.exe.

    build/wwii-horror-playtest-<date>/
        Игра.exe             Godot_v4.7.2-stable_win64.exe, renamed
        Игра.pck             build/windows/game.pck
        override.cfg         keeps up to 100 run logs instead of 5; the build stamp for the run log
        ПРОЧТИ.txt           docs/playtest/README_TESTER.md
        АНКЕТА.txt           docs/playtest/QUESTIONNAIRE.md
        Клавиши.txt          docs/playtest/KEYS.md (open only if stuck: question В24)
        Лицензия Godot.txt   the engine's license, its third-party notices and license texts
        ВЕРСИЯ.txt           date, commit, engine and pack sizes and SHA-256, the stamp, test results given
    build/wwii-horror-playtest-<date>.zip

macOS: a file added inside Godot.app breaks Apple's seal on the bundle, so the app is
copied entry by entry, untouched, from the official zip (checked by SHA-256), and a script
starts its binary with --main-pack. Only the zip is written: a folder on Windows would lose
the Unix permissions the script and the binary need.

    build/wwii-horror-playtest-<date>-mac.zip
        wwii-horror-playtest-<date>-mac/
            Запустить игру.command   checks the pack size, runs Godot.app with --main-pack
            ПРОЧТИ.txt, АНКЕТА.txt, Клавиши.txt, Лицензия Godot.txt, ВЕРСИЯ.txt
            Файлы игры/
                Godot.app/           from Godot_v4.7.2-stable_macos.universal.zip
                Игра.pck
                override.cfg         next to the pack: with --main-pack Godot reads it there

Linux (x86_64): as on Windows, the official binary under another name with the pack next
to it under the same name (Godot looks for <name without the extension>.pck in its own
folder), checked by the SHA-256 of the official zip. Only a .tar.gz is written: tar keeps
the Unix permissions (the binary 0755), a folder on Windows would not.

    build/wwii-horror-playtest-<date>-linux.tar.gz
        wwii-horror-playtest-<date>-linux/
            Игра.x86_64          Godot_v4.7.2-stable_linux.x86_64, renamed
            Игра.pck, override.cfg
            ПРОЧТИ.txt, АНКЕТА.txt, Клавиши.txt, Лицензия Godot.txt, ВЕРСИЯ.txt

The tester texts mark the parts for one system with <!-- win --> ... <!-- /win -->,
<!-- mac --> ... <!-- /mac --> and <!-- linux --> ... <!-- /linux --> (on lines of their
own or inside one line); each build keeps its own parts and drops the others'.
{{BUILD_DATE}} and {{PLATFORM}} are filled in.

Builds of the same date are replaced all together (the folder and the archives), only once
every new one is complete; if an old one cannot be moved away (a file in it or an old
archive is open, the game is running), the old ones stay as they were and the unfinished
new ones are removed. Unfinished ones are removed on any other failure too. With --no-mac
or --no-linux the builder stops if an archive of that system of the same date is there: it
would keep the earlier pack and texts. A pack older than the sources (project.godot, export_presets.cfg, src/, assets/) is
not taken: export it again first.

If the pack is missing or cut short, the engine (an editor build) opens the Godot Project
Manager instead of the game: the tester's note says what to do then.
"""
import argparse
import collections
import datetime
import functools
import gzip
import hashlib
import io
import os
import pathlib
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
GODOT_VERSION = "4.7.2"
GODOT_EXE = "Godot_v4.7.2-stable_win64.exe"
GODOT_CONSOLE = "Godot_v4.7.2-stable_win64_console.exe"
GODOT_DESCRIPTION = "Godot Engine"   # the console wrapper says "Godot Engine (Console)"
GODOT_SIGNER = "Prehensile Tales B.V."
WINGET_DIR = pathlib.Path(os.path.expandvars(
    r"%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe"))
SOURCE_URL = "https://github.com/godotengine/godot/tree/4.7.2-stable"
EXE_NAME = "Игра.exe"
PCK_NAME = "Игра.pck"   # on Windows the exe's name with .pck: that is how Godot finds it
MAX_LOGS = 100

# The official zip from the 4.7.2-stable release page on github.com/godotengine/godot
# (downloaded 22.11.2026 with the author's leave) and its SHA-256 as published there.
MAC_ZIP = ROOT / "build" / "godot_macos_4.7.2" / "Godot_v4.7.2-stable_macos.universal.zip"
MAC_ZIP_SHA256 = "c58a24e31d720be9d62f60cb5627c4e695fb72f21b0cfe1bc9ccaa9a3b3ba63e"
MAC_APP = "Godot.app/"
MAC_BINARY = "Godot.app/Contents/MacOS/Godot"
MAC_DIR = "Файлы игры"
MAC_SCRIPT = "Запустить игру.command"
MOLTENVK_URL = "https://github.com/KhronosGroup/MoltenVK"

# The official zip from the same release page (downloaded 23.11.2026 with the author's
# leave) and its SHA-256 as published there; it holds the one binary.
LINUX_ZIP = ROOT / "build" / "godot_linux_4.7.2" / "Godot_v4.7.2-stable_linux.x86_64.zip"
LINUX_ZIP_SHA256 = "cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4"
LINUX_BINARY = "Godot_v4.7.2-stable_linux.x86_64"
LINUX_EXE = "Игра.x86_64"   # Godot loads <this name without .x86_64>.pck from its folder

WIN_LOGS = r"%APPDATA%\Godot\app_userdata\Documentary WWII Horror (working title)\logs"
MAC_LOGS = "~/Library/Application Support/Godot/app_userdata/Documentary WWII Horror (working title)/logs"
LINUX_LOGS = "~/.local/share/godot/app_userdata/Documentary WWII Horror (working title)/logs"

# Read by Godot after the pack's own project settings: from the exe's folder, or, with
# --main-pack, from the pack's folder. ASCII only: testers may open it, and it has to
# parse on any machine.
OVERRIDE = """; Playtest build: keep up to {n} run logs (Godot's default is 5),
; so the log of a crash is not pushed out by the next runs.
; Logs: {logs}
[debug]

file_logging/max_log_files={n}

; Which build this is, for the run log ("game: build"; GameState.build_stamp).
[application]

config/playtest_build="{stamp}"
"""

LICENSE_WIN = """Игра.exe — это официальный движок Godot Engine {ver} (файл {exe}),
переименованный для удобства запуска; саму игру он берёт из файла Игра.pck рядом.
"""
LICENSE_MAC = """«Файлы игры/Godot.app» — это официальный движок Godot Engine {ver} для macOS
(из архива {zip}) без изменений; «Запустить игру.command» запускает его с файлом
игры «Файлы игры/Игра.pck».
"""
LICENSE_LINUX = """Игра.x86_64 — это официальный движок Godot Engine {ver} для Linux
(файл {binary} из архива {zip}),
переименованный для удобства запуска; саму игру он берёт из файла Игра.pck рядом.
"""
LICENSE_COMMON = """
Godot распространяется по лицензии MIT, его сторонние компоненты — по своим лицензиям.
Ниже — текст MIT, список компонентов с их авторскими правами и лицензиями и тексты
этих лицензий в том виде, в каком их выдаёт сам движок {ver}.
Исходный код Godot {ver} и этих компонентов: {src}
"""
LICENSE_MOLTENVK = """
В движок для macOS входит также библиотека MoltenVK (лицензия Apache-2.0, её текст —
ниже, в разделе «License: Apache-2.0»; исходный код и авторские права: {url}).
В списке компонентов, который выдаёт движок, её нет.
"""

# bash 3.2 (what macOS ships), LF, no BOM. Paths are absolute: Godot reads override.cfg
# from the folder of the --main-pack path.
MAC_LAUNCHER = """#!/bin/bash
# Starts the playtest build: the official Godot {ver} for macOS (Godot.app, untouched)
# with the game pack. Written by tools/make_playtest_build.py.
cd "$(dirname "$0")" || exit 1
HERE="$(pwd)"
APP="$HERE/{dir}/Godot.app/Contents/MacOS/Godot"
PCK="$HERE/{dir}/{pck}"
SIZE={size}
if [ ! -x "$APP" ] || [ ! -f "$PCK" ]; then
	echo "Не найдены файлы игры в папке «{dir}»."
	echo "Распакуйте архив заново, целиком, и запустите этот файл из распакованной папки."
	exit 1
fi
# macOS may keep Terminal out of Downloads, Desktop or Documents ("Не разрешать").
if ! HAVE=$( {{ wc -c < "$PCK"; }} 2>/dev/null ); then
	echo "Нет доступа к файлу «{pck}»: macOS не дала Терминалу открыть папку с игрой."
	echo "Перенесите папку игры в свою личную папку (в Finder нажмите Shift + Command + H) и запустите этот файл оттуда."
	exit 1
fi
HAVE=${{HAVE// /}}
if [ "$HAVE" != "$SIZE" ]; then
	echo "Файл «{pck}» повреждён или распакован не полностью: $HAVE байт вместо $SIZE."
	echo "Распакуйте архив заново, целиком."
	exit 1
fi
echo "Игра запускается. Не закрывайте это окно, пока играете: вместе с ним закроется игра."
"$APP" --main-pack "$PCK"
CODE=$?
echo "Игра закрыта (код $CODE). Это окно можно закрыть."
exit $CODE
"""

# build/windows/game.pck as read once at the start: every build is written from these bytes.
Pack = collections.namedtuple("Pack", "path size sha data")
WRITE_FAULT = "%s: what was written is not the pack read at the start (a disk fault?): nothing changed, run again"

INLINE_PART = re.compile(r"<!-- (win|mac|linux) -->(.*?)<!-- /\1 -->")
LINE_PART = re.compile(r"<!-- (/?)(win|mac|linux) -->")


def run(cmd: list, what: str, **kw) -> str:
    """Runs cmd; on a failure shows what it printed instead of dropping it."""
    try:
        r = subprocess.run(cmd, capture_output=True, **kw)
    except subprocess.TimeoutExpired:
        sys.exit("%s did not finish in %s s" % (what, kw.get("timeout")))
    if r.returncode != 0:
        sys.exit("%s failed (exit %d):\n%s" % (what, r.returncode,
                                                (r.stdout + r.stderr).decode("utf-8", "replace")[-3000:]))
    return r.stdout.decode("utf-8", "replace").strip()


def powershell(cmd: str, path: pathlib.Path) -> str:
    return run(["powershell", "-NoProfile", "-Command", cmd], "PowerShell",
               env=dict(os.environ, TARGET=str(path)))


def find_godot(given: str) -> pathlib.Path:
    if given:
        p = pathlib.Path(given)
        if not p.is_file():
            sys.exit("--godot %s: no such file" % given)
        return p
    p = WINGET_DIR / GODOT_EXE
    if p.is_file():
        return p
    w = shutil.which(GODOT_EXE)
    if w:
        return pathlib.Path(w)
    sys.exit("no " + GODOT_EXE + ": pass --godot PATH")


def check_godot(godot: pathlib.Path) -> str:
    """The engine itself (not the console wrapper), version 4.7.2, signed by its publisher."""
    desc, version, status, signer = (powershell(
        "$v = (Get-Item -LiteralPath $env:TARGET).VersionInfo; "
        "$s = Get-AuthenticodeSignature -LiteralPath $env:TARGET; "
        "$n = ''; if ($s.SignerCertificate) { $n = $s.SignerCertificate.GetNameInfo('SimpleName', $false) }; "
        "'{0}|{1}|{2}|{3}' -f $v.FileDescription, $v.FileVersion, $s.Status, $n", godot).split("|") + [""] * 4)[:4]
    if desc != GODOT_DESCRIPTION:
        sys.exit("%s is %r, not %r: pass the engine (%s), not the console wrapper"
                 % (godot, desc, GODOT_DESCRIPTION, GODOT_EXE))
    if version != GODOT_VERSION:
        sys.exit("%s is Godot %s, not %s" % (godot, version, GODOT_VERSION))
    if status != "Valid":
        sys.exit("%s: signature %s - not the official binary?" % (godot, status or "missing"))
    if signer != GODOT_SIGNER:
        sys.exit("%s: signed by %r, not %r" % (godot, signer, GODOT_SIGNER))
    return signer


def license_dump(godot: pathlib.Path) -> str:
    """The license texts from the engine itself, so they always match what is shipped."""
    console = godot.with_name(GODOT_CONSOLE)
    with tempfile.TemporaryDirectory() as tmp:
        dump = pathlib.Path(tmp) / "license.txt"
        run([str(console if console.is_file() else godot), "--headless", "--script",
             str(ROOT / "tools" / "godot_license.gd"), "--", str(dump)],
            "tools/godot_license.gd", cwd=tmp, timeout=120)
        if not dump.is_file():
            sys.exit("tools/godot_license.gd wrote no " + str(dump))
        lic = dump.read_text(encoding="utf-8")
    if "Permission is hereby granted" not in lic or "License: Apache-2.0" not in lic:
        sys.exit("the license dump has no MIT or Apache-2.0 text")
    return lic


def sha(p: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def crlf_bom(s: str) -> bytes:
    return b"\xef\xbb\xbf" + s.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8")


def for_platform(s: str, keep: str, src: pathlib.Path) -> str:
    """Keeps the parts marked for `keep` ("win", "mac" or "linux"), drops the others', and the marks."""
    for n, line in enumerate(s.split("\n"), 1):   # a mistyped mark would reach the tester
        for mark in re.findall(r"<!--.*?(?:-->|$)", line):
            if not LINE_PART.fullmatch(mark):
                sys.exit("%s:%d: unknown mark %s" % (src, n, mark[:40]))
    s = INLINE_PART.sub(lambda m: m.group(2) if m.group(1) == keep else "", s)
    out: list = []
    block = None
    for n, line in enumerate(s.split("\n"), 1):
        m = LINE_PART.fullmatch(line.strip())
        if m:
            closing, mark = m.group(1) == "/", m.group(2)
            if closing != (block is not None) or (closing and mark != block):
                sys.exit("%s:%d: unbalanced %s" % (src, n, line.strip()))
            block = None if closing else mark
            continue
        if block is None or block == keep:
            out.append(line)
    if block is not None:
        sys.exit("%s: <!-- %s --> is not closed" % (src, block))
    s = "\n".join(out)
    if LINE_PART.search(s):
        sys.exit("%s: a mark is left over (a part inside a line must close on that line)" % src)
    if "<!--" in s:
        sys.exit("%s: a mark is left over" % src)
    return s


def tester_text(src: pathlib.Path, keep: str, system: str, shown_date: str) -> bytes:
    s = for_platform(src.read_text(encoding="utf-8").replace("\r\n", "\n"), keep, src)
    s = s.replace("{{BUILD_DATE}}", shown_date).replace("{{PLATFORM}}", system)
    if "{{" in s:
        sys.exit("%s: a placeholder is left: %s" % (src, s[s.index("{{"):][:40]))
    return crlf_bom(s)


@functools.lru_cache(maxsize=None)
def source_commit() -> str:
    """The commit the pack's sources are at, +changes if they differ from it (src, assets, project.godot,
    export_presets.cfg: what the pack is exported from); unknown without git."""
    try:
        head = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--short=7", "HEAD"],
                              capture_output=True, text=True, check=True).stdout.strip()
        changed = subprocess.run(["git", "-C", str(ROOT), "status", "--porcelain", "--", "project.godot",
                                  "export_presets.cfg", "src", "assets"],
                                 capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"
    return head + ("+changes" if changed else "")


def build_stamp(date: str, pck: Pack) -> str:
    """The build's mark in the run log: ASCII, one line, as in ВЕРСИЯ.txt."""
    return "%s commit %s pck %d bytes SHA-256 %s" % (date, source_commit(), pck.size, pck.sha[:12])


def override(logs: str, date: str, pck: Pack) -> bytes:
    return OVERRIDE.format(n=MAX_LOGS, logs=logs, stamp=build_stamp(date, pck)).replace("\n", "\r\n") \
        .encode("ascii")


def remove(p: pathlib.Path) -> None:
    if p.is_dir():
        shutil.rmtree(p)
    elif p.exists():
        p.unlink()


def rename(a: pathlib.Path, b: pathlib.Path) -> None:
    """a.rename(b), tried again for a few seconds: on Windows an antivirus or the search
    indexer may hold a freshly written file for a moment."""
    for _ in range(10):
        try:
            a.rename(b)
            return
        except PermissionError:
            time.sleep(0.5)
    a.rename(b)


def discard(paths) -> None:
    """Removes unfinished outputs, as far as it can."""
    for p in paths:
        try:
            remove(p)
        except OSError:
            pass


def swap_in(pairs: list) -> None:
    """Puts every finished (new, out) in place of its out, all or none. If an old one cannot
    be moved away or a new one put in place, puts back what was moved, removes the
    unfinished new ones and stops: the old builds stay as they were."""
    stale = [o for o in (out.with_name(out.name + ".old") for _n, out in pairs)
             if o.exists() and not o.with_name(o.name[:-len(".old")]).exists()]
    if stale:
        discard(n for n, _o in pairs)
        sys.exit("a run was cut short: %s is the only copy of the old build; rename it back "
                 "(drop .old) and run again" % ", ".join(map(str, stale)))
    moved, placed = [], []
    out = None
    try:
        for new, out in pairs:
            old = out.with_name(out.name + ".old")
            remove(old)
            if out.exists():
                rename(out, old)
                moved.append((out, old))
        for new, out in pairs:
            rename(new, out)
            placed.append((new, out))
    except BaseException as e:   # Ctrl+C while a rename waits is rolled back too
        where, stuck = out, []
        for n, o in reversed(placed):
            try:
                rename(o, n)
            except OSError:
                stuck.append("%s is the new one" % o)
        for o, b in reversed(moved):
            try:
                rename(b, o)
            except OSError:
                stuck.append("the old %s is %s" % (o.name, b))
        discard(n for n, _o in pairs)
        if stuck:
            sys.exit("cannot replace %s: %s\nnot everything is put back, see to it by hand: %s"
                     % (where, e, "; ".join(stuck)))
        if not isinstance(e, OSError):
            raise
        sys.exit("cannot replace %s (is the game running, or a file in it or an old archive open?): %s\n"
                 "nothing changed: close it and run again" % (where, e))
    for _out, old in moved:
        shutil.rmtree(old, ignore_errors=True) if old.is_dir() else old.unlink(missing_ok=True)


def version_lines(head: list, pck: Pack, checks: list, date: str) -> bytes:
    lines = head + ["%s: %d байт, SHA-256 %s" % (PCK_NAME, pck.size, pck.sha)]
    commit = source_commit()
    lines.append("Исходники: коммит %s" % commit.replace("+changes", " и изменения после него")
                 if commit != "unknown" else "Исходники: коммит неизвестен (нет git)")
    lines.append("Метка сборки в журнале игры (game: build): " + build_stamp(date, pck))
    if checks:
        lines.append("Проверено перед сборкой: " + "; ".join(checks))
    return crlf_bom("\n".join(lines) + "\n")


TEXTS = (("README_TESTER.md", "ПРОЧТИ.txt"), ("QUESTIONNAIRE.md", "АНКЕТА.txt"), ("KEYS.md", "Клавиши.txt"))


def build_windows(name: str, date: str, pck: Pack, godot: pathlib.Path, signer: str,
                  lic: str, checks: list, texts: list) -> list:
    """Writes the folder and its zip beside the old ones; returns the (new, final) pairs."""
    out = ROOT / "build" / name
    new = out.with_name(name + ".new")
    remove(new)
    new.mkdir(parents=True)
    shutil.copyfile(godot, new / EXE_NAME)
    (new / PCK_NAME).write_bytes(pck.data)
    if (new / PCK_NAME).stat().st_size != pck.size or sha(new / PCK_NAME) != pck.sha:
        sys.exit(WRITE_FAULT % (new / PCK_NAME))
    (new / "override.cfg").write_bytes(override(WIN_LOGS, date, pck))
    (new / "Лицензия Godot.txt").write_bytes(crlf_bom(
        LICENSE_WIN.format(ver=GODOT_VERSION, exe=GODOT_EXE)
        + LICENSE_COMMON.format(ver=GODOT_VERSION, src=SOURCE_URL) + "\n" + lic))
    for dst, data in texts:
        (new / dst).write_bytes(data)
    (new / "ВЕРСИЯ.txt").write_bytes(version_lines([
        "Тестовая сборка %s для Windows" % date,
        "Запуск: %s — официальный Godot %s (%s, подпись %s), переименованный; игра — в %s рядом"
        % (EXE_NAME, GODOT_VERSION, GODOT_EXE, signer, PCK_NAME),
        "%s: %d байт, SHA-256 %s" % (EXE_NAME, godot.stat().st_size, sha(godot)),
    ], pck, checks, date))

    z = ROOT / "build" / (name + ".zip")
    tmpz = z.with_name(z.name + ".tmp")
    with zipfile.ZipFile(tmpz, "w", zipfile.ZIP_DEFLATED) as f:
        for p in sorted(new.rglob("*")):
            if p.is_file():
                f.write(p, name + "/" + p.relative_to(new).as_posix())
    return [(new, out), (tmpz, z)]


def unix_info(arcname: str, mode: int, date_time: tuple) -> zipfile.ZipInfo:
    """An entry macOS unpacks with these Unix permissions (create_system 3 = Unix)."""
    zi = zipfile.ZipInfo(arcname, date_time)
    zi.create_system = 3
    zi.external_attr = mode << 16
    zi.compress_type = zipfile.ZIP_STORED if arcname.endswith("/") else zipfile.ZIP_DEFLATED
    return zi


def check_mac_zip(mac_zip: pathlib.Path) -> tuple:
    """The official zip: one untouched Godot.app 4.7.2 with an executable binary."""
    if sha(mac_zip) != MAC_ZIP_SHA256:
        sys.exit("%s: SHA-256 is not the published %s" % (mac_zip, MAC_ZIP_SHA256))
    src = zipfile.ZipFile(mac_zip)
    stray = [i.filename for i in src.infolist() if not i.filename.startswith(MAC_APP)]
    if stray:
        sys.exit("%s: entries outside Godot.app: %s" % (mac_zip, stray[:5]))
    binary = src.getinfo(MAC_BINARY)
    if binary.external_attr >> 16 != 0o100755:
        sys.exit("%s: %s mode %o" % (mac_zip, MAC_BINARY, binary.external_attr >> 16))
    plist = plistlib.loads(src.read("Godot.app/Contents/Info.plist"))
    if plist.get("CFBundleShortVersionString") != GODOT_VERSION:
        sys.exit("%s: Godot.app is %s" % (mac_zip, plist.get("CFBundleShortVersionString")))
    h = hashlib.sha256()
    with src.open(binary) as r:
        for block in iter(lambda: r.read(1 << 20), b""):
            h.update(block)
    return src, binary.file_size, h.hexdigest()


def build_mac(name: str, date: str, pck: Pack, mac_zip: pathlib.Path, src: zipfile.ZipFile,
              binary_size: int, binary_sha: str, lic: str, checks: list, texts: list) -> list:
    """Writes the zip beside the old one and reads it back; returns the (new, final) pair."""
    z = ROOT / "build" / (name + ".zip")
    tmpz = z.with_name(z.name + ".tmp")
    now = datetime.datetime.now().timetuple()[:6]
    script = MAC_LAUNCHER.format(ver=GODOT_VERSION, dir=MAC_DIR, pck=PCK_NAME,
                                 size=pck.size).encode("utf-8")
    assert b"\r" not in script
    own = {  # path in the build -> (mode, bytes)
        MAC_SCRIPT: (0o100755, script),
        "Лицензия Godot.txt": (0o100644, crlf_bom(
            LICENSE_MAC.format(ver=GODOT_VERSION, zip=mac_zip.name)
            + LICENSE_COMMON.format(ver=GODOT_VERSION, src=SOURCE_URL)
            + LICENSE_MOLTENVK.format(url=MOLTENVK_URL) + "\n" + lic)),
        "ВЕРСИЯ.txt": (0o100644, version_lines([
            "Тестовая сборка %s для macOS" % date,
            "Запуск: «%s» запускает официальный Godot %s для macOS («%s/Godot.app» из %s, без изменений)"
            " с файлом игры «%s/%s»" % (MAC_SCRIPT, GODOT_VERSION, MAC_DIR, mac_zip.name, MAC_DIR, PCK_NAME),
            "%s: %d байт, SHA-256 %s (совпадает с опубликованным на странице выпуска %s-stable)"
            % (mac_zip.name, mac_zip.stat().st_size, MAC_ZIP_SHA256, GODOT_VERSION),
            "%s: %d байт, SHA-256 %s" % (MAC_BINARY, binary_size, binary_sha),
        ], pck, checks, date)),
        MAC_DIR + "/override.cfg": (0o100644, override(MAC_LOGS, date, pck)),
    }
    for dst, data in texts:
        own[dst] = (0o100644, data)
    top = name + "/"
    app = top + MAC_DIR + "/"
    with zipfile.ZipFile(tmpz, "w", zipfile.ZIP_DEFLATED) as f:
        f.writestr(unix_info(top, 0o40755, now), b"")
        for path in sorted(p for p in own if "/" not in p):
            mode, data = own[path]
            f.writestr(unix_info(top + path, mode, now), data)
        f.writestr(unix_info(app, 0o40755, now), b"")
        zi = unix_info(app + PCK_NAME, 0o100644, now)
        zi.file_size = pck.size
        with f.open(zi, "w") as w:
            w.write(pck.data)
        mode, data = own[MAC_DIR + "/override.cfg"]
        f.writestr(unix_info(app + "override.cfg", mode, now), data)
        # Godot.app as it is: same names, dates and Unix modes (symlinks would stay links,
        # their target being the entry's data); only the folder in front is new.
        for info in src.infolist():
            zi = zipfile.ZipInfo(app + info.filename, info.date_time)
            zi.create_system = 3
            zi.external_attr = info.external_attr
            if info.is_dir():
                zi.compress_type = zipfile.ZIP_STORED
                f.writestr(zi, b"")
                continue
            zi.compress_type = info.compress_type
            zi.file_size = info.file_size
            with src.open(info) as r, f.open(zi, "w") as w:
                shutil.copyfileobj(r, w, 1 << 20)

    # Read it back: every entry whole, Godot.app the same as in the official zip.
    with zipfile.ZipFile(tmpz) as f:
        bad = f.testzip()
        if bad:
            sys.exit("%s: bad CRC in %s" % (tmpz, bad))
        expected = {top, app, app + PCK_NAME} | {top + p for p in own} \
            | {app + i.filename for i in src.infolist()}
        if set(f.namelist()) != expected:
            sys.exit("%s: entries differ: %s" % (tmpz, sorted(set(f.namelist()) ^ expected)[:5]))
        for info in src.infolist():
            c = f.getinfo(app + info.filename)
            if (c.CRC, c.file_size, c.external_attr, c.create_system) != \
                    (info.CRC, info.file_size, info.external_attr, 3):
                sys.exit("%s: %s differs from the official zip" % (tmpz, info.filename))
        for path, (mode, data) in own.items():
            c = f.getinfo(top + path)
            if c.external_attr >> 16 != mode or f.read(c) != data:
                sys.exit("%s: %s is not what was written" % (tmpz, path))
        h = hashlib.sha256()
        with f.open(app + PCK_NAME) as r:
            for block in iter(lambda: r.read(1 << 20), b""):
                h.update(block)
        if f.getinfo(app + PCK_NAME).file_size != pck.size or h.hexdigest() != pck.sha:
            sys.exit(WRITE_FAULT % ("%s: %s" % (tmpz, app + PCK_NAME)))
        links = [i.filename for i in f.infolist() if stat.S_ISLNK(i.external_attr >> 16)]
        print("read back %s: %d entries, symlinks: %d" % (tmpz.name, len(f.infolist()), len(links)))
    return [(tmpz, z)]


def check_linux_zip(linux_zip: pathlib.Path) -> tuple:
    """The official zip: the one Godot 4.7.2 binary, executable, a 64-bit x86-64 ELF."""
    if sha(linux_zip) != LINUX_ZIP_SHA256:
        sys.exit("%s: SHA-256 is not the published %s" % (linux_zip, LINUX_ZIP_SHA256))
    src = zipfile.ZipFile(linux_zip)
    if src.namelist() != [LINUX_BINARY]:
        sys.exit("%s: expected only %s, found %s" % (linux_zip, LINUX_BINARY, src.namelist()[:5]))
    binary = src.getinfo(LINUX_BINARY)
    if binary.external_attr >> 16 != 0o100755:
        sys.exit("%s: %s mode %o" % (linux_zip, LINUX_BINARY, binary.external_attr >> 16))
    h = hashlib.sha256()
    with src.open(binary) as r:
        head = r.read(20)
        if head[:5] != b"\x7fELF\x02" or int.from_bytes(head[18:20], "little") != 62:
            sys.exit("%s: %s is not a 64-bit x86-64 ELF" % (linux_zip, LINUX_BINARY))
        h.update(head)
        for block in iter(lambda: r.read(1 << 20), b""):
            h.update(block)
    return src, binary.file_size, h.hexdigest()


def tar_info(arcname: str, mode: int, size: int, mtime: int) -> tarfile.TarInfo:
    """An entry with these Unix permissions and no owner of note: it unpacks as the user's."""
    ti = tarfile.TarInfo(arcname)
    ti.type = tarfile.DIRTYPE if stat.S_ISDIR(mode) else tarfile.REGTYPE
    ti.mode = stat.S_IMODE(mode)
    ti.size = 0 if ti.type == tarfile.DIRTYPE else size
    ti.mtime = mtime
    ti.uid = ti.gid = 0
    ti.uname = ti.gname = ""
    return ti


def build_linux(name: str, date: str, pck: Pack, linux_zip: pathlib.Path, src: zipfile.ZipFile,
                binary_size: int, binary_sha: str, lic: str, checks: list, texts: list) -> list:
    """Writes the .tar.gz beside the old one and reads it back; returns the (new, final) pair.
    tar keeps the Unix permissions, so the game binary stays executable."""
    t = ROOT / "build" / (name + ".tar.gz")
    tmpt = t.with_name(t.name + ".tmp")
    mtime = int(time.time())
    own = {  # path in the build -> bytes, mode 0644
        "override.cfg": override(LINUX_LOGS, date, pck),
        "Лицензия Godot.txt": crlf_bom(
            LICENSE_LINUX.format(ver=GODOT_VERSION, binary=LINUX_BINARY, zip=linux_zip.name)
            + LICENSE_COMMON.format(ver=GODOT_VERSION, src=SOURCE_URL) + "\n" + lic),
        "ВЕРСИЯ.txt": version_lines([
            "Тестовая сборка %s для Linux" % date,
            "Запуск: %s — официальный Godot %s для Linux (%s из %s), переименованный; игра — в %s рядом"
            % (LINUX_EXE, GODOT_VERSION, LINUX_BINARY, linux_zip.name, PCK_NAME),
            "%s: %d байт, SHA-256 %s (совпадает с опубликованным на странице выпуска %s-stable)"
            % (linux_zip.name, linux_zip.stat().st_size, LINUX_ZIP_SHA256, GODOT_VERSION),
            "%s: %d байт, SHA-256 %s" % (LINUX_EXE, binary_size, binary_sha),
        ], pck, checks, date),
    }
    for dst, data in texts:
        own[dst] = data
    top = name + "/"
    with open(tmpt, "wb") as raw:
        # The name in the gzip header is the archive's own, not the .tmp one.
        with gzip.GzipFile(filename=t.name, mode="wb", fileobj=raw, mtime=mtime) as gz:
            with tarfile.open(fileobj=gz, mode="w", format=tarfile.PAX_FORMAT) as f:
                f.addfile(tar_info(name, 0o40755, 0, mtime))
                with src.open(LINUX_BINARY) as r:
                    f.addfile(tar_info(top + LINUX_EXE, 0o100755, binary_size, mtime), r)
                f.addfile(tar_info(top + PCK_NAME, 0o100644, pck.size, mtime), io.BytesIO(pck.data))
                for path in sorted(own):
                    f.addfile(tar_info(top + path, 0o100644, len(own[path]), mtime), io.BytesIO(own[path]))

    # Read it back: the same names, types and permissions, every file whole.
    want = {name: (tarfile.DIRTYPE, 0o755, None),
            top + LINUX_EXE: (tarfile.REGTYPE, 0o755, (binary_size, binary_sha)),
            top + PCK_NAME: (tarfile.REGTYPE, 0o644, (pck.size, pck.sha))}
    for path in sorted(own):
        want[top + path] = (tarfile.REGTYPE, 0o644, (len(own[path]), hashlib.sha256(own[path]).hexdigest()))
    with tarfile.open(tmpt, "r:gz") as f:
        members = f.getmembers()
        got = {m.name: m for m in members}
        if len(got) != len(members) or set(got) != set(want):
            sys.exit("%s: entries differ: %s" % (tmpt, sorted(set(got) ^ set(want))[:5]))
        for path, (kind, mode, content) in want.items():
            m = got[path]
            if m.type != kind or m.mode != mode:
                sys.exit("%s: %s is type %r mode %o" % (tmpt, path, m.type, m.mode))
            if content:
                h, size = hashlib.sha256(), 0
                r = f.extractfile(m)
                for block in iter(lambda: r.read(1 << 20), b""):
                    h.update(block)
                    size += len(block)
                if (size, h.hexdigest()) != content:
                    sys.exit("%s: %s is not what was written" % (tmpt, path))
        print("read back %s: %d entries" % (tmpt.name, len(members)))
    return [(tmpt, t)]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", default=datetime.date.today().isoformat())
    ap.add_argument("--units", default="")
    ap.add_argument("--playthrough", default="")
    ap.add_argument("--flow", default="")
    ap.add_argument("--godot", default="", help="path to " + GODOT_EXE)
    ap.add_argument("--macos-zip", default=str(MAC_ZIP), help="path to the official Godot macOS zip")
    ap.add_argument("--no-mac", action="store_true", help="build without the Mac archive")
    ap.add_argument("--linux-zip", default=str(LINUX_ZIP), help="path to the official Godot Linux x86_64 zip")
    ap.add_argument("--no-linux", action="store_true", help="build without the Linux archive")
    a = ap.parse_args()

    # Everything that can be checked is checked before anything is written, the tester
    # texts included; all the builds are put in place together (swap_in).
    try:
        build_date = datetime.date.fromisoformat(a.date)
    except ValueError:
        sys.exit("--date %s: expected YYYY-MM-DD" % a.date)
    date = build_date.isoformat()
    shown_date = build_date.strftime("%d.%m.%Y")
    name = "wwii-horror-playtest-" + date
    for left_out, suffix, flag in ((a.no_mac, "-mac.zip", "--no-mac"), (a.no_linux, "-linux.tar.gz", "--no-linux")):
        if left_out and (ROOT / "build" / (name + suffix)).exists():
            sys.exit("build/%s%s of the same date is there, with the previous pack and texts: "
                     "remove it, or build without %s" % (name, suffix, flag))
    pck = ROOT / "build" / "windows" / "game.pck"
    if not pck.is_file():
        sys.exit("no build/windows/game.pck: export the pack first (docs/ARCHITECTURE.md, «Проверка»)")
    skip = ("assets/refs/", "src/scenes/test/")   # left out of the pack by export_presets.cfg
    sources = [ROOT / "project.godot", ROOT / "export_presets.cfg"] + [
        p for d in ("src", "assets") for p in (ROOT / d).rglob("*")
        if p.is_file() and not p.relative_to(ROOT).as_posix().startswith(skip)]
    newest = max(sources, key=lambda p: p.stat().st_mtime)
    if newest.stat().st_mtime > pck.stat().st_mtime:
        sys.exit("build/windows/game.pck is older than %s: export the pack again (docs/playtest/README.md, step 1)"
                 % newest.relative_to(ROOT).as_posix())
    data = pck.read_bytes()   # about 10 MB
    pack = Pack(pck, len(data), hashlib.sha256(data).hexdigest(), data)
    for src, _dst in TEXTS:
        if not (ROOT / "docs" / "playtest" / src).is_file():
            sys.exit("missing docs/playtest/" + src)
    systems = (("win", "Windows"),) + ((("mac", "macOS"),) if not a.no_mac else ()) \
        + ((("linux", "Linux"),) if not a.no_linux else ())
    texts = {keep: [(dst, tester_text(ROOT / "docs" / "playtest" / src, keep, system, shown_date))
                    for src, dst in TEXTS] for keep, system in systems}
    mac = None
    if not a.no_mac:
        mac_zip = pathlib.Path(a.macos_zip)
        if not mac_zip.is_file():
            sys.exit("no %s: the official Godot %s macOS zip (docs/playtest/README.md), or pass --no-mac"
                     % (mac_zip, GODOT_VERSION))
        mac = (mac_zip,) + check_mac_zip(mac_zip)
    linux = None
    if not a.no_linux:
        linux_zip = pathlib.Path(a.linux_zip)
        if not linux_zip.is_file():
            sys.exit("no %s: the official Godot %s Linux x86_64 zip (docs/playtest/README.md), or pass --no-linux"
                     % (linux_zip, GODOT_VERSION))
        linux = (linux_zip,) + check_linux_zip(linux_zip)
    godot = find_godot(a.godot)
    signer = check_godot(godot)
    lic = license_dump(godot)
    checks = [s for s in (("автотесты " + a.units) if a.units else "",
                          ("прогоны ботами " + a.playthrough) if a.playthrough else "",
                          ("сквозной прогон меню → эпилог " + a.flow) if a.flow else "") if s]

    unfinished = [ROOT / "build" / (name + ".new"), ROOT / "build" / (name + ".zip.tmp"),
                  ROOT / "build" / (name + "-mac.zip.tmp"), ROOT / "build" / (name + "-linux.tar.gz.tmp")]
    try:
        pairs = build_windows(name, date, pack, godot, signer, lic, checks, texts["win"])
        if mac:
            pairs += build_mac(name + "-mac", date, pack, mac[0], mac[1], mac[2], mac[3], lic, checks, texts["mac"])
        if linux:
            pairs += build_linux(name + "-linux", date, pack, linux[0], linux[1], linux[2], linux[3], lic, checks,
                                 texts["linux"])
        if (pck.stat().st_size, sha(pck)) != (pack.size, pack.sha):
            sys.exit("build/windows/game.pck changed while the builds were written: nothing changed, run again")
    except BaseException:
        discard(unfinished)
        raise
    swap_in(pairs)
    for _new, out in pairs:
        print(out, "(folder)" if out.is_dir() else out.stat().st_size)


# Only when run: check scripts load this file for tester_text() without starting a build.
if __name__ == "__main__":
    main()
