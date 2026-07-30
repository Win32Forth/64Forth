//
//  FileAccess.swift
//  64Forth
//
//  Public domain.
//
//  ANS File-Access word set (11) — host-side open file table + path resolve.
//  Used by kernel CODE words OPEN-FILE, READ-FILE, etc.
//

import Foundation

/// Fam bits (compatible with common ANS practice / TZForth).
enum FileAccessMode {
    static let rdonly: Int64 = 1
    static let wronly: Int64 = 2
    static let rdwr: Int64 = 4
    static let bin: Int64 = 8

    static func allowsRead(_ fam: Int64) -> Bool {
        if fam & rdwr != 0 { return true }
        if fam & rdonly != 0 { return true }
        if fam & wronly != 0 { return false }
        return true
    }

    static func allowsWrite(_ fam: Int64) -> Bool {
        fam & (wronly | rdwr) != 0
    }
}

/// One open Forth file (buffered; dirty data flushed on CLOSE/FLUSH).
struct ForthFileEntry {
    var path: String
    var data: Data
    var position: Int
    var fam: Int64
    var isOpen: Bool
    var writeDirty: Bool
}

/// File-Access table shared by kernel hooks.
final class FileAccess {
    static let shared = FileAccess()

    static let iorOK: Int64 = 0
    static let iorErr: Int64 = -1

    private var files: [Int: ForthFileEntry] = [:]
    private var nextId = 1
    private let lock = NSLock()

    private init() {}

    // MARK: - Paths

    /// Resolve a Forth path string relative to FileHost logical cwd.
    /// Honors **FROMLIB** when armed (same as FLOAD/INCLUDE): relative paths under
    /// `Resources/Library`, then clear the flag so one-shot arming matches TZForth.
    func resolvePath(_ name: String) -> URL {
        var n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.hasPrefix("~") {
            n = NSString(string: n).expandingTildeInPath
        }
        if n.hasPrefix("/") {
            return URL(fileURLWithPath: n).standardizedFileURL
        }
        // FROMLIB SZEDIT Editor/foo.txt  →  OPEN-FILE under bundle Library
        if FileHost.shared.fromLibraryArmed, let lib = FileHost.shared.libraryURL {
            FileHost.shared.clearFromLibrary()
            return lib.appendingPathComponent(n).standardizedFileURL
        }
        let base = FileHost.shared.logicalCurrentDirectory
        return URL(fileURLWithPath: base)
            .appendingPathComponent(n)
            .standardizedFileURL
    }

    /// Writable location for create/write (avoid read-only app bundle).
    func writableURL(for preferred: URL) -> URL {
        let path = preferred.path
        if let res = Bundle.main.resourceURL?.path, path.hasPrefix(res) {
            return applicationSupportDir().appendingPathComponent(preferred.lastPathComponent)
        }
        if path.hasPrefix(Bundle.main.bundlePath) {
            return applicationSupportDir().appendingPathComponent(preferred.lastPathComponent)
        }
        return preferred
    }

