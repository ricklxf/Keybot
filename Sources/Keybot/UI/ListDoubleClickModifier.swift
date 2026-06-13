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

    // SwiftUI manages exactly one Coordinator per view instance
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.action = action
        DispatchQueue.main.async {
            var candidate: NSView? = v.superview
            while let cur = candidate {
                if let table = cur as? NSTableView {
                    table.doubleAction = #selector(Coordinator.doubleClicked(_:))
                    table.target = context.coordinator
                    // Retain coordinator so it outlives this helper view
                    objc_setAssociatedObject(table, &associatedKey,
                                            context.coordinator, .OBJC_ASSOCIATION_RETAIN)
                    return
                }
                candidate = cur.superview
            }
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Keep the coordinator's action up to date (e.g. when selectedID changes)
        context.coordinator.action = action
    }

    final class Coordinator: NSObject {
        var action: (() -> Void)?
        @objc func doubleClicked(_ sender: Any?) { action?() }
    }
}

private var associatedKey: UInt8 = 0
