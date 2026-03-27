#!/usr/bin/env sh
#
# adapters/codex.sh
#
# Codex CLI adapter for agent-notify.
#
# This script is meant to be registered as the Codex notify command.
# When a Codex task completes, Codex runs the configured notify command.
# This adapter reads any available payload and calls bin/agent-notify.
#
# Usage (as a Codex notify command or Stop hook command):
#   /path/to/adapters/codex.sh [event]
#
# Codex CLI configuration:
#   Set the notify command in ~/.codex/config.toml:
#
#     [notify]
#     command = "/path/to/adapters/codex.sh"
#
# Codex CLI documentation:
#   https://github.com/openai/codex
#
# Note: The exact payload format Codex passes to the notify command may vary
# across versions. This adapter reads stdin defensively and tries common field
# names. If Codex passes nothing, a generic completion message is used.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
NOTIFY="$REPO_ROOT/bin/agent-notify"
event="${1:-complete}"

# ---------------------------------------------------------------------------
# Read stdin payload if available.
# Codex may pass JSON describing the completed task.
# ---------------------------------------------------------------------------
payload=""
if [ ! -t 0 ]; then
  payload="$(cat)"
fi

title="Codex"
message="Task finished"

# ---------------------------------------------------------------------------
# Try to extract a human-readable summary from the payload.
# We try several common field names in order of preference.
# ---------------------------------------------------------------------------
if [ -n "$payload" ] && command -v python3 >/dev/null 2>&1; then
  extracted="$(printf '%s' "$payload" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Try common field names for task summary / result text
    for key in ('message', 'summary', 'result', 'text', 'output', 'description'):
        val = data.get(key, '')
        if val and isinstance(val, str):
            # Trim to a reasonable notification length
            print(val[:200])
            break
except Exception:
    pass
" 2>/dev/null)"

  if [ -n "$extracted" ]; then
    message="$extracted"
  fi
fi

# ---------------------------------------------------------------------------
# Dispatch to agent-notify
# ---------------------------------------------------------------------------
exec "$NOTIFY" \
  --tool    "codex" \
  --event   "$event" \
  --title   "$title" \
  --message "$message"
