//
//  ConsoleTextView.swift
//  64Forth
//
//  Public domain.
//
//  Console editor with protected engine-output prefix.
//  macOS: AppKit NSTextView; iOS: UIKit UITextView.
//

import SwiftUI

#if os(macOS)
import AppKit


/// Which surface this text view belongs to (split editor vs command pane).
enum ConsolePaneKind {
    /// Single full-window console — always a live REPL.
    case full
    /// Legacy upper facility / SZ-EDITOR grid (unused; safe no-op paths).
    case facility
    /// Legacy lower interactive command pane (Option A).
    case command
}

/// Scroll view for the console transcript. Wheel always scrolls natively;
/// SZ-EDITOR scrolling lives in the editor window, not here.
final class ConsoleNSScrollView: NSScrollView {
    var paneKind: ConsolePaneKind = .full

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
    }

    /// Report visible size in monospaced cells for an idle full console.
    /// When the facility is active, the editor window owns metrics.
    override func layout() {
        super.layout()
        reportVisibleCellMetrics()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        reportVisibleCellMetrics()
    }

    private func reportVisibleCellMetrics() {
        guard paneKind == .full else { return }
        guard !KernelBridge.shared.isFacilityTerminalActive else { return }
        guard let textView = documentView as? NSTextView else { return }
        let clip = contentView.bounds.size
        guard clip.width > 1, clip.height > 1 else { return }
        KernelBridge.shared.updateConsoleMetrics(scrollView: self, textView: textView)
    }
}

/// NSTextView for the console REPL (⌘-click VIEW, protected prefix, history).
final class ConsoleNSTextView: NSTextView {
    /// Console ⌘-click → VIEW word at UTF-16 index.
    var onCommandClickAtUTF16: ((Int) -> Void)?
    /// Split-pane role (legacy facility/command kept for ConsoleView compile).
    var paneKind: ConsolePaneKind = .full
    /// First UTF-16 index the user may edit (command pane prompt is before this).
    var editableStartUTF16: Int = 0
    /// Called when this view takes focus via click (so SwiftUI can update FocusState).
    var onPaneActivated: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func becomeFirstResponder() -> Bool {
        super.becomeFirstResponder()
    }

    // MARK: - Legacy caret stubs (ConsoleView still calls these; no overlay)

    func showFacilityLineCaret(atUTF16 utf16Index: Int) {
        _ = utf16Index
    }

    func hideFacilityLineCaret() {}

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // Legacy facility pane: do not route KEY into the grid from the console.
        if paneKind == .facility {
            return
        }
        if window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
        if paneKind == .command {
            KernelBridge.shared.setCommandPaneFocused(true)
        } else {
            KernelBridge.shared.setCommandPaneFocused(false)
        }
        let end = (string as NSString).length
        let start = min(max(0, editableStartUTF16), end)
        let sel = selectedRange()
        if sel.length == 0, sel.location < start {
            setSelectedRange(NSRange(location: end, length: 0))
        }
        super.keyDown(with: event)
    }

    /// Command pane: never insert into the protected prompt; clamp to input region.
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard paneKind == .command else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }
        let end = (string as NSString).length
        let start = min(max(0, editableStartUTF16), end)
        var r = replacementRange
        if r.location == NSNotFound {
            r = selectedRange()
        }
        if r.location < start {
            r = NSRange(location: end, length: 0)
            setSelectedRange(r)
        }
        super.insertText(insertString, replacementRange: r)
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        // Legacy facility pane: ignore grid mouse; editor window owns input.
        if paneKind == .facility {
            return
        }

        let pt = convert(event.locationInWindow, from: nil)
        let idx = characterIndexForInsertion(at: pt)
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = mods.contains(.command)

        if paneKind == .command {
            KernelBridge.shared.setCommandPaneFocused(true)
        } else {
            KernelBridge.shared.setCommandPaneFocused(false)
        }
        window?.makeFirstResponder(self)
        onPaneActivated?()

        // ⌘-click → VIEW word under click (works while editor KEY waits).
        if cmd {
            onCommandClickAtUTF16?(idx)
            return
        }

        super.mouseDown(with: event)
        // Collapsed caret in the protected prompt → move to end for typing.
        let sel = selectedRange()
        if sel.length == 0 {
            let end = (string as NSString).length
            let start = min(max(0, editableStartUTF16), end)
            if sel.location < start {
                setSelectedRange(NSRange(location: end, length: 0))
            }
        }
    }
}

