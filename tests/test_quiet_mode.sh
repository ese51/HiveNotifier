#!/bin/bash
#
# tests/test_quiet_mode.sh
#
# Tests for the quiet-mode guard (lib/quiet_mode.sh).
#
# Run:
#   bash tests/test_quiet_mode.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Source the library under test
# shellcheck source=../lib/quiet_mode.sh
. "$REPO_ROOT/lib/quiet_mode.sh"

# ---------------------------------------------------------------------------
# Redirect state files to a temp directory so tests never touch real state
# ---------------------------------------------------------------------------
_TEST_TMP="$(mktemp -d)"
_QM_STATE_FILE="$_TEST_TMP/state.json"
_QM_SUPPRESSED_FILE="$_TEST_TMP/suppressed.json"
trap 'rm -rf "$_TEST_TMP"' EXIT

# ---------------------------------------------------------------------------
# Test harness
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

_assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf '  PASS  %s\n' "$desc"
    _PASS=$(( _PASS + 1 ))
  else
    printf '  FAIL  %s\n         expected: %s\n         actual:   %s\n' \
      "$desc" "$expected" "$actual"
    _FAIL=$(( _FAIL + 1 ))
  fi
}

_assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    printf '  PASS  %s\n' "$desc"
    _PASS=$(( _PASS + 1 ))
  else
    printf '  FAIL  %s\n         expected to contain: %s\n         actual: %s\n' \
      "$desc" "$needle" "$haystack"
    _FAIL=$(( _FAIL + 1 ))
  fi
}

# Reset per-test state
_reset() {
  rm -f "$_QM_STATE_FILE" "$_QM_SUPPRESSED_FILE"
  unset -f curl 2>/dev/null || true
  HIVEMIND_BASE_URL="http://localhost:8000"
  HIVEMIND_API_SECRET=""
  AGENT_NOTIFY_QUIET_MODE_CHECK="1"
  tool=""
  title=""
  _QM_SEND_SUMMARY=0
  _QM_SUMMARY_MSG=""
}

# Count entries in the suppressed JSON file
_suppressed_count() {
  [ -f "$_QM_SUPPRESSED_FILE" ] || { printf '0'; return; }
  python3 -c "import json; print(len(json.load(open('$_QM_SUPPRESSED_FILE'))))" 2>/dev/null || printf '0'
}

# ---------------------------------------------------------------------------
# ── Policy tests ──────────────────────────────────────────────────────────
# ---------------------------------------------------------------------------

# 1. Quiet mode OFF (focus_name=Off) → send
test_quiet_mode_off_sends() {
  _reset
  curl() {
    printf '{"quiet_mode":{"enabled":false,"source":"hivefocus","focus_name":"Off","started_at":null,"updated_at":null,"expires_at":null,"pending_suppressed_count":0}}'
    return 0
  }
  local rc=0; agent_notify_quiet_mode_check || rc=$?
  _assert_rc "quiet_mode=off → sends (rc=1)" "1" "$rc"
}

# 2. Sleep focus → suppress
test_sleep_focus_suppresses() {
  _reset
  curl() {
    printf '{"quiet_mode":{"enabled":true,"source":"hivefocus","focus_name":"Sleep","started_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z","expires_at":null,"pending_suppressed_count":0}}'
    return 0
  }
  local rc=0; agent_notify_quiet_mode_check || rc=$?
  _assert_rc "Sleep focus → suppressed (rc=0)" "0" "$rc"
}

# 3. "Sleep Mode" (with variant casing) → suppress
test_sleep_mode_focus_suppresses() {
  _reset
  curl() {
    printf '{"quiet_mode":{"enabled":true,"source":"hivefocus","focus_name":"Sleep Mode","started_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z","expires_at":null,"pending_suppressed_count":0}}'
    return 0
  }
  local rc=0; agent_notify_quiet_mode_check || rc=$?
  _assert_rc "Sleep Mode focus → suppressed (rc=0)" "0" "$rc"
}

# 4. "Do Not Disturb" → suppress
test_dnd_focus_suppresses() {
  _reset
  curl() {
    printf '{"quiet_mode":{"enabled":true,"source":"hivefocus","focus_name":"Do Not Disturb","started_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z","expires_at":null,"pending_suppressed_count":0}}'
    return 0
  }
  local rc=0; agent_notify_quiet_mode_check || rc=$?
  _assert_rc "Do Not Disturb → suppressed (rc=0)" "0" "$rc"
}

# 5. "Work" focus + enabled=true → ALLOW (bypass suppression)
test_work_focus_allows() {
  _reset
  curl() {
    printf '{"quiet_mode":{"enabled":true,"source":"hivefocus","focus_name":"Work","started_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z","expires_at":null,"pending_suppressed_count":0}}'
    return 0
  }
  local rc=0; agent_notify_quiet_mode_check || rc=$?
  _assert_rc "Work focus (enabled=true) → allowed (rc=1)" "1" "$rc"
}

