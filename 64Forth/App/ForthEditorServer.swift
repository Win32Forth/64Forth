//
//  ForthEditorServer.swift
//  64Forth
//
//  Created by Tom's MacBook Air on 9/30/26.
//

import Foundation

final class ForthEditorServer {
    static let shared = ForthEditorServer()
    static let socketFileName = "edit.sock"

    static var socketURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("64Forth", isDirectory: true)
            .appendingPathComponent(socketFileName)
    }

    private init() {}

    private var serverFD: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.64forth.editor-server")
    private var clients: [Int32] = []
    private var clientSources: [Int32: DispatchSourceRead] = [:]
    private var debugPoll: DispatchSourceTimer?
    private var lastDebugArmed = false
    /// Tail of console text for late sock clients (DEBUG often opens 64Edit after first prints).
    private var recentConsole = ""
    private let recentConsoleMax = 32_768

    /// True when at least one 64Edit sock client is connected (edit.sock).
    /// Used to skip `open -a` on DEBUG/EDIT when the editor can take pending-goto
    /// or `debugLocation` without a Launch Services reactivation flash.
    var hasConnectedClients: Bool {
        queue.sync { !clients.isEmpty }
    }

    func start() {
        // Belt-and-suspenders with SO_NOSIGPIPE on each client: a write to a
        // closed 64Edit sock must never kill 64Forth (DEBUG abort after editor quit).
        signal(SIGPIPE, SIG_IGN)

        let dir = Self.socketURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = Self.socketURL.path
        try? FileManager.default.removeItem(atPath: path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        path.withCString { cstr in
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                let raw = UnsafeMutableRawPointer(ptr)
                _ = strncpy(raw.assumingMemoryBound(to: CChar.self), cstr, 104)
            }
        }

        let bindOk = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindOk == 0, Darwin.listen(fd, 4) == 0 else {
            Darwin.close(fd)
            return
        }

        serverFD = fd
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in
            self?.acceptClient()
        }
        src.resume()
        source = src

        let kernel = KernelBridge.shared
        let previous = kernel.onEmit
        kernel.onEmit = { chunk in
            previous?(chunk)
            ForthEditorServer.shared.broadcast(.consoleOutput(text: chunk))
        }

        startDebugSessionPoll()
    }

    /// Watch `kernel_any_debug_armed` and push `.debugSession` on edges.
    private func startDebugSessionPoll() {
        debugPoll?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
        t.setEventHandler { [weak self] in
            self?.pollDebugSession()
        }
        t.resume()
        debugPoll = t
    }

    private func pollDebugSession() {
        let armed = KernelBridge.shared.isAnyDebugArmed
        guard armed != lastDebugArmed else { return }
        lastDebugArmed = armed
        if !armed {
            DispatchQueue.main.async {
                FileHost.shared.clearDebugReveal()
            }
        }
        for fd in clients {
            writeResponse(.debugSession(armed: armed), to: fd)
        }
    }

    /// Push `debugSession(armed: true)` as soon as a pause paints, so 64Edit
    /// letter keys do not wait on the 100ms poll edge (first `i` / Switch to Edit).
    func notifyDebugSessionArmed() {
        queue.async {
            guard KernelBridge.shared.isAnyDebugArmed else { return }
            guard !self.lastDebugArmed else { return }
            self.lastDebugArmed = true
            for fd in self.clients {
                self.writeResponse(.debugSession(armed: true), to: fd)
            }
        }
    }

    private func acceptClient() {
        let cfd = Darwin.accept(serverFD, nil, nil)
        guard cfd >= 0 else { return }

        // Writing to a closed 64Edit sock must not SIGPIPE-kill 64Forth (e.g. quit
        // editor while DEBUG is still paused, then abort from the console).
        var on: Int32 = 1
        _ = setsockopt(cfd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout.size(ofValue: on)))

        clients.append(cfd)

        let src = DispatchSource.makeReadSource(fileDescriptor: cfd, queue: queue)
        src.setEventHandler { [weak self] in
            self?.readClient(cfd)
        }
        src.setCancelHandler {
            Darwin.close(cfd)
        }
        src.resume()
        clientSources[cfd] = src
        NSLog("64Forth editor server: client fd=%d", cfd)

        // Replay recent console so a late connect (e.g. DEBUG open) sees the pause banner.
        if !recentConsole.isEmpty {
            writeResponse(.consoleOutput(text: recentConsole), to: cfd)
        }
        // Sync current stepper state so a late connect sees an active session.
        let armed = KernelBridge.shared.isAnyDebugArmed
        lastDebugArmed = armed
        writeResponse(.debugSession(armed: armed), to: cfd)
    }

    private func dropClient(_ fd: Int32) {
        clients.removeAll { $0 == fd }
        if let src = clientSources.removeValue(forKey: fd) {
            src.cancel()
        }
    }

    private func readClient(_ fd: Int32) {
        var buf = [UInt8](repeating: 0, count: 16_384)
        let n = Darwin.read(fd, &buf, buf.count)
        if n <= 0 {
            dropClient(fd)
            return
        }

        NSLog("64Forth editor server: read %d bytes", n)
        let data = Data(buf.prefix(Int(n)))
        for line in data.split(separator: 10) where !line.isEmpty {
            handleLine(Data(line), fd: fd)
        }
    }

    private func handleLine(_ data: Data, fd: Int32) {
        NSLog("64Forth editor server: request %s", String(data: data, encoding: .utf8) ?? "?")
        let request: EditorRequest
        do {
            request = try IPCCodec.decodeRequest(data)
        } catch {
            writeResponse(.error(message: error.localizedDescription), to: fd)
            return
        }

        let kernel = KernelBridge.shared

        // Stepper keys must not wait behind a blocking evaluate on the main queue.
        // DEBUG started from the editor console holds main inside evaluate()'s pump;
        // pushKey is lock-safe from this I/O queue and wakes the Forth KEY wait.
        switch request {
        case .stepOver:
            if !kernel.debugStepOver() {
                writeResponse(.error(message: "debugger not armed"), to: fd)
            }
            return
        case .stepInto:
            if !kernel.debugStepInto() {
                writeResponse(.error(message: "debugger not armed"), to: fd)
            }
            return
        case .stepOut:
            if !kernel.debugStepOut() {
                writeResponse(.error(message: "debugger not armed"), to: fd)
            }
            return
        case .resume:
            if !kernel.debugResume() {
                writeResponse(.error(message: "debugger not armed"), to: fd)
            }
            return
        case .stop:
            if !kernel.debugAbort() {
                writeResponse(.executionFinished(exitCode: 0), to: fd)
            }
            return
        case .setBreakpoint:
            writeResponse(.error(message: "breakpoints not wired yet"), to: fd)
            return
        case .executeCommand, .loadSource:
            break
        }

        // evaluate / loadFile need the main-thread AppKit pump while KEY waits.
        DispatchQueue.main.async {
            let response: ForthResponse
            switch request {
            case .executeCommand(let command):
                // Kernel holds evalLock while DEBUG waits for KEY; reject with a clear message.
                if kernel.isAnyDebugArmed {
                    response = .error(message: "debugger paused — use Step/Continue")
                } else {
                    let st = kernel.evaluate(command)
                    kernel.forceFlushEmitSync()
                    response = st == 0
                        ? .consoleOutput(text: "ok(\(kernel.dataStackDepth))")
                        : .error(message: "status=\(st)")
                }
            case .loadSource(let path):
                if kernel.isAnyDebugArmed {
                    response = .error(message: "debugger paused — use Step/Continue")
                } else {
                    let st = kernel.loadFile(named: path)
                    kernel.forceFlushEmitSync()
                    response = st == 0 ? .consoleOutput(text: "ok") : .error(message: "load status=\(st)")
                }
            default:
                return
            }
            self.queue.async {
                self.writeResponse(response, to: fd)
            }
        }
    }

    @discardableResult
    private func writeResponse(_ response: ForthResponse, to fd: Int32) -> Bool {
        guard clients.contains(fd) || clientSources[fd] != nil else { return false }
        guard let data = try? IPCCodec.encodeResponse(response) else { return false }
        var line = data
        line.append(0x0A)
        let n = line.withUnsafeBytes { raw -> Int in
            Darwin.write(fd, raw.baseAddress, line.count)
        }
        if n < 0 {
            dropClient(fd)
            return false
        }
        return true
    }

    func broadcast(_ response: ForthResponse) {
        queue.async {
            if case .consoleOutput(let text) = response, !text.isEmpty {
                self.appendRecentConsole(text)
            }
            for fd in self.clients {
                self.writeResponse(response, to: fd)
            }
        }
    }

    private func appendRecentConsole(_ text: String) {
        recentConsole.append(text)
        guard recentConsole.count > recentConsoleMax else { return }
        let overflow = recentConsole.count - recentConsoleMax
        recentConsole.removeFirst(overflow)
        if let nl = recentConsole.firstIndex(of: "\n") {
            recentConsole.removeSubrange(..<recentConsole.index(after: nl))
        }
    }
}
