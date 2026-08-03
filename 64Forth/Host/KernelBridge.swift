//
//  KernelBridge.swift
//  64Forth
//
//  Public domain.
//
//  Swift ↔ PickleForth assembly kernel.
//  Host words: FROMLIB, FLOAD/INCLUDE, CHDIR, PWD, DIR (TZForth-style).
//  Phase 5: eval reentrancy guard (kernel is not re-entrant).
//

import Foundation
#if os(macOS)
import AppKit
#endif

// MARK: - C ABI (forth.s)

@_silgen_name("kernel_init")
private func kernel_init() -> Int32

@_silgen_name("kernel_eval")
private func kernel_eval(_ line: UnsafePointer<CChar>?, _ n: Int) -> Int32

@_silgen_name("kernel_data_depth")
private func kernel_data_depth() -> Int32

@_silgen_name("kernel_take_repl_batch_stop")
private func kernel_take_repl_batch_stop() -> Int32

@_silgen_name("kernel_take_sz_editor_open")
private func kernel_take_sz_editor_open() -> Int32

@_silgen_name("kernel_set_sz_app_quit")
private func kernel_set_sz_app_quit()

@_silgen_name("kernel_clear_sz_app_quit")
private func kernel_clear_sz_app_quit()

@_silgen_name("kernel_sz_app_quit_pending")
private func kernel_sz_app_quit_pending() -> Int32

@_silgen_name("kernel_on_memory_fault")
private func kernel_on_memory_fault(_ sig: Int32)

@_silgen_name("kernel_take_fault_flag")
private func kernel_take_fault_flag() -> Int32

@_silgen_name("kernel_set_emit")
private func kernel_set_emit(_ fn: (@convention(c) (Int32) -> Void)?)
@_silgen_name("kernel_set_emit_buf")
private func kernel_set_emit_buf(_ fn: (@convention(c) (UnsafePointer<CChar>?, Int) -> Void)?)

@_silgen_name("kernel_set_key")
private func kernel_set_key(_ fn: (@convention(c) () -> Int32)?)

@_silgen_name("kernel_set_key_q")
private func kernel_set_key_q(_ fn: (@convention(c) () -> Int32)?)

@_silgen_name("kernel_set_time_date")
private func kernel_set_time_date(
    _ fn: (@convention(c) (UnsafeMutablePointer<Int64>?) -> Void)?
)

/// File-Access multiplex: op + up to 4 int args + optional path/buffer pointer.
/// Results in o1/o2/o3 (meaning depends on op). Returns ior (0 = ok).
@_silgen_name("kernel_set_file_op")
private func kernel_set_file_op(
    _ fn: (@convention(c) (
        Int64, Int64, Int64, Int64, Int64,
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<Int64>?,
        UnsafeMutablePointer<Int64>?,
        UnsafeMutablePointer<Int64>?
    ) -> Int64)?
)

@_silgen_name("kernel_set_fromlib")
private func kernel_set_fromlib(_ fn: (@convention(c) () -> Void)?)

@_silgen_name("kernel_set_fromlib_clear")
private func kernel_set_fromlib_clear(_ fn: (@convention(c) () -> Void)?)

@_silgen_name("kernel_set_end_include")
private func kernel_set_end_include(_ fn: (@convention(c) () -> Void)?)

@_silgen_name("kernel_set_load_file")
private func kernel_set_load_file(
    _ fn: (@convention(c) (
        UnsafePointer<CChar>?,
        Int,
        UnsafeMutablePointer<UnsafePointer<CChar>?>?,
        UnsafeMutablePointer<Int>?
    ) -> Int32)?
)

@_silgen_name("kernel_set_resolve_key")
private func kernel_set_resolve_key(
    _ fn: (@convention(c) (
        UnsafePointer<CChar>?,
        Int,
        UnsafeMutablePointer<CChar>?,
        Int,
        UnsafeMutablePointer<Int>?
    ) -> Int32)?
)

@_silgen_name("kernel_set_last_load_key")
private func kernel_set_last_load_key(
    _ fn: (@convention(c) (
        UnsafeMutablePointer<CChar>?,
        Int,
        UnsafeMutablePointer<Int>?
    ) -> Int32)?
)

@_silgen_name("kernel_set_chdir")
private func kernel_set_chdir(
    _ fn: (@convention(c) (UnsafePointer<CChar>?, Int) -> Void)?
)

@_silgen_name("kernel_set_pwd")
private func kernel_set_pwd(_ fn: (@convention(c) () -> Void)?)

@_silgen_name("kernel_set_dir")
private func kernel_set_dir(
    _ fn: (@convention(c) (UnsafePointer<CChar>?, Int) -> Void)?
)

@_silgen_name("kernel_set_edit")
private func kernel_set_edit(
    _ fn: (@convention(c) (UnsafePointer<CChar>?, Int) -> Void)?
)

@_silgen_name("kernel_set_facility_op")
private func kernel_set_facility_op(
    _ fn: (@convention(c) (Int64, Int64, Int64) -> Void)?
)

