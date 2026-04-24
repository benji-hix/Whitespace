// Sources/Folio/App/FolioApp.swift
import SwiftUI
import CoreText

@main
struct FolioApp: App {
    @State private var fileStore        = FileStore()
    @State private var keybindingStore  = KeybindingStore()
    @State private var themeStore       = ThemeStore()
    @State private var preferencesStore = PreferencesStore()

    init() { registerFonts() }

    var body: some Scene {
        WindowGroup {
            CanvasView()
                .environment(fileStore)
                .environment(keybindingStore)
                .environment(themeStore)
                .environment(preferencesStore)
                .background(WindowConfigurator())
                .frame(minWidth: 600, minHeight: 400)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 650)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") { fileStore.newBuffer() }
                    .keyboardShortcut("n")
                Button("Open…") { fileStore.openPanel() }
                    .keyboardShortcut("o")
                Divider()
                Button("Save") { Task { try? await fileStore.saveActive() } }
                    .keyboardShortcut("s")
                Button("Save As…") { _ = fileStore.saveAsPanel() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .printItem) { }

            CommandMenu("View") {
                Button("Toggle Dark Mode") { themeStore.toggle() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Command Palette") { }
                    .keyboardShortcut("p")
                    .disabled(true)
                Button("Shortcut Overlay") { }
                    .keyboardShortcut("/")
                    .disabled(true)
            }
        }

        Settings {
            PreferencesView()
                .environment(keybindingStore)
                .environment(preferencesStore)
                .environment(themeStore)
        }
    }

    private func registerFonts() {
        let names = ["CrimsonPro-Light", "CrimsonPro-LightItalic", "CrimsonPro-Medium", "CrimsonPro-MediumItalic"]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
