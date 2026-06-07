# Paste Formatting Normalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Normalize all rich text pasted or dragged into the editor so it keeps only bold/italic/underline and strips everything else, re-applying the app's own font, paragraph style, and color.

**Architecture:** A pure, AppKit-light `PasteNormalizer` does the work in two stages — `styledRuns(from:)` classifies the source into flag-only runs (bold/italic/underline) while stripping all other attributes and leading whitespace, and `attributedString(runs:baseAttributes:)` rebuilds an `NSAttributedString` using the editor's current typing attributes. `ZenTextView` overrides `readSelectionFromPasteboard(_:)` — the shared entry point for ⌘V and drag-and-drop — to run the source through the normalizer and insert the result with proper undo + change notifications.

**Tech Stack:** Swift, AppKit (`NSTextView`, `NSAttributedString`, `NSPasteboard`), TextKit 2, XCTest.

---

## Build & Test Commands (read first)

This repo builds via Xcode MCP tooling, not `swift build` (it's an `.xcodeproj`, single macOS target). Per `CLAUDE.md`:

- **Xcode open (preferred):** build with mcpbridge `BuildProject`, read results with `GetBuildLog` / `XcodeListNavigatorIssues`; run tests with mcpbridge `RunSomeTests` (scoped to `WhitespaceTests`) or `RunAllTests`, read failures with `GetConsoleOutput`. Verify Xcode is running first with `XcodeListWindows`.
- **Xcode closed (fallback):** `mcp__xcodebuild__build_macos` then `mcp__xcodebuild__test_macos` (requires the `macos` workflow enabled).

New `.swift` files must be added to the Xcode project model — do **not** hand-edit `.pbxproj`. Add files via mcpbridge `XcodeInsertFile`/`XcodeWrite` (which routes through Xcode's project model) so the target picks them up, or have the user add the file in Xcode. After creating `PasteNormalizer.swift` and `PasteNormalizerTests.swift`, confirm each is a member of the correct target (`Whitespace` for the source file, `WhitespaceTests` for the test file) before building.

Throughout: "Run the tests" means run the `WhitespaceTests` target via the tool above; quoted commands like `swift test` are illustrative of intent only.

---

## Task 1: `PasteNormalizer` Stage 1 — the classifier

Build the run classifier first: trait detection, strip-everything-else, leading-whitespace stripping, and newline normalization. This is the core logic and is fully unit-testable without the live text view or registered fonts.

**Files:**
- Create: `Sources/Whitespace/Editor/PasteNormalizer.swift`
- Test: `Tests/WhitespaceTests/PasteNormalizerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/WhitespaceTests/PasteNormalizerTests.swift`:

```swift
// Tests/WhitespaceTests/PasteNormalizerTests.swift
import XCTest
import AppKit
@testable import Whitespace

final class PasteNormalizerTests: XCTestCase {

    // Fonts that reliably carry the symbolic traits, independent of which
    // concrete family the test machine resolves them to.
    private func font(traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let base = NSFont.systemFont(ofSize: 12).fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: base, size: 12)!
    }
    private var boldFont: NSFont   { font(traits: .bold) }
    private var italicFont: NSFont { font(traits: .italic) }

    func testDetectsBoldItalicUnderline() {
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "b", attributes: [.font: boldFont]))
        s.append(NSAttributedString(string: "i", attributes: [.font: italicFont]))
        s.append(NSAttributedString(string: "u",
            attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue]))

        XCTAssertEqual(PasteNormalizer.styledRuns(from: s), [
            StyledRun(text: "b", bold: true,  italic: false, underline: false),
            StyledRun(text: "i", bold: false, italic: true,  underline: false),
            StyledRun(text: "u", bold: false, italic: false, underline: true),
        ])
    }

    func testStripsColorStrikethroughLinkAndSize() {
        let s = NSAttributedString(string: "x", attributes: [
            .foregroundColor:    NSColor.red,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .link:               URL(string: "https://example.com")!,
            .font:               NSFont.systemFont(ofSize: 99),
        ])
        XCTAssertEqual(PasteNormalizer.styledRuns(from: s),
                       [StyledRun(text: "x", bold: false, italic: false, underline: false)])
    }

    func testStripsLeadingTabsAndSpacesPerLine() {
        let s = NSAttributedString(string: "\t  Alpha\n   Beta")
        XCTAssertEqual(PasteNormalizer.styledRuns(from: s).map(\.text).joined(),
                       "Alpha\nBeta")
    }

    func testPreservesInteriorWhitespace() {
        let s = NSAttributedString(string: "a   b")
        XCTAssertEqual(PasteNormalizer.styledRuns(from: s).map(\.text).joined(), "a   b")
    }

    func testNormalizesCRLFAndCR() {
        let s = NSAttributedString(string: "a\r\nb\rc")
        XCTAssertEqual(PasteNormalizer.styledRuns(from: s).map(\.text).joined(), "a\nb\nc")
    }

    func testWordStyleParagraphRoundTrips() {
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "\tThe ", attributes: [.foregroundColor: NSColor.blue]))
        s.append(NSAttributedString(string: "quick",  attributes: [.font: boldFont]))
        s.append(NSAttributedString(string: " brown ", attributes: [:]))
        s.append(NSAttributedString(string: "fox",    attributes: [.font: italicFont]))

        XCTAssertEqual(PasteNormalizer.styledRuns(from: s), [
            StyledRun(text: "The ",    bold: false, italic: false, underline: false),
            StyledRun(text: "quick",   bold: true,  italic: false, underline: false),
            StyledRun(text: " brown ", bold: false, italic: false, underline: false),
            StyledRun(text: "fox",     bold: false, italic: true,  underline: false),
        ])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the `WhitespaceTests` target (see Build & Test Commands).
Expected: FAIL — `PasteNormalizer` / `StyledRun` are not defined (compile error).

- [ ] **Step 3: Write the minimal implementation**

Create `Sources/Whitespace/Editor/PasteNormalizer.swift`:

```swift
// Sources/Whitespace/Editor/PasteNormalizer.swift
import AppKit

struct StyledRun: Equatable {
    var text: String
    var bold: Bool
    var italic: Bool
    var underline: Bool
}

enum PasteNormalizer {

    /// Canonical mapping from bold/italic flags to a WhitespaceFont face name.
    static func fontName(bold: Bool, italic: Bool) -> String {
        switch (bold, italic) {
        case (true,  true):  return WhitespaceFont.boldItalic
        case (true,  false): return WhitespaceFont.bold
        case (false, true):  return WhitespaceFont.italic
        case (false, false): return WhitespaceFont.regular
        }
    }

    /// Stage 1: classify the source into flag-only runs. Keeps only
    /// bold/italic/underline, drops every other attribute by construction,
    /// strips leading tabs/spaces at each line start, and normalizes CR/CRLF
    /// to LF.
    static func styledRuns(from source: NSAttributedString) -> [StyledRun] {
        var runs: [StyledRun] = []
        var atLineStart = true

        func append(_ ch: Character, bold: Bool, italic: Bool, underline: Bool) {
            if var last = runs.last,
               last.bold == bold, last.italic == italic, last.underline == underline {
                last.text.append(ch)
                runs[runs.count - 1] = last
            } else {
                runs.append(StyledRun(text: String(ch),
                                      bold: bold, italic: italic, underline: underline))
            }
        }

        let full = NSRange(location: 0, length: source.length)
        let nsString = source.string as NSString

        source.enumerateAttributes(in: full, options: []) { attrs, range, _ in
            let traits = (attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            let bold = traits.contains(.bold)
            let italic = traits.contains(.italic)
            let underline = (attrs[.underlineStyle] as? Int ?? 0) != 0

            for ch in nsString.substring(with: range) {
                switch ch {
                case "\n", "\r", "\r\n":
                    append("\n", bold: false, italic: false, underline: false)
                    atLineStart = true
                case "\u{2028}", "\u{2029}":
                    append(ch, bold: false, italic: false, underline: false)
                    atLineStart = true
                case " ", "\t" where atLineStart:
                    continue  // drop leading whitespace
                default:
                    append(ch, bold: bold, italic: italic, underline: underline)
                    atLineStart = false
                }
            }
        }
        return runs
    }
}
```

Note: in Swift, `"\r\n"` is a single `Character` (extended grapheme cluster), so the `case "\n", "\r", "\r\n"` arm collapses all three to one `\n`. The `case " ", "\t" where atLineStart` arm only matches a space/tab when we are at a line start; otherwise it falls through to `default` and the whitespace is kept.

- [ ] **Step 4: Run the tests to verify they pass**

Run the `WhitespaceTests` target.
Expected: PASS — all six Stage 1 tests green.

- [ ] **Step 5: Commit**

```bash
git add Sources/Whitespace/Editor/PasteNormalizer.swift Tests/WhitespaceTests/PasteNormalizerTests.swift
git commit -m "feat: add PasteNormalizer run classifier (stage 1)"
```

---

## Task 2: `PasteNormalizer` Stage 2 — rebuild the attributed string

Map flag-only runs back to an `NSAttributedString` using the editor's current typing attributes (size, paragraph style, color), applying the right WhitespaceFont face per run and underline only where flagged.

**Files:**
- Modify: `Sources/Whitespace/Editor/PasteNormalizer.swift`
- Test: `Tests/WhitespaceTests/PasteNormalizerTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `PasteNormalizerTests`:

```swift
    func testAttributedStringAppliesBaseStyleAndUnderline() {
        let pStyle = NSMutableParagraphStyle()
        pStyle.firstLineHeadIndent = 36
        let base: [NSAttributedString.Key: Any] = [
            .font:            NSFont.systemFont(ofSize: 20),
            .paragraphStyle:  pStyle,
            .foregroundColor: NSColor.green,
        ]
        let runs = [
            StyledRun(text: "a", bold: false, italic: false, underline: false),
            StyledRun(text: "b", bold: false, italic: false, underline: true),
        ]

        let out = PasteNormalizer.attributedString(runs: runs, baseAttributes: base)
        XCTAssertEqual(out.string, "ab")

        let a0 = out.attributes(at: 0, effectiveRange: nil)
        XCTAssertEqual(a0[.paragraphStyle] as? NSParagraphStyle, pStyle)
        XCTAssertEqual(a0[.foregroundColor] as? NSColor, NSColor.green)
        XCTAssertEqual((a0[.font] as? NSFont)?.pointSize, 20)   // size from base
        XCTAssertNil(a0[.underlineStyle])                       // run 0 not underlined

        let a1 = out.attributes(at: 1, effectiveRange: nil)
        XCTAssertEqual(a1[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)
    }
```

(Font-name assertions are intentionally avoided: CrimsonPro may not be registered in the test bundle, so `NSFont(name:size:)` can fall back to the system font. Point size, paragraph style, color, and underline are all reliable.)

- [ ] **Step 2: Run the test to verify it fails**

Run the `WhitespaceTests` target.
Expected: FAIL — `attributedString(runs:baseAttributes:)` is not defined.

- [ ] **Step 3: Write the minimal implementation**

Add this method inside `enum PasteNormalizer` in `PasteNormalizer.swift`:

```swift
    /// Stage 2: rebuild an attributed string from flag-only runs, using the
    /// editor's current typing attributes as the base. Overrides only `.font`
    /// (the matching WhitespaceFont face at the base size) and `.underlineStyle`.
    static func attributedString(runs: [StyledRun],
                                 baseAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let size = (baseAttributes[.font] as? NSFont)?.pointSize ?? 18
        let result = NSMutableAttributedString()

        for run in runs {
            let name = fontName(bold: run.bold, italic: run.italic)
            let font = NSFont(name: name, size: size)
                ?? NSFont(name: WhitespaceFont.regular, size: size)
                ?? NSFont.systemFont(ofSize: size)

            var attrs = baseAttributes
            attrs[.font] = font
            if run.underline {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            } else {
                attrs[.underlineStyle] = nil
            }
            result.append(NSAttributedString(string: run.text, attributes: attrs))
        }
        return result
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the `WhitespaceTests` target.
Expected: PASS — Stage 2 test green, all Stage 1 tests still green.

- [ ] **Step 5: Commit**

```bash
git add Sources/Whitespace/Editor/PasteNormalizer.swift Tests/WhitespaceTests/PasteNormalizerTests.swift
git commit -m "feat: add PasteNormalizer attributed-string builder (stage 2)"
```

---

## Task 3: Wire the paste/drag hook into `ZenTextView`

Override `readSelectionFromPasteboard(_:)` to route paste and drag-and-drop through the normalizer, and point the existing `fontName(bold:italic:)` helper at the now-shared mapping (single source of truth).

**Files:**
- Modify: `Sources/Whitespace/Editor/ZenTextView.swift` (add override; change `fontName` body around line 576-583)

- [ ] **Step 1: Point the existing `fontName` helper at `PasteNormalizer`**

In `ZenTextView.swift`, replace the body of the existing private `fontName(bold:italic:)` (currently the `switch` at ~lines 576-583) so both call sites share one mapping:

```swift
    private func fontName(bold: Bool, italic: Bool) -> String {
        PasteNormalizer.fontName(bold: bold, italic: italic)
    }
```

- [ ] **Step 2: Add the paste/drag override**

Add this method to `ZenTextView` (e.g. just below the `// MARK: - Bold / Italic` section, before `// MARK: - keyDown`):

```swift
    // MARK: - Paste / Drag normalization

    override func readSelectionFromPasteboard(_ pboard: NSPasteboard) -> Bool {
        let source: NSAttributedString
        if let data = pboard.data(forType: .rtfd),
           let s = NSAttributedString(rtfd: data, documentAttributes: nil) {
            source = s
        } else if let data = pboard.data(forType: .rtf),
                  let s = NSAttributedString(rtf: data, documentAttributes: nil) {
            source = s
        } else if let data = pboard.data(forType: .html),
                  let s = try? NSAttributedString(
                      data: data,
                      options: [.documentType: NSAttributedString.DocumentType.html],
                      documentAttributes: nil) {
            source = s
        } else if let str = pboard.string(forType: .string) {
            source = NSAttributedString(string: str)
        } else {
            return super.readSelectionFromPasteboard(pboard)
        }

        let runs = PasteNormalizer.styledRuns(from: source)
        let normalized = PasteNormalizer.attributedString(runs: runs, baseAttributes: typingAttributes)

        let range = selectedRange()
        guard shouldChangeText(in: range, replacementString: normalized.string) else { return false }
        textStorage?.replaceCharacters(in: range, with: normalized)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + normalized.length, length: 0))
        return true
    }
```

- [ ] **Step 3: Build and run the existing test suite**

Build the project (mcpbridge `BuildProject`, or `mcp__xcodebuild__build_macos`).
Expected: clean build, no warnings introduced.
Run the `WhitespaceTests` target.
Expected: PASS — all `PasteNormalizer` tests still green (no behavior in them changed; this confirms the `fontName` refactor didn't break the mapping).

- [ ] **Step 4: Manual verification in the running app**

The live paste path can't be unit-tested cleanly (it needs a real pasteboard + view), so verify by hand:

1. Launch the app (mcpbridge run / `mcp__xcodebuild__launch_macos`, or run from Xcode).
2. In **TextEdit** or **Word**, type a paragraph mixing **bold**, *italic*, underline, a colored word, and a leading tab/indent. Copy it.
3. In Whitespace, paste with ⌘V. Confirm:
   - Font is CrimsonPro at the editor's size; source font/size/color are gone.
   - Bold, italic, and underline survive; strikethrough/links/colors do not.
   - No literal leading indent — only the app's aesthetic first-line indent.
   - Undo (⌘Z) removes the whole paste in one step; typing afterward uses the regular face.
4. Repeat by **dragging** selected rich text from TextEdit into the editor — same result.
5. Confirm autosave/title still reflects the change (the binding updated), proving `didChangeText()` fired.

- [ ] **Step 5: Commit**

```bash
git add Sources/Whitespace/Editor/ZenTextView.swift
git commit -m "feat: normalize pasted and dragged text to app style"
```

---

## Done criteria

- Clean build, `WhitespaceTests` target passing.
- Manual paste + drag verification from a rich-text source confirms: only bold/italic/underline survive, app font/paragraph style/color applied, leading whitespace stripped, single-step undo, autosave updates.
- Branch `improve-paste-formatting` ready for review/merge (see `superpowers:finishing-a-development-branch`).
