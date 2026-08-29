#!/usr/bin/env python3
"""PermissionRequest hook: asks NotchDrop, falls back to the terminal prompt."""

import json
import os
import subprocess
import sys
import time

INBOX = os.path.expanduser("~/Documents/NotchDrop/ClaudeEvents")

# Must stay below the hook timeout configured in settings.json.
WAIT_SECONDS = 45
POLL_SECONDS = 0.2

# Fields worth showing, in the order they best describe a call.
DETAIL_KEYS = ("command", "file_path", "url", "pattern", "path", "prompt", "query")


def decide(decision, reason=""):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PermissionRequest",
            "decision": decision,
            "decisionReason": reason,
        }
    }))


def app_running():
    try:
        return subprocess.run(
            ["pgrep", "-f", "NotchDrop.app"], capture_output=True
        ).returncode == 0
    except Exception:
        return False


def summarize(tool_input):
    if not isinstance(tool_input, dict):
        return ""
    for key in DETAIL_KEYS:
        value = tool_input.get(key)
        if isinstance(value, str) and value.strip():
            return value[:1000]
    try:
        return json.dumps(tool_input)[:1000]
    except Exception:
        return ""


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        decide("ask", "Hook could not read its input")
        return

    # With no app there is nobody to answer, so never stall the terminal.
    if not app_running():
        decide("ask", "NotchDrop is not running")
        return

    request_id = data.get("tool_use_id") or str(int(time.time() * 1000))
    os.makedirs(INBOX, exist_ok=True)

    payload = {
        "id": request_id,
        "cwd": data.get("cwd", ""),
        "tool_name": data.get("tool_name", ""),
        "detail": summarize(data.get("tool_input")),
        "date": time.time(),
    }
    request_path = os.path.join(INBOX, "request-%s.json" % request_id)
    tmp = request_path + ".tmp"
    with open(tmp, "w") as handle:
        json.dump(payload, handle)
    os.replace(tmp, request_path)

    response_path = os.path.join(INBOX, "response-%s.json" % request_id)
    deadline = time.time() + WAIT_SECONDS
    decision = "ask"

    while time.time() < deadline:
        if os.path.exists(response_path):
            try:
                with open(response_path) as handle:
                    decision = json.load(handle).get("decision", "ask")
            except Exception:
                decision = "ask"
            break
        time.sleep(POLL_SECONDS)

    for path in (request_path, response_path):
        try:
            os.remove(path)
        except OSError:
            pass

    decide(
        decision,
        "Answered from the notch" if decision != "ask"
        else "No answer in time, using the terminal prompt",
    )


main()