/// AppKit console editor. SwiftUI `TextEditor` does not protect a prefix or
/// reliably scroll to the insertion point after programmatic appends.
struct ConsoleTextView: NSViewRepresentable {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    @Binding var pinCaretRequest: Int
    /// First UTF-16 index the user may edit (engine/protected output is before this).
    var editableStartUTF16: Int
    /// Split-pane role (default full-window console).
    var paneKind: ConsolePaneKind = .full
    var onReturnPressed: () -> Bool
    /// Up/Down on the input line → command history (not caret into protected text).
    var onHistoryUp: () -> Void = {}
    var onHistoryDown: () -> Void = {}
    /// Raw key bytes for kernel KEY while evaluate is waiting (Latin-1 / UTF-8 bytes).
    var onKeyCharacter: (Int32) -> Void = { _ in }
    /// Console ⌘-click at UTF-16 index → VIEW that token (Hyper).
    var onCommandClickUTF16: (Int) -> Void = { _ in }
    /// Native click/focus claimed this pane (update SwiftUI FocusState).
    var onPaneActivated: () -> Void = {}
    var onTextViewReady: (NSTextView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ConsoleNSScrollView()
        scrollView.paneKind = paneKind
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = ConsoleNSTextView()
        textView.paneKind = paneKind
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )
        scrollView.documentView = textView

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.string = text
        let end = (text as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
        let coord = context.coordinator
        textView.onCommandClickAtUTF16 = { [weak coord] idx in
            coord?.parent.onCommandClickUTF16(idx)
        }
        textView.onPaneActivated = { [weak coord] in
            coord?.parent.onPaneActivated()
        }

        context.coordinator.textView = textView
        onTextViewReady(textView)
        DispatchQueue.main.async {
            scrollView.layoutSubtreeIfNeeded()
            scrollView.layout()
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if let sv = scrollView as? ConsoleNSScrollView {
            sv.paneKind = paneKind
            // Idle full console only — editor window owns metrics while facility is active.
            if paneKind == .full, !KernelBridge.shared.isFacilityTerminalActive {
                let clip = sv.contentView.bounds.size
                if clip.width > 1, clip.height > 1 {
                    KernelBridge.shared.updateConsoleMetrics(scrollView: sv, textView: textView)
                }
            }
        }
        if let ctv = textView as? ConsoleNSTextView {
            let coord = context.coordinator
            ctv.paneKind = paneKind
            ctv.editableStartUTF16 = editableStartUTF16
            ctv.onCommandClickAtUTF16 = { [weak coord] idx in
                coord?.parent.onCommandClickUTF16(idx)
            }
            ctv.onPaneActivated = { [weak coord] in
                coord?.parent.onPaneActivated()
            }
            ctv.isEditable = paneKind != .facility
            ctv.isSelectable = true
            ctv.hideFacilityLineCaret()
        }

        var shouldScroll = false
        var pinOnScroll = false
        let needsPinCaret = context.coordinator.lastHandledPinCaretRequest != pinCaretRequest
        if needsPinCaret {
            context.coordinator.lastHandledPinCaretRequest = pinCaretRequest
        }

        // Legacy facility pane: host may still replace the string; do not fight scroll/caret.
        let legacyFacilityPane = paneKind == .facility

        if textView.string != text {
            let oldString = textView.string
            let selected = textView.selectedRange()
            let end = (text as NSString).length
            let oldEnd = (oldString as NSString).length
            let isPrefixAppend = !legacyFacilityPane && text.hasPrefix(oldString) && end > oldEnd

            context.coordinator.isProgrammaticUpdate = true
            if isPrefixAppend {
                let suffix = (text as NSString).substring(from: oldEnd)
                if let storage = textView.textStorage {
                    storage.beginEditing()
                    storage.replaceCharacters(in: NSRange(location: oldEnd, length: 0), with: suffix)
                    storage.endEditing()
                } else {
                    textView.string = text
                }
            } else {
                textView.string = text
            }
            context.coordinator.isProgrammaticUpdate = false

            if legacyFacilityPane {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                shouldScroll = false
            } else if needsPinCaret || isPrefixAppend || selected.location >= oldEnd {
                textView.setSelectedRange(NSRange(location: end, length: 0))
                shouldScroll = true
                pinOnScroll = true
            } else if selected.location <= end {
                textView.setSelectedRange(selected)
                shouldScroll = true
                pinOnScroll = false
            } else {
                textView.setSelectedRange(NSRange(location: end, length: 0))
                shouldScroll = true
                pinOnScroll = true
            }

            Self.resizeTextViewToFitContent(textView)
        } else if needsPinCaret, !legacyFacilityPane {
            let end = (text as NSString).length
            textView.setSelectedRange(NSRange(location: end, length: 0))
            shouldScroll = true
            pinOnScroll = true
            Self.resizeTextViewToFitContent(textView)
        }

        if shouldScroll, !legacyFacilityPane {
            if paneKind == .command {
                Self.scrollToEndNow(in: textView, pinCaret: pinOnScroll)
            }
            Self.scheduleScrollToInsertionPoint(in: textView, pinCaret: pinOnScroll)
        }

        // Command pane: keep insertion point out of the protected prompt.
        if paneKind == .command, KernelBridge.shared.isCommandPaneFocused {
            let end = (textView.string as NSString).length
            let start = min(max(0, editableStartUTF16), end)
            let sel = textView.selectedRange()
            if sel.length == 0, sel.location < start {
                textView.setSelectedRange(NSRange(location: end, length: 0))
            }
        }

        // Claim first responder only when this pane should own focus.
        // Never steal FR for the legacy facility pane.
        if isFocused, paneKind != .facility,
           let window = scrollView.window, window.firstResponder !== textView {
            if paneKind == .command, !KernelBridge.shared.isCommandPaneFocusedFlag {
                // Editor owns input — do not reclaim FR for command binding updates.
            } else {
                window.makeFirstResponder(textView)
                if paneKind == .command {
                    KernelBridge.shared.setCommandPaneFocused(true)
                }
            }
        }
    }

    static func scheduleScrollToInsertionPoint(in textView: NSTextView, pinCaret: Bool = true) {
        scrollToEndNow(in: textView, pinCaret: pinCaret)
        DispatchQueue.main.async {
            scrollToEndNow(in: textView, pinCaret: pinCaret)
            DispatchQueue.main.async {
                scrollToEndNow(in: textView, pinCaret: pinCaret)
            }
        }
    }

    /// Grow the text view and scroll to the caret (or document end).
    static func scrollToEndNow(in textView: NSTextView, pinCaret: Bool = true) {
        resizeTextViewToFitContent(textView)
        if pinCaret {
            let end = (textView.string as NSString).length
            if end > 0 {
                textView.setSelectedRange(NSRange(location: end, length: 0))
            }
        }
        scrollToShowInsertionPoint(in: textView)
    }

    /// Append UTF-16 text without replacing the whole string (preserves scroll).
    static func appendTextPreservingScroll(_ suffix: String, to textView: NSTextView) {
        guard !suffix.isEmpty else { return }
        let oldLen = (textView.string as NSString).length
        if let storage = textView.textStorage {
            storage.beginEditing()
            storage.replaceCharacters(in: NSRange(location: oldLen, length: 0), with: suffix)
            storage.endEditing()
        } else {
            textView.string = textView.string + suffix
        }
        let end = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
        scrollToEndNow(in: textView)
    }

    private static func resizeTextViewToFitContent(_ textView: NSTextView) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        layoutManager.ensureLayout(for: textContainer)

        let usedRect = layoutManager.usedRect(for: textContainer)
        var contentBottom = usedRect.maxY
        let extraRect = layoutManager.extraLineFragmentRect
        if extraRect.height > 0, layoutManager.extraLineFragmentTextContainer === textContainer {
            contentBottom = max(contentBottom, extraRect.maxY)
        }

        let inset = textView.textContainerInset
        let targetHeight = max(
            contentBottom + inset.height * 2,
            textView.enclosingScrollView?.contentSize.height ?? 0
        )
        var frame = textView.frame
        if abs(frame.size.height - targetHeight) > 0.5 {
            frame.size.height = targetHeight
            textView.frame = frame
        }
    }

