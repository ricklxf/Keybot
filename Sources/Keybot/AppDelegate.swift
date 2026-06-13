import Cocoa
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 已有实例在运行则直接退出，避免重复图标
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.keybot.app")
        if running.count > 1 {
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        startWithPermissionCheck()
        buildStatusItem()
    }

    // MARK: - Permission & Start

    private func startWithPermissionCheck() {
        if AXIsProcessTrusted() {
            EventTap.shared.start()
        } else {
            // 触发系统权限弹窗
            AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            )
            // 轮询直到用户授权
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    self?.permissionTimer = nil
                    EventTap.shared.start()
                    self?.rebuildMenu()
                }
            }
        }
    }

    // MARK: - Menu Bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem?.button {
            btn.image = NSImage(systemSymbolName: "keyboard.fill", accessibilityDescription: "Keybot")
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let statusTitle = EventTap.shared.isRunning ? "✅ 运行中" : "⚠️ 需要辅助功能权限"
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        menu.addItem(statusItem)

        if !EventTap.shared.isRunning {
            let grantItem = NSMenuItem(title: "  前往系统设置授权…", action: #selector(openAccessibilityPrefs), keyEquivalent: "")
            grantItem.target = self
            menu.addItem(grantItem)
        }

        menu.addItem(.separator())

        let mappingsHeader = NSMenuItem(title: "当前映射：", action: nil, keyEquivalent: "")
        mappingsHeader.isEnabled = false
        menu.addItem(mappingsHeader)

        let rules = [
            "Ctrl + C/V/X/Z/A/S/F  →  Cmd",
            "Ctrl + 鼠标点击  →  Cmd + 点击",
            "ESC  →  Cmd+W（访达/微信/QQ）",
            "F5  →  Cmd+R（Edge）",
            "Ctrl + L  →  锁屏 + 休眠",
        ]
        for rule in rules {
            let item = NSMenuItem(title: "  \(rule)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "开机自启", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isLoginItemEnabled() ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 Keybot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        self.statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func openAccessibilityPrefs() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func toggleLoginItem() {
        if isLoginItemEnabled() {
            removeLoginItem()
        } else {
            addLoginItem()
        }
        rebuildMenu()
    }

    // MARK: - Login Item (LaunchAgent)

    private var launchAgentPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/LaunchAgents/com.keybot.app.plist"
    }

    private func isLoginItemEnabled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentPath)
    }

    private func addLoginItem() {
        guard let execPath = Bundle.main.executablePath else { return }
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.keybot.app</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(execPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
        </dict>
        </plist>
        """
        let dir = (launchAgentPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? plistContent.write(toFile: launchAgentPath, atomically: true, encoding: .utf8)
        runLaunchctl(["load", launchAgentPath])
    }

    private func removeLoginItem() {
        runLaunchctl(["unload", launchAgentPath])
        try? FileManager.default.removeItem(atPath: launchAgentPath)
    }

    private func runLaunchctl(_ args: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = args
        try? task.run()
        task.waitUntilExit()
    }
}
