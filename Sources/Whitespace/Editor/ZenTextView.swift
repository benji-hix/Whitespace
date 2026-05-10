// Sources/Whitespace/Editor/ZenTextView.swift
import AppKit

final class ZenTextView: NSTextView {
    var onTextChange: ((String) -> Void)?
    var keybindingStore: KeybindingStore?

    /// Multiplier for scroll-animation pace. Higher = faster, lower = slower.
    /// 1.0 is the tuned default; the Settings slider exposes 0.4 ... 2.0.
    var scrollSpeed: Double = 1.0

    var onToggleCommandPalette: (() -> Void)?
    var onToggleShortcutOverlay: (() -> Void)?
    var onToggleTheme: (() -> Void)?
    var onSave: (() -> Void)?
    var onSaveAs: (() -> Void)?
    var onOpen: (() -> Void)?
    var onNew: (() -> Void)?
    var onIncreaseFontSize: (() -> Void)?
    var onDecreaseFontSize: (() -> Void)?

    // Last committed scroll target. Used only to short-circuit redundant
    // retargets (sub-pixel rounding, repeated selection notifications). NaN
    // means "uninitialized — next recenter must run."
    private var currentScrollTarget: CGFloat = .nan

    // Document-character offset of the start of the paragraph currently
    // being held centered. nil means "no paragraph anchored — next recenter
    // treats the caret's paragraph as a fresh anchor."
    private var centeredParagraphOffset: Int?

    // Manual cursor blink. AppKit's built-in blink is unreliable when
    // NSTextView is SwiftUI-hosted, so we drive it ourselves.
    private var blinkTimer: Timer?
    private var cursorOn: Bool = true

    // Dedicated subview for our caret. Adding it as an NSView (rather than
    // drawing into NSTextView's draw(_:)) means AppKit handles dirty-rect
    // invalidation when the caret moves — no afterimages — and the caret
    // doesn't compete with TK2's text sublayers.
    private let cursorView: CursorBarView = {
        let v = CursorBarView()
        v.isHidden = true
        v.wantsLayer = true
        return v
    }()

    // MARK: - Init (TextKit 2 stack)

    override convenience init(frame: NSRect) {
        let contentStorage = NSTextContentStorage()
        let layoutManager  = NSTextLayoutManager()
        let container = NSTextContainer(
            size: NSSize(width: frame.width, height: .greatestFiniteMagnitude)
        )
        container.widthTracksTextView = true
        layoutManager.textContainer = container
        contentStorage.addTextLayoutManager(layoutManager)
        self.init(frame: frame, textContainer: container)
    }

    override init(frame: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    // MARK: - Configuration

    private func configure() {
        isRichText                           = true
        importsGraphics                      = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticQuoteSubstitutionEnabled  = false
        isAutomaticDashSubstitutionEnabled   = false
        isAutomaticTextReplacementEnabled    = false
        isAutomaticTextCompletionEnabled     = false
        isGrammarCheckingEnabled             = false
        isContinuousSpellCheckingEnabled     = false
        drawsBackground                      = false
        backgroundColor                      = .clear
        textContainerInset                   = NSSize(width: 0, height: 48)
        isVerticallyResizable                = true
        isHorizontallyResizable              = false
        autoresizingMask                     = [.width]

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSelectionChange(_:)),
            name: NSTextView.didChangeSelectionNotification,
            object: self
        )

