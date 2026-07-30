//
//  FacilityTerminal.swift
//  64Forth
//
//  Public domain.
//
//  ANS Facility PAGE / AT-XY character grid (TZForth FacilityTerminal port).
//  Used by SZ-EDITOR and other full-screen Facility apps. EMIT writes cells
//  while active; TERMINAL-REFRESH pushes a plain multi-line string to the host.
//

import Foundation

/// Character-cell facility terminal (default 88×24 for SZ-EDITOR chrome around 80×20).
final class FacilityTerminal {
    static let shared = FacilityTerminal()

    static let defaultCols = 88
    static let defaultRows = 24

    private(set) var cols: Int = defaultCols
    private(set) var rows: Int = defaultRows
    private var cells: [UInt8] = Array(repeating: 32, count: defaultCols * defaultRows)
    private(set) var isActive = false
    private(set) var cursorCol = 0
    private(set) var cursorRow = 0

    /// Set when a paint is pending; host flushes via TERMINAL-REFRESH / flush.
    var refreshPending = false

    private init() {}

    func resize(cols newCols: Int, rows newRows: Int) {
        let c = max(16, newCols)
        let r = max(8, newRows)
        cols = c
        rows = r
        cells = Array(repeating: 32, count: c * r)
        cursorCol = min(cursorCol, c - 1)
        cursorRow = min(cursorRow, r - 1)
    }

    func page() {
        isActive = true
        cells = Array(repeating: 32, count: cols * rows)
        cursorCol = 0
        cursorRow = 0
        refreshPending = true
    }

    func deactivate() {
        isActive = false
        cursorCol = 0
        cursorRow = 0
        refreshPending = false
    }

    /// ANS AT-XY: column u1, row u2 (0-based as passed from Forth after 1-based convert in CODE, or 0-based from host).
    func atXY(col: Int, row: Int) {
        isActive = true
        cursorCol = min(max(col, 0), cols - 1)
        cursorRow = min(max(row, 0), rows - 1)
        refreshPending = true
    }

    func emit(_ byte: UInt8) {
        guard isActive else { return }
        if byte == 10 {
            newline()
            return
        }
        if byte == 13 { return }
        // Ignore ANSI CSI and other C0 controls that would corrupt the grid
        if byte < 32 && byte != 9 {
            return
        }
        let b: UInt8 = (byte == 9) ? 32 : byte
        let idx = cursorRow * cols + cursorCol
        if idx >= 0 && idx < cells.count {
            cells[idx] = (b >= 32 && b <= 126) ? b : 0x2E
        }
        advanceCursor()
        refreshPending = true
    }

    func newline() {
        guard isActive else { return }
        cursorCol = 0
        cursorRow += 1
        if cursorRow >= rows {
            cursorRow = rows - 1
        }
        refreshPending = true
    }

    private func advanceCursor() {
        cursorCol += 1
        if cursorCol >= cols {
            cursorCol = 0
            cursorRow += 1
            if cursorRow >= rows {
                cursorRow = rows - 1
                cursorCol = cols - 1
            }
        }
    }

    /// Plain multi-line string: `rows` lines of exactly `cols` ASCII glyphs + newline.
    func render() -> String {
        var out = ""
        out.reserveCapacity(rows * (cols + 1))
        for r in 0..<rows {
            let start = r * cols
            for c in 0..<cols {
                let b = cells[start + c]
                if b >= 32 && b <= 126 {
                    out.append(Character(UnicodeScalar(b)))
                } else {
                    out.append(" ")
                }
            }
            out.append("\n")
        }
        return out
    }
}
