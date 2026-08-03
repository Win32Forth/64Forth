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


/// NSTextView that reports mouse clicks in facility/SZ-EDITOR mode (Phase 4a).
final class ConsoleNSTextView: NSTextView {
    var onFacilityClick: ((Int) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if KernelBridge.shared.consumeEditorHotKeyIfNeeded(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if KernelBridge.shared.consumeEditorHotKeyIfNeeded(event) { return }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if KernelBridge.shared.isFacilityTerminalActive, KernelBridge.shared.isEvaluating {
            let pt = convert(event.locationInWindow, from: nil)
            // characterIndexForInsertion(at:) is reliable for monospaced facility paint.
            let idx = characterIndexForInsertion(at: pt)
            onFacilityClick?(idx)
            // Keep focus; do not change the document selection into the paint grid.
            window?.makeFirstResponder(self)
            return
        }
        super.mouseDown(with: event)
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
    var onReturnPressed: () -> Bool
    /// Up/Down on the input line → command history (not caret into protected text).
    var onHistoryUp: () -> Void = {}
    var onHistoryDown: () -> Void = {}
    /// Raw key bytes for kernel KEY while evaluate is waiting (Latin-1 / UTF-8 bytes).
    var onKeyCharacter: (Int32) -> Void = { _ in }
    var onTextViewReady: (NSTextView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = ConsoleNSTextView()
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
        textView.onFacilityClick = { idx in
            KernelBridge.shared.reportFacilityClick(utf16Index: idx)
        }
        let end = (text as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))

        context.coordinator.textView = textView
        onTextViewReady(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        var shouldScroll = false
        let needsPinCaret = context.coordinator.lastHandledPinCaretRequest != pinCaretRequest
        if needsPinCaret {
            context.coordinator.lastHandledPinCaretRequest = pinCaretRequest
        }

        if textView.string != text {
            let oldString = textView.string
            let selected = textView.selectedRange()
            context.coordinator.isProgrammaticUpdate = true
            textView.string = text
            context.coordinator.isProgrammaticUpdate = false

            let end = (text as NSString).length
            let oldEnd = (oldString as NSString).length

            if needsPinCaret {
                textView.setSelectedRange(NSRange(location: end, length: 0))
                shouldScroll = true
            } else if text.hasPrefix(oldString), end > oldEnd, selected.location >= oldEnd {
                textView.setSelectedRange(NSRange(location: end, length: 0))
                shouldScroll = true
            } else if selected.location <= end {
                textView.setSelectedRange(selected)
                shouldScroll = true
            } else {
                textView.setSelectedRange(NSRange(location: end, length: 0))
                shouldScroll = true
            }

            Self.resizeTextViewToFitContent(textView)
        } else if needsPinCaret {
            let end = (text as NSString).length
            textView.setSelectedRange(NSRange(location: end, length: 0))
            shouldScroll = true
            Self.resizeTextViewToFitContent(textView)
        }

        if shouldScroll {
            Self.scheduleScrollToInsertionPoint(in: textView)
        }

        if isFocused, let window = scrollView.window, window.firstResponder !== textView {
            window.makeFirstResponder(textView)
        }
    }

    static func scheduleScrollToInsertionPoint(in textView: NSTextView) {
        DispatchQueue.main.async {
            resizeTextViewToFitContent(textView)
            scrollToShowInsertionPoint(in: textView)
            DispatchQueue.main.async {
                resizeTextViewToFitContent(textView)
                scrollToShowInsertionPoint(in: textView)
            }
        }
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
            let minLoc = min(max(0, parent.editableStartUTF16), (textView.string as NSString).length)
            if affectedCharRange.location < minLoc {
                return false
            }
            // While the kernel is evaluating, KEY/KEY? input is captured by the
            // NSEvent keyDown monitor in KernelBridge (not here). Reject edits so
            // typed keys do not appear on the console input line.
            if KernelBridge.shared.isEvaluating {
                return false
            }
            return true
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // -----------------------------------------------------------------
            // While kernel_eval is active (KEY / EKEY / SZ-KEY waiting — e.g.
            // SZ-EDITOR), AppKit still delivers doCommandBy for arrows, Delete,
            // Home/End, PgUp/Dn, Return.  We must NOT move the NSTextView caret
            // or change the facility paint string; instead push classic F-PC
            // key codes into the Forth key queue (same numbers as sz-edit.fth):
            //
            //   1  Home / start of line     5  End / end of line
            //   2  Left arrow               6  Right arrow
            //   8  Backspace (delete left) 10  Enter / LF
            //  14  Down arrow              16  Up arrow
            //  23  Page Up                 24  Page Down
            //  28  Ctrl-Home / start file  29  Ctrl-End / end of file
            // 127  Forward Delete (delete under cursor)
            //
            // KernelBridge's keyDown monitor also maps hardware keys; this path
            // is the reliable fallback when the text view eats the event first.
            // -----------------------------------------------------------------
            if KernelBridge.shared.isEvaluating {
                // Prefer modifiers from the current key event (NSEvent.modifierFlags can
                // be empty during some doCommandBy deliveries).
                let rawMods = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
                let mods = rawMods.intersection([.command, .control, .option, .shift])
                let cmd = mods.contains(.command) && !mods.contains(.shift)

                // ⌘← / ⌘→ → in-buffer find prev/next (same file); host key 20/21
                // AppKit maps ⌘←/→ to line-start/end selectors — steal them here as fallback.
                if cmd {
                    if commandSelector == #selector(NSResponder.moveLeft(_:))
                        || commandSelector == #selector(NSResponder.moveBackward(_:))
                        || commandSelector == #selector(NSResponder.moveToBeginningOfLine(_:))
                        || commandSelector == #selector(NSResponder.moveToLeftEndOfLine(_:)) {
                        parent.onKeyCharacter(20) // SZ-FIND-PREV
                        return true
                    }
                    if commandSelector == #selector(NSResponder.moveRight(_:))
                        || commandSelector == #selector(NSResponder.moveForward(_:))
                        || commandSelector == #selector(NSResponder.moveToEndOfLine(_:))
                        || commandSelector == #selector(NSResponder.moveToRightEndOfLine(_:)) {
                        parent.onKeyCharacter(21) // SZ-FIND-NEXT
                        return true
                    }
                    // ⌘PgUp / ⌘PgDn → Hyper prev/next (keys 26/27)
                    if commandSelector == #selector(NSResponder.pageUp(_:)) {
                        parent.onKeyCharacter(26) // SZ-HYPER-PREV
                        return true
                    }
                    if commandSelector == #selector(NSResponder.pageDown(_:)) {
                        parent.onKeyCharacter(27) // SZ-HYPER-NEXT
                        return true
                    }
                }

