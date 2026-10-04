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
            // File: load / folder helpers (SZ New/Open/Save/Close removed — use 64Edit).
            CommandGroup(replacing: .newItem) {
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
            // Suppress document-style Save items; editing is in 64Edit.
            CommandGroup(replacing: .saveItem) { }
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

                Button("Toggle Breakpoint") {
                    KernelBridge.shared.requestToggleBreakpointUnderCursor()
                }
                .keyboardShortcut("\\", modifiers: [.command])
            }
            CommandGroup(after: .help) {
                Button("Show Boot Messages") {
                    NotificationCenter.default.post(name: .showBootMessages, object: nil)
                }
            }
        }
    }
}