    func applicationSupportDir() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("64Forth", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Ensure parent directory exists so createFile/write can succeed.
    private func ensureParentDirectory(of url: URL) -> Bool {
        let parent = url.deletingLastPathComponent()
        if parent.path.isEmpty || parent.path == "/" { return true }
        do {
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
            return true
        } catch {
            return false
        }
    }

    // MARK: - Open / close

    func openFile(path: String, fam: Int64, create: Bool) -> (fileid: Int64, ior: Int64) {
        lock.lock()
        defer { lock.unlock() }

        var url = resolvePath(path)
        let write = FileAccessMode.allowsWrite(fam) || create
        if write {
            url = writableURL(for: url)
        }

        var data = Data()
        if create {
            // Truncate / create empty — parent dir must exist (e.g. Application Support/64Forth).
            guard ensureParentDirectory(of: url) else { return (0, Self.iorErr) }
            data = Data()
            let ok = FileManager.default.createFile(atPath: url.path, contents: data, attributes: nil)
            if !ok && !FileManager.default.fileExists(atPath: url.path) {
                return (0, Self.iorErr)
            }
        } else {
            if let existing = try? Data(contentsOf: url) {
                data = existing
            } else if write {
                guard ensureParentDirectory(of: url) else { return (0, Self.iorErr) }
                data = Data()
                let ok = FileManager.default.createFile(atPath: url.path, contents: data, attributes: nil)
                if !ok && !FileManager.default.fileExists(atPath: url.path) {
                    return (0, Self.iorErr)
                }
            } else {
                return (0, Self.iorErr)
            }
        }

        // W/O often starts at EOF for append-like use; Hayes OPEN W/O then WRITE from start
        // after CREATE — position 0 is correct for create; for OPEN W/O of existing, ANS
        // does not require truncate — Hayes opens after create so empty.
        let pos = 0
        let id = nextId
        nextId += 1
        files[id] = ForthFileEntry(
            path: url.path,
            data: data,
            position: pos,
            fam: fam,
            isOpen: true,
            writeDirty: create
        )
        return (Int64(id), Self.iorOK)
    }

    func closeFile(_ fileid: Int64) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        let id = Int(fileid)
        guard var e = files[id], e.isOpen else { return Self.iorErr }
        if e.writeDirty {
            do {
                try e.data.write(to: URL(fileURLWithPath: e.path), options: .atomic)
            } catch {
                return Self.iorErr
            }
        }
        e.isOpen = false
        files[id] = e
        files.removeValue(forKey: id)
        return Self.iorOK
    }

