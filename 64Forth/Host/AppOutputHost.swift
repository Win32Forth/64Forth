//
//  AppOutputHost.swift
//  64Forth — separate char-graphics app window (not the console / Facility).
//
//  Forth owns the cell buffer; Swift only: open/close window, blit, key queue.
//  Public domain / project license.
//

import AppKit
import Foundation

/// Minimal AppKit surface for TCOM-style character graphics under interactive 64Forth.
final class AppOutputHost: NSObject, NSWindowDelegate {
    static let shared = AppOutputHost()

    private var window: NSWindow?
    private var gridView: AppGridView?
    private var cols = 80
    private var rows = 25
    private var cellW: CGFloat = 9
    private var cellH: CGFloat = 16
    /// Snapshot blitted from Forth (host-owned copy for drawRect).
    private var cells: [UInt8] = []
    private var keyQueue: [Int64] = []
    private let keyLock = NSLock()
    private var opened = false
    /// Window / menu title; applied on open and via APP-NAME.
    private var appName: String = "64Forth Graphics"

    /// True when the graphics window is open and key (owns typing for KEY/KEY?).
    var isKeyWindowActive: Bool {
        opened && (window?.isKeyWindow == true)
    }

    private override init() {
        super.init()
    }

    /// op: 1=OPEN(a=cols,b=rows) 2=CLOSE 3=REFRESH(a=addr unused here — use blit API)
    /// Prefer dedicated cdecls for refresh/key; multiplex kept thin.
    func dispatch(op: Int64, a: Int64, b: Int64) -> Int64 {
        switch op {
        case 1:
            return open(cols: Int(a) > 0 ? Int(a) : 80, rows: Int(b) > 0 ? Int(b) : 25)
        case 2:
            close()
            return 0
        default:
            return -1
        }
    }

