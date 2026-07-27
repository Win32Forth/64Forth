//
//  SixtyFourForthApp.swift
//  64Forth
//
//  Public domain.
//
//  SwiftUI entry. Console host from TZForth pattern; engine = PickleForth kernel.
//

import SwiftUI
import AppKit

final class SixtyFourForthAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct SixtyFourForthApp: App {
    @NSApplicationDelegateAdaptor(SixtyFourForthAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Tools") {
                Button("CLS") {
                    NotificationCenter.default.post(name: .clearConsole, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command])

                Divider()

                Button("FLOAD…") {
                    NotificationCenter.default.post(name: .toolsFload, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("CHDIR…") {
                    NotificationCenter.default.post(name: .toolsChdir, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Divider()

                Button("Show Library Folder") {
                    NotificationCenter.default.post(name: .showLibraryFolder, object: nil)
                }
                Button("Show AutoLoad Folder") {
                    NotificationCenter.default.post(name: .showAutoloadFolder, object: nil)
                }
                Button("Show Docs Folder") {
                    NotificationCenter.default.post(name: .showDocsFolder, object: nil)
                }
            }
        }
    }
}
