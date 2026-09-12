//
//  FacilityTerminal.swift
//  64Forth
//
//  Public domain.
//
//  ANS Facility PAGE / AT-XY character grid (TZForth FacilityTerminal port).
//  Used by SZ-EDITOR and other full-screen Facility apps. EMIT writes cells
//  while active; TERMINAL-REFRESH pushes a multi-line string to the host.
//
//  Each cell stores one Unicode scalar (UTF-8 decoded across EMIT/TYPE/XEMIT
//  bytes). Box-drawing and other BMP glyphs render as one monospaced column.
//
//  Thread-safety: Forth `kernel_eval` runs on `64Forth.kernel`; paint / orphan
//  PAGE teardown / FACILITY-OFF exit run on main. All grid state is guarded.
//

import Foundation

/// Character-cell facility terminal (default 88×27 for SZ-EDITOR chrome around 80×20 + 7 chrome rows).
final class FacilityTerminal {
    static let shared = FacilityTerminal()

    static let defaultCols = 88
    static let defaultRows = 27

    /// Per-cell attribute: bit0 = reverse video (selection highlight).
    static let attrReverse: UInt8 = 1

    private let lock = NSLock()

    private var _cols: Int = defaultCols
    private var _rows: Int = defaultRows
    /// Unicode scalar value per cell (space = 32).
    private var cells: [UInt32] = Array(repeating: 32, count: defaultCols * defaultRows)
    /// Parallel to `cells`; nonzero bits mark reverse-video (and future attrs).
    private var attrs: [UInt8] = Array(repeating: 0, count: defaultCols * defaultRows)
    private var _isActive = false
    private var _cursorCol = 0
    private var _cursorRow = 0
    /// When true, subsequent `emit` marks the cell with reverse-video.
    private var reverseOn = false
    /// Incomplete UTF-8 lead/continuation bytes awaiting a full sequence.
    private var utf8Pending: [UInt8] = []

    /// Set when a paint is pending; host flushes via TERMINAL-REFRESH / flush.
    private var _refreshPending = false

    /// True between PAGE/AT-XY and TERMINAL-REFRESH while SZ-REDRAW fills cells.
    /// While set, EMITs must hit the grid even if the command pane has enabled
    /// host emit-bypass (SEE/VIEW during `see dup` was dumping the frame into
    /// the lower console).
    private var _gridPaintActive = false

    private init() {}

    var cols: Int {
        lock.lock(); defer { lock.unlock() }
        return _cols
    }

    var rows: Int {
        lock.lock(); defer { lock.unlock() }
        return _rows
    }

