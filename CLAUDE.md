# Whitespace

A minimalist macOS writing app: one colour, centred text, no visible chrome. It is a personal
tool whose whole value is feel, so polish and data safety outrank features.

AppKit `NSDocument` shell around an `NSTextView` on TextKit 2: the document owns the text
storage, window controllers build the windows, `MainMenu.xib` holds the menu bar, and the
SwiftUI views (canvas, palette, shortcut overlay, Settings) are hosted inside.
macOS 26.0+, Swift 6 language mode, no third-party dependencies, one app target plus a hosted
XCTest bundle. `ARCHITECTURE.md` is the design record and `DESIGN.md` the product philosophy;
read both before structural or UI work, and update `ARCHITECTURE.md` in the same change when
the code stops matching it.

## What matters here

- **Nothing but the words is visible while writing.** Every feature is keyboard-reachable and
  stays hidden until summoned. A feature whose value is "lets the user fiddle with
  presentation" is the wrong feature.
- **Never risk the user's text.** Any change to load, save, autosave or file handling comes
  with a test showing content survives the round trip.
- **Done means observed.** A change is finished when the build is clean, the full suite passes,
  and anything visible has been seen working in the running app. Offscreen tests cannot
  reproduce TextKit 2 layout timing, so a green suite alone does not prove an editor change.
- **Smallest change that solves the problem.** No new dependencies, and no abstraction with a
  single implementation, without saying why.

## Workflow

This repo follows the standard team flow even though it has one owner, so the habits transfer.

- `main` always builds and passes. Nothing is committed to it directly.
- Each change gets a short-lived branch off the latest `main`: `feat/`, `fix/`, `chore/`,
  `docs/` or `refactor/` plus a few words, e.g. `fix/dark-launch-colour`.
- Commits are one concern each with a conventional prefix (`feat:`, `fix:`, `chore:`, `docs:`,
  `test:`, `refactor:`). The message says why, since the diff already says what.
- Open a pull request with `gh pr create`. The description covers what changed, why, and how
  it was verified, with a screenshot for anything visible. The PR is where review happens, so
  keep it small enough to read in one sitting; split unrelated work into separate PRs.
- The owner reviews and squash-merges, then the branch is deleted. Merging is the owner's
  call, never the agent's.
- When explaining a step of this flow, say what a team would use it for; the owner is
  learning it.

## Build, test, run

Plain `xcodebuild` is the baseline and needs nothing else running. Verified 2026-11-19 on
Xcode 27.2: 197 tests, 0 failures, about 20 s of test time (`TypewriterRecenterTests` is
nearly all of it).

```bash
DD=/tmp/whitespace-dd   # explicit DerivedData keeps dev builds away from the default folder

xcodebuild -project Whitespace.xcodeproj -scheme Whitespace -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath $DD build

xcodebuild -project Whitespace.xcodeproj -scheme Whitespace \
  -destination 'platform=macOS' -derivedDataPath $DD test
# one class: append  -only-testing:WhitespaceTests/WhitespaceDocumentTests

open -n $DD/Build/Products/Debug/Whitespace.app
```

Installing to `/Applications` is a Release build plus `ditto`; see `docs/build-and-install.md`.

`CoreSimulator is out of date`, `appintentsmetadataprocessor` and `com.apple.linkd.autoShortcut`
lines in the output are noise for this macOS-only app.

### Xcode's own agent tools

Xcode ships an MCP bridge, `xcrun mcpbridge`, registered for this repo in `.mcp.json` as the
`xcode` server. It talks to the running Xcode, so it needs Xcode open with this project
(`XcodeListWorkspaces` to check, `XcodeOpenWorkspace` to open it).

- Use it for what `xcodebuild` cannot do: `DocumentationSearch` for current Apple APIs,
  `RenderPreview` for SwiftUI views, `XcodeRefreshCodeIssuesInFile` for live diagnostics,
  `RunProject` with `GetConsoleOutput` for runtime logs, `InvokeDebuggerCommand` for LLDB.
  Building and testing work through either route.
