import Cocoa
import ApplicationServices

private let syntheticMarker: Int64 = 0x4B455942

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
    var frontBundleID = ""
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
        case .keyDown, .keyUp:   return handleKey(type: type, event: event)
        case .leftMouseDown, .leftMouseUp: return handleMouse(event: event)
        default: return Unmanaged.passRetained(event)
        }
    }

    private func handleKey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
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

            switch mapping.action {
            case .lockAndSleep:
                if isDown { lockAndSleep() }
                return nil
            case .remap(let targetKC, let targetMods):
                var f = CGEventFlags()
                for m in targetMods { f.insert(m.flag) }
                postKey(CGKeyCode(targetKC), modifiers: f, isDown: isDown)
                return nil
            }
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
