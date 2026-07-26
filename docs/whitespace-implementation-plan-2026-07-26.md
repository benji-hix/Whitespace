# Whitespace — implementation plan

*Written 2026-07-26 against `d1185a5`. Revised same day: underline retracted after the parser probe in §0. Approved scope: next-step queue items 5.1–5.6. Item 5.7 (prune) carries the decision detail you asked for, in Phase 7.*

---

## 0. Why there is no markdown work in this plan

The dialect is settled at **bold and italic only**, which is precisely what the code already implements. `MarkdownText`, `PasteNormalizer`, `StyledRun`, and `ARCHITECTURE.md` §2 all agree today. **No phase touches markdown.**

Recording why, so a future session does not re-propose underline and rediscover this the expensive way:

### 0.1 Underline cannot round-trip through the decoder without custom machinery

Probed directly against Foundation this session — `AttributedString(markdown:options:.inlineOnlyPreservingWhitespace)`:

| Input | Parser output |
|---|---|
| `plain <u>under</u> tail` | `plain <u>under</u> tail` — **tags survive as visible literal text** |
| `plain <ins>under</ins> tail` | `plain <ins>under</ins> tail` — same |
| `__double__ and **star**` | `double and star` — both parse as **bold** |
| `*it* and ***both***` | `it and both` — italic, bold-italic |

Three consequences, any one of which is disqualifying on its own:

- **`__underscores__` are unavailable.** CommonMark binds them to bold. Repurposing them collides with the existing encoder and breaks every other markdown reader.
- **HTML tags pass through as literal characters.** Shipping `<u>` naively puts raw `<u>` on screen inside a markdown document, violating `ARCHITECTURE.md` §2's hard rule: *"The user never sees markdown syntax in a markdown document."*
- **Working around that needs an index-reconciling pre-pass.** Strip the tags, record their spans, hand the clean string to the parser — then reconcile those spans against the index shifts caused by the parser removing `**` and `*` markers. The naive version passes simple tests and silently corrupts real documents.

Against that cost, underline would still have rendered as plain text on GitHub. Retracted.

### 0.2 The existing prohibition stands as written

`ARCHITECTURE.md` §2 — *"Underline does not exist anywhere in the app. `StyledRun` has no underline field; do not add one (markdown cannot express it)"* — remains correct and needs no edit. Commit `6136571` (P3.5) removed underline cleanly on 2026-06-10; that removal stays.

---

## 1. Working rules for every phase

- **1a. Branch per phase.** Never commit to `main`. Branch from `main`, merge back when the phase's done-when passes.
- **1b. Definition of done** (`ARCHITECTURE.md` §4.9, unchanged): clean build **and** full suite green **and**, for UI changes, the behavior observed in the running app. One concern per commit.
- **1c. Test frequently.** Run the full suite after every work item, not just at phase end. It takes ~1 second (96 tests in 0.152s) — there is no reason to batch.
- **1d. Pure logic gets unit tests first.** Anything decision-shaped (geometry, classification, serialization) lives in a pure type with value inputs, per `ARCHITECTURE.md` §4.6.
- **1e. Regenerate, never hand-edit.** New files require `xcodegen generate`. `project.pbxproj` and `Info.plist` are build artifacts.
- **1f. Update `ARCHITECTURE.md` in the same commit** whenever code and doc disagree.

### 1g. Verification is constrained — plan around it

Discovered this session, the hard way:

| Method | Status | Use for |
|---|---|---|
| Unit tests | Works | All pure logic |
| Accessibility API (`osascript` / System Events) | **Works** — window names, fullscreen state, sizes, menu contents, text-area values | Structural assertions: which window opened, is it fullscreen, what the menu contains |
| Synthetic keystrokes (`keystroke`, `key code`) | **Fails silently** — never reach the editor. Your keyboard remapper, per `ARCHITECTURE.md` §4.11 | Nothing. Do not build verification on this |
| `screencapture` | **Fails** — "could not create image from display" when the display sleeps | Only with the display awake and unlocked |

**Consequence:** Phases 2, 3, 4, and 5 all end in a step only you can perform — looking at the screen. The plan marks these **`[owner verify]`**. An agent must never report those phases complete on automation alone.

### 1h. Subagent structure — and an honest note on how much it helps here

**Hard constraint: Xcode builds must serialize.** Concurrent `xcodebuild` runs against the same project share one DerivedData directory and will corrupt or block each other. Two safe patterns:

- **Read-only or new-file-only agents** (investigation, test authoring, doc analysis) — unlimited parallelism, they never build.
- **Agents that build** — one at a time, or each in `isolation: "worktree"`, which gives every agent its own checkout and therefore its own DerivedData.

