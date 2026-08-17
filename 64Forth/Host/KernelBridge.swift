//
//  KernelBridge.swift
//  64Forth
//
//  Public domain.
//
//  Swift ↔ PickleForth assembly kernel.
//  Host words: FROMLIB, FLOAD/INCLUDE, CHDIR, PWD, DIR, SYSTEM (TZForth-style).
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

@_silgen_name("kernel_set_system")
private func kernel_set_system(
    _ fn: (@convention(c) (UnsafePointer<CChar>?, Int) -> Int64)?
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

/// SYSTEM ( c-addr u -- n ): run /bin/sh -c with the length-bounded command string.
private let kernelSystemTrampoline: @convention(c) (UnsafePointer<CChar>?, Int) -> Int64 = { cmd, cmdLen in
    guard let cmd, cmdLen > 0 else {
        FileHost.shared.onMessage?("SYSTEM: empty command\n")
        return -1
    }
    let n = cmdLen
    let bytes = UnsafeBufferPointer(start: UnsafeRawPointer(cmd).assumingMemoryBound(to: UInt8.self), count: n)
    let s = String(decoding: bytes, as: UTF8.self)
    return Int64(FileHost.shared.runSystemCommand(s))
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

/// Facility terminal: 1=PAGE 2=AT-XY 3=TERMINAL-REFRESH 4=FACILITY-OFF 5=resize 6=reverse
/// 7=console-emit  8=command-line done  9=CLS (clear host console)
private let kernelFacilityOpTrampoline: @convention(c) (Int64, Int64, Int64) -> Void = { op, a, b in
    let term = FacilityTerminal.shared
    switch op {
    case 1:
        // PAGE: clear facility grid. Bare `PAGE` from the idle console must not
        // leave facility active (that freezes caret/selection with no KEY loop).
        // Only schedule the orphan check on inactive→active. SZ-REDRAW also uses
        // PAGE while the editor is live; rescheduling there races TERMINAL-REFRESH
        // during splitter/window resize and falsely tears down the split UI.
        let wasActive = term.isActive
        term.page()
        if !wasActive {
            KernelBridge.shared.scheduleOrphanFacilityPageCheck()
        }
    case 2:
        term.atXY(col: Int(a), row: Int(b))
    case 3:
        guard term.isActive else { return }
        term.refreshPending = false
        term.endGridPaint()
        KernelBridge.shared.noteFacilityRefreshSeen()
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
        // Leave facility mode and restore the pre-editor console (snapshot held
        // by ConsoleView). Without this, the last SZ-EDITOR frame stays on screen
        // until the user presses Return — exit feels broken.
        term.deactivate()
        term.endGridPaint()
        KernelBridge.shared.setFacilityEmitBypass(false)
        KernelBridge.shared.noteFacilityRefreshSeen()
        let exit: () -> Void = {
            KernelBridge.shared.onFacilityExit?()
        }
        if Thread.isMainThread {
            exit()
        } else {
            DispatchQueue.main.async(execute: exit)
        }
    case 5:
        term.resize(cols: Int(a), rows: Int(b))
    case 6:
        // FACILITY-REV ( f -- ): nonzero → reverse-video on subsequent EMITs
        term.setReverse(a != 0)
    case 7:
        // (SZ-CONSOLE-EMIT) ( f -- ): nonzero → TYPE/EMIT go to host command pane
        KernelBridge.shared.setFacilityEmitBypass(a != 0)
    case 8:
        // (SZ-CMD-DONE) ( -- ): command-pane line finished; host appends ok(n)> prompt
        KernelBridge.shared.notifyCommandLineDone()
    case 9:
        // CLS ( -- ): clear host console + ok prompt (not SZ-EDITOR exit)
        let clear: () -> Void = {
            KernelBridge.shared.onHostClearConsole?()
        }
        if Thread.isMainThread {
            clear()
        } else {
            DispatchQueue.main.async(execute: clear)
        }
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

/// (SZ-CLICK) — last mouse event in facility grid. Clears one pending event.
/// Returns 0 if none; else:
///   bit0    = valid
///   bit1    = Command held (⌘-click VIEW)
///   bits2–3 = phase: 0=down, 1=drag, 2=up
///   bit4    = Shift held (extend selection)
///   bit5    = double-click (space-delimited word)
///   bit6    = triple-click (whole logical line)
/// Fills col/row (0-based facility cells).
@_cdecl("host_sz_click")
public func host_sz_click(
    _ colOut: UnsafeMutablePointer<Int64>?,
    _ rowOut: UnsafeMutablePointer<Int64>?
) -> Int32 {
    KernelBridge.shared.takeFacilityClick(colOut: colOut, rowOut: rowOut)
}

/// (SZ-VIEW-CELLS) — preferred facility grid size from the console window.
/// cols/rows in monospaced cells; rows already reserve 5 lines for the command area.
@_cdecl("host_sz_view_cells")
public func host_sz_view_cells(
    _ colsOut: UnsafeMutablePointer<Int64>?,
    _ rowsOut: UnsafeMutablePointer<Int64>?
) {
    let cells = KernelBridge.shared.preferredFacilityCells()
    colsOut?.pointee = Int64(cells.cols)
    rowsOut?.pointee = Int64(cells.rows)
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

/// (SZ-PATH@) ( c-addr max -- u ) take host-staged open path (Cmd-O while KEY waits).
@_cdecl("host_sz_path_get")
public func host_sz_path_get(_ ptr: UnsafeMutableRawPointer?, _ maxLen: Int) -> Int {
    KernelBridge.shared.takeStagedEditorOpenPath(into: ptr, maxLength: maxLen)
}

/// (SZ-CMD@) ( c-addr max -- u ) take host-staged console command line (split pane).
@_cdecl("host_sz_cmd_get")
public func host_sz_cmd_get(_ ptr: UnsafeMutableRawPointer?, _ maxLen: Int) -> Int {
    KernelBridge.shared.takeStagedCommandLine(into: ptr, maxLength: maxLen)
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

    /// Monospaced cell metrics for SZ-EDITOR sizing (updated from console layout).
    /// Command-area reserve below facility paint.
    /// Phase 1 split: the lower scrollable command pane is a separate view, so the
    /// facility grid may use the full upper pane (0 reserved rows in cell math).
    static let facilityCommandAreaLines = 0
    /// Extra columns relative to measured fit. +10 widens overall by ~12 vs the
    /// prior −2 setting (user: still ~12 cols too narrow with side panel).
    private static let facilityColAdjust = 10
    /// Rows subtracted from measured pane height. 0 = fit pane; +1 leaves a
    /// little air above the splitter (user: one monospaced cell of gap).
    private static let facilityRowSafety = 0
    /// Right-hand file-list panel content width (filename.ext); +1 outer '|' in Forth.
    static let facilitySidePanelCols = 16
    private var consoleVisibleSize = CGSize(width: 640, height: 400)
    /// Usable content area after insets/padding/scroller (preferred for cell math).
    private var consoleUsableSize = CGSize(width: 640, height: 400)
    private var consoleCellWidth: CGFloat = 8
    private var consoleLineHeight: CGFloat = 16
    private var lastPreferredFacilityCols = 0
    private var lastPreferredFacilityRows = 0

    /// Preferred facility grid (cols × rows) from the visible console, reserving
    /// `facilityCommandAreaLines` rows below the editor for command entry.
    func preferredFacilityCells() -> (cols: Int, rows: Int) {
        // Ceil cell size so we never over-count columns/rows (under-size → wrap).
        let cw = max(consoleCellWidth, 1)
        let lh = max(consoleLineHeight, 1)
        let usable = consoleUsableSize.width > 1 ? consoleUsableSize : consoleVisibleSize
        let cols = max(24, Int(floor(usable.width / cw)) + Self.facilityColAdjust)
        let totalRows = max(1, Int(floor(usable.height / lh)))
        let rows = max(
            10,
            totalRows - Self.facilityCommandAreaLines - Self.facilityRowSafety
        )
        return (cols, rows)
    }

    /// Called from the console scroll view when its visible area or font changes.
    /// Wakes SZ-EDITOR (KEY) when the preferred cell grid changes so REDRAW can sync.
    func updateConsoleVisibleSize(_ size: CGSize, font: Any?) {
        #if os(macOS)
        // Prefer full metrics from the live text view when available.
        if let font = font as? NSFont {
            updateConsoleMetrics(
                visibleSize: size,
                font: font,
                textContainerInset: NSSize(width: 0, height: 0),
                lineFragmentPadding: 5,
                scrollerWidth: 0
            )
            return
        }
        #endif
        guard size.width > 1, size.height > 1 else { return }
        consoleVisibleSize = size
        consoleUsableSize = size
        applyPreferredFacilityCellsIfChanged()
    }

    #if os(macOS)
    /// Accurate metrics from the live `NSScrollView` / `NSTextView` (insets, padding, scroller).
    func updateConsoleMetrics(scrollView: NSScrollView, textView: NSTextView) {
        let clip = scrollView.contentView.bounds.size
        guard clip.width > 1, clip.height > 1 else { return }
        let font = textView.font
            ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let pad = textView.textContainer?.lineFragmentPadding ?? 5
        // Reserve vertical scroller width even when overlay (content can still clip).
        let scrollerW = NSScroller.scrollerWidth(
            for: scrollView.verticalScroller?.controlSize ?? .regular,
            scrollerStyle: scrollView.scrollerStyle
        )
        updateConsoleMetrics(
            visibleSize: clip,
            font: font,
            textContainerInset: textView.textContainerInset,
            lineFragmentPadding: pad,
            scrollerWidth: scrollerW
        )
    }

    private func updateConsoleMetrics(
        visibleSize: CGSize,
        font: NSFont,
        textContainerInset: NSSize,
        lineFragmentPadding: CGFloat,
        scrollerWidth: CGFloat
    ) {
        guard visibleSize.width > 1, visibleSize.height > 1 else { return }
        consoleVisibleSize = visibleSize

        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        // Ceil so floor(usable/cell) never overshoots real glyph width/height.
        let charW = ceil(max(1, ("M" as NSString).size(withAttributes: attrs).width))
        let lm = NSLayoutManager()
        let lineH = ceil(max(1, lm.defaultLineHeight(for: font)))
        consoleCellWidth = charW
        consoleLineHeight = lineH

        // Usable text-container width/height (must match what NSTextView can show
        // without wrapping a full facility row of `cols` monospaced glyphs).
        let usableW = visibleSize.width
            - textContainerInset.width * 2
            - lineFragmentPadding * 2
            - scrollerWidth
            - 4 // pt safety for fractional layout / anti-alias
        let usableH = visibleSize.height
            - textContainerInset.height * 2
            - 4
        consoleUsableSize = CGSize(width: max(1, usableW), height: max(1, usableH))
        applyPreferredFacilityCellsIfChanged()
    }
    #endif

    private func applyPreferredFacilityCellsIfChanged() {
        let cells = preferredFacilityCells()
        let changed = cells.cols != lastPreferredFacilityCols
            || cells.rows != lastPreferredFacilityRows
        guard changed else { return }
        lastPreferredFacilityCols = cells.cols
        lastPreferredFacilityRows = cells.rows
        // Wake the editor so SZ-REDRAW → SZ-SYNC-SIZE can apply the new size.
        // Must run even while isPumpingEvents: during KEY wait the main thread
        // is almost always inside pumpUIForKeyInput, and skipping the wake left
        // lastPreferred updated but the editor never re-synced (window resize
        // appeared broken). pushKey(0) is a no-op in SZ-HANDLE-KEY then REDRAW.
        // The `guard changed` above prevents a layout↔wake feedback loop.
        if isEvaluating, isFacilityTerminalActive {
            if Thread.isMainThread, isPumpingEvents {
                // Defer one turn so we finish the current layout/event before KEY
                // returns and REDRAW runs (avoids nested facility paint mid-layout).
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard self.isEvaluating, self.isFacilityTerminalActive else { return }
                    _ = self.pushKey(0)
                }
            } else {
                _ = pushKey(0)
            }
        }
    }

    /// Facility mouse event phases for (SZ-CLICK) flag bits 2–3.
    enum FacilityMousePhase: Int {
        case down = 0
        case drag = 1
        case up = 2
    }

    private struct FacilityMouseEvent {
        var col: Int
        var row: Int
        /// ⌘ — VIEW on down.
        var command: Bool
        /// ⇧ — extend selection from anchor to this cell.
        var shift: Bool
        /// Double-click — select space-delimited word.
        var doubleClick: Bool
        /// Triple-click — select whole logical line.
        var tripleClick: Bool
        var phase: FacilityMousePhase
    }

    /// Pending facility mouse events (down / drag / up). Drag coalesces.
    private var pendingMouseEvents: [FacilityMouseEvent] = []
    /// True while a SZ-MOUSE key is in the KEY queue for an unconsumed event.
    private var facilityMouseKeyQueued = false

    /// Editor clipboard mirrored to NSPasteboard (UTF-8 text).
    private var editorClipboard = Data()

    /// Fractional line accumulator for trackpad momentum (facility scroll).
    private var facilityScrollAccum: CGFloat = 0

    /// System Settings → Mouse/Trackpad → “Scroll direction: Natural”.
    /// `true` = natural (content follows finger); default when the key is unset.
    private var systemNaturalScrolling: Bool {
        #if os(macOS)
        let key = "com.apple.swipescrolldirection"
        if let v = UserDefaults.standard.object(forKey: key) as? Bool { return v }
        if let v = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[key] as? Bool {
            return v
        }
        return true
        #else
        return true
        #endif
    }

    /// Map scroll-wheel / trackpad into SZ-EDITOR view scroll (keys 9 / 12).
    /// Does not move the caret — only SZ-TOP (see SZ-SCROLL-UP/DOWN).
    /// Direction follows the system Natural scrolling preference via raw `deltaY`
    /// plus `systemNaturalScrolling` (not a second invert of `scrollingDeltaY`).
    func reportFacilityScroll(_ event: NSEvent) {
        guard isFacilityTerminalActive, isEvaluating else { return }
        #if os(macOS)
        // Device-oriented delta (not pre-flipped). Positive = wheel/finger “up”
        // on the device in the traditional sense.
        var dy = event.deltaY
        // Line-based mice report ~1 per notch; precise trackpads report points.
        if !event.hasPreciseScrollingDeltas {
            dy *= 16
        }
        // Natural ON: flip device delta so content follows the finger (same as
        // AppKit scrollingDeltaY). Natural OFF: keep traditional device sense.
        if systemNaturalScrolling {
            dy = -dy
        }
        // Positive dy → earlier lines (scroll “up” the file). Flipped once from
        // an earlier mapping that felt inverted relative to Finder/TextEdit.
        facilityScrollAccum -= dy
        let lineH: CGFloat = 14
        // Cap lines per event so KEY queue is not flooded by momentum.
        var steps = 0
        let maxSteps = 8
        while facilityScrollAccum >= lineH, steps < maxSteps {
            facilityScrollAccum -= lineH
            // View toward end of file (later lines)
            pushKey(7) // SZ-VSCROLL-DN (not ASCII 12 — Form Feed)
            steps += 1
        }
        while facilityScrollAccum <= -lineH, steps < maxSteps {
            facilityScrollAccum += lineH
            // View toward start of file (earlier lines)
            pushKey(3) // SZ-VSCROLL-UP (not ASCII 9 — Tab)
            steps += 1
        }
        if steps >= maxSteps {
            facilityScrollAccum = 0
        }
        #endif
    }

    /// Map a UTF-16 index in the console document to facility col/row, or nil.
    func facilityCell(fromUTF16 utf16Index: Int) -> (col: Int, row: Int)? {
        guard isFacilityTerminalActive else { return nil }
        let prefixLen = (facilityPaintPrefix as NSString).length
        guard utf16Index >= prefixLen else { return nil }
        let local = utf16Index - prefixLen
        let cols = max(1, facilityCols)
        let stride = cols + 1 // row body + '\n'
        guard stride > 0 else { return nil }
        let row = local / stride
        let col = local % stride
        guard col < cols else { return nil } // click on the newline gap
        let rows = FacilityTerminal.shared.rows
        guard row >= 0, row < rows else { return nil }
        return (col, row)
    }

    /// Clamp a UTF-16 index into any facility cell (including status/find chrome).
    /// Unlike `facilityTextCellClamped`, does **not** force the text-body band.
    func facilityGridCellClamped(fromUTF16 utf16Index: Int) -> (col: Int, row: Int)? {
        guard isFacilityTerminalActive else { return nil }
        let cols = max(1, facilityCols)
        let rows = max(1, FacilityTerminal.shared.rows)
        let prefixLen = (facilityPaintPrefix as NSString).length
        let local = max(0, utf16Index - prefixLen)
        let stride = cols + 1
        var row = local / stride
        var col = local % stride
        if col >= cols { col = cols - 1 }
        row = min(max(0, row), rows - 1)
        col = min(max(0, col), cols - 1)
        return (col, row)
    }

    /// Text-body band in facility cells (matches `sz-screen.fth` chrome).
    /// Used for scroll-on-drag edge zones.
    struct FacilityTextBand {
        var textTop: Int
        var textBot: Int
        var textLeft: Int
        /// Last column of the editable text body (inclusive).
        var textRight: Int
    }

    /// Must match Forth: SZ-TEXT-TOP=3, SZ-TEXT-LEFT=7, SZ-SIDE-WIDTH=28,
    /// facility rows = textHeight+7 → TEXT-BOT = rows-5
    /// (outer top, status, col-top, …, col-bot, help1, help2, outer bot).
    var facilityTextBand: FacilityTextBand {
        let rows = max(1, FacilityTerminal.shared.rows)
        let cols = max(1, FacilityTerminal.shared.cols)
        let side = 28
        let textTop = 3
        let textBot = max(textTop, rows - 5)
        let textLeft = 7
        // Outer '│' at cols-1; side panel is `side` cols; editor right '│' before side.
        let textRight = max(textLeft, cols - side - 2)
        return FacilityTextBand(
            textTop: textTop,
            textBot: textBot,
            textLeft: textLeft,
            textRight: textRight
        )
    }

    /// Like `facilityCell`, but clamps into the text band (for drag outside the grid).
    func facilityTextCellClamped(fromUTF16 utf16Index: Int) -> (col: Int, row: Int)? {
        guard isFacilityTerminalActive else { return nil }
        let band = facilityTextBand
        let cols = max(1, facilityCols)
        let rows = max(1, FacilityTerminal.shared.rows)
        let prefixLen = (facilityPaintPrefix as NSString).length
        let local: Int
        if utf16Index < prefixLen {
            local = 0
        } else {
            local = utf16Index - prefixLen
        }
        let stride = cols + 1
        var row = local / stride
        var col = local % stride
        if col >= cols { col = cols - 1 }
        row = min(max(0, row), rows - 1)
        col = min(max(0, col), cols - 1)
        // Prefer text body for selection free-end.
        row = min(max(row, band.textTop), band.textBot)
        col = min(max(col, band.textLeft), band.textRight)
        return (col, row)
    }

    /// Push view-only pan keys for scroll-on-drag (does not clear selection).
    /// `vertical` / `horizontal`: -1 / 0 / +1.
    func reportFacilityEdgeScroll(vertical: Int, horizontal: Int) {
        guard isFacilityTerminalActive, isEvaluating else { return }
        // 129=SZ-VIEW-UP 130=SZ-VIEW-DN 12=SZ-HSCROLL-LEFT 128=SZ-HSCROLL-RIGHT
        if vertical < 0 { _ = pushKey(129) }
        if vertical > 0 { _ = pushKey(130) }
        if horizontal < 0 { _ = pushKey(12) }
        if horizontal > 0 { _ = pushKey(128) }
    }

    /// Queue a facility mouse event (down / drag / up) and wake SZ-MOUSE (key 25).
    /// Drag events coalesce so KEY is not flooded during a fast drag.
    func reportFacilityMouse(
        utf16Index: Int,
        phase: FacilityMousePhase,
        command: Bool = false,
        shift: Bool = false,
        doubleClick: Bool = false,
        tripleClick: Bool = false
    ) {
        guard isFacilityTerminalActive, isEvaluating else { return }
        // Exact cell, else clamp into the full grid (incl. find/status) so clicks never drop.
        guard let cell = facilityCell(fromUTF16: utf16Index)
                ?? facilityGridCellClamped(fromUTF16: utf16Index) else { return }
        reportFacilityMouse(
            col: cell.col,
            row: cell.row,
            phase: phase,
            command: command,
            shift: shift,
            doubleClick: doubleClick,
            tripleClick: tripleClick
        )
    }

    func reportFacilityMouse(
        col: Int,
        row: Int,
        phase: FacilityMousePhase,
        command: Bool = false,
        shift: Bool = false,
        doubleClick: Bool = false,
        tripleClick: Bool = false
    ) {
        guard isFacilityTerminalActive, isEvaluating else { return }
        let ev = FacilityMouseEvent(
            col: col,
            row: row,
            command: command,
            shift: shift,
            doubleClick: doubleClick,
            tripleClick: tripleClick,
            phase: phase
        )
        var shouldPushKey = false
        lock.lock()
        if phase == .drag,
           let last = pendingMouseEvents.last,
           last.phase == .drag {
            // Coalesce: keep only the latest drag position.
            pendingMouseEvents[pendingMouseEvents.count - 1] = ev
            // Key already queued for prior drag (or still waiting).
            shouldPushKey = !facilityMouseKeyQueued
            if shouldPushKey { facilityMouseKeyQueued = true }
        } else {
            pendingMouseEvents.append(ev)
            shouldPushKey = !facilityMouseKeyQueued
            if shouldPushKey { facilityMouseKeyQueued = true }
        }
        lock.unlock()
        if shouldPushKey {
            // 25 = SZ-MOUSE in sz-edit.fth
            pushKey(25)
        }
    }

    /// Compatibility: single-shot click (treated as mouse-down).
    func reportFacilityClick(utf16Index: Int, extend: Bool = false) {
        reportFacilityMouse(utf16Index: utf16Index, phase: .down, command: extend)
    }

    /// Consume one pending mouse event for (SZ-CLICK).
    /// Returns 0, or flag bits (see host_sz_click). Pushes another SZ-MOUSE key if more remain.
    fileprivate func takeFacilityClick(
        colOut: UnsafeMutablePointer<Int64>?,
        rowOut: UnsafeMutablePointer<Int64>?
    ) -> Int32 {
        lock.lock()
        guard !pendingMouseEvents.isEmpty else {
            facilityMouseKeyQueued = false
            lock.unlock()
            colOut?.pointee = 0
            rowOut?.pointee = 0
            return 0
        }
        let ev = pendingMouseEvents.removeFirst()
        let more = !pendingMouseEvents.isEmpty
        facilityMouseKeyQueued = more
        lock.unlock()

        colOut?.pointee = Int64(ev.col)
        rowOut?.pointee = Int64(ev.row)
        var flag: Int32 = 1
        if ev.command { flag |= 2 }
        flag |= Int32(ev.phase.rawValue) << 2
        if ev.shift { flag |= 16 }
        if ev.doubleClick { flag |= 32 }
        if ev.tripleClick { flag |= 64 }

        // Drain remaining events one KEY at a time (down → drag* → up).
        if more {
            _ = pushKey(25)
        }
        return flag
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

    // MARK: - Editor open path staging (Cmd-O while KEY waits)

    /// Path staged by the host open panel for the next `SZ-DO-MENU-OPEN` / `(SZ-PATH@)`.
    private var stagedEditorOpenPath: String = ""
    /// Last successful editor file (absolute or Library-relative). Drives open-panel start dir.
    private(set) var lastEditorFilePath: String?
    /// True if the current editor session was opened under FROMLIB (panel starts at Library).
    private(set) var editorOpenedFromLibrary = false

    // MARK: - Split command pane (phase 1): stage line + emit bypass while facility on

    /// Command line staged by the lower command pane for `(SZ-CMD@)` / key 133.
    private var stagedCommandLine: String = ""
    /// When true, EMIT/TYPE go to the host stream even if the facility grid is active
    /// (so console commands do not paint into the editor cells).
    private var facilityEmitBypass = false
    private let facilityEmitBypassLock = NSLock()
    /// Authoritative: lower command pane owns typing / clipboard.
    /// Set only from pane activation (click / Return submit). Must NOT be inferred
    /// from AppKit first-responder — after a command, ok> reclaims FR on the
    /// command pane while the user may already have clicked back into the editor;
    /// FR-based reads left KEY routing stuck on the console until restart.
    private var commandPaneFocusedFlag = false
    private let commandPaneFocusLock = NSLock()

    /// True when the lower command pane should own typing / clipboard.
    var isCommandPaneFocused: Bool {
        commandPaneFocusLock.lock()
        defer { commandPaneFocusLock.unlock() }
        return commandPaneFocusedFlag
    }

    /// Same as `isCommandPaneFocused` (sticky only; kept for call sites).
    var isCommandPaneFocusedFlag: Bool { isCommandPaneFocused }

    func setCommandPaneFocused(_ on: Bool) {
        commandPaneFocusLock.lock()
        commandPaneFocusedFlag = on
        commandPaneFocusLock.unlock()
    }

    /// Drop coalesced mouse events left over if SZ-MOUSE was not drained (e.g. during
    /// EVALUATE). Prevents a stuck `facilityMouseKeyQueued` from silencing clicks.
    func resetFacilityMouseQueue() {
        lock.lock()
        pendingMouseEvents.removeAll(keepingCapacity: true)
        facilityMouseKeyQueued = false
        facilityScrollAccum = 0
        lock.unlock()
    }

    #if os(macOS)
    /// Pane kind of the key window's first responder, if it is a console text view.
    static func focusedConsolePaneKind() -> ConsolePaneKind? {
        guard let fr = NSApp.keyWindow?.firstResponder else { return nil }
        if let tv = fr as? ConsoleNSTextView {
            return tv.paneKind
        }
        var v = fr as? NSView
        while let cur = v {
            if let tv = cur as? ConsoleNSTextView {
                return tv.paneKind
            }
            v = cur.superview
        }
        return nil
    }
    #endif

    /// Optional host sink when a split-pane console command finishes (append ok prompt).
    var onCommandLineDone: (() -> Void)?

    func setFacilityEmitBypass(_ on: Bool) {
        if !on {
            // Flush any TYPE still buffered while bypass is still on, so the
            // prompt / last output is not mis-routed into the facility grid.
            facilityEmitBypassLock.lock()
            let wasOn = facilityEmitBypass
            facilityEmitBypassLock.unlock()
            if wasOn {
                drainEmitBufferToSink()
            }
        }
        facilityEmitBypassLock.lock()
        facilityEmitBypass = on
        facilityEmitBypassLock.unlock()
        if !on {
            // One more drain after clearing the flag for anything that raced in.
            drainEmitBufferToSink()
        }
    }

    func notifyCommandLineDone() {
        // Finish any TYPE still in the emit buffer before the host appends ok(n)>.
        // drain always hops to main when needed; then run the host callback after
        // that drain so ok> is not interleaved with trailing TYPE on the main queue.
        drainEmitBufferToSink()
        // EVALUATE may have run while mouse/scroll keys were pushed; clear any
        // undrained mouse coalescing state so the next editor click wakes KEY.
        resetFacilityMouseQueue()
        let done = onCommandLineDone
        // Always async to main so Forth never touches SwiftUI, and so the drain
        // async block (if any) is ordered before this callback on the main queue.
        DispatchQueue.main.async {
            done?()
        }
    }

    private var isFacilityEmitBypass: Bool {
        facilityEmitBypassLock.lock()
        defer { facilityEmitBypassLock.unlock() }
        return facilityEmitBypass
    }

    /// Stage a console command for Forth while SZ-EDITOR KEY is waiting (key 133).
    func stageCommandLine(_ line: String) {
        stagedCommandLine = line
    }

    /// Copy staged command into Forth buffer and clear it. Returns byte length.
    func takeStagedCommandLine(into ptr: UnsafeMutableRawPointer?, maxLength: Int) -> Int {
        let data = Data(stagedCommandLine.utf8)
        stagedCommandLine = ""
        let n = min(max(0, maxLength), data.count)
        if n > 0, let ptr {
            data.copyBytes(to: ptr.assumingMemoryBound(to: UInt8.self), count: n)
        }
        return n
    }

    /// Submit a command line into the open editor KEY loop (no nested host evaluate).
    /// Returns false if the editor is not active.
    @discardableResult
    func submitCommandLineFromPane(_ line: String) -> Bool {
        guard isEvaluating, FacilityTerminal.shared.isActive else { return false }
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return true }
        stageCommandLine(t)
        return pushKey(133) // SZ-CMD-EVAL
    }

    /// Stage a path for Forth `(SZ-PATH@)` / `SZ-HOST-TAKE-PATH` (no nested evaluate).
    /// Prefer Library-relative form when the file is under the bundle Library so
    /// SZ-FNAME / visit slots stay short (absolute DerivedData paths are huge).
    func stageEditorOpenPath(_ path: String) {
        let staged: String
        if let lib = FileHost.shared.libraryURL {
            let libPath = lib.standardizedFileURL.path
            let full = URL(fileURLWithPath: path).standardizedFileURL.path
            if full == libPath || full.hasPrefix(libPath + "/") {
                let rest = String(full.dropFirst(libPath.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                staged = rest.isEmpty ? "Library" : "Library/" + rest
            } else {
                staged = path
            }
        } else {
            staged = path
        }
        stagedEditorOpenPath = staged
        noteEditorFilePath(staged)
    }

    /// Copy staged open path into Forth buffer and clear it. Returns byte length.
    func takeStagedEditorOpenPath(into ptr: UnsafeMutableRawPointer?, maxLength: Int) -> Int {
        let data = Data(stagedEditorOpenPath.utf8)
        stagedEditorOpenPath = ""
        let n = min(max(0, maxLength), data.count)
        if n > 0, let ptr {
            data.copyBytes(to: ptr.assumingMemoryBound(to: UInt8.self), count: n)
        }
        return n
    }

    /// Remember the file currently being edited (for Cmd-O start directory).
    func noteEditorFilePath(_ path: String) {
        let t = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        lastEditorFilePath = t
    }

    /// Directory for NSOpenPanel: current file's folder, else Library if FROMLIB session, else cwd.
    func editorOpenStartDirectory() -> URL {
        if let p = lastEditorFilePath, !p.isEmpty {
            // Absolute path on disk
            if p.hasPrefix("/") {
                let parent = URL(fileURLWithPath: p).deletingLastPathComponent()
                if FileManager.default.fileExists(atPath: parent.path) {
                    return parent
                }
            }
            // HYPER / Library-relative (Library/…, Hyper/…, Editor/…)
            if let resolved = FileHost.shared.resolveHyperStylePath(p)
                ?? FileHost.shared.resolveLoadPath(p, switchCwdForFromLib: false) {
                let parent = resolved.deletingLastPathComponent()
                if FileManager.default.fileExists(atPath: parent.path) {
                    return parent
                }
            }
        }
        if editorOpenedFromLibrary, let lib = FileHost.shared.libraryURL {
            return lib
        }
        if FileHost.shared.fromLibraryArmed, let lib = FileHost.shared.libraryURL {
            return lib
        }
        return URL(fileURLWithPath: FileHost.shared.logicalCurrentDirectory, isDirectory: true)
    }

    /// ⌘X / ⌘C / ⌘V while SZ-EDITOR KEY is waiting.
    /// Not used when the split command pane is focused (that pane uses AppKit clipboard).
    @discardableResult
    func pushEditorClipboardKey(_ which: String) -> Bool {
        guard isEvaluating, isFacilityTerminalActive else { return false }
        if isCommandPaneFocused { return false }
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

    /// Host restores the pre-facility console transcript after FACILITY-OFF.
    /// Called on the main thread (sync if already main, else async).
    var onFacilityExit: (() -> Void)?

    /// Host CLS: clear transcript and show a fresh ok prompt (menu + Forth `CLS`).
    var onHostClearConsole: (() -> Void)?

    /// Optional banner prefix kept above facility paints (e.g. empty while editing).
    var facilityPaintPrefix: String = ""

    /// Set when TERMINAL-REFRESH / FACILITY-OFF runs after a bare PAGE.
    /// Bare PAGE without a following refresh is treated as orphaned and unlocked.
    private var facilityRefreshSeenSincePage = false
    private let orphanFacilityLock = NSLock()

    func noteFacilityRefreshSeen() {
        orphanFacilityLock.lock()
        facilityRefreshSeenSincePage = true
        orphanFacilityLock.unlock()
    }

    /// After the *first* PAGE of a facility session: if no TERMINAL-REFRESH
    /// follows, deactivate so the idle console can type and select again.
    ///
    /// Must not call `onFacilityExit` — that tears down the editor split and
    /// races with SZ-REDRAW during splitter drag (console wipe + flash loop).
    /// Bare PAGE never begins the split (`onTerminalRefresh` does); deactivating
    /// the terminal is enough to unlock the idle console.
    func scheduleOrphanFacilityPageCheck() {
        orphanFacilityLock.lock()
        facilityRefreshSeenSincePage = false
        orphanFacilityLock.unlock()
        DispatchQueue.main.async {
            // Two turns: allow same evaluate to finish PAGE…TERMINAL-REFRESH.
            DispatchQueue.main.async {
                self.orphanFacilityLock.lock()
                let sawRefresh = self.facilityRefreshSeenSincePage
                self.orphanFacilityLock.unlock()
                guard FacilityTerminal.shared.isActive, !sawRefresh else { return }
                FacilityTerminal.shared.deactivate()
                FacilityTerminal.shared.endGridPaint()
                self.setFacilityEmitBypass(false)
            }
        }
    }

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

    /// Agent / headless mode: deliver EMIT synchronously (no main-queue defer).
    /// Required when there is no AppKit run loop pumping drains.
    private var agentSyncEmit = false

    /// Enable synchronous emit delivery (agent CLI). Call before evaluate.
    func setAgentSyncEmit(_ on: Bool) {
        agentSyncEmit = on
        if on {
            forceFlushEmitSync()
        }
    }

    /// Drain pending emit buffer to `onEmit` immediately on this thread.
    func forceFlushEmitSync() {
        lock.lock()
        absorbEmitBytesLocked()
        let chunk = pendingEmit
        pendingEmit = ""
        emitFlushScheduled = false
        let sink = onEmit
        lock.unlock()
        if !chunk.isEmpty, let sink {
            sink(chunk)
        }
    }

    private init() {
        kernelHookTarget = self

        // Recover SIGSEGV/SIGBUS into the kernel setjmp (like TZForth soft faults).
        // Must be before any kernel_eval; kernel_init also installs via sigaction.
        Self.installMemoryFaultHandlers()

        // Agent headless: skip AppKit key monitor (no window / may not have NSApp yet).
        if !AgentChannel.isRequested {
            installKeyDownMonitor()
        }

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
        kernel_set_system(kernelSystemTrampoline)
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
    /// Agent mode: flush synchronously so transcripts work without a GUI run loop.
    private func scheduleEmitFlush() {
        if agentSyncEmit {
            forceFlushEmitSync()
            return
        }
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
    /// Always invokes `onEmit` on the main thread — `(SZ-CONSOLE-EMIT) 0` drains
    /// from the Forth queue; mutating SwiftUI/AppKit there hung the UI after commands.
    private func drainEmitBufferToSink() {
        lock.lock()
        absorbEmitBytesLocked()
        let chunk = pendingEmit
        pendingEmit = ""
        let sink = onEmit
        // Clear schedule flag before calling sink so concurrent emit can re-schedule.
        emitFlushScheduled = false
        lock.unlock()

        let deliver: () -> Void = { [weak self] in
            guard let self else { return }
            if !chunk.isEmpty, let sink {
                sink(chunk)
            }
            // If more was buffered while we delivered, schedule another drain.
            // Incomplete UTF-8 tails stay in pendingEmitBytes without forcing a spin.
            self.lock.lock()
            let stillPending = !self.pendingEmit.isEmpty || !self.pendingEmitBytes.isEmpty
            let needAgain = stillPending && !self.emitFlushScheduled
            if needAgain { self.emitFlushScheduled = true }
            self.lock.unlock()
            if needAgain {
                DispatchQueue.main.async { [weak self] in
                    self?.drainEmitBufferToSink()
                }
            }
        }

        if Thread.isMainThread {
            deliver()
        } else {
            DispatchQueue.main.async(execute: deliver)
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
        // Lower command pane owns arrows / editing keys while focused.
        if isCommandPaneFocused { return false }
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
    /// Push a keyDown into the SZ-EDITOR KEY queue. Used by the local monitor and
    /// by facility `keyDown` when the monitor left the event (stale focus flag).
    /// - Returns: true if the event was fully handled (caller should not pass to super).
    @discardableResult
    func deliverFacilityKeyDown(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        lock.lock()
        let active = evaluatingFlag
        lock.unlock()
        guard active else { return false }
        let facilityOn = FacilityTerminal.shared.isActive
        let mods = event.modifierFlags.intersection([.control, .option, .shift, .command])

        // ⌘S / ⌘W / ⌘Q / clipboard / find while facility is open.
        if mods.contains(.command) {
            if facilityOn {
                let ch = (event.charactersIgnoringModifiers ?? "").lowercased()
                if ch == "s", !mods.contains(.shift) {
                    pushKey(19)
                    return true
                }
                if ch == "w", !mods.contains(.shift) {
                    pushKey(17)
                    return true
                }
                if ch == "q", !mods.contains(.shift) {
                    requestQuitAppAfterEditorClose()
                    pushKey(17)
                    return true
                }
                if ch == "f", !mods.contains(.shift) {
                    pushKey(131)
                    return true
                }
                if ch == "g" {
                    pushKey(mods.contains(.shift) ? 20 : 21)
                    return true
                }
                if ch == "e", !mods.contains(.shift) {
                    pushKey(18)
                    return true
                }
                if !mods.contains(.shift), ch == "x" || ch == "c" || ch == "v" {
                    if pushEditorClipboardKey(ch) { return true }
                }
                switch event.keyCode {
                case 115: pushKey(28); return true
                case 119: pushKey(29); return true
                default: break
                }
            }
            // Other ⌘ chords (menus) — not handled here.
            return false
        }

        // macOS Delete (backspace) is keyCode 51; character is often DEL (127).
        if event.keyCode == 51 {
            pushKey(8)
            return true
        }

        // Return (36): plain → LF (10); ⇧Return → 132 (find previous).
        if facilityOn, event.keyCode == 36 {
            if mods.contains(.shift), !mods.contains(.command), !mods.contains(.option) {
                pushKey(132)
            } else {
                pushKey(10)
            }
            return true
        }

        if mods.contains(.control) {
            switch event.keyCode {
            case 115: pushKey(28); return true
            case 119: pushKey(29); return true
            default: break
            }
        }

        if let fkid = Self.facilityFKeyId(for: event) {
            if facilityOn, let pc = Self.editorPCKeyCode(forFacilityId: fkid) {
                pushKey(pc)
            } else {
                pushKey(FacilityFKey.event(fkid))
            }
            return true
        }

        let chars = event.charactersIgnoringModifiers ?? event.characters
        if let chars, !chars.isEmpty {
            var any = false
            for scalar in chars.unicodeScalars {
                if scalar.value >= 0xF700 && scalar.value <= 0xF8FF { continue }
                var v = Int32(bitPattern: UInt32(scalar.value))
                if v == 13 { v = 10 }
                if v == 127 && facilityOn { v = 8 }
                if v > 0 && v < 0x11_0000 {
                    pushKey(v)
                    any = true
                }
            }
            return any
        }
        // Consume unknown keys while evaluating so they do not edit the grid string.
        return facilityOn
    }

    private func installKeyDownMonitor() {
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            self.lock.lock()
            let active = self.evaluatingFlag
            self.lock.unlock()
            let mods = event.modifierFlags.intersection([.control, .option, .shift, .command])
            let facilityOn = FacilityTerminal.shared.isActive

            // Sticky flag only (not first-responder). After a command-pane line,
            // ok> may leave FR on the command view even after the user clicked the
            // editor; FR-based routing left the editor dead.
            let commandPaneFocus = self.isCommandPaneFocusedFlag

            // Idle console: ⌘PgUp / ⌘PgDn → evaluate HYPER-PREV / HYPER-NEXT
            if mods.contains(.command), !mods.contains(.shift), !active,
               event.keyCode == 116 || event.keyCode == 121 {
                let prev = (event.keyCode == 116)
                self.evaluateHyperNav(prev ? "HYPER-PREV" : "HYPER-NEXT")
                return nil
            }

            // Lower command pane owns typing + clipboard while sticky is set.
            // Still steal editor-global ⌘ shortcuts (save/close/quit/find/hyper/VIEW).
            if commandPaneFocus {
                if mods.contains(.command), active && facilityOn {
                    let ch = (event.charactersIgnoringModifiers ?? "").lowercased()
                    if ch == "s", !mods.contains(.shift) {
                        self.pushKey(19)
                        return nil
                    }
                    if ch == "w", !mods.contains(.shift) {
                        self.pushKey(17)
                        return nil
                    }
                    if ch == "q", !mods.contains(.shift) {
                        self.requestQuitAppAfterEditorClose()
                        self.pushKey(17)
                        return nil
                    }
                    // ⌘E → VIEW word under command caret (ConsoleView notification)
                    // even while the lower pane owns typing.
                    if ch == "e", !mods.contains(.shift) {
                        self.viewWordUnderConsoleCursor()
                        return nil
                    }
                    // ⌘F find field; ⌘G / ⌘⇧G find next/prev in the open buffer.
                    if ch == "f", !mods.contains(.shift) {
                        self.pushKey(131)
                        return nil
                    }
                    if ch == "g" {
                        self.pushKey(mods.contains(.shift) ? 20 : 21)
                        return nil
                    }
                    // ⌘PgUp / ⌘PgDn — Hyper prev/next (same as facility-focused).
                    if !mods.contains(.shift), event.keyCode == 116 {
                        self.pushKey(26)
                        return nil
                    }
                    if !mods.contains(.shift), event.keyCode == 121 {
                        self.pushKey(27)
                        return nil
                    }
                    // ⌘← / ⌘→ — in-buffer find (steal before NSTextView line-start/end).
                    // Do not call consumeEditorHotKeyIfNeeded — it no-ops while command focused.
                    if !mods.contains(.shift), !mods.contains(.option) {
                        switch event.keyCode {
                        case 123: // left
                            self.pushKey(20)
                            return nil
                        case 124: // right
                            self.pushKey(21)
                            return nil
                        case 115: // Home
                            self.pushKey(28)
                            return nil
                        case 119: // End
                            self.pushKey(29)
                            return nil
                        default:
                            break
                        }
                    }
                }
                return event
            }

            // Editor owns KEY (sticky clear): deliver facility keys even if FR lags.
            if active, facilityOn {
                if self.consumeEditorHotKeyIfNeeded(event) {
                    return nil
                }
                if self.deliverFacilityKeyDown(event) {
                    return nil
                }
                // Unhandled ⌘ menu shortcuts pass through.
                if mods.contains(.command) { return event }
                return nil
            }

            // SZ-EDITOR ⌘←/→ find and ⌘PgUp/Dn Hyper when facility FR not detected.
            if self.consumeEditorHotKeyIfNeeded(event) {
                return nil
            }

            // Phase 5 idle / facility-adjacent ⌘E / ⌘F / ⌘G
            if mods.contains(.command) {
                let ch = (event.charactersIgnoringModifiers ?? "").lowercased()
                if ch == "e", !mods.contains(.shift) {
                    if active && facilityOn {
                        self.pushKey(18)
                        return nil
                    }
                    if !active {
                        self.viewWordUnderConsoleCursor()
                        return nil
                    }
                }
                if ch == "f", active && facilityOn, !mods.contains(.shift) {
                    self.pushKey(131)
                    return nil
                }
                if ch == "g", active && facilityOn {
                    self.pushKey(mods.contains(.shift) ? 20 : 21)
                    return nil
                }
                if active && facilityOn, !mods.contains(.shift),
                   ch == "x" || ch == "c" || ch == "v" {
                    if self.pushEditorClipboardKey(ch) { return nil }
                }
            }

            guard active else { return event }

            if self.deliverFacilityKeyDown(event) {
                return nil
            }
            if mods.contains(.command) { return event }
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
            // Nested CFRunLoopRunInMode re-entry (e.g. from scroll/layout while
            // already pumping) has trapped as EXC_BREAKPOINT on some macOS builds.
            while done.wait(timeout: .now() + 0.016) == .timedOut {
                if !self.isPumpingEvents {
                    var more = true
                    var steps = 0
                    while more, steps < 8 {
                        let r = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0, true)
                        more = (r == .handledSource)
                        steps += 1
                    }
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
        noteEditorFilePath(path)
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
                editorOpenedFromLibrary = true
            } else {
                szEditorOpenStartDirectory = nil
                editorOpenedFromLibrary = false
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

        // Automated Editor side-list / Hyper-goto suite (TZForth-style FTEST path).
        //   SZFLTEST=1 open 64Forth.app
        // Captures console output to Application Support and /tmp, then exits.
        if ProcessInfo.processInfo.environment["SZFLTEST"] == "1" {
            runSzFlTestAndExit()
        }

        return true
    }

    /// Run `Editor/sz-fl-test.fth`, write transcript, terminate (no GUI needed).
    private func runSzFlTestAndExit() {
        var log = ""
        let prev = onEmit
        onEmit = { s in
            log += s
            prev?(s)
        }
        handleEmitString("=== SZFLTEST=1 starting Editor/sz-fl-test.fth ===\n")
        _ = evaluate("FROMLIB FLOAD Editor/sz-fl-test.fth")
        handleEmitString("=== SZFLTEST=1 finished ===\n")
        onEmit = prev

        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("64Forth", isDirectory: true)
        if let support {
            try? fm.createDirectory(at: support, withIntermediateDirectories: true)
            let out = support.appendingPathComponent("sz-fl-test-results.txt")
            try? log.write(to: out, atomically: true, encoding: .utf8)
            handleEmitString("SZFLTEST wrote \(out.path)\n")
        }
        let tmp = URL(fileURLWithPath: "/tmp/sz-fl-test-results.txt")
        try? log.write(to: tmp, atomically: true, encoding: .utf8)
        handleEmitString("SZFLTEST also wrote \(tmp.path)\n")

        // Allow emit flush then exit with status based on failures.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let failed = log.contains("*** SZ-FL-TEST FAILURES ***")
                || !log.contains("ALL PASS")
            Foundation.exit(failed ? 1 : 0)
        }
    }

    @discardableResult
    func evaluateStub(_ line: String) -> Int32 {
        handleEmitString("ok  (stub: kernel not live — '\(line)')\n")
        return 0
    }

    // MARK: - Hooks

    /// EMITs go to the facility grid when it is active, unless command-pane bypass
    /// is on *and* we are not mid SZ-REDRAW (PAGE/AT-XY … TERMINAL-REFRESH).
    private var emitToFacilityGrid: Bool {
        let term = FacilityTerminal.shared
        guard term.isActive else { return false }
        if term.gridPaintActive { return true }
        return !isFacilityEmitBypass
    }

    fileprivate func handleEmitFromKernel(_ c: Int32) {
        // Facility grid paint always hits cells (even during command-pane bypass).
        // Bypass only redirects non-paint TYPE/EMIT to the lower host pane so
        // `see dup` does not dump the editor frame into the command transcript.
        if emitToFacilityGrid {
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
        if emitToFacilityGrid {
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
        if emitToFacilityGrid {
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
