//
//  AppOutputHost.swift
//  64Forth — separate char-graphics app window (not the console / Facility).
//
//  Forth owns the cell buffer; Swift only: open/close window, blit, key queue.
//  Public domain / project license.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

/// Minimal AppKit surface for TCOM-style character graphics under interactive 64Forth.
final class AppOutputHost: NSObject, NSWindowDelegate {
    static let shared = AppOutputHost()

    private var window: NSWindow?
    private var gridView: AppGridView?
    private var cols = 80
    private var rows = 25
    private var cellW: CGFloat = 9
    private var cellH: CGFloat = 16
    
    private var pix: [UInt8] = []
    private var pixW = 640
    private var pixH = 400
    private var pixStride = 80          // bytes/row (depth-dependent)
    private var pixDepth = 1            // 1 | 8 | 32
    private var hasPixels = false
    /// Scratch BGRA for CGImage (rebuilt each blit/draw as needed).
    private var drawBGRA: [UInt8] = []

    /// Snapshot blitted from Forth (host-owned copy for drawRect).
    private var cells: [UInt8] = []
    private var keyQueue: [Int64] = []
    private let keyLock = NSLock()
    private var opened = false
    /// Window / menu title; applied on open and via APP-NAME.
    private var appName: String = "64Forth Graphics"

    /// Latest mouse sample in Forth PLOT coords (origin bottom-left).
    /// Button mask matches classic getmous / NSEvent.pressedMouseButtons:
    /// bit0=left (1), bit1=right (2), bit2=middle (4).
    private let mouseLock = NSLock()
    private var mouseX: Int64 = 0
    private var mouseY: Int64 = 0
    private var mouseButtons: Int64 = 0

    /// True when the graphics window is open and key (owns typing for KEY/KEY?).
    var isKeyWindowActive: Bool {
        opened && (window?.isKeyWindow == true)
    }

    // MARK: - Image viewer (NSImage / macOS-supported formats)

