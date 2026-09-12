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
    /// If ITC DEBUG / TDBG is paused in KEY, abort the stepper first so close can run.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let k = KernelBridge.shared
        if k.isEvaluating && k.isFacilityTerminalActive {
            k.requestQuitFromEditor()
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
                    // Direct — NotificationCenter/`onReceive` defers while KEY waits.
                    KernelBridge.shared.requestFileNew()
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
                    // Direct pushKey(19) while KEY waits (same deferral trap as Open).
                    KernelBridge.shared.requestFileSave()
                }
                .keyboardShortcut("s", modifiers: .command)
                Button("Save As…") {
                    KernelBridge.shared.requestFileSaveAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandGroup(after: .saveItem) {
                Button("Close Editor") {
                    KernelBridge.shared.requestFileClose()
                }
                .keyboardShortcut("w", modifiers: .command)
            }
            CommandMenu("Tools") {
                Button("CLS") {
                    NotificationCenter.default.post(name: .clearConsole, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("VIEW Word Under Cursor") {
                    // Direct — NotificationCenter/`onReceive` defers while KEY waits.
                    KernelBridge.shared.requestViewWordUnderCursor()
                }
                .keyboardShortcut("e", modifiers: [.command])

                Divider()

                // Find: ⌘←/→ preferred; ⌘G / ⌘⇧G are reliable letter shortcuts (like ⌘E).
                Button("Find Previous Word") {
                    KernelBridge.shared.requestEditorFind(prev: true)
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)

                Button("Find Next Word") {
                    KernelBridge.shared.requestEditorFind(prev: false)
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

                Button("Find Previous Word (G)") {
                    KernelBridge.shared.requestEditorFind(prev: true)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Button("Find Next Word (G)") {
                    KernelBridge.shared.requestEditorFind(prev: false)
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("Hyper Previous Hit") {
                    KernelBridge.shared.requestHyperNav(prev: true)
                }
                .keyboardShortcut(.pageUp, modifiers: .command)

                Button("Hyper Next Hit") {
                    KernelBridge.shared.requestHyperNav(prev: false)
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

                Button("Update User Data in 64Forth Folder") {
                    FileHost.shared.installUserTree(replaceExisting: false)
                }
                Button("Restore Shipped Files to 64Forth Folder") {
                    FileHost.shared.confirmRestoreShippedFiles()
                }
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