    fileprivate static func scrollToShowInsertionPoint(in textView: NSTextView) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let scrollView = textView.enclosingScrollView else { return }

        layoutManager.ensureLayout(for: textContainer)

        let range = textView.selectedRange()
        let length = (textView.string as NSString).length
        let atEnd = range.location >= length

        if atEnd {
            scrollToDocumentBottom(
                textView: textView,
                scrollView: scrollView,
                layoutManager: layoutManager,
                textContainer: textContainer
            )
        } else if length > 0 {
            textView.scrollRangeToVisible(NSRange(location: range.location, length: max(range.length, 1)))
        }
    }

    private static func scrollToDocumentBottom(
        textView: NSTextView,
        scrollView: NSScrollView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) {
        layoutManager.ensureLayout(for: textContainer)

        var contentBottom = layoutManager.usedRect(for: textContainer).maxY
        let extraRect = layoutManager.extraLineFragmentRect
        if extraRect.height > 0, layoutManager.extraLineFragmentTextContainer === textContainer {
            contentBottom = max(contentBottom, extraRect.maxY)
        }

        let origin = textView.textContainerOrigin
        let inset = textView.textContainerInset
        let documentBottom = contentBottom + origin.y + inset.height
        let docHeight = max(documentBottom, textView.frame.maxY)

        let clipView = scrollView.contentView
        let clipHeight = clipView.bounds.height
        let targetY = max(0, docHeight - clipHeight)

        if abs(clipView.bounds.origin.y - targetY) > 0.5 {
            clipView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(clipView)
        }

        let len = (textView.string as NSString).length
        if len > 0 {
            textView.scrollRangeToVisible(NSRange(location: len, length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ConsoleTextView
        weak var textView: NSTextView?
        var isProgrammaticUpdate = false
        var lastHandledPinCaretRequest = 0

        init(parent: ConsoleTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate, let textView else { return }
            parent.text = textView.string
        }

        /// Refuse edits that would change the protected engine-output prefix.
        /// Selection/copy of history is still allowed.
        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            let len = (textView.string as NSString).length
            let minLoc = min(max(0, parent.editableStartUTF16), len)

            // Legacy facility pane: never mutate via AppKit (safe no-op host surface).
            if parent.paneKind == .facility {
                return false
            }

            // Command pane: always allow typing in the input region.
            if parent.paneKind == .command {
                if affectedCharRange.location < minLoc {
                    guard let replacement = replacementString, !replacement.isEmpty else {
                        return false
                    }
                    let end = (textView.string as NSString).length
                    textView.setSelectedRange(NSRange(location: end, length: 0))
                    if let storage = textView.textStorage {
                        storage.beginEditing()
                        storage.replaceCharacters(in: NSRange(location: end, length: 0), with: replacement)
                        storage.endEditing()
                    } else {
                        textView.insertText(replacement, replacementRange: NSRange(location: end, length: 0))
                    }
                    let newEnd = (textView.string as NSString).length
                    textView.setSelectedRange(NSRange(location: newEnd, length: 0))
                    parent.text = textView.string
                    return false
                }
                return true
            }

            // .full is always a live REPL (including while facility KEY waits).
            if affectedCharRange.location < minLoc {
                return false
            }
            return true
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Legacy facility pane: swallow AppKit editing commands.
            if parent.paneKind == .facility {
                return true
            }

            // .full / .command: normal REPL — Return, history, protected-prefix clamp.
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return parent.onReturnPressed()
            }
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onHistoryUp()
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onHistoryDown()
                return true
            }

            let minLoc = min(max(0, parent.editableStartUTF16), (textView.string as NSString).length)
            let sel = textView.selectedRange()
            let caretInInputLine = sel.length == 0 && sel.location >= minLoc

            if caretInInputLine {
                if commandSelector == #selector(NSResponder.moveLeft(_:))
                    || commandSelector == #selector(NSResponder.moveBackward(_:)) {
                    if sel.location <= minLoc {
                        return true
                    }
                    textView.setSelectedRange(NSRange(location: sel.location - 1, length: 0))
                    return true
                }
                if commandSelector == #selector(NSResponder.moveWordLeft(_:))
                    || commandSelector == #selector(NSResponder.moveWordBackward(_:))
                    || commandSelector == #selector(NSResponder.moveToBeginningOfLine(_:))
                    || commandSelector == #selector(NSResponder.moveToLeftEndOfLine(_:))
                    || commandSelector == #selector(NSResponder.moveToBeginningOfParagraph(_:))
                    || commandSelector == #selector(NSResponder.pageUp(_:))
                    || commandSelector == #selector(NSResponder.moveToBeginningOfDocument(_:)) {
                    textView.setSelectedRange(NSRange(location: minLoc, length: 0))
                    return true
                }
            }

            return false
        }
    }
}