- Leave its project-mutating tools alone (`UpdateTargetBuildSetting`, `AddInfoPlist`,
  `AddEntitlement`, `XcodeNewTarget`): they edit the generated project, and the next
  `xcodegen generate` discards the edit. Make those changes in `project.yml`.
- If its tools are absent or Xcode is closed, carry on with `xcodebuild`.
- Opening Xcode or launching the app can take focus from whatever the owner is doing. Open in
  the background (`open -g`) and say so first when something must come to the front.
- `xcrun mcpbridge run-agent` (alias `xcrun agent`) launches Xcode and waits on it, even with
  `--dry-run`. Do not run it from a non-interactive shell.

For Apple API questions, check current documentation before relying on memory: AppKit's
document and window APIs and SwiftUI's hosting APIs change between releases, and this project
targets the newest OS. Check a delegate method exists in the SDK headers before relying on it:
UIKit-only names compile on macOS and are never called.

## Project file

`project.yml` (XcodeGen) is the source of truth. `Whitespace.xcodeproj` and
`Sources/Whitespace/App/Info.plist` are generated and committed.

- After adding or removing a file, or changing a setting: `xcodegen generate`, then commit the
  regenerated project with the change.
- Do not hand-edit `project.pbxproj` or accept Xcode's "Update to recommended settings"; the
  next generate discards both. Settings and Info.plist keys go in `project.yml`.
- `Sources/Whitespace/App/MainMenu.xib` is a source file, not generated: edit it directly.

## Things that will bite

- **Shared preferences.** Debug builds, the hosted test bundle and the installed
  `/Applications` copy share bundle id `com.benji.Whitespace`, so they share the owner's real
  UserDefaults. Tests use `UserDefaults(suiteName:)` and wipe it in tearDown, never `.standard`.
  Quit the installed app before launching a Debug build, or you may be looking at the wrong copy.
  The test host is the real app, so it shares the owner's saved windows and autosave folder
  too: the scheme passes `-ApplePersistenceIgnoreState YES` to tests, and any document a test
  edits gets a temporary file URL and is closed in teardown.
- **The shell is hand-built AppKit.** Menus, windows and restoration are ours to keep correct;
  nothing appears for free. After changing the menu bar, diff it over accessibility against the
  previous one. AppKit rewrites a nib item's ⌃⌘F to the Globe key, which is why the full-screen
  chords are set in code. `ARCHITECTURE.md` §1 and §4 have the details; read them before
  touching launch, window chrome, document types or the save path.
- **Edit counting.** NSDocument marks a document edited only through undo groups. A new edit
  path must register undo, or call `updateChangeCount` if it cannot (attribute-only edits do).
  Every save breaks the editor's typing coalescing, or typing after a save is never counted.
  Tests have no event loop, so they frame each event with an explicit undo group
  (`WhitespaceDocumentShellTests`).
- **Save path testing.** Drive `data(ofType:)` and `encodedData(for:)` directly; for saves,
  autosave and revert, open a document from a temporary file and call
  `save(to:ofType:for:)` or `revert(toContentsOf:ofType:)`. The flatten warning is asked
  there, so replace `askBeforeFlattening` and set `conversionDefaults` to a test suite.
- **Concurrency.** Swift 6 strict checking with nonisolated default isolation; mark UI types
  and UI tests `@MainActor` explicitly.
- **Driving the app.** Synthetic keystrokes are unreliable on this Mac (keyboard remappers);
  prefer menu clicks through accessibility. Capture only the app's own window, never the full
  screen, which would include the owner's other windows.
- **Open Recent is always empty on this Mac.** System Settings keeps no recent items, so an
  empty menu here is not a bug; check recents in a scratch app with its own
  `NSRecentDocumentsLimit`.
- **Known gaps** are listed in `ARCHITECTURE.md` §5. Add to it or strike from it as they change.

## Code style

- Comments only where the reason is not obvious from the code.
- No handling for cases the type system or framework already rules out; validate at the
  boundaries (file I/O, user input).
- Decision-shaped editor logic (geometry, normalisation, serialisation) lives in a pure type
  with value inputs and unit tests; AppKit and TextKit calls stay in the view.
- XCTest only. There is no linter and no CI, so the two commands above are the gate.
