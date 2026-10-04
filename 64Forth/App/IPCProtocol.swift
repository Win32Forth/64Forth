//
//  IPCProtocol.swift
//  64Edit
//
//  Created by Tom's MacBook Air on 9/30/26.
//

import Foundation

/// One BREAK-table slot for sock sync (name + enable).
struct BreakpointEntry: Codable, Equatable, Hashable {
    var name: String
    var enabled: Bool
}

// MARK: - Messages from 64Edit to 64Forth

enum EditorRequest: Codable, Equatable {
    case loadSource(path: String)
    case executeCommand(command: String)
    /// ⌘-click / Hyper VIEW: evaluate `(VIEW)` and reply with `viewResult`.
    case viewWord(name: String)
    /// F9 / ⌘\: toggle BREAK on a dictionary word (xt slot), not a source line.
    case toggleBreakpoint(name: String)
    /// Remove a BREAK slot by name (kernel clear; works while paused).
    case removeBreakpoint(name: String)
    /// Enable or disable a BREAK without removing it.
    case setBreakpointEnabled(name: String, enabled: Bool)
    /// Idle: evaluate `BPGO <name>` (run that word until an enabled BREAK hits).
    case breakGo(name: String)
    /// Paused: set `debug_bp_go` and Continue (run until enabled BREAK).
    case armBreakGo
    case stepInto
    case stepOver
    case stepOut
    case resume
    case stop
}

// MARK: - Messages from 64Forth to 64Edit

enum ForthResponse: Codable, Equatable {
    case consoleOutput(text: String)
    case breakpointHit(line: Int, stackTrace: [String])
    case variableChanged(name: String, value: String)
    case executionFinished(exitCode: Int)
    case error(message: String)
    /// ITC DEBUG / TDBG stepper armed (true) or finished / aborted (false).
    case debugSession(armed: Bool)
    /// Source location for the paused word (VIEW stamp). Line is 1-based.
    /// `name` is the peek token to highlight (empty when unknown).
    /// `off`/`len` are file-relative UTF-8 byte spans from dbg-map (0/0 = use name).
    case debugLocation(path: String, line: Int, name: String, off: Int, len: Int)
    /// Result of `viewWord`: `opened` is true when EDIT-AT ran (stamp found).
    case viewResult(word: String, opened: Bool)
    /// Current BREAK table (after toggle/remove/enable, or on connect).
    case breakpoints(entries: [BreakpointEntry])
}

// MARK: - JSON on the wire (NSXPC cannot pass Swift enums)

enum IPCCodec {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    static let decoder = JSONDecoder()

    static func encodeRequest(_ request: EditorRequest) throws -> Data {
        try encoder.encode(request)
    }

    static func decodeRequest(_ data: Data) throws -> EditorRequest {
        try decoder.decode(EditorRequest.self, from: data)
    }

    static func encodeResponse(_ response: ForthResponse) throws -> Data {
        try encoder.encode(response)
    }

    static func decodeResponse(_ data: Data) throws -> ForthResponse {
        try decoder.decode(ForthResponse.self, from: data)
    }
}

// MARK: - XPC interfaces
// Methods must be @objc. Payloads are Data, not Swift enums.

@objc protocol ForthEngineXPC {
    func handleRequest(_ requestData: Data, withReply reply: @escaping (Data) -> Void)
}

@objc protocol ForthClientXPC {
    func engineDidSend(_ responseData: Data)
}
