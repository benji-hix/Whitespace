// Sources/Whitespace/CommandPalette/CommandPaletteView.swift
import SwiftUI
import AppKit

struct CommandPaletteView: View {
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var focused: Bool

    private struct Action: Identifiable {
        let id = UUID()
        let label: String
        let systemImage: String
        let perform: () -> Void
    }

    private var actions: [Action] {
        [
            Action(label: "New Document", systemImage: "plus") {
                NSApp.sendAction(#selector(NSDocumentController.newDocument(_:)), to: nil, from: nil)
            },
            Action(label: "Open File…", systemImage: "folder") {
                NSApp.sendAction(#selector(NSDocumentController.openDocument(_:)), to: nil, from: nil)
            },
        ]
    }

    private var filtered: [Action] {
        guard !query.isEmpty else { return actions }
        return actions.filter { $0.label.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Run a command…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onKeyPress(.upArrow) { selectedIndex = max(0, selectedIndex - 1); return .handled }
                    .onKeyPress(.downArrow) { selectedIndex = min(max(0, filtered.count - 1), selectedIndex + 1); return .handled }
                    .onKeyPress(.return) { commitSelection(); return .handled }
                    .onKeyPress(.escape) { dismiss(); return .handled }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.3)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, action in
                        row(label: action.label, systemImage: action.systemImage, index: idx) {
                            dismiss()
                            action.perform()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 280)
        }
        .frame(width: 420)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .onAppear { focused = true; selectedIndex = 0 }
        .onChange(of: query) { _, _ in selectedIndex = 0 }
    }

    private func row(label: String, systemImage: String, index: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(label)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(index == selectedIndex ? Color.primary.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func commitSelection() {
        guard filtered.indices.contains(selectedIndex) else { return }
        let action = filtered[selectedIndex]
        dismiss()
        action.perform()
    }

    private func dismiss() {
        query = ""
        isPresented = false
    }
}
