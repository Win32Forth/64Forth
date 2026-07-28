//
//  ConsoleTextView.swift
//  64Forth
//
//  Public domain.
//
//  AppKit-backed console (TZForth lineage): protected engine output prefix,
//  Return commits the full input line, caret cannot walk into protected text
//  while editing the input line. Selection/copy of history remains allowed.
//

import SwiftUI
import AppKit

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

        let textView = NSTextView()
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
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // During KEY wait, Return is a character (LF), not "submit line".
                // (Also handled by the keyDown monitor; keep this as a fallback.)
                if KernelBridge.shared.isEvaluating {
                    parent.onKeyCharacter(10)
                    return true
                }
                return parent.onReturnPressed()
            }

            let minLoc = min(max(0, parent.editableStartUTF16), (textView.string as NSString).length)
            let sel = textView.selectedRange()
            let caretInInputLine = sel.length == 0 && sel.location >= minLoc

            if caretInInputLine {
                if commandSelector == #selector(NSResponder.moveUp(_:)) {
                    parent.onHistoryUp()
                    return true
                }
                if commandSelector == #selector(NSResponder.moveDown(_:)) {
                    parent.onHistoryDown()
                    return true
                }
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