@_silgen_name("kernel_set_allocate")
private func kernel_set_allocate(
    _ fn: (@convention(c) (Int, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32)?
)

@_silgen_name("kernel_set_free")
private func kernel_set_free(
    _ fn: (@convention(c) (UnsafeMutableRawPointer?) -> Int32)?
)

@_silgen_name("kernel_set_bi_mul")
private func kernel_set_bi_mul(
    _ fn: (@convention(c) (Int64, Int64, Int64) -> Void)?
)

@_silgen_name("kernel_set_bi_divmod")
private func kernel_set_bi_divmod(
    _ fn: (@convention(c) (Int64, Int64, Int64, Int64) -> Void)?
)

@_silgen_name("kernel_set_bi_isqrt")
private func kernel_set_bi_isqrt(
    _ fn: (@convention(c) (Int64, Int64) -> Void)?
)

@_silgen_name("kernel_set_float_op")
private func kernel_set_float_op(
    _ fn: (@convention(c) (
        Int64, Int64, Int64, Int64, Int64,
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<Int64>?,
        UnsafeMutablePointer<Int64>?,
        UnsafeMutablePointer<Int64>?
    ) -> Int64)?
)

// MARK: - C hook target (must not touch KernelBridge.shared)

private var kernelHookTarget: KernelBridge?

private let kernelEmitTrampoline: @convention(c) (Int32) -> Void = { c in
    kernelHookTarget?.handleEmitFromKernel(c)
}

/// Bulk TYPE/XEMIT: copy bytes first (kernel buffer must not be assumed stable),
/// then UTF-8 decode (Latin-1 fallback). Facility mode paints cells without
/// building a large intermediate String when possible.
private let kernelEmitBufTrampoline: @convention(c) (UnsafePointer<CChar>?, Int) -> Void = { ptr, n in
    guard let ptr, n > 0 else { return }
    // Guard against garbage length (e.g. stack corruption after editor exit).
    let count = min(n, 1 << 20) // 1 MiB cap
    guard count > 0 else { return }
    var bytes = [UInt8](repeating: 0, count: count)
    memcpy(&bytes, ptr, count)
    kernelHookTarget?.handleEmitBytes(bytes)
}

private let kernelKeyTrampoline: @convention(c) () -> Int32 = {
    kernelHookTarget?.handleKeyFromKernel() ?? -1
}

private let kernelKeyQTrampoline: @convention(c) () -> Int32 = {
    kernelHookTarget?.handleKeyAvailableFromKernel() ?? 0
}

private let kernelTimeDateTrampoline: @convention(c) (UnsafeMutablePointer<Int64>?) -> Void = { out in
    guard let out else { return }
    var cal = Calendar.current
    cal.timeZone = .current
    let now = Date()
    let c = cal.dateComponents([.second, .minute, .hour, .day, .month, .year], from: now)
    out[0] = Int64(c.second ?? 0)
    out[1] = Int64(c.minute ?? 0)
    out[2] = Int64(c.hour ?? 0)
    out[3] = Int64(c.day ?? 1)
    out[4] = Int64(c.month ?? 1)
    out[5] = Int64(c.year ?? 1970)
}

/// File-Access op codes (must match forth.s XFILE_* helpers).
private enum FileOp: Int64 {
    case open = 1
    case create = 2
    case close = 3
    case read = 4
    case write = 5
    case readLine = 6
    case writeLine = 7
    case position = 8
    case size = 9
    case repos = 10
    case resize = 11
    case delete = 12
    case rename = 13
    case status = 14
    case flush = 15
}

private func forthString(ptr: UnsafeMutableRawPointer?, len: Int64) -> String {
    guard let ptr, len > 0, len < 1_000_000 else { return "" }
    let p = ptr.assumingMemoryBound(to: UInt8.self)
    return String(bytes: UnsafeBufferPointer(start: p, count: Int(len)), encoding: .utf8)
        ?? String(bytes: UnsafeBufferPointer(start: p, count: Int(len)), encoding: .isoLatin1)
        ?? ""
}

private let kernelFileOpTrampoline: @convention(c) (
    Int64, Int64, Int64, Int64, Int64,
    UnsafeMutableRawPointer?,
    UnsafeMutablePointer<Int64>?,
    UnsafeMutablePointer<Int64>?,
    UnsafeMutablePointer<Int64>?
) -> Int64 = { op, a, b, c, d, ptr, o1, o2, o3 in
    let fa = FileAccess.shared
    switch FileOp(rawValue: op) {
    case .open, .create:
        // a=pathLen unused if ptr+b is used: ptr=c-addr, b=u, c=fam
        let path = forthString(ptr: ptr, len: b)
        let fam = c
        let create = (op == FileOp.create.rawValue)
        let (fid, ior) = fa.openFile(path: path, fam: fam, create: create)
        o1?.pointee = fid
        return ior
    case .close:
        return fa.closeFile(a)
    case .read:
        // a=fileid, b=u, ptr=c-addr → o1=u2
        let n = Int(b)
        let buf = ptr?.assumingMemoryBound(to: UInt8.self)
        let (got, ior) = fa.readFile(fileid: a, buffer: buf, length: n)
        o1?.pointee = got
        return ior
    case .write:
        let n = Int(b)
        let buf = ptr.map { UnsafePointer($0.assumingMemoryBound(to: UInt8.self)) }
        return fa.writeFile(fileid: a, buffer: buf, length: n)
    case .readLine:
        let n = Int(b)
        let buf = ptr?.assumingMemoryBound(to: UInt8.self)
        let (u2, flag, ior) = fa.readLine(fileid: a, buffer: buf, maxLen: n)
        o1?.pointee = u2
        o2?.pointee = flag
        return ior
    case .writeLine:
        let n = Int(b)
        let buf = ptr.map { UnsafePointer($0.assumingMemoryBound(to: UInt8.self)) }
        return fa.writeLine(fileid: a, buffer: buf, length: n)
    case .position:
        let (lo, hi, ior) = fa.filePosition(a)
        o1?.pointee = lo
        o2?.pointee = hi
        return ior
    case .size:
        let (lo, hi, ior) = fa.fileSize(a)
        o1?.pointee = lo
        o2?.pointee = hi
        return ior
    case .repos:
        // a=fileid, b=lo, c=hi
        return fa.repositionFile(fileid: a, lo: b, hi: c)
    case .resize:
        return fa.resizeFile(fileid: a, lo: b, hi: c)
    case .delete:
        let path = forthString(ptr: ptr, len: b)
        return fa.deleteFile(path: path)
    case .rename:
        // ptr = c-addr1, b=u1, a unused; need second path — use o3 as temp?
        // Convention: ptr=path1, b=u1, and path2 at a as pointer? 
        // Use: ptr=path1, b=u1, c=path2addr, d=u2
        let p1 = forthString(ptr: ptr, len: b)
        let p2addr = UInt(bitPattern: Int(c))
        let p2 = forthString(ptr: UnsafeMutableRawPointer(bitPattern: p2addr), len: d)
        return fa.renameFile(from: p1, to: p2)
    case .status:
        let path = forthString(ptr: ptr, len: b)
        let (x, ior) = fa.fileStatus(path: path)
        o1?.pointee = x
        return ior
    case .flush:
        return fa.flushFile(a)
    case .none:
        return FileAccess.iorErr
    }
}

private let kernelFromlibTrampoline: @convention(c) () -> Void = {
    FileHost.shared.armFromLibrary()
}

private let kernelFromlibClearTrampoline: @convention(c) () -> Void = {
    FileHost.shared.clearFromLibrary()
}

private let kernelEndIncludeTrampoline: @convention(c) () -> Void = {
    FileHost.shared.endLoadCwdIfNeeded()
}

private let kernelLoadFileTrampoline: @convention(c) (
    UnsafePointer<CChar>?,
    Int,
    UnsafeMutablePointer<UnsafePointer<CChar>?>?,
    UnsafeMutablePointer<Int>?
) -> Int32 = { path, pathLen, outPtr, outLen in
    FileHost.shared.loadFileForKernel(
        path: path,
        pathLen: pathLen,
        outPtr: outPtr,
        outLen: outLen
    )
}

private let kernelResolveKeyTrampoline: @convention(c) (
    UnsafePointer<CChar>?,
    Int,
    UnsafeMutablePointer<CChar>?,
    Int,
    UnsafeMutablePointer<Int>?
) -> Int32 = { path, pathLen, out, outMax, outLen in
    guard let key = FileHost.shared.resolveRegistryKey(path: path, pathLen: pathLen),
          let out, outMax > 0 else { return -1 }
    let bytes = Array(key.utf8)
    let n = min(bytes.count, outMax)
    for i in 0..<n { out[i] = CChar(bitPattern: bytes[i]) }
    outLen?.pointee = n
    return 0
}

private let kernelLastLoadKeyTrampoline: @convention(c) (
    UnsafeMutablePointer<CChar>?,
    Int,
    UnsafeMutablePointer<Int>?
) -> Int32 = { out, outMax, outLen in
    guard let key = FileHost.shared.lastLoadRegistryKey, !key.isEmpty,
          let out, outMax > 0 else { return -1 }
    let bytes = Array(key.utf8)
    let n = min(bytes.count, outMax)
    for i in 0..<n { out[i] = CChar(bitPattern: bytes[i]) }
    outLen?.pointee = n
    return 0
}

private let kernelChdirTrampoline: @convention(c) (UnsafePointer<CChar>?, Int) -> Void = { path, pathLen in
    if path == nil || pathLen == 0 {
        FileHost.shared.presentDirectoryPicker()
    } else {
        FileHost.shared.changeDirectory(spec: String(cString: path!))
    }
}

private let kernelPwdTrampoline: @convention(c) () -> Void = {
    FileHost.shared.printPwd()
}

private let kernelDirTrampoline: @convention(c) (UnsafePointer<CChar>?, Int) -> Void = { path, pathLen in
    if path == nil || pathLen == 0 {
        FileHost.shared.listDirectory(spec: "")
    } else {
        FileHost.shared.listDirectory(spec: String(cString: path!))
    }
}

private let kernelEditTrampoline: @convention(c) (UnsafePointer<CChar>?, Int) -> Void = { path, pathLen in
    FileHost.shared.editForKernel(path: path, pathLen: pathLen)
}

private let kernelAllocTrampoline: @convention(c) (Int, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 = { n, out in
    guard n >= 0, let out else { return -1 }
    let p = UnsafeMutableRawPointer.allocate(byteCount: max(n, 1), alignment: 8)
    p.initializeMemory(as: UInt8.self, repeating: 0, count: max(n, 1))
    out.pointee = p
    return 0
}

private let kernelFreeTrampoline: @convention(c) (UnsafeMutableRawPointer?) -> Int32 = { p in
    guard let p else { return -1 }
    p.deallocate()
    return 0
}

private let kernelBiMulTrampoline: @convention(c) (Int64, Int64, Int64) -> Void = { a, b, r in
    BigIntHost.mul(a: a, b: b, r: r)
}

private let kernelBiDivmodTrampoline: @convention(c) (Int64, Int64, Int64, Int64) -> Void = { num, den, quot, rem in
    BigIntHost.divmod(num: num, den: den, quot: quot, rem: rem)
}

private let kernelBiIsqrtTrampoline: @convention(c) (Int64, Int64) -> Void = { a, r in
    BigIntHost.isqrt(a: a, r: r)
}

private let kernelFloatOpTrampoline: @convention(c) (
    Int64, Int64, Int64, Int64, Int64,
    UnsafeMutableRawPointer?,
    UnsafeMutablePointer<Int64>?,
    UnsafeMutablePointer<Int64>?,
    UnsafeMutablePointer<Int64>?
) -> Int64 = { op, a, b, c, d, ptr, o1, o2, o3 in
    FloatHost.shared.dispatch(op: op, a: a, b: b, c: c, d: d, ptr: ptr, o1: o1, o2: o2, o3: o3)
}

/// Facility terminal: 1=PAGE 2=AT-XY 3=TERMINAL-REFRESH 4=FACILITY-OFF 5=resize
private let kernelFacilityOpTrampoline: @convention(c) (Int64, Int64, Int64) -> Void = { op, a, b in
    let term = FacilityTerminal.shared
    switch op {
    case 1:
        term.page()
    case 2:
        term.atXY(col: Int(a), row: Int(b))
    case 3:
        guard term.isActive else { return }
        term.refreshPending = false
        let screen = term.render()
        let paint: () -> Void = {
            KernelBridge.shared.onTerminalRefresh?(screen)
        }
        if Thread.isMainThread {
            paint()
        } else {
            DispatchQueue.main.async(execute: paint)
        }
    case 4:
        term.deactivate()
    case 5:
        term.resize(cols: Int(a), rows: Int(b))
    default:
        break
    }
}

/// AT-XY? — facility cursor (0-based). Called from kernel CODE `XAT_XY_Q`.
@_cdecl("host_facility_xy")
public func host_facility_xy(
    _ colOut: UnsafeMutablePointer<Int64>?,
    _ rowOut: UnsafeMutablePointer<Int64>?
) {
    let term = FacilityTerminal.shared
    colOut?.pointee = Int64(term.cursorCol)
    rowOut?.pointee = Int64(term.cursorRow)
}

/// (SZ-CLICK) — last mouse click in facility grid (Phase 4a). Clears pending.
/// Returns 0 if none; else bit0=1 valid, bit1=1 if Command held (range-select).
/// Fills col/row (0-based facility cells).
@_cdecl("host_sz_click")
public func host_sz_click(
    _ colOut: UnsafeMutablePointer<Int64>?,
    _ rowOut: UnsafeMutablePointer<Int64>?
) -> Int32 {
    KernelBridge.shared.takeFacilityClick(colOut: colOut, rowOut: rowOut)
}

/// (SZ-CLIP!) ( c-addr u -- ) set host/system clipboard from Forth bytes.
@_cdecl("host_sz_clip_set")
public func host_sz_clip_set(_ ptr: UnsafeRawPointer?, _ len: Int) {
    KernelBridge.shared.setEditorClipboard(ptr: ptr, length: len)
}

/// (SZ-CLIP@) copy host clipboard into buffer; returns length written (≤ max).
@_cdecl("host_sz_clip_get")
public func host_sz_clip_get(_ ptr: UnsafeMutableRawPointer?, _ maxLen: Int) -> Int {
    KernelBridge.shared.getEditorClipboard(into: ptr, maxLength: maxLen)
}

// MARK: - Bridge

final class KernelBridge {
    static let shared = KernelBridge()

    private(set) var isKernelLive = false

    /// Data-stack depth in cells after the last eval (for `ok(n)>` prompt). 0 if kernel not live.
    var dataStackDepth: Int {
        guard isKernelLive else { return 0 }
        return Int(kernel_data_depth())
    }

    /// True while kernel_eval is active (Forth queue and/or main waiting on it).
    /// Guarded by `lock` for safe reads from the keyDown monitor on main.
    private var evaluatingFlag = false
    var isEvaluating: Bool {
        lock.lock()
        defer { lock.unlock() }
        return evaluatingFlag
    }
    private let evalLock = NSLock()

    /// Set when `\S` / `\s` runs on the console SOURCE (SOURCE-ID 0). Host multi-line
    /// paste should stop further lines (TZForth `replBatchStop`). Cleared on read.
    private(set) var replBatchStopRequested = false

    /// Bare SZEDIT / SZ-HOST-REQUEST-OPEN: host should show open panel after evaluate.
    private(set) var szEditorOpenRequested = false

    /// Start directory for the next SZ-EDITOR open panel (e.g. Library after FROMLIB).
    var szEditorOpenStartDirectory: URL?

    /// Facility PAGE/AT-XY grid active (SZ-EDITOR full-screen mode).
    var isFacilityTerminalActive: Bool { FacilityTerminal.shared.isActive }

    var facilityCols: Int { FacilityTerminal.shared.cols }

    /// Pending facility mouse click (col, row), set from ConsoleTextView.
    private var pendingClickCol = 0
    private var pendingClickRow = 0
    private var pendingClickExtend = false
    private var pendingClick = false

    /// Editor clipboard mirrored to NSPasteboard (UTF-8 text).
    private var editorClipboard = Data()

    /// Map a UTF-16 index in the console document to facility col/row and queue SZ-MOUSE.
    /// - Parameter extend: ⌘-click → range select (flag bit1 in (SZ-CLICK)).
    func reportFacilityClick(utf16Index: Int, extend: Bool = false) {
        guard isFacilityTerminalActive, isEvaluating else { return }
        let prefixLen = (facilityPaintPrefix as NSString).length
        guard utf16Index >= prefixLen else { return }
        let local = utf16Index - prefixLen
        let cols = max(1, facilityCols)
        let stride = cols + 1 // row body + '\n'
        guard stride > 0 else { return }
        let row = local / stride
        let col = local % stride
        guard col < cols else { return } // click on the newline gap
        let rows = FacilityTerminal.shared.rows
        guard row >= 0, row < rows else { return }
        lock.lock()
        pendingClickCol = col
        pendingClickRow = row
        pendingClickExtend = extend
        pendingClick = true
        lock.unlock()
        // 25 = SZ-MOUSE in sz-edit.fth
        pushKey(25)
    }

    /// Consume pending click for (SZ-CLICK). Returns 0, or 1, or 3 (1|2 = ⌘-extend).
    fileprivate func takeFacilityClick(
        colOut: UnsafeMutablePointer<Int64>?,
        rowOut: UnsafeMutablePointer<Int64>?
    ) -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        guard pendingClick else {
            colOut?.pointee = 0
            rowOut?.pointee = 0
            return 0
        }
        colOut?.pointee = Int64(pendingClickCol)
        rowOut?.pointee = Int64(pendingClickRow)
        let extend = pendingClickExtend
        pendingClick = false
        pendingClickExtend = false
        return extend ? 3 : 1
    }

    func setEditorClipboard(ptr: UnsafeRawPointer?, length: Int) {
        let n = max(0, length)
        if let ptr, n > 0 {
            editorClipboard = Data(bytes: ptr, count: n)
        } else {
            editorClipboard = Data()
        }
        #if os(macOS)
        let s = String(data: editorClipboard, encoding: .utf8)
            ?? String(data: editorClipboard, encoding: .isoLatin1)
            ?? ""
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
        #endif
    }

    func getEditorClipboard(into ptr: UnsafeMutableRawPointer?, maxLength: Int) -> Int {
        #if os(macOS)
        // Prefer live pasteboard so external Cmd+C works with Cmd+V in editor.
        if let s = NSPasteboard.general.string(forType: .string) {
            editorClipboard = Data(s.utf8)
        }
        #endif
        let n = min(max(0, maxLength), editorClipboard.count)
        if n > 0, let ptr {
            editorClipboard.copyBytes(to: ptr.assumingMemoryBound(to: UInt8.self), count: n)
        }
        return n
    }

    /// ⌘X / ⌘C / ⌘V while SZ-EDITOR KEY is waiting.
    @discardableResult
    func pushEditorClipboardKey(_ which: String) -> Bool {
        guard isEvaluating, isFacilityTerminalActive else { return false }
        switch which {
        case "x": return pushKey(11)  // SZ-CUT
        case "c": return pushKey(22)  // SZ-COPY
        case "v": return pushKey(15)  // SZ-PASTE
        default: return false
        }
    }
    var facilityCursorCol: Int { FacilityTerminal.shared.cursorCol }
    var facilityCursorRow: Int { FacilityTerminal.shared.cursorRow }

    /// Host replaces console body with rendered facility screen (cols×rows + newlines).
    var onTerminalRefresh: ((String) -> Void)?

    /// Optional banner prefix kept above facility paints (e.g. empty while editing).
    var facilityPaintPrefix: String = ""

    var onEmit: ((String) -> Void)? {
        didSet {
            flushPendingEmit()
            FileHost.shared.onMessage = { [weak self] s in
                self?.handleEmitString(s)
            }
        }
    }

    /// Coalesced emit buffer. Kernel TYPE/EMIT fires per character; without
    /// batching, each char schedules a main-queue NSTextView update and the UI
    /// freezes (spinning beach ball) during Hayes / long INCLUDE.
    private var pendingEmit = ""
    /// Raw bytes from kernel EMIT/TYPE. Decoded as UTF-8 into `pendingEmit` on flush
    /// so multi-byte xchars (e.g. U+20AC → E2 82 AC) become one Swift character, not
    /// three Latin-1 code units. Incomplete trailing sequences stay here across flushes.
    private var pendingEmitBytes: [UInt8] = []
    /// True while a main-queue flush of `pendingEmit` is scheduled or running.
    private var emitFlushScheduled = false
    private var keyQueue: [Int32] = []
    private let lock = NSLock()
    /// Wakes a background KEY wait when a key is enqueued (main-thread monitor).
    private let keyAvailable = DispatchSemaphore(value: 0)

    /// Serial queue for `kernel_eval` so the main thread stays free to run AppKit
    /// (KEY/KEY? input). Main waits by pumping `NSApp.nextEvent`.
    private let forthQueue = DispatchQueue(label: "64Forth.kernel")

    /// Local keyDown monitor: delivers KEY/KEY? bytes while `isEvaluating`.
    private var keyDownMonitor: Any?

    private init() {
        kernelHookTarget = self

        // Recover SIGSEGV/SIGBUS into the kernel setjmp (like TZForth soft faults).
        // Must be before any kernel_eval; kernel_init also installs via sigaction.
        Self.installMemoryFaultHandlers()

        installKeyDownMonitor()

        kernel_set_emit(kernelEmitTrampoline)
        kernel_set_emit_buf(kernelEmitBufTrampoline)
        kernel_set_key(kernelKeyTrampoline)
        kernel_set_key_q(kernelKeyQTrampoline)
        kernel_set_time_date(kernelTimeDateTrampoline)
        kernel_set_file_op(kernelFileOpTrampoline)
        kernel_set_fromlib(kernelFromlibTrampoline)
        kernel_set_fromlib_clear(kernelFromlibClearTrampoline)
        kernel_set_end_include(kernelEndIncludeTrampoline)
        kernel_set_load_file(kernelLoadFileTrampoline)
        kernel_set_resolve_key(kernelResolveKeyTrampoline)
        kernel_set_last_load_key(kernelLastLoadKeyTrampoline)
        kernel_set_chdir(kernelChdirTrampoline)
        kernel_set_pwd(kernelPwdTrampoline)
        kernel_set_dir(kernelDirTrampoline)
        kernel_set_edit(kernelEditTrampoline)
        kernel_set_allocate(kernelAllocTrampoline)
        kernel_set_free(kernelFreeTrampoline)
        kernel_set_bi_mul(kernelBiMulTrampoline)
        kernel_set_bi_divmod(kernelBiDivmodTrampoline)
        kernel_set_bi_isqrt(kernelBiIsqrtTrampoline)
        kernel_set_float_op(kernelFloatOpTrampoline)
        kernel_set_facility_op(kernelFacilityOpTrampoline)
        FloatHost.shared.onEmit = { [weak self] s in
            self?.handleEmitString(s)
        }
        FloatHost.shared.reset()
        FacilityTerminal.shared.deactivate()

        FileHost.shared.onMessage = { [weak self] s in
            self?.handleEmitString(s)
        }

        let rc = kernel_init()
        isKernelLive = (rc == 0)
        // Re-install after init in case anything reset dispositions.
        Self.installMemoryFaultHandlers()
        lock.lock()
        pendingEmit = ""
        pendingEmitBytes = []
        lock.unlock()
        FileHost.shared.releaseIncludeBuffers()
        FileHost.shared.endAllLoadCwds()
        FileHost.shared.endAllFromLibraryLoads()
        if !isKernelLive {
            handleEmitString("[64Forth] kernel_init failed (rc=\(rc))\n")
        }
        if let err = BigIntHost.selfTest() {
            handleEmitString("[64Forth] BigIntHost self-test FAILED: \(err)\n")
        }
    }

    /// Expected UTF-8 sequence length from a leading byte (1…4). Continuation/invalid → 1.
    private static func utf8SequenceLength(_ b: UInt8) -> Int {
        if b < 0x80 { return 1 }
        if b & 0xE0 == 0xC0 { return 2 }
        if b & 0xF0 == 0xE0 { return 3 }
        if b & 0xF8 == 0xF0 { return 4 }
        return 1
    }

    /// Move complete UTF-8 sequences from `pendingEmitBytes` into `pendingEmit`.
    /// Leaves an incomplete trailing sequence in the byte buffer. Call with `lock` held.
    private func absorbEmitBytesLocked() {
        guard !pendingEmitBytes.isEmpty else { return }
        var i = 0
        let n = pendingEmitBytes.count
        while i < n {
            let b = pendingEmitBytes[i]
            // Unexpected continuation byte: emit as Latin-1 and resync.
            if b >= 0x80 && (b & 0xC0) == 0x80 {
                if let s = String(bytes: [b], encoding: .isoLatin1) {
                    pendingEmit.append(s)
                }
                i += 1
                continue
            }
            let need = Self.utf8SequenceLength(b)
            if i + need > n {
                break // incomplete trailing sequence — wait for more bytes
            }
            let slice = Array(pendingEmitBytes[i ..< i + need])
            if let s = String(bytes: slice, encoding: .utf8) {
                pendingEmit.append(s)
                i += need
            } else {
                // Invalid sequence: emit first byte as Latin-1 and resync.
                if let s = String(bytes: [b], encoding: .isoLatin1) {
                    pendingEmit.append(s)
                }
                i += 1
            }
        }
        if i > 0 {
            pendingEmitBytes.removeFirst(i)
        }
    }

    /// Drain `pendingEmit` to `onEmit` (main thread). Used at startup and when
    /// installing the sink; long-running eval uses `scheduleEmitFlush`.
    private func flushPendingEmit() {
        lock.lock()
        absorbEmitBytesLocked()
        let pending = pendingEmit
        pendingEmit = ""
        emitFlushScheduled = false
        let sink = onEmit
        lock.unlock()
        guard !pending.isEmpty, let sink else { return }
        if Thread.isMainThread {
            sink(pending)
        } else {
            DispatchQueue.main.async { sink(pending) }
        }
    }

    /// Schedule at most one main-queue drain of the emit buffer. Further chars
    /// only append until that drain runs, so TYPE of a long file is O(chunks)
    /// of UI updates instead of O(characters).
    private func scheduleEmitFlush() {
        lock.lock()
        if emitFlushScheduled {
            lock.unlock()
            return
        }
        emitFlushScheduled = true
        lock.unlock()

        let work = { [weak self] in
            guard let self else { return }
            // Small yield so more TYPE chars can accumulate this timeslice.
            // 0 delay still coalesces a full main-queue turn of emits.
            self.drainEmitBufferToSink()
        }
        if Thread.isMainThread {
            // Defer to next run-loop turn so a burst of main-thread emits still batches.
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    /// Take all pending text and deliver once; re-schedule if more arrived.
    private func drainEmitBufferToSink() {
        lock.lock()
        absorbEmitBytesLocked()
        let chunk = pendingEmit
        pendingEmit = ""
        let sink = onEmit
        // Clear schedule flag before calling sink so concurrent emit can re-schedule.
        emitFlushScheduled = false
        lock.unlock()

        if !chunk.isEmpty, let sink {
            sink(chunk)
        }

        // If more was buffered while we delivered, schedule another drain.
        // Incomplete UTF-8 tails stay in pendingEmitBytes without forcing a spin.
        lock.lock()
        let stillPending = !pendingEmit.isEmpty
        let needAgain = stillPending && !emitFlushScheduled
        if needAgain { emitFlushScheduled = true }
        lock.unlock()
        if needAgain {
            DispatchQueue.main.async { [weak self] in
                self?.drainEmitBufferToSink()
            }
        }
    }

    func statusLine() -> String {
        if isKernelLive {
            return "[64Forth] kernel live — FP · BIG-INTEGER · FROMLIB FLOAD DIR\n"
        }
        return "[64Forth] kernel embed API failed to start\n"
    }

    /// Enqueue a raw key for KEY / KEY?. Only accepted while `kernel_eval` is
    /// running — otherwise normal console typing would fill the queue and
    /// WAIT-KEY / KEY? would return leftover command-line characters.
    ///
    /// Maps AppKit private-use function-key scalars (U+F700…) down to F-PC codes.
    /// Raw U+F703 otherwise becomes `255 AND` → 3 and is silently dropped in SZ-HANDLE-KEY.
    @discardableResult
    func pushKey(_ c: Int32) -> Bool {
        let mapped = Self.mapHostKeyCode(c)
        lock.lock()
        guard evaluatingFlag else {
            lock.unlock()
            return false
        }
        keyQueue.append(mapped)
        lock.unlock()
        keyAvailable.signal()
        return true
    }

    /// NSEvent function-key characters → classic editor codes (no modifiers).
    private static func mapHostKeyCode(_ c: Int32) -> Int32 {
        switch c {
        case 0xF700: return 16  // up
        case 0xF701: return 14  // down
        case 0xF702: return 2   // left
        case 0xF703: return 6   // right
        case 0xF704: return 28  // home (doc) — close enough; real home is 1/28 via keyCode
        case 0xF705: return 29  // end
        case 0xF72C: return 23  // page up
        case 0xF72D: return 24  // page down
        case 0xF728: return 127 // forward delete
        default: return c
        }
    }

    /// Map a keyDown event to an SZ-EDITOR F-PC code while facility is active.
    /// Handles ⌘←/→ find and ⌘PgUp/Dn Hyper; plain arrows / home / etc.
    /// - Returns: nil if this event is not a facility editor key we should steal.
    func facilityEditorKey(from event: NSEvent) -> Int32? {
        #if os(macOS)
        guard event.type == .keyDown else { return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command)
        let shift = flags.contains(.shift)
        let opt = flags.contains(.option)

        let code = Int(event.keyCode)
        // Also recognise function-key character values AppKit puts in `characters`.
        let u: UInt32 = {
            if let s = event.charactersIgnoringModifiers ?? event.characters,
               let v = s.unicodeScalars.first {
                return v.value
            }
            return 0
        }()

        let left = (code == 123) || (u == 0xF702) || (event.specialKey == .leftArrow)
        let right = (code == 124) || (u == 0xF703) || (event.specialKey == .rightArrow)
        let up = (code == 126) || (u == 0xF700) || (event.specialKey == .upArrow)
        let down = (code == 125) || (u == 0xF701) || (event.specialKey == .downArrow)
        let pgUp = (code == 116) || (u == 0xF72C) || (event.specialKey == .pageUp)
        let pgDn = (code == 121) || (u == 0xF72D) || (event.specialKey == .pageDown)
        let home = (code == 115) || (event.specialKey == .home)
        let end = (code == 119) || (event.specialKey == .end)

        // ⌘← / ⌘→ — in-buffer find (not line ends). Ignore ⌘⇧ (selection).
        if cmd && !shift && !opt {
            if left { return 20 }
            if right { return 21 }
            if pgUp { return 26 }
            if pgDn { return 27 }
            if home { return 28 }
            if end { return 29 }
            // ⌘X / ⌘C / ⌘V handled via characters path (not special keys)
        }
        // Plain navigation (no command)
        if !cmd && !opt {
            if left { return 2 }
            if right { return 6 }
            if up { return 16 }
            if down { return 14 }
            if pgUp { return 23 }
            if pgDn { return 24 }
            if home { return shift ? 28 : 1 }
            if end { return shift ? 29 : 5 }
        }
        #endif
        return nil
    }

    /// Consume SZ-EDITOR navigation / find hotkeys before AppKit text-view bindings.
    /// - Returns: true if the event was handled and must not be dispatched further.
    @discardableResult
    func consumeEditorHotKeyIfNeeded(_ event: NSEvent) -> Bool {
        #if os(macOS)
        lock.lock()
        let active = evaluatingFlag
        lock.unlock()
        guard active, FacilityTerminal.shared.isActive else { return false }
        guard let key = facilityEditorKey(from: event) else { return false }
        // Only steal keys we care about for exclusive handling (find / hyper / nav).
        // Always steal: find 20/21, hyper 26/27, and all motion when facility is up
        // so NSTextView never sees them.
        return pushKey(key)
        #else
        return false
        #endif
    }

    /// True while `pumpUIForKeyInput` is on the stack (prevents nested nextEvent crashes).
    private var isPumpingEvents = false

    /// Drop any pending KEY bytes (call at start/end of evaluate).
    func clearKeyQueue() {
        lock.lock()
        keyQueue.removeAll(keepingCapacity: true)
        lock.unlock()
        // Drain stale semaphore permits so KEY does not wake spuriously.
        while keyAvailable.wait(timeout: .now()) == .success {}
    }

    /// Dequeue and dispatch UI events so KEY can receive input while evaluate waits.
    /// Must run on the main thread (classic modal input loop pattern).
    private func pumpUIForKeyInput(seconds: TimeInterval) {
        if !Thread.isMainThread {
            // Avoid deadlock if main is already inside this pump.
            if isPumpingEvents { return }
            DispatchQueue.main.sync {
                self.pumpUIForKeyInput(seconds: seconds)
            }
            return
        }
        // Nested nextEvent/sendEvent re-entry has crashed here under key repeat.
        guard !isPumpingEvents else { return }
        isPumpingEvents = true
        defer { isPumpingEvents = false }

        let until = Date(timeIntervalSinceNow: seconds)
        while Date() < until {
            #if os(macOS)
            var got = false
            autoreleasepool {
                // Single mode only — multi-mode dequeue loops can re-enter sendEvent unsafely.
                if let event = NSApp.nextEvent(
                    matching: .any,
                    until: Date(timeIntervalSinceNow: 0.003),
                    inMode: .default,
                    dequeue: true
                ) {
                    if event.type == .keyDown, self.consumeEditorHotKeyIfNeeded(event) {
                        got = true
                    } else {
                        NSApp.sendEvent(event)
                        got = true
                    }
                }
            }
            #else
            let r = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.005, true)
            let got = (r == .handledSource)
            #endif
            lock.lock()
            let hasKey = !keyQueue.isEmpty
            lock.unlock()
            if hasKey { return }
            if !got && Date() >= until { return }
        }
    }

    /// ANS Facility function-key ids (must match kernel K-* constants / TZForth).
    private enum FacilityFKey {
        static let left = 1, right = 2, up = 3, down = 4
        static let home = 5, end = 6, prior = 7, next = 8
        static let insert = 9, delete = 10
        static let f1 = 11, f2 = 12, f3 = 13, f4 = 14
        static let f5 = 15, f6 = 16, f7 = 17, f8 = 18
        static let f9 = 19, f10 = 20, f11 = 21, f12 = 22
        /// Tagged EKEY event: (2 << 24) | k-id
        static func event(_ id: Int) -> Int32 {
            Int32(bitPattern: UInt32((2 << 24) | (id & 0xFFFFFF)))
        }
    }

    #if os(macOS)
    private func installKeyDownMonitor() {
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            self.lock.lock()
            let active = self.evaluatingFlag
            self.lock.unlock()
            let mods = event.modifierFlags.intersection([.control, .option, .shift, .command])
            let facilityOn = FacilityTerminal.shared.isActive

            // SZ-EDITOR ⌘←/→ find and ⌘PgUp/Dn Hyper (shared with ForthApplication.sendEvent).
            if self.consumeEditorHotKeyIfNeeded(event) {
                return nil
            }

            // Idle console: ⌘PgUp / ⌘PgDn → evaluate HYPER-PREV / HYPER-NEXT
            if mods.contains(.command), !mods.contains(.shift), !active,
               event.keyCode == 116 || event.keyCode == 121 {
                let prev = (event.keyCode == 116)
                self.evaluateHyperNav(prev ? "HYPER-PREV" : "HYPER-NEXT")
                return nil
            }

            // Phase 5: ⌘E → VIEW; ⌘G / ⌘⇧G → find next/prev (letter keys, reliable)
            if mods.contains(.command) {
                let ch = (event.charactersIgnoringModifiers ?? "").lowercased()
                if ch == "e", !mods.contains(.shift) {
                    if active && facilityOn {
                        self.pushKey(18) // SZ-VIEW-UNDER
                        return nil
                    }
                    if !active {
                        self.viewWordUnderConsoleCursor()
                        return nil
                    }
                }
                if ch == "g", active && facilityOn {
                    // ⌘G next, ⌘⇧G previous (same as Tools menu)
                    self.pushKey(mods.contains(.shift) ? 20 : 21)
                    return nil
                }
                // ⌘X / ⌘C / ⌘V — cut / copy / paste in SZ-EDITOR
                if active && facilityOn, !mods.contains(.shift),
                   ch == "x" || ch == "c" || ch == "v" {
                    if self.pushEditorClipboardKey(ch) { return nil }
                }
            }

            guard active else { return event }

            // ⌘S / ⌘W / ⌘Q while facility editor is open.
            // 19 = save, 17 = close editor (S/D if dirty). ⌘Q also marks app-quit-after-close.
            // ⌘Home / ⌘End → start/end of file (Mac-friendly; same as Ctrl-Home/End).
            // ⌘←/→ and ⌘PgUp/Dn are handled above (find / Hyper).
            if mods.contains(.command) {
                if facilityOn {
                    let ch = (event.charactersIgnoringModifiers ?? "").lowercased()
                    if ch == "s" {
                        self.pushKey(19)
                        return nil
                    }
                    if ch == "w" {
                        self.pushKey(17)
                        return nil
                    }
                    if ch == "q" {
                        // Same S/D prompt as close; cancel stays in editor and does not quit app.
                        self.requestQuitAppAfterEditorClose()
                        self.pushKey(17)
                        return nil
                    }
                    if ch == "x" || ch == "c" || ch == "v" {
                        if self.pushEditorClipboardKey(ch) { return nil }
                    }
                    switch event.keyCode {
                    case 115: // Home
                        self.pushKey(28) // SZ-HOME-FILE
                        return nil
                    case 119: // End
                        self.pushKey(29) // SZ-END-FILE
                        return nil
                    default:
                        break
                    }
                }
                // Other ⌘ shortcuts (menus, etc.) pass through.
                return event
            }

            // macOS Delete (backspace) is keyCode 51; its character is often DEL (127).
            // SZ-EDITOR treats 8 as backspace and 127 as forward-delete.
            if event.keyCode == 51 {
                self.pushKey(8) // BS
                return nil
            }

            // Ctrl-Home / Ctrl-End → start/end of file (sz-edit: 28 / 29).
            // Plain Home/End → start/end of line (1 / 5) via F-PC mapping below.
            // Also accept while KEY is waiting even if facility flag races briefly.
            if mods.contains(.control) {
                switch event.keyCode {
                case 115: // Home
                    self.pushKey(28) // SZ-HOME-FILE
                    return nil
                case 119: // End
                    self.pushKey(29) // SZ-END-FILE
                    return nil
                default:
                    break
                }
            }

            // Facility Ext: map arrows / navigation / F-keys to tagged EKEY events.
            // KEY skips tag-2 events; EKEY returns them for EKEY>FKEY.
            // Also push classic F-PC editor codes so SZ-HANDLE-KEY works.
            if let fkid = Self.facilityFKeyId(for: event) {
                if facilityOn,
                   let pc = Self.editorPCKeyCode(forFacilityId: fkid) {
                    self.pushKey(pc)
                } else {
                    self.pushKey(FacilityFKey.event(fkid))
                }
                return nil
            }

            let chars = event.charactersIgnoringModifiers ?? event.characters
            if let chars, !chars.isEmpty {
                for scalar in chars.unicodeScalars {
                    let raw = Int32(bitPattern: UInt32(scalar.value))
                    // Private-use function keys (arrows etc.): already handled above when
                    // facility is on; never push raw U+F70x (255 AND → silent no-op).
                    if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                        continue
                    }
                    var v = raw
                    // Normalize Return/Enter to LF (10).
                    if v == 13 { v = 10 }
                    // Mac backspace character is often 127 — map to BS when facility editor active
                    if v == 127 && FacilityTerminal.shared.isActive { v = 8 }
                    if v > 0 && v < 0x11_0000 {
                        self.pushKey(v)
                    }
                }
                return nil // consume — do not insert into the console or re-submit
            }
            // Consume other keys while evaluating so they do not edit the console.
            return nil
        }
    }

    /// Map NSEvent special keys → K-* id, or nil for normal character keys.
    private static func facilityFKeyId(for event: NSEvent) -> Int? {
        // Prefer keyCode for arrows / nav (charactersIgnoringModifiers may be empty).
        switch event.keyCode {
        case 123: return FacilityFKey.left
        case 124: return FacilityFKey.right
        case 125: return FacilityFKey.down
        case 126: return FacilityFKey.up
        case 115: return FacilityFKey.home
        case 119: return FacilityFKey.end
        case 116: return FacilityFKey.prior   // page up
        case 121: return FacilityFKey.next    // page down
        case 114: return FacilityFKey.insert
        case 117: return FacilityFKey.delete  // forward delete
        case 122: return FacilityFKey.f1
        case 120: return FacilityFKey.f2
        case 99:  return FacilityFKey.f3
        case 118: return FacilityFKey.f4
        case 96:  return FacilityFKey.f5
        case 97:  return FacilityFKey.f6
        case 98:  return FacilityFKey.f7
        case 100: return FacilityFKey.f8
        case 101: return FacilityFKey.f9
        case 109: return FacilityFKey.f10
        case 103: return FacilityFKey.f11
        case 111: return FacilityFKey.f12
        default: break
        }
        return nil
    }
    #else
    // iOS: keys arrive via ConsoleTextView / SwiftUI (pushKey), not NSEvent.
    private func installKeyDownMonitor() {}
    #endif

    /// Classic F-PC codes used by sz-edit.fth (SZ-LEFT=2, SZ-RIGHT=6, …).
    private static func editorPCKeyCode(forFacilityId id: Int) -> Int32? {
        switch id {
        case FacilityFKey.left: return 2
        case FacilityFKey.right: return 6
        case FacilityFKey.down: return 14
        case FacilityFKey.up: return 16
        case FacilityFKey.home: return 1
        case FacilityFKey.end: return 5
        case FacilityFKey.prior: return 23
        case FacilityFKey.next: return 24
        case FacilityFKey.delete: return 127
        default: return nil
        }
    }

    /// Phase 5: run HYPER-NEXT / HYPER-PREV from idle console (⌘PgDn / ⌘PgUp).
    private func evaluateHyperNav(_ word: String) {
        // Avoid re-entrancy if a long evaluate is already running.
        lock.lock()
        let busy = evaluatingFlag
        lock.unlock()
        guard !busy else { return }
        DispatchQueue.main.async { [weak self] in
            _ = self?.evaluate(word)
        }
    }

    /// Phase 5: ⌘E — ask ConsoleView to VIEW the Forth token under the caret.
    private func viewWordUnderConsoleCursor() {
        NotificationCenter.default.post(name: .viewWordUnderCursor, object: nil)
    }

    /// Clear the sticky multi-line paste stop (call before a paste batch if needed).
    func clearReplBatchStop() {
        replBatchStopRequested = false
        if isKernelLive {
            _ = kernel_take_repl_batch_stop()
        }
    }

    /// Interpret one console line. Not re-entrant (returns −3 if busy).
    /// After eval, `replBatchStopRequested` is true if `\S` ran on the console line
    /// (SOURCE-ID 0); multi-line paste should stop further lines.
    ///
    /// On the main thread, the kernel runs on `forthQueue` while main pumps AppKit
    /// events so KEY/KEY? can receive keystrokes (blocking eval on main freezes input).
    /// Does not print kernel "ok" — embed mode leaves prompts to the host (ANS EVALUATE
    /// has no required ok output).
    @discardableResult
    func evaluate(_ line: String) -> Int32 {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return 0 }

        guard isKernelLive else {
            return evaluateStub(t)
        }

        // Kernel VM is single-threaded; reject overlapping evaluate (e.g. paste storm).
        guard evalLock.try() else {
            handleEmitString("(busy — finish current command first)\n")
            return -3
        }

        // Main thread: run kernel off-main so AppKit can deliver keyDown.
        if Thread.isMainThread {
            var status: Int32 = 0
            let done = DispatchSemaphore(value: 0)
            forthQueue.async {
                status = self.runKernelEval(t)
                done.signal()
            }
            // Pump UI until the kernel finishes (KEY waits use keyAvailable + queue).
            // Service the main GCD queue so batched emit flushes, scroll events,
            // and off-main FLOAD/CHDIR panels can run — keeps the console live.
            while done.wait(timeout: .now() + 0.016) == .timedOut {
                // Drain all ready main sources (emit batches, SwiftUI layout).
                var more = true
                while more {
                    let r = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0, true)
                    more = (r == .handledSource)
                }
                self.pumpUIForKeyInput(seconds: 0.012)
            }
            // Final emit drain (anything still buffered after last TYPE).
            self.drainEmitBufferToSink()
            evalLock.unlock()
            return status
        }

        let status = runKernelEval(t)
        evalLock.unlock()
        // Off-main callers: still surface open request (ConsoleView handles on main).
        return status
    }

    /// Clear open-panel sticky after ConsoleView services it.
    func takeSzEditorOpenRequest() -> Bool {
        let v = szEditorOpenRequested
        szEditorOpenRequested = false
        return v
    }

    /// ⌘Q while editor open: after SZ-EDIT-LOOP ends, terminate the app.
    func requestQuitAppAfterEditorClose() {
        kernel_set_sz_app_quit()
    }

    func clearQuitAppAfterEditorClose() {
        kernel_clear_sz_app_quit()
    }

    /// If true after an evaluate that left the facility editor, host should quit.
    var quitAppAfterEditorClosePending: Bool {
        kernel_sz_app_quit_pending() != 0
    }

    /// Open a path in SZ-EDITOR (EDITOR vocabulary). Path is absolute or relative.
    @discardableResult
    func openInSzEditor(path: String) -> Int32 {
        // Escape for S" … " — use a counted path via evaluate of SET-PATH + OPEN-EDIT
        let escaped = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        // Stage path then enter editor (words live in EDITOR wordlist)
        let line = "ONLY FORTH ALSO EDITOR S\" \(escaped)\" SZ-HOST-SET-PATH SZ-HOST-OPEN-EDIT ONLY FORTH"
        return evaluate(line)
    }

    /// Body of evaluate on the Forth serial queue (or any non-reentrant caller).
    private func runKernelEval(_ t: String) -> Int32 {
        lock.lock()
        evaluatingFlag = true
        lock.unlock()
        clearKeyQueue()
        defer {
            clearKeyQueue()
            lock.lock()
            evaluatingFlag = false
            lock.unlock()
        }

        var status: Int32 = 0
        t.withCString { ptr in
            let n = strlen(ptr)
            status = kernel_eval(ptr, n)
        }

        // \S on console SOURCE → host should stop remaining multi-line paste lines.
        if kernel_take_repl_batch_stop() != 0 {
            replBatchStopRequested = true
        }

        // Bare SZEDIT / (SZ-OPEN-REQ): open panel after this evaluate returns.
        if kernel_take_sz_editor_open() != 0 {
            szEditorOpenRequested = true
            // FROMLIB SZEDIT (no path) → panel starts at Resources/Library
            if FileHost.shared.fromLibraryArmed, let lib = FileHost.shared.libraryURL {
                FileHost.shared.clearFromLibrary()
                szEditorOpenStartDirectory = lib
            } else {
                szEditorOpenStartDirectory = nil
            }
        }

        if status == -1 {
            if kernel_take_fault_flag() != 0 {
                handleEmitString("memory access error\n")
            }
        }

        FileHost.shared.releaseIncludeBuffers()
        FileHost.shared.endAllLoadCwds()
        FileHost.shared.endAllFromLibraryLoads()
        if FileHost.shared.fromLibraryArmed {
            FileHost.shared.clearFromLibrary()
        }

        // Ensure last output reaches the console before evaluate returns.
        // Off-main: schedule drain; main wait loop also drains after join.
        scheduleEmitFlush()

        // ⌘Q while editor was open: quit app only after the editor session ended.
        if quitAppAfterEditorClosePending && !FacilityTerminal.shared.isActive {
            clearQuitAppAfterEditorClose()
            #if os(macOS)
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
            #endif
        }

        if status == 1 {
            #if os(macOS)
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
            #endif
        }
        return status
    }

    // MARK: - Memory fault recovery (SIGSEGV / SIGBUS → soft restart)

    /// C handler trampoline: must not capture Swift context.
    private static let memoryFaultTrampoline: @convention(c) (Int32) -> Void = { sig in
        kernel_on_memory_fault(sig)
    }

    /// Install/replace Unix signal handlers so bad Forth pointers recover instead of
    /// killing the app. Under Xcode, pair with `.lldbinit-64forth` so LLDB passes
    /// the signal through (otherwise the debugger stops on EXC_BAD_ACCESS first).
    private static func installMemoryFaultHandlers() {
        var action = sigaction()
        // Darwin: handler in the union at offset 0
        action.__sigaction_u.__sa_handler = memoryFaultTrampoline
        action.sa_flags = Int32(SA_NODEFER)
        sigemptyset(&action.sa_mask)
        sigaction(SIGSEGV, &action, nil)
        sigaction(SIGBUS, &action, nil)
    }

    @discardableResult
    func loadFile(named name: String) -> Int32 {
        let spec = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spec.isEmpty else {
            return evaluate("FLOAD")
        }
        return evaluate("INCLUDE \(spec)")
    }

    /// Phase 4 AutoLoad boot.
    @discardableResult
    func runAutoLoadIfPresent() -> Bool {
        guard isKernelLive else { return false }
        guard let autoURL = FileHost.shared.autoLoadFileURL else { return false }

        let autoDir = autoURL.deletingLastPathComponent()
        let host = FileHost.shared
        let savedLogical = host.logicalCurrentDirectory
        let savedProcess = FileManager.default.currentDirectoryPath

        host.logicalCurrentDirectory = autoDir.path
        _ = FileManager.default.changeCurrentDirectoryPath(autoDir.path)

        // Embed kernel_eval never prints "ok"; ConsoleView prints ok(n)> once after boot.
        // SEE/HELP are defined in the kernel bootstrap (forth_init_str).
        _ = evaluate("INCLUDE \(autoURL.path)")
        _ = evaluate("MAIN")

        host.logicalCurrentDirectory = savedLogical
        _ = FileManager.default.changeCurrentDirectoryPath(savedProcess)
        host.endAllLoadCwds()
        host.endAllFromLibraryLoads()
        host.clearFromLibrary()

        return true
    }

    @discardableResult
    func evaluateStub(_ line: String) -> Int32 {
        handleEmitString("ok  (stub: kernel not live — '\(line)')\n")
        return 0
    }

    // MARK: - Hooks

    fileprivate func handleEmitFromKernel(_ c: Int32) {
        // Facility terminal (PAGE/AT-XY mode): paint into cell grid, not console stream.
        if FacilityTerminal.shared.isActive {
            FacilityTerminal.shared.emit(UInt8(truncatingIfNeeded: c))
            return
        }
        // Buffer as raw bytes (not Latin-1 one-byte Strings) so UTF-8 multi-byte
        // sequences stay intact across EMIT calls. Absorb complete sequences into
        // pendingEmit immediately so order matches interleaved TYPE/emit_buf
        // (handleEmitString). Without that, CR (byte path) piles up in
        // pendingEmitBytes while TYPE appends to pendingEmit; flush then dumps
        // all newlines at the end → one long line + trailing blank lines.
        let u = UInt8(truncatingIfNeeded: c)
        lock.lock()
        pendingEmitBytes.append(u)
        absorbEmitBytesLocked()
        let hasSink = (onEmit != nil)
        lock.unlock()
        if hasSink {
            scheduleEmitFlush()
        }
    }

    /// Bulk emit from kernel TYPE/XEMIT (already copied out of kernel memory).
    fileprivate func handleEmitBytes(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        if FacilityTerminal.shared.isActive {
            for b in bytes {
                FacilityTerminal.shared.emit(b)
            }
            return
        }
        let s = String(bytes: bytes, encoding: .utf8)
            ?? String(bytes: bytes, encoding: .isoLatin1)
            ?? ""
        handleEmitString(s)
    }

    fileprivate func handleKeyFromKernel() -> Int32 {
        // Called from the Forth queue during kernel_eval. Main is pumping events;
        // wait on keyAvailable (signaled by pushKey from the keyDown monitor).
        let deadline = Date().addingTimeInterval(120)
        while true {
            lock.lock()
            if !keyQueue.isEmpty {
                let c = keyQueue.removeFirst()
                lock.unlock()
                return c
            }
            lock.unlock()
            if Date() > deadline { return -1 }
            // Short wait; main thread's evaluate loop keeps AppKit alive.
            _ = keyAvailable.wait(timeout: .now() + 0.05)
        }
    }

    /// KEY?: non-blocking peek. Main evaluate loop pumps AppKit; we sleep briefly
    /// when empty so BEGIN KEY? UNTIL does not burn a core and starves nothing.
    fileprivate func handleKeyAvailableFromKernel() -> Int32 {
        if Thread.isMainThread {
            pumpUIForKeyInput(seconds: 0.01)
        }
        lock.lock()
        let ready = !keyQueue.isEmpty
        lock.unlock()
        if !ready {
            Thread.sleep(forTimeInterval: 0.01)
        }
        return ready ? 1 : 0
    }

    fileprivate func handleEmitString(_ s: String) {
        guard !s.isEmpty else { return }
        if FacilityTerminal.shared.isActive {
            for b in s.utf8 {
                FacilityTerminal.shared.emit(b)
            }
            return
        }
        lock.lock()
        // Drain any complete UTF-8 already in the byte buffer before this chunk
        // so CR/EMIT bytes stay in front of TYPE/emit_buf text.
        absorbEmitBytesLocked()
        pendingEmit.append(s)
        let hasSink = (onEmit != nil)
        lock.unlock()
        // No sink yet (early boot): leave in pendingEmit until onEmit is set.
        if hasSink {
            scheduleEmitFlush()
        }
    }
}
