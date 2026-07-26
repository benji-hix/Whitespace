// Sources/Whitespace/App/WhitespaceApp.swift
import SwiftUI
import AppKit
import CoreText
import UniformTypeIdentifiers

@main
struct WhitespaceApp: App {
    @State private var keybindingStore  = KeybindingStore()
    @State private var themeStore       = ThemeStore()
    @State private var preferencesStore = PreferencesStore()

    init() { registerFonts() }

    var body: some Scene {
        // The autoclosure re-evaluates per new document, so the preference
        // applies at creation time.
        DocumentGroup(newDocument: WhitespaceDocument(
            contentType: preferencesStore.newDocumentType == .markdown
                ? WhitespaceDocument.markdownType
                : .plainText
        )) { file in
            CanvasView(document: file.$document)
                .environment(keybindingStore)
                .environment(themeStore)
                .environment(preferencesStore)
                .background(WindowConfigurator())
                .frame(minWidth: 600, minHeight: 400)
                // Declarative: stop DocumentGroup from installing its
                // title-bar toolbar at all, instead of stripping it after
                // the fact (which flickers on window swaps and drags).
                .toolbarVisibility(.hidden, for: .windowToolbar)
        }
        .commands {
            CommandGroup(replacing: .printItem) { }
            ViewMenuCommands(themeStore: themeStore)
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

/// DocumentGroup is window-per-document, so palette/overlay state is
/// per-window (owned by each CanvasView) and the menu reaches the key
/// window's copy through the focused-value system.
struct ViewMenuCommands: Commands {
    let themeStore: ThemeStore
    @FocusedValue(\.canvasUI) private var canvasUI

    var body: some Commands {
        // .toolbar placement lands these in the system View menu rather
        // than adding a second, custom "View" menu.
        CommandGroup(after: .toolbar) {
            Button("Toggle Dark Mode") { themeStore.toggle() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Command Palette") { canvasUI?.showCommandPalette.toggle() }
                .keyboardShortcut("p")
                .disabled(canvasUI == nil)
            Button("Shortcut Overlay") { canvasUI?.showShortcutOverlay.toggle() }
                .keyboardShortcut("/")
                .disabled(canvasUI == nil)
            Divider()
            Button("Maximize Window") { NSApp.mainWindow?.zoom(nil) }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            // AppKit's own Enter Full Screen item below this one is bound to the
            // Globe key on macOS 26, and Globe does not exist on most external
            // keyboards. An NSMenuItem holds exactly one key equivalent, so a
            // second chord needs a second item — this one. Both stay: Globe is
            // the shorter chord when the keyboard has it.
            Button("Toggle Full Screen") { NSApp.mainWindow?.toggleFullScreen(nil) }
                .keyboardShortcut("f", modifiers: [.control, .command])
        }
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowStylingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// DocumentGroup attaches the window well after view creation and keeps
/// re-asserting its own chrome (toolbar, titlebar, tab bar) after sheets,
/// saves, and tab operations. viewDidMoveToWindow applies the styling at
/// attach; didUpdateNotification re-applies it whenever any of it drifts —
/// the notification is hot, so the observer only acts when the cheap
/// deviation check fails.
private final class WindowStylingView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        applyStyling(to: window)
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidUpdate(_:)),
            name: NSWindow.didUpdateNotification,
            object: window
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowDidUpdate(_ note: Notification) {
        guard let window, stylingHasDrifted(in: window) else { return }
        applyStyling(to: window)
    }

    private func stylingHasDrifted(in window: NSWindow) -> Bool {
        window.toolbar != nil
            || !window.titlebarAppearsTransparent
            || window.titleVisibility != .hidden
            || !window.styleMask.contains(.fullSizeContentView)
            || window.standardWindowButton(.closeButton)?.isHidden == false
    }

    private func applyStyling(to window: NSWindow) {
        // Tabs are chrome; every document gets its own clean window.
        window.tabbingMode = .disallowed
        window.toolbar = nil
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }
}

// NOTE: SwiftUI installs its own NSDocumentController subclass
// (SwiftUI.PlatformDocumentController) before applicationWillFinishLaunching,
// so neither pinning the shared controller nor subclassing it can influence
// document behavior — untitled typing is steered through the content-type
// list order on WhitespaceDocument instead.
