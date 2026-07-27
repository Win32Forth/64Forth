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
import AppKit

// MARK: - C ABI (forth.s)

@_silgen_name("kernel_init")
private func kernel_init() -> Int32

@_silgen_name("kernel_eval")
private func kernel_eval(_ line: UnsafePointer<CChar>?, _ n: Int) -> Int32

@_silgen_name("kernel_set_emit")
private func kernel_set_emit(_ fn: (@convention(c) (Int32) -> Void)?)

@_silgen_name("kernel_set_key")
private func kernel_set_key(_ fn: (@convention(c) () -> Int32)?)

@_silgen_name("kernel_set_fromlib")
private func kernel_set_fromlib(_ fn: (@convention(c) () -> Void)?)

@_silgen_name("kernel_set_fromlib_clear")
private func kernel_set_fromlib_clear(_ fn: (@convention(c) () -> Void)?)

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

// MARK: - C hook target (must not touch KernelBridge.shared)

private var kernelHookTarget: KernelBridge?

private let kernelEmitTrampoline: @convention(c) (Int32) -> Void = { c in
    kernelHookTarget?.handleEmitFromKernel(c)
}

private let kernelKeyTrampoline: @convention(c) () -> Int32 = {
    kernelHookTarget?.handleKeyFromKernel() ?? -1
}

private let kernelFromlibTrampoline: @convention(c) () -> Void = {
    FileHost.shared.armFromLibrary()
}

private let kernelFromlibClearTrampoline: @convention(c) () -> Void = {
    FileHost.shared.clearFromLibrary()
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

// MARK: - Bridge

final class KernelBridge {
    static let shared = KernelBridge()

    private(set) var isKernelLive = false

    /// True while kernel_eval is on the stack (not re-entrant).
    private(set) var isEvaluating = false
    private let evalLock = NSLock()

    var onEmit: ((String) -> Void)? {
        didSet {
            flushPendingEmit()
            FileHost.shared.onMessage = { [weak self] s in
                self?.handleEmitString(s)
            }
        }
    }

    private var pendingEmit = ""
    private var keyQueue: [Int32] = []
    private let lock = NSLock()

    private init() {
        kernelHookTarget = self

        kernel_set_emit(kernelEmitTrampoline)
        kernel_set_key(kernelKeyTrampoline)
        kernel_set_fromlib(kernelFromlibTrampoline)
        kernel_set_fromlib_clear(kernelFromlibClearTrampoline)
        kernel_set_load_file(kernelLoadFileTrampoline)
        kernel_set_resolve_key(kernelResolveKeyTrampoline)
        kernel_set_last_load_key(kernelLastLoadKeyTrampoline)
        kernel_set_chdir(kernelChdirTrampoline)
        kernel_set_pwd(kernelPwdTrampoline)
        kernel_set_dir(kernelDirTrampoline)
        kernel_set_allocate(kernelAllocTrampoline)
        kernel_set_free(kernelFreeTrampoline)
        kernel_set_bi_mul(kernelBiMulTrampoline)
        kernel_set_bi_divmod(kernelBiDivmodTrampoline)
        kernel_set_bi_isqrt(kernelBiIsqrtTrampoline)

        FileHost.shared.onMessage = { [weak self] s in
            self?.handleEmitString(s)
        }

        let rc = kernel_init()
        isKernelLive = (rc == 0)
        lock.lock()
        pendingEmit = ""
        lock.unlock()
        FileHost.shared.releaseIncludeBuffers()
        FileHost.shared.endAllFromLibraryLoads()
        if !isKernelLive {
            handleEmitString("[64Forth] kernel_init failed (rc=\(rc))\n")
        }
    }

    private func flushPendingEmit() {
        lock.lock()
        let pending = pendingEmit
        pendingEmit = ""
        lock.unlock()
        guard !pending.isEmpty, let sink = onEmit else { return }
        if Thread.isMainThread {
            sink(pending)
        } else {
            DispatchQueue.main.async { sink(pending) }
        }
    }

    func statusLine() -> String {
        if isKernelLive {
            return "[64Forth] kernel live — vocab/BIG-INTEGER · BI-MUL · FROMLIB FLOAD DIR\n"
        }
        return "[64Forth] kernel embed API failed to start\n"
    }

    func pushKey(_ c: Int32) {
        lock.lock()
        keyQueue.append(c)
        lock.unlock()
    }

    /// Interpret one console line. Not re-entrant (returns −3 if busy).
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
        isEvaluating = true
        defer {
            isEvaluating = false
            evalLock.unlock()
        }

        var status: Int32 = 0
        t.withCString { ptr in
            let n = strlen(ptr)
            status = kernel_eval(ptr, n)
        }

        FileHost.shared.releaseIncludeBuffers()
        FileHost.shared.endAllFromLibraryLoads()
        if FileHost.shared.fromLibraryArmed {
            FileHost.shared.clearFromLibrary()
        }

        if status == 1 {
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
        return status
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

        _ = evaluate("INCLUDE \(autoURL.path)")
        _ = evaluate("MAIN")

        host.logicalCurrentDirectory = savedLogical
        _ = FileManager.default.changeCurrentDirectoryPath(savedProcess)
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
        let u = UInt8(truncatingIfNeeded: c)
        let s = String(bytes: [u], encoding: .isoLatin1) ?? ""
        handleEmitString(s)
    }

    fileprivate func handleKeyFromKernel() -> Int32 {
        // Wait briefly for console input (KEY during kernel_eval). Spin the
        // main run loop so typed keys can reach pushKey without freezing forever.
        let deadline = Date().addingTimeInterval(30)
        while true {
            lock.lock()
            if !keyQueue.isEmpty {
                let c = keyQueue.removeFirst()
                lock.unlock()
                return c
            }
            lock.unlock()
            if Date() > deadline { return -1 }
            if Thread.isMainThread {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            } else {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
    }

    private func handleEmitString(_ s: String) {
        lock.lock()
        let sink = onEmit
        if sink == nil {
            pendingEmit.append(s)
            lock.unlock()
            return
        }
        lock.unlock()
        if Thread.isMainThread {
            sink?(s)
        } else {
            DispatchQueue.main.async { sink?(s) }
        }
    }
}
