# NSDocument Migration + Markdown Support — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hand-rolled `FileStore`/`FileBuffer` multi-buffer model with SwiftUI's native `DocumentGroup` + `FileDocument`, then register `.md` (Markdown) as a usable document type alongside `.txt`.

**Architecture:** Whitespace becomes a true macOS document-based app. Each open file is its own window, courtesy of `DocumentGroup`. The OS provides recent files menu, dirty indicator in the title bar, autosave, version browser, encoding sniffing on open, security-scoped bookmarks, and crash-time restoration — all of which `FileStore` reinvented incompletely. The single `WhitespaceDocument: FileDocument` value type holds the text plus its content type (plain or markdown). `CanvasView` takes a `Binding<WhitespaceDocument>` instead of pulling state from `FileStore`. The Command Palette loses its "switch between buffers" feature (the OS Window menu and ⌘` already do this for windows); it keeps the New / Open quick actions.

**Tech Stack:** SwiftUI `DocumentGroup`, `FileDocument`, `UniformTypeIdentifiers`, AppKit `NSTextView` (unchanged), XCTest.

---

## File Structure

**New:**
- `Sources/Whitespace/Files/WhitespaceDocument.swift` — the `FileDocument` value type (~70 lines). Holds `text: String` and `contentType: UTType`. Reads/writes plain text and markdown.
- `Tests/WhitespaceTests/WhitespaceDocumentTests.swift` — replaces `FileStoreTests` and `FileBufferTests`.

**Modified:**
- `Sources/Whitespace/App/WhitespaceApp.swift` — `WindowGroup` → `DocumentGroup`; remove the `FileStore` `@State`; remove the custom New/Open/Save/Save-As `CommandGroup` (DocumentGroup provides them); remove `FileStore` from environment.
- `Sources/Whitespace/Canvas/CanvasView.swift` — accept `@Binding var document: WhitespaceDocument` parameter; remove `FileStore` environment and the `activeText` indirection; remove the `scheduleAutoSave` `onChange`; remove the "create initial buffer if empty" `onAppear`.
- `Sources/Whitespace/Editor/ZenTextViewRepresentable.swift` — no signature changes; keeps its `@Binding var text: String`.
- `Sources/Whitespace/CommandPalette/CommandPaletteView.swift` — remove buffer list / buffer switching; keep "New Window" and "Open…" quick actions only.
- `Sources/Whitespace/App/Info.plist` — add `CFBundleDocumentTypes` for plain text and markdown; add `UTImportedTypeDeclarations` for `net.daringfireball.markdown`.
- `Sources/Whitespace/Preferences/PreferencesStore.swift` — remove `autoSaveEnabled` and `autoSaveDelay` (NSDocument autosave is automatic). Remove their getters/setters.
- `Sources/Whitespace/Preferences/PreferencesView.swift` — remove autosave UI controls.
- `Tests/WhitespaceTests/PreferencesStoreTests.swift` — drop tests covering the removed autosave keys.

**Deleted:**
- `Sources/Whitespace/Files/FileStore.swift`
- `Sources/Whitespace/Files/FileBuffer.swift`
- `Tests/WhitespaceTests/FileStoreTests.swift`
- `Tests/WhitespaceTests/FileBufferTests.swift`

**Xcode project model changes:** Adding/removing files requires updating `Whitespace.xcodeproj/project.pbxproj`. With Xcode running and `mcpbridge` available, prefer `XcodeWrite` / `XcodeUpdate` (which keep the project model in sync). If unavailable, the plan calls out manual project membership steps.

---

## Task 1: Add Markdown UTI and Document Types to Info.plist

**Files:**
- Modify: `Sources/Whitespace/App/Info.plist`

- [ ] **Step 1: Read current Info.plist**

Confirm the keys we'll be adding aren't already present. The current file ends at `</dict></plist>` with `NSPrincipalClass` as the last entry.

- [ ] **Step 2: Add CFBundleDocumentTypes and UTImportedTypeDeclarations**

Insert these keys before the closing `</dict>`. The Markdown UTI uses the conventional reverse-DNS identifier (`net.daringfireball.markdown`) since macOS does not declare a system-wide Markdown UTI as of macOS 14.

```xml
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>Plain Text</string>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>LSHandlerRank</key>
        <string>Alternate</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>public.plain-text</string>
            <string>public.text</string>
            <string>public.utf8-plain-text</string>
        </array>
    </dict>
    <dict>
        <key>CFBundleTypeName</key>
        <string>Markdown Document</string>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>LSHandlerRank</key>
        <string>Alternate</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>net.daringfireball.markdown</string>
        </array>
    </dict>
</array>
<key>UTImportedTypeDeclarations</key>
<array>
    <dict>
        <key>UTTypeIdentifier</key>
        <string>net.daringfireball.markdown</string>
        <key>UTTypeDescription</key>
        <string>Markdown Document</string>
        <key>UTTypeConformsTo</key>
        <array>
            <string>public.plain-text</string>
        </array>
        <key>UTTypeTagSpecification</key>
        <dict>
            <key>public.filename-extension</key>
            <array>
                <string>md</string>
                <string>markdown</string>
                <string>mdown</string>
            </array>
            <key>public.mime-type</key>
            <array>
                <string>text/markdown</string>
            </array>
        </dict>
    </dict>
</array>
```

- [ ] **Step 3: Validate the plist**

Run: `plutil -lint Sources/Whitespace/App/Info.plist`
Expected: `Sources/Whitespace/App/Info.plist: OK`

- [ ] **Step 4: Commit**

```bash
git add Sources/Whitespace/App/Info.plist
git commit -m "chore: declare Plain Text and Markdown document types in Info.plist"
```

---

## Task 2: Write `WhitespaceDocumentTests` (failing)

**Files:**
- Create: `Tests/WhitespaceTests/WhitespaceDocumentTests.swift`

- [ ] **Step 1: Write the failing test file**

```swift
// Tests/WhitespaceTests/WhitespaceDocumentTests.swift
import XCTest
import UniformTypeIdentifiers
@testable import Whitespace

final class WhitespaceDocumentTests: XCTestCase {
    func testNewDocumentIsEmptyPlainText() {
        let doc = WhitespaceDocument()
        XCTAssertEqual(doc.text, "")
        XCTAssertEqual(doc.contentType, .plainText)
    }

    func testReadPlainTextUTF8() throws {
        let data = "hello world".data(using: .utf8)!
        let doc = try WhitespaceDocument(data: data, type: .plainText)
        XCTAssertEqual(doc.text, "hello world")
        XCTAssertEqual(doc.contentType, .plainText)
    }

    func testReadMarkdown() throws {
        let data = "# Heading\n\nBody.".data(using: .utf8)!
        let markdown = UTType("net.daringfireball.markdown")!
        let doc = try WhitespaceDocument(data: data, type: markdown)
        XCTAssertEqual(doc.text, "# Heading\n\nBody.")
        XCTAssertEqual(doc.contentType, markdown)
    }

    func testReadFallsBackToLatin1WhenNotUTF8() throws {
        // 0xE9 is "é" in Latin-1, invalid as a standalone UTF-8 byte.
        let data = Data([0x68, 0xE9, 0x6C, 0x6C, 0x6F]) // "héllo" Latin-1
        let doc = try WhitespaceDocument(data: data, type: .plainText)
        XCTAssertEqual(doc.text, "héllo")
    }

    func testReadEmptyData() throws {
        let doc = try WhitespaceDocument(data: Data(), type: .plainText)
        XCTAssertEqual(doc.text, "")
    }

    func testWriteRoundtripPlainText() throws {
        var doc = WhitespaceDocument()
        doc.text = "round trip"
        let data = try doc.encodedData(for: .plainText)
        XCTAssertEqual(String(data: data, encoding: .utf8), "round trip")
    }

    func testWriteRoundtripMarkdown() throws {
        let markdown = UTType("net.daringfireball.markdown")!
        var doc = WhitespaceDocument(text: "# Hi", contentType: markdown)
        let data = try doc.encodedData(for: markdown)
        XCTAssertEqual(String(data: data, encoding: .utf8), "# Hi")
    }
}
```

- [ ] **Step 2: Run the tests to confirm they fail**

If Xcode is open, prefer mcpbridge: `RunSomeTests` scoped to `WhitespaceDocumentTests`.
Otherwise: `mcp__xcodebuild__test_macos` with the `WhitespaceTests` scheme.
Expected: compile error (no `WhitespaceDocument` type).

- [ ] **Step 3: Add `WhitespaceDocumentTests.swift` to the test target**

If `XcodeUpdate`/`XcodeInsertFile` is available via mcpbridge, use it — it patches `project.pbxproj` and keeps the project model live. Otherwise, open `Whitespace.xcodeproj` and drag the file into the `WhitespaceTests` group, ensuring "Add to targets: WhitespaceTests" is checked.

Do NOT commit yet — the type doesn't exist. Tests are red on purpose.

---

## Task 3: Implement `WhitespaceDocument`

**Files:**
- Create: `Sources/Whitespace/Files/WhitespaceDocument.swift`

- [ ] **Step 1: Write the implementation**

```swift
// Sources/Whitespace/Files/WhitespaceDocument.swift
import SwiftUI
import UniformTypeIdentifiers

struct WhitespaceDocument: FileDocument {
    static let markdownType = UTType(importedAs: "net.daringfireball.markdown")

    static var readableContentTypes: [UTType] { [.plainText, .text, markdownType] }
    static var writableContentTypes: [UTType] { [.plainText, markdownType] }

    var text: String
    var contentType: UTType

    init(text: String = "", contentType: UTType = .plainText) {
        self.text = text
        self.contentType = contentType
    }

    init(configuration: ReadConfiguration) throws {
        let type = configuration.contentType
        let data = configuration.file.regularFileContents ?? Data()
        try self.init(data: data, type: type)
    }

    init(data: Data, type: UTType) throws {
        guard !data.isEmpty else {
            self.text = ""
            self.contentType = type
            return
        }
        if let utf8 = String(data: data, encoding: .utf8) {
            self.text = utf8
        } else {
            var used: UInt = 0
            let nsstr = NSString(data: data, usedEncoding: &used) as String?
            guard let decoded = nsstr else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            self.text = decoded
        }
        self.contentType = type
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try encodedData(for: configuration.contentType)
        return FileWrapper(regularFileWithContents: data)
    }

    func encodedData(for type: UTType) throws -> Data {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }
}
```

- [ ] **Step 2: Add the file to the app target**

Use `XcodeInsertFile` via mcpbridge if Xcode is open. Otherwise add it to the `Whitespace` target manually in Xcode.

- [ ] **Step 3: Run the tests, confirm they pass**

mcpbridge: `RunSomeTests` for `WhitespaceDocumentTests`.
Headless: `mcp__xcodebuild__test_macos` filtered to `WhitespaceTests/WhitespaceDocumentTests`.
Expected: 7 tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/Whitespace/Files/WhitespaceDocument.swift Tests/WhitespaceTests/WhitespaceDocumentTests.swift Whitespace.xcodeproj/project.pbxproj
git commit -m "feat: add WhitespaceDocument FileDocument with plain text and markdown support"
```

---

## Task 4: Wire `DocumentGroup` into `WhitespaceApp`

**Files:**
- Modify: `Sources/Whitespace/App/WhitespaceApp.swift`
- Modify: `Sources/Whitespace/Canvas/CanvasView.swift` (signature change only — full body replacement comes in Task 5)

- [ ] **Step 1: Replace `WhitespaceApp.swift` in full**

```swift
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
```

Notes on what changed:
- `WindowGroup { CanvasView() }` → `DocumentGroup(newDocument:) { file in CanvasView(document: file.$document) }`. `file.$document` is `Binding<WhitespaceDocument>`.
- Removed `FileStore` `@State` and its environment injection.
- Removed the custom `CommandGroup(replacing: .newItem)` — `DocumentGroup` automatically installs New / Open / Save / Save As / Recent Files menu items with the standard shortcuts.

- [ ] **Step 2: Build to surface compile errors**

mcpbridge: `BuildProject`, then `XcodeListNavigatorIssues`.
Headless: `mcp__xcodebuild__build_macos`.
Expected: errors in `CanvasView.swift` (still references `FileStore`); fix in next task.

Do NOT commit yet — the build is broken.

---

## Task 5: Rewrite `CanvasView` to use the document binding

**Files:**
- Modify: `Sources/Whitespace/Canvas/CanvasView.swift`

- [ ] **Step 1: Replace the file in full**

```swift
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
```

What changed vs. the old version:
- `@Environment(FileStore.self)` removed; replaced with `@Binding var document: WhitespaceDocument`.
- Custom `activeText` `Binding<String>` removed; we pass `$document.text` straight to the editor.
- `.onChange(of: fileStore.activeBuffer?.text)` autosave block deleted — `DocumentGroup` autosaves automatically.
- `.onAppear { if fileStore.buffers.isEmpty { fileStore.newBuffer() } }` deleted — `DocumentGroup` always opens with a document.
- Save/Open/New callbacks now dispatch via standard `NSDocument` / `NSDocumentController` action selectors through the responder chain (the same actions the menu items invoke).

- [ ] **Step 2: Build**

mcpbridge: `BuildProject` then `XcodeListNavigatorIssues`.
Expected: errors only in `CommandPaletteView.swift` (still references `FileStore`).

Do NOT commit yet.

---

## Task 6: Strip buffer switching from `CommandPaletteView`

**Files:**
- Modify: `Sources/Whitespace/CommandPalette/CommandPaletteView.swift`

- [ ] **Step 1: Read the full current file**

Run: `Read /Users/benji/Code/Whitespace/.claude/worktrees/frosty-rubin-5724f1/Sources/Whitespace/CommandPalette/CommandPaletteView.swift`
This is needed because the rewrite removes the buffer-list section and the file isn't included verbatim above.

- [ ] **Step 2: Replace `FileStore` usage with `NSDocumentController` actions**

Goal of the edit:
- Remove `@Environment(FileStore.self) private var fileStore`.
- Remove the `filtered: [FileBuffer]` computed property and the buffer-row list section.
- Remove `switchTo(buffer:)`.
- The two static actions ("New", "Open…") become:
  ```swift
  Button("New Document") {
      dismiss()
      NSApp.sendAction(#selector(NSDocumentController.newDocument(_:)), to: nil, from: nil)
  }
  Button("Open File…") {
      dismiss()
      NSApp.sendAction(#selector(NSDocumentController.openDocument(_:)), to: nil, from: nil)
  }
  ```
- The palette becomes: a search field at top, the two action rows below, filtered by `query`.

If after the edits the palette is reduced to two static actions and feels degenerate, that's acceptable for this plan — UX redesign of the palette is a separate concern. The ⌘P chord still toggles it.

- [ ] **Step 3: Build**

mcpbridge: `BuildProject` then `XcodeListNavigatorIssues`.
Expected: clean build (warnings about unused symbols in `FileStore.swift` / `FileBuffer.swift` are fine — they get deleted next).

Do NOT commit yet — there's still dead `FileStore` code.

---

## Task 7: Delete `FileStore`, `FileBuffer`, and their tests

**Files:**
- Delete: `Sources/Whitespace/Files/FileStore.swift`
- Delete: `Sources/Whitespace/Files/FileBuffer.swift`
- Delete: `Tests/WhitespaceTests/FileStoreTests.swift`
- Delete: `Tests/WhitespaceTests/FileBufferTests.swift`

- [ ] **Step 1: Confirm nothing else references them**

Run: `grep -rn "FileStore\|FileBuffer" Sources/ Tests/`
Expected: no matches. If anything matches, fix the offending file before deleting.

- [ ] **Step 2: Delete the files**

If Xcode is open, prefer mcpbridge `XcodeRM` (it removes from `project.pbxproj` too). Otherwise:
```bash
rm Sources/Whitespace/Files/FileStore.swift
rm Sources/Whitespace/Files/FileBuffer.swift
rm Tests/WhitespaceTests/FileStoreTests.swift
rm Tests/WhitespaceTests/FileBufferTests.swift
```
Then in Xcode (if open), remove the dangling references from the navigator (right-click → Delete → Remove References).

- [ ] **Step 3: Build and run all tests**

mcpbridge: `BuildProject`, then `RunAllTests`.
Headless: `mcp__xcodebuild__build_macos`, then `mcp__xcodebuild__test_macos`.
Expected: clean build, all tests pass.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: replace FileStore with native DocumentGroup + WhitespaceDocument"
```

---

## Task 8: Remove unused autosave preference

**Files:**
- Modify: `Sources/Whitespace/Preferences/PreferencesStore.swift`
- Modify: `Sources/Whitespace/Preferences/PreferencesView.swift`
- Modify: `Tests/WhitespaceTests/PreferencesStoreTests.swift`

NSDocument provides autosave automatically (every ~5 min, plus on idle / window close). The custom `autoSaveEnabled` and `autoSaveDelay` settings are dead.

- [ ] **Step 1: Remove autosave properties from `PreferencesStore`**

Delete the `autoSaveEnabled` and `autoSaveDelay` stored properties (and their UserDefaults plumbing in `init` / `didSet` / setter methods). Also remove the corresponding default-value constants if any.

- [ ] **Step 2: Remove autosave UI from `PreferencesView`**

Find the autosave toggle and delay slider (likely in the General tab) and delete those rows.

- [ ] **Step 3: Update `PreferencesStoreTests`**

Read the file: `Read /Users/benji/Code/Whitespace/.claude/worktrees/frosty-rubin-5724f1/Tests/WhitespaceTests/PreferencesStoreTests.swift`
Remove any test that asserts on `autoSaveEnabled` or `autoSaveDelay`.

- [ ] **Step 4: Build and run all tests**

mcpbridge: `BuildProject` then `RunAllTests`.
Expected: clean build, all tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: remove custom autosave preference (NSDocument handles autosave)"
```

---

## Task 9: Manual verification of the document flow

This is a manual smoke test — the kind of thing automated tests cannot verify. Do not skip; do not claim done without running through it.

- [ ] **Step 1: Build and run the app**

mcpbridge: `BuildProject` then launch from Xcode (`Cmd+R` in the IDE) — `BuildProject` does not run the app. Headless: `mcp__xcodebuild__build_run_macos`.

- [ ] **Step 2: Walk through the golden path**

Verify each of the following — write down the result for each:

1. App launches with a blank "Untitled" document window.
2. Type some text → window title shows the dirty indicator (the small dot in the close button).
3. ⌘S → save panel appears, with "Plain Text" and "Markdown Document" in the file format popup.
4. Save as `.txt` → file appears on disk; dirty indicator clears.
5. ⌘N → a *new* window opens (this is `DocumentGroup` behavior, not in-window buffer switching).
6. ⌘O → open panel appears; both `.txt` and `.md` files are selectable.
7. Open the `.txt` file from step 4 → its window comes forward (or opens fresh).
8. File menu → "Open Recent" → the file from step 4 is listed.
9. Create a `.md` file: ⌘N, type `# Heading\n\nBody.`, ⌘S, choose Markdown format → file saves with `.md` extension.
10. Reopen the `.md` file → contents render in the editor verbatim (no markdown rendering yet — that's a separate feature).
11. Open a non-UTF8 text file (e.g. one saved as Latin-1 with `iconv -f utf-8 -t iso-8859-1 input.txt > out.txt`) → opens without error, contents are correct.
12. ⌘Z after typing → undo works (NSDocument's undo manager wired automatically).

- [ ] **Step 3: Document any failures**

If any step above fails, do not proceed to Task 10. Diagnose using `GetConsoleOutput` (mcpbridge) or the Xcode console. Common issues:
- File format popup missing → `writableContentTypes` not declared.
- `.md` files not openable → Info.plist `LSItemContentTypes` mismatch with `UTImportedTypeDeclarations` identifier.
- Crash on launch → `DocumentGroup` `newDocument:` signature mismatch.

- [ ] **Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: <describe the issue>"
```

If no fixes were needed, skip this step.

---

## Task 10: Add Markdown to default save type & polish

**Files:**
- (May modify) `Sources/Whitespace/Files/WhitespaceDocument.swift`

- [ ] **Step 1: Verify the save panel default**

In Task 9 step 9, check whether the save panel's *default* selected file format is whatever the document was opened as. SwiftUI's `DocumentGroup` should pick the first entry in `writableContentTypes` for new documents. We currently order `[.plainText, markdownType]` so new docs default to plain text — which is correct.

- [ ] **Step 2: Add a regression test for default content type**

```swift
func testWritableContentTypesPlainTextFirst() {
    XCTAssertEqual(WhitespaceDocument.writableContentTypes.first, .plainText)
    XCTAssertTrue(WhitespaceDocument.writableContentTypes.contains(WhitespaceDocument.markdownType))
}

func testReadableContentTypesIncludesMarkdown() {
    XCTAssertTrue(WhitespaceDocument.readableContentTypes.contains(WhitespaceDocument.markdownType))
    XCTAssertTrue(WhitespaceDocument.readableContentTypes.contains(.plainText))
}
```

Add these to `WhitespaceDocumentTests.swift`.

- [ ] **Step 3: Run all tests**

mcpbridge: `RunAllTests`. Expected: all green.

- [ ] **Step 4: Commit**

```bash
git add Tests/WhitespaceTests/WhitespaceDocumentTests.swift
git commit -m "test: lock in plain-text default and markdown availability"
```

---

## Task 11: Final build, test, and PR

- [ ] **Step 1: Clean build**

mcpbridge: `BuildProject` (after Xcode → Product → Clean Build Folder if anything looks off).
Headless: `mcp__xcodebuild__clean` then `mcp__xcodebuild__build_macos`.
Expected: zero warnings, zero errors.

- [ ] **Step 2: Full test run**

mcpbridge: `RunAllTests`. Expected: all green.

- [ ] **Step 3: Push the branch**

```bash
git push -u origin feat/nsdocument-markdown
```

- [ ] **Step 4: Open the PR**

```bash
gh pr create --title "Migrate to DocumentGroup; add Markdown support" --body "$(cat <<'EOF'
## Summary
- Replaces hand-rolled FileStore/FileBuffer with native SwiftUI DocumentGroup + FileDocument.
- Each open file is its own window (standard macOS document model).
- Adds Markdown (`.md`, `.markdown`, `.mdown`) as a registered, openable, saveable document type.
- Removes custom autosave preference — NSDocument handles autosave automatically.
- Picks up free behavior: Recent Files menu, dirty indicator in titlebar, version browser, encoding sniffing on open, security-scoped bookmarks for sandboxed file access.

## Test plan
- [x] Unit tests for WhitespaceDocument (read UTF-8, read Latin-1 fallback, read Markdown, roundtrip both types)
- [x] Manual smoke test of the full document flow (Task 9 checklist)
- [x] Clean build, all tests green

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-Review Notes

Spec coverage check:
- NSDocument migration → Tasks 2–8.
- Markdown type registration → Tasks 1, 3, 9, 10.
- Removal of dead state (FileStore, FileBuffer, autosave prefs) → Tasks 7, 8.
- Verification → Task 9 (manual) + Tasks 2 / 10 (automated).

No placeholders. No "TODO" / "TBD". Code in every code step. Type names consistent (`WhitespaceDocument`, `markdownType`, `text`, `contentType` used identically across tasks). File paths are absolute or workspace-relative as appropriate.

Out of scope (separate plans, not in this one):
- Markdown *rendering* (formatted display, syntax highlighting). Right now `.md` files just edit as raw text.
- Command Palette redesign (the post-Task-6 palette is degenerate; that's a UX project).
- Insertion-indicator hack and keyCode-based shortcut dispatch in `ZenTextView` (separate audit follow-ups).
