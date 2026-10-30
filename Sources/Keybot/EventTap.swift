import Cocoa
import ApplicationServices

private let syntheticMarker: Int64 = 0x4B455942

private let kcCommand: CGKeyCode = 55
private let kcControl: CGKeyCode = 59
private let kcRightControl: CGKeyCode = 62
// 设备相关的左右修饰键位（NX_DEVICE*KEYMASK），只改 maskControl/maskCommand 会留下残位
private let deviceCtrlBits: UInt64 = 0x0001 | 0x2000
private let deviceCmdBits: UInt64 = 0x0008 | 0x0010

private func tapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    EventTap.shared.handle(proxy: proxy, type: type, event: event)
}

final class EventTap {
    static let shared = EventTap()

    private var tap: CFMachPort?
    private(set) var isRunning = false
    var isCapturingKey = false
    // 物理上按着 Control，但已对应用宣称"Control 松开、Command 按下"
    private var ctrlSwapped = false

    @discardableResult
    func start() -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
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

    func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // 系统会在回调响应慢或被判定异常时自动禁用 tap，需主动重新启用，否则按键全部失效直到重启
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passRetained(event)
        case .keyDown, .keyUp:   return handleKey(proxy: proxy, type: type, event: event)
        case .flagsChanged:      return handleFlags(proxy: proxy, event: event)
        case .leftMouseDown, .leftMouseUp: return handleMouse(event: event)
        default: return Unmanaged.passRetained(event)
        }
    }

    private func handleKey(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == syntheticMarker {
            return Unmanaged.passRetained(event)
        }
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
            guard mapping.trigger.matches(keyCode: keyCode, flags: flags) else { continue }
            guard mapping.condition.matches(bundleID: bundleID) else { continue }
            guard !mapping.requireTextSelection || hasSelectedText() else { continue }

            switch mapping.action {
            case .lockAndSleep:
                if isDown { lockAndSleep() }
                return nil
            case .remap(let targetKC, let targetMods):
                var f = CGEventFlags()
                for m in targetMods { f.insert(m.flag) }
                // Ctrl+键 → Cmd+键 时，应用（尤其 Chromium/Electron）只看到 Control 的按下/松开，
                // 中间却夹着带 Command 的按键，内部修饰键状态会错乱成"Ctrl 卡住"（远程桌面必现）。
                // 所以先补发配套的修饰键事件，让 Control/Command 的按下松开序列自洽
                if flags.contains(.maskControl), !flags.contains(.maskCommand),
                   f.contains(.maskCommand), !f.contains(.maskControl) {
                    beginCtrlSwap(proxy: proxy, flags: flags)
                } else {
                    endCtrlSwap(proxy: proxy, flags: flags)
                }
                if mapping.useSyntheticRepost {
                    // Chromium 系应用（Edge/Chrome）对原地改事件不敏感，识别不出来，
                    // 必须消耗原事件再发一个全新的合成事件才行
                    postKey(CGKeyCode(targetKC), modifiers: f, isDown: isDown)
                    return nil
                }
                // 原地修改事件，避免消耗原始事件再发合成事件
                // 消耗+重发会产生修饰键状态跳变，导致被控端远程桌面修饰键卡住
                event.setIntegerValueField(.keyboardEventKeycode, value: Int64(targetKC))
                event.flags = f
                return Unmanaged.passRetained(event)
            }
        }

        // 按住 Ctrl 期间按了不改的键（如 Ctrl+K），先把 Control 还给应用
        endCtrlSwap(proxy: proxy, flags: flags)
        return Unmanaged.passRetained(event)
    }

    private func handleFlags(proxy: CGEventTapProxy, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard ctrlSwapped, event.getIntegerValueField(.eventSourceUserData) != syntheticMarker else {
            return Unmanaged.passRetained(event)
        }
        let flags = event.flags
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        if (keyCode == kcControl || keyCode == kcRightControl), !flags.contains(.maskControl) {
            // 松开物理 Ctrl → 对应用来说是松开 Command
            ctrlSwapped = false
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(kcCommand))
            event.flags = withoutCtrlCmd(flags)
            return Unmanaged.passRetained(event)
        }
        if !flags.contains(.maskControl) {
            // 漏掉了 Ctrl 松开（如 tap 曾被系统暂停），补一个 Command 松开自愈
            endCtrlSwap(proxy: proxy, flags: flags)
            return Unmanaged.passRetained(event)
        }
        // 交换期间按下/松开其他修饰键：继续对应用呈现 Command 而不是 Control
        event.flags = withoutCtrlCmd(flags).union(CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x0008))
        return Unmanaged.passRetained(event)
    }

    private func beginCtrlSwap(proxy: CGEventTapProxy, flags: CGEventFlags) {
        guard !ctrlSwapped else { return }
        ctrlSwapped = true
        let released = CGEventFlags(rawValue: flags.subtracting(.maskControl).rawValue & ~deviceCtrlBits)
        postModifier(proxy: proxy, keyCode: kcControl, flags: released)
        postModifier(proxy: proxy, keyCode: kcCommand,
                     flags: released.union(CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x0008)))
    }

    private func endCtrlSwap(proxy: CGEventTapProxy, flags: CGEventFlags) {
        guard ctrlSwapped else { return }
        ctrlSwapped = false
        postModifier(proxy: proxy, keyCode: kcCommand, flags: withoutCtrlCmd(flags))
        if flags.contains(.maskControl) {
            postModifier(proxy: proxy, keyCode: kcControl,
                         flags: withoutCtrlCmd(flags).union(CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x0001)))
        }
    }

    private func withoutCtrlCmd(_ flags: CGEventFlags) -> CGEventFlags {
        CGEventFlags(rawValue: flags.subtracting([.maskControl, .maskCommand]).rawValue & ~(deviceCtrlBits | deviceCmdBits))
    }

    // tapPostEvent 插在本 tap 之后、当前事件之前送达，保证修饰键事件先于被改写的按键
    private func postModifier(proxy: CGEventTapProxy, keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let e = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else { return }
        e.type = .flagsChanged
        e.flags = flags
        e.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        e.tapPostEvent(proxy)
    }

    private func hasSelectedText() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        // 目标 App 卡住/无响应时，Accessibility 查询会一直等它回应——这个查询
        // 跟所有按键事件挤在同一条处理队列里，卡住等于把全系统键盘输入都拖死。
        // 设个超时上限，超时就当查不到处理，不能让它无限期等下去。
        AXUIElementSetMessagingTimeout(systemWide, 0.2)
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return false }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.2)

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
