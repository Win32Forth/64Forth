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

@_silgen_name("kernel_take_repl_batch_stop")
private func kernel_take_repl_batch_stop() -> Int32

@_silgen_name("kernel_on_memory_fault")
private func kernel_on_memory_fault(_ sig: Int32)

@_silgen_name("kernel_take_fault_flag")
private func kernel_take_fault_flag() -> Int32

@_silgen_name("kernel_set_emit")
private func kernel_set_emit(_ fn: (@convention(c) (Int32) -> Void)?)

@_silgen_name("kernel_set_key")
private func kernel_set_key(_ fn: (@convention(c) () -> Int32)?)

@_silgen_name("kernel_set_key_q")
private func kernel_set_key_q(_ fn: (@convention(c) () -> Int32)?)

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

private let kernelKeyQTrampoline: @convention(c) () -> Int32 = {
    kernelHookTarget?.handleKeyAvailableFromKernel() ?? 0
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

// MARK: - Bridge

final class KernelBridge {
    static let shared = KernelBridge()

    private(set) var isKernelLive = false

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
        kernel_set_key(kernelKeyTrampoline)
        kernel_set_key_q(kernelKeyQTrampoline)
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

        FileHost.shared.onMessage = { [weak self] s in
            self?.handleEmitString(s)
        }

        let rc = kernel_init()
        isKernelLive = (rc == 0)
        // Re-install after init in case anything reset dispositions.
        Self.installMemoryFaultHandlers()
        lock.lock()
        pendingEmit = ""
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

    /// Enqueue a raw key for KEY / KEY?. Only accepted while `kernel_eval` is
    /// running — otherwise normal console typing would fill the queue and
    /// WAIT-KEY / KEY? would return leftover command-line characters.
    func pushKey(_ c: Int32) {
        lock.lock()
        guard evaluatingFlag else {
            lock.unlock()
            return
        }
        keyQueue.append(c)
        lock.unlock()
        keyAvailable.signal()
    }

    /// Drop any pending KEY bytes (call at start/end of evaluate).
    func clearKeyQueue() {
        lock.lock()
        keyQueue.removeAll(keepingCapacity: true)
        lock.unlock()
        // Drain stale semaphore permits so KEY does not wake spuriously.
        while keyAvailable.wait(timeout: .now()) == .success {}
    }

    /// Dequeue and dispatch AppKit events so the keyDown monitor can run.
    /// Must run on the main thread (classic modal input loop pattern).
    private func pumpUIForKeyInput(seconds: TimeInterval) {
        if !Thread.isMainThread {
            DispatchQueue.main.sync {
                self.pumpUIForKeyInput(seconds: seconds)
            }
            return
        }
        let until = Date(timeIntervalSinceNow: seconds)
        while Date() < until {
            // Prefer default mode; also try eventTracking for nested tracking.
            let modes: [RunLoop.Mode] = [.default, .eventTracking, .modalPanel]
            var got = false
            for mode in modes {
                if let event = NSApp.nextEvent(
                    matching: .any,
                    until: Date(timeIntervalSinceNow: 0.005),
                    inMode: mode,
                    dequeue: true
                ) {
                    NSApp.sendEvent(event)
                    got = true
                    break
                }
            }
            lock.lock()
            let hasKey = !keyQueue.isEmpty
            lock.unlock()
            if hasKey { return }
            if !got && Date() >= until { return }
        }
    }

    private func installKeyDownMonitor() {
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            self.lock.lock()
            let active = self.evaluatingFlag
            self.lock.unlock()
            guard active else { return event }
            // Leave menu shortcuts alone.
            if event.modifierFlags.contains(.command) { return event }

            let chars = event.charactersIgnoringModifiers ?? event.characters
            if let chars, !chars.isEmpty {
                for scalar in chars.unicodeScalars {
                    var v = Int32(bitPattern: UInt32(scalar.value))
                    // Normalize Return/Enter to LF (10).
                    if v == 13 { v = 10 }
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
            // Also service the main GCD queue so off-main FLOAD/CHDIR panels can run.
            while done.wait(timeout: .now() + 0.02) == .timedOut {
                _ = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.01, true)
                self.pumpUIForKeyInput(seconds: 0.02)
            }
            evalLock.unlock()
            return status
        }

        let status = runKernelEval(t)
        evalLock.unlock()
        return status
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

        if status == 1 {
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
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
        let u = UInt8(truncatingIfNeeded: c)
        let s = String(bytes: [u], encoding: .isoLatin1) ?? ""
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
