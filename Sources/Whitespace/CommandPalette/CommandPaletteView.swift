// Sources/Whitespace/CommandPalette/CommandPaletteView.swift
import SwiftUI

struct CommandPaletteView: View {
    @Environment(FileStore.self) private var fileStore
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var focused: Bool

    private var filtered: [FileBuffer] {
        guard !query.isEmpty else { return fileStore.buffers }
        return fileStore.buffers.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Open file or switch…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onKeyPress(.upArrow) { selectedIndex = max(0, selectedIndex - 1); return .handled }
                    .onKeyPress(.downArrow) { selectedIndex = min(totalRows - 1, selectedIndex + 1); return .handled }
                    .onKeyPress(.return) { commitSelection(); return .handled }
                    .onKeyPress(.escape) { dismiss(); return .handled }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.3)

            // File list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, buffer in
                        row(label: buffer.displayName, systemImage: "doc.text", index: idx) {
                            switchTo(buffer: buffer)
                        }
                    }

                    Divider().padding(.vertical, 4).opacity(0.3)

                    row(label: "Open file…", systemImage: "folder", index: filtered.count) {
                        dismiss()
                        fileStore.openPanel()
                    }
                    row(label: "New file", systemImage: "plus", index: filtered.count + 1) {
                        dismiss()
                        fileStore.newBuffer()
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
        .onChange(of: fileStore.buffers.count) { _, _ in
            selectedIndex = min(selectedIndex, max(0, totalRows - 1))
        }
    }

    private var totalRows: Int { filtered.count + 2 }

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

    private func switchTo(buffer: FileBuffer) {
        if let idx = fileStore.buffers.firstIndex(where: { $0.id == buffer.id }) {
            fileStore.activeIndex = idx
        }
        dismiss()
    }

    private func commitSelection() {
        if selectedIndex < filtered.count {
            switchTo(buffer: filtered[selectedIndex])
        } else if selectedIndex == filtered.count {
            dismiss(); fileStore.openPanel()
        } else {
            dismiss(); fileStore.newBuffer()
        }
    }

    private func dismiss() {
        query = ""
        isPresented = false
    }
}
