// Sources/Whitespace/Preferences/PreferencesView.swift
import SwiftUI

struct PreferencesView: View {
    @State private var selectedTab: PrefTab = .general

    enum PrefTab { case general, keybindings }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tabButton("General", tab: .general)
                tabButton("Keybindings", tab: .keybindings)
                Spacer()
            }
            .padding(.horizontal, 40)
            .padding(.top, 36)
            .padding(.bottom, 20)

            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Color.primary.opacity(0.07))

            Group {
                if selectedTab == .general {
                    GeneralTabView()
                } else {
                    KeybindingsTabView()
                }
            }
        }
        .frame(width: 500, height: 450)
        .background(.ultraThinMaterial)
        .background(PrefsWindowAccessor())
    }

    private func tabButton(_ label: String, tab: PrefTab) -> some View {
        Button(label) { selectedTab = tab }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: selectedTab == tab ? .medium : .regular))
            .foregroundStyle(selectedTab == tab ? Color.primary.opacity(0.72) : Color.primary.opacity(0.28))
            .padding(.trailing, 22)
    }
}

// MARK: - General

private struct GeneralTabView: View {
    @Environment(PreferencesStore.self) private var prefs
    @Environment(ThemeStore.self) private var themeStore

    var body: some View {
        @Bindable var prefs = prefs

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PrefSection("Appearance") {
                    PrefRow("Theme") {
                        Picker("", selection: Binding(
                            get: { themeStore.current },
                            set: { themeStore.set($0) }
                        )) {
                            ForEach(Theme.allCases, id: \.self) { t in
                                Text(t.rawValue.capitalized).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }

                    PrefRow("Font Size") {
                        HStack(spacing: 10) {
                            Text("\(prefs.fontSize) pt")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color.primary.opacity(0.38))
                                .frame(width: 44, alignment: .trailing)
                            Stepper("", value: Binding(
                                get: { prefs.fontSize },
                                set: { prefs.setFontSize($0) }
                            ), in: 12...28)
                            .labelsHidden()
                        }
                    }

                    PrefRow("Line Height") {
                        Picker("", selection: $prefs.lineHeightMultiple) {
                            Text("Compact").tag(1.4)
                            Text("Normal").tag(1.6)
                            Text("Relaxed").tag(1.8)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 196)
                    }

                    PrefRow("Column Width") {
                        Picker("", selection: $prefs.columnWidth) {
                            ForEach(ColumnWidth.allCases, id: \.self) { w in
                                Text(w.rawValue.capitalized).tag(w)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 196)
                    }
                }

                PrefSection("Auto-Save") {
                    PrefRow("Enabled") {
                        Toggle("", isOn: $prefs.autoSaveEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    if prefs.autoSaveEnabled {
                        PrefRow("Delay") {
                            Picker("", selection: $prefs.autoSaveDelay) {
                                Text("1 second").tag(1)
                                Text("2 seconds").tag(2)
                                Text("5 seconds").tag(5)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 196)
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 30)
        }
    }
}

// MARK: - Keybindings

private struct KeybindingsTabView: View {
    @Environment(KeybindingStore.self) private var keybindingStore
    @State private var recordingAction: KeybindingAction? = nil
    @State private var conflictMessage: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let msg = conflictMessage {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.7))
                        .padding(.bottom, 14)
                }

                PrefSection("Editor Shortcuts") {
                    ForEach(KeybindingAction.allCases, id: \.rawValue) { action in
                        PrefRow(action.displayName) {
                            HStack(spacing: 12) {
                                Text(keybindingStore.binding(for: action).displayString)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(
                                        recordingAction == action
                                            ? Color.accentColor.opacity(0.8)
                                            : Color.primary.opacity(0.32)
                                    )
                                    .frame(minWidth: 56, alignment: .trailing)
                                Button(recordingAction == action ? "Cancel" : "Record") {
                                    recordingAction = recordingAction == action ? nil : action
                                    conflictMessage = nil
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .font(.system(size: 11))
                            }
                        }
                    }
                }

                Button("Reset to Defaults") {
                    keybindingStore.resetToDefaults()
                    recordingAction = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.3))
                .padding(.top, 6)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 30)
        }
    }
}

// MARK: - Helpers

private struct PrefSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(Color.primary.opacity(0.2))
                .padding(.bottom, 16)
            content
        }
        .padding(.bottom, 34)
    }
}

private struct PrefRow<Control: View>: View {
    let label: String
    @ViewBuilder let control: Control

    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.58))
            Spacer()
            control
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Color.primary.opacity(0.05))
        }
    }
}

// MARK: - Window

private struct PrefsWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isOpaque = false
            window.backgroundColor = .clear
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
