# agent-notify

A cross-tool notification layer for terminal AI coding agents.

Get a sound on your machine or a push notification on your phone the moment an agent finishes a task, needs your attention, or requests permission -- without polling a terminal window.

---

## Why

Terminal agents like Claude Code and Codex can run for minutes at a time. You step away, lose focus, and miss the moment they stop or ask a question. agent-notify fires a local sound or phone notification as soon as something needs you. It works out of the box with no account required for sound notifications, and supports Pushover for push delivery to your phone or Apple Watch.

---

## Supported tools

| Tool | Events |
|------|--------|
| Claude Code | Stop, Notification, PermissionRequest |
| Codex | Task complete |

---

## Supported notification backends

| Backend | What it does | Requires |
|---------|-------------|----------|
| `sound` | Plays a local sound or terminal bell | Nothing -- works by default |
| `pushover` | Pushes to your phone via [Pushover](https://pushover.net) | Pushover account + env vars |

Both backends are independent. If one fails, the other still runs.

---

## Apple Watch

Apple Watch support works through the Pushover iPhone app. When Pushover delivers a notification to your iPhone, iOS mirrors it to your Apple Watch if notification mirroring is enabled. No separate configuration is needed beyond the Pushover app on your iPhone.

---

## Quick start

```sh
git clone https://github.com/your-username/agent-notify.git
cd agent-notify
chmod +x bin/agent-notify adapters/*.sh backends/*.sh install/*.sh

# Test sound only
./bin/agent-notify --tool test --event test --title "Hello" --message "agent-notify is working"
```

You should hear a sound. If you are on a headless server or muted machine, a terminal bell is emitted as fallback.

---

## Environment variables

Copy `.env.example` to `.env` in the repo root and fill in values:

```sh
cp .env.example .env
```

| Variable | Required | Description |
|----------|----------|-------------|
| `PUSHOVER_TOKEN` | For Pushover only | Your Pushover application API token |
| `PUSHOVER_USER` | For Pushover only | Your Pushover user key |
| `AGENT_NOTIFY_PUSH_TTL_FINISH` | No | Pushover TTL for finish events. Default: `120`. Blank disables ttl for finish events |
| `AGENT_NOTIFY_PUSH_TTL_ATTENTION` | No | Pushover TTL for attention events. Default: `900`. Blank disables ttl for attention events |
| `AGENT_NOTIFY_BACKENDS` | No | Comma-separated backends to run. Default: `sound` |
| `AGENT_NOTIFY_SOUND_FINISH` | No | Override the sound backend's finish sound. macOS default: `/System/Library/Sounds/Glass.aiff` |
| `AGENT_NOTIFY_SOUND_ATTENTION` | No | Override the sound backend's attention sound. macOS default: `/System/Library/Sounds/Funk.aiff` |
| `PUSHOVER_SOUND` | No | Pushover sound name. Default: `pushover` |
| `PUSHOVER_PRIORITY` | No | Pushover priority (-2 to 2). Default: `0` |

`bin/agent-notify` loads `.env` from the repo root automatically if the file exists.

For the built-in `sound` backend, event routing works like this:

- Finish sound: `stop`, `complete`
- Attention sound: `notification`, `permission_request`
- Unknown events: fall back to the attention sound

Example custom sound configuration on macOS:

```sh
AGENT_NOTIFY_SOUND_FINISH=/System/Library/Sounds/Glass.aiff
AGENT_NOTIFY_SOUND_ATTENTION=/System/Library/Sounds/Hero.aiff
```

For the `pushover` backend, ttl is applied by normalized event:

- Finish ttl: `stop`, `complete` -> default `120` seconds
- Attention ttl: `notification`, `permission_request` -> default `900` seconds
- Unknown events fall back to the attention ttl
- If `AGENT_NOTIFY_PUSH_TTL_FINISH` or `AGENT_NOTIFY_PUSH_TTL_ATTENTION` is set to a blank value in `.env`, that ttl is omitted entirely

**Never commit your `.env` file.** It is listed in `.gitignore`.

---

## Installation: Claude Code

### Automatic (recommended)

```sh
./install/install-claude.sh
```

This merges hook entries into `~/.claude/settings.json` without touching any existing settings. Restart Claude Code for the changes to take effect.

### Manual

Run the installer with `--project` to print a config block you can copy into your project-level `.claude/settings.json`:

```sh
./install/install-claude.sh --project
```

Or copy `examples/claude-settings.json` and replace `/path/to/agent-notify` with the absolute path to your repo.

### What gets added

Three hooks are registered:

- **Stop** -- fires when Claude finishes a task
- **Notification** -- fires when Claude sends an in-session notification
- **PermissionRequest** -- fires when Claude needs your permission before acting

Each hook calls `adapters/claude.sh` with the hook type as an argument. The adapter parses Claude's JSON payload and calls `bin/agent-notify`.

---

## Installation: Codex

### Automatic (recommended)

```sh
./install/install-codex.sh
```

This appends a `[notify]` section to `~/.codex/config.toml` if one is not already present.

### Manual

Run the installer with `--project` to print the config block:

```sh
./install/install-codex.sh --project
```

Or copy `examples/codex-config.toml` and replace `/path/to/agent-notify` with the absolute path to your repo.

**Note:** Verify the Codex notify configuration format against the [current Codex documentation](https://github.com/openai/codex) for your version. The `[notify]` key format may differ across releases.

---

## Enabling push notifications (Pushover)

1. Create a free account at [pushover.net](https://pushover.net).
2. Note your **user key** from the dashboard.
3. Create a new application at [pushover.net/apps/build](https://pushover.net/apps/build). Name it `agent-notify` or anything you like. Copy the **API token**.
4. Add both values to your `.env`:

```sh
PUSHOVER_TOKEN=your_application_token
PUSHOVER_USER=your_user_key
AGENT_NOTIFY_BACKENDS=sound,pushover
AGENT_NOTIFY_PUSH_TTL_FINISH=120
AGENT_NOTIFY_PUSH_TTL_ATTENTION=900
```

5. Install the Pushover app on your iPhone or Android device.
6. Test it:

```sh
./bin/agent-notify --tool test --event test --title "Test" --message "Push is working"
```

---

## Architecture

```
bin/agent-notify          Main dispatcher. Reads AGENT_NOTIFY_BACKENDS,
                          runs each backend script in order.

adapters/
  claude.sh               Translates Claude hook stdin JSON into a normalized
                          agent-notify call.
  codex.sh                Translates Codex task completion payload into a
                          normalized agent-notify call.

backends/
  sound.sh                Plays a local sound. Chooses a sound from the
                          normalized event type, then detects macOS / Linux /
                          WSL2 / Windows and uses the right mechanism.
  pushover.sh             Sends a push notification via the Pushover API.

install/
  install-claude.sh       Merges hooks into ~/.claude/settings.json.
  install-codex.sh        Appends notify config to ~/.codex/config.toml.

examples/
  claude-settings.json    Reference hook configuration.
  codex-config.toml       Reference notify configuration.
```

### Normalized payload

Every adapter translates its tool-specific input into the same four fields before calling `bin/agent-notify`:

| Field | Description |
|-------|-------------|
| `--tool` | Source tool (`claude`, `codex`) |
| `--event` | Event type (`stop`, `notification`, `permission_request`, `complete`) |
| `--title` | Short notification title |
| `--message` | Notification body |

Backends only see these four fields. They have no knowledge of which tool fired the event.

---

## Platform support

| Platform | Sound | Pushover |
|----------|-------|---------|
| macOS | `afplay` (`Glass.aiff` for finish, `Funk.aiff` for attention) | Yes |
| Linux (PulseAudio) | `paplay` | Yes |
| Linux (minimal/server) | Terminal bell | Yes |
| WSL2 | PowerShell beep | Yes |
| Windows (Git Bash / MSYS2) | PowerShell beep | Yes |

---

## Troubleshooting

**No sound on macOS**

Make sure your volume is not muted and the files `/System/Library/Sounds/Glass.aiff` and `/System/Library/Sounds/Funk.aiff` exist. If you prefer different sounds, set `AGENT_NOTIFY_SOUND_FINISH` and `AGENT_NOTIFY_SOUND_ATTENTION` in `.env`.

**No sound on Linux**

Check that `paplay` is installed (`sudo apt install pulseaudio-utils` on Debian/Ubuntu). If you are on a server with no audio, the terminal bell is the fallback.

**Pushover notification not arriving**

- Run the test command above and check stderr for error messages.
- Confirm `PUSHOVER_TOKEN` and `PUSHOVER_USER` are set correctly and exported or stored in `.env`.
- Confirm your Pushover app is installed and logged in on your device.
- The Pushover free tier allows 10,000 messages per month. Check your usage at pushover.net.

**Claude hooks not firing**

- Run `./install/install-claude.sh` again and check the output.
- Open `~/.claude/settings.json` and verify the hook entries are present.
- Make sure `adapters/claude.sh` is executable: `chmod +x adapters/claude.sh`
- Restart Claude Code after editing `settings.json`.

**Scripts not executable**

```sh
chmod +x bin/agent-notify adapters/*.sh backends/*.sh install/*.sh
```

**Path has spaces**

The installer quotes adapter paths automatically. If you configure hooks manually, quote the path:

```json
"command": "\"/Users/your name/agent-notify/adapters/claude.sh\" stop"
```

---

## Security notes

- Never commit your `.env` file. It is gitignored.
- The Pushover API token and user key are passed as POST body fields over HTTPS by `curl`. They do not appear in process arguments or logs.
- Hook scripts are run with your user permissions. Do not point Claude hooks at untrusted scripts.
- If you install agent-notify for multiple users, each user should have their own `.env` with their own Pushover credentials.

---

## Adding a new backend

1. Create `backends/yourbackend.sh`.
2. Accept `--tool`, `--event`, `--message`, `--title` arguments (you may ignore ones you do not need).
3. Exit 0 on success, exit 1 on hard failure.
4. Add your backend name to `AGENT_NOTIFY_BACKENDS` in `.env`.

Example skeleton:

```sh
#!/usr/bin/env sh
# backends/mybackend.sh

while [ $# -gt 0 ]; do
  case "$1" in
    --tool)    tool="$2";    shift 2 ;;
    --event)   event="$2";   shift 2 ;;
    --message) message="$2"; shift 2 ;;
    --title)   title="$2";   shift 2 ;;
    *)         shift ;;
  esac
done

# Your notification logic here
printf 'mybackend: %s -- %s\n' "$title" "$message"
```

No changes to `bin/agent-notify` or any adapter are needed.

---

## Adding a new tool adapter

1. Create `adapters/yourtool.sh`.
2. Read whatever input the tool provides (stdin, env vars, arguments).
3. Call `bin/agent-notify` with `--tool`, `--event`, `--title`, `--message`.
4. If an install step is needed, create `install/install-yourtool.sh`.

---

## Limitations

- **Windows native support** (outside WSL2 / Git Bash) is limited to PowerShell beep. A full Windows Notification Center integration is not included in v1.
- **macOS sound defaults** are `Glass.aiff` for finish events and `Funk.aiff` for attention events. Override them with `AGENT_NOTIFY_SOUND_FINISH` and `AGENT_NOTIFY_SOUND_ATTENTION`.
- **Codex notify format** may vary across Codex CLI versions. Verify the `[notify]` configuration key against the current Codex documentation.
- **No per-event backend overrides** in v1. All events for all tools use the same `AGENT_NOTIFY_BACKENDS` list.

---

## Roadmap

Possible additions for future versions:

- Per-event backend configuration (e.g. play sound on Stop but push on PermissionRequest)
- `ntfy` backend for self-hosted push notifications
- Slack backend for team alerts
- Telegram backend
- macOS Notification Center backend (using `osascript`)
- Linux desktop notification backend (`notify-send`)
- Antigravity support if a documented hook or notify integration surface becomes available

---

## License

MIT. See [LICENSE](LICENSE).

---

## Contributing

Pull requests welcome. Please keep new backends and adapters simple and self-contained. Each file should be readable on its own without needing to trace through multiple layers.
