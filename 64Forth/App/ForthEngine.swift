//
//  ForthEngine.swift
//  64Forth
//
//  Created by Tom's MacBook Air on 9/30/26.
//

import Foundation

final class ForthEngine: NSObject, ForthEngineXPC {
    weak var client: ForthClientXPC?

    func handleRequest(_ requestData: Data, withReply reply: @escaping (Data) -> Void) {
        let response: ForthResponse
        do {
            let request = try IPCCodec.decodeRequest(requestData)
            response = handle(request)
        } catch {
            response = .error(message: error.localizedDescription)
        }

        do {
            reply(try IPCCodec.encodeResponse(response))
        } catch {
            let fallback = ForthResponse.error(message: "encode failed")
            reply((try? IPCCodec.encodeResponse(fallback)) ?? Data())
        }
    }

    private func handle(_ request: EditorRequest) -> ForthResponse {
        switch request {
        case .loadSource(let path):
            push(.consoleOutput(text: "load \(path)"))
            return .consoleOutput(text: "ok")
        case .executeCommand(let command):
            push(.consoleOutput(text: "> \(command)"))
            return .consoleOutput(text: "ok")
        case .setBreakpoint(let line, let enabled):
            return .consoleOutput(text: "breakpoint \(line) \(enabled ? "on" : "off")")
        case .stepInto:
            return .consoleOutput(text: "step into")
        case .stepOver:
            return .consoleOutput(text: "step over")
        case .stepOut:
            return .consoleOutput(text: "step out")
        case .resume:
            return .consoleOutput(text: "resume")
        case .stop:
            return .executionFinished(exitCode: 0)
        }

    }

    private func push(_ response: ForthResponse) {
        guard let data = try? IPCCodec.encodeResponse(response) else { return }
        client?.engineDidSend(data)
    }
}
