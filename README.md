# agent-notify

Stop babysitting your AI agents.

Get sound, iPhone, and Apple Watch alerts when Claude Code or Codex:
- finishes a task
- needs your input
- sends a notification

## Features

- 🔔 Local sound notifications (macOS, Linux, Windows)
- 📱 Push notifications via Pushover
- ⌚ Apple Watch support (via iPhone mirroring)
- ⚡ Works with Claude Code and Codex
- 🧠 Event-aware alerts (different sounds + priorities)
- 🧩 Extensible architecture (add Slack, Telegram, etc.)

## Why this exists

If you're running long AI tasks, you shouldn't have to sit and watch your terminal.

agent-notify lets you:
- walk away
- get notified when something matters
- come back only when needed

## Quick Start

```bash
git clone https://github.com/YOUR_USERNAME/agent-notify
cd agent-notify
chmod +x bin/agent-notify adapters/*.sh backends/*.sh install/*.sh
./install/install-claude.sh
````

## Optional: Enable phone + Apple Watch alerts

1. Create a Pushover account: [https://pushover.net](https://pushover.net)
2. Create an application to get a token
3. Add to `.env`:

```bash
AGENT_NOTIFY_BACKENDS=sound,pushover
PUSHOVER_TOKEN=your_token
PUSHOVER_USER=your_user_key
```

## Supported Tools

* Claude Code (hooks: stop, notification, permission_request)
* Codex (task completion + hooks)

## Roadmap

* Telegram backend
* Slack backend
* ntfy support
* Antigravity (if hooks become available)

---

Built for real workflows. Not demos.

```

---

## My push to you

Don’t treat this like a side project.

This is:
- directly useful
- tied to your Hive ecosystem
- something other builders actually need

---

If you want, next I’ll help you:
👉 turn this into a **one-command install (curl | bash)** so people actually use it
```