#else
import UIKit

/// iOS console editor (UITextView). Core REPL input; facility/editor keys via pushKey.
struct ConsoleTextView: UIViewRepresentable {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    @Binding var pinCaretRequest: Int
    var editableStartUTF16: Int
    var onReturnPressed: () -> Bool
    var onHistoryUp: () -> Void = {}
    var onHistoryDown: () -> Void = {}
    var onKeyCharacter: (Int32) -> Void = { _ in }
    var onTextViewReady: (UITextView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.backgroundColor = .systemBackground
        tv.textColor = .label
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.smartDashesType = .no
        tv.smartQuotesType = .no
        tv.smartInsertDeleteType = .no
        tv.spellCheckingType = .no
        tv.keyboardDismissMode = .interactive
        tv.text = text
        tv.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        context.coordinator.textView = tv
        onTextViewReady(tv)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        let needsPin = context.coordinator.lastHandledPinCaretRequest != pinCaretRequest
        if needsPin {
            context.coordinator.lastHandledPinCaretRequest = pinCaretRequest
        }
        if tv.text != text {
            let selected = tv.selectedRange
            let oldEnd = (tv.text as NSString).length
            context.coordinator.isProgrammaticUpdate = true
            tv.text = text
            context.coordinator.isProgrammaticUpdate = false
            let end = (text as NSString).length
            if needsPin || selected.location >= oldEnd {
                tv.selectedRange = NSRange(location: end, length: 0)
            } else {
                let loc = min(selected.location, end)
                tv.selectedRange = NSRange(location: loc, length: 0)
            }
            scrollToEnd(tv)
        } else if needsPin {
            let end = (text as NSString).length
            tv.selectedRange = NSRange(location: end, length: 0)
            scrollToEnd(tv)
        }
        if isFocused, !tv.isFirstResponder {
            tv.becomeFirstResponder()
        }
    }

