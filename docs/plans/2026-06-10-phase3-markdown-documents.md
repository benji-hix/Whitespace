# Phase 3 — Per-type documents: .md with formatting, .txt strictly plain

*Scoped on `fable-review-1` after R1–R8. Resolves S4 (rich text in memory, plain text on disk) with the owner's decisions locked in below. Same process rules as Phase 2: one item per commit, tests first where coverage is missing, build + full suite after each change, stop-and-revert if risk exceeds estimate.*

## Owner decisions (locked)

1. **New documents default to `.md`**, with a Settings preference to choose `.md` or `.txt` as the default for new files.
2. **Save As converting `.md` → `.txt` shows one confirmation dialog** with a "Don't show this again" suppression option.
3. **⌘B/⌘I in a `.txt` document do nothing** — no beep, no visual reaction (VS Code style).
4. **Merge/reconciliation cost of `feat/nsdocument-markdown` is accepted.**

Plus the standing design rulings: underline support is removed app-wide (markdown can't express it; nothing in the app creates it except paste); markdown syntax is a storage format only — the user always sees rendered bold/italic, never asterisks.

## Resulting model (target state)

- `WhitespaceDocument` (FileDocument) is the single document type, carrying `contentType` (.plainText or markdown) and **styled runs** rather than a plain string.
- `.txt`: editor runs `isRichText = false`; formatting chords are inert; paste strips all styling; bytes on disk == characters on screen.
- `.md`: ⌘B/⌘I work; save encodes runs → `**bold**` / `*italic*`; load parses syntax → rendered styles. Underline never round-trips.
- NSDocument/DocumentGroup native machinery replaces the hand-rolled equivalents from Phase 2 where they overlap (see supersessions table in P3.3).

## Ordered work items

Pure, conflict-free engine code first (P3.1–P3.2); the big merge next (P3.3); wiring after (P3.4–P3.5); UX last (P3.6–P3.7); docs close it out (P3.8).

### P3.1 — Markdown encoder (pure, new code, no conflicts)

`MarkdownText.encode(runs: [StyledRun]) -> String` beside `PasteNormalizer`, reusing `StyledRun`. Maps bold/italic/bold-italic to `**`/`*`/`***`; ignores the underline flag by design. Edge cases with tests: escaping literal `*` and `_` typed by the user; markdown's no-space-inside-markers rule (whitespace hoisted out of emphasis spans: `"bold "` bold → `**bold** `); emphasis runs spanning newlines (split per line); empty runs; adjacent same-style runs (already merged by `StyledRun` construction).
**Blast radius:** none — new file + test file, nothing consumes it yet (same pattern as PasteNormalizer's staged landing).
**Verify:** unit tests only; full suite stays green.

### P3.2 — Markdown decoder (reuses the paste pipeline)

`MarkdownText.decode(_ markdown: String) -> [StyledRun]` using `AttributedString(markdown:options:)` with `.inlineOnlyPreservingWhitespace` (the editor-oriented mode that keeps line breaks), bridged to `NSAttributedString` and pushed through the existing `PasteNormalizer.styledRuns` classifier — loading a file is literally the paste problem.
Round-trip property tests: `decode(encode(runs)) == runs` for representative corpora (plain prose, mixed emphasis, escaped asterisks, multi-paragraph).
**Blast radius:** none — pure code.
**Verify:** unit tests incl. round-trips; full suite green.

### P3.3 — Merge `feat/nsdocument-markdown` into `fable-review-1` (the reconciliation)

Merge the branch and resolve in favor of the DocumentGroup architecture for file/window concerns while **keeping every Phase 2 editor/UI fix**. Known collision map:

| Area | Resolution |
|---|---|
| `FileStore`/`FileBuffer` (branch deletes; R3/R5 modified) | Deleted. Native equivalents take over (below). |
| `WhitespaceApp` (both sides rewrote) | DocumentGroup scene + branch's NSDocumentController pinning, **plus** our AppDelegate-free quit handling (native), CanvasUIState env, View-menu commands, font registration. |
| `CommandPaletteView` (both sides rewrote) | Branch's action-palette model (New/Open via NSDocumentController) **re-fitted with R4's working key handling** (onSubmit, key-equivalent arrow buttons, Escape NSEvent monitor, focus return). The buffer list is gone by design — DocumentGroup is window-per-document. |
| `CanvasView` | Branch's document-binding shape + our CanvasUIState/focus-request/overlay wiring. |
| Preferences (branch removed auto-save settings) | Removed — NSDocument autosaves natively. |
| Tests | FileStore/FileBuffer/auto-save suites retire with their subjects; `WhitespaceDocumentTests` joins; all editor suites (undo, keyDown, paste, TypewriterScroll, keybindings, theme, prefs) must pass unchanged. |
| `project.pbxproj` | Never hand-merged — regenerate with `xcodegen generate`. |

**Phase 2 supersessions (expected, not regressions):** R3's untitled-save prompt, dirty-quit prompt, and per-buffer auto-save are replaced by NSDocument's native Save As flow, `reviewUnsavedDocuments`, and autosave-in-place. R5's `autoSavePolicy` closure dies with FileStore. R1's undo-clear-on-buffer-switch becomes moot (window per document). Each must be verified live in its native form before this commit closes.
**Blast radius:** the largest item — app scenes, palette, canvas, files, tests.
**Verify:** full merged suite green, then a live smoke pass: new/open/save/Save As/Open Recent, multi-window, dirty-close prompt (native), undo, ⌘P palette actions with R4 keys, ⌘/ overlay, Record button, typewriter feel.

### P3.4 — Documents carry styled runs; editor syncs attributed text for .md

`WhitespaceDocument` stores `[StyledRun]` (+ `contentType`): read = P3.2 decode (or plain-text wrap for .txt), write = P3.1 encode (or plain join for .txt). The editor binding for `.md` documents syncs **attributed** content (runs) instead of a plain `String` — the upgrade of the S3 two-sources-of-truth seam. `updateNSView` compares run arrays (Equatable) instead of strings; `textDidChange` extracts runs via the `styledRuns` classifier; the wholesale-replacement reset block (scroll anchor + undo clear + reapply) stays intact per ARCHITECTURE.md §3.4.
**Risk note: this is the riskiest item of the phase** (two-way attributed sync touches every keystroke). Characterization tests first on the run-extraction path; stop-and-revert applies.
**Blast radius:** `WhitespaceDocument`, representable, `ZenTextView` helpers.
**Verify:** unit round-trips (type styled text → runs → encode → decode → same runs); live: bold/italic survive save → close → reopen, and survive window close/reopen.

### P3.5 — Editor mode switch per content type

A `formattingEnabled: Bool` on `ZenTextView`, driven by the document's `contentType`: `.txt` → `isRichText = false`, ⌘B/⌘I branches return silently (no beep — decision 3), paste normalizes to plain (all flags dropped); `.md` → current behavior minus underline (PasteNormalizer stops preserving underline app-wide; its underline handling and tests are removed).
**Blast radius:** `ZenTextView`, `PasteNormalizer` (deletion), representable wiring, keyDown/paste tests.
**Verify:** keyDown tests for inert chords in plain mode; paste tests per mode; live: ⌘B in .txt does visibly nothing, ⌘B in .md bolds, pasted underline disappears in both.

### P3.6 — New-document default + Settings preference (decision 1)

`PreferencesStore.newDocumentType` (default markdown), persisted under `whitespace.prefs.newDocumentType`; a "New Files" picker (Markdown / Plain Text) in Settings ▸ General; `DocumentGroup(newDocument:)` consults it.
**Blast radius:** PreferencesStore (+tests), PreferencesView, WhitespaceApp.
**Verify:** prefs persistence tests; live: toggle setting, ⌘N yields each type, ⌘B inert/active accordingly.

### P3.7 — Save As conversion warning (decision 2)

When a Save As targets `.txt` from a document whose runs contain any formatting, show one `NSAlert` ("Converting to plain text removes formatting") with the native suppression checkbox ("Don't show this again"), persisted as `whitespace.prefs.suppressPlainTextConversionWarning`. No formatting present → no dialog.
**Implementation risk note:** hooking the moment between the user's Save As choice and the write under DocumentGroup is the fiddly part (the document's write path must not present UI); expected shape is intercepting at the pinned NSDocumentController/save-panel layer found in the branch. If it turns into a fight with AppKit, stop and report options rather than forcing it.
**Blast radius:** document controller layer, PreferencesStore (+test for the suppression flag).
**Verify:** live matrix — formatted .md → Save As .txt prompts once; suppression checkbox silences it permanently; unformatted .md → no prompt; Cancel aborts the save.

### P3.8 — Documentation close-out

Update `ARCHITECTURE.md`: document model section (DocumentGroup, WhitespaceDocument, runs), per-type behavior rules as conventions, supersessions of Phase 2 items recorded, S4 closed and removed from open items; the pre-existing typewriter recenter bug remains the sole open bug.
**Verify:** doc-only commit; final full suite + live smoke pass for the phase.

## Out of scope (unchanged)

Markdown beyond bold/italic (headings, lists, links — DESIGN.md: not a markdown power tool); underline in any form; the pre-existing typewriter recenter bug (separate item); error-surfacing for file I/O beyond what NSDocument provides natively.
