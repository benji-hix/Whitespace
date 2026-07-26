# Whitespace — state reconstruction, 2026-07-26

Gap since last commit: **45 days** (last commit 2026-06-11, last git activity 2026-06-18).

Verified fresh this session: build succeeds (exit 0), 96 tests pass (exit 0), app launches. Nothing is broken.

**The obstacle is not architecture.** The architecture is sound and documented in `ARCHITECTURE.md`. The problem is that the last two months of work went into scope `DESIGN.md` explicitly disclaims (markdown formatting, a paste subsystem, a document-architecture migration), while the first three seconds of using the app — launch shows a file-open dialog, not a blank page — sat unfixed behind a decision you wrote down and never made.

---

## 1. Method note

There is **no pre-implementation spec in this repo.** The first commit (`7ee393f`, 2026-04-22) is a bare Xcode scaffold: 8 files, no design doc. The entire app was built in a 26-hour burst across 2026-04-23 → 04-24 (19 commits). `DESIGN.md` was committed 2026-05-02 — ten days after the app already worked. It is a philosophy document written retroactively, not a specification written in advance.

So §2's "Designed MVP" is reconstructed from two sources treated as jointly authoritative: the April 23–24 build sequence (what you actually made first) and `DESIGN.md` (what you said it was for). Where they disagree, that is noted.

---

## 2. The original MVP

### 2.1 Designed MVP — what the artifacts commit to

| ID | Commitment | Evidence |
|---|---|---|
| 2.1a | Single-column, typewriter-centered writing surface; text stays vertically centered, the page moves | `DESIGN.md` §Typography; commit `53dcda8` "font-height cursor, typewriter centering" |
| 2.1b | Crimson Pro serif, generous margins, single column always | `DESIGN.md` §Typography; commit `b620699` bundles CrimsonPro Light/Medium |
| 2.1c | Zero visible UI while writing — no toolbars, sidebars, status bars, buttons, badges | `DESIGN.md` §Chrome |
| 2.1d | Monochrome; two themes (paper / dark); color never used as affordance | `DESIGN.md` §Chrome; commit `2c24742` Theme + ThemeStore |
| 2.1e | Open, edit, and save plain text files | commit `4d41f2f` FileBuffer + FileStore |
| 2.1f | Command palette (⌘P) as the only navigation surface | commit `9863d0f` |
| 2.1g | Shortcut overlay (⌘/) — learnable, never a visible button | commit `ca23b95`; `DESIGN.md` Forbidden List bans a visible shortcuts button by name |
| 2.1h | Customizable editor delete-keybindings, 6 vim-inspired actions | commit `db25611` — the **third commit in the project**; this was foundational, not added later |
| 2.1i | Settings window for font size, line height, column width | commit `d8ddec6` |

All nine exist and work today.

### 2.2 Scope drift — present in code or later notes, never in the original MVP

| ID | Drift | Scale | Note |
|---|---|---|---|
| 2.2a | **Markdown as a document format** with bold/italic round-trip: encoder, decoder, per-type editor modes, conversion gate, New Files preference | Phase 3, 8 commits, ~330 src + ~380 test lines | `DESIGN.md`: "Not iA Writer / Bear / Ulysses-adjacent… not a markdown power tool." The Forbidden List targets formatting directly. ⌘B/⌘I are chords not chrome, so the *letter* holds — but the surrounding machinery is the power-tool surface area the doc disclaims |
| 2.2b | **Paste formatting normalization** — its own design spec + implementation plan | 5 commits, 2 docs | Defensible: it protects 2.1b/2.1d from foreign styling. Still a subsystem with its own spec that no MVP artifact asked for |
| 2.2c | **NSDocument / DocumentGroup migration** — replaced a working FileStore with native document architecture | Largest single item in the project | Real engineering value; zero user-visible MVP value |
| 2.2d | **Plain-text conversion warning** — `NSAlert` with suppression checkbox | P3.7 | A modal dialog in an app whose thesis is "zero visible UI" |
| 2.2e | **Scroll-speed slider; shortcut-panel auto-dismiss toggle + delay field** | 3 prefs keys, ~40 view lines | Presentation fiddling — the exact category `DESIGN.md`'s Decision Heuristic rejects |
| 2.2f | **Keybinding Record UI** with conflict messaging | R7, ~100 lines | The keybinding *system* was MVP (2.1h). A recording GUI was not |
| 2.2g | **Theme cross-fade** — manual ~60fps interpolation loop | `ThemeStore` | `DESIGN.md`: "The only motion is smooth scrolling" |

### 2.3 Inferred

