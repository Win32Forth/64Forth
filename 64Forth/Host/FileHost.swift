//
//  FileHost.swift
//  64Forth
//
//  Public domain.
//
//  Path / Resources / FROMLIB architecture from TZForth.
//  Kernel INCLUDE will receive absolute paths or file text from this host (Phase 3).
//

import Foundation
import AppKit

/// Host-side directories and resolve rules (TZForth lineage).
final class FileHost {
    static let shared = FileHost()

    /// Logical session cwd (may differ from process cwd under sandbox).
    var logicalCurrentDirectory: String

    /// When true, next path resolve uses bundle Library (FROMLIB).
    private(set) var fromLibraryArmed = false

    private init() {
        logicalCurrentDirectory = FileManager.default.currentDirectoryPath
    }

    // MARK: - Bundle roots (Contents/Resources/…)

    var resourcesURL: URL? {
        Bundle.main.resourceURL
    }

    var libraryURL: URL? {
        resourcesURL?.appendingPathComponent("Library", isDirectory: true)
    }

    var autoLoadURL: URL? {
        resourcesURL?.appendingPathComponent("AutoLoad", isDirectory: true)
    }

    var docsURL: URL? {
        resourcesURL?.appendingPathComponent("Docs", isDirectory: true)
    }

    func resourceRootsDescription() -> String {
        var lines: [String] = []
        lines.append("Resources: \(resourcesURL?.path ?? "(not bundled yet — run from Xcode app)")")
        lines.append("Library:   \(libraryURL?.path ?? "—")")
        lines.append("AutoLoad:  \(autoLoadURL?.path ?? "—")")
        lines.append("Docs:      \(docsURL?.path ?? "—")")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - FROMLIB

    /// Arm next resolve to Resources/Library (TZForth FROMLIB).
    func armFromLibrary() {
        fromLibraryArmed = true
    }

    func clearFromLibrary() {
        fromLibraryArmed = false
    }

    /// Resolve a load name for FLOAD/INCLUDE.
    /// - Relative: against Library if armed, else logicalCurrentDirectory.
    /// - Absolute / ~ : as-is.
    func resolveLoadPath(_ name: String) -> URL? {
        var n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return nil }

        if n.hasPrefix("~") {
            n = NSString(string: n).expandingTildeInPath
        }

        if n.hasPrefix("/") {
            clearFromLibrary()
            return URL(fileURLWithPath: n)
        }

        let base: URL
        if fromLibraryArmed, let lib = libraryURL {
            base = lib
            clearFromLibrary()
        } else {
            base = URL(fileURLWithPath: logicalCurrentDirectory, isDirectory: true)
        }

        // Optional: add .fth if no extension (TZForth-style)
        var file = n
        if !file.contains(".") {
            file += ".fth"
        }
        return base.appendingPathComponent(file)
    }

    func revealInFinder(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
