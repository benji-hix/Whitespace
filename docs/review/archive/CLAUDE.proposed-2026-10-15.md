> **Superseded 2026-11-17.** Archived for history only. The live file is `CLAUDE.md` at the repo root; do not follow this one.

# Whitespace

Minimalist macOS writing app: one colour, centred text, no visible chrome. SwiftUI shell
(`DocumentGroup` + `Settings`) around an AppKit `NSTextView` (TextKit 2). macOS 26.0+,
Swift 6 language mode, no third-party dependencies. Remote: github.com/benji-hix/Whitespace.

## Rules
- Core principle: while writing, nothing but the words is visible. Every feature must be keyboard-reachable and stay invisible until summoned.
- Never risk user text. Any change to save, load, autosave or file handling needs a test proving no data loss.
- One branch per change (feat/, fix/, chore/). Never commit to main. Open PRs with gh; I squash-merge.
- Nothing is done until verified: the build passes, tests pass, and visible changes are checked in the running app with screenshots as evidence.
- Prefer the smallest change that solves the problem. Don't add dependencies or abstractions without saying why.
- When reporting several items I might act on, label groups with letters and items with numbers (A1, A1.1). Always pair an ID with a short label when referring back, and keep IDs stable when revising.

## Commands (verified 2026-10-15, Xcode 27.0, from a clean clone)
```bash
DD=/tmp/whitespace-dd   # explicit DerivedData; avoids the Whitespace-* glob ambiguity
# build (~10 s clean)
xcodebuild -project Whitespace.xcodeproj -scheme Whitespace -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath $DD build
# test (131 XCTest cases, ~17 s; TypewriterRecenterTests alone is ~15 s)
xcodebuild -project Whitespace.xcodeproj -scheme Whitespace \
  -destination 'platform=macOS' -derivedDataPath $DD test
# one class:  add  -only-testing:WhitespaceTests/WhitespaceDocumentTests
# run
open -n $DD/Build/Products/Debug/Whitespace.app
# install to /Applications: see docs/build-and-install.md (Release + ditto)
```
- "CoreSimulator is out of date" lines from xcodebuild are noise on this Mac; ignore them.
- Neither Xcode MCP server is guaranteed to be connected; plain `xcodebuild` always works.

## Project file
- `project.yml` (XcodeGen 2.45) is the source of truth. `Whitespace.xcodeproj` and
  `Sources/Whitespace/App/Info.plist` are generated *and committed*. After adding/removing
  files or changing settings: `xcodegen generate`, and commit both.
- Never hand-edit `project.pbxproj` or accept Xcode's "Update to recommended settings";
  the next `xcodegen generate` would discard it. Put settings in `project.yml`.
- `CFBundleShortVersionString`/`CFBundleVersion` are literals in Info.plist; bumping
  `MARKETING_VERSION` alone does not change the shown version.

## Gotchas
- Debug builds, the hosted test bundle and the installed /Applications copy share bundle
  id `com.benji.Whitespace`, so they share the owner's real UserDefaults. Tests must use
  `UserDefaults(suiteName:)` (see PreferencesStoreTests), never `.standard`.
- Quit /Applications/Whitespace before launching a Debug build, or you may test the wrong copy.
- `fileWrapper(configuration:)` can't be called from tests (no public `WriteConfiguration`
  init); test save paths through `WhitespaceDocument.encodedData(for:)` and
  `PlainTextConversionGate.approvedData(...)`, writing to `NSTemporaryDirectory()`.
- Concurrency: Swift 6 strict checking, but default isolation is *nonisolated*; annotate
  `@MainActor` explicitly on UI types and UI tests.
- Screenshots: capture only the app window (`screencapture -l <windowID>`), never the full
  screen; it exposes the owner's other windows.
- Known gaps live in ARCHITECTURE.md §5; update it when you close or add one.

## Conventions
- Conventional commits (`feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`).
- XCTest only (no Swift Testing yet). No linter, no CI: the build+test commands above are the gate.
- Comments only for non-obvious WHY. No defensive handling for impossible cases; validate at
  boundaries (file I/O, user input).
