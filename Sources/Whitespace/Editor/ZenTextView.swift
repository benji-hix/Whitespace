// Sources/Whitespace/Editor/ZenTextView.swift
import AppKit
import Carbon

final class ZenTextView: NSTextView {
    var onTextChange: ((String) -> Void)?
    var keybindingStore: KeybindingStore?

    // MARK: - Typewriter smooth scroll state
    private var scrollTimer: Timer?
    private var scrollTargetY: CGFloat = 0
    private var scrollCurrentY: CGFloat = 0
    // The starting character index of the visual line that contains the
    // cursor as of the most recent target compute. Used to detect "still on
    // the same line" and skip retargeting entirely. -1 means "uninitialized,
    // always retarget on next call" (initial state and after external text
    // replacement via invalidateScrollAnchor()).
    private var lastLineCharLocation: Int = -1

    // MARK: - Kinetic wheel scroll state
    private var wheelTimer: Timer?
    private var wheelVelocity: CGFloat = 0

    // Callbacks for overlay/app control (set by ZenTextViewRepresentable)
    var onToggleCommandPalette: (() -> Void)?
    var onToggleShortcutOverlay: (() -> Void)?
    var onToggleTheme: (() -> Void)?
    var onSave: (() -> Void)?
    var onSaveAs: (() -> Void)?
    var onOpen: (() -> Void)?
    var onNew: (() -> Void)?
    var onIncreaseFontSize: (() -> Void)?
    var onDecreaseFontSize: (() -> Void)?

    // MARK: - Init (mirrors ClearText pattern)

    override convenience init(frame: NSRect) {
        let storage   = NSTextStorage()
        let layout    = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: frame.width, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
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
    }

