# Building and installing Whitespace

Quit Whitespace first, the normal way, so every window is saved or you choose
what happens to it. Then, from the repo on an up-to-date `main`:

```bash
cd /Users/benji/Code/Whitespace && \
if pgrep -x Whitespace >/dev/null; then echo "Whitespace is running: quit it first"; false; else \
  B=/tmp/whitespace-release && \
  xcodebuild build -project Whitespace.xcodeproj -scheme Whitespace -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$B" && \
  rm -rf /Applications/Whitespace.app.new && \
  ditto "$B/Build/Products/Release/Whitespace.app" /Applications/Whitespace.app.new && \
  { [ ! -e /Applications/Whitespace.app ] || trash /Applications/Whitespace.app; } && \
  mv /Applications/Whitespace.app.new /Applications/Whitespace.app && \
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -u "$B/Build/Products/Release/Whitespace.app" && \
  rm -rf "$B" && \
  open /Applications/Whitespace.app
fi
```

Why each step:

- **It refuses to run while Whitespace is open** rather than killing it. A
  forced quit skips the save and Keep/Delete prompts, and an open window may
  hold writing that has not reached disk.
- **The build goes to its own folder**, not Xcode's DerivedData. Every
  worktree and checkout gets its own `DerivedData/Whitespace-*` folder, so a
  wildcard there can match an old build and install it.
- **The new bundle is copied beside the old one, then swapped in.** `ditto`
  onto an existing folder merges into it, so files from an older build would
  survive. The old app goes to the Trash, so it can be put back.
- **The build is unregistered and deleted afterwards.** macOS registers an
  app as soon as it is built. Every build carries the bundle
  id `com.benji.Whitespace`, and macOS may open any copy it knows about when
  Whitespace is launched by name. Debug builds in `/tmp/whitespace-dd` have the
  same problem; launch those by path (`open -n …`), as `CLAUDE.md` does.

To see which copies macOS knows about:

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump | awk '/^path:/{p=$2} /identifier: +com.benji.Whitespace$/{print p}' | sort -u
```

Forget a stale one with `lsregister -u <path to .app>`, then move it to the
Trash.

## Signing

Ad-hoc, which is what `xcodebuild` does by default with no Developer ID
configured — `Signature=adhoc`, `TeamIdentifier=not set`. That is deliberate:
this is a personal app, ad-hoc needs no paid account, and Gatekeeper accepts a
locally built bundle that never travelled through quarantine.

The trade-off: the bundle is not notarized, so copying it to another Mac (or
downloading it) triggers Gatekeeper's unidentified-developer block. If the app
ever needs to run anywhere else, that is the point to buy a Developer ID and
switch — not before.

Verify a build's signature with:

```bash
codesign --verify --deep --strict /Applications/Whitespace.app
```

## Versioning

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` live in `project.yml`, not in
the Xcode project — `project.pbxproj` and `Info.plist` are generated. Edit
`project.yml`, then run `xcodegen generate`.

1.0 (build 1) was declared on 2026-07-26. The app reached its designed MVP in
April 2026 and simply never had a version pinned to it.

## Requirements

Xcode 26.6 or later, and `xcodegen` (`brew install xcodegen`) whenever files are
added or build settings change.
