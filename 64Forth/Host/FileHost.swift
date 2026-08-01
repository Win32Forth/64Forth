//
//  FileHost.swift
//  64Forth
//
//  Public domain.
//
//  Path / Resources / FROMLIB / CHDIR architecture (TZForth lineage).
//

import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Host-side directories and resolve rules (TZForth lineage).
final class FileHost {
    static let shared = FileHost()

    /// Logical session cwd (may differ from process cwd under sandbox).
    var logicalCurrentDirectory: String

    /// When true, next path resolve uses bundle Library (FROMLIB).
    private(set) var fromLibraryArmed = false

    /// Start directory for the next bare FLOAD/CHDIR open panel (FROMLIB bare).
    var fileDialogStartDirectoryOverride: String?

    /// When true, bare FLOAD after FROMLIB must not leave session cwd at Library permanently.
    var preserveSessionCwdAfterFileOp = false

    /// Saved cwd frames while a FROMLIB *named* load is in progress (nested-safe).
    private var fromLibraryDirStack: [(logical: String, process: String)] = []

    /// Saved cwd frames while a file INCLUDE/FLOAD is active (nested-safe).
    /// Each successful load chdirs to the file's directory so nested relative
    /// FLOAD/INCLUDE resolve next to that file (TZForth performScopedNamedLoad).
    private var loadCwdStack: [(logical: String, process: String)] = []

    /// Pinned INCLUDE buffers for the current kernel_eval (nested INCLUDE).
    private var includeAllocs: [UnsafeMutablePointer<CChar>] = []

    /// Last error message for INCLUDE/FLOAD (also emitted via KernelBridge when set).
    private(set) var lastLoadError: String?

    /// Absolute standardized path of the last successful load (REQUIRE registry key).
    private(set) var lastLoadRegistryKey: String?

    /// Optional emit sink (KernelBridge sets this for load/chdir messages).
    var onMessage: ((String) -> Void)?

    /// Security-scoped bookmark blobs (Phase 5; useful if App Sandbox is enabled later).
    private var scopedBookmarkData: [Data] = []
    private let bookmarksDefaultsKey = "SixtyFourForth.SecurityScopedBookmarks"
    private let lastCwdDefaultsKey = "SixtyFourForth.LastLogicalCwd"

    private init() {
        logicalCurrentDirectory = FileManager.default.currentDirectoryPath
        restorePersistedAccess()
    }

    private func msg(_ s: String) {
        onMessage?(s)
    }