    private func scrollToEnd(_ tv: UITextView) {
        Self.scheduleScrollToInsertionPoint(in: tv)
    }

    static func scheduleScrollToInsertionPoint(in textView: UITextView) {
        DispatchQueue.main.async {
            let len = (textView.text as NSString).length
            if len > 0 {
                textView.scrollRangeToVisible(NSRange(location: len - 1, length: 1))
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ConsoleTextView
        weak var textView: UITextView?
        var isProgrammaticUpdate = false
        var lastHandledPinCaretRequest = 0

        init(parent: ConsoleTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isProgrammaticUpdate else { return }
            parent.text = textView.text ?? ""
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            let minLoc = min(max(0, parent.editableStartUTF16), (textView.text as NSString).length)
            if range.location < minLoc {
                return false
            }
            if KernelBridge.shared.isEvaluating {
                if text == "\n" {
                    parent.onKeyCharacter(10)
                    return false
                }
                if text.count == 1, let sc = text.unicodeScalars.first {
                    var v = Int32(sc.value)
                    if v == 127 { v = 8 }
                    parent.onKeyCharacter(v)
                }
                return false
            }
            if text == "\n" {
                return parent.onReturnPressed()
            }
            return true
        }
    }
}

extension UITextView {
    /// Legacy no-op stubs (macOS ConsoleView still references the AppKit APIs).
    func showFacilityLineCaret(atUTF16 utf16Index: Int) {
        _ = utf16Index
    }

    func hideFacilityLineCaret() {}
}
#endif