    /// Decoded source bitmap (BGRA, top row first) for IMG-RENDER sampling.
    private var imgBGRA: [UInt8] = []
    private var imgW = 0
    private var imgH = 0
    private var imgPath: String = ""

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
        clearMouse()
    }

    fileprivate func clearMouse() {
        mouseLock.lock()
        mouseX = 0
        mouseY = 0
        mouseButtons = 0
        mouseLock.unlock()
    }

    /// Poll model for Forth `(APP-MOUSE)` — latest sample, not a deep queue.
    func readMouse(
        x: UnsafeMutablePointer<Int64>?,
        y: UnsafeMutablePointer<Int64>?,
        buttons: UnsafeMutablePointer<Int64>?
    ) {
        if AgentChannel.isRequested || !opened {
            x?.pointee = 0
            y?.pointee = 0
            buttons?.pointee = 0
            return
        }
        mouseLock.lock()
        x?.pointee = mouseX
        y?.pointee = mouseY
        buttons?.pointee = mouseButtons
        mouseLock.unlock()
    }

    fileprivate func updateMouse(x: Int, y: Int, buttons: Int) {
        mouseLock.lock()
        mouseX = Int64(max(0, x))
        mouseY = Int64(max(0, y))
        mouseButtons = Int64(buttons & 0x7)
        mouseLock.unlock()
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

    /// Packed 1-bit, LSB = leftmost pixel in the byte, row-major, top row first.
    /// Kept for Emitter SA images that still call `(APP-PBLIT)`.
    func pblit(from addr: UnsafeRawPointer?, count: Int, width: Int = 640, height: Int = 400) {
        cblit(from: addr, count: count, depth: 1, width: width, height: height)
    }

    /// Color / depth blit: `depth` is 1 (packed bits), 8 (index), or 32 (BGRA).
    func cblit(
        from addr: UnsafeRawPointer?,
        count: Int,
        depth: Int,
        width: Int = 640,
        height: Int = 400
    ) {
        guard opened, let addr, count > 0 else { return }
        let w = max(1, width)
        let h = max(1, height)
        let d: Int
        let stride: Int
        let need: Int
        switch depth {
        case 8:
            d = 8; stride = w; need = w * h
        case 32:
            d = 32; stride = w * 4; need = w * h * 4
        default:
            d = 1; stride = (w + 7) / 8; need = stride * h
        }
        let n = min(count, need)
        let work = { [weak self] in
            guard let self else { return }
            self.pixW = w
            self.pixH = h
            self.pixDepth = d
            self.pixStride = stride
            if self.pix.count != need {
                self.pix = [UInt8](repeating: 0, count: need)
            }
            self.pix.withUnsafeMutableBytes { dest in
                guard let base = dest.baseAddress else { return }
                memcpy(base, addr, n)
                if n < need {
                    memset(base.advanced(by: n), 0, need - n)
                }
            }
            self.hasPixels = true
            self.gridView?.needsDisplay = true
            self.window?.displayIfNeeded()
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    fileprivate var pixelW: Int { pixW }
    fileprivate var pixelH: Int { pixH }
    fileprivate var showingPixels: Bool { hasPixels }

    /// Default 256-color palette as BGRA UInt32 (low byte = B). Indices 0–15 = classic TCOLOR.
    fileprivate static let defaultPaletteBGRA: [UInt32] = {
        var pal = [UInt32](repeating: 0, count: 256)
        let rgb16: [(UInt8, UInt8, UInt8)] = [
            (0, 0, 0), (0, 0, 170), (0, 170, 0), (0, 170, 170),
            (170, 0, 0), (170, 0, 170), (170, 85, 0), (170, 170, 170),
            (85, 85, 85), (85, 85, 255), (85, 255, 85), (85, 255, 255),
            (255, 85, 85), (255, 85, 255), (255, 255, 85), (255, 255, 255)
        ]
        for (i, c) in rgb16.enumerated() {
            pal[i] = UInt32(c.2) | (UInt32(c.1) << 8) | (UInt32(c.0) << 16) | 0xFF00_0000
        }
        // 16..231: 6×6×6 color cube (VGA-style)
        var idx = 16
        for r in 0..<6 {
            for g in 0..<6 {
                for b in 0..<6 {
                    let R = UInt8(r * 51), G = UInt8(g * 51), B = UInt8(b * 51)
                    pal[idx] = UInt32(B) | (UInt32(G) << 8) | (UInt32(R) << 16) | 0xFF00_0000
                    idx += 1
                }
            }
        }
        // 232..255: grayscale ramp
        for i in 0..<24 {
            let v = UInt8(min(255, 8 + i * 10))
            pal[232 + i] = UInt32(v) | (UInt32(v) << 8) | (UInt32(v) << 16) | 0xFF00_0000
        }
        return pal
    }()

    /// Build a CGImage from the current pixel buffer (top row first → correct in flipped NSView).
    fileprivate func makePixelCGImage() -> CGImage? {
        guard hasPixels, pixW > 0, pixH > 0 else { return nil }
        let need = pixW * pixH * 4
        if drawBGRA.count != need {
            drawBGRA = [UInt8](repeating: 0, count: need)
        }
        switch pixDepth {
        case 8:
            let pal = Self.defaultPaletteBGRA
            let n = min(pix.count, pixW * pixH)
            for i in 0..<n {
                let c = pal[Int(pix[i])]
                let o = i * 4
                drawBGRA[o] = UInt8(c & 0xFF)
                drawBGRA[o + 1] = UInt8((c >> 8) & 0xFF)
                drawBGRA[o + 2] = UInt8((c >> 16) & 0xFF)
                drawBGRA[o + 3] = 0xFF
            }
        case 32:
            let n = min(pix.count, need)
            for i in 0..<n { drawBGRA[i] = pix[i] }
            // Ensure opaque alpha if Forth left 0.
            var i = 3
            while i < n {
                if drawBGRA[i] == 0 { drawBGRA[i] = 0xFF }
                i += 4
            }
        default:
            // 1-bit → green-on-black (legacy look)
            let gR: UInt8 = 178, gG: UInt8 = 255, gB: UInt8 = 178
            for y in 0..<pixH {
                let row = y * pixStride
                for x in 0..<pixW {
                    let on = (pix[row + (x >> 3)] & (1 << (x & 7))) != 0
                    let o = (y * pixW + x) * 4
                    if on {
                        drawBGRA[o] = gB; drawBGRA[o + 1] = gG; drawBGRA[o + 2] = gR; drawBGRA[o + 3] = 0xFF
                    } else {
                        drawBGRA[o] = 0; drawBGRA[o + 1] = 0; drawBGRA[o + 2] = 0; drawBGRA[o + 3] = 0xFF
                    }
                }
            }
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )
        guard let provider = CGDataProvider(data: Data(drawBGRA) as CFData) else { return nil }
        return CGImage(
            width: pixW,
            height: pixH,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: pixW * 4,
            space: cs,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
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

    // MARK: Image load / render

    func clearImage() {
        imgBGRA = []
        imgW = 0
        imgH = 0
        imgPath = ""
    }

    /// Decode any format NSImage can open into a BGRA buffer (top-left origin).
    @discardableResult
    private func ingestNSImage(_ image: NSImage, pathLabel: String) -> Bool {
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            let w = max(1, Int(image.size.width.rounded()))
            let h = max(1, Int(image.size.height.rounded()))
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: w,
                pixelsHigh: h,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: w * 4,
                bitsPerPixel: 32
            ) else { return false }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSColor.black.setFill()
            NSRect(x: 0, y: 0, width: w, height: h).fill()
            image.draw(
                in: NSRect(x: 0, y: 0, width: w, height: h),
                from: .zero,
                operation: .copy,
                fraction: 1.0
            )
            NSGraphicsContext.restoreGraphicsState()
            return ingestBitmapRep(rep, pathLabel: pathLabel)
        }
        return ingestCGImage(cg, pathLabel: pathLabel)
    }

    private func ingestCGImage(_ cg: CGImage, pathLabel: String) -> Bool {
        let w = cg.width
        let h = cg.height
        guard w > 0, h > 0 else { return false }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )
        guard let ctx = CGContext(
            data: &buf,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: cs,
            bitmapInfo: info.rawValue
        ) else { return false }
        ctx.interpolationQuality = .none
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        imgBGRA = buf
        imgW = w
        imgH = h
        imgPath = pathLabel
        return true
    }

    private func ingestBitmapRep(_ rep: NSBitmapImageRep, pathLabel: String) -> Bool {
        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        guard w > 0, h > 0, let data = rep.bitmapData else { return false }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let spp = rep.samplesPerPixel
        let bpr = rep.bytesPerRow
        for y in 0..<h {
            for x in 0..<w {
                let src = y * bpr + x * spp
                let dst = (y * w + x) * 4
                let r = data[src]
                let g = spp > 1 ? data[src + 1] : r
                let b = spp > 2 ? data[src + 2] : r
                let a = spp > 3 ? data[src + 3] : 255
                buf[dst] = b
                buf[dst + 1] = g
                buf[dst + 2] = r
                buf[dst + 3] = a == 0 ? 255 : a
            }
        }
        imgBGRA = buf
        imgW = w
        imgH = h
        imgPath = pathLabel
        return true
    }

    /// NSOpenPanel for macOS-readable images. 0=ok, -1=cancel, -2=failed.
    func chooseImage() -> Int64 {
        if AgentChannel.isRequested { return -1 }
        let work: () -> Int64 = { [weak self] in
            guard let self else { return -2 }
            let panel = NSOpenPanel()
            panel.title = "Open Image"
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.image]
            if let win = self.window {
                let group = DispatchGroup()
                var result: NSApplication.ModalResponse = .abort
                group.enter()
                panel.beginSheetModal(for: win) { r in
                    result = r
                    group.leave()
                }
                while group.wait(timeout: .now() + 0.05) == .timedOut {
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
                }
                guard result == .OK, let url = panel.url else { return -1 }
                return self.loadImage(at: url)
            } else {
                guard panel.runModal() == .OK, let url = panel.url else { return -1 }
                return self.loadImage(at: url)
            }
        }
        if Thread.isMainThread {
            return work()
        }
        var ior: Int64 = -2
        DispatchQueue.main.sync { ior = work() }
        return ior
    }

    /// Load image from UTF-8 path. 0=ok, -2=failed.
    func loadImagePath(from addr: UnsafeRawPointer?, count: Int) -> Int64 {
        guard let addr, count > 0 else { return -2 }
        let n = min(count, 4096)
        let path = String(bytes: UnsafeRawBufferPointer(start: addr, count: n), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else { return -2 }
        let url = URL(fileURLWithPath: path)
        let work: () -> Int64 = { [weak self] in
            self?.loadImage(at: url) ?? -2
        }
        if Thread.isMainThread { return work() }
        var ior: Int64 = -2
        DispatchQueue.main.sync { ior = work() }
        return ior
    }

    private func loadImage(at url: URL) -> Int64 {
        guard let image = NSImage(contentsOf: url) else {
            clearImage()
            return -2
        }
        if ingestNSImage(image, pathLabel: url.path) {
            return 0
        }
        clearImage()
        return -2
    }

    func imageSize(w: UnsafeMutablePointer<Int64>?, h: UnsafeMutablePointer<Int64>?) {
        w?.pointee = Int64(imgW)
        h?.pointee = Int64(imgH)
    }

    /// Sample loaded image into Forth TRUECOLOR buffer (BGRA, top row first).
    /// `cx`/`cy` = image-space center (top-left origin). `zoom100` = 100 → 1:1.
    func renderImage(
        to dest: UnsafeMutableRawPointer?,
        destW: Int,
        destH: Int,
        centerX: Int,
        centerY: Int,
        zoom100: Int
    ) -> Int64 {
        guard let dest, destW > 0, destH > 0, imgW > 0, imgH > 0, !imgBGRA.isEmpty else {
            return -1
        }
        let z = max(1, zoom100)
        let out = dest.assumingMemoryBound(to: UInt8.self)
        let halfW = destW / 2
        let halfH = destH / 2
        for sy in 0..<destH {
            for sx in 0..<destW {
                let ix = centerX + (sx - halfW) * 100 / z
                let iy = centerY + (sy - halfH) * 100 / z
                let o = (sy * destW + sx) * 4
                if ix < 0 || iy < 0 || ix >= imgW || iy >= imgH {
                    out[o] = 0; out[o + 1] = 0; out[o + 2] = 0; out[o + 3] = 255
                } else {
                    let s = (iy * imgW + ix) * 4
                    out[o] = imgBGRA[s]
                    out[o + 1] = imgBGRA[s + 1]
                    out[o + 2] = imgBGRA[s + 2]
                    out[o + 3] = 255
                }
            }
        }
        return 0
    }
}

// MARK: - View

final class AppGridView: NSView {
    weak var host: AppOutputHost?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let opts: NSTrackingArea.Options = [
            .activeInKeyWindow,
            .mouseMoved,
            .inVisibleRect,
            .enabledDuringMouseDrag
        ]
        addTrackingArea(NSTrackingArea(rect: bounds, options: opts, owner: self, userInfo: nil))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let host else { return }
        NSColor.black.setFill()
        bounds.fill()

        if host.showingPixels, let img = host.makePixelCGImage() {
            let rect = CGRect(x: 4, y: 4, width: bounds.width - 8, height: bounds.height - 8)
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.interpolationQuality = .none
                ctx.draw(img, in: rect)
            }
        }

        let font = NSFont.monospacedSystemFont(ofSize: host.gridCellH - 2, weight: .regular)
        let textFg = NSColor(calibratedRed: 0.7, green: 1.0, blue: 0.7, alpha: 1)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textFg]
        let cols = host.gridCols
        let rows = host.gridRows
        let cw = host.gridCellW
        let ch = host.gridCellH
        for y in 0..<rows {
            for x in 0..<cols {
                let chv = host.cellAt(col: x, row: y)
                if chv == 32 { continue }          // leave pixels visible
                let s: String
                if chv == 219 { s = "\u{2588}" }
                else if chv < 32 || chv > 126 { s = "?" }
                else { s = String(UnicodeScalar(chv)) }
                let px = CGFloat(x) * cw + 4
                let py = CGFloat(rows - 1 - y) * ch + 4
                (s as NSString).draw(at: NSPoint(x: px, y: py), withAttributes: attrs)
            }
        }
    }

    /// Map AppKit view point → Forth PLOT coords (origin bottom-left).
    private func reportMouse(_ event: NSEvent) {
        guard let host else { return }
        let pw = host.showingPixels ? max(1, host.pixelW) : 640
        let ph = host.showingPixels ? max(1, host.pixelH) : 400
        let dw = max(1, bounds.width - 8)
        let dh = max(1, bounds.height - 8)
        let sx = dw / CGFloat(pw)
        let sy = dh / CGFloat(ph)
        let local = convert(event.locationInWindow, from: nil)
        var x = Int(((local.x - 4) / sx).rounded(.down))
        var y = Int(((local.y - 4) / sy).rounded(.down))
        if x < 0 { x = 0 }
        if y < 0 { y = 0 }
        if x >= pw { x = pw - 1 }
        if y >= ph { y = ph - 1 }
        // NSEvent.pressedMouseButtons: bit0 left, bit1 right, bit2 middle.
        let buttons = Int(NSEvent.pressedMouseButtons) & 0x7
        host.updateMouse(x: x, y: y, buttons: buttons)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        reportMouse(event)
    }

    override func mouseDragged(with event: NSEvent) {
        reportMouse(event)
    }

    override func mouseUp(with event: NSEvent) {
        reportMouse(event)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        reportMouse(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        reportMouse(event)
    }

    override func rightMouseUp(with event: NSEvent) {
        reportMouse(event)
    }

    override func otherMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        reportMouse(event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        reportMouse(event)
    }

    override func otherMouseUp(with event: NSEvent) {
        reportMouse(event)
    }

    override func mouseMoved(with event: NSEvent) {
        reportMouse(event)
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

@_cdecl("host_app_pblit")
public func host_app_pblit(_ addr: UnsafeRawPointer?, _ nbytes: Int64) {
    AppOutputHost.shared.pblit(from: addr, count: Int(nbytes))
}

@_cdecl("host_app_cblit")
public func host_app_cblit(_ addr: UnsafeRawPointer?, _ nbytes: Int64, _ depth: Int64) {
    AppOutputHost.shared.cblit(from: addr, count: Int(nbytes), depth: Int(depth))
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

/// Latest mouse sample for GRAPHICS `(APP-MOUSE)`.
/// Writes Forth PLOT coords (origin bottom-left) and classic button mask.
@_cdecl("host_app_mouse")
public func host_app_mouse(
    _ x: UnsafeMutablePointer<Int64>?,
    _ y: UnsafeMutablePointer<Int64>?,
    _ buttons: UnsafeMutablePointer<Int64>?
) {
    AppOutputHost.shared.readMouse(x: x, y: y, buttons: buttons)
}

/// NSOpenPanel image pick + decode. 0=ok, -1=cancel, -2=fail.
@_cdecl("host_app_img_choose")
public func host_app_img_choose() -> Int64 {
    AppOutputHost.shared.chooseImage()
}

/// Load image from UTF-8 path. 0=ok, -2=fail.
@_cdecl("host_app_img_load")
public func host_app_img_load(_ addr: UnsafeRawPointer?, _ nbytes: Int64) -> Int64 {
    AppOutputHost.shared.loadImagePath(from: addr, count: Int(nbytes))
}

/// Natural pixel size of the loaded image (0,0 if none).
@_cdecl("host_app_img_size")
public func host_app_img_size(
    _ w: UnsafeMutablePointer<Int64>?,
    _ h: UnsafeMutablePointer<Int64>?
) {
    AppOutputHost.shared.imageSize(w: w, h: h)
}

/// Render view into TRUECOLOR BGRA buffer. zoom100=100 is 1:1.
@_cdecl("host_app_img_render")
public func host_app_img_render(
    _ dest: UnsafeMutableRawPointer?,
    _ destW: Int64,
    _ destH: Int64,
    _ cx: Int64,
    _ cy: Int64,
    _ zoom100: Int64
) -> Int64 {
    AppOutputHost.shared.renderImage(
        to: dest,
        destW: Int(destW),
        destH: Int(destH),
        centerX: Int(cx),
        centerY: Int(cy),
        zoom100: Int(zoom100)
    )
}
