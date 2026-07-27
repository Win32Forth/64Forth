//
//  KernelBridge.swift
//  64Forth
//
//  Public domain.
//
//  Swift ↔ PickleForth assembly kernel. Phase 0: stubs and status.
//  Phase 1: link C ABI (kernel_init, kernel_eval, emit/key hooks).
//

import Foundation
import AppKit

/// Thin façade over the ARM64 kernel in `Kernel/forth.s`.
final class KernelBridge {
    static let shared = KernelBridge()

    /// When true, Phase 1 symbols are linked and cold start has run.
    private(set) var isKernelLive = false

    private init() {
        // Phase 1: call kernel_init() once here.
        // Note: _kernel_cold_start currently runs a full terminal QUIT loop;
        // do not invoke it from the UI thread until it is split into init + eval.
    }

    func statusLine() -> String {
        if isKernelLive {
            return "[64Forth] kernel live (eval ready)\n"
        }
        return "[64Forth] kernel present in target as assembly (_kernel_cold_start); " +
            "embed API not wired yet — see DESIGN.md Phase 1\n"
    }

    /// Phase 0 stub: no real interpretation.
    func evaluateStub(_ line: String) -> String {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }
        if t.uppercased() == "BYE" {
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
            return "Bye!\n"
        }
        if t.uppercased() == "HELP" || t.uppercased().hasPrefix("HELP ") {
            return "HELP will call kernel SEE/HELP after Phase 1 bridge.\n"
        }
        if t.uppercased() == "FROMLIB" {
            FileHost.shared.armFromLibrary()
            return "ok  (FROMLIB armed — next host resolve uses Resources/Library)\n"
        }
        return "ok  (stub: kernel_eval not connected — '\(t)')\n"
    }
}
