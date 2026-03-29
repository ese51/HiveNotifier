#!/bin/bash
#
# tests/test_quiet_mode.sh
#
# Tests for the quiet-mode guard (lib/quiet_mode.sh).
#
# Run:
#   bash tests/test_quiet_mode.sh
#
# Relies on bash (not sh) because:
#   - ${BASH_SOURCE[0]} for reliable self-location
#   - Shell function overriding inside $(…) subshells (bash inherits functions)
#   - local keyword for test-local variables

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Source the library under test
# shellcheck source=../lib/quiet_mode.sh
. "$REPO_ROOT/lib/quiet_mode.sh"

# ---------------------------------------------------------------------------
# Minimal test harness
# ---------------------------------------------------------------------------
_PASS=0
_FAIL=0

_assert_rc() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf '  PASS  %s\n' "$desc"
    _PASS=$(( _PASS + 1 ))
  else
    printf '  FAIL  %s  (expected rc=%s  got rc=%s)\n' "$desc" "$expected" "$actual"
    _FAIL=$(( _FAIL + 1 ))
  fi
}

# Run the check and capture its return code without aborting on non-zero.
# Usage:  rc=0; _check || rc=$?
# (Structured this way so set -e does not fire on non-zero returns.)

# ---------------------------------------------------------------------------
# Test 1: quiet mode OFF → message should send (rc=1)
# ---------------------------------------------------------------------------
test_quiet_mode_off_sends() {
  # Mock curl to return quiet_mode.enabled = false
  curl() {
    printf '{"quiet_mode":{"enabled":false,"source":"hivefocus","focus_name":"Off","started_at":null,"updated_at":null,"expires_at":null,"pending_suppressed_count":0}}'
    return 0
  }
  HIVEMIND_BASE_URL="http://localhost:8000"
  HIVEMIND_API_SECRET=""
  AGENT_NOTIFY_QUIET_MODE_CHECK="1"

  local rc=0; agent_notify_quiet_mode_check || rc=$?
  _assert_rc "quiet_mode=off → sends (rc=1)" "1" "$rc"
  unset -f curl
}

# ---------------------------------------------------------------------------
# Test 2: quiet mode ON → message should be suppressed (rc=0)
# ---------------------------------------------------------------------------
test_quiet_mode_on_suppresses() {
  # Mock curl to return quiet_mode.enabled = true
  curl() {
    printf '{"quiet_mode":{"enabled":true,"source":"hivefocus","focus_name":"Focus","started_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z","expires_at":null,"pending_suppressed_count":0}}'
    return 0
  }
  HIVEMIND_BASE_URL="http://localhost:8000"
  HIVEMIND_API_SECRET=""
  AGENT_NOTIFY_QUIET_MODE_CHECK="1"

  local rc=0; agent_notify_quiet_mode_check || rc=$?
  _assert_rc "quiet_mode=on → suppressed (rc=0)" "0" "$rc"
  unset -f curl
}

# ---------------------------------------------------------------------------
# Test 3: HiveMind unreachable → fail-open, message should send (rc=2)
# ---------------------------------------------------------------------------
test_hivemind_unreachable_fail_open() {
  # Mock curl to simulate a connection failure (curl exit 7 = COULDNT_CONNECT)
  curl() {
    return 7
  }
  HIVEMIND_BASE_URL="http://localhost:8000"
  HIVEMIND_API_SECRET=""
  AGENT_NOTIFY_QUIET_MODE_CHECK="1"

  local rc=0; agent_notify_quiet_mode_check || rc=$?
  _assert_rc "hivemind unreachable → fail-open (rc=2)" "2" "$rc"
  unset -f curl
}

# ---------------------------------------------------------------------------
# Test 4: check disabled via env → skip entirely, message should send (rc=1)
# ---------------------------------------------------------------------------
test_check_disabled_skips() {
  AGENT_NOTIFY_QUIET_MODE_CHECK="0"
  HIVEMIND_BASE_URL="http://should-never-be-called:9999"

  local rc=0; agent_notify_quiet_mode_check || rc=$?
  _assert_rc "check disabled → skipped (rc=1)" "1" "$rc"

  unset AGENT_NOTIFY_QUIET_MODE_CHECK
  unset HIVEMIND_BASE_URL
}

# ---------------------------------------------------------------------------
# Test 5: empty HIVEMIND_BASE_URL → skip silently, message should send (rc=1)
# ---------------------------------------------------------------------------
test_empty_base_url_skips() {
  HIVEMIND_BASE_URL=""
  AGENT_NOTIFY_QUIET_MODE_CHECK="1"

  local rc=0; agent_notify_quiet_mode_check || rc=$?
  _assert_rc "empty HIVEMIND_BASE_URL → skipped (rc=1)" "1" "$rc"

  unset HIVEMIND_BASE_URL
}

# ---------------------------------------------------------------------------
# Test 6: curl returns empty body (timeout/empty response) → fail-open (rc=2)
# ---------------------------------------------------------------------------
test_empty_response_fail_open() {
  curl() {
    printf ''
    return 0
  }
  HIVEMIND_BASE_URL="http://localhost:8000"
  HIVEMIND_API_SECRET=""
  AGENT_NOTIFY_QUIET_MODE_CHECK="1"

  local rc=0; agent_notify_quiet_mode_check || rc=$?
  _assert_rc "empty response → fail-open (rc=2)" "2" "$rc"
  unset -f curl
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
printf '\nRunning quiet-mode guard tests...\n\n'
test_quiet_mode_off_sends
test_quiet_mode_on_suppresses
test_hivemind_unreachable_fail_open
test_check_disabled_skips
test_empty_base_url_skips
test_empty_response_fail_open

printf '\n%d passed  %d failed\n' "$_PASS" "$_FAIL"
[ "$_FAIL" -eq 0 ] || exit 1
