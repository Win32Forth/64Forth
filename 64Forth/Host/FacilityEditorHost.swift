//
//  FacilityEditorHost.swift
//  64Forth — dedicated SZ-EDITOR / Facility window (not the console, not App Output).
//
//  Pattern mirrors AppOutputHost (imperative NSWindow, deferred close, key routing),
//  but paints FacilityTerminal Unicode cells + attrs for SZ-EDITOR.
//  AppOutputHost remains GRAPHICS / Emitter only — do not merge the two.
//
//  Public domain.
//

import AppKit
import Foundation

/// AppKit host for the in-app Facility editor (SZ-EDITOR).
final class FacilityEditorHost: NSObject, NSWindowDelegate {
    static let shared = FacilityEditorHost()

    private var window: NSWindow?
    private var gridView: FacilityGridView?
    private var opened = false
    private var titleText = "SZ-EDITOR"

    /// Monospaced cell metrics (updated from the live view / font).
    private(set) var cellW: CGFloat = 9
    private(set) var cellH: CGFloat = 16

    /// True when the editor window is open and is the key window.
    var isKeyWindowActive: Bool {
        opened && (window?.isKeyWindow == true)
    }

    var isOpen: Bool { opened }

    private override init() {
        super.init()
    }

    /// Open (or raise) the editor window and redraw from FacilityTerminal.
    /// Called on TERMINAL-REFRESH while facility is active (separate-editor mode).
    func presentFromRefresh() {
        guard KernelBridge.useSeparateFacilityEditor else { return }
        if AgentChannel.isRequested { return }
        guard FacilityTerminal.shared.isActive else { return }

        let work = { [weak self] in
            guard let self else { return }
            let firstOpen = (self.window == nil)
            if firstOpen {
                self.buildWindow()
            }
            self.opened = true
            self.applyTitle()
            self.reportMetricsToKernel()
            self.gridView?.needsDisplay = true
            if firstOpen {
                // Raise + take KEY only on first open so later TERMINAL-REFRESH
                // paints do not steal focus from the live Console REPL.
                self.window?.makeKeyAndOrderFront(nil)
                self.window?.makeFirstResponder(self.gridView)
                KernelBridge.shared.setCommandPaneFocused(false)
                NSApp.activate(ignoringOtherApps: true)
            } else {
                self.window?.orderFront(nil)
                self.gridView?.needsDisplay = true
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }

    /// Redraw only (window already open).
    func redraw() {
        let work = { [weak self] in
            guard let self, self.opened else { return }
            self.applyTitle()
            self.gridView?.needsDisplay = true
            self.window?.displayIfNeeded()
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    /// FACILITY-OFF / editor quit — defer teardown like AppOutput.
    func close() {
        DispatchQueue.main.async { [weak self] in
            self?.teardownWindow()
        }
    }

    private func teardownWindow() {
        opened = false
        window?.delegate = nil
        window?.orderOut(nil)
        window = nil
        gridView = nil
    }

    /// Key monitor: when this window is key, feed facility KEY (not GRAPHICS, not console).
    @discardableResult
    func routeKeyIfActive(_ event: NSEvent) -> Bool {
        guard isKeyWindowActive, event.type == .keyDown else { return false }
        KernelBridge.shared.setCommandPaneFocused(false)
        if KernelBridge.shared.deliverFacilityKeyDown(event) {
            return true
        }
        // Swallow non-⌘ keys so they do not fall through to the console while editing.
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        if mods.contains(.command) { return false }
        return true
    }

    func setTitle(_ name: String) {
        titleText = name.isEmpty ? "SZ-EDITOR" : name
        let work: () -> Void = { [weak self] in
            self?.applyTitle()
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func applyTitle() {
        window?.title = titleText
    }

    private func buildWindow() {
        let term = FacilityTerminal.shared
        measureCellSize()
        let cols = max(24, term.cols)
        let rows = max(10, term.rows)
        let contentW = CGFloat(cols) * cellW + 8
        let contentH = CGFloat(rows) * cellH + 8

        let win = NSWindow(
            contentRect: NSRect(x: 80, y: 80, width: contentW, height: contentH),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = titleText
        win.delegate = self
        win.isReleasedWhenClosed = false
        win.setFrameAutosaveName("64Forth.FacilityEditor")

        let view = FacilityGridView(frame: NSRect(x: 0, y: 0, width: contentW, height: contentH))
        view.host = self
        view.wantsLayer = true
        win.contentView = view
        window = win
        gridView = view
    }

    private func measureCellSize() {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let charW = ceil(max(1, ("M" as NSString).size(withAttributes: attrs).width))
        let lm = NSLayoutManager()
        let lineH = ceil(max(1, lm.defaultLineHeight(for: font)))
        cellW = charW
        cellH = lineH
    }

    /// Push content-size metrics so `(SZ-VIEW-CELLS)` / SZ-SYNC-SIZE track this window.
    func reportMetricsToKernel() {
        guard let view = gridView ?? window?.contentView else { return }
        let size = view.bounds.size
        guard size.width > 1, size.height > 1 else { return }
        measureCellSize()
        KernelBridge.shared.updateFacilityEditorMetrics(
            contentSize: size,
            cellWidth: cellW,
            cellHeight: cellH
        )
    }

    func windowDidResize(_ notification: Notification) {
        reportMetricsToKernel()
        gridView?.needsDisplay = true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        KernelBridge.shared.setCommandPaneFocused(false)
        window?.makeFirstResponder(gridView)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Inject editor quit (key 17); Forth runs S/D then FACILITY-OFF → close().
        // Do not tear down here (same rule as AppOutput).
        if KernelBridge.shared.isEvaluating, FacilityTerminal.shared.isActive {
            _ = KernelBridge.shared.pushKey(17)
            return false
        }
        opened = false
        DispatchQueue.main.async { [weak self] in
            self?.teardownWindow()
        }
        return false
    }

    fileprivate var gridCellW: CGFloat { cellW }
    fileprivate var gridCellH: CGFloat { cellH }
}

// MARK: - Grid view

final class FacilityGridView: NSView {
    weak var host: FacilityEditorHost?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true } // row 0 at top, matching FacilityTerminal

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let host else { return }
        let term = FacilityTerminal.shared
        let cols = term.cols
        let rows = term.rows
        let cw = host.gridCellW
        let ch = host.gridCellH

        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        let font = NSFont.monospacedSystemFont(ofSize: max(9, ch - 3), weight: .regular)
        let fg = NSColor.labelColor
        let bgSel = NSColor.selectedTextBackgroundColor
        let fgSel = NSColor.selectedTextColor
        let normal: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fg]
        let selected: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fgSel]

        let originX: CGFloat = 4
        let originY: CGFloat = 4

        for y in 0..<rows {
            for x in 0..<cols {
                let px = originX + CGFloat(x) * cw
                let py = originY + CGFloat(y) * ch
                let cellRect = NSRect(x: px, y: py, width: cw, height: ch)
                let attr = term.attrAt(col: x, row: y)
                let reverse = (attr & FacilityTerminal.attrReverse) != 0
                if reverse {
                    bgSel.setFill()
                    cellRect.fill()
                }
                let scalar = term.scalarAt(col: x, row: y)
                guard scalar != 32, let us = UnicodeScalar(scalar) else { continue }
                let s = String(Character(us))
                (s as NSString).draw(at: NSPoint(x: px, y: py), withAttributes: reverse ? selected : normal)
            }
        }

        // Insertion caret (facility cursor).
        if term.isActive {
            let cx = originX + CGFloat(term.cursorCol) * cw
            let cy = originY + CGFloat(term.cursorRow) * ch
            NSColor.controlAccentColor.setFill()
            NSRect(x: cx, y: cy, width: 2, height: ch - 1).fill()
        }
    }

    override func layout() {
        super.layout()
        host?.reportMetricsToKernel()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        host?.reportMetricsToKernel()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        KernelBridge.shared.setCommandPaneFocused(false)
        reportMouse(event, phase: .down)
    }

    override func mouseDragged(with event: NSEvent) {
        reportMouse(event, phase: .drag)
    }

    override func mouseUp(with event: NSEvent) {
        reportMouse(event, phase: .up)
    }

    override func scrollWheel(with event: NSEvent) {
        KernelBridge.shared.reportFacilityScroll(event)
    }

    override func keyDown(with event: NSEvent) {
        _ = FacilityEditorHost.shared.routeKeyIfActive(event)
    }

    private func reportMouse(_ event: NSEvent, phase: KernelBridge.FacilityMousePhase) {
        guard let host else { return }
        let pt = convert(event.locationInWindow, from: nil)
        let cw = max(1, host.gridCellW)
        let ch = max(1, host.gridCellH)
        let col = Int(floor((pt.x - 4) / cw))
        let row = Int(floor((pt.y - 4) / ch))
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = mods.contains(.command)
        let shift = mods.contains(.shift) && !cmd
        let triple = event.clickCount >= 3 && !cmd
        let double = event.clickCount == 2 && !cmd
        KernelBridge.shared.reportFacilityMouse(
            col: col,
            row: row,
            phase: phase,
            command: cmd,
            shift: shift,
            doubleClick: double,
            tripleClick: triple
        )
    }
}
