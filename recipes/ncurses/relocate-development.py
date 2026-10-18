"""Adjust consumer metadata where upstream install options are insufficient."""

import os
from pathlib import Path
import re
import shlex
import shutil

prefix = Path(os.environ["PREFIX"])
dev = prefix / "lib/devkit"
# Preserve generated library dependencies while removing build-only compiler/linker flags.

for path in (dev / "lib/pkgconfig").glob("*.pc"):
    if path.stem not in [
        "form",
        "formw",
        "menu",
        "menuw",
        "ncurses++",
        "ncurses++w",
        "ncurses",
        "ncursesw",
        "panel",
        "panelw",
        "tinfo",
        "tinfow",
    ]:
        continue
    text = path.read_text()
    subdir = "ncursesw" if path.stem.endswith("w") else "ncurses"
    text = re.sub(
        r"(?m)^includedir=.*$",
        "includedir=${prefix}/lib/devkit/include/ncurses-6.6/" + subdir,
        text,
    )
    lines = text.splitlines(keepends=True)
    for i, line in enumerate(lines):
        if line.startswith(("Libs:", "Libs.private:", "Cflags:")):
            key, value = line.split(":", 1)
            flags = shlex.split(value)
            allowed = [
                flag
                for flag in flags
                if flag.startswith(("-l", "-L", "-I", "-D", "-U")) or flag == "-pthread"
            ]
            lines[i] = key + ": " + " ".join(allowed) + "\n"
    path.write_text("".join(lines))
for name in ["ncurses6-config", "ncursesw6-config"]:
    source = prefix / "bin" / name
    path = dev / "libexec/ncurses/bin" / name
    path.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(source), path)
    text = path.read_text()
    text = re.sub(
        r"(?m)^prefix=.*$",
        'prefix="$(CDPATH= cd -- "$(dirname -- "$0")/../../../../.." && pwd)"',
        text,
        count=1,
    )
    text = re.sub(r"(?m)^exec_prefix=.*$", 'exec_prefix="${prefix}"', text, count=1)
    # Each native narrow/wide includedir already contains its final subdirectory.
    # The helper otherwise appends CURSES_LIB a second time.
    text = re.sub(
        r"(?m)^(\s*)includesubdir=.*$",
        r'\1includesubdir="${includedir}"',
        text,
    )
    text = text.replace(str(prefix), "${prefix}")
    text = re.sub(r"(?m)^RPATH_LIST=.*$", 'RPATH_LIST="${prefix}/lib/devkit/lib"', text)
    for key in ["CFLAGS", "LIBS"]:

        def clean(match):
            flags = shlex.split(match[1])
            allowed = [
                flag
                for flag in flags
                if flag.startswith(("-l", "-L", "-I", "-D", "-U")) or flag == "-pthread"
            ]
            return key + '="' + " ".join(allowed) + '"'

        text = re.sub(r"(?m)^" + key + r'="(.*)"$', clean, text)
    text = re.sub(
        r"(?m)^for opt in -L\$libdir .*\$LIBS$",
        "for opt in -L$libdir $LIBS",
        text,
    )
    path.write_text(text)
