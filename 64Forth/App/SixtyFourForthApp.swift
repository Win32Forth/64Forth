//
//  SixtyFourForthApp.swift
//  64Forth
//
//  Public domain.
//
//  SwiftUI entry. Console host from TZForth pattern; engine = PickleForth kernel (phased).
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
                Button("Show Library Folder") {
                    NotificationCenter.default.post(name: .showLibraryFolder, object: nil)
                }
                Button("Show AutoLoad Folder") {
                    NotificationCenter.default.post(name: .showAutoloadFolder, object: nil)
                }
            }
        }
    }
}
