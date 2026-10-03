//
//  IPCProtocol.swift
//  64Edit
//
//  Created by Tom's MacBook Air on 9/30/26.
//

import Foundation

// MARK: - Messages from 64Edit to 64Forth

enum EditorRequest: Codable, Equatable {
    case loadSource(path: String)
    case executeCommand(command: String)
    case setBreakpoint(line: Int, enabled: Bool)
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
    case debugLocation(path: String, line: Int)
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
