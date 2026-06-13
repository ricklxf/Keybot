# Keybot

[🇨🇳 中文](README.md)

A macOS keyboard remapping tool built with CGEventTap, designed as a drop-in replacement for Karabiner. Solves two pain points:

- **Karabiner's stuck Ctrl key** — CGEventTap modifies modifier flags directly in the event stream, with no virtual HID driver layer that can get stuck
- **Karabiner doesn't work in remote desktop** — CGEventTap runs in the user's GUI session, so keyboard events from Screen Sharing / VNC pass through it just the same

## Preferences

Click the menu bar icon → **Preferences…** (or `Cmd+,`) to open the configuration window:

- **Trigger key** — click the recorder field and press any key combination
- **Action** — remap to another key, or trigger Lock & Sleep
- **Scope** — all apps, or a specific list of Bundle IDs
- Drag rows to reorder rule priority; toggle individual rules on/off

Config is persisted to `~/Library/Application Support/Keybot/config.json`. To sync across Macs: `git pull && ./build.sh`.

## Default Mappings

| Trigger | Action | Scope |
|---------|--------|-------|
| Ctrl + C/V/X/Z/A/S/F/P | → Cmd + same key | All apps |
| Ctrl + Left Click | → Cmd + Left Click | All apps (always on) |
| ESC | → Cmd+W (close window) | Finder, WeChat, QQ only |
| F5 | → Cmd+R (refresh) | Edge only |
| Ctrl + L | → Lock screen + sleep after 1s | All apps |

> **Note:** In Terminal, Ctrl+C is also remapped to Cmd+C (copy). To send SIGINT, use `kill` instead, or add `com.apple.Terminal` as a scoped exclusion in Preferences.

## Build & Install

Requires Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/ricklxf/Keybot.git
cd Keybot
./build.sh
```

On first launch: **System Settings → Privacy & Security → Accessibility** → enable Keybot.

The app polls for permission and starts automatically once granted. A keyboard icon in the menu bar means it's running.

## Launch at Login

Menu bar icon → **Launch at Login** — writes a LaunchAgent to `~/Library/LaunchAgents/`.

## Code Signing

By default, `build.sh` falls back to ad-hoc signing, which requires re-granting Accessibility permission after every build. Run this once to fix it permanently:

```bash
bash scripts/create_cert.sh
```

This creates a self-signed "Keybot" certificate in your login keychain. Subsequent builds use it automatically.

## Remote Desktop

- **Someone connects into your Mac** (Screen Sharing / VNC) — remapping works normally, CGEventTap runs in the local session
- **You connect out to Windows** (Microsoft Remote Desktop etc.) — most clients map Mac's Cmd to Windows Ctrl, so Ctrl+C → Cmd+C → client → Windows Ctrl+C, which is the expected behavior

## How It Works

```
Physical keypress
    ↓
CGEventTap (.cgSessionEventTap, .headInsertEventTap)
    ↓  swap event.flags: .maskControl → .maskCommand
App receives Cmd+C
```

Karabiner installs a virtual HID device and routes all input through a kernel driver; when the driver's state machine goes wrong, modifiers get stuck. Keybot modifies events in user space with no driver state involved — no stuck keys.

## Troubleshooting

**Nested bundle on another Mac (`/Applications/Keybot.app/Keybot.app/`)**

Caused by `cp -r src dst` when dst already exists. `build.sh` does `rm -rf "$INSTALL"` before copying to prevent this.

**`git push` hangs or fails with "Connection closed by UNKNOWN port 65535"**

Add `ConnectTimeout 10` to the GitHub entry in `~/.ssh/config`:

```
Host github.com
    ProxyCommand connect -S 127.0.0.1:6153 %h %p
    ConnectTimeout 10
```
