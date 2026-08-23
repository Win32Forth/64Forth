//
//  SixtyFourForthApp.swift
//  64Forth
//
//  Public domain.
//
//  SwiftUI entry. Console host from TZForth pattern; engine = PickleForth kernel.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)
final class SixtyFourForthAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// ⌘Q while SZ-EDITOR is open: close the editor first (S/D prompt if dirty).
    /// Cancel (any other key on the prompt) keeps the app running.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let k = KernelBridge.shared
        if k.isEvaluating && k.isFacilityTerminalActive {
            k.requestQuitAppAfterEditorClose()
            // 17 = SZ-CTRL-Q → SZ-DO-QUIT (same as ⌘W close editor)
            k.pushKey(17)
            return .terminateCancel
        }
        return .terminateNow
    }
}
#endif

/// GUI app body. Entry is `AppMain` (`@main`) so `--agent` can skip the window.
struct SixtyFourForthApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(SixtyFourForthAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            // File → Open… (⌘O): open panel; while SZ-EDITOR is open, loads into editor.
            CommandGroup(replacing: .newItem) {
                Button("New") {
                    NotificationCenter.default.post(name: .fileNew, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                Button("Open…") {
                    // Direct callback — do not use NotificationCenter/`onReceive`,
                    // which defer while SZ-EDITOR KEY is waiting and only fire after ⌘W.
                    KernelBridge.shared.requestFileOpen()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            // ⌘S / ⌘W: while SZ-EDITOR is open, Save / Close editor (not the app).
            // ⌘Q still quits the application.
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .fileSave, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
                Button("Save As…") {
                    NotificationCenter.default.post(name: .fileSaveAs, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandGroup(after: .saveItem) {
                Button("Close Editor") {
                    NotificationCenter.default.post(name: .fileClose, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }
            CommandMenu("Tools") {
                Button("CLS") {
                    NotificationCenter.default.post(name: .clearConsole, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("VIEW Word Under Cursor") {
                    NotificationCenter.default.post(name: .viewWordUnderCursor, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command])

                Divider()

                // Find: ⌘←/→ preferred; ⌘G / ⌘⇧G are reliable letter shortcuts (like ⌘E).
                Button("Find Previous Word") {
                    NotificationCenter.default.post(name: .editorFindPrev, object: nil)
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)

                Button("Find Next Word") {
                    NotificationCenter.default.post(name: .editorFindNext, object: nil)
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

                Button("Find Previous Word (G)") {
                    NotificationCenter.default.post(name: .editorFindPrev, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Button("Find Next Word (G)") {
                    NotificationCenter.default.post(name: .editorFindNext, object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("Hyper Previous Hit") {
                    NotificationCenter.default.post(name: .hyperPrev, object: nil)
                }
                .keyboardShortcut(.pageUp, modifiers: .command)

                Button("Hyper Next Hit") {
                    NotificationCenter.default.post(name: .hyperNext, object: nil)
                }
                .keyboardShortcut(.pageDown, modifiers: .command)

                Divider()

                Button("FLOAD…") {
                    NotificationCenter.default.post(name: .toolsFload, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("CHDIR…") {
                    NotificationCenter.default.post(name: .toolsChdir, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("EDIT…") {
                    NotificationCenter.default.post(name: .toolsEdit, object: nil)
                }
                // No ⌘E / ⌘⇧E — ⌘E is VIEW word under cursor (Phase 5)

                Divider()

                Button("Show Library Folder") {
                    FileHost.shared.revealInFinder(FileHost.shared.libraryURL)
                }
                Button("Show AutoLoad Folder") {
                    FileHost.shared.revealInFinder(FileHost.shared.autoLoadURL)
                }
                Button("Show Docs Folder") {
                    FileHost.shared.revealInFinder(FileHost.shared.docsURL)
                }
                Button("Show Config Folder") {
                    FileHost.shared.revealInFinder(FileHost.shared.configURL)
                }
            }
        }
    }
}