    // MARK: - Typewriter mode

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard let scrollView = enclosingScrollView else { return }
        scrollView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollViewFrameChanged(_:)),
            name: NSView.frameDidChangeNotification,
            object: scrollView
        )
        updateTypewriterInsets()
        // Snap the scroll to the centered cursor position now, so the first
        // user interaction (e.g. typing the first character) doesn't trigger
        // a one-time animated catch-up from y=0 to the centered target.
        DispatchQueue.main.async { [weak self] in self?.scrollToCurrentLine(snap: true) }
    }

    @objc private func scrollViewFrameChanged(_ note: Notification) {
        updateTypewriterInsets()
        // Snap (not animate) on layout/resize. Without this, the initial
        // centering after first layout runs a smooth animation from y=0 to
        // the centered target — and if the user starts typing before that
        // animation finishes, the keystroke *appears* to cause a vertical
        // shift. It doesn't; it's the init centering still playing out.
        // Window resizes also feel snappier this way.
        scrollToCurrentLine(snap: true)
    }

    override func scrollRangeToVisible(_ range: NSRange) {
        // Suppressed: our typewriter smooth scroll owns all scroll positioning.
        // NSTextView's default implementation would instant-scroll on every
        // keystroke, fighting the smooth scroll timer and causing jitter.
    }

    private func updateTypewriterInsets() {
        guard let scrollView = enclosingScrollView else { return }
        let half = scrollView.contentSize.height / 2
        guard abs(textContainerInset.height - half) > 1 else { return }
        textContainerInset = NSSize(width: 0, height: half)
    }

    /// Reset the line anchor so the next scrollToCurrentLine call always
    /// recomputes its target. Call this when text is replaced wholesale
    /// (file open / new doc) — the previously-tracked character index no
    /// longer refers to the same logical line in the new content.
    func invalidateScrollAnchor() {
        lastLineCharLocation = -1
    }

    private func scrollToCurrentLine(snap: Bool = false) {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer,
              let scrollView = enclosingScrollView else { return }
        // When the user selects a range (⌘A, shift-arrow, drag), there's no
        // single cursor position to center on. Reading selectedRange().location
        // would jump us to the selection's start, causing an unwanted scroll on
        // ⌘A. Leave the scroll position alone while a selection is active.
        if selectedRange().length > 0 { return }
        // Force layout to be current. NSLayoutManager is lazy: a fresh edit
        // invalidates fragments but doesn't recompute them until something
        // queries layout. If we ask for lineFragmentRect / extraLineFragmentRect
        // before recomputation, we get stale rects from before the edit and our
        // target disagrees with the post-edit reality — visible as a shift on
        // the *next* keystroke when the layout has caught up.
        layoutManager.ensureLayout(for: textContainer)

        // Identify which visual line the cursor is on, by its starting character
        // index. The previous approach of recomputing a target Y on every
        // selection change and trusting a half-line threshold to filter noise
        // worked mid-line but failed on the first 1-2 characters of a new line:
        // the formula switches branches (extraLineFragmentRect → lineFragmentRect)
        // and AppKit's accounting for the two rects differs by a few pixels even
        // when nothing visually moved. Anchoring on the line's *character index*
        // sidesteps that: same line ⇒ same anchor ⇒ skip target compute entirely.
        let cursorLoc = selectedRange().location
        let textLength = (string as NSString).length

        let lineCharLocation: Int
        let lineRectMinY: CGFloat
        if layoutManager.numberOfGlyphs == 0 {
            lineCharLocation = 0
            lineRectMinY = 0
        } else {
            let extraRect = layoutManager.extraLineFragmentRect
            if cursorLoc >= textLength && extraRect != .zero {
                // Phantom line after a trailing newline. Its anchor is textLength
                // — which equals the character index of the first character the
                // user is about to type. That makes the transition phantom-line
                // → first-character-on-new-line a no-op for the line tracker.
                lineCharLocation = textLength
                lineRectMinY = extraRect.minY
            } else {
                let clampedChar = max(0, min(cursorLoc, textLength - 1))
                let glyphRange = layoutManager.glyphRange(
                    forCharacterRange: NSRange(location: clampedChar, length: 0),
                    actualCharacterRange: nil
                )
                let gi = glyphRange.location == NSNotFound
                    ? 0
                    : min(glyphRange.location, layoutManager.numberOfGlyphs - 1)
                var effectiveGlyphRange = NSRange()
                let lineRect = layoutManager.lineFragmentRect(
                    forGlyphAt: gi,
                    effectiveRange: &effectiveGlyphRange
                )
                let charRange = layoutManager.characterRange(
                    forGlyphRange: effectiveGlyphRange,
                    actualGlyphRange: nil
                )
                lineCharLocation = charRange.location
                lineRectMinY = lineRect.minY
            }
        }

        // Same visual line as last call ⇒ nothing to do. This is the fix that
        // the previous formula-tweaking passes were chasing: don't recompute a
        // target Y at all when the cursor is still on the same line, so AppKit
        // rect noise can't translate into a visible shift.
        if !snap && lineCharLocation == lastLineCharLocation { return }
        lastLineCharLocation = lineCharLocation

        let font = (typingAttributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 18)
        let pStyle = typingAttributes[.paragraphStyle] as? NSParagraphStyle
        let lhm = (pStyle?.lineHeightMultiple ?? 0) > 0 ? pStyle!.lineHeightMultiple : 1.0
        let stableHeight = (font.ascender - font.descender + font.leading) * lhm
        // Anchor on lineRect.minY + half the typing font's line height,
        // not lineRect.midY. NSLayoutManager grows the fragment vertically
        // when a tall glyph (descender, cap, '(', etc.) lands on the line —
        // midY would shift by 1–2px on first occurrence. minY is stable.
        let lineMidY = lineRectMinY + stableHeight * 0.5 + textContainerInset.height
        let visibleHeight = scrollView.contentSize.height
        let newTarget = (max(0, lineMidY - visibleHeight * 0.45)).rounded()
        // Secondary safeguard: even when the line anchor changed (e.g. layout
        // reflow shifted earlier paragraphs), suppress sub-half-line-height
        // target adjustments that would manifest as a 1-2px visual jump.
        if !snap && abs(newTarget - scrollTargetY) < stableHeight * 0.5 { return }
        scrollTargetY = newTarget
        if snap {
            stopSmoothScroll()
            scrollCurrentY = newTarget
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: newTarget))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        } else {
            startSmoothScroll()
        }
    }

    private func startSmoothScroll() {
        guard scrollTimer == nil else { return }
        // Stop wheel scroll so it doesn't fight the typewriter positioning
        stopWheelScroll()
        scrollCurrentY = enclosingScrollView?.contentView.bounds.origin.y ?? scrollTargetY
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.smoothScrollTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        scrollTimer = timer
    }

    private func smoothScrollTick() {
        guard let scrollView = enclosingScrollView else {
            stopSmoothScroll()
            return
        }
        scrollCurrentY += (scrollTargetY - scrollCurrentY) * 0.14
        if abs(scrollCurrentY - scrollTargetY) < 0.5 {
            scrollCurrentY = scrollTargetY
            stopSmoothScroll()
        }
        // Snap to integer pixels — sub-pixel scroll positions on layer-backed
        // clip views can jitter visually and read back rounded, fighting the easing.
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: scrollCurrentY.rounded()))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func stopSmoothScroll() {
        scrollTimer?.invalidate()
        scrollTimer = nil
    }

    // MARK: - Kinetic wheel scrolling

    override func scrollWheel(with event: NSEvent) {
        // Trackpad (precise deltas) already has native macOS momentum — pass through
        if event.hasPreciseScrollingDeltas {
            super.scrollWheel(with: event)
            return
        }
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return }
        // Stop typewriter scroll so it doesn't fight the wheel
        stopSmoothScroll()
        // Accumulate velocity; each wheel notch adds an impulse
        wheelVelocity -= delta * 6
        if wheelTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.wheelScrollTick()
            }
            RunLoop.main.add(timer, forMode: .common)
            wheelTimer = timer
        }
    }

    private func wheelScrollTick() {
        guard let scrollView = enclosingScrollView else { stopWheelScroll(); return }
        let maxY = max(0, (scrollView.documentView?.frame.height ?? 0) - scrollView.contentSize.height)
        let currentY = scrollView.contentView.bounds.origin.y
        let newY = min(max(0, currentY + wheelVelocity), maxY)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: newY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        wheelVelocity *= 0.88
        if abs(wheelVelocity) < 0.3 { stopWheelScroll() }
    }

    private func stopWheelScroll() {
        wheelTimer?.invalidate()
        wheelTimer = nil
        wheelVelocity = 0
    }

    deinit {
        stopSmoothScroll()
        stopWheelScroll()
    }

    @objc private func handleSelectionChange(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in self?.scrollToCurrentLine() }
    }

    // MARK: - Cursor

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        if flag {
            let font = typingAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 18)
            // ascender - descender spans from top of caps to bottom of descenders;
            // anchor to rect.maxY so the cursor tracks the text baseline regardless of lineHeightMultiple
            let cursorHeight = font.ascender - font.descender
            color.set()
            NSBezierPath.fill(NSRect(
                x: rect.minX,
                y: rect.maxY - cursorHeight,
                width: rect.width,
                height: cursorHeight
            ))
        } else {
            super.drawInsertionPoint(in: rect, color: color, turnedOn: false)
        }
    }

    // MARK: - Apply Theme/Prefs

    func applyTheme(_ theme: Theme) {
        textColor                  = theme.textColor
        insertionPointColor        = theme.cursorColor
        selectedTextAttributes     = [.backgroundColor: theme.selectionColor]
        // Ensure new typed characters use theme text color
        var attrs = typingAttributes
        attrs[.foregroundColor] = theme.textColor
        typingAttributes = attrs
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

        // Vim-inspired editor shortcuts via keybindingStore
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

    // MARK: - NSTextView change notification

    override func didChangeText() {
        super.didChangeText()
        onTextChange?(string)
        // No scroll trigger here: typing always moves the selection, so
        // handleSelectionChange already schedules scrollToCurrentLine.
        // Calling it again from here doubled the work per keystroke.
    }
}
