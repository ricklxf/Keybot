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
            mappingList
            bottomBar
        }
        .frame(minWidth: 620, minHeight: 440)
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
        .alert("Restore Defaults?", isPresented: $showingResetAlert) {
            Button("Restore", role: .destructive) { store.resetToDefaults() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all custom rules and restore the built-in default mappings.")
        }
    }

    // MARK: - List

    private var mappingList: some View {
        List(selection: $selectedID) {
            ForEach(store.mappings) { mapping in
                MappingRowView(mapping: mapping, isSelected: selectedID == mapping.id)
                    .tag(mapping.id)
                    .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                    .simultaneousGesture(TapGesture(count: 2).onEnded { beginEdit(mapping) })
            }
            .onMove { store.mappings.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { store.mappings.remove(atOffsets: $0) }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: UUID.self, menu: { ids in
            if let id = ids.first, let m = store.mappings.first(where: { $0.id == id }) {
                Button("Edit…") { beginEdit(m) }
                Divider()
                Button("Delete", role: .destructive) {
                    store.mappings.removeAll { $0.id == id }
                    selectedID = nil
                }
            }
        })
    }

    // MARK: - Bottom Bar (Finder-style)

    private var bottomBar: some View {
        HStack(spacing: 0) {
            // Grouped +/- buttons
            HStack(spacing: 0) {
                Button { addNew() } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Add rule")

                Divider().frame(height: 14)

                Button { deleteSelected() } label: {
                    Image(systemName: "minus")
                        .frame(width: 28, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(selectedID == nil)
                .help("Delete selected rule")
            }
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
            )

            Divider().frame(height: 14).padding(.horizontal, 6)

            Button { editSelected() } label: {
                Image(systemName: "pencil")
                    .frame(width: 28, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(selectedID == nil)
            .help("Edit rule")

            Spacer()

            Button("Restore Defaults") { showingResetAlert = true }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - Actions

    private func addNew() {
        isAddingNew = true
        editingMapping = KeyMapping(
            name: "New Rule",
            trigger: KeyTrigger(keyCode: 0, modifiers: [.control]),
            action: .remap(keyCode: 0, modifiers: [.command])
        )
        showingEdit = true
    }

    private func editSelected() {
        guard let id = selectedID, let m = store.mappings.first(where: { $0.id == id }) else { return }
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

// MARK: - Row

private struct MappingRowView: View {
    @ObservedObject private var store = ConfigStore.shared
    let mapping: KeyMapping
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Trigger badge — keyboard shortcut style
            Text(mapping.trigger.displayString)
                .font(.system(.body, design: .monospaced).weight(.medium))
                .foregroundStyle(isSelected ? Color.white : (mapping.enabled ? Color.primary : Color.secondary))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background { badgeBackground }
                .frame(minWidth: 52, alignment: .center)

            // Name + action subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(mapping.name)
                    .font(.body)
                    .foregroundStyle(mapping.enabled ? Color.primary : Color.secondary)

                Text(mapping.action.displayString)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }

            Spacer(minLength: 8)

            // App scope badge
            conditionBadge

            // Toggle
            Toggle("", isOn: enabledBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .opacity(mapping.enabled ? 1 : 0.55)
    }

    @ViewBuilder
    private var badgeBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
                )
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.textBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 1.5, x: 0, y: 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
        }
    }

    @ViewBuilder
    private var conditionBadge: some View {
        switch mapping.condition {
        case .all:
            Text("All Apps")
                .font(.caption)
                .foregroundStyle(Color.secondary)
        case .only(let ids) where ids.isEmpty:
            Text("No Apps")
                .font(.caption)
                .foregroundStyle(Color.secondary)
        case .only(let ids):
            Text("\(ids.count) app\(ids.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(Color(NSColor.controlAccentColor))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color(NSColor.controlAccentColor).opacity(0.12))
                )
        }
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
