import SwiftUI
import AppKit

struct KeyRecorderView: NSViewRepresentable {
    @Binding var trigger: KeyTrigger

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let v = KeyRecorderNSView()
        v.onCapture = { [weak v] t in
            trigger = t
            v?.refresh(with: t.displayString)
        }
        return v
    }

    func updateNSView(_ nsView: KeyRecorderNSView, context: Context) {
        nsView.refresh(with: trigger.displayString)
    }
}

final class KeyRecorderNSView: NSView {
    var onCapture: ((KeyTrigger) -> Void)?
    private(set) var isRecording = false

    private let label = NSTextField(labelWithString: "点击录制…")
    private let clearBtn: NSButton = {
        let b = NSButton(title: "✕", target: nil, action: nil)
        b.bezelStyle = .roundRect
        b.isBordered = false
        b.font = .systemFont(ofSize: 10)
        return b
    }()
    private var localMonitor: Any?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        clearBtn.translatesAutoresizingMaskIntoConstraints = false
        clearBtn.target = self
        clearBtn.action = #selector(clear)
        addSubview(clearBtn)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: clearBtn.leadingAnchor, constant: -4),

            clearBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            clearBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearBtn.widthAnchor.constraint(equalToConstant: 20),

            heightAnchor.constraint(equalToConstant: 32),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(startRecording))
        addGestureRecognizer(click)
    }

    func refresh(with text: String) {
        guard !isRecording else { return }
        label.stringValue = text.isEmpty ? "点击录制…" : text
    }

    @objc private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        EventTap.shared.isCapturingKey = true
        label.stringValue = "请按下按键组合…"
        layer?.borderColor = NSColor.controlAccentColor.cgColor

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.captureEvent(event)
            return nil
        }
    }

    private func captureEvent(_ event: NSEvent) {
        stopRecording()

        var mods: [ModifierKey] = []
        let flags = event.modifierFlags
        if flags.contains(.control) { mods.append(.control) }
        if flags.contains(.option)  { mods.append(.option) }
        if flags.contains(.shift)   { mods.append(.shift) }
        if flags.contains(.command) { mods.append(.command) }

        let t = KeyTrigger(keyCode: Int(event.keyCode), modifiers: mods)
        label.stringValue = t.displayString
        onCapture?(t)
    }

    private func stopRecording() {
        isRecording = false
        EventTap.shared.isCapturingKey = false
        layer?.borderColor = NSColor.separatorColor.cgColor
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
    }

    @objc private func clear() {
        stopRecording()
        let empty = KeyTrigger(keyCode: 0, modifiers: [])
        label.stringValue = "点击录制…"
        onCapture?(empty)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopRecording() }
    }
}