        addSubview(cursorView)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        // blinkTimer is invalidated in viewDidMoveToWindow when the window
        // becomes nil — we can't touch a non-Sendable Timer from a
        // nonisolated deinit under Swift 6 strict concurrency.
    }

    // MARK: - Typewriter mode (single scroll authority)

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window = window else {
            stopCursorBlink()
            return
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: window
        )
        // TK2 NSTextView renders its caret via an NSTextInsertionIndicator
        // subview, not via drawInsertionPoint. Hide any that are already
        // present so our custom draw can take over.
        hideSystemInsertionIndicators()
        startCursorBlink()
        DispatchQueue.main.async { [weak self] in
            self?.updateTypewriterInsets()
            self?.recenter(animated: false)
        }
    }

    /// New insertion-indicator views can be added at any time. Catch each
    /// one and suppress it so only our custom cursor draws.
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        suppressInsertionIndicators(in: subview)
    }

    /// Walk a view tree and hide any `NSTextInsertionIndicator` we find,
    /// including private subclasses. NSTextView frequently nests the
    /// indicator inside an internal container view, so a single-level
    /// `subviews` check misses it; matching by class-name string also
    /// catches `_NSTextInsertionIndicator`-style internal subclasses.
    /// Defense in depth: `displayMode = .hidden`, `isHidden = true`, and
    /// `frame = .zero` so even if NSTextView resets one, the others hold.
    private func suppressInsertionIndicators(in view: NSView) {
        let typeName = String(describing: type(of: view))
        if typeName.contains("InsertionIndicator") {
            if #available(macOS 14, *), let indicator = view as? NSTextInsertionIndicator {
                indicator.displayMode = .hidden
            }
            view.isHidden = true
            view.frame = .zero
            view.alphaValue = 0
            view.layer?.opacity = 0
        }
        for sub in view.subviews {
            suppressInsertionIndicators(in: sub)
        }
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        // Last line of defense: re-suppress before every draw cycle so a
        // momentarily un-hidden indicator can't reach the screen.
        hideSystemInsertionIndicators()
    }

    override func mouseDown(with event: NSEvent) {
        // Suppress before super so the indicator can't flash during
        // super's caret-placement work. Also after, in case super un-hid it.
        hideSystemInsertionIndicators()
        super.mouseDown(with: event)
        hideSystemInsertionIndicators()
    }

    private func hideSystemInsertionIndicators() {
        // The indicator may be added as a sibling (in the clip view or
        // scroll view), not as a descendant of self. Walk the entire
        // window's content view to catch it wherever it lives.
        let root: NSView = window?.contentView ?? self
        suppressInsertionIndicators(in: root)
    }

    @objc private func windowDidResize(_ note: Notification) {
        // Resize changes the inset and viewport dimensions — re-anchor the
        // paragraph as if it were a fresh selection so the caret lands at a
        // known position rather than wherever the deadzone math drifts to.
        invalidateScrollAnchor()
        updateTypewriterInsets()
        recenter(animated: false)
    }

    private func updateTypewriterInsets() {
        guard let scrollView = enclosingScrollView else { return }
        let half = scrollView.contentSize.height / 2
        guard abs(textContainerInset.height - half) > 1 else { return }
        textContainerInset = NSSize(width: 0, height: half)
    }

    /// Reset the cached scroll target and paragraph anchor. Call after
    /// wholesale text replacement (file open / new doc) so the next
    /// recenter is unconditional.
    func invalidateScrollAnchor() {
        currentScrollTarget = .nan
        centeredParagraphOffset = nil
    }

    /// AppKit calls this when something asks the scroll view to bring a
    /// range into view (paste, find, programmatic caret moves, IME, …).
    /// We route everything through `recenter` so there is exactly one
    /// authority for viewport position. The default implementation would
    /// instant-scroll and fight our typewriter animation.
    override func scrollRangeToVisible(_ range: NSRange) {
        recenter(animated: true)
    }

    @objc private func handleSelectionChange(_ note: Notification) {
        resetCursorBlink()
        // NSTextView may re-add or un-hide the system insertion indicator
        // when the caret moves — re-suppress on every selection change.
        hideSystemInsertionIndicators()
        // Defer one runloop turn so layout from the triggering edit has
        // settled before we ask TK2 for the caret rect.
        DispatchQueue.main.async { [weak self] in
            self?.recenter(animated: true)
            self?.hideSystemInsertionIndicators()
        }
    }

    /// The single source of truth for viewport position. Computes the
    /// target Y from the caret, then either snaps or animates the clip
    /// view's bounds origin. Re-issuing the same target is a no-op.
    private func recenter(animated: Bool) {
        guard let scrollView = enclosingScrollView else { return }
        // Active selection ranges shouldn't move the viewport — ⌘A,
        // shift-arrow, drag-select would otherwise jump us.
        if selectedRange().length > 0 { return }
        guard let target = caretCenterTargetY() else { return }

        if !animated {
            currentScrollTarget = target
            scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: target))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            return
        }

        if abs(target - currentScrollTarget) < 0.5 { return }
        let currentY = scrollView.contentView.bounds.origin.y
        let distance = abs(target - currentY)
        currentScrollTarget = target

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = kineticDuration(forDistance: distance)
            ctx.timingFunction = kineticTiming(forDistance: distance)
            ctx.allowsImplicitAnimation = true
            scrollView.contentView.animator().setBoundsOrigin(
                NSPoint(x: 0, y: target)
            )
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// Distance-scaled animation duration, divided by the user's
    /// scroll-speed multiplier (Settings → Editor → Scroll Speed).
    /// Constants below are the post-tuning baseline (formerly experienced
    /// as "0.62x" before the slider was zeroed to that value).
    private func kineticDuration(forDistance distance: CGFloat) -> TimeInterval {
        let scaled = TimeInterval(distance / 680)
        let base = min(1.13, max(0.68, scaled))
        return base / max(0.05, scrollSpeed)
    }

    /// Kinetic ease curve. Both curves bias the cubic-bezier's second
    /// control point toward `(0, 1)` so the animation spends a long tail
    /// approaching its final value — a slow, lingering settle.
    private func kineticTiming(forDistance distance: CGFloat) -> CAMediaTimingFunction {
        if distance < 150 {
            // Pronounced ease-in into a long soft tail.
            return CAMediaTimingFunction(controlPoints: 0.5, 0.0, 0.08, 1.0)
        } else {
            // Faster mid-travel, even longer settle.
            return CAMediaTimingFunction(controlPoints: 0.3, 0.5, 0.04, 1.0)
        }
    }

    /// Compute the desired clip-view bounds origin Y for the current caret.
    ///
    /// Two regimes:
    /// 1. **Paragraph change.** When the caret enters a different paragraph
    ///    (click, Enter, arrow across boundary), animate to put that
    ///    paragraph's midpoint at ~45% of the viewport. If the paragraph is
    ///    taller than the viewport's middle 70%, clamp so the caret stays
    ///    visible.
    /// 2. **Within the same paragraph.** Hold position unless the caret
    ///    leaves the central deadzone (middle 60% of viewport). When it
    ///    does, scroll just enough to bring it to the deadzone edge it
    ///    crossed — typewriter "page flip" feel without per-keystroke drift.
    ///
    /// Returns nil to mean "don't scroll" — used in the deadzone case.
    private func caretCenterTargetY() -> CGFloat? {
        guard let tlm = textLayoutManager,
              let scrollView = enclosingScrollView,
              scrollView.contentSize.height > 0 else { return nil }

        let caret: NSTextLocation
        if let selection = tlm.textSelections.first?.textRanges.first {
            caret = selection.location
        } else {
            caret = tlm.documentRange.location
        }

        let caretRange = NSTextRange(location: caret)
        // TK2 layout is lazy. Force the caret region current before we
        // ask for geometry — otherwise we read pre-edit rects.
        tlm.ensureLayout(for: caretRange)

        var caretFrame: CGRect = .null
        tlm.enumerateTextSegments(
            in: caretRange,
            type: .selection,
            options: [.rangeNotRequired]
        ) { _, segmentFrame, _, _ in
            caretFrame = segmentFrame
            return false
        }
        guard !caretFrame.isNull,
              let fragment = tlm.textLayoutFragment(for: caret),
              let elementRange = fragment.textElement?.elementRange else {
            return nil
        }

        let inset          = textContainerOrigin.y
        let visibleHeight  = scrollView.contentSize.height
        let currentY       = scrollView.contentView.bounds.origin.y
        let paragraphMidY  = fragment.layoutFragmentFrame.midY + inset
        let caretMinY      = caretFrame.minY + inset
        let caretMaxY      = caretFrame.maxY + inset
        let paragraphOffset = tlm.offset(
            from: tlm.documentRange.location,
            to: elementRange.location
        )

        let paragraphChanged = (centeredParagraphOffset != paragraphOffset)
        centeredParagraphOffset = paragraphOffset

        if paragraphChanged {
            // Place paragraph midpoint at 45% of the viewport.
            var target = paragraphMidY - visibleHeight * 0.45
            // Caret-visibility safety net: paragraph taller than the safe
            // zone falls back to caret-line clamping so the cursor stays
            // inside the middle 70% of the viewport.
            let safeMin = visibleHeight * 0.15
            let safeMax = visibleHeight * 0.85
            let caretMinAtTarget = caretMinY - target
            let caretMaxAtTarget = caretMaxY - target
            if caretMinAtTarget < safeMin {
                target = caretMinY - safeMin
            } else if caretMaxAtTarget > safeMax {
                target = caretMaxY - safeMax
            }
            return max(0, target.rounded())
        }

        // Same paragraph: hold position unless the caret leaves the deadzone.
        let deadzoneTop    = currentY + visibleHeight * 0.30
        let deadzoneBottom = currentY + visibleHeight * 0.70
        if caretMinY >= deadzoneTop && caretMaxY <= deadzoneBottom {
            return nil
        }
        let target: CGFloat
        if caretMaxY > deadzoneBottom {
            // Caret fell below — scroll so the caret returns to the top of
            // the deadzone, giving room to keep writing downward.
            target = caretMinY - visibleHeight * 0.30
        } else {
            // Caret rose above — symmetric: caret to the deadzone bottom.
            target = caretMaxY - visibleHeight * 0.70
        }
        return max(0, target.rounded())
    }

    // MARK: - Cursor

    /// Compute the cursor bar's rect in this text view's coordinate space.
    ///
    /// Two-tier strategy:
    /// 1. **Preferred:** read the baseline from TK2's actual rendered
    ///    layout via `NSTextLineFragment.glyphOrigin` (no font-metric
    ///    assumptions, baseline-correct by construction).
    /// 2. **Fallback:** if any of TK2's layout queries return nil/empty
    ///    (which happens at end-of-text and during early layout passes),
    ///    derive the baseline from the segment frame minus `|descender|`.
    ///    This is a few pixels off in worst cases but keeps the cursor
    ///    visible — much better than returning nil and hiding it.
    private func currentCursorBarRect() -> NSRect? {
        guard selectedRange().length == 0,
              let tlm = textLayoutManager else { return nil }
        let caret = tlm.textSelections.first?.textRanges.first?.location
            ?? tlm.documentRange.location
        let caretRange = NSTextRange(location: caret)
        tlm.ensureLayout(for: caretRange)

        var caretFrame: CGRect = .null
        tlm.enumerateTextSegments(
            in: caretRange,
            type: .selection,
            options: [.rangeNotRequired]
        ) { _, segmentFrame, _, _ in
            caretFrame = segmentFrame
            return false
        }
        guard !caretFrame.isNull else { return nil }

        let font = typingAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 18)
        let baselineY = preciseBaselineY(at: caret, caretFrame: caretFrame, tlm: tlm)
            ?? (caretFrame.maxY + textContainerOrigin.y - abs(font.descender))

        // Extend 2pt below the baseline so the cursor reads as anchored
        // to the text rather than floating above it. Cap-tall bars that
        // end exactly at baseline visually appear a hair too high.
        let belowBaselineExtension: CGFloat = 2
        let cursorBottomY = (baselineY + belowBaselineExtension).rounded()
        let cursorTopY = (baselineY - font.ascender).rounded()
        let cursorX = (caretFrame.minX + textContainerOrigin.x + 1).rounded()

        return NSRect(
            x: cursorX,
            y: cursorTopY,
            width: 1.0,
            height: max(1, cursorBottomY - cursorTopY)
        )
    }

    /// Try to read the baseline Y from TK2's layout fragments. Returns nil
    /// if the fragment / line fragment lookup fails — caller falls back to
    /// segment-based approximation.
    private func preciseBaselineY(
        at caret: NSTextLocation,
        caretFrame: CGRect,
        tlm: NSTextLayoutManager
    ) -> CGFloat? {
        // textLayoutFragment(for:) can return nil for end-of-text. If so,
        // step back one location and try again — that catches the fragment
        // for the last real character.
        var fragment = tlm.textLayoutFragment(for: caret)
        if fragment == nil,
           let prev = tlm.location(caret, offsetBy: -1) {
            fragment = tlm.textLayoutFragment(for: prev)
        }
        guard let layoutFragment = fragment else { return nil }

        let fragmentFrame = layoutFragment.layoutFragmentFrame
        let caretYInFragment = caretFrame.midY - fragmentFrame.origin.y
        let pickedLineFragment =
            layoutFragment.textLineFragments.first(where: { lf in
                lf.typographicBounds.minY <= caretYInFragment
                    && caretYInFragment <= lf.typographicBounds.maxY
            })
            ?? layoutFragment.textLineFragments.last
            ?? layoutFragment.textLineFragments.first
        guard let lineFragment = pickedLineFragment else { return nil }

        let baselineInFragment =
            lineFragment.typographicBounds.origin.y + lineFragment.glyphOrigin.y
        let baselineInContainer = fragmentFrame.origin.y + baselineInFragment
        return baselineInContainer + textContainerOrigin.y
    }

    /// Update `cursorView`'s frame and visibility from the current caret
    /// state. Call whenever the caret may have moved or the blink state
    /// toggled. AppKit invalidates the old + new frames automatically.
    private func updateCursorView() {
        guard cursorOn, let bar = currentCursorBarRect() else {
            cursorView.isHidden = true
            return
        }
        // The theme's cursor color is 0.5 alpha for a soft system-cursor
        // look, but with our thinner 1pt bar that reads as faint. Bump
        // alpha so the cursor reads as confidently present.
        cursorView.color = insertionPointColor.withAlphaComponent(0.85)
        cursorView.frame = bar
        cursorView.isHidden = false
    }

    private func startCursorBlink() {
        stopCursorBlink()
        cursorOn = true
        updateCursorView()
        let timer = Timer(timeInterval: 0.53, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.cursorOn.toggle()
                self.updateCursorView()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        blinkTimer = timer
    }

    private func stopCursorBlink() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        cursorOn = true
    }

    /// Re-phase the blink so the cursor is solid for a full on-cycle right
    /// after user activity (typing, clicking, arrow keys).
    private func resetCursorBlink() {
        guard blinkTimer != nil else { return }
        cursorOn = true
        updateCursorView()
        startCursorBlink()
    }

    // MARK: - Apply Theme/Prefs

    func applyTheme(_ theme: Theme) {
        applyColors(text: theme.textColor, cursor: theme.cursorColor, selection: theme.selectionColor)
    }

    func applyColors(text: NSColor, cursor: NSColor, selection: NSColor) {
        textColor                  = text
        insertionPointColor        = cursor
        selectedTextAttributes     = [.backgroundColor: selection]
        var attrs = typingAttributes
        attrs[.foregroundColor] = text
        typingAttributes = attrs
        // Re-color any already-laid-out glyphs so the body text follows the
        // animated tint, not just future typing.
        if let storage = textStorage, storage.length > 0 {
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: text, range: NSRange(location: 0, length: storage.length))
            storage.endEditing()
        }
    }

    func applyFont(size: CGFloat, lineHeightMultiple: CGFloat) {
        let pStyle = NSMutableParagraphStyle()
        pStyle.lineHeightMultiple = lineHeightMultiple
        pStyle.paragraphSpacing = 4
        pStyle.firstLineHeadIndent = size * 2
        let regularFont = NSFont(name: WhitespaceFont.regular, size: size) ?? NSFont.systemFont(ofSize: size)
        typingAttributes = [.font: regularFont, .paragraphStyle: pStyle]
        guard let storage = textStorage, storage.length > 0 else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            let name = fontName(bold: isBoldFont(value as? NSFont), italic: isItalicFont(value as? NSFont))
            let font = NSFont(name: name, size: size) ?? regularFont
            storage.addAttributes([.font: font, .paragraphStyle: pStyle], range: range)
        }
        storage.endEditing()
    }

    // MARK: - Bold / Italic

    private func isBoldFont(_ font: NSFont?) -> Bool {
        guard let name = font?.fontName else { return false }
        return name == WhitespaceFont.bold || name == WhitespaceFont.boldItalic
    }

    private func isItalicFont(_ font: NSFont?) -> Bool {
        guard let name = font?.fontName else { return false }
        return name == WhitespaceFont.italic || name == WhitespaceFont.boldItalic
    }

    private func fontName(bold: Bool, italic: Bool) -> String {
        switch (bold, italic) {
        case (true,  true):  return WhitespaceFont.boldItalic
        case (true,  false): return WhitespaceFont.bold
        case (false, true):  return WhitespaceFont.italic
        case (false, false): return WhitespaceFont.regular
        }
    }

    private func toggleBold() {
        let currentFont = selectedFont()
        let newName = fontName(bold: !isBoldFont(currentFont), italic: isItalicFont(currentFont))
        applyFontVariant(named: newName, size: currentFont?.pointSize ?? CGFloat(16))
    }

    private func toggleItalic() {
        let currentFont = selectedFont()
        let newName = fontName(bold: isBoldFont(currentFont), italic: !isItalicFont(currentFont))
        applyFontVariant(named: newName, size: currentFont?.pointSize ?? CGFloat(16))
    }

    private func selectedFont() -> NSFont? {
        let range = selectedRange()
        if range.length > 0 {
            return textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        }
        return typingAttributes[.font] as? NSFont
    }

    private func applyFontVariant(named name: String, size: CGFloat) {
        guard let newFont = NSFont(name: name, size: size) else { return }
        let range = selectedRange()
        if range.length > 0 {
            textStorage?.addAttribute(.font, value: newFont, range: range)
        }
        var attrs = typingAttributes
        attrs[.font] = newFont
        typingAttributes = attrs
    }

    // MARK: - keyDown

    override func keyDown(with event: NSEvent) {
        let flags  = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd    = flags.contains(.command)
        let shift  = flags.contains(.shift)
        let ctrl   = flags.contains(.control)

        // App-level shortcuts (keyCode constants: P=35, /=44, D=2, S=1, O=31, N=45, +=24, -=27)
        if cmd && !shift && !ctrl && event.keyCode == 6  { undoManager?.undo();       return }  // ⌘Z
        if cmd && shift  && !ctrl && event.keyCode == 6  { undoManager?.redo();       return }  // ⌘⇧Z
        if cmd && !shift && !ctrl && event.keyCode == 11 { toggleBold();              return }  // ⌘B
        if cmd && !shift && !ctrl && event.keyCode == 34 { toggleItalic();            return }  // ⌘I
        if cmd && !shift && !ctrl && event.keyCode == 35 { onToggleCommandPalette?(); return }  // ⌘P
        if cmd && !shift && !ctrl && event.keyCode == 44 { onToggleShortcutOverlay?(); return } // ⌘/
        if cmd && shift  && !ctrl && event.keyCode == 2  { onToggleTheme?();          return }  // ⌘⇧D
        if cmd && !shift && !ctrl && event.keyCode == 1  { onSave?();                 return }  // ⌘S
        if cmd && shift  && !ctrl && event.keyCode == 1  { onSaveAs?();               return }  // ⌘⇧S
        if cmd && !shift && !ctrl && event.keyCode == 31 { onOpen?();                 return }  // ⌘O
        if cmd && !shift && !ctrl && event.keyCode == 45 { onNew?();                  return }  // ⌘N
        if cmd && !shift && !ctrl && event.keyCode == 24 { onIncreaseFontSize?();     return }  // ⌘+
        if cmd && !shift && !ctrl && event.keyCode == 27 { onDecreaseFontSize?();     return }  // ⌘-

        let pressed = ShortcutBinding(
            keyCode: event.keyCode,
            modifiers: UInt64(flags.rawValue) & ShortcutBinding.modifierMask
        )
        if let store = keybindingStore {
            for action in KeybindingAction.allCases {
                if store.binding(for: action) == pressed {
                    perform(action)
                    return
                }
            }
        }

        super.keyDown(with: event)
    }

    // MARK: - Text Manipulation

    private func perform(_ action: KeybindingAction) {
        switch action {
        case .deleteWordLeft:    deleteWordBackward(nil)
        case .deleteWordRight:   deleteWordForward(nil)
        case .deleteToLineStart: deleteToBeginningOfLine(nil)
        case .deleteToLineEnd:   deleteToEndOfLine(nil)
        case .killLine:          killLine()
        case .deleteCharForward: deleteForward(nil)
        }
    }

    private func killLine() {
        guard let storage = textStorage else { return }
        let str = storage.string as NSString
        let loc = selectedRange().location
        let lineRange = str.lineRange(for: NSRange(location: loc, length: 0))
        let restLength = lineRange.upperBound - loc
        if restLength > 0 {
            replaceCharacters(in: NSRange(location: loc, length: restLength), with: "")
        }
    }

    override func didChangeText() {
        super.didChangeText()
        onTextChange?(string)
        resetCursorBlink()
    }
}

/// Tiny NSView that draws a single colored bar filling its bounds.
/// Used as a sibling/subview overlay for the caret so AppKit handles
/// invalidation of the old + new frames automatically when the caret
/// moves — no afterimages, no fighting NSTextView's text sublayers.
final class CursorBarView: NSView {
    var color: NSColor = .black {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // Layer-backed NSViews get a default ~0.25s implicit CALayer animation
    // on position/bounds/hidden, which makes the caret slide to a new line
    // (e.g. after pressing Enter) instead of snapping. Suppress all the
    // implicit actions so the cursor moves instantaneously.
    override func makeBackingLayer() -> CALayer {
        let layer = CALayer()
        layer.actions = [
            "position": NSNull(),
            "bounds":   NSNull(),
            "frame":    NSNull(),
            "hidden":   NSNull(),
            "opacity":  NSNull(),
        ]
        return layer
    }

    override func draw(_ dirtyRect: NSRect) {
        color.set()
        bounds.fill()
    }
}
