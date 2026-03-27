#!/usr/bin/env sh
#
# adapters/claude.sh
#
# Claude Code hook adapter for agent-notify.
#
# This script is meant to be registered as a Claude Code hook command.
# Claude Code invokes the configured command and pipes a JSON payload to stdin.
# This adapter parses that payload, maps it to normalized arguments, and calls
# bin/agent-notify.
#
# Usage (as a Claude hook command):
#   /path/to/adapters/claude.sh <hook_type>
#
# Where hook_type is one of:
#   stop                 Fired when Claude finishes a task
#   notification         Fired when Claude sends an in-session notification
#   permission_request   Fired when Claude needs user permission before acting
#
# Claude Code hook documentation:
#   https://docs.anthropic.com/en/docs/claude-code/hooks

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
NOTIFY="$REPO_ROOT/bin/agent-notify"

# The hook type is passed as the first argument by the configured command string
hook_type="${1:-stop}"

# ---------------------------------------------------------------------------
# Read the JSON payload from stdin.
# Claude Code pipes JSON to the hook command's stdin. If there is no stdin
# (e.g. running manually for testing), payload remains empty.
# ---------------------------------------------------------------------------
payload=""
if [ ! -t 0 ]; then
  payload="$(cat)"
fi

# ---------------------------------------------------------------------------
# JSON field extraction (no jq dependency)
#
# Prefers Python 3 (standard on macOS 10.15+ and most Linux distros).
# Falls back to a best-effort sed/grep pattern for minimal environments.
# ---------------------------------------------------------------------------
json_str_field() {
  local key="$1"
  local json="$2"

  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$json" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    val = data.get('$key', '')
    if val:
        print(str(val))
except Exception:
    pass
" 2>/dev/null
  else
    # Fallback: extract the first occurrence of \"key\": \"value\"
    # This does not handle escaped quotes or nested objects.
    printf '%s' "$json" \
      | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
      | head -1 \
      | sed 's/.*:[[:space:]]*"\([^"]*\)".*/\1/'
  fi
}

# ---------------------------------------------------------------------------
# Map hook type to title and message
# ---------------------------------------------------------------------------
title=""
message=""

case "$hook_type" in
  stop)
    title="Claude Code"
    message="Task finished"
    ;;
  notification)
    title="Claude Code"
    # Claude sends a "message" field for Notification hooks
    message="$(json_str_field "message" "$payload")"
    if [ -z "$message" ]; then
      message="Notification from Claude"
    fi
    ;;
  permission_request)
    title="Claude Code: Permission Required"
    # Claude sends a "tool_name" field for PermissionRequest hooks
    tool_name="$(json_str_field "tool_name" "$payload")"
    if [ -n "$tool_name" ]; then
      message="Permission requested for: $tool_name"
    else
      message="Claude is requesting permission to continue"
    fi
    ;;
  *)
    title="Claude Code"
    message="Event: $hook_type"
    ;;
esac

# ---------------------------------------------------------------------------
# Dispatch to agent-notify
# ---------------------------------------------------------------------------
exec "$NOTIFY" \
  --tool    "claude" \
  --event   "$hook_type" \
  --title   "$title" \
  --message "$message"
