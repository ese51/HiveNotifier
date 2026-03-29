#!/usr/bin/env sh
#
# lib/quiet_mode.sh
#
# Quiet-mode guard for agent-notify.
# Source this file, then call agent_notify_quiet_mode_check before dispatching
# to any backend.
#
# Return codes from agent_notify_quiet_mode_check:
#   0  Suppress — quiet mode is active for this focus name
#   1  Proceed  — quiet mode off, or focus name overrides suppression
#   2  Error    — HiveMind unreachable; proceed (fail-open)
#
# Output variables set by agent_notify_quiet_mode_check:
#   _QM_SEND_SUMMARY   "1" if focus just transitioned OFF and a summary exists
#   _QM_SUMMARY_MSG    human-readable suppression summary (may be empty)
#
# Configuration (via .env or environment):
#   HIVEMIND_BASE_URL              Base URL of HiveMind.  Default: http://localhost:8000
#                                  Set to "" to skip the check silently.
#   HIVEMIND_API_SECRET            X-Jarvis-Api-Secret header value (optional).
#   AGENT_NOTIFY_QUIET_MODE_CHECK  Set to "0" to disable the check entirely.
#
# Focus-aware policy:
#   focus_name = "Work"                      → always allow (even if enabled=true)
#   focus_name = "Sleep" / "Sleep Mode"
#               / "Do Not Disturb"          → suppress when enabled=true
#   focus_name = anything else               → allow (default behavior)
#
# State files (cleaned up externally when no longer needed):
#   _QM_STATE_FILE      previous quiet-mode state (transition detection)
#   _QM_SUPPRESSED_FILE log of notifications suppressed during current Focus session

_QM_STATE_FILE="${TMPDIR:-/tmp}/hivenotifier_state.json"
_QM_SUPPRESSED_FILE="${TMPDIR:-/tmp}/hivenotifier_suppressed.json"
_QM_SEND_SUMMARY=0
_QM_SUMMARY_MSG=""

# ---------------------------------------------------------------------------
# Internal: parse enabled + focus_name from the HiveMind JSON response.
# Sets _qm_enabled ("true"/"false") and _qm_focus_name (raw string).
# ---------------------------------------------------------------------------
_qm_parse_response() {
  _qm_pr_json="${1:-}"

  if command -v python3 >/dev/null 2>&1; then
    _qm_pr_out="$(QM_JSON="$_qm_pr_json" python3 <<'PYEOF' 2>/dev/null
import json, os
try:
    d = json.loads(os.environ.get('QM_JSON', '{}'))
    qm = d.get('quiet_mode', {})
    print('true' if qm.get('enabled') else 'false')
    print(qm.get('focus_name', '') or '')
except Exception:
    print('false')
    print('')
PYEOF
)"
    _qm_enabled="$(printf '%s' "$_qm_pr_out" | head -1)"
    _qm_focus_name="$(printf '%s' "$_qm_pr_out" | sed -n '2p')"
  else
    # Fallback: grep for enabled boolean; focus_name unavailable without Python
    _qm_enabled="$(printf '%s' "$_qm_pr_json" \
      | grep -o '"enabled"[[:space:]]*:[[:space:]]*[a-z]*' \
      | grep -o 'true\|false' \
      | head -1)"
    _qm_focus_name=""
  fi

  case "$_qm_enabled" in
    true|false) ;;
    *) _qm_enabled="false" ;;
  esac
}

# ---------------------------------------------------------------------------
# Internal: lowercase + trim whitespace
# ---------------------------------------------------------------------------
_qm_normalize() {
  printf '%s' "${1:-}" | tr 'A-Z' 'a-z' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# ---------------------------------------------------------------------------
# Internal: focus-aware suppression policy
# Args: $1=enabled ("true"/"false"), $2=focus_name (raw)
# Returns: 0 = suppress, 1 = allow
# ---------------------------------------------------------------------------
_qm_should_suppress() {
  _qm_ss_enabled="${1:-false}"
  _qm_ss_name="$(_qm_normalize "${2:-}")"

  # Focus is off — never suppress
  [ "$_qm_ss_enabled" = "true" ] || return 1

  # Work mode always bypasses quiet mode
  [ "$_qm_ss_name" = "work" ] && return 1

  # Named suppress modes
  case "$_qm_ss_name" in
    sleep|"sleep mode"|"do not disturb")
      return 0
      ;;
    *)
      # Unknown/custom mode with enabled=true → allow (conservative default)
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Internal: load "enabled" boolean from previous state file
# Prints "true" or "false"
# ---------------------------------------------------------------------------
_qm_load_prev_state() {
  [ -f "$_QM_STATE_FILE" ] || { printf 'false'; return 0; }
  command -v python3 >/dev/null 2>&1 || { printf 'false'; return 0; }
  QM_FILE="$_QM_STATE_FILE" python3 <<'PYEOF' 2>/dev/null
import json, os
try:
    d = json.load(open(os.environ['QM_FILE']))
    print('true' if d.get('enabled') else 'false')
except Exception:
    print('false')
PYEOF
}