    #if os(macOS)
    /// Create, configure, and run an `NSOpenPanel` entirely on the main thread.
    ///
    /// `kernel_eval` often runs on `forthQueue` (so KEY can pump AppKit). AppKit
    /// requires *all* `NSOpenPanel` / `NSSavePanel` use on the main thread —
    /// including `init`, not only `runModal`. Uses async + wait so we never
    /// `main.sync` against a main thread that is already pumping for KEY
    /// (that would deadlock).
    private func pickWithOpenPanelOnMain(
        configure: @escaping (NSOpenPanel) -> Void
    ) -> URL? {
        if Thread.isMainThread {
            let panel = NSOpenPanel()
            configure(panel)
            guard panel.runModal() == .OK else { return nil }
            return panel.url
        }
        var picked: URL?
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            configure(panel)
            if panel.runModal() == .OK {
                picked = panel.url
            }
            done.signal()
        }
        while done.wait(timeout: .now() + 0.05) == .timedOut {
            // Main evaluate loop processes this async block while pumping UI.
        }
        return picked
    }
    #endif

    // MARK: - Bundle roots (Contents/Resources/…)

    var resourcesURL: URL? {
        Bundle.main.resourceURL
    }

    var libraryURL: URL? {
        if let root = resourcesURL {
            let dir = root.appendingPathComponent("Library", isDirectory: true)
            if FileManager.default.fileExists(atPath: dir.path) { return dir }
        }
        if let u = Bundle.main.url(forResource: "Library", withExtension: nil) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                return u
            }
        }
        return nil
    }

    var autoLoadURL: URL? {
        if let root = resourcesURL {
            let dir = root.appendingPathComponent("AutoLoad", isDirectory: true)
            if FileManager.default.fileExists(atPath: dir.path) { return dir }
        }
        if let u = Bundle.main.url(forResource: "AutoLoad", withExtension: nil) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                return u
            }
        }
        return nil
    }

    /// `Resources/AutoLoad/autoload.fth` if present (TZForth boot file name rules).
    var autoLoadFileURL: URL? {
        var candidates: [URL] = []
        if let u = Bundle.main.url(forResource: "autoload", withExtension: "fth", subdirectory: "AutoLoad") {
            candidates.append(u)
        }
        if let u = Bundle.main.url(forResource: "AutoLoad", withExtension: "fth", subdirectory: "AutoLoad") {
            candidates.append(u)
        }
        if let root = resourcesURL {
            candidates.append(root.appendingPathComponent("AutoLoad/autoload.fth"))
            candidates.append(root.appendingPathComponent("AutoLoad/AutoLoad.fth"))
            candidates.append(root.appendingPathComponent("autoload.fth"))
        }
        if let dir = autoLoadURL,
           let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for f in files where f.pathExtension.lowercased() == "fth" {
                if f.deletingPathExtension().lastPathComponent.lowercased() == "autoload" {
                    candidates.append(f)
                }
            }
        }
        for url in candidates {
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    var docsURL: URL? {
        if let root = resourcesURL {
            let dir = root.appendingPathComponent("Docs", isDirectory: true)
            if FileManager.default.fileExists(atPath: dir.path) { return dir }
        }
        if let u = Bundle.main.url(forResource: "Docs", withExtension: nil) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                return u
            }
        }
        return nil
    }

    func resourceRootsDescription() -> String {
        var lines: [String] = []
        lines.append("Resources: \(resourcesURL?.path ?? "(not bundled — run the .app from Xcode)")")
        lines.append("Library:   \(libraryURL?.path ?? "— (missing from bundle)")")
        lines.append("AutoLoad:  \(autoLoadURL?.path ?? "—")")
        if let boot = autoLoadFileURL {
            lines.append("autoload:  \(boot.lastPathComponent)")
        } else {
            lines.append("autoload:  (none — pure REPL)")
        }
        lines.append("Docs:      \(docsURL?.path ?? "—")")
        lines.append("cwd:       \(logicalCurrentDirectory)")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - FROMLIB

    /// Arm next resolve to Resources/Library (TZForth FROMLIB).
    func armFromLibrary() {
        fromLibraryArmed = true
    }

    /// Disarm FROMLIB without loading (e.g. REQUIRE skipped — already loaded).
    func clearFromLibrary() {
        fromLibraryArmed = false
    }

    private func isAbsoluteOrHome(_ spec: String) -> Bool {
        let s = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.hasPrefix("/") || s.hasPrefix("~")
    }

    /// Normalize leaf: append `.fth` when no extension.
    func normalizeSourceSpec(_ spec: String) -> String {
        let trimmed = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let leaf = (trimmed as NSString).lastPathComponent
        if leaf.isEmpty || leaf.contains(".") { return trimmed }
        return trimmed + ".fth"
    }

    /// Resolve a load name for FLOAD/INCLUDE/REQUIRE.
    /// - Relative + FROMLIB armed → under Resources/Library (flag cleared; path base only —
    ///   nested relatives use the loaded file's directory via loadCwdStack in pinFileContents)
    /// - Relative → logicalCurrentDirectory
    /// - Absolute / ~ → as-is
    func resolveLoadPath(_ name: String, switchCwdForFromLib: Bool = true) -> URL? {
        var n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return nil }

        if n.hasPrefix("~") {
            n = NSString(string: n).expandingTildeInPath
        }

        if n.hasPrefix("/") {
            return URL(fileURLWithPath: n)
        }

        n = normalizeSourceSpec(n)

        let armed = fromLibraryArmed
        let base: URL
        if armed, let lib = libraryURL {
            clearFromLibrary()
            base = lib
            // Remember session cwd so evaluate() can restore after a FROMLIB-named load.
            // Nested relative FLOAD uses the *file's* folder (see beginLoadCwd), not Library root.
            if switchCwdForFromLib {
                pushFromLibrarySessionFrame()
            }
        } else {
            if armed {
                clearFromLibrary()
                // Armed but Library missing from bundle
                lastLoadError = "FROMLIB: Resources/Library not found in app bundle"
                return nil
            }
            base = URL(fileURLWithPath: logicalCurrentDirectory, isDirectory: true)
        }

        let path = (base.path as NSString).appendingPathComponent(n)
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    /// Resolve a load name to an absolute registry key (consumes FROMLIB like a real load).
    /// Does not require the file to exist on disk. Does not switch session cwd.
    func resolveRegistryKey(path: UnsafePointer<CChar>?, pathLen: Int) -> String? {
        guard let path, pathLen > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: pathLen)
        for i in 0..<pathLen { bytes[i] = UInt8(bitPattern: path[i]) }
        let raw = String(bytes: bytes, encoding: .utf8) ?? ""
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // switchCwdForFromLib: false — REQUIRED path-key resolve must not leave cwd at Library.
        guard !name.isEmpty, let url = resolveLoadPath(name, switchCwdForFromLib: false) else { return nil }
        return url.standardizedFileURL.path
    }

    /// Snapshot session cwd for FROMLIB restore (does not change cwd).
    private func pushFromLibrarySessionFrame() {
        let frame = (logical: logicalCurrentDirectory, process: FileManager.default.currentDirectoryPath)
        fromLibraryDirStack.append(frame)
    }

    func endFromLibraryLoadIfNeeded() {
        guard let frame = fromLibraryDirStack.popLast() else { return }
        logicalCurrentDirectory = frame.logical
        let proc = frame.process.isEmpty ? frame.logical : frame.process
        if !proc.isEmpty {
            _ = FileManager.default.changeCurrentDirectoryPath(proc)
        }
    }

    func endAllFromLibraryLoads() {
        while !fromLibraryDirStack.isEmpty {
            endFromLibraryLoadIfNeeded()
        }
    }

    // MARK: - Per-file load cwd (nested relative FLOAD)

    /// Enter the loaded file's directory for the duration of its INCLUDE SOURCE.
    private func beginLoadCwd(forFileURL url: URL) {
        let parent = url.deletingLastPathComponent().path
        let frame = (logical: logicalCurrentDirectory, process: FileManager.default.currentDirectoryPath)
        loadCwdStack.append(frame)
        logicalCurrentDirectory = parent
        _ = FileManager.default.changeCurrentDirectoryPath(parent)
    }

    /// Restore cwd when a file INCLUDE/FLOAD SOURCE ends (kernel SOURCE-ID was > 0).
    func endLoadCwdIfNeeded() {
        guard let frame = loadCwdStack.popLast() else { return }
        logicalCurrentDirectory = frame.logical
        let proc = frame.process.isEmpty ? frame.logical : frame.process
        if !proc.isEmpty {
            _ = FileManager.default.changeCurrentDirectoryPath(proc)
        }
    }

    func endAllLoadCwds() {
        while !loadCwdStack.isEmpty {
            endLoadCwdIfNeeded()
        }
    }

    // MARK: - CHDIR (TZForth-style)

    /// Named CHDIR. Honors FROMLIB for relative paths (permanent chdir under Library).
    func changeDirectory(spec: String) {
        let s = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty {
            presentDirectoryPicker()
            return
        }

        // FROMLIB + relative → under Library permanently
        if fromLibraryArmed {
            clearFromLibrary()
            if !isAbsoluteOrHome(s), let lib = libraryURL {
                let expanded = (s as NSString).expandingTildeInPath
                let target = (lib.path as NSString).appendingPathComponent(expanded)
                applyChdir(URL(fileURLWithPath: target).standardizedFileURL)
                return
            }
        }

        let expanded = (s as NSString).expandingTildeInPath
        let newURL: URL
        if expanded.hasPrefix("/") {
            newURL = URL(fileURLWithPath: expanded)
        } else {
            newURL = URL(fileURLWithPath: logicalCurrentDirectory)
                .appendingPathComponent(expanded)
                .standardizedFileURL
        }
        applyChdir(newURL)
    }

    /// Bare CHDIR: folder picker. FROMLIB arms start at Library.
    func presentDirectoryPicker() {
        #if !os(macOS)
        msg("? bare CHDIR: use CHDIR with a path on iOS (folder dialog not yet available)\n")
        return
        #else
        let startDir: URL
        if fromLibraryArmed {
            clearFromLibrary()
            if let lib = libraryURL {
                startDir = lib
            } else {
                startDir = URL(fileURLWithPath: logicalCurrentDirectory, isDirectory: true)
            }
        } else if let override = fileDialogStartDirectoryOverride {
            startDir = URL(fileURLWithPath: override, isDirectory: true)
            fileDialogStartDirectoryOverride = nil
        } else {
            startDir = URL(fileURLWithPath: logicalCurrentDirectory, isDirectory: true)
        }

        guard let url = pickWithOpenPanelOnMain(configure: { panel in
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Choose"
            panel.message = "CHDIR — set working directory"
            panel.directoryURL = startDir
        }) else {
            msg("(CHDIR cancelled)\n")
            return
        }
        applyChdir(url)
        #endif
    }

    private func applyChdir(_ url: URL) {
        endAllLoadCwds()
        endAllFromLibraryLoads()
        clearFromLibrary()
        logicalCurrentDirectory = url.path
        _ = FileManager.default.changeCurrentDirectoryPath(url.path)
        rememberScopedURL(url)
        UserDefaults.standard.set(url.path, forKey: lastCwdDefaultsKey)
        msg("Current directory: \(logicalCurrentDirectory)\n")
    }

    func printPwd() {
        msg("Current directory: \(logicalCurrentDirectory)\n")
    }

    // MARK: - DIR (TZForth-style)

    /// List directory. Bare → cwd (or Library if FROMLIB). Named path / `*.fth` wildcards.
    func listDirectory(spec: String) {
        let fm = FileManager.default
        var basePath = logicalCurrentDirectory
        var filter = ""
        let raw = spec.trimmingCharacters(in: .whitespacesAndNewlines)

        // FROMLIB: bare or relative lists under Resources/Library (then clear flag)
        if fromLibraryArmed {
            clearFromLibrary()
            if let lib = libraryURL {
                if raw.isEmpty {
                    emitDirectoryListing(of: lib.path, filter: "")
                    return
                }
                if !isAbsoluteOrHome(raw) {
                    let expanded = (raw as NSString).expandingTildeInPath
                    let hasWild = expanded.contains("*") || expanded.contains("?")
                    if hasWild {
                        if let lastSlash = expanded.lastIndex(of: "/") {
                            let dirPart = String(expanded[..<lastSlash])
                            filter = String(expanded[expanded.index(after: lastSlash)...])
                            let dirPath = dirPart.isEmpty
                                ? lib.path
                                : (lib.path as NSString).appendingPathComponent(dirPart)
                            emitDirectoryListing(of: dirPath, filter: filter)
                        } else {
                            emitDirectoryListing(of: lib.path, filter: expanded)
                        }
                    } else {
                        let target = (lib.path as NSString).appendingPathComponent(expanded)
                        var isD: ObjCBool = false
                        if fm.fileExists(atPath: target, isDirectory: &isD), isD.boolValue {
                            emitDirectoryListing(of: target, filter: "")
                        } else {
                            // treat as filter in Library root
                            emitDirectoryListing(of: lib.path, filter: expanded)
                        }
                    }
                    return
                }
                // absolute with FROMLIB armed: fall through after clear
            } else {
                msg("DIR: FROMLIB armed but Resources/Library missing\n")
                return
            }
        }

        if !raw.isEmpty {
            let expanded = (raw as NSString).expandingTildeInPath
            let hasWild = expanded.contains("*") || expanded.contains("?")
            if hasWild {
                if let lastSlash = expanded.lastIndex(of: "/") {
                    let dirPart = String(expanded[..<lastSlash])
                    filter = String(expanded[expanded.index(after: lastSlash)...])
                    if dirPart.isEmpty {
                        basePath = "/"
                    } else {
                        let dirExpanded = (dirPart as NSString).expandingTildeInPath
                        if dirExpanded.hasPrefix("/") {
                            basePath = dirExpanded
                        } else {
                            basePath = (basePath as NSString).appendingPathComponent(dirExpanded)
                        }
                    }
                } else {
                    filter = expanded
                }
            } else {
                let testURL: URL
                if expanded.hasPrefix("/") {
                    testURL = URL(fileURLWithPath: expanded)
                } else {
                    testURL = URL(fileURLWithPath: basePath).appendingPathComponent(expanded)
                }
                var isD: ObjCBool = false
                if fm.fileExists(atPath: testURL.path, isDirectory: &isD), isD.boolValue {
                    basePath = testURL.path
                    filter = ""
                } else {
                    filter = expanded
                }
            }
        }

        emitDirectoryListing(of: basePath, filter: filter)
    }

    private func emitDirectoryListing(of basePath: String, filter: String) {
        let fm = FileManager.default
        let listURL = URL(fileURLWithPath: basePath)
        do {
            let contents = try fm.contentsOfDirectory(
                at: listURL,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            msg("\nDirectory of \(listURL.path)\n\n")
            var count = 0
            for fileURL in contents.sorted(by: {
                $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased()
            }) {
                let name = fileURL.lastPathComponent
                if !filter.isEmpty, !matchesWildcard(filter, in: name) {
                    continue
                }
                var isDir: ObjCBool = false
                fm.fileExists(atPath: fileURL.path, isDirectory: &isDir)
                if isDir.boolValue {
                    let padded = name.padding(toLength: 30, withPad: " ", startingAt: 0)
                    msg(" \(padded) <DIR>\n")
                } else {
                    let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    let padded = name.padding(toLength: 30, withPad: " ", startingAt: 0)
                    let sizeStr = String(size).padding(toLength: 12, withPad: " ", startingAt: 0)
                    msg(" \(padded) \(sizeStr)\n")
                }
                count += 1
            }
            msg("\n \(count) file(s)\n\n")
        } catch {
            msg("DIR error: Cannot read directory '\(listURL.path)'\n")
            msg("  (Use bare FLOAD or CHDIR to open/authorize a folder if access fails.)\n")
        }
    }

    /// MS-DOS style * and ? wildcards, case-insensitive.
    private func matchesWildcard(_ pattern: String, in name: String) -> Bool {
        let regexPattern = "^" + NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
            + "$"
        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: .caseInsensitive) else {
            return false
        }
        let range = NSRange(location: 0, length: name.utf16.count)
        return regex.firstMatch(in: name, options: [], range: range) != nil
    }

    // MARK: - Bookmarks / persistence (Phase 5)

    private func rememberScopedURL(_ url: URL) {
        // Prefer security-scoped bookmarks when the URL supports them (panel picks).
        #if os(macOS)
        let opts: URL.BookmarkCreationOptions = [.withSecurityScope]
        #else
        let opts: URL.BookmarkCreationOptions = []
        #endif
        guard let data = try? url.bookmarkData(
            options: opts,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        scopedBookmarkData.removeAll { $0 == data }
        scopedBookmarkData.append(data)
        // Cap list
        if scopedBookmarkData.count > 32 {
            scopedBookmarkData.removeFirst(scopedBookmarkData.count - 32)
        }
        UserDefaults.standard.set(scopedBookmarkData, forKey: bookmarksDefaultsKey)
    }

    private func restorePersistedAccess() {
        if let path = UserDefaults.standard.string(forKey: lastCwdDefaultsKey),
           !path.isEmpty {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                logicalCurrentDirectory = path
                _ = FileManager.default.changeCurrentDirectoryPath(path)
            }
        }
        if let saved = UserDefaults.standard.array(forKey: bookmarksDefaultsKey) as? [Data] {
            scopedBookmarkData = saved
            for data in scopedBookmarkData {
                var isStale = false
                #if os(macOS)
                let resolveOpts: URL.BookmarkResolutionOptions = [.withSecurityScope]
                #else
                let resolveOpts: URL.BookmarkResolutionOptions = []
                #endif
                guard let url = try? URL(
                    resolvingBookmarkData: data,
                    options: resolveOpts,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ) else { continue }
                _ = url.startAccessingSecurityScopedResource()
            }
        }
    }

    // MARK: - Load for kernel hook

    /// Kernel load_file_hook. path_len == 0 → bare FLOAD dialog (TZForth).
    /// Returns 0 and sets outPtr/outLen on success; −1 on failure/cancel.
    func loadFileForKernel(
        path: UnsafePointer<CChar>?,
        pathLen: Int,
        outPtr: UnsafeMutablePointer<UnsafePointer<CChar>?>?,
        outLen: UnsafeMutablePointer<Int>?
    ) -> Int32 {
        lastLoadError = nil

        // Bare FLOAD / INCLUDE → open panel
        if path == nil || pathLen == 0 {
            return loadViaOpenPanel(outPtr: outPtr, outLen: outLen)
        }

        let name = String(cString: path!)
        guard let url = resolveLoadPath(name) else {
            let err = lastLoadError ?? "can't open: \(name) (resolve failed)"
            lastLoadError = err
            msg(err + "\n")
            if libraryURL == nil {
                msg("  hint: Library missing from app bundle — check Copy Bundle Resources\n")
            } else if fromLibraryArmed == false {
                msg("  cwd: \(logicalCurrentDirectory)\n")
                msg("  Library: \(libraryURL?.path ?? "—")\n")
                msg("  try: FROMLIB FLOAD \(normalizeSourceSpec(name))\n")
                msg("  or:  CHDIR then FLOAD, or bare FLOAD (dialog)\n")
            }
            return -1
        }

        return pinFileContents(url: url, displayName: name, outPtr: outPtr, outLen: outLen)
    }

    private func loadViaOpenPanel(
        outPtr: UnsafeMutablePointer<UnsafePointer<CChar>?>?,
        outLen: UnsafeMutablePointer<Int>?
    ) -> Int32 {
        #if !os(macOS)
        msg("? bare FLOAD: use INCLUDE with a path on iOS (file dialog not yet available)\n")
        preserveSessionCwdAfterFileOp = false
        return -1
        #else
        // Capture start dir / preserve flag on the kernel thread; create the
        // panel only on main (AppKit main-thread rule).
        let startDir: URL
        if fromLibraryArmed, let lib = libraryURL {
            clearFromLibrary()
            startDir = lib
            preserveSessionCwdAfterFileOp = true
        } else if let override = fileDialogStartDirectoryOverride {
            startDir = URL(fileURLWithPath: override, isDirectory: true)
            fileDialogStartDirectoryOverride = nil
        } else {
            clearFromLibrary()
            startDir = URL(fileURLWithPath: logicalCurrentDirectory, isDirectory: true)
        }

        guard let url = pickWithOpenPanelOnMain(configure: { panel in
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [
                UTType(filenameExtension: "fth") ?? .plainText,
                UTType(filenameExtension: "fs") ?? .plainText,
                UTType(filenameExtension: "4th") ?? .plainText,
                .plainText
            ]
            panel.prompt = "Load"
            panel.message = "FLOAD / INCLUDE — choose a Forth source file"
            panel.directoryURL = startDir
        }) else {
            msg("(FLOAD cancelled)\n")
            preserveSessionCwdAfterFileOp = false
            return -1
        }

        // TZForth bare pick: permanently chdir to parent unless FROMLIB preserve flag.
        // Nested relatives still use beginLoadCwd inside pinFileContents either way
        // (FROMLIB bare: temp cwd for the load only; restore when SOURCE ends).
        if !preserveSessionCwdAfterFileOp {
            let parent = url.deletingLastPathComponent()
            logicalCurrentDirectory = parent.path
            _ = FileManager.default.changeCurrentDirectoryPath(parent.path)
            rememberScopedURL(parent)
            rememberScopedURL(url)
            UserDefaults.standard.set(parent.path, forKey: lastCwdDefaultsKey)
            msg("Current directory: \(logicalCurrentDirectory)\n")
        } else {
            // FROMLIB bare FLOAD: do not permanently change session CHDIR, but nested
            // FLOAD must still resolve next to the picked file (pinFileContents chdirs).
            rememberScopedURL(url)
        }
        preserveSessionCwdAfterFileOp = false

        return pinFileContents(url: url, displayName: url.lastPathComponent, outPtr: outPtr, outLen: outLen)
        #endif
    }

    private func pinFileContents(
        url: URL,
        displayName: String,
        outPtr: UnsafeMutablePointer<UnsafePointer<CChar>?>?,
        outLen: UnsafeMutablePointer<Int>?
    ) -> Int32 {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            let err = "can't open: \(displayName)\n  path: \(url.path)\n  \(error.localizedDescription)"
            lastLoadError = err
            msg(err + "\n")
            return -1
        }

        // Must fit largest Hayes FP test (paranoia.4th ~70 KiB) and room to grow.
        let maxBytes = 262_144
        let n = min(data.count, maxBytes)
        if data.count > maxBytes {
            msg("(warning: \(displayName) truncated to \(maxBytes) bytes)\n")
        }
        let p = UnsafeMutablePointer<CChar>.allocate(capacity: n + 1)
        if n > 0 {
            data.copyBytes(to: UnsafeMutableRawPointer(p).assumingMemoryBound(to: UInt8.self), count: n)
        }
        p[n] = 0
        includeAllocs.append(p)

        // Nested FLOAD/INCLUDE resolve relative to this file's folder for the duration
        // of its SOURCE (restored when the kernel finishes the include — endLoadCwdIfNeeded).
        beginLoadCwd(forFileURL: url)

        lastLoadRegistryKey = url.standardizedFileURL.path
        outPtr?.pointee = UnsafePointer(p)
        outLen?.pointee = n
        return 0
    }

    func releaseIncludeBuffers() {
        for p in includeAllocs {
            p.deallocate()
        }
        includeAllocs.removeAll()
    }

    // MARK: - EDIT (TZForth-style: open in system editor, update cwd)

    /// Kernel EDIT hook. path_len == 0 → open panel. Named: resolve (FROMLIB ok), open, chdir.
    /// FROMLIB EDIT does not permanently leave session cwd at Library (same as TZForth).
    func editForKernel(path: UnsafePointer<CChar>?, pathLen: Int) {
        lastLoadError = nil
        if path == nil || pathLen == 0 {
            presentEditPicker()
            return
        }

        var bytes = [UInt8](repeating: 0, count: pathLen)
        for i in 0..<pathLen { bytes[i] = UInt8(bitPattern: path![i]) }
        let raw = String(bytes: bytes, encoding: .utf8) ?? ""
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            presentEditPicker()
            return
        }

        // FROMLIB named EDIT: open under Library but restore session cwd afterward.
        let preserveCwd = fromLibraryArmed
        let savedLogical = logicalCurrentDirectory
        let savedProcess = FileManager.default.currentDirectoryPath

        guard var url = resolveLoadPath(name) else {
            let err = lastLoadError ?? "can't edit: \(name) (resolve failed)"
            lastLoadError = err
            msg(err + "\n")
            if preserveCwd {
                restoreSessionDirectory(logical: savedLogical, process: savedProcess)
            }
            return
        }

        // Auto .fth fallback (like FLOAD/EDIT in TZForth) when leaf has no extension.
        let leaf = url.lastPathComponent
        if !leaf.contains(".") {
            let alt = url.deletingLastPathComponent().appendingPathComponent(leaf + ".fth")
            if !FileManager.default.fileExists(atPath: url.path),
               FileManager.default.fileExists(atPath: alt.path) {
                url = alt
            }
        }

        if !FileManager.default.fileExists(atPath: url.path) {
            msg("can't edit: \(url.path) (not found)\n")
            if preserveCwd {
                restoreSessionDirectory(logical: savedLogical, process: savedProcess)
                endAllFromLibraryLoads()
            }
            return
        }

        openInSystemEditor(url)

        if preserveCwd || preserveSessionCwdAfterFileOp {
            preserveSessionCwdAfterFileOp = false
            restoreSessionDirectory(logical: savedLogical, process: savedProcess)
            endAllFromLibraryLoads()
        } else {
            // Session cwd → file's folder (named EDIT without FROMLIB).
            let parent = url.deletingLastPathComponent()
            applyChdir(parent)
        }
    }

    /// Bare EDIT: file open panel. FROMLIB arms start at Library without permanent CHDIR.
    func presentEditPicker() {
        #if !os(macOS)
        msg("? bare EDIT: use EDIT with a path on iOS (file dialog not yet available)\n")
        return
        #else
        let preserveCwd: Bool
        let savedLogical = logicalCurrentDirectory
        let savedProcess = FileManager.default.currentDirectoryPath
        let startDir: URL
        let panelMessage: String

        if fromLibraryArmed, let lib = libraryURL {
            clearFromLibrary()
            startDir = lib
            preserveCwd = true
            preserveSessionCwdAfterFileOp = true
            panelMessage = "Select a library source file to open in the system default editor."
        } else if let override = fileDialogStartDirectoryOverride {
            startDir = URL(fileURLWithPath: override, isDirectory: true)
            fileDialogStartDirectoryOverride = nil
            preserveCwd = preserveSessionCwdAfterFileOp
            panelMessage = preserveCwd
                ? "Select a library source file to open in the system default editor."
                : "Select a file to open in the system default editor. The current directory will change to the file's folder."
        } else {
            clearFromLibrary()
            startDir = URL(fileURLWithPath: logicalCurrentDirectory, isDirectory: true)
            preserveCwd = false
            panelMessage = "Select a file to open in the system default editor. The current directory will change to the file's folder."
        }

        guard let url = pickWithOpenPanelOnMain(configure: { panel in
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [
                UTType(filenameExtension: "fth") ?? .plainText,
                UTType(filenameExtension: "fs") ?? .plainText,
                UTType(filenameExtension: "4th") ?? .plainText,
                .plainText,
                .text
            ]
            panel.prompt = "Edit"
            panel.message = panelMessage
            panel.directoryURL = startDir
        }) else {
            msg("(EDIT cancelled)\n")
            if preserveCwd {
                restoreSessionDirectory(logical: savedLogical, process: savedProcess)
            }
            preserveSessionCwdAfterFileOp = false
            return
        }

        rememberScopedURL(url)
        openInSystemEditor(url)

        if preserveCwd {
            restoreSessionDirectory(logical: savedLogical, process: savedProcess)
            preserveSessionCwdAfterFileOp = false
        } else {
            applyChdir(url.deletingLastPathComponent())
        }
        #endif
    }

    private func openInSystemEditor(_ url: URL) {
        #if os(macOS)
        let ok = NSWorkspace.shared.open(url)
        if ok {
            msg("EDIT: \(url.path)\n")
        } else {
            msg("? EDIT could not open: \(url.path)\n")
        }
        #else
        msg("? EDIT open in system editor is not available on iOS: \(url.path)\n")
        #endif
    }

    private func restoreSessionDirectory(logical: String, process: String) {
        logicalCurrentDirectory = logical
        _ = FileManager.default.changeCurrentDirectoryPath(process)
    }

    // MARK: - Finder

    /// Open a folder (or select a file) in Finder (macOS). On iOS, print the path.
    /// `activateFileViewerSelecting` is flaky for directories inside the .app
    /// package (Library/AutoLoad/Docs under Contents/Resources); `open` is reliable.
    func revealInFinder(_ url: URL?) {
        guard let url else {
            msg("? folder not available in this build (missing from app bundle)\n")
            return
        }
        let path = url.standardizedFileURL.path
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            msg("? missing: \(path)\n")
            return
        }
        #if os(macOS)
        let fileURL = URL(fileURLWithPath: path, isDirectory: isDir.boolValue)
        if isDir.boolValue {
            if !NSWorkspace.shared.open(fileURL) {
                // Fallback: select the folder in its parent
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            }
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        }
        #else
        msg("folder: \(path)\n")
        #endif
    }

    /// Programmatic CHDIR (Tools menu / host).
    @discardableResult
    func setCurrentDirectory(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            msg("can't chdir: \(path)\n")
            return false
        }
        applyChdir(url)
        return true
    }
}
