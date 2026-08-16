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
    /// Single full-window console (facility inactive).
    case full
    /// Upper facility / SZ-EDITOR grid.
    case facility
    /// Lower interactive command pane (Option A).
    case command
}

/// Scroll view that feeds trackpad/mouse wheel into SZ-EDITOR (not the NSTextView string).
final class ConsoleNSScrollView: NSScrollView {
    /// When `.command`, wheel always scrolls this view; never the facility grid.
    var paneKind: ConsolePaneKind = .full

    override func scrollWheel(with event: NSEvent) {
        // Command pane: native scroll of command transcript.
        if paneKind == .command {
            super.scrollWheel(with: event)
            return
        }
        // Facility / full console while editor active: always map wheel to SZ-SCROLL-*.
        // Do not gate on isCommandPaneFocused — the mouse is over *this* pane, so a
        // stale command-focus flag must not disable editor scrolling after click-back.
        if paneKind != .command,
           KernelBridge.shared.isFacilityTerminalActive,
           KernelBridge.shared.isEvaluating {
            KernelBridge.shared.reportFacilityScroll(event)
            return
        }
        super.scrollWheel(with: event)
    }

    /// Report visible size in monospaced cells so SZ-EDITOR can match the window.
    /// Only the facility / full console drives metrics — the command pane is short and
    /// must never overwrite preferred facility cols/rows (that broke click→cell mapping).
    override func layout() {
        super.layout()
        reportVisibleCellMetrics()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        reportVisibleCellMetrics()
    }

    private func reportVisibleCellMetrics() {
        guard paneKind == .facility || paneKind == .full else { return }
        guard let textView = documentView as? NSTextView else { return }
        let clip = contentView.bounds.size
        guard clip.width > 1, clip.height > 1 else { return }
        KernelBridge.shared.updateConsoleMetrics(scrollView: self, textView: textView)
    }
}

/// NSTextView that reports mouse clicks in facility/SZ-EDITOR mode (Phase 4a).
final class ConsoleNSTextView: NSTextView {
    /// Console (non-facility) ⌘-click → VIEW word at UTF-16 index.
    var onCommandClickAtUTF16: ((Int) -> Void)?
    /// Split-pane role (facility vs command).
    var paneKind: ConsolePaneKind = .full
    /// First UTF-16 index the user may edit (command pane prompt is before this).
    var editableStartUTF16: Int = 0
    /// Called when this view takes focus via click (so SwiftUI can update FocusState).
    /// Must be cheap and idempotent — not every first-responder pulse.
    var onPaneActivated: (() -> Void)?

