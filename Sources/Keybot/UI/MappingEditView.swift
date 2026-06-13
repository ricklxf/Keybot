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
            // Header
            HStack {
                Image(systemName: "keyboard")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(name.isEmpty ? "新规则" : name)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // Name
                    settingSection(title: "规则名称") {
                        TextField("名称", text: $name)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
                            )
                    }

                    // Trigger
                    settingSection(title: "触发按键") {
                        KeyRecorderView(trigger: $trigger)
                    }

                    // Action
                    settingSection(title: "执行操作") {
                        VStack(spacing: 8) {
                            Picker("", selection: $actionType) {
                                ForEach(ActionType.allCases, id: \.self) {
                                    Text($0.rawValue).tag($0)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                            if actionType == .remap {
                                KeyRecorderView(trigger: targetTrigger)
                            }
                        }
                    }

                    // Condition
                    settingSection(title: "生效范围") {
                        VStack(spacing: 8) {
                            Picker("", selection: $conditionType) {
                                ForEach(ConditionType.allCases, id: \.self) {
                                    Text($0.rawValue).tag($0)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                            if conditionType == .only {
                                ZStack(alignment: .topLeading) {
                                    TextEditor(text: $bundleIDsText)
                                        .font(.system(.body, design: .monospaced))
                                        .frame(height: 80)
                                        .padding(4)
                                        .background(Color(NSColor.controlBackgroundColor))
                                        .clipShape(RoundedRectangle(cornerRadius: 7))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7)
                                                .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
                                        )

                                    if bundleIDsText.isEmpty {
                                        Text("每行一个 Bundle ID\n例：com.apple.finder")
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundStyle(Color(NSColor.placeholderTextColor))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 12)
                                            .allowsHitTesting(false)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            // Buttons
            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)
                Spacer()
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func settingSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