# ---------------------------------------------------------------------------
# Internal: persist current state for next invocation
# Args: $1=enabled ("true"/"false"), $2=focus_name
# ---------------------------------------------------------------------------
_qm_save_state() {
  command -v python3 >/dev/null 2>&1 || return 0
  QM_ENABLED="${1:-false}" QM_FOCUS="${2:-}" QM_FILE="$_QM_STATE_FILE" \
  python3 <<'PYEOF' 2>/dev/null
import json, os
enabled = os.environ.get('QM_ENABLED', 'false') == 'true'
focus = os.environ.get('QM_FOCUS', '')
with open(os.environ['QM_FILE'], 'w') as f:
    json.dump({'enabled': enabled, 'focus_name': focus}, f)
PYEOF
}

# ---------------------------------------------------------------------------
# Internal: append a suppressed notification to the local log
# Args: $1=source (tool name), $2=title
# ---------------------------------------------------------------------------
_qm_record_suppressed() {
  command -v python3 >/dev/null 2>&1 || return 0
  QM_SOURCE="${1:-}" QM_TITLE="${2:-}" QM_FILE="$_QM_SUPPRESSED_FILE" \
  python3 <<'PYEOF' 2>/dev/null
import json, os
from datetime import datetime, timezone
src   = os.environ.get('QM_SOURCE', '')
title = os.environ.get('QM_TITLE', '')
f     = os.environ['QM_FILE']
try:
    data = json.load(open(f))
except Exception:
    data = []
data.append({
    'ts':     datetime.now(timezone.utc).isoformat(),
    'source': src,
    'title':  title,
})
with open(f, 'w') as fp:
    json.dump(data, fp)
PYEOF
}

# ---------------------------------------------------------------------------
# Internal: build a human-readable suppression summary from the local log
# Prints the summary string, or nothing if the log is empty/missing
# ---------------------------------------------------------------------------
_qm_build_summary() {
  command -v python3 >/dev/null 2>&1 || { printf ''; return 0; }
  [ -f "$_QM_SUPPRESSED_FILE" ]     || { printf ''; return 0; }
  QM_FILE="$_QM_SUPPRESSED_FILE" python3 <<'PYEOF' 2>/dev/null
import json, os, sys
from collections import Counter
try:
    data = json.load(open(os.environ['QM_FILE']))
except Exception:
    data = []
if not data:
    sys.exit(0)
total   = len(data)
sources = Counter(d.get('source', '') for d in data if d.get('source'))
noun    = 'notification' if total == 1 else 'notifications'
lines   = ['You had {} {} while Focus was on:'.format(total, noun)]
for src, cnt in sorted(sources.items(), key=lambda x: -x[1]):
    if src:
        lines.append('- {} from {}'.format(cnt, src))
if not sources:
    lines.append('(source unknown)')
print('\n'.join(lines))
PYEOF
}

# ---------------------------------------------------------------------------
# Internal: clear the suppression log
# ---------------------------------------------------------------------------
_qm_clear_suppressed() {
  rm -f "$_QM_SUPPRESSED_FILE" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Public: agent_notify_quiet_mode_check
# ---------------------------------------------------------------------------
agent_notify_quiet_mode_check() {
  # Reset output variables
  _QM_SEND_SUMMARY=0
  _QM_SUMMARY_MSG=""

  # Allow complete opt-out
  if [ "${AGENT_NOTIFY_QUIET_MODE_CHECK:-1}" = "0" ]; then
    return 1
  fi

  # ${VAR-default}: empty string means "no HiveMind", not "use default"
  _qm_base_url="${HIVEMIND_BASE_URL-http://localhost:8000}"
  if [ -z "$_qm_base_url" ]; then
    return 1
  fi

  _qm_endpoint="${_qm_base_url}/api/jarvis/quiet-mode"
  _qm_secret="${HIVEMIND_API_SECRET:-}"

  if ! command -v curl >/dev/null 2>&1; then
    printf 'agent-notify: quiet-mode check skipped (curl not available) — proceeding\n' >&2
    return 2
  fi

  # Fetch current quiet-mode state from HiveMind
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

  # Parse current state
  _qm_parse_response "$_qm_response"
  # _qm_enabled and _qm_focus_name are now set

  # --- Transition detection: focus was ON, is now OFF → schedule summary ---
  _qm_prev_enabled="$(_qm_load_prev_state)"
  if [ "$_qm_prev_enabled" = "true" ] && [ "$_qm_enabled" = "false" ]; then
    _qm_built="$(_qm_build_summary)"
    if [ -n "$_qm_built" ]; then
      _QM_SEND_SUMMARY=1
      _QM_SUMMARY_MSG="$_qm_built"
    fi
    _qm_clear_suppressed
  fi

  # Persist new state for next invocation
  _qm_save_state "$_qm_enabled" "$_qm_focus_name"

  # --- Focus-aware policy ---
  if _qm_should_suppress "$_qm_enabled" "$_qm_focus_name"; then
    # Record the suppression (tool/title come from bin/agent-notify scope)
    _qm_record_suppressed "${tool:-}" "${title:-}"
    return 0
  fi

  return 1
}

# ---------------------------------------------------------------------------
# GAP: pending_suppressed_count updates
# ---------------------------------------------------------------------------
# HiveMind exposes no external API for HiveNotifier to increment
# pending_suppressed_count.  Its record_suppressed() method is called
# internally by JarvisHeartbeatNotifier only.  Until HiveMind adds a
#   POST /api/jarvis/quiet-mode/suppress
# endpoint, suppression events are tracked locally in
# $_QM_SUPPRESSED_FILE only, and pending_suppressed_count in
# GET /api/jarvis/quiet-mode will not reflect HiveNotifier suppressions.