    /// Facility grid must accept clicks and KEY focus even when not AppKit-editable.
    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        // Do not set sticky command-focus from FR alone — ok> makeFirstResponder on
        // the command pane must not re-route KEY after the user clicked the editor.
        // Sticky is set only by mouseDown / onPaneActivated / explicit host APIs.
        return ok
    }

    /// Thin vertical I-beam for the Facility / SZ-EDITOR insert point (host paint).
    private lazy var facilityCaretView: NSView = {
        let v = NSView(frame: .zero)
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        v.isHidden = true
        return v
    }()

    /// True while SZ-EDITOR / facility owns the insert point (may be blink-off phase).
    private var facilityCaretActive = false
    /// Visible half of the blink cycle.
    private var facilityCaretBlinkOn = true
    /// Last UTF-16 index for the facility bar (reposition on layout if needed).
    private var facilityCaretUTF16: Int = 0
    /// ~0.53s matches typical AppKit insertion-point blink period.
    private var facilityCaretBlinkTimer: Timer?

    // MARK: - Insertion point (facility overlay vs command-pane AppKit caret)

    /// Facility pane: never draw AppKit I-beam (custom overlay only). Command pane: normal caret.
    override var shouldDrawInsertionPoint: Bool {
        if paneKind == .command {
            return isEditable && (window?.firstResponder === self)
        }
        if paneKind == .facility, KernelBridge.shared.isFacilityTerminalActive {
            return false
        }
        // Full console (no split): suppress system caret while facility grid is active.
        if paneKind == .full, KernelBridge.shared.isFacilityTerminalActive {
            return false
        }
        return super.shouldDrawInsertionPoint
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        if paneKind != .command, KernelBridge.shared.isFacilityTerminalActive { return }
        super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
    }

    override var insertionPointColor: NSColor? {
        get {
            if paneKind != .command, KernelBridge.shared.isFacilityTerminalActive { return .clear }
            return super.insertionPointColor
        }
        set { super.insertionPointColor = newValue }
    }

    /// Avoid a zero-length selection paint flashing at the top-left of the grid.
    /// Command pane keeps normal selection so typing and caret placement work.
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        if paneKind != .command, KernelBridge.shared.isFacilityTerminalActive {
            // Keep a collapsed selection for AppKit, but force location 0 and never
            // allow a non-empty range that would look like text selection on the grid.
            let zero = [NSValue(range: NSRange(location: 0, length: 0))]
            super.setSelectedRanges(zero, affinity: affinity, stillSelecting: false)
            return
        }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
    }

    // MARK: - Facility I-beam caret (+ blink)

    /// Place a 2pt vertical bar at the left edge of the character cell at `utf16Index`.
    /// Repositions and restarts blink (visible) so typing/motion feels like a normal editor.
    func showFacilityLineCaret(atUTF16 utf16Index: Int) {
        facilityCaretUTF16 = utf16Index
        facilityCaretActive = true
        facilityCaretBlinkOn = true
        if facilityCaretView.superview !== self {
            addSubview(facilityCaretView)
        }
        layoutFacilityCaretBar()
        startFacilityCaretBlinkTimer()
    }

    func hideFacilityLineCaret() {
        facilityCaretActive = false
        facilityCaretBlinkOn = true
        stopFacilityCaretBlinkTimer()
        facilityCaretView.isHidden = true
    }

    private func layoutFacilityCaretBar() {
        guard facilityCaretActive else {
            facilityCaretView.isHidden = true
            return
        }
        guard let layoutManager, let textContainer else {
            facilityCaretView.isHidden = true
            return
        }
        let length = (string as NSString).length
        let utf16Index = facilityCaretUTF16
        guard length > 0, utf16Index >= 0, utf16Index < length else {
            facilityCaretView.isHidden = true
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let charRange = NSRange(location: utf16Index, length: 1)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else {
            facilityCaretView.isHidden = true
            return
        }
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let origin = textContainerOrigin
        rect.origin.x += origin.x
        rect.origin.y += origin.y

        // Insert-point bar: left edge of the cell (before the character).
        let barWidth: CGFloat = 2
        let x = max(0, rect.minX - barWidth * 0.5)
        facilityCaretView.frame = NSRect(x: x, y: rect.minY, width: barWidth, height: max(rect.height, 1))
        facilityCaretView.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        facilityCaretView.isHidden = !facilityCaretBlinkOn
    }

    private func startFacilityCaretBlinkTimer() {
        if facilityCaretBlinkTimer != nil { return }
        // Common AppKit period; main run-loop common modes so it ticks during KEY pump.
        let t = Timer(timeInterval: 0.53, repeats: true) { [weak self] _ in
            self?.facilityCaretBlinkTick()
        }
        RunLoop.main.add(t, forMode: .common)
        facilityCaretBlinkTimer = t
    }

    private func stopFacilityCaretBlinkTimer() {
        facilityCaretBlinkTimer?.invalidate()
        facilityCaretBlinkTimer = nil
    }

    private func facilityCaretBlinkTick() {
        guard facilityCaretActive,
              KernelBridge.shared.isFacilityTerminalActive,
              !KernelBridge.shared.isCommandPaneFocused else {
            hideFacilityLineCaret()
            return
        }
        facilityCaretBlinkOn.toggle()
        facilityCaretView.isHidden = !facilityCaretBlinkOn
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Command pane: normal text shortcuts (copy/paste into command line).
        if paneKind == .command {
            return super.performKeyEquivalent(with: event)
        }
        if KernelBridge.shared.consumeEditorHotKeyIfNeeded(event) { return true }
        // ⌘X/C/V while SZ-EDITOR is open (menu may not claim them during KEY wait).
        if KernelBridge.shared.isEvaluating, KernelBridge.shared.isFacilityTerminalActive {
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods.contains(.command), !mods.contains(.shift) {
                let ch = (event.charactersIgnoringModifiers ?? "").lowercased()
                if ch == "x" || ch == "c" || ch == "v" {
                    if KernelBridge.shared.pushEditorClipboardKey(ch) { return true }
                }
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if paneKind == .command {
            // Ensure we are first responder and caret is past the prompt before insert.
            if window?.firstResponder !== self {
                window?.makeFirstResponder(self)
            }
            KernelBridge.shared.setCommandPaneFocused(true)
            let end = (string as NSString).length
            let start = min(max(0, editableStartUTF16), end)
            let sel = selectedRange()
            if sel.length == 0, sel.location < start {
                setSelectedRange(NSRange(location: end, length: 0))
            }
            super.keyDown(with: event)
            return
        }
        // Facility / editor: own KEY routing here if the local monitor left the event
        // (e.g. stale command-focus flag). Never fall through to non-editable super
        // which would drop printables.
        if KernelBridge.shared.isEvaluating, KernelBridge.shared.isFacilityTerminalActive {
            KernelBridge.shared.setCommandPaneFocused(false)
            if KernelBridge.shared.consumeEditorHotKeyIfNeeded(event) { return }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods.contains(.command), !mods.contains(.shift) {
                let ch = (event.charactersIgnoringModifiers ?? "").lowercased()
                if ch == "x" || ch == "c" || ch == "v" {
                    if KernelBridge.shared.pushEditorClipboardKey(ch) { return }
                }
            }
            if KernelBridge.shared.deliverFacilityKeyDown(event) { return }
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
        if paneKind == .command {
            super.scrollWheel(with: event)
            return
        }
        // Facility: always scroll the editor when the pointer is over this view.
        if paneKind != .command,
           KernelBridge.shared.isFacilityTerminalActive,
           KernelBridge.shared.isEvaluating {
            KernelBridge.shared.reportFacilityScroll(event)
            return
        }
        super.scrollWheel(with: event)
    }

    // MARK: - Facility context menu (Cut / Copy / Paste → SZ-EDITOR keys)

    /// Custom Edit menu while SZ-EDITOR owns the facility terminal (not NSTextView’s system menu).
    private lazy var facilityContextMenu: NSMenu = {
        let menu = NSMenu(title: "Edit")
        menu.autoenablesItems = false
        let cut = NSMenuItem(title: "Cut", action: #selector(facilityCut(_:)), keyEquivalent: "x")
        cut.keyEquivalentModifierMask = .command
        cut.target = self
        let copy = NSMenuItem(title: "Copy", action: #selector(facilityCopy(_:)), keyEquivalent: "c")
        copy.keyEquivalentModifierMask = .command
        copy.target = self
        let paste = NSMenuItem(title: "Paste", action: #selector(facilityPaste(_:)), keyEquivalent: "v")
        paste.keyEquivalentModifierMask = .command
        paste.target = self
        menu.addItem(cut)
        menu.addItem(copy)
        menu.addItem(paste)
        return menu
    }()

    private var facilityEditorMenuActive: Bool {
        paneKind != .command
            && KernelBridge.shared.isFacilityTerminalActive
            && KernelBridge.shared.isEvaluating
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        if facilityEditorMenuActive {
            // Do not probe NSPasteboard here — general.string on the main thread
            // can priority-invert (user-interactive wait on pasteboard server).
            // Cut/Copy/Paste stay enabled; Forth no-ops on empty selection/clip.
            return facilityContextMenu
        }
        return super.menu(for: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        if facilityEditorMenuActive {
            // Keep focus; do not let NSTextView select into the facility paint grid.
            window?.makeFirstResponder(self)
            NSMenu.popUpContextMenu(facilityContextMenu, with: event, for: self)
            return
        }
        super.rightMouseDown(with: event)
    }

    @objc private func facilityCut(_ sender: Any?) {
        _ = KernelBridge.shared.pushEditorClipboardKey("x")
    }

    @objc private func facilityCopy(_ sender: Any?) {
        _ = KernelBridge.shared.pushEditorClipboardKey("c")
    }

    @objc private func facilityPaste(_ sender: Any?) {
        _ = KernelBridge.shared.pushEditorClipboardKey("v")
    }

    /// Facility drag-select tracking (plain / shift; not ⌘ VIEW or double-click word).
    private var facilityDragTracking = false
    private var facilityDragShift = false
    private var facilityLastDragCol = -1
    private var facilityLastDragRow = -1
    /// Latest drag pointer (view coords) for edge auto-scroll.
    private var facilityDragPoint = NSPoint.zero
    /// Timer: pan view while pointer sits in a text-band edge zone during drag.
    private var facilityEdgeScrollTimer: Timer?

    private func stopFacilityEdgeScroll() {
        facilityEdgeScrollTimer?.invalidate()
        facilityEdgeScrollTimer = nil
    }

    /// Vertical/horizontal edge direction from a text-band cell (-1 / 0 / +1).
    private func facilityEdgeDirections(col: Int, row: Int) -> (v: Int, h: Int) {
        let band = KernelBridge.shared.facilityTextBand
        let v: Int
        if row <= band.textTop { v = -1 }
        else if row >= band.textBot { v = 1 }
        else { v = 0 }
        let h: Int
        if col <= band.textLeft { h = -1 }
        else if col >= band.textRight { h = 1 }
        else { h = 0 }
        return (v, h)
    }

    private func startFacilityEdgeScrollIfNeeded(v: Int, h: Int) {
        if v == 0 && h == 0 {
            stopFacilityEdgeScroll()
            return
        }
        if facilityEdgeScrollTimer != nil { return }
        // ~10 Hz: pan + re-extend selection while held at the edge.
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.facilityEdgeScrollTick()
        }
        RunLoop.main.add(t, forMode: .common)
        facilityEdgeScrollTimer = t
        // Immediate first step so the user does not wait a full interval.
        facilityEdgeScrollTick()
    }

    private func facilityEdgeScrollTick() {
        guard facilityDragTracking,
              KernelBridge.shared.isFacilityTerminalActive,
              KernelBridge.shared.isEvaluating else {
            stopFacilityEdgeScroll()
            return
        }
        let idx = characterIndexForInsertion(at: facilityDragPoint)
        guard let cell = KernelBridge.shared.facilityTextCellClamped(fromUTF16: idx) else {
            stopFacilityEdgeScroll()
            return
        }
        let (v, h) = facilityEdgeDirections(col: cell.col, row: cell.row)
        if v == 0 && h == 0 {
            stopFacilityEdgeScroll()
            return
        }
        let band = KernelBridge.shared.facilityTextBand
        // Free end stays on the edge cell of the text band after each pan.
        let edgeCol = h < 0 ? band.textLeft : (h > 0 ? band.textRight : cell.col)
        let edgeRow = v < 0 ? band.textTop : (v > 0 ? band.textBot : cell.row)
        KernelBridge.shared.reportFacilityEdgeScroll(vertical: v, horizontal: h)
        facilityLastDragCol = edgeCol
        facilityLastDragRow = edgeRow
        KernelBridge.shared.reportFacilityMouse(
            col: edgeCol,
            row: edgeRow,
            phase: .drag,
            shift: facilityDragShift
        )
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let idx = characterIndexForInsertion(at: pt)
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = mods.contains(.command)
        let shift = mods.contains(.shift) && !cmd
        // Triple is clickCount >= 3; double is exactly 2 (do not treat triple as double).
        let tripleClick = event.clickCount >= 3 && !cmd
        let doubleClick = event.clickCount == 2 && !cmd

        // Command pane: normal text selection + editing (history is selectable for copy).
        if paneKind == .command {
            KernelBridge.shared.setCommandPaneFocused(true)
            window?.makeFirstResponder(self)
            // Always notify so SwiftUI FocusState leaves the facility pane.
            onPaneActivated?()
            // Native click/drag selection (including protected transcript for Copy).
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
            return
        }

        if paneKind == .facility || paneKind == .full,
           KernelBridge.shared.isFacilityTerminalActive, KernelBridge.shared.isEvaluating {
            // Sticky flag is the KEY routing authority — clear it first (and keep
            // clearing after FocusState / late ok> callbacks on the next turn).
            KernelBridge.shared.setCommandPaneFocused(false)
            KernelBridge.shared.resetFacilityMouseQueue()
            window?.makeFirstResponder(self)
            onPaneActivated?()
            window?.makeFirstResponder(self)
            KernelBridge.shared.setCommandPaneFocused(false)
            // Beat a racing onCommandLineDone that might re-assert command sticky.
            DispatchQueue.main.async {
                KernelBridge.shared.setCommandPaneFocused(false)
            }
            stopFacilityEdgeScroll()

            // Prefer exact cell; fall back to full-grid clamp (incl. find/status chrome).
            let cell = KernelBridge.shared.facilityCell(fromUTF16: idx)
                ?? KernelBridge.shared.facilityGridCellClamped(fromUTF16: idx)

            // Immediate host I-beam so click feedback is not delayed until KEY/REDRAW.
            if let cell {
                let cols = max(1, KernelBridge.shared.facilityCols)
                let prefix = (KernelBridge.shared.facilityPaintPrefix as NSString).length
                let loc = prefix + cell.row * (cols + 1) + cell.col
                showFacilityLineCaret(atUTF16: loc)
            }

            if cmd {
                facilityDragTracking = false
                facilityDragShift = false
                if let cell {
                    KernelBridge.shared.reportFacilityMouse(
                        col: cell.col, row: cell.row, phase: .down, command: true
                    )
                } else {
                    KernelBridge.shared.reportFacilityMouse(
                        utf16Index: idx, phase: .down, command: true
                    )
                }
                return
            }
            if tripleClick {
                facilityDragTracking = false
                facilityDragShift = false
                if let cell {
                    KernelBridge.shared.reportFacilityMouse(
                        col: cell.col, row: cell.row, phase: .down, tripleClick: true
                    )
                }
                return
            }
            if doubleClick {
                facilityDragTracking = false
                facilityDragShift = false
                if let cell {
                    KernelBridge.shared.reportFacilityMouse(
                        col: cell.col, row: cell.row, phase: .down, doubleClick: true
                    )
                }
                return
            }
            // Plain or ⇧ press: track for drag / shift-extend.
            facilityDragTracking = true
            facilityDragShift = shift
            facilityDragPoint = pt
            if let cell {
                facilityLastDragCol = cell.col
                facilityLastDragRow = cell.row
                KernelBridge.shared.reportFacilityMouse(
                    col: cell.col, row: cell.row, phase: .down, shift: shift
                )
            } else {
                facilityDragTracking = false
                facilityDragShift = false
            }
            return
        }

        // Console REPL: ⌘-click → VIEW word under click (same as ⌘E on that token).
        if cmd, !KernelBridge.shared.isEvaluating {
            onCommandClickAtUTF16?(idx)
            window?.makeFirstResponder(self)
            return
        }

        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if facilityDragTracking,
           KernelBridge.shared.isFacilityTerminalActive,
           KernelBridge.shared.isEvaluating {
            let pt = convert(event.locationInWindow, from: nil)
            facilityDragPoint = pt
            let idx = characterIndexForInsertion(at: pt)
            // Prefer clamped text-band cell so drags past the frame still track.
            guard let cell = KernelBridge.shared.facilityTextCellClamped(fromUTF16: idx)
                    ?? KernelBridge.shared.facilityCell(fromUTF16: idx) else {
                return
            }
            let (v, h) = facilityEdgeDirections(col: cell.col, row: cell.row)
            startFacilityEdgeScrollIfNeeded(v: v, h: h)
            // Throttle: only when the cell under the pointer changes (or edge timer).
            if cell.col == facilityLastDragCol, cell.row == facilityLastDragRow {
                return
            }
            facilityLastDragCol = cell.col
            facilityLastDragRow = cell.row
            KernelBridge.shared.reportFacilityMouse(
                col: cell.col,
                row: cell.row,
                phase: .drag,
                shift: facilityDragShift
            )
            return
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if facilityDragTracking {
            facilityDragTracking = false
            stopFacilityEdgeScroll()
            let shift = facilityDragShift
            facilityDragShift = false
            if KernelBridge.shared.isFacilityTerminalActive,
               KernelBridge.shared.isEvaluating {
                let pt = convert(event.locationInWindow, from: nil)
                let idx = characterIndexForInsertion(at: pt)
                if let cell = KernelBridge.shared.facilityTextCellClamped(fromUTF16: idx)
                    ?? KernelBridge.shared.facilityCell(fromUTF16: idx) {
                    KernelBridge.shared.reportFacilityMouse(
                        col: cell.col,
                        row: cell.row,
                        phase: .up,
                        shift: shift
                    )
                } else if facilityLastDragCol >= 0 {
                    // Release outside grid: finalize at last in-grid cell.
                    KernelBridge.shared.reportFacilityMouse(
                        col: facilityLastDragCol,
                        row: facilityLastDragRow,
                        phase: .up,
                        shift: shift
                    )
                }
                facilityLastDragCol = -1
                facilityLastDragRow = -1
                return
            }
            facilityLastDragCol = -1
            facilityLastDragRow = -1
        }
        super.mouseUp(with: event)
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
        // Initial cell metrics before first layout pass.
        DispatchQueue.main.async {
            scrollView.layoutSubtreeIfNeeded()
            if let sv = scrollView as? ConsoleNSScrollView {
                // layout() reports metrics; force one more pass after window attach
                sv.layout()
            }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if let sv = scrollView as? ConsoleNSScrollView {
            sv.paneKind = paneKind
            // Only the facility (upper) pane drives SZ-EDITOR cell metrics.
            if paneKind == .facility || paneKind == .full {
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
            // Keep facility selectable + editable for reliable first-responder / click
            // focus; shouldChangeTextIn rejects all grid mutations while facility is on.
            ctv.isEditable = true
            ctv.isSelectable = true
            // Facility I-beam is drawn by ConsoleView; never on the command pane.
            if paneKind != .facility {
                ctv.hideFacilityLineCaret()
            } else if !KernelBridge.shared.isFacilityTerminalActive
                        || KernelBridge.shared.isCommandPaneFocused {
                ctv.hideFacilityLineCaret()
            }
        }

        var shouldScroll = false
        let needsPinCaret = context.coordinator.lastHandledPinCaretRequest != pinCaretRequest
        if needsPinCaret {
            context.coordinator.lastHandledPinCaretRequest = pinCaretRequest
        }

        // Facility *grid* paint: only the upper facility pane freezes selection/scroll.
        let facilityPaint = paneKind == .facility
            && KernelBridge.shared.isFacilityTerminalActive

        if textView.string != text {
            let oldString = textView.string
            let selected = textView.selectedRange()
            context.coordinator.isProgrammaticUpdate = true
            textView.string = text
            context.coordinator.isProgrammaticUpdate = false

            let end = (text as NSString).length
            let oldEnd = (oldString as NSString).length

            if facilityPaint {
                // Facility owns the grid; keep selection at 0 and do not auto-scroll
                // the NSScrollView (wheel scroll is handled as SZ-SCROLL-* keys).
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                shouldScroll = false
            } else if needsPinCaret {
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
        } else if needsPinCaret, !facilityPaint {
            let end = (text as NSString).length
            textView.setSelectedRange(NSRange(location: end, length: 0))
            shouldScroll = true
            Self.resizeTextViewToFitContent(textView)
        }

        if shouldScroll, !facilityPaint {
            Self.scheduleScrollToInsertionPoint(in: textView)
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
        // Sticky flag is authoritative: never let commandText / ok> updates steal
        // FR after the user clicked the facility (sticky false).
        if isFocused, let window = scrollView.window, window.firstResponder !== textView {
            if paneKind == .command, !KernelBridge.shared.isCommandPaneFocusedFlag {
                // Editor owns input — do not reclaim FR for command binding updates.
            } else if paneKind == .facility, KernelBridge.shared.isCommandPaneFocusedFlag {
                // Command pane owns input — do not steal FR on grid paint.
            } else {
                window.makeFirstResponder(textView)
                if paneKind == .command {
                    KernelBridge.shared.setCommandPaneFocused(true)
                } else if paneKind == .facility {
                    KernelBridge.shared.setCommandPaneFocused(false)
                }
            }
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
            let len = (textView.string as NSString).length
            let minLoc = min(max(0, parent.editableStartUTF16), len)

            // Command pane: always allow typing in the input region, even while the
            // editor KEY loop is active. If the caret is stuck in the prompt, move
            // it to the end and insert there so characters are not silently dropped.
            if parent.paneKind == .command {
                if affectedCharRange.location < minLoc {
                    guard let replacement = replacementString, !replacement.isEmpty else {
                        return false
                    }
                    let end = (textView.string as NSString).length
                    textView.setSelectedRange(NSRange(location: end, length: 0))
                    // Perform the insert ourselves at the end of the field.
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

            // Facility grid string is host-painted only — never mutate via AppKit.
            if parent.paneKind == .facility || parent.paneKind == .full,
               KernelBridge.shared.isFacilityTerminalActive {
                return false
            }

            if affectedCharRange.location < minLoc {
                return false
            }
            // While the kernel is evaluating, KEY/KEY? input is captured by the
            // NSEvent keyDown monitor in KernelBridge (not here). Reject edits so
            // typed keys do not appear on the facility/console line.
            if KernelBridge.shared.isEvaluating,
               !KernelBridge.shared.isCommandPaneFocused {
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

            // Command pane is identified by paneKind (not only the focus flag),
            // so Return keeps working even if the flag briefly races.
            if parent.paneKind == .command {
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
                return false // normal character editing
            }

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

                // Return → LF (10); ⇧Return → 132 (find previous while Cmd-F field open)
                if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                    let shiftOnly = mods.contains(.shift)
                        && !mods.contains(.command)
                        && !mods.contains(.option)
                    parent.onKeyCharacter(shiftOnly ? 132 : 10)
                    return true
                }
                // Tab → ASCII 9; SZ-EDITOR expands to spaces (must not be swallowed)
                if commandSelector == #selector(NSResponder.insertTab(_:)) {
                    parent.onKeyCharacter(9)
                    return true
                }
                // Shift-Tab: ignore for now (no outdent yet)
                if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
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
            // Facility grid still painted: never commit a REPL line (Return would
            // re-enter evaluate while SZ-EDITOR may still be active, or race).
            if KernelBridge.shared.isFacilityTerminalActive {
                return true
            }
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
import ObjectiveC

private let facilityCaretViewTag = 0xFAC1_CA2E
private var facilityCaretBlinkTimerKey: UInt8 = 0
private var facilityCaretBlinkOnKey: UInt8 = 0
private var facilityCaretUTF16Key: UInt8 = 0

extension UITextView {
    private var facilityCaretBlinkTimer: Timer? {
        get { objc_getAssociatedObject(self, &facilityCaretBlinkTimerKey) as? Timer }
        set { objc_setAssociatedObject(self, &facilityCaretBlinkTimerKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var facilityCaretBlinkOn: Bool {
        get { (objc_getAssociatedObject(self, &facilityCaretBlinkOnKey) as? Bool) ?? true }
        set { objc_setAssociatedObject(self, &facilityCaretBlinkOnKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var facilityCaretUTF16: Int {
        get { (objc_getAssociatedObject(self, &facilityCaretUTF16Key) as? Int) ?? 0 }
        set { objc_setAssociatedObject(self, &facilityCaretUTF16Key, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// Thin vertical I-beam for the Facility / SZ-EDITOR insert point (+ blink).
    func showFacilityLineCaret(atUTF16 utf16Index: Int) {
        facilityCaretUTF16 = utf16Index
        facilityCaretBlinkOn = true
        // Hide UITextView insertion point while we draw our own.
        tintColor = .clear
        layoutFacilityCaretBar()
        if facilityCaretBlinkTimer == nil {
            let t = Timer(timeInterval: 0.53, repeats: true) { [weak self] _ in
                self?.facilityCaretBlinkTick()
            }
            RunLoop.main.add(t, forMode: .common)
            facilityCaretBlinkTimer = t
        }
    }

    func hideFacilityLineCaret() {
        facilityCaretBlinkTimer?.invalidate()
        facilityCaretBlinkTimer = nil
        facilityCaretBlinkOn = true
        viewWithTag(facilityCaretViewTag)?.isHidden = true
        // Restore default caret tint for normal REPL.
        tintColor = .systemBlue
    }

    private func facilityCaretBlinkTick() {
        guard KernelBridge.shared.isFacilityTerminalActive else {
            hideFacilityLineCaret()
            return
        }
        facilityCaretBlinkOn.toggle()
        viewWithTag(facilityCaretViewTag)?.isHidden = !facilityCaretBlinkOn
    }

    private func layoutFacilityCaretBar() {
        let caret: UIView
        if let existing = viewWithTag(facilityCaretViewTag) {
            caret = existing
        } else {
            let v = UIView(frame: .zero)
            v.tag = facilityCaretViewTag
            v.backgroundColor = .systemBlue
            v.isUserInteractionEnabled = false
            v.isHidden = true
            addSubview(v)
            caret = v
        }

        let utf16Index = facilityCaretUTF16
        let ns = (text ?? "") as NSString
        let length = ns.length
        guard length > 0, utf16Index >= 0, utf16Index < length,
              let start = position(from: beginningOfDocument, offset: utf16Index),
              let end = position(from: start, offset: 1),
              let textRange = textRange(from: start, to: end) else {
            caret.isHidden = true
            return
        }

        let rect = firstRect(for: textRange)
        guard rect.width > 0 || rect.height > 0 else {
            caret.isHidden = true
            return
        }
        let barWidth: CGFloat = 2
        let x = max(0, rect.minX - barWidth * 0.5)
        caret.frame = CGRect(x: x, y: rect.minY, width: barWidth, height: max(rect.height, 1))
        caret.backgroundColor = .systemBlue
        caret.isHidden = !facilityCaretBlinkOn
    }
}

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
        if !KernelBridge.shared.isFacilityTerminalActive {
            tv.hideFacilityLineCaret()
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
