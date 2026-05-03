# Whitespace — Claude Code Guidelines

## Project

macOS writing app (SwiftUI + AppKit). Single target, no iOS/tvOS/watchOS.
Project file: `Whitespace.xcodeproj` · Sources: `Sources/Whitespace/` · Tests: `Tests/WhitespaceTests/`

---

## MCP Tool Selection

Two MCP servers are configured. They overlap on builds and tests; the tables below give the tiebreaker. **When Xcode is open, prefer mcpbridge** — it sees the live workspace state, produces richer diagnostics, and shares a build cache with the IDE. Fall back to XcodeBuildMCP when Xcode is closed or in headless/CI contexts.

### Apple Xcode MCP (`xcrun mcpbridge`) — preferred when Xcode is running

Verify Xcode is running with `XcodeListWindows` before any other call. If it returns empty, switch to XcodeBuildMCP.

| Use it for | Tool |
|---|---|
| Building the project (uses Xcode's build system) | `BuildProject` |
| Running tests | `RunAllTests`, `RunSomeTests`, `GetTestList` |
| Reading build output and runtime logs | `GetBuildLog`, `GetConsoleOutput` |
| Inspecting target build settings | `GetTargetBuildSettings` |
| Live Xcode analyzer diagnostics (retain cycles, warnings) | `XcodeRefreshCodeIssuesInFile`, `XcodeListNavigatorIssues` |
| Searching Apple docs and WWDC transcripts | `DocumentationSearch` |
| Rendering a SwiftUI preview to verify UI | `RenderPreview` |
| Running a Swift snippet quickly without a full build | `ExecuteSnippet` |
| Reading/searching/editing project files | `XcodeRead`, `XcodeGrep`, `XcodeGlob`, `XcodeLS`, `XcodeWrite`, `XcodeUpdate`, `XcodeInsertFile`, `XcodeGetCurrentFile` |
| File/directory operations within the project | `XcodeMV`, `XcodeRM`, `XcodeMakeDir` |

### XcodeBuildMCP (`mcp__xcodebuild__*`) — fallback / headless

Use the `macos` workflow tools (`mcp__xcodebuild__*_macos`). The `simulator` workflow does NOT apply — this is not an iOS project.

| Use it for | Notes |
|---|---|
| Building / running / testing the macOS app | `build_macos`, `build_run_macos`, `test_macos`, `launch_macos`, `stop_macos` |
| Code coverage reports | `get_coverage_report`, `get_file_coverage` |
| Bundle paths and metadata | `get_macos_app_path`, `get_macos_bundle_id`, `show_build_settings` |
| Any headless / CI context | No Xcode process required |

**Workflow config (one-time setup, important):** by default XcodeBuildMCP only enables the `simulator` workflow, so none of the `*_macos` tools above will be loaded. Enable the `macos` workflow (and optionally `xcode-ide` for live-Xcode integration) in your XcodeBuildMCP config: see https://github.com/getsentry/XcodeBuildMCP/blob/main/docs/CONFIGURATION.md. Until that's done, XcodeBuildMCP cannot build or test this project — `mcpbridge` is the only path.

### Tools NOT available from either MCP

- **LLDB debugging on the macOS app.** XcodeBuildMCP's `debugging` workflow is iOS-simulator-only ("Attach LLDB to sim app"). For native macOS LLDB, attach via `lldb` from the Bash tool, or step through inside Xcode itself.
- **macOS UI automation.** XcodeBuildMCP's `ui-automation` workflow is simulator-only (simulator gestures, sim hardware buttons). For driving the running macOS app, use the `computer-use` MCP, AppleScript via `osascript`, or XCTest UI tests run through `RunSomeTests`/`test_macos`.

---

## Build & Verify Loop

1. Edit source files (prefer `XcodeWrite`/`XcodeUpdate` if Xcode is open so the project model stays in sync; otherwise use the local Edit/Write tools).
2. Build:
   - **Xcode open:** `BuildProject`, then `GetBuildLog` for full output and `XcodeListNavigatorIssues` for the structured warnings/errors view.
   - **Xcode closed:** `mcp__xcodebuild__build_macos` (requires `macos` workflow enabled).
3. If the build succeeds, run the relevant tests: `RunSomeTests` (scoped) or `RunAllTests`. Read failures with `GetConsoleOutput`.
4. For UI changes: render the SwiftUI preview with `RenderPreview` before declaring done.
5. For runtime issues: `GetConsoleOutput` after launching captures stdout/stderr and os_log output from the running app.

Do not claim a task is complete without a clean build AND a passing test run.

---

## Coding Conventions

- No comments unless the WHY is non-obvious
- No error handling for impossible cases — trust Swift's type system and framework guarantees
- Validate only at system boundaries (user input, file I/O)
- Prefer editing existing files over creating new ones
- No backwards-compat shims for removed code
