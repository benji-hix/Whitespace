// Sources/Whitespace/Canvas/CanvasUIState.swift
import Observation

/// Overlay visibility shared between the menu bar commands and CanvasView.
@Observable
@MainActor
final class CanvasUIState {
    var showCommandPalette = false
    var showShortcutOverlay = false
}
