// Sources/Whitespace/Canvas/CanvasView.swift
import SwiftUI

struct CanvasView: View {
    @Environment(FileStore.self) private var fileStore
    @Environment(ThemeStore.self) private var themeStore
    @Environment(PreferencesStore.self) private var prefs
    @Environment(KeybindingStore.self) private var keybindingStore

    @State private var showCommandPalette = false
    @State private var showShortcutOverlay = false
    @State private var autoDismissTask: Task<Void, Never>?

    private var activeText: Binding<String> {
        Binding(
            get: { fileStore.activeBuffer?.text ?? "" },
            set: { fileStore.updateActiveText($0) }
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Layer 1: Background
                GrainBackground(themeStore: themeStore)

                // Layer 2: Editor (centered column)
                HStack {
                    Spacer(minLength: 0)
                    ZenTextViewRepresentable(
                        text: activeText,
                        themeStore: themeStore,
                        preferences: prefs,
                        keybindingStore: keybindingStore,
                        onToggleCommandPalette: { showCommandPalette.toggle() },
                        onToggleShortcutOverlay: { showShortcutOverlay.toggle() },
                        onToggleTheme: { themeStore.toggle() },
                        onSave: { Task { try? await fileStore.saveActive() } },
                        onSaveAs: { _ = fileStore.saveAsPanel() },
                        onOpen: { fileStore.openPanel() },
                        onNew: { fileStore.newBuffer() },
                        onIncreaseFontSize: { prefs.setFontSize(prefs.fontSize + 1) },
                        onDecreaseFontSize: { prefs.setFontSize(prefs.fontSize - 1) }
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
                if showCommandPalette {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { showCommandPalette = false }

                    CommandPaletteView(isPresented: $showCommandPalette)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }

                HStack {
                    Spacer(minLength: 0)
                    ShortcutOverlayView(themeStore: themeStore)
                        .padding(.trailing, geo.size.width / 18)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .opacity(showShortcutOverlay ? 1 : 0)
                .allowsHitTesting(showShortcutOverlay)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showCommandPalette)
        .animation(.timingCurve(0.6, 0.0, 0.4, 1.0, duration: 0.6), value: showShortcutOverlay)
        .onChange(of: showShortcutOverlay) { _, isOn in
            autoDismissTask?.cancel()
            autoDismissTask = nil
            guard isOn, prefs.shortcutsAutoDismissEnabled else { return }
            let seconds = prefs.shortcutsAutoDismissDelay
            autoDismissTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                showShortcutOverlay = false
            }
        }
        .onChange(of: fileStore.activeBuffer?.text) { _, _ in
            if prefs.autoSaveEnabled {
                fileStore.scheduleAutoSave(delay: prefs.autoSaveDelay)
            }
        }
        .onAppear {
            if fileStore.buffers.isEmpty { fileStore.newBuffer() }
        }
    }
}
