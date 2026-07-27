# Building and installing Whitespace

One command rebuilds the app and replaces the copy in `/Applications`:

```bash
cd /Users/benji/Code/Whitespace && \
xcodebuild build -project Whitespace.xcodeproj -scheme Whitespace -configuration Release -destination 'platform=macOS' && \
pkill -x Whitespace; \
ditto ~/Library/Developer/Xcode/DerivedData/Whitespace-*/Build/Products/Release/Whitespace.app /Applications/Whitespace.app && \
open /Applications/Whitespace.app
```

`ditto` replaces the bundle wholesale rather than merging into it, so stale files
from an older build cannot survive. `pkill` first because macOS will not cleanly
replace a running bundle.

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
