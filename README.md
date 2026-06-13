# Keybot

[中文](#中文) · [English](#english)

---

## 中文

用 CGEventTap 实现的 macOS 键位映射工具，替代 Karabiner，解决两个痛点：

- **Karabiner 卡 Ctrl**：CGEventTap 直接在事件流里修改 modifier flags，没有虚拟 HID 驱动层的 stuck key 问题
- **远程桌面不生效**：CGEventTap 运行在用户 GUI session 里，Screen Sharing / VNC 连入的键盘事件同样会经过它

### 偏好设置

菜单栏图标 → **Preferences…**（或 `Cmd+,`）打开配置窗口：

- **触发按键**：点击录制框，按下任意按键组合自动识别
- **操作**：重映射到另一个键，或执行锁屏 + 休眠
- **生效范围**：所有应用，或指定 Bundle ID 列表
- 拖拽调整规则优先级，开关按钮单独禁用某条规则

配置自动持久化到 `~/Library/Application Support/Keybot/config.json`，多台 Mac 同步只需 `git pull && ./build.sh`。

### 默认映射规则

| 触发 | 效果 | 范围 |
|------|------|------|
| Ctrl + C/V/X/Z/A/S/F/P | → Cmd + 同键 | 全局 |
| Ctrl + 鼠标左键 | → Cmd + 鼠标左键 | 全局（始终生效） |
| ESC | → Cmd+W（关闭窗口） | 仅访达、微信、QQ |
| F5 | → Cmd+R（刷新） | 仅 Edge |
| Ctrl + L | → 锁屏 + 1 秒后休眠 | 全局 |

> **注意**：Terminal 里 Ctrl+C 也会被映射为 Cmd+C（复制）。发送 SIGINT 请改用 `kill` 命令，或在偏好设置里将 `com.apple.Terminal` 加入指定应用并禁用该规则。

### 构建 & 安装

需要 Xcode Command Line Tools（`xcode-select --install`）。

```bash
git clone https://github.com/ricklxf/Keybot.git
cd Keybot
./build.sh
```

首次运行后：**系统设置 → 隐私与安全性 → 辅助功能** → 开启 Keybot。

应用会自动检测权限并启动事件监听，菜单栏出现键盘图标即表示运行中。

### 开机自启

菜单栏图标 → **Launch at Login**，会在 `~/Library/LaunchAgents/` 写入 LaunchAgent。

### 代码签名

默认使用 ad-hoc 签名，每次编译后需要重新授权辅助功能。一次性修复：

```bash
bash scripts/create_cert.sh
```

在本地钥匙串创建「Keybot」自签名证书后，之后每次构建自动使用，不再重复弹窗。

### 远程桌面说明

- **别人连入你的 Mac**（Screen Sharing / VNC）：映射正常生效，CGEventTap 跑在本地 session
- **你从 Mac 连出去到 Windows**（Microsoft Remote Desktop 等）：客户端会把 Mac 的 Cmd 映射为 Windows 的 Ctrl，所以 Ctrl+C → Cmd+C → 客户端 → Windows Ctrl+C，符合预期

### 技术原理

```
键盘物理按键
    ↓
CGEventTap (.cgSessionEventTap, .headInsertEventTap)
    ↓  修改 event.flags：.maskControl → .maskCommand
应用程序收到 Cmd+C
```

Karabiner 创建虚拟 HID 设备，通过内核驱动路由所有输入，驱动层状态机出错时会出现 modifier stuck。Keybot 在用户态直接改事件，不涉及驱动状态，不会 stuck。

### 常见问题

**另一台 Mac 上出现 `/Applications/Keybot.app/Keybot.app/` 嵌套**

由 `cp -r src dst`（dst 已存在时）导致。`build.sh` 已在复制前执行 `rm -rf "$INSTALL"` 修复此问题。

**`git push` 卡住或报 "Connection closed by UNKNOWN port 65535"**

在 `~/.ssh/config` 的 GitHub 配置里加一行 `ConnectTimeout 10`：

```
Host github.com
    ProxyCommand connect -S 127.0.0.1:6153 %h %p
    ConnectTimeout 10
```

---

## English

A macOS keyboard remapping tool built with CGEventTap, designed as a drop-in replacement for Karabiner. Solves two pain points:

- **Karabiner's stuck Ctrl key** — CGEventTap modifies modifier flags directly in the event stream, with no virtual HID driver layer that can get stuck
- **Karabiner doesn't work in remote desktop** — CGEventTap runs in the user's GUI session, so keyboard events from Screen Sharing / VNC pass through it just the same

### Preferences

Click the menu bar icon → **Preferences…** (or `Cmd+,`) to open the configuration window:

- **Trigger key** — click the recorder field and press any key combination
- **Action** — remap to another key, or trigger Lock & Sleep
- **Scope** — all apps, or a specific list of Bundle IDs
- Drag rows to reorder rule priority; toggle individual rules on/off

Config is persisted to `~/Library/Application Support/Keybot/config.json`. To sync across Macs: `git pull && ./build.sh`.

### Default Mappings

| Trigger | Action | Scope |
|---------|--------|-------|
| Ctrl + C/V/X/Z/A/S/F/P | → Cmd + same key | All apps |
| Ctrl + Left Click | → Cmd + Left Click | All apps (always on) |
| ESC | → Cmd+W (close window) | Finder, WeChat, QQ only |
| F5 | → Cmd+R (refresh) | Edge only |
| Ctrl + L | → Lock screen + sleep after 1s | All apps |

> **Note:** In Terminal, Ctrl+C is also remapped to Cmd+C (copy). To send SIGINT, use `kill` instead, or add `com.apple.Terminal` as a scoped exclusion in Preferences.

### Build & Install

Requires Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/ricklxf/Keybot.git
cd Keybot
./build.sh
```

On first launch: **System Settings → Privacy & Security → Accessibility** → enable Keybot.

The app polls for permission and starts automatically once granted. A keyboard icon in the menu bar means it's running.

### Launch at Login

Menu bar icon → **Launch at Login** — writes a LaunchAgent to `~/Library/LaunchAgents/`.

### Code Signing

By default, `build.sh` falls back to ad-hoc signing, which requires re-granting Accessibility permission after every build. Run this once to fix it permanently:

```bash
bash scripts/create_cert.sh
```

This creates a self-signed "Keybot" certificate in your login keychain. Subsequent builds use it automatically.

### Remote Desktop

- **Someone connects into your Mac** (Screen Sharing / VNC) — remapping works normally, CGEventTap runs in the local session
- **You connect out to Windows** (Microsoft Remote Desktop etc.) — most clients map Mac's Cmd to Windows Ctrl, so Ctrl+C → Cmd+C → client → Windows Ctrl+C, which is the expected behavior

### How It Works

```
Physical keypress
    ↓
CGEventTap (.cgSessionEventTap, .headInsertEventTap)
    ↓  swap event.flags: .maskControl → .maskCommand
App receives Cmd+C
```

Karabiner installs a virtual HID device and routes all input through a kernel driver; when the driver's state machine goes wrong, modifiers get stuck. Keybot modifies events in user space with no driver state involved — no stuck keys.

### Troubleshooting

**Nested bundle on another Mac (`/Applications/Keybot.app/Keybot.app/`)**

Caused by `cp -r src dst` when dst already exists. `build.sh` does `rm -rf "$INSTALL"` before copying to prevent this.

**`git push` hangs or fails with "Connection closed by UNKNOWN port 65535"**

Add `ConnectTimeout 10` to the GitHub entry in `~/.ssh/config`:

```
Host github.com
    ProxyCommand connect -S 127.0.0.1:6153 %h %p
    ConnectTimeout 10
```
