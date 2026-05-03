// Sources/Whitespace/Canvas/CanvasView.swift
import SwiftUI

struct CanvasView: View {
    @Environment(FileStore.self) private var fileStore
    @Environment(ThemeStore.self) private var themeStore
    @Environment(PreferencesStore.self) private var prefs
    @Environment(KeybindingStore.self) private var keybindingStore

    @State private var showCommandPalette = false
    @State private var showShortcutOverlay = false

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
                GrainBackground(theme: themeStore.current)

                // Layer 2: Editor (centered column)
                HStack {
                    Spacer(minLength: 0)
                    ZenTextViewRepresentable(
                        text: activeText,
                        theme: themeStore.current,
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

                if showShortcutOverlay {
                    HStack {
                        Spacer(minLength: 0)
                        ShortcutOverlayView(theme: themeStore.current)
                            .padding(.trailing, geo.size.width / 18)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showCommandPalette)
        .animation(.easeInOut(duration: 0.15), value: showShortcutOverlay)
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