# 6. "WORK" (uppercase) → ALLOW (case-insensitive)
test_work_focus_case_insensitive() {
  _reset
  curl() {
    printf '{"quiet_mode":{"enabled":true,"source":"hivefocus","focus_name":"WORK","started_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z","expires_at":null,"pending_suppressed_count":0}}'
    return 0
  }
  local rc=0; agent_notify_quiet_mode_check || rc=$?
  _assert_rc "WORK (uppercase) → allowed (rc=1)" "1" "$rc"
}

# 7. Unknown custom mode with enabled=true → ALLOW (conservative default)
test_unknown_focus_allows() {
  _reset
  curl() {
    printf '{"quiet_mode":{"enabled":true,"source":"hivefocus","focus_name":"Driving","started_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z","expires_at":null,"pending_suppressed_count":0}}'
    return 0
  }
  local rc=0; agent_notify_quiet_mode_check || rc=$?
  _assert_rc "Driving (unknown mode, enabled=true) → allowed (rc=1)" "1" "$rc"
}

# ---------------------------------------------------------------------------
# ── Suppression tracking tests ────────────────────────────────────────────
# ---------------------------------------------------------------------------

# 8. Suppressed notification is recorded in the local log
test_suppressed_notification_logged() {
  _reset
  curl() {
    printf '{"quiet_mode":{"enabled":true,"source":"hivefocus","focus_name":"Sleep Mode","started_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z","expires_at":null,"pending_suppressed_count":0}}'
    return 0
  }
  tool="claude"; title="Claude finished task"
  local rc=0; agent_notify_quiet_mode_check || rc=$?
  _assert_rc "Sleep Mode → suppressed (rc=0)" "0" "$rc"
  _assert_eq "suppressed log has 1 entry" "1" "$(_suppressed_count)"
}

# 9. Multiple suppressions accumulate
test_suppressed_accumulation() {
  _reset
  curl() {
    printf '{"quiet_mode":{"enabled":true,"source":"hivefocus","focus_name":"Do Not Disturb","started_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z","expires_at":null,"pending_suppressed_count":0}}'
    return 0
  }
  tool="claude"; title="Task 1"
  local rc=0; agent_notify_quiet_mode_check || rc=$?
  tool="codex";  title="Task 2"
  agent_notify_quiet_mode_check || true
  _assert_eq "two suppressions → log has 2 entries" "2" "$(_suppressed_count)"
}

# 10. Work focus does NOT add to suppression log
test_work_focus_not_logged() {
  _reset
  curl() {
    printf '{"quiet_mode":{"enabled":true,"source":"hivefocus","focus_name":"Work","started_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z","expires_at":null,"pending_suppressed_count":0}}'
    return 0
  }
  tool="claude"; title="Some task"
  local rc=0; agent_notify_quiet_mode_check || rc=$?
  _assert_rc "Work → allowed (rc=1)" "1" "$rc"
  _assert_eq "Work focus → nothing logged" "0" "$(_suppressed_count)"
}

# ---------------------------------------------------------------------------
# ── Transition / summary tests ────────────────────────────────────────────
# ---------------------------------------------------------------------------

# 11. Focus OFF after ON → _QM_SEND_SUMMARY=1 with count
test_summary_on_focus_off() {
  _reset
  # Seed: was in quiet mode with 3 suppressed notifications
  printf '{"enabled":true,"focus_name":"Sleep Mode"}' > "$_QM_STATE_FILE"
  printf '[{"ts":"2026-01-01T00:00:00+00:00","source":"claude","title":"Task 1"},{"ts":"2026-01-01T00:01:00+00:00","source":"claude","title":"Task 2"},{"ts":"2026-01-01T00:02:00+00:00","source":"codex","title":"Task 3"}]' \
    > "$_QM_SUPPRESSED_FILE"

  curl() {
    printf '{"quiet_mode":{"enabled":false,"source":"hivefocus","focus_name":"Off","started_at":null,"updated_at":null,"expires_at":null,"pending_suppressed_count":0}}'
    return 0
  }
  local rc=0; agent_notify_quiet_mode_check || rc=$?

  _assert_rc  "focus OFF → allows (rc=1)"           "1"  "$rc"
  _assert_eq  "summary flag set"                     "1"  "$_QM_SEND_SUMMARY"
  _assert_contains "summary has total count"         "3 notifications" "$_QM_SUMMARY_MSG"
  _assert_contains "summary groups by claude"        "2 from claude"   "$_QM_SUMMARY_MSG"
  _assert_contains "summary groups by codex"         "1 from codex"    "$_QM_SUMMARY_MSG"
}

