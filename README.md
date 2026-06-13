# Keybot

用 CGEventTap 实现的 macOS 键位映射工具，替代 Karabiner，解决两个痛点：
- **Karabiner 卡 Ctrl**：CGEventTap 直接在事件流里修改 modifier flags，没有虚拟 HID 驱动层的 stuck key 问题
- **远程桌面不生效**：CGEventTap 运行在用户 GUI session 里，Screen Sharing / VNC 连入的键盘事件同样会经过它

## 映射规则

| 触发 | 效果 | 范围 |
|------|------|------|
| Ctrl + C/V/X/Z/A/S/F | → Cmd + 同键 | 全局 |
| Ctrl + 鼠标左键 | → Cmd + 鼠标左键 | 全局 |
| ESC | → Cmd + W（关闭窗口） | 仅访达、微信、QQ |
| F5 | → Cmd + R（刷新） | 仅 Edge |
| Ctrl + L | → 锁屏 + 1 秒后休眠 | 全局 |

> **注意**：Terminal 里 Ctrl+C 也会被映射为 Cmd+C（复制）。发送 SIGINT 请改用 `kill` 命令。

## 构建 & 安装

需要 Xcode Command Line Tools（`xcode-select --install`）。

```bash
git clone https://github.com/ricklxf/Keybot.git
cd Keybot
./build.sh
cp -r .build/Keybot.app /Applications/
open /Applications/Keybot.app
```

首次运行后：**系统设置 → 隐私与安全性 → 辅助功能** → 开启 Keybot。

应用会自动检测权限并启动事件监听。菜单栏出现键盘图标即表示运行中。

## 开机自启

点击菜单栏图标 → **开机自启**，会在 `~/Library/LaunchAgents/` 写入 LaunchAgent。

## 远程桌面说明

- **别人连入你的 Mac**（Screen Sharing / VNC）：映射正常生效，因为 CGEventTap 跑在本地 session
- **你从 Mac 连出去到 Windows**（Microsoft Remote Desktop 等）：大多数远程桌面客户端会把 Mac 的 Cmd 键映射为 Windows 的 Ctrl，所以 Ctrl+C → Cmd+C → 客户端 → Windows Ctrl+C，符合预期

## 技术原理

```
键盘物理按键
    ↓
CGEventTap (.cgSessionEventTap, .headInsertEventTap)
    ↓  修改 event.flags：.maskControl → .maskCommand
应用程序收到 Cmd+C
```

与 Karabiner 的区别：Karabiner 创建虚拟 HID 设备，通过内核驱动路由所有输入，驱动层状态机出错时会出现 modifier stuck。Keybot 在用户态直接改事件，不涉及驱动状态，不会 stuck。
