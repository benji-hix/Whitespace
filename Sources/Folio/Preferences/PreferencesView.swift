// Sources/Folio/Preferences/PreferencesView.swift
import SwiftUI

struct PreferencesView: View {
    @Environment(PreferencesStore.self) private var prefs
    @Environment(KeybindingStore.self) private var keybindingStore
    @Environment(ThemeStore.self) private var themeStore

    @State private var recordingAction: KeybindingAction? = nil
    @State private var conflictMessage: String? = nil

    var body: some View {
        @Bindable var prefs = prefs

        TabView {
            // MARK: General
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: Binding(
                        get: { themeStore.current },
                        set: { themeStore.set($0) }
                    )) {
                        ForEach(Theme.allCases, id: \.self) { t in
                            Text(t.rawValue.capitalized).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)

                    LabeledContent("Font Size") {
                        Stepper("\(prefs.fontSize)pt", value: Binding(
                            get: { prefs.fontSize },
                            set: { prefs.setFontSize($0) }
                        ), in: 12...28)
                    }

                    Picker("Line Height", selection: $prefs.lineHeightMultiple) {
                        Text("Compact (1.4)").tag(1.4)
                        Text("Normal (1.6)").tag(1.6)
                        Text("Relaxed (1.8)").tag(1.8)
                    }

                    Picker("Column Width", selection: $prefs.columnWidth) {
                        ForEach(ColumnWidth.allCases, id: \.self) { w in
                            Text(w.rawValue.capitalized).tag(w)
                        }
                    }
                }

                Section("Auto-Save") {
                    Toggle("Enable Auto-Save", isOn: $prefs.autoSaveEnabled)
                    if prefs.autoSaveEnabled {
                        Picker("Delay", selection: $prefs.autoSaveDelay) {
                            Text("1 second").tag(1)
                            Text("2 seconds").tag(2)
                            Text("5 seconds").tag(5)
                        }
                    }
                }
            }
            .tabItem { Label("General", systemImage: "gearshape") }
            .padding()

            // MARK: Keybindings
            Form {
                if let msg = conflictMessage {
                    Text(msg)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                ForEach(KeybindingAction.allCases, id: \.rawValue) { action in
                    LabeledContent(action.displayName) {
                        HStack {
                            Text(keybindingStore.binding(for: action).displayString)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(recordingAction == action ? .blue : .primary)
                                .frame(minWidth: 80, alignment: .trailing)
                            Button(recordingAction == action ? "Cancel" : "Record") {
                                recordingAction = recordingAction == action ? nil : action
                                conflictMessage = nil
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Button("Reset to Defaults") {
                    keybindingStore.resetToDefaults()
                    recordingAction = nil
                }
                .buttonStyle(.bordered)
            }
            .tabItem { Label("Keybindings", systemImage: "keyboard") }
            .padding()
        }
        .frame(width: 480, height: 360)
    }
}
