// Sources/Whitespace/Canvas/CanvasUIState.swift
import SwiftUI

/// Overlay visibility for one document window. Each window controller owns an
/// instance, so the View menu's palette and overlay items act on the key
/// window only.
@Observable
@MainActor
final class CanvasUIState {
    var showCommandPalette = false
    var showShortcutOverlay = false
}