# 12. Summary clears the suppressed log
test_summary_clears_suppressed() {
  _reset
  printf '{"enabled":true,"focus_name":"Sleep"}' > "$_QM_STATE_FILE"
  printf '[{"ts":"2026-01-01T00:00:00+00:00","source":"claude","title":"T"}]' \
    > "$_QM_SUPPRESSED_FILE"

  curl() {
    printf '{"quiet_mode":{"enabled":false,"source":"hivefocus","focus_name":"Off","started_at":null,"updated_at":null,"expires_at":null,"pending_suppressed_count":0}}'
    return 0
  }
  agent_notify_quiet_mode_check || true

  _assert_eq "suppressed log cleared after summary" "0" "$(_suppressed_count)"
}

# 13. No summary when log is empty (e.g. Work mode was active the whole time)
test_no_summary_when_log_empty() {
  _reset
  printf '{"enabled":true,"focus_name":"Work"}' > "$_QM_STATE_FILE"
  # suppressed file absent — nothing was actually suppressed

  curl() {
    printf '{"quiet_mode":{"enabled":false,"source":"hivefocus","focus_name":"Off","started_at":null,"updated_at":null,"expires_at":null,"pending_suppressed_count":0}}'
    return 0
  }
  agent_notify_quiet_mode_check || true

  _assert_eq "no summary when log empty" "0" "$_QM_SEND_SUMMARY"
}

# 14. Single notification → singular noun in summary
test_summary_singular_noun() {
  _reset
  printf '{"enabled":true,"focus_name":"Sleep"}' > "$_QM_STATE_FILE"
  printf '[{"ts":"2026-01-01T00:00:00+00:00","source":"claude","title":"One task"}]' \
    > "$_QM_SUPPRESSED_FILE"

  curl() {
    printf '{"quiet_mode":{"enabled":false,"source":"hivefocus","focus_name":"Off","started_at":null,"updated_at":null,"expires_at":null,"pending_suppressed_count":0}}'
    return 0
  }
  agent_notify_quiet_mode_check || true

  _assert_contains "summary uses singular noun" "1 notification while" "$_QM_SUMMARY_MSG"
}

# ---------------------------------------------------------------------------
# ── Failure / skip tests ──────────────────────────────────────────────────
# ---------------------------------------------------------------------------

# 15. HiveMind unreachable → fail-open (rc=2), no summary
test_hivemind_unreachable_fail_open() {
  _reset
  # Seed as if quiet mode was on — summary should NOT fire
  printf '{"enabled":true,"focus_name":"Sleep"}' > "$_QM_STATE_FILE"
  printf '[{"ts":"2026-01-01T00:00:00+00:00","source":"claude","title":"T"}]' \
    > "$_QM_SUPPRESSED_FILE"

  curl() { return 7; }  # CURLE_COULDNT_CONNECT

  local rc=0; agent_notify_quiet_mode_check || rc=$?
  _assert_rc "unreachable → fail-open (rc=2)"  "2" "$rc"
  _assert_eq "unreachable → no summary"         "0" "$_QM_SEND_SUMMARY"
}

# 16. Check disabled via env → skip (rc=1)
test_check_disabled_skips() {
  _reset
  AGENT_NOTIFY_QUIET_MODE_CHECK="0"
  HIVEMIND_BASE_URL="http://should-never-be-called:9999"

  local rc=0; agent_notify_quiet_mode_check || rc=$?
  _assert_rc "check disabled → skipped (rc=1)" "1" "$rc"
}

# 17. Empty HIVEMIND_BASE_URL → skip silently (rc=1)
test_empty_base_url_skips() {
  _reset
  HIVEMIND_BASE_URL=""

  local rc=0; agent_notify_quiet_mode_check || rc=$?
  _assert_rc "empty HIVEMIND_BASE_URL → skipped (rc=1)" "1" "$rc"
}

# 18. curl returns empty body → fail-open (rc=2)
test_empty_response_fail_open() {
  _reset
  curl() { printf ''; return 0; }

  local rc=0; agent_notify_quiet_mode_check || rc=$?
  _assert_rc "empty response → fail-open (rc=2)" "2" "$rc"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------
printf '\nRunning quiet-mode guard tests...\n\n'
printf '── Policy ──────────────────────────────\n'
test_quiet_mode_off_sends
test_sleep_focus_suppresses
test_sleep_mode_focus_suppresses
test_dnd_focus_suppresses
test_work_focus_allows
test_work_focus_case_insensitive
test_unknown_focus_allows

printf '\n── Suppression tracking ────────────────\n'
test_suppressed_notification_logged
test_suppressed_accumulation
test_work_focus_not_logged

printf '\n── Transition / summary ────────────────\n'
test_summary_on_focus_off
test_summary_clears_suppressed
test_no_summary_when_log_empty
test_summary_singular_noun

printf '\n── Failure / skip ──────────────────────\n'
test_hivemind_unreachable_fail_open
test_check_disabled_skips
test_empty_base_url_skips
test_empty_response_fail_open

printf '\n%d passed  %d failed\n' "$_PASS" "$_FAIL"
[ "$_FAIL" -eq 0 ] || exit 1
