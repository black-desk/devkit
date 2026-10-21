import importlib.metadata
import pathlib
import tempfile

import google.auth
import google_auth_oauthlib.flow
import googleapiclient.discovery
import lieer.gmailieer
import lieer.local
import notmuch2

assert importlib.metadata.version("lieer") == "1.6"
assert importlib.metadata.version("notmuch2") == "0.39"
with tempfile.TemporaryDirectory() as directory:
    root = pathlib.Path(directory)
    message = root / "message.eml"
    message.write_text(
        "From: sender@example.invalid\n"
        "To: devkit@example.invalid\n"
        "Subject: devkit binding probe\n"
        "Message-ID: <lieer-probe@example.invalid>\n\nLocal message.\n"
    )
    with notmuch2.Database.create(path=root) as database:
        database.add(message)
        assert database.count_messages("subject:binding") == 1
        found = database.find("lieer-probe@example.invalid")
        found.tags.add("devkit")
        assert database.count_messages("tag:devkit") == 1
print("lieer imports and notmuch2 database operations: OK")