**Honest assessment:** with underline gone, this plan lost its one big fan-out. What remains is mostly small, serial, single-file work where spawning three agents to change one file is overhead rather than parallelism. **Phase 3 is the only phase with genuine fan-out value**; Phase 2 has modest value. The rest should run single-agent. The plan names the structure per phase rather than applying a uniform pattern that would be padding.

Where fan-out does apply:

```
Fan out (parallel, no builds)     →  Serial implement      →  Serial verify
├─ investigator: read the code,      one implementer         one verifier:
│  report findings                   owns the edits and      build + full suite,
└─ test-author: write the failing    the build lock          report raw output
   tests (new files only)
```

---

## 2. Phase order and rationale

Your ranking was 5.1, 5.2, 5.3, 5.4, 5.5, 5.6. I have made **one resequencing change** and I want it visible rather than buried:

**Typewriter recentering (5.5) moves ahead of fullscreen (5.3).** Reason: 5.2 and 5.5 are the same class of defect in the same file — stale TextKit 2 layout geometry read at the wrong moment in `ZenTextView`. The `ensureParagraphLayout` insight in your abandoned caret fix is very likely the same insight the recenter bug needs. Fixing them adjacent, while that subsystem is loaded in context, is materially cheaper than fixing one, switching to window geometry, and coming back.

The second reason is diagnostic: if you validate fullscreen while the caret is still misplaced and recentering is still broken, you cannot tell whether a problem at 2560×1440 is a fullscreen bug or one of the two known bugs showing up differently. Fullscreen validation is only meaningful against a correct editor.

Everything else keeps your order.

| Phase | Item | Size | Depends on |
|---|---|---|---|
| 0 | Salvage the uncommitted worktree diffs | S | — |
| 1 | Launch and ⌘N produce a blank untitled `.md` (5.1) | S | — |
| 2 | Caret baseline correctness (5.2) | S | 0 |
| 3 | Typewriter recentering (5.5) | M | 2 |
| 4 | Fullscreen (5.3) | M | 2, 3 |
| 5 | Dark theme finalization (5.4) | S | 0, 4 |
| 6 | Ship — icon, versioning, install (5.6) | S | 1–5 |
| 7 | Prune (5.7) | S | 0, 5 |

---

## Phase 0 — Baseline and salvage

**Goal:** get the only unique content on disk into git before anything else touches the tree.

Two uncommitted worktree diffs are the sole content in this repo not reachable from `main`. Both are fragile — a stray `git worktree prune` or a cleanup script destroys them. Salvage first, always.

**Work items**

- **0a.** Branch `salvage/worktree-harvest` from `main`.
- **0b.** Copy the caret diff out of `.claude/worktrees/frosty-rubin-5724f1` (94 lines in `ZenTextView.swift`) to a patch file under `docs/`. Do not apply it yet — Phase 2 owns that.
- **0c.** Copy the theme diff out of `.claude/worktrees/distracted-ritchie-1ce181` (`Theme.swift`, `#6B5B5E` → `#988888`) to a patch file. Phase 5 owns it.
- **0d.** Record the baseline: run build and full suite, save the raw output.

**Subagents:** none. This is three file copies.

**Done when:** both patches are committed to a branch; worktree contents, branch tips, and the stash can all be destroyed without losing work. Baseline output shows `** BUILD SUCCEEDED **` and 96 tests / 0 failures.

---

## Phase 1 — Launch and ⌘N produce a blank untitled `.md`

**Goal:** opening Whitespace puts you on a blank page. No file dialog, ever.

**Why first:** it is the first three seconds of every use, it is small, and it is the one open UX decision in `ARCHITECTURE.md` §5 that was written down and never made.

**Current state:** `newDocumentType` already defaults to `.markdown`, so the *type* is correct — ⌘N already gives you a markdown document. The defect is launch only: a cold launch shows the standard NSDocument open panel (verified this session — the window is named `Open`).

**Work items**

- **1.1** Suppress the launch-time open panel and open one untitled document instead. Under `DocumentGroup`, SwiftUI's private `PlatformDocumentController` owns this; expect the lever to be `NSApplicationDelegate.applicationShouldOpenUntitledFile` / `applicationOpenUntitledFile` via `NSApplicationDelegateAdaptor`, not a SwiftUI modifier. `ARCHITECTURE.md` §1 warns the controller cannot be replaced or subclassed — work with the delegate hooks, not against the controller.
- **1.2** Confirm the reopened-document path still works: if macOS state restoration has documents to restore, restore them and do **not** additionally open a blank one.
- **1.3** Verify ⌘N still honors the New Files preference in both settings.

