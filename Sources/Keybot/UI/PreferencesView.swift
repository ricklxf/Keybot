import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var store = ConfigStore.shared
    @State private var selectedID: UUID?
    @State private var showingEdit = false
    @State private var editingMapping: KeyMapping?
    @State private var isAddingNew = false
    @State private var showingResetAlert = false

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedID) {
                ForEach(store.mappings) { mapping in
                    MappingRowView(mapping: mapping)
                        .tag(mapping.id)
                        .onTapGesture(count: 2) { beginEdit(mapping) }
                }
                .onMove { from, to in store.mappings.move(fromOffsets: from, toOffset: to) }
                .onDelete { idxs in store.mappings.remove(atOffsets: idxs) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            Divider()

            HStack(spacing: 6) {
                Button { addNew() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("添加规则")

                Button { deleteSelected() } label: { Image(systemName: "minus") }
                    .buttonStyle(.borderless)
                    .disabled(selectedID == nil)
                    .help("删除选中规则")

                Button { editSelected() } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless)
                    .disabled(selectedID == nil)
                    .help("编辑规则")

                Spacer()

                Button("恢复默认") { showingResetAlert = true }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(minWidth: 580, minHeight: 400)
        .sheet(isPresented: $showingEdit) {
            if let m = editingMapping {
                MappingEditView(mapping: m) { saved in
                    if isAddingNew {
                        store.mappings.append(saved)
                        selectedID = saved.id
                    } else if let idx = store.mappings.firstIndex(where: { $0.id == saved.id }) {
                        store.mappings[idx] = saved
                    }
                    isAddingNew = false
                }
            }
        }
        .alert("恢复默认设置？", isPresented: $showingResetAlert) {
            Button("恢复", role: .destructive) { store.resetToDefaults() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除所有自定义规则，恢复为内置默认映射。")
        }
    }

    private func addNew() {
        isAddingNew = true
        editingMapping = KeyMapping(
            name: "新规则",
            trigger: KeyTrigger(keyCode: 0, modifiers: [.control]),
            action: .remap(keyCode: 0, modifiers: [.command])
        )
        showingEdit = true
    }

    private func editSelected() {
        guard let id = selectedID,
              let m = store.mappings.first(where: { $0.id == id }) else { return }
        beginEdit(m)
    }

    private func beginEdit(_ m: KeyMapping) {
        isAddingNew = false
        editingMapping = m
        showingEdit = true
    }

    private func deleteSelected() {
        guard let id = selectedID else { return }
        store.mappings.removeAll { $0.id == id }
        selectedID = nil
    }
}

private struct MappingRowView: View {
    @ObservedObject private var store = ConfigStore.shared
    let mapping: KeyMapping

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: enabledBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 3) {
                Text(mapping.name)
                    .fontWeight(.medium)

                HStack(spacing: 6) {
                    Text(mapping.trigger.displayString)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Text(mapping.action.displayString)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if case .only(let ids) = mapping.condition, !ids.isEmpty {
                        Text("· \(ids.count) 个应用")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 3)
        .opacity(mapping.enabled ? 1 : 0.5)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { mapping.enabled },
            set: { val in
                if let idx = store.mappings.firstIndex(where: { $0.id == mapping.id }) {
                    store.mappings[idx].enabled = val
                }
            }
        )
    }
}
