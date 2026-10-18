"""Relocate this recipe's development interfaces after upstream installation."""

import os
from pathlib import Path
import re
import shutil

prefix = Path(os.environ["PREFIX"])
dev = prefix / "lib/devkit"
(dev / "lib").mkdir(parents=True, exist_ok=True)
# Resolve every alias before removing any public linker symlinks.
libraries = [
    path for stem in ["curl"] for path in (prefix / "lib").glob("lib" + stem + ".*")
]
shared = {
    path: path.resolve(strict=True)
    for path in libraries
    if ".so" in path.name and path.is_symlink()
}
for path in libraries:
    target = dev / "lib" / path.name
    if path.name.endswith((".a", ".la")):
        assert not target.exists(), target
        if path.is_symlink():
            original = Path(os.path.abspath(path.parent / path.readlink()))
            if original in libraries:
                original = dev / "lib" / original.name
            target.symlink_to(os.path.relpath(original, target.parent))
            path.unlink()
        else:
            shutil.move(str(path), target)
        if target.suffix == ".la":
            target.write_text(
                re.sub(
                    re.escape(str(prefix)) + r"/lib(?!/devkit)(?=/|['\s])",
                    str(dev) + "/lib",
                    target.read_text(),
                )
            )
    elif ".so" in path.name:
        if path in shared:
            runtime = shared[path]
            target.symlink_to(os.path.relpath(runtime, target.parent))
            if path.name.endswith(".so"):
                path.unlink()
        else:
            with path.open("rb") as stream:
                elf = stream.read(4) == b"\x7fELF"
            if not path.name.endswith(".so"):
                target.symlink_to(os.path.relpath(path, target.parent))
            else:
                assert not elf, ("unreviewed unversioned runtime ELF", path)
                shutil.move(str(path), target)
                target.write_text(
                    target.read_text().replace(
                        str(prefix) + "/lib/", str(dev) + "/lib/"
                    )
                )
import re

# Change only location variables; upstream Libs/Requires retain their generated dependencies.
for name in ["libcurl"]:
    path = prefix / "lib/pkgconfig" / (name + ".pc")
    target = dev / "lib/pkgconfig" / path.name
    target.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file():
        assert not target.exists(), target
        shutil.move(str(path), target)
    assert target.is_file(), target
    text = target.read_text()
    values = {
        "prefix": "${pcfiledir}/../..",
        "exec_prefix": "${prefix}",
        "libdir": "${prefix}/lib",
        "includedir": "${prefix}/include/curl-8.22.0",
    }
    lines = text.splitlines(keepends=True)
    for key, value in values.items():
        matches = [
            i for i, line in enumerate(lines) if re.match(r"^" + key + r"\s*=", line)
        ]
        if matches:
            assert len(matches) == 1, (target, key)
            lines[matches[0]] = key + "=" + value + "\n"
        elif key == "prefix":
            lines.insert(0, key + "=" + value + "\n")
    text = "".join(lines)
    text = text.replace(
        "-Wl,-rpath -Wl," + str(prefix) + "/lib",
        "-Wl,-rpath -Wl,${prefix}/../../lib",
    )
    # Recorded input prefixes become metadata-relative paths, preserving library order.
    text = text.replace(str(prefix) + "/lib/devkit", "${prefix}")
    text = text.replace(str(prefix) + "/lib", "${libdir}")
    text = text.replace(str(prefix) + "/include", "${includedir}")
    target.write_text(text)
# Keep curl-config's generated dependency list; only relocate its query paths.
source = prefix / "bin/curl-config"
path = prefix / "libexec/curl/bin/curl-config"
path.parent.mkdir(parents=True, exist_ok=True)
shutil.move(str(source), path)
text = path.read_text()
text = re.sub(
    r"(?m)^prefix=.*$",
    'prefix="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"',
    text,
    count=1,
)
text = re.sub(r"(?m)^exec_prefix=.*$", 'exec_prefix="${prefix}"', text, count=1)
text = re.sub(
    r"(?m)^includedir=.*$",
    'includedir="${prefix}/lib/devkit/include/curl-8.22.0"',
    text,
    count=1,
)
# Original curl-config embeds libdir at each query site rather than defining a variable.
text = text.replace(
    "-Wl,-rpath -Wl," + str(prefix) + "/lib", "-Wl,-rpath -Wl,${prefix}/lib"
)
text = text.replace(str(prefix) + "/lib/devkit", "${prefix}/lib/devkit")
text = text.replace(str(prefix) + "/lib", "${prefix}/lib/devkit/lib")
text = text.replace(str(prefix), "${prefix}")
# The upstream --ca branch single-quotes the configured literal path.
text = re.sub(
    r"(--ca\)\s*\n\s*)echo .*",
    lambda m: m[1] + 'echo "${prefix}/etc/ssl/certs/ca-certificates.crt"',
    text,
)
text = re.sub(
    r"(--cc\)\s*\n\s*)echo .*",
    lambda m: m[1] + 'echo "${prefix}/bin/clang"',
    text,
)
path.write_text(text)
