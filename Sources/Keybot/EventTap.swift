import Cocoa
import ApplicationServices

// 必须是全局函数才能作为 C 函数指针传入 CGEvent.tapCreate
private func tapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    EventTap.shared.handle(type: type, event: event)
}

final class EventTap {
    static let shared = EventTap()

    private var tap: CFMachPort?
    private(set) var isRunning = false

    // 缓存当前前台 app bundle ID，避免每次事件都调用 NSWorkspace
    var frontBundleID = ""

    @discardableResult
    func start() -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: nil
        ) else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true

        frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        return true
    }

    @objc private func appActivated(_ n: Notification) {
        let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        frontBundleID = app?.bundleIdentifier ?? ""
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .keyDown, .keyUp:
            return handleKey(type: type, event: event)
        case .leftMouseDown, .leftMouseUp:
            return handleMouse(event: event)
        default:
            return Unmanaged.passRetained(event)
        }
    }

    private func handleKey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let isDown = type == .keyDown

        // Ctrl+letter → Cmd+letter
        // 只处理"仅按下 Ctrl"的情况，Ctrl+Shift / Ctrl+Opt 等组合保持原样
        if flags.contains(.maskControl),
           !flags.contains(.maskCommand),
           !flags.contains(.maskAlternate),
           Keys.ctrlToCmd.contains(keyCode)
        {
            var newFlags = flags
            newFlags.remove(.maskControl)
            newFlags.insert(.maskCommand)
            event.flags = newFlags
            return Unmanaged.passRetained(event)
        }

        // Cmd+L → 锁屏 + 休眠（1 秒后）
        let onlyCmd = CGEventFlags.maskCommand
        if keyCode == Keys.l,
           flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]) == onlyCmd
        {
            if isDown { lockAndSleep() }
            return nil // 同时消耗 keyDown 和 keyUp
        }

        // ESC → Cmd+W（仅限 Finder / 微信 / QQ）
        if keyCode == Keys.escape,
           flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]) == []
        {
            let targets: Set<String> = [
                "com.apple.finder",
                "com.tencent.xinWeChat",
                "com.tencent.qq"
            ]
            if targets.contains(frontBundleID) {
                postKey(Keys.w, modifiers: .maskCommand, isDown: isDown)
                return nil
            }
        }

        // F5 → Cmd+R（仅限 Edge）
        if keyCode == Keys.f5, frontBundleID == "com.microsoft.edgemac" {
            postKey(Keys.r, modifiers: .maskCommand, isDown: isDown)
            return nil
        }

        return Unmanaged.passRetained(event)
    }

    private func handleMouse(event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        if flags.contains(.maskControl), !flags.contains(.maskCommand) {
            var newFlags = flags
            newFlags.remove(.maskControl)
            newFlags.insert(.maskCommand)
            event.flags = newFlags
        }
        return Unmanaged.passRetained(event)
    }

    private func postKey(_ keyCode: CGKeyCode, modifiers: CGEventFlags, isDown: Bool) {
        guard let e = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: isDown) else { return }
        e.flags = modifiers
        e.post(tap: .cgSessionEventTap)
    }

    private func lockAndSleep() {
        // Ctrl+Cmd+Q = macOS 锁屏快捷键
        postKey(Keys.q, modifiers: [.maskControl, .maskCommand], isDown: true)
        postKey(Keys.q, modifiers: [.maskControl, .maskCommand], isDown: false)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            task.arguments = ["sleepnow"]
            try? task.run()
        }
    }
}
