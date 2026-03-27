#!/usr/bin/env sh
#
# backends/sound.sh
#
# Play a local sound notification.
#
# Detects the operating system and uses the most appropriate sound mechanism:
#   macOS         afplay with a built-in system sound
#   Linux         paplay with a freedesktop sound, or terminal bell fallback
#   WSL2          Windows PowerShell beep via powershell.exe
#   Windows       PowerShell beep via powershell.exe (Git Bash / MSYS2 / Cygwin)
#   Other / unknown  Terminal bell (printf '\a')
#
# This backend accepts the standard agent-notify argument set and uses the
# normalized event type to choose which sound to play.
#
# Exit codes:
#   0  Sound played (or bell emitted as fallback)
#   1  Unexpected error before any output was produced

# Consume standard agent-notify arguments so this script is safe to call
# with the full argument set even though it ignores most of them.
event=""
while [ $# -gt 0 ]; do
  case "$1" in
    --event)
      event="$2"
      shift 2
      ;;
    --tool|--message|--title)
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

# ---------------------------------------------------------------------------
# OS detection
# ---------------------------------------------------------------------------
os="$(uname -s 2>/dev/null)"
finish_sound="${AGENT_NOTIFY_SOUND_FINISH:-/System/Library/Sounds/Glass.aiff}"
attention_sound="${AGENT_NOTIFY_SOUND_ATTENTION:-/System/Library/Sounds/Funk.aiff}"

sound_for_event() {
  case "$event" in
    stop|complete|success)
      printf '%s' "$finish_sound"
      ;;
    notification|permission_request|needs_input|warning|error)
      printf '%s' "$attention_sound"
      ;;
    *)
      printf '%s' "$attention_sound"
      ;;
  esac
}

play_sound() {
  case "$os" in
    Darwin)
      # macOS: afplay is always available. Use a calmer sound for completion
      # and a more attention-grabbing sound for anything that needs the user.
      sound_file="$(sound_for_event)"
      if [ -f "$sound_file" ]; then
        afplay "$sound_file"
      else
        printf '\a'
      fi
      ;;
    Linux)
      # Check for WSL (Windows Subsystem for Linux)
      if grep -qi "microsoft" /proc/version 2>/dev/null; then
        # WSL2: delegate to Windows via powershell.exe
        if command -v powershell.exe >/dev/null 2>&1; then
          powershell.exe -NoProfile -NonInteractive -c \
            "[System.Console]::Beep(1000, 300)" 2>/dev/null || printf '\a'
        else
          printf '\a'
        fi
      elif command -v paplay >/dev/null 2>&1; then
        # PulseAudio (common on GNOME/KDE desktops)
        sound_file="/usr/share/sounds/freedesktop/stereo/complete.oga"
        if [ -f "$sound_file" ]; then
          paplay "$sound_file" 2>/dev/null || printf '\a'
        else
          # Try the bell sound as a secondary option
          bell_file="/usr/share/sounds/freedesktop/stereo/bell.oga"
          if [ -f "$bell_file" ]; then
            paplay "$bell_file" 2>/dev/null || printf '\a'
          else
            printf '\a'
          fi
        fi
      elif command -v aplay >/dev/null 2>&1; then
        # ALSA fallback (common on minimal Linux installs)
        printf '\a'
      else
        printf '\a'
      fi
      ;;
    MINGW*|CYGWIN*|MSYS*)
      # Native Windows running via Git Bash, Cygwin, or MSYS2
      if command -v powershell.exe >/dev/null 2>&1; then
        powershell.exe -NoProfile -NonInteractive -c \
          "[System.Console]::Beep(1000, 300)" 2>/dev/null || printf '\a'
      else
        printf '\a'
      fi
      ;;
    *)
      # Unknown OS: use the universal terminal bell
      printf '\a'
      ;;
  esac
}

play_sound