    @discardableResult
    func open(cols c: Int, rows r: Int) -> Int64 {
        if AgentChannel.isRequested { return -1 }
        let cols = max(1, min(c, 256))
        let rows = max(1, min(r, 128))
        let work = { [weak self] in
            guard let self else { return }
            self.cols = cols
            self.rows = rows
            self.cells = [UInt8](repeating: 32, count: cols * rows)
            if self.window == nil {
                self.buildWindow()
            } else {
                self.resizeWindow()
            }
            self.window?.makeKeyAndOrderFront(nil)
            self.window?.makeFirstResponder(self.gridView)
            NSApp.activate(ignoringOtherApps: true)
            self.opened = true
            self.gridView?.needsDisplay = true
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
        return 0
    }

    func close() {
        // Never tear down synchronously inside pumpUIForKeyInput / sendEvent.
        DispatchQueue.main.async { [weak self] in
            self?.teardownWindow()
        }
    }

    private func teardownWindow() {
        opened = false
        pushKey(0x1B) // unblock Forth KEY if waiting
        window?.delegate = nil
        window?.orderOut(nil)
        window = nil
        gridView = nil
        keyLock.lock()
        keyQueue.removeAll()
        keyLock.unlock()
    }

    /// Called from KernelBridge key monitor while evaluate is active.
    /// Returns true if the event was consumed for the graphics KEY queue.
    @discardableResult
    func routeKeyIfActive(_ event: NSEvent) -> Bool {
        guard isKeyWindowActive, event.type == .keyDown else { return false }
        let code = Self.mapKeyEvent(event)
        if code >= 0 {
            pushKey(code)
        }
        return true // swallow so console KEY does not also see it
    }

    fileprivate static func mapKeyEvent(_ event: NSEvent) -> Int64 {
        switch event.keyCode {
        case 123: return 203
        case 124: return 205
        case 125: return 208
        case 126: return 200
        case 53: return 0x1B
        case 49: return 0x20
        default: break
        }
        if let chars = event.charactersIgnoringModifiers, let ch = chars.utf16.first, ch < 128 {
            return Int64(ch)
        }
        return -1
    }

    /// Copy Forth buffer (addr, cols*rows bytes) into host snapshot and redraw.
    func blit(from addr: UnsafeRawPointer?, count: Int) {
        guard opened, let addr, count > 0 else { return }
        let n = min(count, cols * rows)
        let work = { [weak self] in
            guard let self else { return }
            if self.cells.count != self.cols * self.rows {
                self.cells = [UInt8](repeating: 32, count: self.cols * self.rows)
            }
            self.cells.withUnsafeMutableBytes { dest in
                guard let base = dest.baseAddress else { return }
                memcpy(base, addr, n)
            }
            self.gridView?.needsDisplay = true
            self.window?.displayIfNeeded()
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    /// Set window title (and remembered name for next open).
    func setAppName(from addr: UnsafeRawPointer?, count: Int) {
        let name: String
        if let addr, count > 0 {
            let n = min(count, 255)
            name = String(bytes: UnsafeRawBufferPointer(start: addr, count: n), encoding: .utf8)
                ?? "64Forth Graphics"
        } else {
            name = "64Forth Graphics"
        }
        let work = { [weak self] in
            guard let self else { return }
            self.appName = name.isEmpty ? "64Forth Graphics" : name
            self.window?.title = self.appName
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    /// F-PC/TCOM `TONE`: `freq` = Hz, `dur` = tenths of a second.
    /// Plays a sine tone (blocks roughly `dur` tenths). Falls back to `NSSound.beep()`
    /// if the buffer cannot be built. Caps duration like F-PC (`50` tenths max).
    func tone(freq: Int64, dur: Int64) {
        let hz = max(20.0, min(Double(freq), 12000.0))
        let tenths = max(0, min(Int(dur), 50))
        if tenths == 0 { return }
        let seconds = Double(tenths) / 10.0
        guard let data = Self.sineWAV(frequency: hz, seconds: seconds) else {
            let work = { NSSound.beep() }
            if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
            Thread.sleep(forTimeInterval: seconds)
            return
        }
        let play: () -> Void = {
            if let sound = NSSound(data: data) {
                sound.play()
            } else {
                NSSound.beep()
            }
        }
        if Thread.isMainThread {
            play()
        } else {
            DispatchQueue.main.async(execute: play)
        }
        // Block like F-PC TONE so GAME timing stays sane; main evaluate loop pumps.
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    /// Minimal 16-bit mono PCM WAV at 22'050 Hz.
    private static func sineWAV(frequency: Double, seconds: Double) -> Data? {
        let sampleRate = 22050.0
        let n = max(1, Int(sampleRate * seconds))
        var data = Data()
        data.reserveCapacity(44 + n * 2)
        func appendU32(_ v: UInt32) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        func appendU16(_ v: UInt16) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        let dataSize = UInt32(n * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        appendU32(36 + dataSize)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        appendU32(16)            // PCM chunk size
        appendU16(1)             // PCM
        appendU16(1)             // mono
        appendU32(UInt32(sampleRate))
        appendU32(UInt32(sampleRate * 2)) // byte rate
        appendU16(2)             // block align
        appendU16(16)            // bits
        data.append(contentsOf: Array("data".utf8))
        appendU32(dataSize)
        let twoPiF = 2.0 * Double.pi * frequency
        for i in 0..<n {
            let t = Double(i) / sampleRate
            // Short attack/release to avoid clicks
            var env = 1.0
            let attack = min(0.01, seconds / 4)
            let release = min(0.02, seconds / 3)
            if t < attack { env = t / attack }
            if t > seconds - release { env = max(0, (seconds - t) / release) }
            let sample = Int16(max(-32767, min(32767, sin(twoPiF * t) * 0.35 * env * 32767.0)))
            appendU16(UInt16(bitPattern: sample))
        }
        return data
    }

    /// Yield so the main evaluate pump can deliver keys / redraw.
    /// Do not nest `nextEvent` here (close-time crashes); main already pumps.
    func pump() {
        Thread.sleep(forTimeInterval: 0.01)
    }

    func keyAvailable() -> Int64 {
        keyLock.lock()
        let ready = !keyQueue.isEmpty
        keyLock.unlock()
        if !ready {
            // Busy KEY? loops (tetra MOVEMENT) must yield or they starve UI.
            Thread.sleep(forTimeInterval: 0.001)
        }
        return ready ? -1 : 0
    }

    func takeKey() -> Int64 {
        keyLock.lock()
        defer { keyLock.unlock() }
        if keyQueue.isEmpty { return -1 }
        return keyQueue.removeFirst()
    }

    /// Blocking-ish KEY: wait up to ~timeoutSec. Main thread already pumps
    /// during evaluate — do not nest nextEvent here (crashes on close).
    func waitKey(timeoutSec: Double = 30) -> Int64 {
        let deadline = Date().addingTimeInterval(timeoutSec)
        while Date() < deadline {
            if !opened { return 0x1B }
            let k = takeKey()
            if k >= 0 { return k }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return -1
    }

    fileprivate func pushKey(_ c: Int64) {
        keyLock.lock()
        if keyQueue.count < 64 {
            keyQueue.append(c)
        }
        keyLock.unlock()
    }

    private func buildWindow() {
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        cellH = font.ascender - font.descender + 2
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        cellW = ("M" as NSString).size(withAttributes: attrs).width
        if cellW < 1 { cellW = 9 }
        if cellH < 1 { cellH = 16 }

        let contentW = CGFloat(cols) * cellW + 8
        let contentH = CGFloat(rows) * cellH + 8
        let rect = NSRect(x: 100, y: 80, width: contentW, height: contentH)
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let win = NSWindow(
            contentRect: rect,
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        win.title = appName
        win.delegate = self
        let view = AppGridView(frame: NSRect(x: 0, y: 0, width: contentW, height: contentH))
        view.host = self
        view.wantsLayer = true
        win.contentView = view
        window = win
        gridView = view
    }

    private func resizeWindow() {
        guard let win = window else { return }
        let contentW = CGFloat(cols) * cellW + 8
        let contentH = CGFloat(rows) * cellH + 8
        win.setContentSize(NSSize(width: contentW, height: contentH))
        gridView?.frame = NSRect(x: 0, y: 0, width: contentW, height: contentH)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Defer teardown — closing mid pumpUIForKeyInput/sendEvent crashes.
        opened = false
        pushKey(0x1B)
        DispatchQueue.main.async { [weak self] in
            self?.teardownWindow()
        }
        return false
    }

    fileprivate func cellAt(col: Int, row: Int) -> UInt8 {
        guard col >= 0, row >= 0, col < cols, row < rows else { return 32 }
        let i = row * cols + col
        guard i < cells.count else { return 32 }
        return cells[i]
    }

    fileprivate var gridCols: Int { cols }
    fileprivate var gridRows: Int { rows }
    fileprivate var gridCellW: CGFloat { cellW }
    fileprivate var gridCellH: CGFloat { cellH }
}

// MARK: - View

final class AppGridView: NSView {
    weak var host: AppOutputHost?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let host else { return }
        NSColor.black.setFill()
        bounds.fill()
        let font = NSFont.monospacedSystemFont(ofSize: host.gridCellH - 2, weight: .regular)
        let fg = NSColor(calibratedRed: 0.7, green: 1.0, blue: 0.7, alpha: 1)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fg]
        let cols = host.gridCols
        let rows = host.gridRows
        let cw = host.gridCellW
        let ch = host.gridCellH
        for y in 0..<rows {
            for x in 0..<cols {
                let chv = host.cellAt(col: x, row: y)
                let s: String
                if chv == 219 {
                    s = "\u{2588}"
                } else if chv < 32 || chv > 126 {
                    s = "?"
                } else {
                    s = String(UnicodeScalar(chv))
                }
                let px = CGFloat(x) * cw + 4
                let py = CGFloat(rows - 1 - y) * ch + 4
                (s as NSString).draw(at: NSPoint(x: px, y: py), withAttributes: attrs)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard let host else { return }
        let code = AppOutputHost.mapKeyEvent(event)
        if code >= 0 {
            host.pushKey(code)
        }
    }
}

// MARK: - C ABI from forth.s

@_cdecl("host_app_open")
public func host_app_open(_ cols: Int64, _ rows: Int64) -> Int64 {
    AppOutputHost.shared.open(cols: Int(cols), rows: Int(rows))
}

@_cdecl("host_app_close")
public func host_app_close() {
    AppOutputHost.shared.close()
}

@_cdecl("host_app_blit")
public func host_app_blit(_ addr: UnsafeRawPointer?, _ nbytes: Int64) {
    AppOutputHost.shared.blit(from: addr, count: Int(nbytes))
}

@_cdecl("host_app_keyq")
public func host_app_keyq() -> Int64 {
    AppOutputHost.shared.keyAvailable()
}

@_cdecl("host_app_key")
public func host_app_key() -> Int64 {
    let k = AppOutputHost.shared.takeKey()
    if k >= 0 { return k }
    return AppOutputHost.shared.waitKey(timeoutSec: 0.5)
}

@_cdecl("host_app_name")
public func host_app_name(_ addr: UnsafeRawPointer?, _ nbytes: Int64) {
    AppOutputHost.shared.setAppName(from: addr, count: Int(nbytes))
}

@_cdecl("host_app_tone")
public func host_app_tone(_ freq: Int64, _ dur: Int64) {
    AppOutputHost.shared.tone(freq: freq, dur: dur)
}

@_cdecl("host_app_pump")
public func host_app_pump() {
    AppOutputHost.shared.pump()
}
