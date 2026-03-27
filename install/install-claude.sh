#!/usr/bin/env sh
#
# install/install-claude.sh
#
# Install agent-notify hooks into Claude Code settings.
#
# This script adds Stop, Notification, and PermissionRequest hook entries to
# ~/.claude/settings.json. It merges safely -- existing settings are preserved
# and hooks that are already present are skipped rather than duplicated.
#
# Requirements:
#   python3   Used to read, merge, and write the JSON settings file safely.
#             If python3 is not available, the script prints manual instructions.
#
# Usage:
#   install-claude.sh [--user | --project]
#
# Options:
#   --user     Install hooks into ~/.claude/settings.json (default)
#   --project  Print the example hook config for manual project-level setup
#
# Environment variables:
#   CLAUDE_SETTINGS_PATH   Override the target settings.json path.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ADAPTER="$REPO_ROOT/adapters/claude.sh"

CLAUDE_SETTINGS="${CLAUDE_SETTINGS_PATH:-$HOME/.claude/settings.json}"
CLAUDE_DIR="$(dirname "$CLAUDE_SETTINGS")"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
print_usage() {
  printf 'Usage: %s [--user | --project]\n\n' "$0"
  printf 'Options:\n'
  printf '  --user     Install hooks in ~/.claude/settings.json (default)\n'
  printf '  --project  Print example hook config for project-level use\n'
}

mode="user"
case "${1:-}" in
  --project) mode="project" ;;
  --user|"") mode="user" ;;
  -h|--help) print_usage; exit 0 ;;
  *)
    printf 'Unknown option: %s\n' "$1" >&2
    print_usage >&2
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# Project-level: just print the example config
# ---------------------------------------------------------------------------
if [ "$mode" = "project" ]; then
  printf 'To configure agent-notify at the project level, create or update\n'
  printf '.claude/settings.json in your project root.\n\n'
  printf 'Example (replace /path/to/agent-notify with your actual repo path):\n\n'
  cat "$REPO_ROOT/examples/claude-settings.json"
  printf '\n\nYour agent-notify repo is at:\n  %s\n' "$REPO_ROOT"
  exit 0
fi

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------
if [ ! -f "$ADAPTER" ]; then
  printf 'install-claude: adapter not found: %s\n' "$ADAPTER" >&2
  printf 'Make sure you are running this from within the agent-notify repo.\n' >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  printf 'install-claude: python3 is required for automatic install.\n' >&2
  printf '\nPlease add the hooks manually by copying the example config:\n' >&2
  printf '  %s/examples/claude-settings.json\n\n' "$REPO_ROOT" >&2
  printf 'Replace /path/to/agent-notify with:\n  %s\n' "$REPO_ROOT" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Ensure the Claude config directory and settings file exist
# ---------------------------------------------------------------------------
mkdir -p "$CLAUDE_DIR"

if [ ! -f "$CLAUDE_SETTINGS" ]; then
  printf '{}' > "$CLAUDE_SETTINGS"
  printf 'Created new settings file: %s\n' "$CLAUDE_SETTINGS"
fi

printf 'Updating Claude Code settings at: %s\n' "$CLAUDE_SETTINGS"
printf '\n'

# ---------------------------------------------------------------------------
# Merge hooks using Python
# We pass ADAPTER as an argument so there are no shell-quoting issues inside
# the Python heredoc.
# ---------------------------------------------------------------------------
python3 - "$CLAUDE_SETTINGS" "$ADAPTER" <<'PYEOF'
import sys
import json
import os

settings_path = sys.argv[1]
adapter_path  = sys.argv[2]

# Read existing settings
with open(settings_path, 'r') as f:
    try:
        settings = json.load(f)
    except json.JSONDecodeError as e:
        print(f"install-claude: settings.json is not valid JSON: {e}", file=sys.stderr)
        sys.exit(1)

if not isinstance(settings, dict):
    print("install-claude: settings.json root must be a JSON object.", file=sys.stderr)
    sys.exit(1)

if 'hooks' not in settings:
    settings['hooks'] = {}

hooks = settings['hooks']

def make_entry(command):
    """Build a single Claude hook entry."""
    return {
        "matcher": "",
        "hooks": [{"type": "command", "command": command}]
    }

def adapter_already_present(hook_list, adapter_path):
    """Return True if any entry in hook_list references the adapter script."""
    for entry in hook_list:
        for h in entry.get('hooks', []):
            cmd = h.get('command', '')
            # Match on the adapter path to avoid adding duplicates
            if adapter_path in cmd:
                return True
    return False

# Hook type -> argument passed to the adapter
hook_map = [
    ("Stop",              "stop"),
    ("Notification",      "notification"),
    ("PermissionRequest", "permission_request"),
]

for hook_type, arg in hook_map:
    # Quote the adapter path to handle spaces
    command = f'"{adapter_path}" {arg}'

    if hook_type not in hooks:
        hooks[hook_type] = []

    if adapter_already_present(hooks[hook_type], adapter_path):
        print(f"  {hook_type:20s} already configured, skipping")
    else:
        hooks[hook_type].append(make_entry(command))
        print(f"  {hook_type:20s} hook added")

# Write back with consistent formatting
with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')

print(f"\nDone. Restart Claude Code for changes to take effect.")
PYEOF
