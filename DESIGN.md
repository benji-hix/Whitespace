# Whitespace — Design Philosophy

## The Soul

Whitespace is the feeling of sitting down with a blank piece of paper and a pen, and just writing — getting what's on your mind onto the page.

The goal is **calm**, not stillness. Reading-a-book calm, not coding calm.

## What Whitespace Is Not

- **Not Microsoft Word.** Word processors flood the screen with tools, ribbons, distracting chrome, spell check, grammar check. Whitespace has none of that.
- **Not VS Code's Zen mode.** Zen mode strips the chrome but the underlying aesthetic is still a code editor. Writing should feel like reading a book, not like coding.
- **Not iA Writer / Bear / Ulysses-adjacent.** Whitespace doesn't aspire to be a markdown power tool or a library manager. It is a page.

## Typography & Space

- **Typewriter-centered.** The text being worked on stays roughly centered vertically. Your eyes don't move; the page does.
- **Generous margins on all sides** are a *value*, not a default to be overridden. They draw attention to the words.
- **Single column.** Always.
- **Crimson Pro, serif, by default.** Elegant and modern. Serif because writing should feel like reading a book.

## Chrome, Color, Motion

- **Zero visible UI while writing.** No toolbars, no sidebars, no status bars, no buttons, no badges.
- **Monochrome.** Color is not used for decoration or affordance.
- **The only motion is smooth scrolling.** Cursor and text transitions exist to feel natural, not to perform.
- Calmness is the goal. Stillness would be sterile; calm is alive but unhurried.

## The Forbidden List

These are rejected even if users ask:

- **No visible "show shortcuts" button.** Users learn the shortcut for the shortcut overlay, or use the File menu. Discoverability does not justify chrome.
- **No font/formatting ribbon or toolbar.** The point of the app is to eliminate the choices that pull attention away from the words.
- **No persistent UI affordances** of any kind in the writing surface.

The pattern: any feature whose value is "lets the user fiddle with presentation" is the wrong feature. The app exists to remove those choices, not to surface them.

## Decision Heuristic

When evaluating any new feature or change, ask:

1. Does this make the page feel more like paper, or less?
2. Does this draw attention to the words, or away from them?
3. Is the affordance earning its visual weight, or is it chrome?

If the answer pulls toward Word, VS Code, or a settings panel — it's the wrong direction.