    func flushFile(_ fileid: Int64) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        let id = Int(fileid)
        guard var e = files[id], e.isOpen else { return Self.iorErr }
        if e.writeDirty {
            do {
                try e.data.write(to: URL(fileURLWithPath: e.path), options: .atomic)
                e.writeDirty = false
                files[id] = e
            } catch {
                return Self.iorErr
            }
        }
        return Self.iorOK
    }

    // MARK: - Read / write

    func readFile(fileid: Int64, buffer: UnsafeMutablePointer<UInt8>?, length: Int) -> (n: Int64, ior: Int64) {
        lock.lock()
        defer { lock.unlock() }
        let id = Int(fileid)
        guard length >= 0, var e = files[id], e.isOpen else {
            return (0, Self.iorErr)
        }
        if !FileAccessMode.allowsRead(e.fam) {
            return (0, Self.iorErr)
        }

        let avail = max(0, e.data.count - e.position)
        let n = min(length, avail)
        if n > 0, let buffer {
            e.data.copyBytes(to: buffer, from: e.position..<(e.position + n))
        }
        e.position += n
        files[id] = e
        return (Int64(n), Self.iorOK)
    }

    func writeFile(fileid: Int64, buffer: UnsafePointer<UInt8>?, length: Int) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        let id = Int(fileid)
        guard length >= 0, var e = files[id], e.isOpen else { return Self.iorErr }
        if !FileAccessMode.allowsWrite(e.fam) {
            return Self.iorErr
        }

        let needed = e.position + length
        if needed > e.data.count {
            e.data.append(Data(count: needed - e.data.count))
        }
        if length > 0, let buffer {
            for i in 0..<length {
                e.data[e.position + i] = buffer[i]
            }
        }
        e.position += length
        e.writeDirty = true
        files[id] = e
        return Self.iorOK
    }

    func writeLine(fileid: Int64, buffer: UnsafePointer<UInt8>?, length: Int) -> Int64 {
        let w = writeFile(fileid: fileid, buffer: buffer, length: length)
        if w != Self.iorOK { return w }
        var nl: UInt8 = 10
        return withUnsafePointer(to: &nl) { p in
            writeFile(fileid: fileid, buffer: p, length: 1)
        }
    }

    func readLine(fileid: Int64, buffer: UnsafeMutablePointer<UInt8>?, maxLen: Int)
        -> (u2: Int64, flag: Int64, ior: Int64)
    {
        lock.lock()
        defer { lock.unlock() }
        let id = Int(fileid)
        guard maxLen >= 0, var e = files[id], e.isOpen else {
            return (0, 0, Self.iorErr)
        }
        if e.position >= e.data.count {
            return (0, 0, Self.iorOK) // EOF: u2=0 flag=false
        }
        var n = 0
        var sawNL = false
        while n < maxLen && e.position < e.data.count {
            let b = e.data[e.position]
            e.position += 1
            if b == 10 {
                sawNL = true
                break
            }
            if b == 13 {
                // swallow optional LF after CR
                if e.position < e.data.count && e.data[e.position] == 10 {
                    e.position += 1
                }
                sawNL = true
                break
            }
            buffer?[n] = b
            n += 1
        }
        files[id] = e
        // At EOF with zero chars: flag false
        if !sawNL && e.position >= e.data.count && n == 0 {
            return (0, 0, Self.iorOK)
        }
        // ANS: flag true if a line was read (including last line without NL)
        let lineFlag: Int64 = (n > 0 || sawNL) ? -1 : 0
        return (Int64(n), lineFlag, Self.iorOK)
    }

    func filePosition(_ fileid: Int64) -> (lo: Int64, hi: Int64, ior: Int64) {
        lock.lock()
        defer { lock.unlock() }
        guard let e = files[Int(fileid)], e.isOpen else {
            return (0, 0, Self.iorErr)
        }
        return (Int64(e.position), 0, Self.iorOK)
    }

    func fileSize(_ fileid: Int64) -> (lo: Int64, hi: Int64, ior: Int64) {
        lock.lock()
        defer { lock.unlock() }
        guard let e = files[Int(fileid)], e.isOpen else {
            return (0, 0, Self.iorErr)
        }
        return (Int64(e.data.count), 0, Self.iorOK)
    }

    func repositionFile(fileid: Int64, lo: Int64, hi: Int64) -> Int64 {
        _ = hi
        lock.lock()
        defer { lock.unlock() }
        let id = Int(fileid)
        guard var e = files[id], e.isOpen else { return Self.iorErr }
        let pos = Int(lo)
        if pos < 0 || pos > e.data.count { return Self.iorErr }
        e.position = pos
        files[id] = e
        return Self.iorOK
    }

    func resizeFile(fileid: Int64, lo: Int64, hi: Int64) -> Int64 {
        _ = hi
        lock.lock()
        defer { lock.unlock() }
        let id = Int(fileid)
        guard var e = files[id], e.isOpen else { return Self.iorErr }
        let newSize = Int(lo)
        if newSize < 0 { return Self.iorErr }
        if newSize > e.data.count {
            e.data.append(Data(count: newSize - e.data.count))
        } else if newSize < e.data.count {
            e.data = e.data.prefix(newSize)
        }
        if e.position > newSize { e.position = newSize }
        e.writeDirty = true
        files[id] = e
        return Self.iorOK
    }

    func deleteFile(path: String) -> Int64 {
        let url = writableURL(for: resolvePath(path))
        do {
            try FileManager.default.removeItem(at: url)
            return Self.iorOK
        } catch {
            // also try raw resolve
            do {
                try FileManager.default.removeItem(at: resolvePath(path))
                return Self.iorOK
            } catch {
                return Self.iorErr
            }
        }
    }

    func renameFile(from: String, to: String) -> Int64 {
        let a = writableURL(for: resolvePath(from))
        let b = writableURL(for: resolvePath(to))
        do {
            if FileManager.default.fileExists(atPath: b.path) {
                try FileManager.default.removeItem(at: b)
            }
            try FileManager.default.moveItem(at: a, to: b)
            return Self.iorOK
        } catch {
            return Self.iorErr
        }
    }

    func fileStatus(path: String) -> (x: Int64, ior: Int64) {
        let url = resolvePath(path)
        if FileManager.default.fileExists(atPath: url.path) {
            return (0, Self.iorOK)
        }
        let w = writableURL(for: url)
        if FileManager.default.fileExists(atPath: w.path) {
            return (0, Self.iorOK)
        }
        return (-1, Self.iorErr)
    }
}
