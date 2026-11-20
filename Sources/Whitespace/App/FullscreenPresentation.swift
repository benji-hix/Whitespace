// Sources/Whitespace/App/FullscreenPresentation.swift
import AppKit

/// What a document window asks of the system in fullscreen: the menu bar and
/// Dock stay out of sight but slide in at the screen edge, so menus remain
/// reachable by mouse. The set is fixed rather than built from AppKit's
/// proposal, so whether it is valid never depends on the user's settings.
enum FullscreenPresentation {
    static let options: NSApplication.PresentationOptions =
        [.fullScreen, .autoHideMenuBar, .autoHideDock]

    /// The combination rules from `NSApplication.PresentationOptions`. AppKit
    /// raises an exception for a set that breaks any of them, so it is checked
    /// here, in a test, rather than by trying it.
    static func isValid(_ options: NSApplication.PresentationOptions) -> Bool {
        let anyDock = options.contains(.hideDock) || options.contains(.autoHideDock)
        if options.contains(.hideDock) && options.contains(.autoHideDock) { return false }
        if options.contains(.hideMenuBar) && options.contains(.autoHideMenuBar) { return false }
        if options.contains(.hideMenuBar) && !options.contains(.hideDock) { return false }
        if options.contains(.autoHideMenuBar) && !anyDock { return false }
        let needDock: NSApplication.PresentationOptions = [
            .disableProcessSwitching, .disableForceQuit,
            .disableSessionTermination, .disableMenuBarTransparency,
        ]
        if !options.isDisjoint(with: needDock) && !anyDock { return false }
        if options.contains(.autoHideToolbar)
            && !(options.contains(.fullScreen) && options.contains(.autoHideMenuBar)) { return false }
        return true
    }
}
