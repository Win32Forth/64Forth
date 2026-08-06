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
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Notification.Name {
    static let clearConsole = Notification.Name("SixtyFourForthClearConsole")
    static let showLibraryFolder = Notification.Name("SixtyFourForthShowLibrary")
    static let showAutoloadFolder = Notification.Name("SixtyFourForthShowAutoload")
    static let showDocsFolder = Notification.Name("SixtyFourForthShowDocs")
    static let toolsFload = Notification.Name("SixtyFourForthToolsFload")
    static let toolsChdir = Notification.Name("SixtyFourForthToolsChdir")
    static let toolsEdit = Notification.Name("SixtyFourForthToolsEdit")
    /// File → Save (⌘S) while SZ-EDITOR is active → inject save key (19).
    static let fileSave = Notification.Name("SixtyFourForthFileSave")
    /// File → Close (⌘W) while SZ-EDITOR is active → inject quit-editor key (17).
    /// Must not quit the app; ⌘Q does that.
    static let fileClose = Notification.Name("SixtyFourForthFileClose")
    /// Phase 5: ⌘E — VIEW word under console caret (if SZ-EDITOR is loaded).
    static let viewWordUnderCursor = Notification.Name("SixtyFourForthViewWordUnderCursor")
    /// SZ-EDITOR: ⌘← / ⌘→ — prev/next occurrence of word under cursor (same file).
    static let editorFindPrev = Notification.Name("SixtyFourForthEditorFindPrev")
    static let editorFindNext = Notification.Name("SixtyFourForthEditorFindNext")
    /// SZ-EDITOR: ⌘X / ⌘C / ⌘V
    static let editorCut = Notification.Name("SixtyFourForthEditorCut")
    static let editorCopy = Notification.Name("SixtyFourForthEditorCopy")
    static let editorPaste = Notification.Name("SixtyFourForthEditorPaste")
    /// SZ-EDITOR / idle: ⌘PgUp / ⌘PgDn — Hyper prev/next hit.
    static let hyperPrev = Notification.Name("SixtyFourForthHyperPrev")
    static let hyperNext = Notification.Name("SixtyFourForthHyperNext")
}

