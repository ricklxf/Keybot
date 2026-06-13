import SwiftUI

struct MappingEditView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (KeyMapping) -> Void

    @State private var originalID: UUID
    @State private var name: String
    @State private var trigger: KeyTrigger
    @State private var actionType: ActionType
    @State private var targetKeyCode: Int
    @State private var targetModifiers: [ModifierKey]
    @State private var conditionType: ConditionType
    @State private var bundleIDsText: String

    enum ActionType: String, CaseIterable {
        case remap = "重映射按键"
        case lockAndSleep = "锁屏 + 休眠"
    }

    enum ConditionType: String, CaseIterable {
        case all = "所有应用"
        case only = "指定应用"
    }

    init(mapping: KeyMapping, onSave: @escaping (KeyMapping) -> Void) {
        self.onSave = onSave
        _originalID = State(initialValue: mapping.id)
        _name = State(initialValue: mapping.name)
        _trigger = State(initialValue: mapping.trigger)

        switch mapping.action {
        case .lockAndSleep:
            _actionType = State(initialValue: .lockAndSleep)
            _targetKeyCode = State(initialValue: 0)
            _targetModifiers = State(initialValue: [])
        case .remap(let kc, let mods):
            _actionType = State(initialValue: .remap)
            _targetKeyCode = State(initialValue: kc)
            _targetModifiers = State(initialValue: mods)
        }

        switch mapping.condition {
        case .all:
            _conditionType = State(initialValue: .all)
            _bundleIDsText = State(initialValue: "")
        case .only(let ids):
            _conditionType = State(initialValue: .only)
            _bundleIDsText = State(initialValue: ids.joined(separator: "\n"))
        }
    }

    private var targetTrigger: Binding<KeyTrigger> {
        Binding(
            get: { KeyTrigger(keyCode: targetKeyCode, modifiers: targetModifiers) },
            set: { targetKeyCode = $0.keyCode; targetModifiers = $0.modifiers }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("规则名称") {
                    TextField("名称", text: $name)
                }

                Section("触发按键") {
                    KeyRecorderView(trigger: $trigger)
                }

                Section("执行操作") {
                    Picker("操作类型", selection: $actionType) {
                        ForEach(ActionType.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)

                    if actionType == .remap {
                        KeyRecorderView(trigger: targetTrigger)
                    }
                }

                Section("生效范围") {
                    Picker("应用范围", selection: $conditionType) {
                        ForEach(ConditionType.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)

                    if conditionType == .only {
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $bundleIDsText)
                                .frame(height: 72)
                                .font(.system(.body, design: .monospaced))
                            if bundleIDsText.isEmpty {
                                Text("每行一个 Bundle ID\n例：com.apple.finder")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 4)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 420, height: 500)
    }

    private func save() {
        let action: MappingAction = actionType == .lockAndSleep
            ? .lockAndSleep
            : .remap(keyCode: targetKeyCode, modifiers: targetModifiers)

        let condition: AppCondition
        if conditionType == .all {
            condition = .all
        } else {
            let ids = bundleIDsText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            condition = .only(ids)
        }

        onSave(KeyMapping(
            id: originalID,
            name: name.trimmingCharacters(in: .whitespaces),
            trigger: trigger,
            action: action,
            condition: condition
        ))
        dismiss()
    }
}
