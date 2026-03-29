#!/usr/bin/env sh
#
# lib/quiet_mode.sh
#
# Quiet-mode guard for agent-notify.
# Source this file, then call agent_notify_quiet_mode_check before dispatching
# to any backend.
#
# Return codes:
#   0  Quiet mode is ENABLED  — caller should suppress the notification
#   1  Quiet mode is DISABLED — caller should proceed normally
#   2  Check FAILED           — HiveMind unreachable or unreadable;
#                               caller should proceed normally (fail-open)
#
# Configuration (via .env or environment):
#   HIVEMIND_BASE_URL              Base URL of your HiveMind server.
#                                  Default: http://localhost:8000
#                                  Set to "" to skip the check silently.
#   HIVEMIND_API_SECRET            Value for the X-Jarvis-Api-Secret header.
#                                  Leave empty for unauthenticated local use.
#   AGENT_NOTIFY_QUIET_MODE_CHECK  Set to "0" to disable the check entirely.
#                                  Default: "1" (enabled)
#
# Design notes:
#   • Fail-open: if HiveMind is unreachable the notification is sent, not
#     dropped.  Losing a transient connection to HiveMind should not silence
#     agent alerts.
#   • pending_suppressed_count: HiveMind tracks this internally via its own
#     record_suppressed() service method (called by JarvisHeartbeatNotifier).
#     There is currently no external API endpoint for HiveNotifier to POST
#     suppressed notifications to HiveMind.  Suppression events are therefore
#     logged to stderr only.  See GAP note at end of file.

# ---------------------------------------------------------------------------
# Internal: parse the "enabled" field from HiveMind's quiet-mode JSON.
# Accepts the raw JSON string as $1.
# Prints one of: true / false / parse_error
# ---------------------------------------------------------------------------
_qm_parse_enabled() {
  _qm_raw_json="${1:-}"

  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$_qm_raw_json" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print('true' if d.get('quiet_mode', {}).get('enabled') else 'false')
except Exception:
    print('parse_error')
" 2>/dev/null
  else
    # Fallback: grep for the first "enabled": true|false occurrence.
    # Handles compact and prettified JSON equally.
    printf '%s' "$_qm_raw_json" \
      | grep -o '"enabled"[[:space:]]*:[[:space:]]*[a-z]*' \
      | grep -o 'true\|false' \
      | head -1
  fi
}

# ---------------------------------------------------------------------------
# Public: agent_notify_quiet_mode_check
# ---------------------------------------------------------------------------
agent_notify_quiet_mode_check() {
  # Allow opting out entirely without touching HiveMind at all.
  if [ "${AGENT_NOTIFY_QUIET_MODE_CHECK:-1}" = "0" ]; then
    return 1
  fi

  # Use ${VAR-default} (no colon) so that an explicitly empty HIVEMIND_BASE_URL
  # is treated as "no HiveMind configured" rather than falling back to default.
  _qm_base_url="${HIVEMIND_BASE_URL-http://localhost:8000}"

  # Empty base URL means no HiveMind is configured — skip silently.
  if [ -z "$_qm_base_url" ]; then
    return 1
  fi

  _qm_endpoint="${_qm_base_url}/api/jarvis/quiet-mode"
  _qm_secret="${HIVEMIND_API_SECRET:-}"

  if ! command -v curl >/dev/null 2>&1; then
    printf 'agent-notify: quiet-mode check skipped (curl not available) — proceeding\n' >&2
    return 2
  fi

  # Issue the GET request.  --max-time 3 keeps us from stalling agent hooks.
  if [ -n "$_qm_secret" ]; then
    _qm_response="$(curl -sf --max-time 3 \
      -H "X-Jarvis-Api-Secret: $_qm_secret" \
      "$_qm_endpoint" 2>/dev/null)"
  else
    _qm_response="$(curl -sf --max-time 3 "$_qm_endpoint" 2>/dev/null)"
  fi
  _qm_curl_exit=$?

  if [ "$_qm_curl_exit" -ne 0 ] || [ -z "$_qm_response" ]; then
    printf 'agent-notify: quiet-mode check failed (HiveMind unreachable at %s) — proceeding\n' \
      "$_qm_endpoint" >&2
    return 2
  fi

  _qm_enabled="$(_qm_parse_enabled "$_qm_response")"

  case "$_qm_enabled" in
    true)
      return 0
      ;;
    false)
      return 1
      ;;
    *)
      printf 'agent-notify: quiet-mode response unreadable — proceeding\n' >&2
      return 2
      ;;
  esac
}

# ---------------------------------------------------------------------------
# GAP: pending_suppressed_count updates
# ---------------------------------------------------------------------------
# HiveMind exposes no external API to record suppressed notifications from
# outside processes.  Its record_suppressed() method is called internally by
# JarvisHeartbeatNotifier only.  Until HiveMind adds a
#   POST /api/jarvis/quiet-mode/suppress
# (or equivalent) endpoint, HiveNotifier suppression events are logged to
# stderr and counted locally only.  The pending_suppressed_count shown by
# GET /api/jarvis/quiet-mode will therefore not reflect notifications
# suppressed by HiveNotifier.
