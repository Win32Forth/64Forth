//
//  ConsoleView.swift
//  64Forth
//
//  Public domain.
//
//  TZForth-style console host: protected engine output, Return commits the full
//  input line, Up/Down history, feedLine → KernelBridge.evaluate.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension Notification.Name {
    static let clearConsole = Notification.Name("SixtyFourForthClearConsole")
    static let showLibraryFolder = Notification.Name("SixtyFourForthShowLibrary")
    static let showAutoloadFolder = Notification.Name("SixtyFourForthShowAutoload")
    static let showDocsFolder = Notification.Name("SixtyFourForthShowDocs")
    static let toolsFload = Notification.Name("SixtyFourForthToolsFload")
    static let toolsChdir = Notification.Name("SixtyFourForthToolsChdir")
    static let toolsEdit = Notification.Name("SixtyFourForthToolsEdit")
}

private let banner = "=== 64Forth 0.4.0 ===\n"

struct ConsoleView: View {
    @State private var consoleText = banner
    @State private var commandHistory: [String] = []
    @State private var historyIndex = -1
    @State private var isRecallingHistory = false

    /// Length of consoleText after last engine/host output; only text after this is input.
    @State private var protectedLength = 0
    @State private var protectedSnapshot = ""
    @State private var isRevertingProtectedEdit = false
    @State private var isProgrammaticConsoleAppend = false
    @State private var isHandlingReturn = false
    @State private var pinCaretRequest = 0
    @State private var consoleTextView: NSTextView?

    @FocusState private var isFocused: Bool

    private let host = FileHost.shared
    private let kernel = KernelBridge.shared

