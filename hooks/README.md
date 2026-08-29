# Claude Code hooks

These feed the Claude tab in the notch. Copy them to `~/.claude/hooks/`, make
them executable, and register them in `~/.claude/settings.json`:

```json
"hooks": {
  "Stop": [
    { "hooks": [ { "type": "command", "command": "~/.claude/hooks/notch-stop.py", "timeout": 10 } ] }
  ],
  "PermissionRequest": [
    { "hooks": [ { "type": "command", "command": "~/.claude/hooks/notch-permission.py", "timeout": 60 } ] }
  ]
}
```

Use absolute paths, `~` is not expanded there.

The permission hook waits 45 seconds for an answer, which must stay below the
60 second hook timeout. It answers `ask` — the normal terminal prompt — when
the app is not running or when nobody answers in time, so a missing or wedged
app can never approve anything on its own.
