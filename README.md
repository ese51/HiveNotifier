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
