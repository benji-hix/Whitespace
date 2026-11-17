# Whitespace — orientation (2026-10-15)

Read-only review at `5cc693f` (tag `pre-review-2026-10`, last commit 2026-07-27). The only files
written are this one and `docs/review/CLAUDE.proposed.md` (see Q1 below for why it isn't at the root yet).
Input read first: `docs/review/inputs/my-notes.md`.

## 1. Stack

| | |
|---|---|
| Language | Swift 6 language mode (`SWIFT_VERSION 6.0` on both targets). Strict concurrency comes with that mode; default isolation is nonisolated (not MainActor-by-default) |
| UI | SwiftUI shell (`DocumentGroup` + `Settings` scene) around an AppKit `NSTextView` subclass on **TextKit 2** |
| Min macOS | **26.0**. `project.yml` and `project.pbxproj` agree |
| Toolchain on this Mac | Xcode 27.0 (27A266a), macOS 27.2. The project was last "upgraded" for Xcode 26 (`LastUpgradeCheck 2600`) |
| Project generation | **XcodeGen 2.45.4** from `project.yml`. The `.xcodeproj` and `Info.plist` it generates are committed. Running `xcodegen generate` on a clean clone reproduces the committed project exactly (verified, no diff) |
| Dependencies | **None.** No SPM, CocoaPods or Carthage. Bundled resources are the Crimson Pro fonts (4 TTFs) |
| Signing | Ad-hoc (`Signature=adhoc`, no team). Not sandboxed, no entitlements, no hardened runtime |
| Tests | XCTest only: 18 files, 131 tests, all hosted in the app. No UI tests and no Swift Testing |
| Lint / CI | None (no SwiftLint, swift-format, GitHub Actions, Xcode Cloud or Makefile) |
| Remote | `github.com/benji-hix/Whitespace`; local `main` = `origin/main` |

## 2. Architecture sketch

```
WhitespaceApp (@main)
├─ DocumentGroup(newDocument:) ── WhitespaceDocument : FileDocument  { runs: [StyledRun], contentType }
│    └─ CanvasView ── GrainBackground + EdgeFade mask + centred column
│         └─ ZenTextViewRepresentable ── NSScrollView ── ZenTextView (NSTextView, TextKit 2)
│              (typewriter scroll, custom caret, ⌘B/⌘I, rebindable deletes, paste normalising)
├─ Settings scene ── PreferencesView ── PreferencesStore / ThemeStore / KeybindingStore (UserDefaults)
├─ Overlays per window: CommandPaletteView (⌘P), ShortcutOverlayView (⌘/)
└─ LaunchDelegate: swaps the launch Open panel for a blank document
```

- **Create.** `newUntitled()` picks `.md` or `.txt` from `whitespace.prefs.newDocumentType`. The order of `readable`/`writableContentTypes` matters, because SwiftUI uses the first entry.
- **Load.** Tries UTF-8, then falls back to ISO Latin-1. Markdown is decoded inline-only into `StyledRun`s (bold and italic) by `MarkdownText.decode`.
- **Save.** `fileWrapper` → `encodedData(for:)` → `PlainTextConversionGate`. The gate warns before bold/italic is flattened into a `.txt` file. It blocks the background writer thread with `DispatchQueue.main.sync` plus a modal `NSAlert`. Files are always written as UTF-8.
- **Autosave, versions, revert.** Left entirely to SwiftUI's private NSDocument machinery. There is no custom code and no tests for them.
- **Render.** Horizontal centring is a SwiftUI `HStack` with a max column width. Vertical centring sets `textContainerInset.height` to half the viewport and recomputes it on resize.
- **Theme.** Two app-owned themes (`.paper`, `.dark`) with hard-coded `NSColor`s. The theme does **not follow the system appearance** and is toggled with ⌘⇧D. Colours cross-fade through a hand-rolled ~60 fps Task loop.
- **Settings.** Plain UserDefaults behind `@Observable` stores; `@AppStorage` isn't used.
  - Keys `whitespace.prefs.*`: fontSize, lineHeight, columnWidth, scrollSpeed, newDocumentType, shortcutsAutoDismiss*, suppressPlainTextConversionWarning.
  - Also `whitespace.theme` and `whitespace.keybinding.<action>`.
- **Shortcuts.**
  - Menu: ⌘⇧D (theme), ⌘P (palette), ⌘/ (overlay), ⌘⇧M (maximise), ⌃⌘F (fullscreen).
  - Editor: ⌘B, ⌘I, ⌘=, ⌘−.
  - Rebindable deletes: ⌥⌫, ⌥⌦, ⌘⌫, ⌘⌦, ⌃K, ⌃D.

`ARCHITECTURE.md` is detailed and mostly accurate. Where it disagrees with the code:
- It describes how window chrome is re-asserted, but the code skips fullscreen.
- It says ⌘B/⌘I can't be menu items, which is not true.

## 3. Build / run / test: commands and real results

Run from a **fresh `git clone`** into a scratch directory, with an explicit `-derivedDataPath`. That kept the working tree and `~/Library/Developer/Xcode/DerivedData` untouched.

```bash
DD=/tmp/whitespace-dd
xcodebuild -project Whitespace.xcodeproj -scheme Whitespace -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath $DD build
xcodebuild -project Whitespace.xcodeproj -scheme Whitespace \
  -destination 'platform=macOS' -derivedDataPath $DD test
open -n $DD/Build/Products/Debug/Whitespace.app
```

| Step | Result |
|---|---|
| Debug build (clean) | `** BUILD SUCCEEDED **` in 9.5 s wall, **0 compiler warnings** |
| Release build | `** BUILD SUCCEEDED **`, 0 warnings, `Signature=adhoc` |
| Tests | `** TEST SUCCEEDED **`: **131 tests, 0 failures**, 16.8 s. `TypewriterRecenterTests` (5 tests) takes 14.8 s of that |
| Run | Launches into one blank, chrome-less "paper" window (system was in Dark mode, theme pref = `paper`). Quit cleanly |
| `xcodegen generate` | Output is identical to the committed project |

Noise in the output (none of it is a failure):
- `CoreSimulator is out of date (1166 < 1171.7)`: Xcode 27 is newer than this Mac's simulator framework. It doesn't matter for a macOS-only build.
- `appintentsmetadataprocessor: Metadata extraction skipped`: expected, since the app uses no App Intents.
- `com.apple.linkd.autoShortcut` connection errors while the test host runs.

Install procedure: `docs/build-and-install.md` (Release build, `ditto` to `/Applications`). Its `DerivedData/Whitespace-*` glob breaks if more than one `Whitespace-*` folder exists.

## 4. Files that matter

Paths are under `Sources/Whitespace/` unless noted.

| File | Lines | Why it matters |
|---|---|---|
| `App/WhitespaceApp.swift` | 183 | Scenes, menu commands, window-chrome hiding (`WindowStylingView`), `LaunchDelegate` |
| `Files/WhitespaceDocument.swift` | 117 | `FileDocument`: read, write, encoding fallback, content-type ordering. **Data-critical** |
| `Files/PlainTextConversionGate.swift` | 68 | Flatten-to-.txt warning; blocks the writer thread. **Data-critical** |
| `Editor/ZenTextView.swift` | 825 | The editor. Caret, typewriter scroll, keys, colours, fonts. Most-churned file (18 commits) |
| `Editor/ZenTextViewRepresentable.swift` | 157 | SwiftUI↔AppKit bridge; syncs colours, fonts and runs |
| `Editor/MarkdownText.swift` | 95 | Markdown ↔ `StyledRun` |
| `Editor/PasteNormalizer.swift` | 86 | `StyledRun` type, paste cleaning, runs → attributed string |
| `Canvas/CanvasView.swift` | 102 | Per-window layout, column width, overlays |
| `Theme/Theme.swift`, `ThemeStore.swift` | 63 / 104 | Colours and the theme transition |
| `Preferences/PreferencesStore.swift`, `PreferencesView.swift` | 129 / 360 | Settings model and UI |
| `project.yml` | — | Source of truth for the Xcode project |
| `ARCHITECTURE.md` | — | The owner's design record. §5 lists known gaps |
| `Tests/WhitespaceTests/WhitespaceDocumentTests.swift`, `PlainTextConversionGateTests.swift` | — | The only save/load coverage |

## 5. Findings worth knowing before any work

**A. Owner-reported issues: likely causes (traced in code, not yet reproduced in the app)**
- **A1 | Dark-mode text colour at launch.** In `makeNSView`, `applyColors` runs first (`ZenTextViewRepresentable.swift:36`). Then `applyFont` replaces `typingAttributes` wholesale with `[.font, .paragraphStyle]` (`ZenTextView.swift:609`), which drops `.foregroundColor`. The storage is then rebuilt from those colourless attributes (`:46`). After that the coordinator records `lastTheme`, so colours are never re-applied until the next theme toggle. The same wipe happens on every font-size change.
- **A2 | Fullscreen still shows the menu bar and traffic lights.**
  - Nothing sets `NSApplication.PresentationOptions`, `window(_:willUseFullScreenPresentationOptions:)` or `.windowToolbarFullScreenVisibility`.
  - `stylingHasDrifted` returns `false` in fullscreen on purpose (`WhitespaceApp.swift:128`), because it assumes "fullscreen already hides the chrome". It doesn't: AppKit shows the titlebar and menu bar on hover.

**B. Data-safety risks (no test covers these)**
- **B1 | Latin-1 fallback always succeeds.** A UTF-16 file, or any other non-UTF-8 file, opens as mojibake and is re-saved as UTF-8 (`WhitespaceDocument.swift:68`).
- **B2 | Markdown is silently lossy on round-trip.** Links, code spans, `~~`, headings and HTML are flattened on load. The next save or autosave overwrites the original without a warning. The gate only covers bold/italic → `.txt`.
- **B3 | `contentType` is fixed at init.** After a Save As from `.md` to `.txt`, the document probably still thinks it is markdown. This needs a check in the running app.
- **B4 | Deadlock risk.** `DispatchQueue.main.sync` in the gate would deadlock if the main thread ever waits synchronously on a save.
- **B5 | Untested save paths.** Autosave, revert, external file changes and `fileWrapper(configuration:)` itself are not tested. SwiftUI's `WriteConfiguration` has no public init.
- **B6 | Tests can touch real settings.** Hosted tests share bundle ID `com.benji.Whitespace`, and therefore UserDefaults, with the installed app. `WhitespaceDocumentTests` writes to `UserDefaults.standard`; it restores the value afterwards, but a crash mid-test would leave your preference changed.

**C. Small bugs noticed in passing**
- **C1 | ⌘+ doesn't work.** The shortcut overlay advertises ⌘+, but `keyDown` rejects Shift, so only ⌘= works.
- **C2 | Version numbers are hard-coded.** `Info.plist` has `CFBundleShortVersionString`/`CFBundleVersion` as literals (`1.0`/`1`), so bumping `MARKETING_VERSION` in `project.yml` (the documented workflow) changes nothing. `$(DEVELOPMENT_LANGUAGE)` is used but never defined.
- **C3 | No app icon.** `Assets.xcassets` contains no AppIcon (already listed in ARCHITECTURE.md §5).
- **C4 | Known gaps already listed in ARCHITECTURE.md §5:**
  - Open Recent stays empty.
  - The Settings window exposes no accessibility elements.
  - ⌘B/⌘I can't be undone on their own.

**D. Dated patterns (noted, not fixed)**
- **D1 | Xcode 26-era project settings.** Project-level defaults still say `SWIFT_VERSION 5.0`, `gnu++14`/`gnu11` and `COMBINE_HIDPI_IMAGES`. Newer recommended settings are missing (`ENABLE_USER_SCRIPT_SANDBOXING`, `DEAD_CODE_STRIPPING`, `ENABLE_HARDENED_RUNTIME`). Xcode 27 will offer to "update to recommended settings"; doing that in the pbxproj would be lost on the next `xcodegen generate`.
- **D2 | Imperative window chrome.** The chrome is set from a hot `NSWindow.didUpdateNotification` observer instead of `.windowStyle(.hiddenTitleBar)`, `.windowToolbarFullScreenVisibility(.onHover/.hidden)` or presentation options.
- **D3 | Colours ignore the system appearance.** The colours are hard-coded, the hand-rolled 60 fps fade loop does the animation, and the app never sets `NSAppearance`.
- **D4 | Older concurrency and timing idioms:**
  - `Task.sleep(nanoseconds:)`
  - `DispatchQueue.main.async` used to "wait for the window"
  - selector-based NotificationCenter observers
  - a `Timer` for the caret blink
  - the redundant `#available(macOS 14)` check while the deployment target is 26
- **D5 | Carbon key translation.** `ShortcutBinding.swift` uses Carbon `TISCopyCurrentKeyboardLayoutInputSource`/`UCKeyTranslate`. It still works, but it is the oldest API in the codebase.
- **D6 | ⌘B/⌘I by keyCode.** They are hard-coded keyCodes in `keyDown`, not menu commands, so they don't show up in the menu bar or in Help search.
- **D7 | Dead code.** `ZenTextView.applyTheme` (`:583`) is never called.
- **D8 | Stale repo files.** `docs/2026-07-26-*.patch` are both already applied. `mockups/whitespace-fullscreen.html` is still waiting on a decision.
- **D9 | MCP guidance points at missing tools.** The root `CLAUDE.md` is mostly MCP tool-selection guidance for servers (`mcpbridge`, XcodeBuildMCP) that weren't connected in this session. Plain `xcodebuild` did everything.

## 6. Git history in brief

There are 86 commits, all yours, from Apr 22 to Jul 27 2026, in five bursts:
1. MVP as "Folio" (Apr 22–24).
2. Rename to Whitespace and move to TextKit 2 with DocumentGroup (May).
3. Paste normalisation (early Jun).
4. An audit, then Markdown documents (Jun 10–11).
5. A polish-and-ship push ending in v1.0 (Jul 26–27).

Nothing looks abandoned:
- Every plan in `docs/` has matching commits.
- The branch, worktree and stash prune is done; only `main` remains.
- Commit prefixes are conventional, plus the non-standard `tune:` and `ship:`.
- 7 `--no-ff` merges, but much of the work went straight to main. There have never been PRs.

## 7. Open questions for you

Reply per ID, e.g. "Q1 replace, Q2 b, …".

- **Q1 | CLAUDE.md conflict.** A tracked `CLAUDE.md` already exists at the root, holding the old MCP guidance. Writing a new one there would modify an existing file, which this session wasn't allowed to do. The proposed version is at `docs/review/CLAUDE.proposed.md` (59 lines). Options:
  - (a) replace the root file with it
  - (b) merge in the old MCP section
  - (c) keep both
- **Q2 | Dark mode.** What did you mean by "the app starts in dark mode"?
  - (a) the app's own dark theme (⌘⇧D, persisted)
  - (b) macOS system appearance
  - Today the theme ignores the system. Should it follow the system by default?
- **Q3 | Fullscreen target.** What should "right" look like?
  - Menu bar fully hidden even on hover, or reachable at the top edge?
  - Traffic lights never shown?
  - Is `mockups/whitespace-fullscreen.html` still the reference?
- **Q4 | Markdown fidelity (B2).** Should opening a `.md` that contains links, headings or code be lossless on save? Options:
  - preserve the unknown syntax as literal text
  - warn before flattening
  - restrict the app to bold/italic-only markdown
- **Q5 | Non-UTF-8 files (B1).** Refuse to open them, or detect UTF-16 and other encodings properly?
- **Q6 | Export (from your notes).** Which formats matter? For example PDF, .docx, HTML, or RTF. Should export be a palette command only?
- **Q7 | VS Code-style shortcuts.** Which ones first? Line move/duplicate (⌥↑/⇧⌥↓), multi-cursor, Go to line, word/paragraph navigation, Quick Open (⌘P is already the palette)?
- **Q8 | Bundle ID isolation (B6).** OK to give Debug builds their own bundle ID (e.g. `com.benji.Whitespace.debug`)? That would keep dev runs and tests out of your real preferences and stop them colliding with the installed copy.
- **Q9 | CI.** Do you want a minimal GitHub Actions build-and-test on PRs? It fits the PR-based workflow you're moving to.
- **Q10 | Housekeeping.** Can the two applied `.patch` files and the placeholder `WhitespaceTests.swift` (`XCTAssertTrue(true)`) be deleted in a `chore/` PR?
