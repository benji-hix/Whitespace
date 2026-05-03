# Whitespace — Claude Code Guidelines

## Project

macOS writing app (SwiftUI + AppKit). Single target, no iOS/tvOS/watchOS.
Project file: `Whitespace.xcodeproj` · Sources: `Sources/Whitespace/` · Tests: `Tests/WhitespaceTests/`

---

## MCP Tool Selection

Two MCP servers are configured. Pick the right one — they are complementary, not interchangeable.

### Apple Xcode MCP (`xcrun mcpbridge`) — requires Xcode running

| Use it for | Tool |
|---|---|
| Searching Apple docs and WWDC transcripts | `DocumentationSearch` |
| Rendering a SwiftUI preview to verify UI | `RenderPreview` |
| Running a Swift snippet quickly without a full build | `ExecuteSnippet` |
| Live Xcode analyzer diagnostics (retain cycles, warnings) | `XcodeRefreshCodeIssuesInFile`, `XcodeListNavigatorIssues` |
| Reading/writing/moving project files | `XcodeRead`, `XcodeWrite`, `XcodeUpdate`, `XcodeGrep`, etc. |

**Critical:** If Xcode is not running, all `mcpbridge` calls fail. Check with `XcodeListWindows` first. Fall back to XcodeBuildMCP for builds if Xcode is unavailable.

### XcodeBuildMCP (`mcp__xcodebuild__*`) — standalone, no Xcode process needed

| Use it for | Notes |
|---|---|
| Building and running the macOS app | Use `macos` workflow tools — this is a macOS app, not iOS |
| Running the test suite | `test` in `macos` workflow |
| LLDB debugging (breakpoints, variables, stack traces) | `debugging` workflow — must be enabled |
| UI automation (tap, type, swipe, accessibility tree) | `ui-automation` workflow — must be enabled |
| Code coverage reports | `get-coverage-report`, `get-file-coverage` |
| Any headless / CI context | Xcode process not required |

**Workflow config:** Only the `simulator` workflow is enabled by default. For this macOS-only project, ensure the `macos` workflow is enabled. The `simulator` workflow tools do not apply here.

### Either works for

- Building the project and reading structured error output
- Listing schemes and discovering project structure

---

## Build & Verify Loop

1. Edit source files
2. Build with XcodeBuildMCP (`macos` workflow `build` or `build-and-run`)
3. Check for errors — use `XcodeListNavigatorIssues` if Xcode is open for richer diagnostics
4. For UI changes: use `RenderPreview` (Apple MCP) to verify SwiftUI previews before claiming done

Do not claim a task is complete without running a build.

---

## Coding Conventions

- No comments unless the WHY is non-obvious
- No error handling for impossible cases — trust Swift's type system and framework guarantees
- Validate only at system boundaries (user input, file I/O)
- Prefer editing existing files over creating new ones
- No backwards-compat shims for removed code