- **2.3a `[inferred]` The app was meant to be used fullscreen.** Evidence: the repo's only mockup is `mockups/whitespace-fullscreen.html`, titled "Fullscreen Mockup", with its canvas sized `/* macOS window @ ~fullscreen 16:10 ratio */`; and the last branch you created was named `fullscreen-debugging`.
- **2.3b `[inferred]` The MVP was reached on 2026-04-24 and never declared.** Evidence: 19 commits over two days built every layer in dependency order (stores → editor → palette → overlay → preferences → app wiring), then an 8-day silence. Everything after is refinement, migration, or new scope. No commit, tag, release, or doc marks a v1.
- **2.3c `[inferred]` You are the only intended user.** Evidence: bundle id `com.benji.Whitespace`; no signing, notarization, or export config in `project.yml`; no LICENSE, no README, no app icon (`Assets.xcassets/Contents.json` is 3 lines); public GitHub repo with zero issues, zero PRs, zero releases.
- **2.3d `[inferred]` Documents-on-disk was always the model, never a library.** Evidence: `DESIGN.md` "not a library manager"; the palette's fuzzy file-switching was deliberately deleted in P3.3 in favour of window-per-document.

---

## 3. Your last position

### 3.1 Last thing worked on — and it isn't the last commit

**Last commit:** 2026-06-11 00:13, `d1185a5`, merge of `fable-review-1` into main. That work **is finished.** It closed an 8-item refactor (R1–R8) plus an 8-item Phase 3 (P3.1–P3.8), with `ARCHITECTURE.md` rewritten as the close-out document. Clean merge, green build, green tests.

**Last activity:** 2026-06-18 12:04:45 — `checkout: moving from main to fullscreen-debugging` (reflog). **Zero commits were ever made on that branch.** The repo then sat on it, untouched, for 38 days until this session.

So the last thing you did was open a fullscreen investigation and stop before writing a line. Nothing about it is finished, and nothing about it was started.

### 3.2 Blockers to resumption — none

Verified with fresh command output this session:

| Check | Result |
|---|---|
| `xcodebuild … build` | `** BUILD SUCCEEDED **`, exit 0 |
| `xcodebuild … test` | 96 tests, 0 failures, exit 0, `** TEST SUCCEEDED **` |
| App launch | Launches; ⌘N gives an `Untitled` window; editor accepts text |
| Enter Full Screen | Works — window 2560×1440, `AXFullScreen=true` |
| Working tree | Clean |
| Stash | One entry, Xcode scheme version-stamp churn only — not work |
| Remote | No open issues, no PRs |

Two non-fatal Swift 6 warnings: `WhitespaceApp.swift:19:26` and `:19:43`, main-actor-isolated property referenced from a Sendable closure.

`[unverified]` Sustained-typing behaviour and on-screen caret position could not be checked. Synthetic keystrokes did not reach the editor (the keyboard-remapper limitation recorded in `ARCHITECTURE.md` §4.11), and `screencapture` failed with "could not create image from display" — the display was asleep. Editor writability was confirmed via the accessibility API instead.

### 3.3 Decisions you appear to have been stuck on

- **3.3a Fullscreen — the strongest signal.** A named branch, no commits, 38 days of silence. Fullscreen works *mechanically* (verified above), so what stopped you was a judgment call about appearance or behaviour, not a crash. `[inferred]` from the code, the two likeliest culprits: `WindowStylingView.windowDidUpdate` (`WhitespaceApp.swift:111–122`) re-asserts hidden traffic lights on every window update, which will fight AppKit's fullscreen titlebar auto-show; and `CanvasView`'s fade-mask stops (`CanvasView.swift:37–50`) and `geo.size.width / 18` overlay padding (`:67`) were tuned against a 900×450 window, not 2560×1440.
- **3.3b An abandoned caret fix is still sitting on disk, uncommitted.** `.claude/worktrees/frosty-rubin-5724f1/Sources/Whitespace/Editor/ZenTextView.swift` holds **94 uncommitted lines** dated 2026-05-30: a diagnosed fix for stale TextKit 2 caret geometry — a new `ensureParagraphLayout(containing:tlm:)` plus a deferred `updateCursorView()` re-paint — with `#if DEBUG` file logging to `/tmp/caretdbg.log` still embedded. `ensureParagraphLayout` **does not exist in main**; this never landed. The in-code comments carry a complete diagnosis.
- **3.3c Dark-mode legibility, never settled.** `.claude/worktrees/distracted-ritchie-1ce181` holds an uncommitted one-line change lightening dark-theme text (`#6B5B5E` → `#988888`), dated 2026-05-11. `Theme.swift` was touched by 4 separate commits. You kept adjusting it and never landed on a value.
- **3.3d Launch behaviour — written down, never decided.** `ARCHITECTURE.md` §5: "Launch shows the standard open panel instead of an untitled window — NSDocument default; owner UX call pending." Confirmed true this session: a cold launch produces a window named `Open`.
- **3.3e Churn hotspots.** `ZenTextView.swift` (12 commits), `ZenTextViewRepresentable.swift` (10), `WhitespaceApp.swift` (10). The caret and the window/document shell are where the repeated rewriting concentrated.

