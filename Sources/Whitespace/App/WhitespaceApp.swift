// Sources/Whitespace/App/WhitespaceApp.swift
import SwiftUI
import CoreText

@main
struct WhitespaceApp: App {
    @State private var keybindingStore  = KeybindingStore()
    @State private var themeStore       = ThemeStore()
    @State private var preferencesStore = PreferencesStore()

    init() { registerFonts() }

    var body: some Scene {
        DocumentGroup(newDocument: WhitespaceDocument()) { file in
            CanvasView(document: file.$document)
                .environment(keybindingStore)
                .environment(themeStore)
                .environment(preferencesStore)
                .background(WindowConfigurator())
                .frame(minWidth: 600, minHeight: 400)
        }
        .commands {
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
                Divider()
                Button("Maximize Window") { NSApp.mainWindow?.zoom(nil) }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
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
