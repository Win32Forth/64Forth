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
    private var clientSources: [DispatchSourceRead] = []
    private var debugPoll: DispatchSourceTimer?
    private var lastDebugArmed = false
    /// Tail of console text for late sock clients (DEBUG often opens 64Edit after first prints).
    private var recentConsole = ""
    private let recentConsoleMax = 32_768

    func start() {
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

    private func acceptClient() {
            let cfd = Darwin.accept(serverFD, nil, nil)
            guard cfd >= 0 else { return }
            clients.append(cfd)

            let src = DispatchSource.makeReadSource(fileDescriptor: cfd, queue: queue)
            src.setEventHandler { [weak self] in
                self?.readClient(cfd)
            }
            src.setCancelHandler {
                Darwin.close(cfd)
            }
            src.resume()
            clientSources.append(src)
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

    private func readClient(_ fd: Int32) {
            var buf = [UInt8](repeating: 0, count: 16_384)
            let n = Darwin.read(fd, &buf, buf.count)
            if n <= 0 {
                clients.removeAll { $0 == fd }
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

        DispatchQueue.main.async {
            let kernel = KernelBridge.shared
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
            case .stepOver:
                response = kernel.debugStepOver()
                    ? .consoleOutput(text: "")
                    : .error(message: "debugger not armed")
            case .stepInto:
                response = kernel.debugStepInto()
                    ? .consoleOutput(text: "")
                    : .error(message: "debugger not armed")
            case .resume:
                response = kernel.debugResume()
                    ? .consoleOutput(text: "")
                    : .error(message: "debugger not armed")
            case .stop:
                if kernel.debugAbort() {
                    response = .consoleOutput(text: "")
                } else {
                    response = .executionFinished(exitCode: 0)
                }
            case .setBreakpoint:
                response = .error(message: "breakpoints not wired yet")
            }
            self.writeResponse(response, to: fd)
        }
    }

    private func writeResponse(_ response: ForthResponse, to fd: Int32) {
        guard let data = try? IPCCodec.encodeResponse(response) else { return }
        var line = data
        line.append(0x0A)
        line.withUnsafeBytes { raw in
            _ = Darwin.write(fd, raw.baseAddress, line.count)
        }
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
