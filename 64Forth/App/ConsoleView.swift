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
private let banner = "=== 64Forth 1.2.1 === Aug 31, 2026 11:04 PM ===\n"

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
    @State private var commandTextView: NSTextView?
    #else
    @State private var consoleTextView: UITextView?
    @State private var commandTextView: UITextView?
    #endif
    /// Throttle auto-scroll while engine output streams.
    @State private var lastFollowOutputTime = Date.distantPast
    /// Console body when the editor first opened (seed + fallback if command pane is empty).
    @State private var preFacilityConsole: String?

    /// Phase 1 split: facility editor (upper) + scrollable command pane (lower).
    @State private var isEditorSplitActive = false
    @State private var commandText = ""
    @State private var commandProtectedLength = 0
    @State private var commandProtectedSnapshot = ""
    @State private var isProgrammaticCommandAppend = false
    @State private var isRevertingCommandProtected = false
    @State private var commandPinCaretRequest = 0
    @State private var commandHistoryIndex = -1
    /// After Return in the command pane, restore command focus when the line finishes
    /// — unless the user clicked the facility editor first (cleared in onPaneActivated).
    @State private var preferCommandFocusAfterEval = false
    /// ⌘-click / ⌘E VIEW from the command pane: run HYPER-VIEW-CU without a CR / ok>
    /// (and without scrolling the transcript to a new prompt).
    @State private var suppressNextCommandPrompt = false
    /// Throttle live scroll work during huge command-pane TYPE dumps (~20 Hz).
    @State private var lastCommandFollowOutputTime = Date.distantPast

    @FocusState private var isFocused: Bool
    @FocusState private var isCommandFocused: Bool

    private let host = FileHost.shared
    private let kernel = KernelBridge.shared

    var body: some View {
        // Split modifiers so the type-checker does not time out on one huge chain.
        applyToolNotifications(to: applyEditorNotifications(to: consoleRoot))
    }

    /// Single full console when idle; VSplitView when SZ-EDITOR facility is active.
    private var consoleRoot: some View {
        Group {
            if isEditorSplitActive {
                splitEditorAndCommand
            } else {
                fullConsolePane
            }
        }
        .onAppear(perform: handleConsoleAppear)
        // Sticky command-focus is set only by pane click / Return / onCommandLineDone.
        // Do not drive it from FocusState — ok> and SwiftUI thrash re-asserted
        // command focus after editor click-back and left KEY dead.
        .onChange(of: isCommandFocused) { _, focused in
            if !focused {
                kernel.setCommandPaneFocused(false)
            }
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                kernel.setCommandPaneFocused(false)
            }
        }
    }

    #if os(macOS)
    private var splitEditorAndCommand: some View {
        // Custom NSSplitView: 5pt divider (gray/white/black/white/gray) for easy grab.
        EditorCommandSplitView {
            facilityPane
                .frame(minHeight: 160)
        } bottom: {
            commandPane
                .frame(minHeight: 72)
                .frame(idealHeight: 100)
        }
    }
    #else
    private var splitEditorAndCommand: some View {
        VStack(spacing: 0) {
            facilityPane
                .frame(minHeight: 160)
            Divider()
            commandPane
                .frame(minHeight: 72, idealHeight: 100)
        }
    }
    #endif

    /// Upper: facility grid (existing console text binding while editor is open).
    private var facilityPane: some View {
        ConsoleTextView(
            text: $consoleText,
            isFocused: $isFocused,
            pinCaretRequest: $pinCaretRequest,
            editableStartUTF16: (protectedSnapshot as NSString).length,
            paneKind: .facility,
            onReturnPressed: { handleFacilityReturnKey() },
            onHistoryUp: { },
            onHistoryDown: { },
            onKeyCharacter: { c in
                kernel.pushKey(c)
            },
            onCommandClickUTF16: { idx in
                handleViewWordAtConsoleUTF16(idx)
            },
            onPaneActivated: {
                // Leave command pane completely so KEY monitor + caret return to editor.
                // Update FocusState synchronously so the command pane's updateNSView
                // does not immediately re-steal first responder on the next frame.
                preferCommandFocusAfterEval = false
                isCommandFocused = false
                isFocused = true
                kernel.setCommandPaneFocused(false)
                #if os(macOS)
                if let tv = consoleTextView, let win = tv.window {
                    win.makeFirstResponder(tv)
                }
                applyFacilityCursorHighlight()
                #endif
            },
            onTextViewReady: { textView in
                DispatchQueue.main.async {
                    consoleTextView = textView
                }
            }
        )
        .id("facilityPane")
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

    /// Lower: scrollable Forth command transcript + input (Option A phase 1).
    private var commandPane: some View {
        ConsoleTextView(
            text: $commandText,
            isFocused: $isCommandFocused,
            pinCaretRequest: $commandPinCaretRequest,
            editableStartUTF16: (commandProtectedSnapshot as NSString).length,
            paneKind: .command,
            onReturnPressed: { handleCommandPaneReturn() },
            onHistoryUp: { recallCommandHistory(up: true) },
            onHistoryDown: { recallCommandHistory(up: false) },
            onKeyCharacter: { _ in
                // Keys are typed into this text view; do not push into editor KEY.
            },
            onCommandClickUTF16: { idx in
                handleViewWordAtCommandUTF16(idx)
            },
            onPaneActivated: {
                // Idempotent — do not bump pinCaret on every responder pulse (beach ball).
                isFocused = false
                let already = isCommandFocused
                isCommandFocused = true
                if !already {
                    commandPinCaretRequest += 1
                }
                kernel.setCommandPaneFocused(true)
                #if os(macOS)
                if let tv = commandTextView, let win = tv.window {
                    win.makeFirstResponder(tv)
                }
                (consoleTextView as? ConsoleNSTextView)?.hideFacilityLineCaret()
                #endif
            },
            onTextViewReady: { textView in
                DispatchQueue.main.async {
                    commandTextView = textView
                }
            }
        )
        .id("commandPane")
        .focused($isCommandFocused)
        .onChange(of: commandText) { oldValue, newValue in
            handleCommandTextChange(oldValue: oldValue, newValue: newValue)
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
                kernel.pushKey(c)
            },
            onCommandClickUTF16: { idx in
                handleViewWordAtConsoleUTF16(idx)
            },
            onPaneActivated: {
                isFocused = true
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
            // Only the live split owns the lower pane. Between PAGE (facility on)
            // and the first TERMINAL-REFRESH, keep writing consoleText so seed can
            // capture the full pre-editor transcript. Routing to commandText early
            // left the lower pane empty (or only post-PAGE crumbs) and skipped seed.
            if self.isEditorSplitActive {
                self.appendCommandOutput(chunk)
            } else {
                self.appendEngineOutput(chunk)
            }
        }
        // After SZ-DO-CONSOLE-LINE finishes EVALUATE, host appends ok(n)> .
        kernel.onCommandLineDone = {
            guard self.isEditorSplitActive else { return }
            // Silent VIEW from ⌘-click / ⌘E: no CR/ok> and no scroll.
            if self.suppressNextCommandPrompt {
                self.suppressNextCommandPrompt = false
                self.preferCommandFocusAfterEval = false
                _ = self.kernel.consumeForceCommandFocusAfterDebug()
                return
            }
            // Always append the prompt in the lower pane (never facility/consoleText).
            if !self.commandText.hasSuffix("\n") {
                self.appendCommandOutput("\n")
            }
            let n = self.kernel.dataStackDepth
            self.appendCommandOutput("ok(\(n))> ")
            // Reclaim command focus if Return left prefer set, or DBG just ended
            // (facility click while stepping clears prefer; still want the prompt).
            let forceAfterDebug = self.kernel.consumeForceCommandFocusAfterDebug()
            let prefer = self.preferCommandFocusAfterEval
            self.preferCommandFocusAfterEval = false
            guard prefer || forceAfterDebug else { return }
            self.commandPinCaretRequest += 1
            self.isCommandFocused = true
            self.isFocused = false
            self.kernel.setCommandPaneFocused(true)
            #if os(macOS)
            (self.consoleTextView as? ConsoleNSTextView)?.hideFacilityLineCaret()
            // After SZ-REDRAW / Files restore, re-assert FR on the next turns so a
            // racing facility paint cannot leave the caret stranded in the editor.
            func claimCommandFocus(attempts: Int) {
                guard attempts > 0 else { return }
                guard self.kernel.isCommandPaneFocused else { return }
                if let tv = self.commandTextView, let win = tv.window {
                    win.makeFirstResponder(tv)
                    let end = (tv.string as NSString).length
                    tv.setSelectedRange(NSRange(location: end, length: 0))
                }
                if attempts > 1 {
                    DispatchQueue.main.async {
                        claimCommandFocus(attempts: attempts - 1)
                    }
                }
            }
            claimCommandFocus(attempts: 3)
            #endif
        }
        // Facility terminal (PAGE/AT-XY): replace upper pane with grid paint.
        kernel.onSaveAsPanelRequest = { [self] in
            handleFileSaveAs()
        }
        // ⌘O while KEY waits (stolen in key monitor — avoid deferred menu stacking).
        kernel.onOpenPanelRequest = { [self] in
            handleFileOpen()
        }
        kernel.onTerminalRefresh = { screen in
            // Ignore late paints after FACILITY-OFF (race with async exit).
            guard FacilityTerminal.shared.isActive else { return }
            isProgrammaticConsoleAppend = true
            // First paint: seed the lower command pane with the live console
            // transcript (banner / cwd / AutoLoad / ok>), then put the grid above.
            // On close we restore from the command pane (or this snapshot).
            if !isEditorSplitActive {
                let seed = capturePreFacilityConsoleTranscript()
                preFacilityConsole = seed
                beginEditorSplit(seedingFrom: seed)
            }
            // Pure facility grid only — no paint prefix, no host ok> lines.
            // A stray ok(0)> above the splitter breaks cell hit-testing (find field,
            // caret placement) because UTF-16 → (col,row) assumes a pure grid.
            kernel.facilityPaintPrefix = ""
            var grid = screen
            // Defensive: strip any host prompt that may have been concatenated.
            if grid.hasPrefix("ok(") || grid.contains("\nok(") {
                grid = grid
                    .components(separatedBy: .newlines)
                    .filter { line in
                        let t = line.trimmingCharacters(in: .whitespaces)
                        return !(t.hasPrefix("ok(") && t.contains(")>"))
                    }
                    .joined(separator: "\n")
                if !grid.hasSuffix("\n") { grid += "\n" }
            }
            consoleText = grid
            if !consoleText.hasSuffix("\n") {
                consoleText += "\n"
            }
            markProtectedThroughEndOfText()
            // Do NOT scroll-to-end on every facility paint — that fights mouse-wheel
            // scroll (and can re-enter AppKit layout during evaluate's run-loop pump).
            DispatchQueue.main.async {
                isProgrammaticConsoleAppend = false
                // Selection reverse-video (if any) then I-beam caret.
                applyFacilitySelectionHighlight()
                applyFacilityCursorHighlight()
            }
        }
        // FACILITY-OFF / editor Cmd-W: restore REPL text so exit is obvious.
        kernel.onFacilityExit = {
            restoreConsoleAfterFacility()
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

    /// Best pre-editor console body for seeding the lower pane.
    /// Prefer the live NSTextView when it is ahead of the SwiftUI binding.
    private func capturePreFacilityConsoleTranscript() -> String {
        var seed = consoleText
        #if os(macOS)
        if let tv = consoleTextView {
            let live = tv.string
            if !live.isEmpty, live.count >= seed.count {
                seed = live
            }
        }
        #endif
        return seed
    }

    /// Enter split layout when SZ-EDITOR first paints.
    /// - Parameter seedingFrom: console transcript just before the grid replaces it
    ///   (banner, cwd, AutoLoad, `ok>`). The lower pane shows that so the editor
    ///   appears to split the console in place; on close we restore the same buffer.
    private func beginEditorSplit(seedingFrom transcript: String = "") {
        isEditorSplitActive = true
        isProgrammaticCommandAppend = true
        // Always seed on first open. `commandText` may already hold stray host
        // output that arrived after PAGE but before this paint — that must not
        // suppress the real console transcript.
        let earlyCommandIO = commandText
        var seed = transcript
        if seed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            seed = "ok(\(kernel.dataStackDepth))> "
        }
        commandText = seed
        // Keep any true post-PAGE host crumbs that are not already in the seed.
        if !earlyCommandIO.isEmpty,
           !seed.contains(earlyCommandIO),
           !earlyCommandIO.hasPrefix(seed) {
            if !commandText.hasSuffix("\n"), !earlyCommandIO.hasPrefix("\n") {
                commandText += "\n"
            }
            commandText += earlyCommandIO
        }
        // Protect before clearing programmatic flag so onChange cannot revert the seed.
        markCommandProtectedThroughEnd()
        isProgrammaticCommandAppend = false
        kernel.setCommandPaneFocused(false)
        #if os(macOS)
        // Apply seed as soon as the command text view exists. The first layout
        // may create it after this call; retry a couple of frames.
        func syncCommandTextViewSeed(attempts: Int) {
            guard attempts > 0 else { return }
            if let tv = self.commandTextView {
                if tv.string != self.commandText {
                    tv.string = self.commandText
                }
                ConsoleTextView.scrollToEndNow(in: tv)
                return
            }
            DispatchQueue.main.async {
                syncCommandTextViewSeed(attempts: attempts - 1)
            }
        }
        DispatchQueue.main.async {
            syncCommandTextViewSeed(attempts: 8)
        }
        #endif
        commandPinCaretRequest += 1
    }

    private func markCommandProtectedThroughEnd() {
        commandProtectedLength = commandText.count
        commandProtectedSnapshot = commandText
    }

    private func appendCommandOutput(_ s: String) {
        guard !s.isEmpty else { return }
        // SwiftUI / AppKit only from main (emit drain can originate on Forth queue).
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.appendCommandOutput(s) }
            return
        }
        // Hard guarantee: command-pane I/O never touches facility consoleText.
        let was = isProgrammaticCommandAppend
        isProgrammaticCommandAppend = true
        let prior = commandText
        commandText += s
        markCommandProtectedThroughEnd()
        isProgrammaticCommandAppend = was
        #if os(macOS)
        if let tv = commandTextView {
            // Append-only into the live NSTextView. Replacing `tv.string = full`
            // on every TYPE chunk resets the clip view to the top, so during a
            // long FLOAD only the first screenful stayed visible until editor exit.
            let live = tv.string
            if commandText.hasPrefix(live), commandText.count > live.count {
                let suffix = String(commandText.dropFirst(live.count))
                ConsoleTextView.appendTextPreservingScroll(suffix, to: tv)
            } else if tv.string != commandText {
                tv.string = commandText
                ConsoleTextView.scrollToEndNow(in: tv)
            } else {
                ConsoleTextView.scrollToEndNow(in: tv)
            }
            // Throttle extra async passes so the pump can keep up during huge dumps.
            let now = Date()
            if now.timeIntervalSince(lastCommandFollowOutputTime) >= 0.05
                || s.contains("\n") && s.count > 40
                || prior.isEmpty {
                lastCommandFollowOutputTime = now
                ConsoleTextView.scheduleScrollToInsertionPoint(in: tv)
            }
        }
        #endif
    }

    private func appendCommandPrompt() {
        let n = kernel.dataStackDepth
        appendCommandOutput("ok(\(n))> ")
        commandPinCaretRequest += 1
    }

    private func handleCommandTextChange(oldValue: String, newValue: String) {
        if isRevertingCommandProtected {
            isRevertingCommandProtected = false
            return
        }
        if isProgrammaticCommandAppend { return }
        if newValue.count < commandProtectedLength
            || (!commandProtectedSnapshot.isEmpty && !newValue.hasPrefix(commandProtectedSnapshot)) {
            isRevertingCommandProtected = true
            commandText = oldValue
            return
        }
    }

    /// Return in the lower command pane: stage line for Forth KEY 133 (no nested evaluate).
    private func handleCommandPaneReturn() -> Bool {
        // Prefer live text view contents (binding can lag one frame behind typing).
        #if os(macOS)
        if let tv = commandTextView {
            commandText = tv.string
        }
        #endif
        // Protected length is Character-count of the snapshot (ASCII prompts).
        let prot = min(commandProtectedLength, commandText.count)
        let user = String(commandText.dropFirst(prot))
        let line = user.trimmingCharacters(in: .whitespacesAndNewlines)
        isProgrammaticCommandAppend = true
        if !commandText.hasSuffix("\n") {
            commandText += "\n"
        }
        markCommandProtectedThroughEnd()
        isProgrammaticCommandAppend = false

        if line.isEmpty {
            appendCommandPrompt()
            return true
        }

        commandHistory.append(line)
        if commandHistory.count > 50 {
            commandHistory.removeFirst()
        }
        commandHistoryIndex = -1

        if kernel.isFacilityTerminalActive, kernel.isEvaluating {
            // Editor KEY loop: stage + wake (SZ-DO-CONSOLE-LINE → EVALUATE; host adds ok>).
            preferCommandFocusAfterEval = true
            if !kernel.submitCommandLineFromPane(line) {
                preferCommandFocusAfterEval = false
                appendCommandOutput("(command submit failed)\n")
                appendCommandPrompt()
            }
            // Keep focus so the next line can be typed after the prompt arrives.
            isCommandFocused = true
            kernel.setCommandPaneFocused(true)
        } else if !kernel.isEvaluating {
            // No editor — evaluate into the command pane (or main if not split).
            isProgrammaticCommandAppend = true
            _ = kernel.evaluate(line)
            markCommandProtectedThroughEnd()
            appendCommandPrompt()
            isProgrammaticCommandAppend = false
        } else {
            appendCommandOutput("(busy — finish current command first)\n")
            appendCommandPrompt()
        }
        return true
    }

    private func recallCommandHistory(up: Bool) {
        guard !commandHistory.isEmpty else { return }
        if up {
            commandHistoryIndex = min(commandHistoryIndex + 1, commandHistory.count - 1)
        } else {
            commandHistoryIndex = max(commandHistoryIndex - 1, -1)
        }
        isProgrammaticCommandAppend = true
        if commandText.count > commandProtectedLength {
            commandText = String(commandText.prefix(commandProtectedLength))
        }
        if commandHistoryIndex >= 0 {
            commandText += commandHistory[commandHistory.count - 1 - commandHistoryIndex]
        }
        isProgrammaticCommandAppend = false
        commandPinCaretRequest += 1
    }

    /// Return while focus is on the facility pane (editor): inject LF into KEY.
    private func handleFacilityReturnKey() -> Bool {
        if kernel.isFacilityTerminalActive, kernel.isEvaluating {
            kernel.pushKey(10)
            return true
        }
        // Never treat the painted editor grid as REPL input. Falling through to
        // handleReturnKey() EVALUATEs box-drawing / chrome → `undefined: │` spam
        // (seen when menubar Open was deferred and ⌘W raced facility teardown).
        if isEditorSplitActive || consoleTextLooksLikeFacilityGrid(consoleText) {
            return true
        }
        return handleReturnKey()
    }

    /// True when `consoleText` is still an SZ-EDITOR cell paint (not a REPL transcript).
    private func consoleTextLooksLikeFacilityGrid(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        // Editor chrome uses Unicode box-drawing; REPL transcripts do not.
        let box = CharacterSet(charactersIn: "─│┌┐└┘├┤┬┴┼╭╮╯╰═║╔╗╚╝╠╣╦╩╬")
        if t.unicodeScalars.contains(where: { box.contains($0) }) { return true }
        if t.hasPrefix(" Cmd-E/") || t.contains("│tt") { return true }
        return false
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
        // Leave the NSScrollView scroll position alone (facility uses its own TOP).
        if kernel.isFacilityTerminalActive {
            applyFacilitySelectionHighlight()
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
    /// While the editor *split* is live, host prompts and TYPE go to the lower
    /// command pane (never the facility grid). Facility-active alone is not
    /// enough — the first PAGE happens before the split exists, and those emits
    /// must still land in consoleText so the lower pane can be seeded.
    private func appendEngineOutput(_ s: String) {
        guard !s.isEmpty else { return }
        if isEditorSplitActive {
            appendCommandOutput(s)
            return
        }
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

    /// Put the pre-editor console back after SZ-EDITOR / facility leave.
    /// Prefer the live command-pane transcript (seeded at open + any command I/O);
    /// fall back to the open-time snapshot so we never leave an empty console.
    private func restoreConsoleAfterFacility() {
        kernel.setCommandPaneFocused(false)
        kernel.setFacilityEmitBypass(false)
        preferCommandFocusAfterEval = false
        suppressNextCommandPrompt = false
        isCommandFocused = false
        isProgrammaticConsoleAppend = true

        // Live NSTextView can be ahead of the SwiftUI binding for a frame.
        #if os(macOS)
        if let tv = commandTextView, !tv.string.isEmpty {
            commandText = tv.string
        }
        #endif

        let live = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        let snap = preFacilityConsole?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Prefer the longer non-empty buffer (live session vs open snapshot).
        if !live.isEmpty, live.count >= snap.count {
            consoleText = commandText
        } else if let saved = preFacilityConsole, !snap.isEmpty {
            consoleText = saved
        } else if !live.isEmpty {
            consoleText = commandText
        } else {
            // Do not keep the facility grid in the REPL buffer (would EVALUATE as
            // `undefined: │` if Return landed on the upper pane during teardown).
            consoleText = ""
        }

        preFacilityConsole = nil
        isEditorSplitActive = false
        commandText = ""
        commandProtectedLength = 0
        commandProtectedSnapshot = ""
        // If restore somehow still holds a grid paint, drop it.
        if consoleTextLooksLikeFacilityGrid(consoleText) {
            consoleText = ""
        }
        // Ensure a trailing newline so a following prompt/TYPE is not glued
        // onto the last transcript line.
        if !consoleText.isEmpty && !consoleText.hasSuffix("\n") {
            consoleText += "\n"
        }
        markProtectedThroughEndOfText()
        #if os(macOS)
        (consoleTextView as? ConsoleNSTextView)?.hideFacilityLineCaret()
        #endif
        isProgrammaticConsoleAppend = false
        isCommandFocused = false
        isFocused = true
        kernel.setCommandPaneFocused(false)
        // Already ends with ok(n)> from the command pane in the usual case.
        if !consoleText.hasSuffix("> ") {
            ensureInputPrompt()
        }
        keepCursorVisible(followPrompt: true)
        // Split teardown replaces the facility NSTextView with the full console.
        // Claim FR + caret on the *new* view across a few frames (same race as
        // post-DEBUG ok>); an immediate pinCaret often still hits the dying pane.
        #if os(macOS)
        claimFullConsoleFocusAfterEditorClose(attempts: 6)
        #endif
    }

    #if os(macOS)
    /// After ⌘W / FACILITY-OFF: put the caret at end of the restored transcript.
    private func claimFullConsoleFocusAfterEditorClose(attempts: Int) {
        guard attempts > 0 else { return }
        guard !isEditorSplitActive else {
            DispatchQueue.main.async {
                self.claimFullConsoleFocusAfterEditorClose(attempts: attempts - 1)
            }
            return
        }
        if let tv = consoleTextView as? ConsoleNSTextView, tv.paneKind == .full,
           let win = tv.window {
            // Sync live string if SwiftUI binding raced the text view.
            if tv.string != consoleText {
                tv.string = consoleText
            }
            win.makeFirstResponder(tv)
            let end = (tv.string as NSString).length
            tv.setSelectedRange(NSRange(location: end, length: 0))
            ConsoleTextView.scrollToEndNow(in: tv, pinCaret: true)
            pinCaretRequest += 1
            isFocused = true
            return
        }
        DispatchQueue.main.async {
            self.claimFullConsoleFocusAfterEditorClose(attempts: attempts - 1)
        }
    }
    #endif

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
        // Never start a nested evaluate while the facility editor owns the console.
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

    /// Submit all pending user input (single line or multi-line paste). Never splits at caret.
    private func commitUserInput() {
        guard !isRecallingHistory else { return }
        // Facility grid must never be submitted as console lines.
        if isEditorSplitActive || consoleTextLooksLikeFacilityGrid(consoleText) {
            return
        }

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

    /// Phase 5 ⌘E: VIEW word under caret — command pane, idle console, or editor.
    private func handleViewWordUnderCursor() {
        #if os(macOS)
        // Prefer the focused command pane (WORDS listing, etc.) even while editor KEY waits.
        if isCommandFocused || kernel.isCommandPaneFocused,
           let tv = commandTextView {
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

    /// Console ⌘-click (idle full pane): VIEW word under the click.
    private func handleViewWordAtConsoleUTF16(_ idx: Int) {
        #if os(macOS)
        guard let tv = consoleTextView else { return }
        let ns = tv.string as NSString
        viewForthToken(at: idx, in: ns, placingCaretIn: tv)
        #endif
    }

    /// Command-pane ⌘-click: VIEW word under the click (works while SZ-EDITOR KEY waits).
    private func handleViewWordAtCommandUTF16(_ idx: Int) {
        #if os(macOS)
        guard let tv = commandTextView else { return }
        let ns = tv.string as NSString
        viewForthToken(at: idx, in: ns, placingCaretIn: tv)
        #endif
    }

    /// Open Hyper VIEW for the token at `idx`. While the editor KEY loop is active,
    /// stages the line via key 133 (no nested host evaluate). Idle: host evaluate.
    private func viewForthToken(at idx: Int, in ns: NSString, placingCaretIn tv: NSTextView) {
        #if os(macOS)
        var i = idx
        if i > ns.length { i = ns.length }
        guard let word = Self.forthToken(at: i, in: ns), !word.isEmpty else { return }
        tv.setSelectedRange(NSRange(location: min(i, ns.length), length: 0))
        let escaped = word
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let line = "S\" \(escaped)\" HYPER-VIEW-CU"

        if kernel.isEvaluating, kernel.isFacilityTerminalActive {
            // Safe while KEY waits. Silent: no CR/ok> / scroll (user is navigating
            // the editor from a WORDS listing, not running a console command).
            suppressNextCommandPrompt = true
            preferCommandFocusAfterEval = false
            if !kernel.submitCommandLineFromPane(line) {
                suppressNextCommandPrompt = false
                appendCommandOutput("(VIEW submit failed)\n")
                appendCommandPrompt()
            }
            return
        }
        guard !kernel.isEvaluating else { return }

        isProgrammaticConsoleAppend = true
        _ = kernel.evaluate(line)
        // evaluate blocks until the editor exits. FACILITY-OFF restores the
        // transcript (async from the Forth queue); ensure restore + prompt here
        // if the callback has not already run.
        if !kernel.isFacilityTerminalActive {
            if preFacilityConsole != nil {
                restoreConsoleAfterFacility()
            }
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

    /// Apply facility reverse-video cells (drag / range selection) onto the console storage.
    private func applyFacilitySelectionHighlight() {
        guard kernel.isFacilityTerminalActive else { return }
        let term = FacilityTerminal.shared
        #if os(macOS)
        guard let textView = consoleTextView, let storage = textView.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        if full.length > 0 {
            storage.removeAttribute(.backgroundColor, range: full)
            storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: full)
        }
        guard term.hasReverseAttrs else { return }
        let mask = term.reverseMask()
        let cols = max(1, term.cols)
        let rows = term.rows
        let prefixLen = (kernel.facilityPaintPrefix as NSString).length
        let stride = cols + 1
        let accent = NSColor.controlAccentColor
        let onAccent = NSColor.white
        storage.beginEditing()
        for r in 0..<rows {
            let base = r * cols
            for c in 0..<cols {
                let i = base + c
                guard i < mask.count, mask[i] & FacilityTerminal.attrReverse != 0 else { continue }
                let loc = prefixLen + r * stride + c
                guard loc >= 0, loc < storage.length else { continue }
                let range = NSRange(location: loc, length: 1)
                storage.addAttribute(.backgroundColor, value: accent, range: range)
                storage.addAttribute(.foregroundColor, value: onAccent, range: range)
            }
        }
        storage.endEditing()
        #else
        guard let textView = consoleTextView else { return }
        let storage = textView.textStorage!
        let full = NSRange(location: 0, length: storage.length)
        if full.length > 0 {
            storage.removeAttribute(.backgroundColor, range: full)
            storage.addAttribute(.foregroundColor, value: UIColor.label, range: full)
        }
        guard term.hasReverseAttrs else { return }
        let mask = term.reverseMask()
        let cols = max(1, term.cols)
        let rows = term.rows
        let prefixLen = (kernel.facilityPaintPrefix as NSString).length
        let stride = cols + 1
        let accent = UIColor.systemBlue
        let onAccent = UIColor.white
        storage.beginEditing()
        for r in 0..<rows {
            let base = r * cols
            for c in 0..<cols {
                let i = base + c
                guard i < mask.count, mask[i] & FacilityTerminal.attrReverse != 0 else { continue }
                let loc = prefixLen + r * stride + c
                guard loc >= 0, loc < storage.length else { continue }
                let range = NSRange(location: loc, length: 1)
                storage.addAttribute(.backgroundColor, value: accent, range: range)
                storage.addAttribute(.foregroundColor, value: onAccent, range: range)
            }
        }
        storage.endEditing()
        #endif
    }

    /// Thin vertical I-beam at the Facility cursor (editor insert point).
    /// SZ-EDITOR parks the cursor via AT-XY; we paint a line caret on that cell.
    /// Hidden while the lower command pane has focus so the “cursor” is not stuck
    /// looking like it still lives in the editor.
    private func applyFacilityCursorHighlight() {
        #if os(macOS)
        guard let textView = consoleTextView as? ConsoleNSTextView else { return }
        guard kernel.isFacilityTerminalActive else {
            textView.hideFacilityLineCaret()
            return
        }
        if kernel.isCommandPaneFocused {
            textView.hideFacilityLineCaret()
            return
        }
        let storageLen = textView.textStorage?.length ?? (textView.string as NSString).length
        let prefixLen = (kernel.facilityPaintPrefix as NSString).length
        let cols = max(1, kernel.facilityCols)
        let row = kernel.facilityCursorRow
        let col = min(max(0, kernel.facilityCursorCol), cols - 1)
        // Each rendered line is `cols` Unicode cells + '\n' (BMP glyphs = 1 UTF-16).
        let loc = prefixLen + row * (cols + 1) + col
        guard loc >= 0 && loc < storageLen else {
            textView.hideFacilityLineCaret()
            return
        }
        textView.showFacilityLineCaret(atUTF16: loc)
        #else
        guard let textView = consoleTextView else { return }
        guard kernel.isFacilityTerminalActive else {
            textView.hideFacilityLineCaret()
            return
        }
        if kernel.isCommandPaneFocused {
            textView.hideFacilityLineCaret()
            return
        }
        let storageLen = textView.textStorage.length
        let prefixLen = (kernel.facilityPaintPrefix as NSString).length
        let cols = max(1, kernel.facilityCols)
        let row = kernel.facilityCursorRow
        let col = min(max(0, kernel.facilityCursorCol), cols - 1)
        let loc = prefixLen + row * (cols + 1) + col
        guard loc >= 0 && loc < storageLen else {
            textView.hideFacilityLineCaret()
            return
        }
        textView.showFacilityLineCaret(atUTF16: loc)
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

#if os(macOS)
/// Vertical split with a 5pt grab bar: gray / white / black / white / gray.
private struct EditorCommandSplitView<Top: View, Bottom: View>: NSViewRepresentable {
    @ViewBuilder var top: () -> Top
    @ViewBuilder var bottom: () -> Bottom

    func makeNSView(context: Context) -> EditorCommandNSSplitView {
        let split = EditorCommandNSSplitView()
        split.isVertical = false // horizontal divider (top/bottom panes)
        split.dividerStyle = .thin
        split.autoresizingMask = [.width, .height]

        let topHost = NSHostingView(rootView: top())
        let botHost = NSHostingView(rootView: bottom())
        split.addArrangedSubview(topHost)
        split.addArrangedSubview(botHost)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        context.coordinator.topHost = topHost
        context.coordinator.botHost = botHost
        // Initial command pane ~100pt after first layout.
        DispatchQueue.main.async {
            let total = split.bounds.height
            guard total > 200 else { return }
            split.setPosition(total - 100 - split.dividerThickness, ofDividerAt: 0)
        }
        return split
    }

    func updateNSView(_ split: EditorCommandNSSplitView, context: Context) {
        context.coordinator.topHost?.rootView = top()
        context.coordinator.botHost?.rootView = bottom()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var topHost: NSHostingView<Top>?
        var botHost: NSHostingView<Bottom>?
    }
}

/// NSSplitView with a 5-pixel painted divider for easy mouse hit-testing.
final class EditorCommandNSSplitView: NSSplitView {
    override var dividerThickness: CGFloat { 5 }

    override func drawDivider(in rect: NSRect) {
        // Five 1pt stripes: gray, white, black, white, gray.
        let colors: [NSColor] = [
            NSColor(calibratedWhite: 0.55, alpha: 1),
            .white,
            .black,
            .white,
            NSColor(calibratedWhite: 0.55, alpha: 1)
        ]
        let stripeH = max(rect.height / CGFloat(colors.count), 1)
        for (i, color) in colors.enumerated() {
            let y = rect.minY + CGFloat(i) * stripeH
            let r = NSRect(x: rect.minX, y: y, width: rect.width, height: stripeH)
            color.setFill()
            r.fill()
        }
    }
}
#endif
