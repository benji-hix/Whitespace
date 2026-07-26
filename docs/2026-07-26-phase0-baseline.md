# Phase 0 baseline — 2026-07-26

Recorded on branch `salvage/worktree-harvest`, branched from `main` at `d1185a5`.
Working tree carried no source modifications; only untracked `docs/` files.

## Command

```bash
xcodebuild test -project Whitespace.xcodeproj -scheme Whitespace -configuration Debug -destination 'platform=macOS'
```

Xcode 26.6 (17F113). Xcode.app not running — `xcodebuild` from the shell, since
XcodeBuildMCP has only the `simulator` workflow enabled and exposes no `*_macos` tools.

## Result

```
** BUILD SUCCEEDED **

Test Suite 'All tests' passed at 2026-07-26 13:08:13.841.
	 Executed 96 tests, with 0 failures (0 unexpected) in 0.097 (0.155) seconds

** TEST SUCCEEDED **
```

96 tests, 0 failures — matches the figure in the implementation plan.

## Warnings

Zero warnings attributable to project source. The four `warning:` lines in the log are
toolchain noise: one AppIntents metadata skip and three XCTest framework binary-parse
warnings from Xcode's own bundled frameworks.

The two Swift 6 warnings the plan's Phase 6.5 expects at `WhitespaceApp.swift:19` did
not appear. This was an incremental build, which does not re-emit diagnostics for files
it did not recompile — so their absence here is *not* evidence they are fixed.
[unverified] Phase 6.5 should confirm against a clean build.

## Salvaged patches

Both diffs below were the only content in the repository not reachable from `main`.
Neither is applied — Phases 2 and 5 own them.

| Patch | Source worktree | Owner |
|---|---|---|
| `2026-07-26-caret-baseline-ensureParagraphLayout.patch` (94+/3-) | `.claude/worktrees/frosty-rubin-5724f1` | Phase 2 |
| `2026-07-26-dark-theme-textcolor.patch` (1+/1-) | `.claude/worktrees/distracted-ritchie-1ce181` | Phase 5 |

Each patch file's base blob differs from `main`'s blob for the same file, so neither
applies cleanly with `git apply`. Provenance headers in the patch files record the base
commit and both blob hashes; try `git apply -3` first, then hand-port.

With these committed, the worktrees, their branch tips, and the stash hold nothing
unique and can be destroyed (Phase 7).
