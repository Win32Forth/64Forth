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
    /// File → Save As… (⌘⇧S)
    static let fileSaveAs = Notification.Name("SixtyFourForthFileSaveAs")
    /// File → New (⌘N) → untitled buffer (SZ-EDITOR when active, else start editor).
    static let fileNew = Notification.Name("SixtyFourForthFileNew")
    /// File → Open… (⌘O) → open panel (into SZ-EDITOR when active, else start editor).
    static let fileOpen = Notification.Name("SixtyFourForthFileOpen")
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

// Console header. Update version when bumping MARKETING_VERSION.
// Update the date/time stamp only when finishing a change set for a version —
// just before DMG + commit/push (not on every intermediate build).
// Format: === 64Forth M.N.P === Mon D, YYYY H:MM AM/PM ===
private let banner = "=== 64Forth 1.3.7 === Sep 12, 2026 10:56 AM ===\n"

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
    /// After Return while editor KEY waits, reclaim console focus when the line finishes
    /// — unless the user activated the editor window first.
    @State private var preferCommandFocusAfterEval = false
    /// ⌘-click / ⌘E VIEW: run `VIEW name` without a CR / ok>.
    @State private var suppressNextCommandPrompt = false

    @FocusState private var isFocused: Bool

    private let host = FileHost.shared
    private let kernel = KernelBridge.shared

    var body: some View {
        // Split modifiers so the type-checker does not time out on one huge chain.
        applyToolNotifications(to: applyEditorNotifications(to: consoleRoot))
    }

    /// Full-window Forth REPL. SZ-EDITOR lives in FacilityEditorHost (macOS).
    private var consoleRoot: some View {
        fullConsolePane
            .onAppear(perform: handleConsoleAppear)
            .onChange(of: isFocused) { _, focused in
                if focused {
                    kernel.setCommandPaneFocused(false)
                }
            }
    }

    private var fullConsolePane: some View {
        ConsoleTextView(
            text: $consoleText,
            isFocused: $isFocused,
            pinCaretRequest: $pinCaretRequest,
            editableStartUTF16: (protectedSnapshot as NSString).length,
            paneKind: .full,
            onReturnPressed: { handleReturnKey() },
            onHistoryUp: { recallHistory(up: true) },
            onHistoryDown: { recallHistory(up: false) },
            onKeyCharacter: { c in
                // Console typing stays in the NSTextView; facility KEY lives in
                // FacilityEditorHost. Still push for non-editor KEY waits.
                if kernel.isFacilityTerminalActive {
                    return
                }
                kernel.pushKey(c)
            },
            onCommandClickUTF16: { idx in
                handleViewWordAtConsoleUTF16(idx)
            },
            onPaneActivated: {
                isFocused = true
                kernel.setCommandPaneFocused(false)
            },
            onTextViewReady: { textView in
                DispatchQueue.main.async {
                    consoleTextView = textView
                }
            }
        )
        .focused($isFocused)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { reportConsoleGeometry(geo.size) }
                    .onChange(of: geo.size) { _, newSize in
                        reportConsoleGeometry(newSize)
                    }
            }
        )
        .onChange(of: consoleText) { oldValue, newValue in
            handleConsoleTextChange(oldValue: oldValue, newValue: newValue)
        }
    }

    /// Push visible console size to the kernel so SZ-SYNC-SIZE can match the window.
    private func reportConsoleGeometry(_ size: CGSize) {
        #if os(macOS)
        // Prefer live scroll/text view metrics (insets, padding, scroller).
        if let tv = consoleTextView, let sv = tv.enclosingScrollView {
            kernel.updateConsoleMetrics(scrollView: sv, textView: tv)
            return
        }
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        kernel.updateConsoleVisibleSize(size, font: font)
        #else
        kernel.updateConsoleVisibleSize(size, font: nil)
        #endif
    }

    private func handleConsoleAppear() {
        isFocused = true
        kernel.onEmit = { chunk in
            // Full Console REPL only (never App Output; never in-console facility grid).
            self.appendEngineOutput(chunk)
        }
        // After SZ-DO-CONSOLE-LINE finishes EVALUATE, host appends ok(n)> .
        kernel.onCommandLineDone = {
            if self.suppressNextCommandPrompt {
                self.suppressNextCommandPrompt = false
                self.preferCommandFocusAfterEval = false
                _ = self.kernel.consumeForceCommandFocusAfterDebug()
                return
            }
            if !self.consoleText.hasSuffix("\n") {
                self.appendEngineOutput("\n")
            }
            let n = self.kernel.dataStackDepth
            self.appendEngineOutput("ok(\(n))> ")
            let forceAfterDebug = self.kernel.consumeForceCommandFocusAfterDebug()
            let prefer = self.preferCommandFocusAfterEval
            self.preferCommandFocusAfterEval = false
            guard prefer || forceAfterDebug else { return }
            self.pinCaretRequest += 1
            self.isFocused = true
            self.kernel.setCommandPaneFocused(false)
            #if os(macOS)
            func claimConsoleFocus(attempts: Int) {
                guard attempts > 0 else { return }
                if let tv = self.consoleTextView, let win = tv.window {
                    win.makeKeyAndOrderFront(nil)
                    win.makeFirstResponder(tv)
                    let end = (tv.string as NSString).length
                    tv.setSelectedRange(NSRange(location: end, length: 0))
                }
                if attempts > 1 {
                    DispatchQueue.main.async {
                        claimConsoleFocus(attempts: attempts - 1)
                    }
                }
            }
            claimConsoleFocus(attempts: 3)
            #endif
        }
        kernel.onSaveAsPanelRequest = { [self] in
            handleFileSaveAs()
        }
        // ⌘O while KEY waits (stolen in key monitor — avoid deferred menu stacking).
        kernel.onOpenPanelRequest = { [self] in
            handleFileOpen()
        }
        // ⌘E / Tools→VIEW: direct hook (same deferral trap as File→Open).
        kernel.onViewWordUnderCursor = { [self] in
            handleViewWordUnderCursor()
        }
        kernel.onTerminalRefresh = { _ in
            // Ignore late paints after FACILITY-OFF (race with async exit).
            guard FacilityTerminal.shared.isActive else { return }
            // SZ-EDITOR window only; Console stays a full REPL.
            #if os(macOS)
            FacilityEditorHost.shared.presentFromRefresh()
            #endif
        }
        // FACILITY-OFF / editor Cmd-W: close dedicated editor window.
        // Do not rewrite the console transcript.
        kernel.onFacilityExit = {
            #if os(macOS)
            FacilityEditorHost.shared.close()
            #endif
            kernel.setCommandPaneFocused(false)
            kernel.setFacilityEmitBypass(false)
        }
        // Forth `CLS` / Tools menu: clear host console (not editor exit).
        kernel.onHostClearConsole = {
            self.clearConsole()
        }
        // Startup: banner → cwd + blank line → AutoLoad → host prompt.
        isProgrammaticConsoleAppend = true
        appendEngineOutput("Working folder: \(host.logicalCurrentDirectory)\n\n")
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
            .onReceive(NotificationCenter.default.publisher(for: .fileSaveAs)) { _ in
                handleFileSaveAs()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fileNew)) { _ in
                handleFileNew()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fileOpen)) { _ in
                handleFileOpen()
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
            // User edits (arrows + backspace) must not pin the caret at EOL.
            ConsoleTextView.scheduleScrollToInsertionPoint(in: textView, pinCaret: followPrompt)
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
        // Stage console line into the editor KEY loop (key 133 /
        // SZ-DO-CONSOLE-LINE) — never nested host evaluate.
        if kernel.isFacilityTerminalActive, kernel.isEvaluating {
            return submitConsoleLineWhileEditorKeyWaits()
        }
        if kernel.isFacilityTerminalActive || kernel.isEvaluating {
            return true
        }
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

    /// Full-console Return while SZ-EDITOR KEY waits.
    private func submitConsoleLineWhileEditorKeyWaits() -> Bool {
        #if os(macOS)
        if let tv = consoleTextView {
            consoleText = tv.string
        }
        #endif
        let prot = min(protectedLength, consoleText.count)
        let user = String(consoleText.dropFirst(prot))
        let line = user.trimmingCharacters(in: .whitespacesAndNewlines)

        isProgrammaticConsoleAppend = true
        if !consoleText.hasSuffix("\n") {
            consoleText += "\n"
        }
        markProtectedThroughEndOfText()
        isProgrammaticConsoleAppend = false

        if line.isEmpty {
            appendPrompt()
            return true
        }

        commandHistory.append(line)
        if commandHistory.count > 50 {
            commandHistory.removeFirst()
        }
        historyIndex = -1

        preferCommandFocusAfterEval = true
        if !kernel.submitCommandLineFromPane(line) {
            preferCommandFocusAfterEval = false
            appendEngineOutput("(command submit failed)\n")
            appendPrompt()
        }
        isFocused = true
        kernel.setCommandPaneFocused(false)
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
            ?? kernel.editorOpenStartDirectory()
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
        // Single-flight: extra ⌘O while a panel is up/queued must not stack.
        guard kernel.beginEditorFilePanel() else { return }
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
            let url: URL?
            if panel.runModal() == .OK {
                url = panel.url
            } else {
                url = nil
            }
            self.kernel.endEditorFilePanel()
            completion(url)
        }
        // While SZ-EDITOR KEY waits, never nest runModal inside nextEvent/sendEvent
        // (that looked dead and stacked deferred menu opens). Idle console: run
        // sync so Open → openInSzEditor happens on the same turn (async idle path
        // showed the panel but never entered the editor after OK).
        if kernel.isEvaluating {
            DispatchQueue.main.async(execute: work)
        } else if Thread.isMainThread {
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
        appendEngineOutput("Working folder: \(host.logicalCurrentDirectory)\n\n")
        appendPrompt()
        isProgrammaticConsoleAppend = false
        keepCursorVisible(followPrompt: true)
    }

    // MARK: - File menu (⌘O / ⌘S / ⌘W)

    /// ⌘O / File→Open… — panel starts at current file folder, FROMLIB Library, or cwd.
    private func handleFileOpen() {
        #if os(macOS)
        let startDir = kernel.editorOpenStartDirectory()
        if kernel.isEvaluating, kernel.isFacilityTerminalActive {
            // In SZ-EDITOR KEY loop: stage path + push key 30 (SZ-CMD-OPEN).
            presentSzEditorOpenPanel(startDirectory: startDir) { url in
                guard let url else { return }
                self.kernel.stageEditorOpenPath(url.path)
                _ = self.kernel.pushKey(30)
            }
            return
        }
        if kernel.isEvaluating {
            // Busy with non-editor work — don't nest.
            appendEngineOutput("? Open: finish the current command first\n")
            markProtectedThroughEndOfText()
            return
        }
        // Idle console: open panel then enter SZ-EDITOR (same as bare SZEDIT).
        presentSzEditorOpenPanel(startDirectory: startDir) { url in
            guard let url else { return }
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
        #else
        appendEngineOutput("? Open panel not available on iOS\n")
        markProtectedThroughEndOfText()
        #endif
    }

    private func presentSzEditorSavePanel(
        startDirectory: URL,
        suggestedName: String,
        completion: @escaping (URL?) -> Void
    ) {
        #if !os(macOS)
        appendEngineOutput("? Save As panel not available on iOS\n")
        markProtectedThroughEndOfText()
        completion(nil)
        return
        #else
        guard kernel.beginEditorFilePanel() else { return }
        let work = {
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.allowedContentTypes = [
                UTType(filenameExtension: "fth") ?? .plainText,
                UTType(filenameExtension: "fs") ?? .plainText,
                UTType(filenameExtension: "4th") ?? .plainText,
                UTType(filenameExtension: "txt") ?? .plainText,
                .plainText
            ]
            panel.nameFieldStringValue = suggestedName
            panel.title = "Save Forth File"
            panel.message = "SZ-EDITOR — Save As (default extension .fth)"
            panel.prompt = "Save"
            panel.directoryURL = startDirectory
            let url: URL?
            if panel.runModal() == .OK {
                url = panel.url
            } else {
                url = nil
            }
            self.kernel.endEditorFilePanel()
            completion(url)
        }
        DispatchQueue.main.async(execute: work)
        #endif
    }

    /// ⌘N / File→New — untitled buffer. Editor KEY: 31. Idle: SZ-EDIT-NEW.
    private func handleFileNew() {
        if kernel.isEvaluating, kernel.isFacilityTerminalActive {
            kernel.pushKey(31)
            return
        }
        if kernel.isEvaluating {
            appendEngineOutput("? New: finish the current command first\n")
            markProtectedThroughEndOfText()
            return
        }
        _ = kernel.evaluate("ALSO EDITOR SZ-EDIT-NEW PREVIOUS")
    }

    /// ⌘S — inject save (code 19 = SZ-CTRL-S) into the editor KEY loop.
    private func handleFileSave() {
        guard kernel.isEvaluating, kernel.isFacilityTerminalActive else {
            appendEngineOutput("? Save: open a file in SZ-EDITOR first (SZEDIT)\n")
            markProtectedThroughEndOfText()
            return
        }
        kernel.pushKey(19)
    }

    /// ⌘⇧S / File→Save As… — always pick a path (copy of the current buffer).
    private func handleFileSaveAs() {
        guard kernel.isEvaluating, kernel.isFacilityTerminalActive else {
            appendEngineOutput("? Save As: open a file in SZ-EDITOR first\n")
            markProtectedThroughEndOfText()
            return
        }
        presentSzEditorSavePanel(
            startDirectory: kernel.editorOpenStartDirectory(),
            suggestedName: kernel.editorSuggestedSaveName()
        ) { url in
            guard let url else { return }
            self.kernel.stageEditorOpenPath(url.path)
            _ = self.kernel.pushKey(35)
        }
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

    /// ⌘E: VIEW word under caret — console transcript, or editor caret when editor is key.
    private func handleViewWordUnderCursor() {
        #if os(macOS)
        // Console key while editor KEY waits: VIEW token in the REPL transcript.
        if kernel.isEvaluating, kernel.isFacilityTerminalActive,
           !FacilityEditorHost.shared.isKeyWindowActive,
           let tv = consoleTextView {
            var idx = tv.selectedRange().location
            let ns = tv.string as NSString
            if idx > ns.length { idx = ns.length }
            viewForthToken(at: idx, in: ns, placingCaretIn: tv)
            return
        }
        #endif
        if kernel.isEvaluating, kernel.isFacilityTerminalActive {
            kernel.pushKey(18) // SZ-VIEW-UNDER (word under facility caret)
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

    /// Console ⌘-click: VIEW word under the click.
    private func handleViewWordAtConsoleUTF16(_ idx: Int) {
        #if os(macOS)
        guard let tv = consoleTextView else { return }
        let ns = tv.string as NSString
        viewForthToken(at: idx, in: ns, placingCaretIn: tv)
        #endif
    }

    /// Open Hyper VIEW for the token at `idx`. While the editor KEY loop is active,
    /// stages the line via key 133 (no nested host evaluate). Idle: host evaluate.
    ///
    /// Uses FORTH `VIEW name` (not `S" name" HYPER-VIEW-CU`). `HYPER-VIEW-CU` /
    /// `(VIEW)` live in SYSVOC after Hyper load, so a bare `HYPER-VIEW-CU` is
    /// `undefined` under ONLY FORTH and leaves the string on the stack (+2 depth).
    /// `VIEW` stays in FORTH and already calls `(VIEW)` by XT.
    private func viewForthToken(at idx: Int, in ns: NSString, placingCaretIn tv: NSTextView) {
        #if os(macOS)
        var i = idx
        if i > ns.length { i = ns.length }
        guard let word = Self.forthToken(at: i, in: ns), !word.isEmpty else { return }
        // PARSE-NAME stops at blank; reject whitespace-tainted tokens.
        guard word.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return }
        tv.setSelectedRange(NSRange(location: min(i, ns.length), length: 0))
        let line = "VIEW \(word)"

        if kernel.isEvaluating, kernel.isFacilityTerminalActive {
            // Safe while KEY waits. Silent: no CR/ok> / scroll.
            suppressNextCommandPrompt = true
            preferCommandFocusAfterEval = false
            if !kernel.submitCommandLineFromPane(line) {
                suppressNextCommandPrompt = false
                appendEngineOutput("(VIEW submit failed)\n")
                appendPrompt()
            }
            return
        }
        guard !kernel.isEvaluating else { return }

        isProgrammaticConsoleAppend = true
        _ = kernel.evaluate(line)
        // evaluate blocks until the editor exits; console transcript was never overwritten.
        if !kernel.isFacilityTerminalActive {
            ensureInputPrompt()
        }
        isProgrammaticConsoleAppend = false
        keepCursorVisible(followPrompt: true)
        #endif
    }

    /// After facility restore / console VIEW: make sure the user can type.
    /// Pre-facility snapshot usually already ends with `ok(n)> `; do not double it.
    private func ensureInputPrompt() {
        if consoleText.hasSuffix("> ") { return }
        isProgrammaticConsoleAppend = true
        if !consoleText.isEmpty && !consoleText.hasSuffix("\n") {
            consoleText += "\n"
            markProtectedThroughEndOfText()
        }
        appendPrompt()
        isProgrammaticConsoleAppend = false
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
