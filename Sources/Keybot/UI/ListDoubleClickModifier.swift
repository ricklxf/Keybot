import SwiftUI
import AppKit

extension View {
    func onDoubleClick(perform action: @escaping () -> Void) -> some View {
        modifier(DoubleClickModifier(action: action))
    }
}

private struct DoubleClickModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content.background(DoubleClickHelper(action: action))
    }
}

private struct DoubleClickHelper: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        // Defer until the view is in the hierarchy so we can walk up to NSTableView
        DispatchQueue.main.async { wireUp(view: v) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    private func wireUp(view: NSView) {
        var candidate: NSView? = view.superview
        while let v = candidate {
            if let table = v as? NSTableView {
                // Only wire once
                if table.doubleAction != #selector(Coordinator.doubleClicked(_:)) {
                    table.doubleAction = #selector(Coordinator.doubleClicked(_:))
                    table.target = makeCoordinator()
                    // Store coordinator on the table so it isn't released
                    objc_setAssociatedObject(table, &coordinatorKey, makeCoordinator(), .OBJC_ASSOCIATION_RETAIN)
                }
                return
            }
            candidate = v.superview
        }
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }

        @objc func doubleClicked(_ sender: Any?) { action() }
    }
}

private var coordinatorKey: UInt8 = 0
