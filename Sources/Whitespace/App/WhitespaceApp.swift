// Sources/Whitespace/App/WhitespaceApp.swift
import SwiftUI
import AppKit
import CoreText
import UniformTypeIdentifiers

@main
struct WhitespaceApp: App {
    @NSApplicationDelegateAdaptor(LaunchDelegate.self) private var launchDelegate
    @State private var keybindingStore  = KeybindingStore()
    @State private var themeStore       = ThemeStore()
    @State private var preferencesStore = PreferencesStore()

    init() { registerFonts() }

    var body: some Scene {
        // The autoclosure re-evaluates per new document, so the preference
        // applies at creation time. It is Sendable, so it must not touch
        // preferencesStore — newUntitled reads the same UserDefaults key the
        // content-type lists do.
        DocumentGroup(newDocument: WhitespaceDocument.newUntitled()) { file in
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
        // In fullscreen AppKit owns the titlebar: it auto-shows on hover and
        // un-hides the traffic lights as part of that. Re-asserting here would
        // fight it on every windowDidUpdate — which is a hot notification — and
        // the symptom is flicker along the top edge. Fullscreen already hides
        // the chrome, so there is nothing to enforce.
        if window.styleMask.contains(.fullScreen) { return false }
        return window.toolbar != nil
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

/// Launch must land on a blank page, never a file dialog.
///
/// With nothing to restore, AppKit answers its own untitled-file question with
/// the app-centric Open panel, so a cold launch opens a window titled `Open`.
/// The failure hides easily: any leftover autosaved untitled document satisfies
/// the launch instead, so the panel only surfaces once the autosave store is
/// empty — which is why it reads as intermittent.
///
/// `applicationShouldOpenUntitledFile` / `applicationOpenUntitledFile` are the
/// obvious levers and they do not work here. SwiftUI keeps itself as
/// `NSApp.delegate` (`SwiftUI.AppDelegate`) and an `NSApplicationDelegateAdaptor`
/// object only receives the delegate methods that AppKit posts as
/// notifications — the will/did-finish-launching pair. Every other delegate
/// method is messaged straight to SwiftUI's object, so implementing those two
/// compiles, runs, and is never called. Measured, not assumed.
///
/// What is reachable is the outcome. By `applicationDidFinishLaunching` the
/// panel is already a visible `NSOpenPanel` in `NSApp.windows`, so the decision
/// reads AppKit's answer instead of trying to pre-empt it. Restoration is the
/// other branch: it publishes its documents *after* this notification (and after
/// the first runloop idle), leaving `NSApp.windows` empty here — so an absent
/// panel means a session is still on its way and must not be covered with a
/// blank page.
final class LaunchDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let panel = NSApp.windows.first(where: { $0 is NSOpenPanel && $0.isVisible }) else { return }
        // Order matters: give the app a document before dismissing the panel,
        // so cancelling never lands on a running app with nothing open.
        // newDocument is the path ⌘N takes, so the New Files preference still
        // chooses the type.
        NSDocumentController.shared.newDocument(nil)
        (panel as? NSOpenPanel)?.cancel(nil)
    }
}
