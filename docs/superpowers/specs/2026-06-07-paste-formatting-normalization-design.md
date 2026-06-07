# Paste Formatting Normalization — Design

**Date:** 2026-06-07
**Branch:** `improve-paste-formatting`
**Status:** Approved

## Problem

Pasting text into the editor (e.g. copied from a Word document) carries the
source formatting verbatim: font family, font size, paragraph indents (or lack
of them), colors, and so on. This breaks the app's uniform appearance, where
all body text is one font at one size and every paragraph's first line is
indented purely as an aesthetic (no literal indent characters).

## Goal

Any rich text entering the editor — via ⌘V **or** drag-and-drop — should be
normalized to the app's own style. Specifically:

- **Keep** bold, italic, and underline (as visual marks).
- **Strip** everything else: font family, font size, foreground/background
  colors, strikethrough, hyperlinks, lists, alignment, and all paragraph-level
  indentation.
- **Strip literal leading whitespace** (tabs and runs of spaces at the start of
  each pasted line/paragraph), so nothing pushes the real characters inward.
- **Re-apply** the editor's current style: `WhitespaceFont` (CrimsonPro) at the
  current preference size, the current paragraph style (first-line indent, line
  height, paragraph spacing), and the current theme text color.

The first-line indent remains purely aesthetic — produced by the paragraph
style's `firstLineHeadIndent`, never by literal characters.

## Current State (as found)

- The editor is `ZenTextView: NSTextView` (TextKit 2) in
  `Sources/Whitespace/Editor/ZenTextView.swift`. It has **no** paste override,
  so ⌘V and drops fall through to AppKit's default rich-text read, which
  preserves source formatting.
- The app's style model: `applyFont(size:lineHeightMultiple:)` sets
  `typingAttributes` with `.font` (a `WhitespaceFont` face) and a
  `.paragraphStyle` carrying `firstLineHeadIndent = size * 2`,
  `lineHeightMultiple`, and `paragraphSpacing = 4`.
- Bold/italic are **distinct font faces**, not symbolic traits:
  `WhitespaceFont` (`Sources/Whitespace/Resources/FontNames.swift`) maps to
  `CrimsonPro-Light` / `-LightItalic` / `-Medium` / `-MediumItalic`. The helper
  `fontName(bold:italic:)` already exists on `ZenTextView`.
- Current size/line-height come from `PreferencesStore`.
- `ZenTextViewRepresentable.Coordinator.textDidChange` syncs the text view's
  string back to the SwiftUI binding (drives autosave). Any programmatic edit
  must fire `NSText.didChangeNotification` for this to run.

## Approach

Override `readSelectionFromPasteboard(_:)` on `ZenTextView`. This single method
is the shared entry point for both paste and drag-and-drop insertion, so one
hook covers the chosen scope without duplicated logic. It pulls the richest
representation off the pasteboard, runs it through a pure normalizer, and
inserts the result.

(Alternatives rejected: overriding only `paste(_:)` misses drag-and-drop;
restricting the view to plain-text pasteboard types would discard bold/italic/
underline entirely.)

## Components

### 1. `PasteNormalizer` — new file `Sources/Whitespace/Editor/PasteNormalizer.swift`

A pure value type with **no NSTextView dependency**, so it is unit-testable in
isolation. Two stages:

#### Stage 1 — `styledRuns(from: NSAttributedString) -> [StyledRun]`

`StyledRun` is a small struct: `{ text: String, bold: Bool, italic: Bool,
underline: Bool }`. This stage holds all the real logic:

- **Trait detection** per source run:
  - bold/italic: read the run's `.font` as `NSFont`, inspect
    `font.fontDescriptor.symbolicTraits` for `.bold` / `.italic`. This works
    regardless of the source family (Calibri-Bold, Times-Italic, etc.). If a
    run has no `.font`, treat as neither.
  - underline: run's `.underlineStyle` attribute present and `!= 0`.
- **Everything else is dropped by construction** — we only ever read those
  three signals, so colors, sizes, families, strikethrough, links, background,
  lists, and alignment never propagate.
- **Leading-whitespace strip + newline normalization**, single pass over the
  string while tracking an `atLineStart` flag:
  - At line start, skip ` ` (U+0020) and `\t` (U+0009) characters; they are not
    emitted, and the flag stays `true`.
  - `\r\n` and lone `\r` are emitted as a single `\n`; `\n` is emitted as-is.
    All three set `atLineStart = true`.
  - ` ` (line separator) and ` ` (paragraph separator) are emitted
    unchanged and also set `atLineStart = true`, so indentation after a soft
    break is stripped too.
  - Any other character is emitted with its run's flags and sets
    `atLineStart = false`.

