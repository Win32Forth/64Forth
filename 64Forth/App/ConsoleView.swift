//
//  ConsoleView.swift
//  64Forth
//
//  Public domain.
//
//  Simplified TZForth-style console. Phase 0: host-side echo and status.
//  Phase 2+: protected region, history, full KEY path, feedLine → kernel.
//

import SwiftUI
import AppKit

extension Notification.Name {
    static let clearConsole = Notification.Name("SixtyFourForthClearConsole")
    static let showLibraryFolder = Notification.Name("SixtyFourForthShowLibrary")
    static let showAutoloadFolder = Notification.Name("SixtyFourForthShowAutoload")
}

private let banner =
    "=== 64Forth (scaffold) ===\n" +
    "Host: SwiftUI console (TZForth lineage)\n" +
    "Kernel: PickleForth ARM64 ITC (entry _kernel_cold_start; embed API Phase 1)\n" +
    "Resources: AutoLoad/, Library/ (FROMLIB Phase 3)\n" +
    "Type a line and press Return (echo only until kernel bridge is wired).\n\n"

struct ConsoleView: View {
    @State private var consoleText = banner
    @State private var commandHistory: [String] = []
    @FocusState private var isFocused: Bool

    private let host = FileHost.shared
    private let kernel = KernelBridge.shared

    var body: some View {
        TextEditor(text: $consoleText)
            .font(.system(.body, design: .monospaced))
            .focused($isFocused)
            .padding(4)
            .onAppear {
                isFocused = true
                appendStatus(kernel.statusLine())
                appendStatus(host.resourceRootsDescription())
            }
            .onReceive(NotificationCenter.default.publisher(for: .clearConsole)) { _ in
                consoleText = banner
                appendStatus(kernel.statusLine())
            }
            .onReceive(NotificationCenter.default.publisher(for: .showLibraryFolder)) { _ in
                host.revealInFinder(host.libraryURL)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showAutoloadFolder)) { _ in
                host.revealInFinder(host.autoLoadURL)
            }
            .onSubmit(of: .text) {
                // TextEditor does not use onSubmit the same way; handle via monitor later.
            }
            // Minimal line commit: detect trailing newline after banner (Phase 0 prototype)
            .onChange(of: consoleText) { _, newValue in
                handlePossibleLineCommit(newValue)
            }
    }

    private func appendStatus(_ s: String) {
        if !s.hasSuffix("\n") {
            consoleText += s + "\n"
        } else {
            consoleText += s
        }
    }

    /// Phase 0: if the user appended a full line after the last "ok> " marker, echo and note stub.
    @State private var lastProcessedCount = 0

    private func handlePossibleLineCommit(_ text: String) {
        // Only act when text ends with newline and grew
        guard text.hasSuffix("\n"), text.count > lastProcessedCount else { return }
        let added = String(text.dropFirst(lastProcessedCount))
        lastProcessedCount = text.count
        let lines = added.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            let cmd = line.trimmingCharacters(in: .whitespaces)
            guard !cmd.isEmpty else { continue }
            // Ignore our own status echoes
            if cmd.hasPrefix("===") || cmd.hasPrefix("Host:") || cmd.hasPrefix("Kernel:")
                || cmd.hasPrefix("Resources:") || cmd.hasPrefix("Type a line")
                || cmd.hasPrefix("[64Forth]") || cmd.hasPrefix("AutoLoad")
                || cmd.hasPrefix("Library") || cmd.hasPrefix("Docs") {
                continue
            }
            commandHistory.append(cmd)
            let reply = kernel.evaluateStub(cmd)
            appendStatus(reply)
            lastProcessedCount = consoleText.count
        }
    }
}