private let banner = "=== 64Forth 1.0.5 ===\n"

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
    #if os(macOS)
    @State private var consoleTextView: NSTextView?
    #else
    @State private var consoleTextView: UITextView?
    #endif
    /// Throttle auto-scroll while engine output streams.
    @State private var lastFollowOutputTime = Date.distantPast

    @FocusState private var isFocused: Bool

    private let host = FileHost.shared
    private let kernel = KernelBridge.shared

    var body: some View {
        // Split modifiers so the type-checker does not time out on one huge chain.
        applyToolNotifications(to: applyEditorNotifications(to: consoleBase))
    }

    private var consoleBase: some View {
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
            onCommandClickUTF16: { idx in
                handleViewWordAtConsoleUTF16(idx)
            },
            onTextViewReady: { textView in
                DispatchQueue.main.async {
                    consoleTextView = textView
                }
            }
        )
        .focused($isFocused)
        .onAppear(perform: handleConsoleAppear)
        .onChange(of: consoleText) { oldValue, newValue in
            handleConsoleTextChange(oldValue: oldValue, newValue: newValue)
        }
    }

    private func handleConsoleAppear() {
        isFocused = true
        kernel.onEmit = { chunk in
            appendEngineOutput(chunk)
        }
        // Facility terminal (PAGE/AT-XY): replace console body with grid paint.
        kernel.onTerminalRefresh = { screen in
            isProgrammaticConsoleAppend = true
            consoleText = kernel.facilityPaintPrefix + screen
            if !consoleText.hasSuffix("\n") {
                consoleText += "\n"
            }
            markProtectedThroughEndOfText()
            keepCursorVisible(followPrompt: true)
            DispatchQueue.main.async {
                isProgrammaticConsoleAppend = false
                // Reverse-video insert point (TZForth facility cursor).
                applyFacilityCursorHighlight()
            }
        }
        // Startup: banner → cwd + blank line → AutoLoad → host prompt.
        isProgrammaticConsoleAppend = true
        appendEngineOutput("cwd: \(host.logicalCurrentDirectory)\n\n")
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

    private func handleConsoleTextChange(oldValue: String, newValue: String) {
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
        // Facility PAGE/AT-XY paints replace the whole console body each frame.
        if kernel.isFacilityTerminalActive {
            keepCursorVisible()
            applyFacilityCursorHighlight()
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

    /// Editor / Hyper menu shortcuts (split from `body` for the type-checker).
    private func applyEditorNotifications<Content: View>(to content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .clearConsole)) { _ in
                clearConsole()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fileSave)) { _ in
                handleFileSave()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fileClose)) { _ in
                handleFileClose()
            }
            .onReceive(NotificationCenter.default.publisher(for: .viewWordUnderCursor)) { _ in
                handleViewWordUnderCursor()
            }
            .onReceive(NotificationCenter.default.publisher(for: .editorFindPrev)) { _ in
                handleEditorFind(prev: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .editorFindNext)) { _ in
                handleEditorFind(prev: false)
            }
            .onReceive(NotificationCenter.default.publisher(for: .editorCut)) { _ in
                _ = kernel.pushEditorClipboardKey("x")
            }
            .onReceive(NotificationCenter.default.publisher(for: .editorCopy)) { _ in
                _ = kernel.pushEditorClipboardKey("c")
            }
            .onReceive(NotificationCenter.default.publisher(for: .editorPaste)) { _ in
                _ = kernel.pushEditorClipboardKey("v")
            }
            .onReceive(NotificationCenter.default.publisher(for: .hyperPrev)) { _ in
                handleHyperNav(prev: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .hyperNext)) { _ in
                handleHyperNav(prev: false)
            }
    }

    /// Tools menu / folder notifications.
    private func applyToolNotifications<Content: View>(to content: Content) -> some View {
        content
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
        // Show data-stack depth so residual cells after prior work are obvious
        // (e.g. before FLOAD Hayes / ANS-VALIDATE). Format: ok(0)>
        let n = kernel.dataStackDepth
        appendEngineOutput("ok(\(n))> ")
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
    private func maybeFollowOutputIfNearBottom() {
        let now = Date()
        // ~20 Hz max scroll work during huge TYPE dumps
        guard now.timeIntervalSince(lastFollowOutputTime) >= 0.05 else { return }
        lastFollowOutputTime = now
        guard let textView = consoleTextView else { return }
        #if os(macOS)
        guard let scrollView = textView.enclosingScrollView else { return }
        let visible = scrollView.contentView.bounds
        let docH = scrollView.documentView?.bounds.height ?? 0
        // Within ~2 lines of the end → keep following; else leave scroll alone.
        let nearBottom = visible.maxY >= docH - 48
        #else
        let visible = textView.bounds
        let contentH = textView.contentSize.height
        let nearBottom = textView.contentOffset.y + visible.height >= contentH - 48
        #endif
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
                if t == "ok>" || t.hasPrefix("ok>") || t.hasPrefix("ok(") { return false }
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
        handleSzEditorOpenRequestIfNeeded()
        if !consoleText.hasSuffix("\n") {
            consoleText += "\n"
            markProtectedThroughEndOfText()
        }
        appendPrompt()
        isProgrammaticConsoleAppend = false
        keepCursorVisible(followPrompt: true)
    }

    /// Bare SZEDIT / SZ-HOST-REQUEST-OPEN → open panel, then enter SZ-EDITOR.
    private func handleSzEditorOpenRequestIfNeeded() {
        guard kernel.takeSzEditorOpenRequest() else { return }
        let startDir = kernel.szEditorOpenStartDirectory
            ?? URL(fileURLWithPath: host.logicalCurrentDirectory, isDirectory: true)
        kernel.szEditorOpenStartDirectory = nil

        presentSzEditorOpenPanel(startDirectory: startDir) { url in
            guard let url else {
                self.appendEngineOutput("(SZEDIT cancelled)\n")
                self.markProtectedThroughEndOfText()
                return
            }
            self.isProgrammaticConsoleAppend = true
            _ = self.kernel.openInSzEditor(path: url.path)
            self.markProtectedThroughEndOfText()
            if !self.consoleText.hasSuffix("\n") {
                self.consoleText += "\n"
                self.markProtectedThroughEndOfText()
            }
            self.appendPrompt()
            self.isProgrammaticConsoleAppend = false
            self.keepCursorVisible(followPrompt: true)
        }
    }

    private func presentSzEditorOpenPanel(
        startDirectory: URL,
        completion: @escaping (URL?) -> Void
    ) {
        #if !os(macOS)
        appendEngineOutput("? SZEDIT open panel not available on iOS; use SZEDIT with a path\n")
        markProtectedThroughEndOfText()
        completion(nil)
        return
        #else
        let work = {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [
                UTType(filenameExtension: "fth") ?? .plainText,
                UTType(filenameExtension: "fs") ?? .plainText,
                UTType(filenameExtension: "4th") ?? .plainText,
                UTType(filenameExtension: "txt") ?? .plainText,
                .plainText,
                .text
            ]
            panel.prompt = "Open"
            panel.message = "SZ-EDITOR — open a file to edit"
            panel.directoryURL = startDirectory
            if panel.runModal() == .OK, let url = panel.url {
                completion(url)
            } else {
                completion(nil)
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
        #endif
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
        appendEngineOutput("cwd: \(host.logicalCurrentDirectory)\n\n")
        appendPrompt()
        isProgrammaticConsoleAppend = false
        keepCursorVisible(followPrompt: true)
    }

    // MARK: - File menu while SZ-EDITOR is open (⌘S / ⌘W)

    /// ⌘S — inject save (code 19 = SZ-CTRL-S) into the editor KEY loop.
    private func handleFileSave() {
        guard kernel.isEvaluating, kernel.isFacilityTerminalActive else {
            appendEngineOutput("? Save: open a file in SZ-EDITOR first (SZEDIT)\n")
            markProtectedThroughEndOfText()
            return
        }
        kernel.pushKey(19)
    }

    /// ⌘W — close the editor only (code 17 = SZ-CTRL-Q → SZ-DO-QUIT), not the app.
    private func handleFileClose() {
        guard kernel.isEvaluating, kernel.isFacilityTerminalActive else {
            // Not in editor: ignore (must not quit the window/app; use ⌘Q to quit).
            return
        }
        kernel.pushKey(17)
    }

    /// ⌘← / ⌘→ — same-file find prev/next (menu key-equivalent path; same as ⌘S).
    private func handleEditorFind(prev: Bool) {
        guard kernel.isEvaluating, kernel.isFacilityTerminalActive else { return }
        kernel.pushKey(prev ? 20 : 21) // SZ-FIND-PREV / SZ-FIND-NEXT
    }

    /// ⌘PgUp / ⌘PgDn — Hyper prev/next (menu key-equivalent when possible).
    private func handleHyperNav(prev: Bool) {
        if kernel.isEvaluating, kernel.isFacilityTerminalActive {
            kernel.pushKey(prev ? 26 : 27) // SZ-HYPER-PREV / SZ-HYPER-NEXT
            return
        }
        guard !kernel.isEvaluating else { return }
        _ = kernel.evaluate(prev ? "HYPER-PREV" : "HYPER-NEXT")
    }

    /// Phase 5 ⌘E: VIEW word under caret (console), or inject editor key if SZ-EDITOR up.
    private func handleViewWordUnderCursor() {
        if kernel.isEvaluating, kernel.isFacilityTerminalActive {
            kernel.pushKey(18) // SZ-VIEW-UNDER
            return
        }
        guard !kernel.isEvaluating else { return }
        #if os(macOS)
        guard let tv = consoleTextView else { return }
        var idx = tv.selectedRange().location
        let ns = tv.string as NSString
        if idx > ns.length { idx = ns.length }
        viewForthToken(at: idx, in: ns, placingCaretIn: tv)
        #endif
    }

    /// Console ⌘-click: VIEW word under the click (same as ⌘E on that token).
    private func handleViewWordAtConsoleUTF16(_ idx: Int) {
        guard !kernel.isEvaluating else { return }
        #if os(macOS)
        guard let tv = consoleTextView else { return }
        let ns = tv.string as NSString
        viewForthToken(at: idx, in: ns, placingCaretIn: tv)
        #endif
    }

    private func viewForthToken(at idx: Int, in ns: NSString, placingCaretIn tv: NSTextView) {
        #if os(macOS)
        var i = idx
        if i > ns.length { i = ns.length }
        guard let word = Self.forthToken(at: i, in: ns), !word.isEmpty else { return }
        tv.setSelectedRange(NSRange(location: min(i, ns.length), length: 0))
        let escaped = word
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        _ = kernel.evaluate("S\" \(escaped)\" HYPER-VIEW-CU")
        #endif
    }

    /// Whitespace-delimited token containing UTF-16 index `idx` (Forth-ish name).
    private static func forthToken(at idx: Int, in ns: NSString) -> String? {
        guard ns.length > 0 else { return nil }
        var i = min(max(0, idx), ns.length)
        func isSep(_ c: unichar) -> Bool {
            c == 32 || c == 9 || c == 10 || c == 13
        }
        if i > 0 && i < ns.length && isSep(ns.character(at: i)) {
            i -= 1
        }
        if i >= ns.length { i = ns.length - 1 }
        if isSep(ns.character(at: i)) { return nil }
        var lo = i
        var hi = i + 1
        while lo > 0 && !isSep(ns.character(at: lo - 1)) { lo -= 1 }
        while hi < ns.length && !isSep(ns.character(at: hi)) { hi += 1 }
        let token = ns.substring(with: NSRange(location: lo, length: hi - lo))
        return token.isEmpty ? nil : token
    }

    /// TZForth-style reverse-video cell at the Facility cursor (editor insert point).
    private func applyFacilityCursorHighlight() {
        guard kernel.isFacilityTerminalActive else { return }
        #if os(macOS)
        guard let textView = consoleTextView, let storage = textView.textStorage else { return }

        let full = NSRange(location: 0, length: storage.length)
        if full.length > 0 {
            storage.removeAttribute(.backgroundColor, range: full)
            storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: full)
        }

        let prefixLen = (kernel.facilityPaintPrefix as NSString).length
        let cols = max(1, kernel.facilityCols)
        let row = kernel.facilityCursorRow
        let col = min(max(0, kernel.facilityCursorCol), cols - 1)
        // Each rendered line is `cols` ASCII glyphs + '\n'
        let loc = prefixLen + row * (cols + 1) + col
        guard loc >= 0 && loc < storage.length else { return }

        let range = NSRange(location: loc, length: 1)
        storage.addAttribute(.backgroundColor, value: NSColor.controlAccentColor, range: range)
        storage.addAttribute(.foregroundColor, value: NSColor.white, range: range)
        #else
        guard let textView = consoleTextView else { return }
        let storage = textView.textStorage
        let full = NSRange(location: 0, length: storage.length)
        if full.length > 0 {
            storage.removeAttribute(.backgroundColor, range: full)
            storage.addAttribute(.foregroundColor, value: UIColor.label, range: full)
        }
        let prefixLen = (kernel.facilityPaintPrefix as NSString).length
        let cols = max(1, kernel.facilityCols)
        let row = kernel.facilityCursorRow
        let col = min(max(0, kernel.facilityCursorCol), cols - 1)
        let loc = prefixLen + row * (cols + 1) + col
        guard loc >= 0 && loc < storage.length else { return }
        let range = NSRange(location: loc, length: 1)
        storage.addAttribute(.backgroundColor, value: UIColor.systemBlue, range: range)
        storage.addAttribute(.foregroundColor, value: UIColor.white, range: range)
        #endif
    }

    private func presentFloadPanel() {
        #if !os(macOS)
        appendEngineOutput("? FLOAD panel not available on iOS; type INCLUDE path\n")
        markProtectedThroughEndOfText()
        return
        #else
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
        #endif
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
