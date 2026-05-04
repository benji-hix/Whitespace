// Sources/Whitespace/Canvas/CanvasView.swift
import SwiftUI

struct CanvasView: View {
    @Binding var document: WhitespaceDocument

    @Environment(ThemeStore.self) private var themeStore
    @Environment(PreferencesStore.self) private var prefs
    @Environment(KeybindingStore.self) private var keybindingStore

    @State private var showCommandPalette = false
    @State private var showShortcutOverlay = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                GrainBackground(theme: themeStore.current)

                HStack {
                    Spacer(minLength: 0)
                    ZenTextViewRepresentable(
                        text: $document.text,
                        theme: themeStore.current,
                        preferences: prefs,
                        keybindingStore: keybindingStore,
                        onToggleCommandPalette: { showCommandPalette.toggle() },
                        onToggleShortcutOverlay: { showShortcutOverlay.toggle() },
                        onToggleTheme: { themeStore.toggle() },
                        onSave: { NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil) },
                        onSaveAs: { NSApp.sendAction(#selector(NSDocument.saveAs(_:)), to: nil, from: nil) },
                        onOpen: { NSApp.sendAction(#selector(NSDocumentController.openDocument(_:)), to: nil, from: nil) },
                        onNew: { NSApp.sendAction(#selector(NSDocumentController.newDocument(_:)), to: nil, from: nil) },
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
    }
}