    var isActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isActive
    }

    var cursorCol: Int {
        lock.lock(); defer { lock.unlock() }
        return _cursorCol
    }

    var cursorRow: Int {
        lock.lock(); defer { lock.unlock() }
        return _cursorRow
    }

    var refreshPending: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _refreshPending
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _refreshPending = newValue
        }
    }

    var gridPaintActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return _gridPaintActive
    }

    /// Snapshot for EMIT routing (one lock; avoids torn isActive/gridPaint reads).
    func emitRoutingState() -> (isActive: Bool, gridPaintActive: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (_isActive, _gridPaintActive)
    }

    func resize(cols newCols: Int, rows newRows: Int) {
        lock.lock(); defer { lock.unlock() }
        let c = max(16, newCols)
        let r = max(8, newRows)
        _cols = c
        _rows = r
        cells = Array(repeating: 32, count: c * r)
        attrs = Array(repeating: 0, count: c * r)
        _cursorCol = min(_cursorCol, c - 1)
        _cursorRow = min(_cursorRow, r - 1)
        reverseOn = false
        utf8Pending.removeAll(keepingCapacity: true)
    }

    func page() {
        lock.lock(); defer { lock.unlock() }
        _isActive = true
        _gridPaintActive = true
        cells = Array(repeating: 32, count: _cols * _rows)
        attrs = Array(repeating: 0, count: _cols * _rows)
        _cursorCol = 0
        _cursorRow = 0
        reverseOn = false
        utf8Pending.removeAll(keepingCapacity: true)
        _refreshPending = true
    }

    func deactivate() {
        lock.lock(); defer { lock.unlock() }
        _isActive = false
        _gridPaintActive = false
        _cursorCol = 0
        _cursorRow = 0
        reverseOn = false
        utf8Pending.removeAll(keepingCapacity: true)
        _refreshPending = false
    }

    /// ANS AT-XY: column u1, row u2 (0-based as passed from Forth after 1-based convert in CODE, or 0-based from host).
    func atXY(col: Int, row: Int) {
        lock.lock(); defer { lock.unlock() }
        _isActive = true
        _gridPaintActive = true
        // Incomplete multi-byte sequence does not span AT-XY positions.
        utf8Pending.removeAll(keepingCapacity: true)
        _cursorCol = min(max(col, 0), _cols - 1)
        _cursorRow = min(max(row, 0), _rows - 1)
        _refreshPending = true
    }

    /// End of one paint frame (TERMINAL-REFRESH). Further EMITs may use host bypass.
    func endGridPaint() {
        lock.lock(); defer { lock.unlock() }
        _gridPaintActive = false
    }

    /// Enable/disable reverse-video attribute on subsequent `emit` cells.
    func setReverse(_ on: Bool) {
        lock.lock(); defer { lock.unlock() }
        reverseOn = on
    }

    /// Accept one raw byte (ASCII or UTF-8 fragment). Complete Unicode scalars become one cell.
    func emit(_ byte: UInt8) {
        lock.lock(); defer { lock.unlock() }
        guard _isActive else { return }

        if !utf8Pending.isEmpty {
            // Expect continuation 10xxxxxx
            if byte & 0xC0 == 0x80 {
                utf8Pending.append(byte)
                let need = Self.utf8ExpectedLength(utf8Pending[0])
                if utf8Pending.count < need { return }
                if let scalar = Self.decodeUTF8(utf8Pending) {
                    putScalarUnlocked(scalar)
                } else {
                    putScalarUnlocked(0x2E) // invalid → '.'
                }
                utf8Pending.removeAll(keepingCapacity: true)
                return
            }
            // Broken sequence: drop pending as '.', reprocess this byte
            utf8Pending.removeAll(keepingCapacity: true)
            putScalarUnlocked(0x2E)
            // Re-enter without re-taking the lock.
            emitUnlocked(byte)
            return
        }

        emitUnlocked(byte)
    }

    /// Caller must hold `lock`.
    private func emitUnlocked(_ byte: UInt8) {
        guard _isActive else { return }

        if !utf8Pending.isEmpty {
            if byte & 0xC0 == 0x80 {
                utf8Pending.append(byte)
                let need = Self.utf8ExpectedLength(utf8Pending[0])
                if utf8Pending.count < need { return }
                if let scalar = Self.decodeUTF8(utf8Pending) {
                    putScalarUnlocked(scalar)
                } else {
                    putScalarUnlocked(0x2E)
                }
                utf8Pending.removeAll(keepingCapacity: true)
                return
            }
            utf8Pending.removeAll(keepingCapacity: true)
            putScalarUnlocked(0x2E)
            emitUnlocked(byte)
            return
        }

        if byte == 10 {
            newlineUnlocked()
            return
        }
        if byte == 13 { return }
        // Ignore ANSI CSI and other C0 controls that would corrupt the grid
        if byte < 32 && byte != 9 {
            return
        }
        if byte < 0x80 {
            putScalarUnlocked(UInt32(byte == 9 ? 32 : byte))
            return
        }
        // Multi-byte lead
        if byte & 0xC0 == 0x80 {
            // Lone continuation
            putScalarUnlocked(0x2E)
            return
        }
        let need = Self.utf8ExpectedLength(byte)
        if need <= 1 {
            putScalarUnlocked(0x2E)
            return
        }
        utf8Pending = [byte]
    }

    func newline() {
        lock.lock(); defer { lock.unlock() }
        newlineUnlocked()
    }

    private func newlineUnlocked() {
        guard _isActive else { return }
        utf8Pending.removeAll(keepingCapacity: true)
        _cursorCol = 0
        _cursorRow += 1
        if _cursorRow >= _rows {
            _cursorRow = _rows - 1
        }
        _refreshPending = true
    }

    private func putScalarUnlocked(_ raw: UInt32) {
        var s = raw
        if s == 9 { s = 32 }
        // C0 controls (except already handled TAB) — skip without advancing
        if s < 32 {
            return
        }
        // Non-characters / invalid scalar values → '.'
        if s > 0x10FFFF || (s >= 0xD800 && s <= 0xDFFF) {
            s = 0x2E
        }
        let idx = _cursorRow * _cols + _cursorCol
        if idx >= 0 && idx < cells.count {
            cells[idx] = s
            attrs[idx] = reverseOn ? Self.attrReverse : 0
        }
        advanceCursorUnlocked()
        _refreshPending = true
    }

    private func advanceCursorUnlocked() {
        _cursorCol += 1
        if _cursorCol >= _cols {
            _cursorCol = 0
            _cursorRow += 1
            if _cursorRow >= _rows {
                _cursorRow = _rows - 1
                _cursorCol = _cols - 1
            }
        }
    }

    /// Write `text` left-justified into `width` cells, pad with spaces. Does not wrap.
    func writePadded(col: Int, row: Int, width: Int, text: String) {
        lock.lock(); defer { lock.unlock() }
        guard _isActive, width > 0 else { return }
        _isActive = true
        _gridPaintActive = true
        utf8Pending.removeAll(keepingCapacity: true)
        _cursorCol = min(max(col, 0), _cols - 1)
        _cursorRow = min(max(row, 0), _rows - 1)
        _refreshPending = true
        var n = 0
        for ch in text {
            if n >= width { break }
            if let s = ch.unicodeScalars.first {
                putScalarUnlocked(s.value)
                n += 1
            }
        }
        while n < width {
            putScalarUnlocked(32)
            n += 1
        }
    }

    /// Unicode scalar at facility cell (space if out of range).
    func scalarAt(col: Int, row: Int) -> UInt32 {
        lock.lock(); defer { lock.unlock() }
        guard col >= 0, row >= 0, col < _cols, row < _rows else { return 32 }
        let i = row * _cols + col
        guard i < cells.count else { return 32 }
        return cells[i]
    }

    /// Attribute byte at facility cell (0 if out of range).
    func attrAt(col: Int, row: Int) -> UInt8 {
        lock.lock(); defer { lock.unlock() }
        guard col >= 0, row >= 0, col < _cols, row < _rows else { return 0 }
        let i = row * _cols + col
        guard i < attrs.count else { return 0 }
        return attrs[i]
    }

    /// Multi-line string: `rows` lines of `cols` glyphs (one Unicode scalar each) + newline.
    /// Box-drawing and other BMP chars are one UTF-16 unit (selection/caret math still works).
    func render() -> String {
        lock.lock(); defer { lock.unlock() }
        var out = ""
        out.reserveCapacity(_rows * (_cols + 1))
        for r in 0..<_rows {
            let start = r * _cols
            for c in 0..<_cols {
                let s = cells[start + c]
                if let us = UnicodeScalar(s), s >= 32 {
                    out.append(Character(us))
                } else {
                    out.append(" ")
                }
            }
            out.append("\n")
        }
        return out
    }

    /// True if any cell currently has reverse-video set.
    var hasReverseAttrs: Bool {
        lock.lock(); defer { lock.unlock() }
        return attrs.contains { $0 & Self.attrReverse != 0 }
    }

    /// Copy of reverse-video mask (one byte per cell, bit0 = reverse).
    func reverseMask() -> [UInt8] {
        lock.lock(); defer { lock.unlock() }
        return attrs
    }

    // MARK: - UTF-8

    private static func utf8ExpectedLength(_ lead: UInt8) -> Int {
        if lead < 0x80 { return 1 }
        if lead & 0xE0 == 0xC0 { return 2 }
        if lead & 0xF0 == 0xE0 { return 3 }
        if lead & 0xF8 == 0xF0 { return 4 }
        return 0
    }

    private static func decodeUTF8(_ bytes: [UInt8]) -> UInt32? {
        guard let first = bytes.first else { return nil }
        let n = utf8ExpectedLength(first)
        guard n > 0, bytes.count == n else { return nil }
        for i in 1..<n {
            if bytes[i] & 0xC0 != 0x80 { return nil }
        }
        let scalar: UInt32
        switch n {
        case 1:
            scalar = UInt32(bytes[0])
        case 2:
            scalar = (UInt32(bytes[0] & 0x1F) << 6) | UInt32(bytes[1] & 0x3F)
            if scalar < 0x80 { return nil } // overlong
        case 3:
            scalar = (UInt32(bytes[0] & 0x0F) << 12)
                | (UInt32(bytes[1] & 0x3F) << 6)
                | UInt32(bytes[2] & 0x3F)
            if scalar < 0x800 { return nil }
            if scalar >= 0xD800 && scalar <= 0xDFFF { return nil }
        case 4:
            scalar = (UInt32(bytes[0] & 0x07) << 18)
                | (UInt32(bytes[1] & 0x3F) << 12)
                | (UInt32(bytes[2] & 0x3F) << 6)
                | UInt32(bytes[3] & 0x3F)
            if scalar < 0x10000 || scalar > 0x10FFFF { return nil }
        default:
            return nil
        }
        return scalar
    }
}
