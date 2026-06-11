// Sources/Whitespace/Canvas/CanvasView.swift
import SwiftUI

struct CanvasView: View {
    @Binding var document: WhitespaceDocument

    @Environment(ThemeStore.self) private var themeStore
    @Environment(PreferencesStore.self) private var prefs
    @Environment(KeybindingStore.self) private var keybindingStore

    // Per-window: each document window owns its overlay state; the menu
    // bar reaches the key window's copy via the focused-value system.
    @State private var ui = CanvasUIState()
    @State private var autoDismissTask: Task<Void, Never>?
    @State private var editorFocusRequest = 0

    var body: some View {
        @Bindable var ui = ui

        GeometryReader { geo in
            ZStack {
                // Layer 1: Background
                GrainBackground(themeStore: themeStore)

                // Layer 2: Editor (centered column)
                HStack {
                    Spacer(minLength: 0)
                    ZenTextViewRepresentable(
                        runs: $document.runs,
                        themeStore: themeStore,
                        preferences: prefs,
                        keybindingStore: keybindingStore,
                        focusRequestID: editorFocusRequest
                    )
                    .frame(maxWidth: prefs.columnWidth.maxPoints, maxHeight: .infinity)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .clear, location: 0.1),
                                .init(color: .black, location: 0.3),
                                .init(color: .black, location: 0.7),
                                .init(color: .clear, location: 0.9),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    Spacer(minLength: 0)
                }

                // Layer 3: Overlays
                if ui.showCommandPalette {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { ui.showCommandPalette = false }

                    CommandPaletteView(isPresented: $ui.showCommandPalette)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }

                HStack {
                    Spacer(minLength: 0)
                    ShortcutOverlayView(themeStore: themeStore)
                        .padding(.trailing, geo.size.width / 18)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .opacity(ui.showShortcutOverlay ? 1 : 0)
                .allowsHitTesting(ui.showShortcutOverlay)
            }
        }
        .focusedSceneValue(\.canvasUI, ui)
        .animation(.easeInOut(duration: 0.15), value: ui.showCommandPalette)
        .animation(.timingCurve(0.6, 0.0, 0.4, 1.0, duration: 0.6), value: ui.showShortcutOverlay)
        .onChange(of: ui.showCommandPalette) { _, isOn in
            // The palette's search field takes keyboard focus; hand it back
            // to the editor on dismissal so typing resumes without a click.
            if !isOn { editorFocusRequest += 1 }
        }
        .onChange(of: ui.showShortcutOverlay) { _, isOn in
            autoDismissTask?.cancel()
            autoDismissTask = nil
            guard isOn, prefs.shortcutsAutoDismissEnabled else { return }
            let seconds = prefs.shortcutsAutoDismissDelay
            autoDismissTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                ui.showShortcutOverlay = false
            }
        }
    }
}