    var body: some View {
        ConsoleTextView(
            text: $consoleText,
            isFocused: $isFocused,
            pinCaretRequest: $pinCaretRequest,
            editableStartUTF16: (protectedSnapshot as NSString).length,
            onReturnPressed: { handleReturnKey() },
            onHistoryUp: { recallHistory(up: true) },
            onHistoryDown: { recallHistory(up: false) },
            onKeyCharacter: { c in
                kernel.pushKey(c)
            },
            onTextViewReady: { textView in
                DispatchQueue.main.async {
                    consoleTextView = textView
                }
            }
        )
        .focused($isFocused)
        .onAppear {
            isFocused = true
            kernel.onEmit = { chunk in
                appendEngineOutput(chunk)
            }
            // Startup: banner (already in consoleText) → cwd → AutoLoad → prompt.
            isProgrammaticConsoleAppend = true
            appendEngineOutput("cwd: \(host.logicalCurrentDirectory)\n")
            markProtectedThroughEndOfText()
            isProgrammaticConsoleAppend = false
            keepCursorVisible(followPrompt: true)

            // AutoLoad after first frame so onEmit appends reliably (TZForth pattern).
            DispatchQueue.main.async {
                isProgrammaticConsoleAppend = true
                _ = kernel.runAutoLoadIfPresent()
                markProtectedThroughEndOfText()
                appendPrompt()
                isProgrammaticConsoleAppend = false
                keepCursorVisible(followPrompt: true)
            }
        }
        .onChange(of: consoleText) { oldValue, newValue in
            if isRevertingProtectedEdit {
                isRevertingProtectedEdit = false
                return
            }
            if isProgrammaticConsoleAppend {
                // During long INCLUDE/Hayes output, follow the end only if the
                // user is already near the bottom — so they can scroll up and
                // read earlier lines without fighting auto-scroll.
                maybeFollowOutputIfNearBottom()
                return
            }
            if newValue.count < protectedLength
                || (!protectedSnapshot.isEmpty && !newValue.hasPrefix(protectedSnapshot)) {
                isRevertingProtectedEdit = true
                consoleText = oldValue
                return
            }
            checkForCommandExecution(newValue)
            keepCursorVisible()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearConsole)) { _ in
            clearConsole()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showLibraryFolder)) { _ in
            host.revealInFinder(host.libraryURL)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAutoloadFolder)) { _ in
            host.revealInFinder(host.autoLoadURL)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showDocsFolder)) { _ in
            host.revealInFinder(host.docsURL)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolsFload)) { _ in
            presentFloadPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolsChdir)) { _ in
            presentChdirPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolsEdit)) { _ in
            presentEditPanel()
        }
    }

    // MARK: - Protected region

    private func markProtectedThroughEndOfText() {
        protectedLength = consoleText.count
        protectedSnapshot = consoleText
    }

    private func markProtected(through length: Int) {
        protectedLength = length
        protectedSnapshot = String(consoleText.prefix(length))
    }

    /// Append kernel/host text and extend the protected prefix.
    private func appendEngineOutput(_ s: String) {
        guard !s.isEmpty else { return }
        let wasProg = isProgrammaticConsoleAppend
        isProgrammaticConsoleAppend = true
        consoleText += s
        markProtectedThroughEndOfText()
        isProgrammaticConsoleAppend = wasProg
    }

    private func appendPrompt() {
        appendEngineOutput("ok> ")
    }

    private func keepCursorVisible(followPrompt: Bool = false) {
        if followPrompt {
            pinCaretRequest += 1
        }
        if let textView = consoleTextView {
            ConsoleTextView.scheduleScrollToInsertionPoint(in: textView)
        }
    }

    /// Throttled auto-scroll for streaming engine output: only if near bottom.
    private var lastFollowOutputTime = Date.distantPast
    private func maybeFollowOutputIfNearBottom() {
        let now = Date()
        // ~20 Hz max scroll work during huge TYPE dumps
        guard now.timeIntervalSince(lastFollowOutputTime) >= 0.05 else { return }
        lastFollowOutputTime = now
        guard let textView = consoleTextView,
              let scrollView = textView.enclosingScrollView else { return }
        let visible = scrollView.contentView.bounds
        let docH = scrollView.documentView?.bounds.height ?? 0
        // Within ~2 lines of the end → keep following; else leave scroll alone.
        let nearBottom = visible.maxY >= docH - 48
        if nearBottom {
            ConsoleTextView.scheduleScrollToInsertionPoint(in: textView)
        }
    }

    // MARK: - Return / commit

    @discardableResult
    private func handleReturnKey() -> Bool {
        guard !isHandlingReturn else { return true }
        isHandlingReturn = true
        defer {
            DispatchQueue.main.async {
                isHandlingReturn = false
            }
        }
        commitUserInput()
        return true
    }

    /// Submit all pending user input (single line or multi-line paste). Never splits at caret.
    private func commitUserInput() {
        guard !isRecallingHistory else { return }

        let userPortion = String(consoleText.dropFirst(protectedLength))

        if userPortion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            commitEmptyLine()
            return
        }

        let candidateLines = filteredCommandLines(from: userPortion, dropTrailingEmpty: false)
        if candidateLines.isEmpty {
            commitEmptyLine()
            return
        }

        finalizeCommittedInputLine()
        dispatchCandidateLines(candidateLines)
    }

    private func filteredCommandLines(from userPortion: String, dropTrailingEmpty: Bool) -> [String] {
        var lines = userPortion.components(separatedBy: .newlines)
        if dropTrailingEmpty,
           let last = lines.last,
           last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.removeLast()
        }
        return lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { raw in
                let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty && !t.hasPrefix("===") else { return false }
                if t == "ok>" || t.hasPrefix("ok>") { return false }
                if t == "ok" || t.hasSuffix(" ok") { return false }
                return true
            }
    }

    private func finalizeCommittedInputLine() {
        pinCaretRequest += 1
        isProgrammaticConsoleAppend = true
        if !consoleText.hasSuffix("\n") {
            consoleText += "\n"
        }
        markProtectedThroughEndOfText()
        isProgrammaticConsoleAppend = false
    }

    private func commitEmptyLine() {
        isProgrammaticConsoleAppend = true
        if !consoleText.hasSuffix("\n") {
            consoleText += "\n"
        }
        markProtectedThroughEndOfText()
        appendPrompt()
        isProgrammaticConsoleAppend = false
        keepCursorVisible(followPrompt: true)
    }

    private func dispatchCandidateLines(_ candidateLines: [String]) {
        for line in candidateLines {
            commandHistory.append(line)
            if commandHistory.count > 50 {
                commandHistory.removeFirst()
            }
        }
        historyIndex = -1

        // TZForth: \S / \s on the console stops the remainder of a multi-line paste.
        kernel.clearReplBatchStop()
        isProgrammaticConsoleAppend = true
        for line in candidateLines {
            _ = kernel.evaluate(line)
            markProtectedThroughEndOfText()
            if kernel.replBatchStopRequested {
                break
            }
        }
        kernel.clearReplBatchStop()
        if !consoleText.hasSuffix("\n") {
            consoleText += "\n"
            markProtectedThroughEndOfText()
        }
        appendPrompt()
        isProgrammaticConsoleAppend = false
        keepCursorVisible(followPrompt: true)
    }

    /// Multi-line paste ending with newline: commit without an extra Return.
    private func checkForCommandExecution(_ fullText: String) {
        guard !isRecallingHistory else { return }
        guard fullText.count > protectedLength else { return }
        let userPortion = String(fullText.dropFirst(protectedLength))

        let lines = userPortion.components(separatedBy: .newlines)
        guard let lastLine = lines.last else { return }
        let trimmedLast = lastLine.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedLast.isEmpty && lines.count >= 2 {
            let candidateLines = filteredCommandLines(from: userPortion, dropTrailingEmpty: true)
            if candidateLines.isEmpty {
                markProtected(through: fullText.count)
                return
            }
            finalizeCommittedInputLine()
            dispatchCandidateLines(candidateLines)
        }
    }

    // MARK: - History

    private func recallHistory(up: Bool) {
        guard !commandHistory.isEmpty else { return }

        if up {
            historyIndex = min(historyIndex + 1, commandHistory.count - 1)
        } else {
            historyIndex = max(historyIndex - 1, -1)
        }

        isRecallingHistory = true
        isProgrammaticConsoleAppend = true
        clearCurrentInputLine()
        if historyIndex >= 0 {
            let selected = commandHistory[commandHistory.count - 1 - historyIndex]
            consoleText += selected
        }
        isProgrammaticConsoleAppend = false
        isRecallingHistory = false
        keepCursorVisible(followPrompt: true)
    }

    private func clearCurrentInputLine() {
        if consoleText.count > protectedLength {
            consoleText = String(consoleText.prefix(protectedLength))
        }
    }

    // MARK: - Tools

    private func clearConsole() {
        isProgrammaticConsoleAppend = true
        consoleText = banner
        markProtectedThroughEndOfText()
        appendEngineOutput("cwd: \(host.logicalCurrentDirectory)\n")
        appendPrompt()
        isProgrammaticConsoleAppend = false
        keepCursorVisible(followPrompt: true)
    }

    private func presentFloadPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "fth") ?? .plainText,
            UTType(filenameExtension: "fs") ?? .plainText,
            UTType(filenameExtension: "4th") ?? .plainText,
            .plainText
        ]
        panel.directoryURL = URL(fileURLWithPath: host.logicalCurrentDirectory, isDirectory: true)
        panel.prompt = "Load"
        panel.message = "FLOAD / INCLUDE a Forth source file"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Echo then load via kernel FLOAD path (absolute path; host opens file).
        isProgrammaticConsoleAppend = true
        consoleText += "INCLUDE \(url.path)\n"
        markProtectedThroughEndOfText()
        isProgrammaticConsoleAppend = false

        commandHistory.append("INCLUDE \(url.path)")
        if commandHistory.count > 50 { commandHistory.removeFirst() }
        historyIndex = -1

        isProgrammaticConsoleAppend = true
        _ = kernel.loadFile(named: url.path)
        markProtectedThroughEndOfText()
        if !consoleText.hasSuffix("\n") {
            consoleText += "\n"
            markProtectedThroughEndOfText()
        }
        appendPrompt()
        isProgrammaticConsoleAppend = false
        keepCursorVisible(followPrompt: true)
    }

    private func presentChdirPanel() {
        // Same as bare CHDIR word (FROMLIB-aware start directory).
        isProgrammaticConsoleAppend = true
        host.presentDirectoryPicker()
        markProtectedThroughEndOfText()
        appendPrompt()
        isProgrammaticConsoleAppend = false
        keepCursorVisible(followPrompt: true)
    }

    private func presentEditPanel() {
        // Same as bare EDIT word (FROMLIB-aware start; chdir to file folder on pick).
        isProgrammaticConsoleAppend = true
        host.presentEditPicker()
        markProtectedThroughEndOfText()
        appendPrompt()
        isProgrammaticConsoleAppend = false
        keepCursorVisible(followPrompt: true)
    }
}
