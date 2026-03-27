#!/usr/bin/env sh
#
# install/install-codex.sh
#
# Install agent-notify as the notify command in the Codex CLI config.
#
# Codex CLI reads its configuration from ~/.codex/config.toml. This script
# appends a [notify] section with the adapter path if one is not already
# present. It does not modify or remove any existing configuration.
#
# Usage:
#   install-codex.sh [--user | --project]
#
# Options:
#   --user     Install notify into ~/.codex/config.toml (default)
#   --project  Print the example config for manual project-level setup
#
# Environment variables:
#   CODEX_CONFIG_PATH   Override the target config.toml path.
#
# IMPORTANT: Verify the Codex CLI notify configuration format against the
# current Codex documentation at https://github.com/openai/codex before
# relying on this installer. The notify integration point may change across
# Codex versions.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ADAPTER="$REPO_ROOT/adapters/codex.sh"

CODEX_CONFIG="${CODEX_CONFIG_PATH:-$HOME/.codex/config.toml}"
CODEX_DIR="$(dirname "$CODEX_CONFIG")"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
print_usage() {
  printf 'Usage: %s [--user | --project]\n\n' "$0"
  printf 'Options:\n'
  printf '  --user     Install notify in ~/.codex/config.toml (default)\n'
  printf '  --project  Print example config for project-level use\n'
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
  printf 'To configure agent-notify for Codex at the project level, add the\n'
  printf 'following to your project'"'"'s codex config file.\n\n'
  printf 'Example (replace /path/to/agent-notify with your actual repo path):\n\n'
  cat "$REPO_ROOT/examples/codex-config.toml"
  printf '\n\nYour agent-notify repo is at:\n  %s\n' "$REPO_ROOT"
  exit 0
fi

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------
if [ ! -f "$ADAPTER" ]; then
  printf 'install-codex: adapter not found: %s\n' "$ADAPTER" >&2
  printf 'Make sure you are running this from within the agent-notify repo.\n' >&2
  exit 1
fi

mkdir -p "$CODEX_DIR"

if [ ! -f "$CODEX_CONFIG" ]; then
  printf '' > "$CODEX_CONFIG"
  printf 'Created new config file: %s\n' "$CODEX_CONFIG"
fi

printf 'Updating Codex config at: %s\n' "$CODEX_CONFIG"
printf '\n'

# ---------------------------------------------------------------------------
# Check if notify is already configured
# We look for either a bare `notify =` line or a `[notify]` section header.
# ---------------------------------------------------------------------------
if grep -q '^\s*notify\s*=' "$CODEX_CONFIG" 2>/dev/null; then
  printf 'A notify command is already configured in %s\n' "$CODEX_CONFIG"
  printf '\nTo update it, edit the file manually and set:\n'
  printf '  notify = "%s"\n' "$ADAPTER"
  exit 0
fi

if grep -q '^\[notify\]' "$CODEX_CONFIG" 2>/dev/null; then
  printf 'A [notify] section already exists in %s\n' "$CODEX_CONFIG"
  printf '\nTo add a command under it, edit the file manually and add:\n'
  printf '  command = "%s"\n' "$ADAPTER"
  exit 0
fi

# ---------------------------------------------------------------------------
# Append the notify section
# ---------------------------------------------------------------------------
# Add a blank line before the section if the file is non-empty
if [ -s "$CODEX_CONFIG" ]; then
  printf '\n' >> "$CODEX_CONFIG"
fi

cat >> "$CODEX_CONFIG" <<EOF
[notify]
# Run this command when a Codex task completes.
# agent-notify will play a sound and optionally send a push notification.
command = "$ADAPTER"
EOF

printf '  [notify] section added\n'
printf '\nDone. The notify command will be used on the next Codex task.\n'
