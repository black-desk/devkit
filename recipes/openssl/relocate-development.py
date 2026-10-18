"""Match OpenSSL's generated header paths to its versioned header directory."""

import os
from pathlib import Path

prefix = Path(os.environ["PREFIX"])
config = prefix / "lib/devkit/lib/cmake/OpenSSL/OpenSSLConfig.cmake"
text = config.read_text()
assert '"${_ossl_prefix}/include"' in text
config.write_text(
    text.replace(
        '"${_ossl_prefix}/include"',
        '"${_ossl_prefix}/lib/devkit/include/openssl-3.5.9"',
    )
)
for name in ("openssl", "libcrypto", "libssl"):
    path = prefix / "lib/devkit/lib/pkgconfig" / (name + ".pc")
    text = path.read_text()
    # openssl.pc itself can omit includedir; preserve its generated dependency list.
    text = text.replace(
        "includedir=${prefix}/include",
        "includedir=${prefix}/lib/devkit/include/openssl-3.5.9",
    )
    path.write_text(text)
