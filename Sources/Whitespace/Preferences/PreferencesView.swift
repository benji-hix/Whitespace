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

                PrefSection("Documents") {
                    PrefRow("New Files") {
                        Picker("", selection: $prefs.newDocumentType) {
                            Text("Markdown").tag(NewDocumentType.markdown)
                            Text("Plain Text").tag(NewDocumentType.plainText)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 196)
                    }
                }

                PrefSection("Editor") {
                    PrefRow("Scroll Speed") {
                        HStack(spacing: 10) {
                            Text(String(format: "%.2fx", prefs.scrollSpeed))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color.primary.opacity(0.38))
                                .frame(width: 56, alignment: .trailing)
                            Slider(value: $prefs.scrollSpeed, in: 0.4...2.0)
                                .frame(width: 140)
                        }
                    }
                }

                PrefSection("Shortcuts Panel") {
                    PrefRow("Auto-dismiss") {
                        Toggle("", isOn: $prefs.shortcutsAutoDismissEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    if prefs.shortcutsAutoDismissEnabled {
                        PrefRow("Hide after") {
                            HStack(spacing: 10) {
                                TextField("", value: Binding(
                                    get: { prefs.shortcutsAutoDismissDelay },
                                    set: { prefs.shortcutsAutoDismissDelay = $0 }
                                ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .multilineTextAlignment(.trailing)
                                .frame(width: 56)
                                Text("seconds")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.primary.opacity(0.38))
                            }
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
    @State private var recordingMonitor: Any?

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
                                    if recordingAction == action {
                                        stopRecording()
                                    } else {
                                        startRecording(action)
                                    }
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
                    stopRecording()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.3))
                .padding(.top, 6)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 30)
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording(_ action: KeybindingAction) {
        stopRecording()
        recordingAction = action
        conflictMessage = nil
        // Swallow every key while recording so the chord can't trigger the
        // action it names (or any other shortcut).
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleRecordingEvent(event, for: action)
            return nil
        }
    }

    private func handleRecordingEvent(_ event: NSEvent, for action: KeybindingAction) {
        if event.keyCode == 53 {  // Escape cancels
            stopRecording()
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifiers = UInt64(flags.rawValue) & ShortcutBinding.modifierMask
        // Bare keys and shift-only chords would hijack normal typing in the
        // editor, where these bindings are matched on every keystroke.
        guard modifiers & ~CGEventFlags.maskShift.rawValue != 0 else {
            conflictMessage = "Use at least one of ⌃, ⌥ or ⌘."
            return
        }
        do {
            try keybindingStore.setBinding(
                ShortcutBinding(keyCode: event.keyCode, modifiers: modifiers),
                for: action
            )
            stopRecording()
        } catch {
            conflictMessage = error.localizedDescription
        }
    }

    private func stopRecording() {
        if let recordingMonitor { NSEvent.removeMonitor(recordingMonitor) }
        recordingMonitor = nil
        recordingAction = nil
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
