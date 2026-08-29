#!/usr/bin/env python3
"""Stop hook: tells NotchDrop that a Claude turn just finished."""

import json
import os
import sys
import time
import uuid

INBOX = os.path.expanduser("~/Documents/NotchDrop/ClaudeEvents")


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return

    os.makedirs(INBOX, exist_ok=True)
    event_id = str(uuid.uuid4())
    message = (data.get("last_assistant_message") or "").strip().replace("\n", " ")

    payload = {
        "id": event_id,
        "cwd": data.get("cwd", ""),
        "tool_name": "",
        "detail": message[:160] or "Turn finished",
        "date": time.time(),
    }

    path = os.path.join(INBOX, "event-%s.json" % event_id)
    tmp = path + ".tmp"
    with open(tmp, "w") as handle:
        json.dump(payload, handle)
    # The watcher polls this folder, so it must never see a half written file.
    os.replace(tmp, path)


main()
