// Sources/Whitespace/Canvas/CanvasUIState.swift
import SwiftUI

/// Overlay visibility for one document window. Each CanvasView owns an
/// instance and publishes it as a focused scene value so the menu bar
/// commands act on the key window only.
@Observable
@MainActor
final class CanvasUIState {
    var showCommandPalette = false
    var showShortcutOverlay = false
}

extension FocusedValues {
    @Entry var canvasUI: CanvasUIState?
}