                // Return / Enter → LF (10); SZ-EDITOR inserts CRLF
                if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                    parent.onKeyCharacter(10)
                    return true
                }
                // Delete (backspace) → BS (8); erase character left of cursor
                if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                    parent.onKeyCharacter(8)
                    return true
                }
                // Forward Delete (fn-Delete / Del) → 127; erase under cursor
                if commandSelector == #selector(NSResponder.deleteForward(_:)) {
                    parent.onKeyCharacter(127)
                    return true
                }
                // Left arrow / Ctrl-B style → 2 (SZ-LEFT)
                if commandSelector == #selector(NSResponder.moveLeft(_:))
                    || commandSelector == #selector(NSResponder.moveBackward(_:)) {
                    parent.onKeyCharacter(2)
                    return true
                }
                // Right arrow / Ctrl-F style → 6 (SZ-RIGHT)
                if commandSelector == #selector(NSResponder.moveRight(_:))
                    || commandSelector == #selector(NSResponder.moveForward(_:)) {
                    parent.onKeyCharacter(6)
                    return true
                }
                // Up arrow → 16 (SZ-UP)
                if commandSelector == #selector(NSResponder.moveUp(_:)) {
                    parent.onKeyCharacter(16)
                    return true
                }
                // Down arrow → 14 (SZ-DOWN)
                if commandSelector == #selector(NSResponder.moveDown(_:)) {
                    parent.onKeyCharacter(14)
                    return true
                }
                // Ctrl/Cmd-Home, Cmd-↑, scroll-to-doc-start → start of file (28)
                if commandSelector == #selector(NSResponder.moveToBeginningOfDocument(_:))
                    || commandSelector == #selector(NSResponder.scrollToBeginningOfDocument(_:)) {
                    parent.onKeyCharacter(28)
                    return true
                }
                // Ctrl/Cmd-End, Cmd-↓, scroll-to-doc-end → end of file (29)
                if commandSelector == #selector(NSResponder.moveToEndOfDocument(_:))
                    || commandSelector == #selector(NSResponder.scrollToEndOfDocument(_:)) {
                    parent.onKeyCharacter(29)
                    return true
                }
                // Home / beginning of line → 1 (SZ-HOME-LINE)
                if commandSelector == #selector(NSResponder.moveToBeginningOfLine(_:))
                    || commandSelector == #selector(NSResponder.moveToLeftEndOfLine(_:)) {
                    parent.onKeyCharacter(1)
                    return true
                }
                // End / end of line → 5 (SZ-END-LINE)
                if commandSelector == #selector(NSResponder.moveToEndOfLine(_:))
                    || commandSelector == #selector(NSResponder.moveToRightEndOfLine(_:)) {
                    parent.onKeyCharacter(5)
                    return true
                }
                // Page Up → 23 (SZ-PGUP)
                if commandSelector == #selector(NSResponder.pageUp(_:)) {
                    parent.onKeyCharacter(23)
                    return true
                }
                // Page Down → 24 (SZ-PGDN)
                if commandSelector == #selector(NSResponder.pageDown(_:)) {
                    parent.onKeyCharacter(24)
                    return true
                }
                // Any other command (select all, etc.): swallow so NSTextView
                // does not mutate the facility terminal paint.
                return true
            }

            // -----------------------------------------------------------------
            // Normal REPL (not waiting on KEY): Return submits the input line;
            // Up/Down recall history; Left stops at the protected prefix edge.
            // -----------------------------------------------------------------
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return parent.onReturnPressed()
            }

            let minLoc = min(max(0, parent.editableStartUTF16), (textView.string as NSString).length)
            let sel = textView.selectedRange()
            let caretInInputLine = sel.length == 0 && sel.location >= minLoc

            if caretInInputLine {
                // Up / Down on the editable input line → command history
                if commandSelector == #selector(NSResponder.moveUp(_:)) {
                    parent.onHistoryUp()
                    return true
                }
                if commandSelector == #selector(NSResponder.moveDown(_:)) {
                    parent.onHistoryDown()
                    return true
                }
                // Left: do not walk the caret into protected engine output
                if commandSelector == #selector(NSResponder.moveLeft(_:))
                    || commandSelector == #selector(NSResponder.moveBackward(_:)) {
                    if sel.location <= minLoc {
                        return true
                    }
                    textView.setSelectedRange(NSRange(location: sel.location - 1, length: 0))
                    return true
                }
                // Word-left / Home / Page Up / document start → clamp to input start
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
            context.coordinator.isProgrammaticUpdate = true
            tv.text = text
            context.coordinator.isProgrammaticUpdate = false
            let end = (text as NSString).length
            tv.selectedRange = NSRange(location: end, length: 0)
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
                // Return → LF for KEY loop
                if text == "\n" {
                    parent.onKeyCharacter(10)
                    return false
                }
                // Single char → push as Latin-1/Unicode scalar
                if text.count == 1, let sc = text.unicodeScalars.first {
                    var v = Int32(sc.value)
                    if v == 127 { v = 8 } // treat DEL as BS in facility
                    parent.onKeyCharacter(v)
                }
                return false
            }
            // Return submits the input line
            if text == "\n" {
                return parent.onReturnPressed()
            }
            return true
        }
    }
}
#endif