Runs are coalesced so contiguous characters sharing the same flags form one
`StyledRun` (efficiency; not semantically required).

#### Stage 2 — `attributedString(runs:baseAttributes:) -> NSAttributedString`

A thin mapping from `[StyledRun]` to an `NSAttributedString`:

- `baseAttributes` is the editor's current `typingAttributes`. From it we take
  the current font **size** (`(baseAttributes[.font] as? NSFont)?.pointSize`),
  the current `.paragraphStyle`, and the current `.foregroundColor`.
- For each run: `.font` = `NSFont(name: fontName(bold:italic:), size: size)`,
  `.paragraphStyle` = the base paragraph style, `.foregroundColor` = the base
  color. Underline runs additionally get `.underlineStyle = .single`.
- The `fontName(bold:italic:)` mapping currently lives as a `private` method on
  `ZenTextView`. To share it without exposing internals, lift the pure name
  mapping into `PasteNormalizer` (or a small shared helper) and have
  `ZenTextView` call through to it, keeping a single source of truth for the
  face names. Font instantiation falls back to the regular face if a named face
  is unavailable.

### 2. `ZenTextView` — paste hook

Override:

```
override func readSelectionFromPasteboard(_ pboard: NSPasteboard) -> Bool
```

Logic:

1. Resolve the richest available representation:
   - If the pasteboard has RTFD/RTF/HTML, read an `NSAttributedString`.
   - Else read a plain `String` and wrap it in an unattributed
     `NSAttributedString`.
   - If neither yields content, return `super.readSelectionFromPasteboard(pboard)`.
2. `let runs = PasteNormalizer.styledRuns(from: source)`
3. `let normalized = PasteNormalizer.attributedString(runs: runs, baseAttributes: typingAttributes)`
4. Insert with full undo + change notification:
   ```
   let range = selectedRange()
   guard shouldChangeText(in: range, replacementString: normalized.string) else { return false }
   textStorage?.replaceCharacters(in: range, with: normalized)
   didChangeText()
   setSelectedRange(NSRange(location: range.location + normalized.length, length: 0))
   ```
5. Return `true`.

`didChangeText()` posts `NSText.didChangeNotification`, so
`Coordinator.textDidChange` runs and the binding/autosave stays correct.

## Edge Cases

- **Empty / whitespace-only paste** → after stripping, `normalized` may be
  empty; the replace is a no-op insert (selection collapses, no crash).
- **Plain-text-only pasteboard** (no rich data) → still routed through the
  normalizer, so leading whitespace is stripped and the app style is applied.
- **Combined bold+italic run** → `fontName(bold: true, italic: true)` →
  `WhitespaceFont.boldItalic`.
- **Run with no `.font`** → treated as regular (neither bold nor italic).
- **Named face unavailable** → `NSFont(name:size:)` fall back to the regular
  face rather than crashing.

## Decisions / Non-Goals

- **Headings stay bold.** An all-bold paragraph (e.g. a Word heading) is kept
  bold per-run; we do not detect or demote heading weights to regular.
- **Bold detection is trait-based**, via `symbolicTraits`. Sources that encode
  weight without setting the bold trait (rare) would read as regular; accepted.
- Only bold, italic, underline survive — confirmed scope. Strikethrough and
  hyperlinks are intentionally stripped.

## Testing

`Tests/WhitespaceTests/PasteNormalizerTests.swift`, driving `styledRuns(from:)`
(the classifier) so tests do not depend on CrimsonPro being registered in the
test bundle:

- bold/italic/underline source runs → correct flags; bold+italic → both flags.
- strikethrough, `.link`, foreground color, and a non-default font size on a
  source run → none appear in the output runs (only the three flags can be set).
- leading tabs and leading spaces at the start of a line are removed; interior
  whitespace is preserved.
- `\r\n` and lone `\r` collapse to `\n`; line count is preserved.
- a Word-style mixed paragraph (regular + bold + italic + underline, with a
  leading tab) round-trips to the expected ordered run list.

A lighter check on Stage 2 asserts that, given a base attributes dict with a
known size/paragraph style/color, the produced `NSAttributedString` applies that
paragraph style and color to every run and sets `.underlineStyle` only on
underline runs.

Build clean and run the test target before declaring done (per CLAUDE.md: no
completion claim without a clean build and a passing test run).