**Risk:** medium-low. `ARCHITECTURE.md` §1 documents that this layer has already fought back once (the `NSDocumentController` pinning that "was proven inert and removed"). If the delegate hook does not take within a reasonable attempt, stop and report options rather than forcing it — this phase is not worth an AppKit brawl.

**Subagents:** single implementer. One file, one behavior.

**Tests**

- Unit: none meaningfully — this is app-lifecycle behavior.
- **Automated check (works):** cold-launch the built app and read the window list over the accessibility API. Must report `Untitled`, not `Open`.

**Done when**

```bash
osascript -e 'tell application "System Events" to tell process "Whitespace" to get name of every window'
```

returns `Untitled` on a cold launch with no arguments, no Open panel appears, ⌘N still produces the preferred type, build is clean, and the full suite is green.

---

## Phase 2 — Caret sits on the correct baseline

**Goal:** the caret is never a fraction of a line too high, in any situation.

**Why:** your words — with an app this minimal, every UI inconsistency is the whole product. And the fix is already written and diagnosed; the cost is porting, not thinking.

**Work items**

- **2.1** Apply the salvaged patch from 0b: `ensureParagraphLayout(containing:tlm:)` plus the deferred `updateCursorView()` re-paint in the selection-change path.
- **2.2** **Strip all `#if DEBUG` instrumentation** — the `debugLog` helper, the `/tmp/caretdbg.log` file writes, and every call site. That logging was a diagnostic scaffold; it does not ship.
- **2.3** Keep the explanatory comments. They record why the naive `ensureLayout(for:)` over a zero-length range is insufficient — exactly the kind of non-obvious WHY the coding conventions want preserved.
- **2.4** Add a regression test. Honest scope: assert that `ensureParagraphLayout` is invoked and that the returned caret rect's baseline matches the paragraph's laid-out baseline after a programmatic edit, hosted in an offscreen `NSWindow` per the `ZenTextViewUndoTests` pattern.

**Subagents:** two, in parallel, neither building — *test-author* (writes the failing regression test as a new file) and *implementer* (ports and cleans the patch). Then one serial verify.

**Done when**

- Clean build, 96+ tests green.
- **`[owner verify]`** In the running app: type the first glyph on a fresh line — caret sits on the baseline immediately, not after the next blink. Press ⌘Z — same. Automation cannot do this step.

---

## Phase 3 — Typewriter recentering follows sustained typing

**Goal:** the active line stays vertically centered while you type continuously. The core promise of the app.

**Why here:** same file, same class of bug as Phase 2, and Phase 2's fix is likely the lead.

**What is already known** (from `ARCHITECTURE.md` §5 — do not re-derive):

- The bug is pre-existing and was verified identical at the pre-engagement baseline.
- **The decision math is tested and exonerated.** `TypewriterScroll.target(for:)` has 13 passing characterization tests. The bug is not in the arithmetic.
- Prime suspects: stale TK2 caret geometry read inside the deferred recenter, or the `currentScrollTarget` cache (`ZenTextView.swift:22`, `203–250`) holding a value that suppresses a needed scroll via the `abs(target - currentScrollTarget) < 0.5` early-return at line 247.

**Work items**

