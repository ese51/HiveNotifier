#!/usr/bin/env sh
#
# backends/pushover.sh
#
# Send a push notification via the Pushover API.
#
# Pushover delivers notifications to iOS and Android. If the user has an Apple
# Watch paired and notification mirroring enabled, it will also appear on the
# watch. No special watch configuration is required.
#
# Required environment variables:
#   PUSHOVER_TOKEN   Your Pushover application API token
#                    Create one at https://pushover.net/apps/build
#   PUSHOVER_USER    Your Pushover user key (shown on your dashboard)
#
# Optional environment variables:
#   PUSHOVER_SOUND   The Pushover sound name to use (default: pushover)
#                    See https://pushover.net/api#sounds for available values
#   PUSHOVER_PRIORITY Notification priority (-2 to 2, default: 0)
#   AGENT_NOTIFY_PUSH_TTL_FINISH
#                    Auto-expire time for finish events in seconds
#                    (default: 120, blank disables ttl)
#   AGENT_NOTIFY_PUSH_TTL_ATTENTION
#                    Auto-expire time for attention events in seconds
#                    (default: 900, blank disables ttl)
#
# If either required variable is missing, this backend exits with code 0 so
# that other backends (e.g. sound) are not blocked.
#
# Exit codes:
#   0  Notification sent, or env vars missing (soft skip)
#   1  curl is not available, or the Pushover API returned an error

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
tool=""
event=""
message=""
title="Agent Notification"

while [ $# -gt 0 ]; do
  case "$1" in
    --tool)    tool="$2";    shift 2 ;;
    --event)   event="$2";   shift 2 ;;
    --message) message="$2"; shift 2 ;;
    --title)   title="$2";   shift 2 ;;
    *)         shift ;;
  esac
done

# ---------------------------------------------------------------------------
# Environment variable checks
# ---------------------------------------------------------------------------
if [ -z "${PUSHOVER_TOKEN:-}" ]; then
  printf 'pushover: PUSHOVER_TOKEN is not set -- skipping push notification\n' >&2
  exit 0
fi

if [ -z "${PUSHOVER_USER:-}" ]; then
  printf 'pushover: PUSHOVER_USER is not set -- skipping push notification\n' >&2
  exit 0
fi

# Require curl
if ! command -v curl >/dev/null 2>&1; then
  printf 'pushover: curl is required but was not found in PATH\n' >&2
  exit 1
fi

# Ensure message is not empty
if [ -z "$message" ]; then
  message="Notification from ${tool:-agent} (${event:-unknown})"
fi

# Optional overrides
pushover_sound="${PUSHOVER_SOUND:-pushover}"
pushover_priority="${PUSHOVER_PRIORITY:-0}"

ttl_for_event() {
  case "$1" in
    stop|complete|success)
      if [ "${AGENT_NOTIFY_PUSH_TTL_FINISH+x}" = "x" ]; then
        printf '%s' "${AGENT_NOTIFY_PUSH_TTL_FINISH}"
      else
        printf '120'
      fi
      ;;
    notification|permission_request|needs_input|warning|error)
      if [ "${AGENT_NOTIFY_PUSH_TTL_ATTENTION+x}" = "x" ]; then
        printf '%s' "${AGENT_NOTIFY_PUSH_TTL_ATTENTION}"
      else
        printf '900'
      fi
      ;;
    *)
      if [ "${AGENT_NOTIFY_PUSH_TTL_ATTENTION+x}" = "x" ]; then
        printf '%s' "${AGENT_NOTIFY_PUSH_TTL_ATTENTION}"
      else
        printf '900'
      fi
      ;;
  esac
}

pushover_ttl="$(ttl_for_event "$event")"

# ---------------------------------------------------------------------------
# Send the notification
# ---------------------------------------------------------------------------
set -- -s \
  --form-string "token=${PUSHOVER_TOKEN}" \
  --form-string "user=${PUSHOVER_USER}" \
  --form-string "title=${title}" \
  --form-string "message=${message}" \
  --form-string "sound=${pushover_sound}" \
  --form-string "priority=${pushover_priority}"

if [ -n "$pushover_ttl" ]; then
  set -- "$@" --form-string "ttl=${pushover_ttl}"
fi

set -- "$@" "https://api.pushover.net/1/messages.json"

response="$(curl "$@" 2>&1)"

# Pushover returns {"status":1,...} on success and {"status":0,...} on failure.
# We parse "status" without jq using a simple grep.
status="$(printf '%s' "$response" \
  | grep -o '"status"[[:space:]]*:[[:space:]]*[0-9]*' \
  | grep -o '[0-9]*$')"

if [ "$status" = "1" ]; then
  printf 'pushover: notification sent\n' >&2
  exit 0
else
  printf 'pushover: API request failed: %s\n' "$response" >&2
  exit 1
fi