---

## 4. Gap to MVP

**Against the designed MVP in §2.1, there are effectively no gaps.** All nine commitments ship and work. What follows is the gap between "the app works" and "you actually write in it."

| ID | Gap | Evidence | Size | Blocked by |
|---|---|---|---|---|
| 4.1 | Launch opens a file dialog instead of a blank page | Verified: cold launch window is named `Open`; `ARCHITECTURE.md` §5 "owner UX call pending" | S | 4.9 |
| 4.2 | Fullscreen never validated against the design | `fullscreen-debugging`, 0 commits; fade-mask stops and overlay padding hardcoded for a small window (`CanvasView.swift:37–50, 67`) | M | — |
| 4.3 | Typewriter recentering doesn't follow sustained typing | `ARCHITECTURE.md` §5, listed as the sole open bug; decision math tested and exonerated (13 `TypewriterScrollTests` pass) | M | — |
| 4.4 | Caret renders a fraction of a line too high after edits | 94 uncommitted lines in the `frosty-rubin` worktree carrying a full diagnosis; absent from main | S | — |
| 4.5 | P3.7 conversion-warning flow never verified live | `ARCHITECTURE.md` §5 "Pending live verification"; unit-tested only (4 `PlainTextConversionGateTests`) | S | — |
| 4.6 | No app icon | `Assets.xcassets/Contents.json` is 3 lines; no AppIcon set | S | — |
| 4.7 | App only exists inside DerivedData | No signing/notarization/export config in `project.yml`; nothing in /Applications | S | — |
| 4.8 | Dark-mode text legibility unsettled | Uncommitted `Theme.swift` change; 4 commits touching that file | S | 4.2 |
| 4.9 | No decision on what launch and ⌘N should produce | `ARCHITECTURE.md` §5 poses the question and never answers it | S | — (a decision, not work) |
| 4.10 | Two Swift 6 concurrency warnings | `WhitespaceApp.swift:19:26`, `:19:43` | S | — |
| 4.11 | Shortcut overlay omits ⌘⇧M and Enter Full Screen | `ShortcutOverlayView.swift:8–19` vs. the live View menu; `ARCHITECTURE.md` §4.2 requires they stay in sync | S | 4.2 |
| 4.12 | Open Recent never populates | `ARCHITECTURE.md` §5, accepted as-is | S | — (likely permanent; OS-level) |

### 4C. Cut list

Aggressive by request. The goal is an app you use, not a complete one.

| ID | Cut | Size | Rationale |
|---|---|---|---|
| 4C.1 | **Markdown formatting in full** — ⌘B/⌘I, `MarkdownText` encoder + decoder, `PlainTextConversionGate`, per-type editor modes, New Files preference | ~330 src + ~380 test lines | `DESIGN.md` disclaims being a markdown tool. In a distraction-free drafting app, bold and italic are the fiddling the app exists to remove. **Caveat: this is the largest thing in the repo and it works.** It is a product decision, not cleanup — see §6. If it stays, it stays whole; the half-state is worse than either end |
| 4C.2 | Scroll-speed slider | `PreferencesStore.scrollSpeed`, `PreferencesView.swift:117–128` | You will set it once |
| 4C.3 | Shortcut-panel auto-dismiss toggle + delay field | `PreferencesView.swift:130–154`, `CanvasView.swift:82–92`, 2 prefs keys | A preference governing how long a help overlay stays up. Pick 4 seconds, hardcode it |
| 4C.4 | Keybinding Record UI + conflict messaging | `KeybindingsTabView`, ~100 lines | Six delete shortcuts you set once, if ever. The defaults are vim-standard. Keep the *system* (2.1h), drop the GUI |
| 4C.5 | Column-width and line-height pickers | Most of what remains of `PreferencesView` (330 lines) | Set to your preference, hardcode, delete. With 4C.2–4C.4 this collapses Settings to near-nothing |
| 4C.6 | The command palette | `CommandPaletteView.swift`, 125 lines | Since P3.3 removed file-switching it holds exactly two actions — New Document and Open File — both already bound to ⌘N and ⌘O. It is a search field for two items that have keyboard shortcuts |
| 4C.7 | `mockups/` | 536-line HTML | Served its purpose; it describes a UI that now exists |
| 4C.8 | Four stale worktrees, six dead branches | — | After harvesting 4.4 and 4.8. `claude/charming-johnson-8777f1`, `claude/festive-feynman-59ca22`, `refine-shortcuts-panel`, `feat/nsdocument-markdown`, `claude/distracted-ritchie-1ce181` all carry zero commits not already in main |
| 4C.9 | The stash | — | Xcode scheme version churn only |