- **3.1** Reproduce deterministically first. Build a test harness that inserts text programmatically in a loop against an offscreen-hosted `ZenTextView` and records caret Y against viewport bounds after each insertion. If the deadzone violation reproduces headlessly, the whole phase becomes unit-testable — pursue this before touching the fix.
- **3.2** Instrument the recenter path to record what geometry it read versus what was true after layout settled. Delete the instrumentation before merge (Phase 2's lesson).
- **3.3** Apply the fix. If Phase 2's `ensureParagraphLayout` is the missing piece, the change may be small; if the `currentScrollTarget` cache is stale-suppressing, the fix is invalidation, not geometry.
- **3.4** Extend `TypewriterScrollTests` with whatever 3.1 makes assertable.

**Risk:** the highest of any phase. `ZenTextView.swift` has 12 commits and is the churn hotspot. If 3.1 cannot reproduce headlessly after a genuine attempt, say so and fall back to instrumented manual reproduction rather than guessing at fixes.

**Subagents:** the one phase where fan-out genuinely pays. Three in parallel, none building:
- *reproducer* — attempts the headless harness (3.1); highest value, report back either way
- *investigator* — traces every write to `currentScrollTarget` and every recenter entry point, reports the call graph
- *doc-checker* — identifies what §5 needs to say afterward

Then serial implement, serial verify.

**Done when**

- Clean build, full suite green including any new tests.
- **`[owner verify]`** Type 40+ continuous lines in the running app. The active line stays within the deadzone throughout; the viewport never pins while the caret walks below it.
- `ARCHITECTURE.md` §5 open-bug entry is removed in the same commit.

---

## Phase 4 — Fullscreen is the primary target

**Goal:** the app is correct at your real display size, in fullscreen, because that is how it is used.

**Your framing, adopted:** centering, padding, and fade-out in fullscreen are *more* important than windowed. This phase treats fullscreen as the reference and windowed as the fallback, inverting how the code was tuned.

**Known suspects** (from reading the code, `[inferred]` until reproduced):

- **4a.** `WindowStylingView.windowDidUpdate` (`WhitespaceApp.swift:111–122`) re-asserts hidden traffic lights on *every* window update. In fullscreen, AppKit auto-shows the titlebar on hover — these two will fight, and the visible symptom would be flicker.
- **4b.** `CanvasView`'s fade-mask gradient stops are hardcoded fractions — `0.1 / 0.3 / 0.7 / 0.9` (`CanvasView.swift:37–50`). At 450pt tall that is a ~90pt fade; at 1440pt it is a ~290pt fade. The mask scales *proportionally*, which is almost certainly wrong for a fixed reading experience.
- **4c.** The shortcut overlay's `geo.size.width / 18` padding (`CanvasView.swift:67`) is 50pt at 900 wide and 142pt at 2560 wide.
- **4d.** Column position: `prefs.columnWidth.maxPoints` tops out at 820pt. Centered in 2560pt leaves ~870pt of margin per side. Verify that reads as generous rather than lost.

**Reference material:** `mockups/whitespace-fullscreen.html` records the *intended* fullscreen appearance — resting state, palette open, overlay open, with stated dimensions for each. Use it as the target rather than re-deriving the design.

**Work items**

- **4.1** Establish the reference: run fullscreen at your actual display resolution and capture what is wrong. **`[owner verify]`** — this is observation, and automation cannot do it.
- **4.2** Decide whether the fade mask should be proportional or absolute. Recommendation: absolute (a fixed point-height fade top and bottom), so the reading experience is identical at every window size. This is a design decision — flag it rather than assume.
- **4.3** Fix the titlebar contention in 4a if it manifests. Likely shape: make `stylingHasDrifted` skip re-assertion while `window.styleMask.contains(.fullScreen)`.
- **4.4** Re-tune overlay padding against fullscreen first, windowed second.
- **4.5** Update `ShortcutOverlayView.appShortcuts` — it currently omits ⌘⇧M and Enter Full Screen, which `ARCHITECTURE.md` §4.2 requires to stay in sync (gap 4.11).

**Subagents:** one investigator to map every hardcoded geometry constant against window size before any edit; then serial implement. Fan-out is low value here — the work is judgment against a screen, not search.

**Done when**

- Clean build, full suite green.
- **`[owner verify]`** One full real writing session in fullscreen: no visible chrome, no flicker on titlebar auto-show, fade mask and column reading correctly at full width.
- Overlay lists every app-level shortcut that exists.

---

## Phase 5 — Finalize the dark theme

**Goal:** one committed dark-mode text color, decided in the condition you actually read in.

**Why after Phase 4:** you cannot judge reading legibility in a 900×450 window. This is why it sat unresolved since 2026-05-11.

**Work items**

- **5.1** Apply the salvaged theme patch from 0c (`#6B5B5E` → `#988888`).
- **5.2** **`[owner verify]`** Read real prose fullscreen, both themes, for long enough to judge. Compare against the current value.
- **5.3** Commit one value. Delete the alternative.
- **5.4** While here: `ThemeStore`'s manual ~60fps cross-fade loop is scope drift against `DESIGN.md` ("the only motion is smooth scrolling"). Not in scope to remove — noting it so the decision stays conscious rather than forgotten.

**Subagents:** none. This is one hex value and your eyes.

**Done when:** `Theme.swift` holds one committed dark `textColor`; no uncommitted theme variants remain anywhere; build and suite green.

---

## Phase 6 — Ship it

**Goal:** an app you launch from Spotlight, not from Xcode.

**Work items**

- **6.1 App icon.** `Assets.xcassets` currently has no AppIcon set. Needs the full macOS size ladder (16 through 512 @1x/@2x). Design direction is yours — `DESIGN.md`'s monochrome constraint governs the app surface, not necessarily the icon, but a monochrome mark would be consistent.
- **6.2 Versioning.** `project.yml` carries `MARKETING_VERSION: "1.0"` and `CURRENT_PROJECT_VERSION: "1"`, both placeholders. Decide the scheme. Given the MVP was reached in April 2026 and never declared, this is the moment to declare 1.0 for real.
- **6.3 Signing.** Decide: ad-hoc local signing (fine for a personal app; Gatekeeper prompts once) versus a Developer ID identity (clean install, needs a paid account). Ad-hoc is the smaller path and matches how this app is used.
- **6.4 Export.** Archive and export to `/Applications`. Add the command to `docs/` so future rebuilds are one step.
- **6.5** Resolve the two Swift 6 warnings at `WhitespaceApp.swift:19` (gap 4.10) — main-actor property referenced from a Sendable closure. Small, and shipping on a warning-free build is worth it.
- **6.6** Verify the plain-text conversion warning live (gap 4.5). `ARCHITECTURE.md` §5 lists it as unit-tested but never manually confirmed, and it is the last unverified flow in the app. **`[owner verify]`** the matrix: a formatted `.md` saved as `.txt` warns once; Cancel aborts the save; Save Anyway writes flattened; the suppression checkbox persists; an unformatted `.md` produces no prompt.

**Subagents:** one for 6.5 (isolated, mechanical), one for icon asset generation once you supply artwork. The rest is configuration and observation.

**Done when:** `Whitespace.app` is in `/Applications`, launches from Spotlight without Xcode, shows a real icon in the Dock, reports its version in About, the build emits zero warnings, and 6.6's matrix is confirmed.

---

## Phase 7 — Prune (your 5.7 decision, with the facts)

You asked for more information before approving. Here it is.

### 7.1 Branches — all seven are fully contained in `main`

Verified with `git merge-base --is-ancestor`:

| Branch | Unique commits | Behind main | Verdict |
|---|---|---|---|
| `claude/charming-johnson-8777f1` | **0** | 41 | contained — safe |
| `claude/festive-feynman-59ca22` | **0** | 41 | contained — safe |
| `claude/distracted-ritchie-1ce181` | **0** | 38 | contained — safe |
| `claude/frosty-rubin-5724f1` | **0** | 42 | contained — safe |
| `feat/nsdocument-markdown` | **0** | 30 | contained — safe |
| `refine-shortcuts-panel` | **0** | 40 | contained — safe |
| `fullscreen-debugging` | **0** | 0 | contained — safe |

**Nothing is lost by deleting any of them.** Every commit they point at is already an ancestor of `main`.

### 7.2 Worktrees — 2.7 MB, and they hold the only unique content

The four worktrees under `.claude/worktrees/` total ~2.7 MB. Two contain uncommitted changes, and **those two diffs are the only content in this repository not reachable from `main`** — which is precisely why Phase 0 salvages them first. After Phases 2 and 5 land, they hold nothing unique.

### 7.3 The stash

One entry, `stash@{0}`: a 4-line-insertion / 8-line-deletion change to `Whitespace.xcscheme` consisting entirely of Xcode version-stamp churn (`LastUpgradeVersion`, `version`, and three default attributes). No work content.

### 7.4 `mockups/whitespace-fullscreen.html`

536 lines. **Correcting my earlier recommendation to cut it:** this is the only artifact recording the intended fullscreen appearance, and Phase 4 uses it as the reference. Keep it at least until Phase 4 closes, then decide.

### 7.5 Recommendation

Run this phase **after Phase 5**, not before — 7.2's contents are inputs to Phases 2 and 5. Then: delete all seven branches, remove all four worktrees, drop the stash, and decide on `mockups/` with Phase 4 finished.

**Done when:** `git branch -a` shows `main` plus any live work; `git worktree list` shows one entry; `git stash list` is empty.

---

## 3. What is deliberately not in this plan

Named so they are conscious omissions rather than oversights:

- **3a.** Cut-list items 4C.2–4C.6 (scroll-speed slider, auto-dismiss preference, keybinding Record UI, column/line-height pickers, command palette). You did not approve these and they are not blocking. They remain available.
- **3b.** Any markdown change. The dialect is bold and italic only, which is the current implementation — see §0.
- **3c.** `ThemeStore`'s cross-fade animation (noted at 5.4) and Open Recent under DocumentGroup (`ARCHITECTURE.md` §5, likely permanent).

---

## 4. Starting the next session

Phase 1 is self-contained and does not depend on Phase 0. Either is a valid start; Phase 0 is safer to do first because it protects against accidental loss.

Opening prompt:

> Read `docs/whitespace-implementation-plan-2026-07-26.md`, then execute Phase 0 followed by Phase 1. Branch from main first. Verify Phase 1 with the accessibility query in its done-when — do not report complete without fresh build, test, and launch output.

No open decisions remain.
