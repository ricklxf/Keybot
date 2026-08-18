import Cocoa
import ApplicationServices

private let syntheticMarker: Int64 = 0x4B455942
// Remoter（远程桌面被控端）注入按键/鼠标事件时打的标记，让 Keybot 的
// 重映射逻辑直接放行，不去改写——远程控制场景下没有人物理坐在这台
// 机器前，注入进来的按键应该原样落地，不该被本机的重映射规则再改写
// 一遍。这个值要跟 Remoter-Mac/Sources/RemoterAgent/Input/InputLocker.swift
// 里的 injectedTag 保持完全一致，两边分处不同仓库，改一边记得也改另一边。
private let remoterInjectedMarker: Int64 = 0x52656d6f_00000001

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
    var isCapturingKey = false

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
        return true
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // 系统会在回调响应慢或被判定异常时自动禁用 tap，需主动重新启用，否则按键全部失效直到重启
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passRetained(event)
        case .keyDown, .keyUp:   return handleKey(type: type, event: event)
        case .leftMouseDown, .leftMouseUp: return handleMouse(event: event)
        default: return Unmanaged.passRetained(event)
        }
    }

    private func handleKey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let sourceTag = event.getIntegerValueField(.eventSourceUserData)
        if sourceTag == syntheticMarker {
            return Unmanaged.passRetained(event)
        }
        // Remoter-injected keys used to skip every mapping unconditionally
        // (see remoterInjectedMarker's doc comment above) — too broad: it
        // also blocked rules a remote session actually needs (e.g. Ctrl+C →
        // Cmd+C outside Terminal, or copying never works when driven via
        // Remoter). Now only mappings that explicitly opt in via
        // appliesToRemoterInjected run for these events; everything else —
        // including anything with a real-world consequence like
        // lockAndSleep — stays skipped by default, since nobody's
        // physically at the machine to notice/undo it going wrong.
        let isRemoterInjected = sourceTag == remoterInjectedMarker
        if isCapturingKey {
            return Unmanaged.passRetained(event)
        }

        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""

        if ConfigStore.shared.isGloballyExcluded(bundleID) {
            return Unmanaged.passRetained(event)
        }

        let flags = event.flags
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let isDown = type == .keyDown

        for mapping in ConfigStore.shared.enabledMappings {
            if isRemoterInjected && !mapping.appliesToRemoterInjected { continue }
            guard mapping.trigger.matches(keyCode: keyCode, flags: flags) else { continue }
            guard mapping.condition.matches(bundleID: bundleID) else { continue }
            guard !mapping.requireTextSelection || hasSelectedText() else { continue }

            switch mapping.action {
            case .lockAndSleep:
                // Defense in depth: never let this fire for a remote
                // session even if some future config mistakenly opts a
                // lockAndSleep rule into appliesToRemoterInjected — the
                // stakes (locking yourself out mid-session) are too high
                // to trust a single checkbox.
                if isRemoterInjected { continue }
                if isDown { lockAndSleep() }
                return nil
            case .remap(let targetKC, let targetMods):
                // 原地修改事件，避免消耗原始事件再发合成事件
                // 消耗+重发会产生修饰键状态跳变，导致被控端远程桌面修饰键卡住
                var f = CGEventFlags()
                for m in targetMods { f.insert(m.flag) }
                event.setIntegerValueField(.keyboardEventKeycode, value: Int64(targetKC))
                event.flags = f
                return Unmanaged.passRetained(event)
            }
        }

        return Unmanaged.passRetained(event)
    }

    private func hasSelectedText() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return false }
        let element = focused as! AXUIElement

        // 优先查选区长度（kAXSelectedTextRangeAttribute），比取选中文本内容
        // （kAXSelectedTextAttribute）更可靠——部分应用（如 Terminal）对后者
        // 的实现不准确，可能在没有选区时也返回非空内容
        var rangeValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
           let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) {
                return range.length > 0
            }
        }

        var selected: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let text = selected as? String else { return false }
        return !text.isEmpty
    }

    private func handleMouse(event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == remoterInjectedMarker {
            return Unmanaged.passRetained(event)
        }
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
        e.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        e.post(tap: .cgSessionEventTap)
    }

    private func lockAndSleep() {
        postKey(12, modifiers: [.maskControl, .maskCommand], isDown: true)
        postKey(12, modifiers: [.maskControl, .maskCommand], isDown: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            task.arguments = ["sleepnow"]
            try? task.run()
        }
    }
}
