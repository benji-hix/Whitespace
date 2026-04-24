// Sources/Folio/Editor/ZenTextView.swift
import AppKit
import Carbon

final class ZenTextView: NSTextView {
    var onTextChange: ((String) -> Void)?
    var keybindingStore: KeybindingStore?

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
        isRichText                           = false
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
    }

    @objc private func scrollViewFrameChanged(_ note: Notification) {
        updateTypewriterInsets()
        scrollToCurrentLine()
    }

    private func updateTypewriterInsets() {
        guard let scrollView = enclosingScrollView else { return }
        let half = scrollView.contentSize.height / 2
        guard abs(textContainerInset.height - half) > 1 else { return }
        textContainerInset = NSSize(width: 0, height: half)
    }

    private func scrollToCurrentLine() {
        guard let layoutManager = layoutManager,
              let scrollView = enclosingScrollView else { return }
        let lineMidY: CGFloat
        if layoutManager.numberOfGlyphs == 0 {
            lineMidY = textContainerInset.height
        } else {
            let charIndex = selectedRange().location
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: max(0, min(charIndex, string.utf16.count > 0 ? string.utf16.count - 1 : 0)), length: 0),
                actualCharacterRange: nil
            )
            let gi = glyphRange.location == NSNotFound ? 0 : min(glyphRange.location, layoutManager.numberOfGlyphs - 1)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: gi, effectiveRange: nil)
            lineMidY = lineRect.midY + textContainerInset.height
        }
        let visibleHeight = scrollView.contentSize.height
        let targetY = max(0, lineMidY - visibleHeight / 2)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    @objc private func handleSelectionChange(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in self?.scrollToCurrentLine() }
    }

    // MARK: - Cursor

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        if flag {
            let fontHeight = (typingAttributes[.font] as? NSFont)?.pointSize ?? 18
            color.set()
            NSBezierPath.fill(NSRect(
                x: rect.minX,
                y: rect.midY - fontHeight / 2,
                width: rect.width,
                height: fontHeight
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
        let nsFont = NSFont(name: FolioFont.regular, size: size)
            ?? NSFont.systemFont(ofSize: size)
        let pStyle = NSMutableParagraphStyle()
        pStyle.lineHeightMultiple = lineHeightMultiple
        let attrs: [NSAttributedString.Key: Any] = [
            .font: nsFont,
            .paragraphStyle: pStyle,
        ]
        typingAttributes = attrs
        if let storage = textStorage, storage.length > 0 {
            storage.addAttributes(attrs, range: NSRange(location: 0, length: storage.length))
        }
    }

    // MARK: - keyDown

    override func keyDown(with event: NSEvent) {
        let flags  = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd    = flags.contains(.command)
        let shift  = flags.contains(.shift)
        let ctrl   = flags.contains(.control)

        // App-level shortcuts (keyCode constants: P=35, /=44, D=2, S=1, O=31, N=45, +=24, -=27)
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
        DispatchQueue.main.async { [weak self] in self?.scrollToCurrentLine() }
    }
}