**Not cut, deliberately:** typewriter centering, the grain background, the theme system, Crimson Pro, the shortcut overlay. Those are the app.

---

## 5. Next-step queue

Ordered by unblocking value — soonest-usable first, not most interesting first.

### 5.1 — Make launch open a blank page

- **Do:** decide and implement what a cold launch and ⌘N produce. Recommended: launch restores the last session, or opens one untitled window. Never the Open panel.
- **Why first:** it is the first three seconds of every single use of this app; it is the one open UX decision you recorded and never made; and it is small. Today, opening your writing app asks you to go find a file — the precise opposite of `DESIGN.md`'s "sitting down with a blank piece of paper."
- **Done when:** launching the built app with no arguments produces a window titled `Untitled` with a caret, and no Open panel appears. Checkable with the same accessibility query used this session — the window list reads `Untitled`, not `Open`.
- **Size:** S — one sitting.

### 5.2 — Port the caret fix off the abandoned worktree

- **Do:** take the 94 uncommitted lines from `.claude/worktrees/frosty-rubin-5724f1`, strip the `#if DEBUG` `/tmp/caretdbg.log` logging, apply to main, add a regression test.
- **Why next:** already diagnosed and already written — the cost is porting, not thinking. A caret that sits a fraction of a line too high after every edit is constant low-grade friction in a typing app.
- **Done when:** clean build, full suite green, and the caret sits on the correct baseline for the first glyph typed on a fresh line and after ⌘Z, observed in the running app.
- **Size:** S.

### 5.3 — Validate and fix fullscreen

- **Do:** run the app fullscreen at your real display size. Check the fade-mask stops, the `geo.size.width / 18` overlay padding, whether `windowDidUpdate` fights AppKit's fullscreen titlebar auto-show, and where the column lands at 2560px wide.
- **Why here:** it is where you stopped, and `[inferred]` 2.3a it is how you intend to use the app. 5.1 and 5.2 are cheap enough to clear first.
- **Done when:** one real writing session fullscreen with no visible chrome, no flicker on titlebar auto-show, and the column and fade mask reading correctly at full width.
- **Size:** M.

### 5.4 — Settle dark-mode text colour

- **Do:** judge the uncommitted `#988888` change fullscreen. Commit it or discard it.
- **Why after 5.3:** you cannot judge reading legibility in a 900×450 window.
- **Done when:** one committed value in `Theme.swift`; the worktree change is gone.
- **Size:** S.

### 5.5 — Fix typewriter recentering under sustained typing

- **Do:** the sole open bug in `ARCHITECTURE.md` §5. The decision math is tested and exonerated; suspect stale TK2 caret geometry in the deferred recenter or the `currentScrollTarget` cache (`ZenTextView.swift:22, 203–250`).
- **Why not earlier:** it is the largest remaining known defect, but it is an M, and 5.3 may change the geometry it operates in.
- **Done when:** typing 40+ continuous lines keeps the caret inside the deadzone throughout, observed in the running app, with `TypewriterScrollTests` still green.
- **Size:** M.

### 5.6 — Install it as a real app

- **Do:** archive and export a signed local build to /Applications; add an app icon (4.6).
- **Why last of the build items:** everything above changes the app. This is the step that turns it into something you launch from Spotlight instead of rebuilding.
- **Done when:** `Whitespace.app` sits in /Applications and launches from Spotlight without Xcode.
- **Size:** S.

### 5.7 — Prune

- **Do:** execute 4C.7–4C.9 (mockups, dead branches and worktrees, stash). Hold 4C.1–4C.6 pending the §6 decision.
- **Done when:** `git branch -a` shows main plus anything live; `git worktree list` shows one entry; `git stash list` is empty.
- **Size:** S.

### Item 1 as a handoff prompt

> In Whitespace, change launch behaviour so that starting the app with no document opens a blank untitled window instead of the standard Open panel. Keep DocumentGroup. Don't add chrome. Build, run the full suite, and verify via the accessibility API that the app's window list shows "Untitled" rather than "Open" on a cold launch.

---

## 6. Open decision

**Does markdown formatting stay?**

It is the largest single item in the repo, the biggest available cut (4C.1), and the one place where shipped code runs against your own stated design philosophy. Items 5.1–5.6 do not depend on the answer; 5.7 and the shape of the codebase from here do.
