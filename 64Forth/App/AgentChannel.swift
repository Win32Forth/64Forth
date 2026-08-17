//
//  AgentChannel.swift
//  64Forth
//
//  Public domain.
//
//  Headless / agent control channel for automation (Grok, CI, scripts).
//  Loads Forth sources, evaluates lines, captures all console EMIT to stdout
//  and an optional transcript file — no GUI required.
//
//  Activation (either):
//    • argv contains `--agent`  (or `-agent`)
//    • environment FORTH64_AGENT=1  (alias: 64FORTH_AGENT=1 via env(1))
//
//  Usage examples:
//    64Forth --agent -e '2 2 + .'
//    64Forth --agent -f /path/to/script.fth -o /tmp/out.txt
//    64Forth --agent --cwd ~/Documents/64TCOM/64TCOMARM64 -f IFDEMO.fth
//    64Forth --agent --repl < commands.txt
//    FORTH64_AGENT=1 64Forth -e 'WORDS'
//
//  Options (order of -e / -f is preserved):
//    --agent | -agent     enable agent mode (required unless env set)
//    -e <text>            evaluate one Forth line
//    -f <path>            INCLUDE / FLOAD a file (absolute or relative)
//    -c | --cwd <path>    chdir before work (also sets logical FileHost cwd)
//    -o | --out <path>    write full transcript to file (also always stdout)
//    --no-autoload        skip Resources/AutoLoad/autoload.fth
//    --autoload           force AutoLoad (default: off in agent mode)
//    --repl               after scripts, read lines from stdin until EOF
//    -h | --help          print this help and exit 0
//
//  Exit status:
//    0  all evaluations returned 0 (ok)
//    1  usage / kernel init / any eval non-zero / I/O error
//

import Foundation
#if os(macOS)
import AppKit
#endif

enum AgentChannel {

    /// True when process should run headless agent instead of the GUI.
    static var isRequested: Bool {
        let env = ProcessInfo.processInfo.environment
        // Prefer FORTH64_AGENT (shell-safe). 64FORTH_AGENT works with env(1) only.
        if env["FORTH64_AGENT"] == "1" || env["64FORTH_AGENT"] == "1" {
            return true
        }
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--agent") || args.contains("-agent")
    }

    /// Parse argv and run; does not return (calls Foundation.exit).
    static func runAndExit() -> Never {
        let code = run()
        Foundation.exit(code)
    }

    /// Parse argv, run agent session, return process exit code.
    @discardableResult
    static func run() -> Int32 {
        let parsed = parseArgs(ProcessInfo.processInfo.arguments)
        if parsed.help {
            printHelp()
            return 0
        }

        #if os(macOS)
        // Minimal AppKit so any host code that touches NSApp does not crash.
        // No windows; we never run the SwiftUI scene.
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        #endif

        var transcript = ""
        let transcriptLock = NSLock()
        let appendOut: (String) -> Void = { s in
            guard !s.isEmpty else { return }
            transcriptLock.lock()
            transcript += s
            transcriptLock.unlock()
            if let data = s.data(using: .utf8) {
                FileHandle.standardOutput.write(data)
            }
        }

        let kernel = KernelBridge.shared
        kernel.setAgentSyncEmit(true)
        kernel.onEmit = { chunk in
            appendOut(chunk)
        }
        // Flush anything buffered during KernelBridge.init before onEmit was set.
        kernel.forceFlushEmitSync()

        appendOut("[64Forth agent] start\n")
        if !kernel.isKernelLive {
            appendOut("[64Forth agent] FATAL: kernel_init failed\n")
            writeTranscriptIfNeeded(parsed.outPath, transcript)
            return 1
        }

        if let cwd = parsed.cwd {
            let fm = FileManager.default
            if fm.changeCurrentDirectoryPath(cwd) {
                FileHost.shared.logicalCurrentDirectory = cwd
                appendOut("[64Forth agent] cwd \(cwd)\n")
            } else {
                appendOut("[64Forth agent] ERROR: cannot chdir \(cwd)\n")
                writeTranscriptIfNeeded(parsed.outPath, transcript)
                return 1
            }
        }

        // Default: no AutoLoad in agent mode (deterministic scripts). Opt in with --autoload.
        if parsed.autoload {
            appendOut("[64Forth agent] AutoLoad…\n")
            _ = kernel.runAutoLoadIfPresent()
            kernel.forceFlushEmitSync()
        }

        var failed = false
        for step in parsed.steps {
            switch step {
            case .eval(let line):
                appendOut("[64Forth agent] eval: \(line)\n")
                let st = kernel.evaluate(line)
                kernel.forceFlushEmitSync()
                appendOut("[64Forth agent] status=\(st) depth=\(kernel.dataStackDepth)\n")
                if st != 0 { failed = true }
            case .file(let path):
                appendOut("[64Forth agent] load: \(path)\n")
                let st = kernel.loadFile(named: path)
                kernel.forceFlushEmitSync()
                appendOut("[64Forth agent] status=\(st) depth=\(kernel.dataStackDepth)\n")
                if st != 0 { failed = true }
            }
        }

        if parsed.repl {
            appendOut("[64Forth agent] repl (stdin) — EOF to finish\n")
            while let line = readLine(strippingNewline: true) {
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { continue }
                if t.uppercased() == "BYE" {
                    appendOut("[64Forth agent] BYE\n")
                    break
                }
                let st = kernel.evaluate(t)
                kernel.forceFlushEmitSync()
                appendOut("ok(\(kernel.dataStackDepth))> ")
                if st != 0 { failed = true }
            }
            appendOut("\n")
        }

        if parsed.steps.isEmpty && !parsed.repl && !parsed.autoload {
            appendOut("[64Forth agent] nothing to do (use -e, -f, --repl, or --autoload)\n")
            appendOut("Try: 64Forth --agent --help\n")
            failed = true
        }

        appendOut(failed
            ? "[64Forth agent] DONE (failed)\n"
            : "[64Forth agent] DONE (ok)\n")

        if !writeTranscriptIfNeeded(parsed.outPath, transcript) {
            failed = true
        }

        kernel.setAgentSyncEmit(false)
        return failed ? 1 : 0
    }

    // MARK: - Args

    private enum Step {
        case eval(String)
        case file(String)
    }

    private struct Parsed {
        var help = false
        var autoload = false
        var repl = false
        var cwd: String?
        var outPath: String?
        var steps: [Step] = []
    }

    private static func parseArgs(_ argv: [String]) -> Parsed {
        var p = Parsed()
        var i = 1 // skip argv[0]
        while i < argv.count {
            let a = argv[i]
            switch a {
            case "--agent", "-agent":
                i += 1
            case "-h", "--help", "-help":
                p.help = true
                i += 1
            case "--no-autoload":
                p.autoload = false
                i += 1
            case "--autoload":
                p.autoload = true
                i += 1
            case "--repl":
                p.repl = true
                i += 1
            case "-e", "--eval":
                i += 1
                guard i < argv.count else {
                    p.help = true
                    break
                }
                p.steps.append(.eval(argv[i]))
                i += 1
            case "-f", "--file", "--fload", "--include":
                i += 1
                guard i < argv.count else {
                    p.help = true
                    break
                }
                p.steps.append(.file(argv[i]))
                i += 1
            case "-c", "--cwd":
                i += 1
                guard i < argv.count else {
                    p.help = true
                    break
                }
                p.cwd = (argv[i] as NSString).expandingTildeInPath
                i += 1
            case "-o", "--out", "--transcript":
                i += 1
                guard i < argv.count else {
                    p.help = true
                    break
                }
                p.outPath = (argv[i] as NSString).expandingTildeInPath
                i += 1
            default:
                // Ignore unknown GUI leftovers (e.g. probe-arg); warn once-ish via step log.
                if a.hasPrefix("-") {
                    FileHandle.standardError.write(Data("[64Forth agent] unknown option: \(a)\n".utf8))
                }
                i += 1
            }
        }
        return p
    }

    private static func writeTranscriptIfNeeded(_ path: String?, _ text: String) -> Bool {
        guard let path, !path.isEmpty else { return true }
        do {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: url, atomically: true, encoding: .utf8)
            let note = "[64Forth agent] transcript → \(path)\n"
            FileHandle.standardOutput.write(Data(note.utf8))
            return true
        } catch {
            let msg = "[64Forth agent] ERROR writing transcript \(path): \(error)\n"
            FileHandle.standardError.write(Data(msg.utf8))
            return false
        }
    }

    private static func printHelp() {
        let help = """
        64Forth agent channel — headless load / eval / capture

        64Forth --agent [options]

        Options:
          -e, --eval <line>       Evaluate a Forth line
          -f, --file <path>       INCLUDE file (also --fload / --include)
          -c, --cwd <path>        Change directory before work
          -o, --out <path>        Write full transcript to path (stdout always)
          --autoload              Run Resources AutoLoad + MAIN first
          --no-autoload           Skip AutoLoad (default in agent mode)
          --repl                  Read further lines from stdin until EOF or BYE
          -h, --help              This help

        Environment:
          FORTH64_AGENT=1         Same as --agent (shell-safe name)

        Examples:
          64Forth --agent -e '2 2 + .'
          64Forth --agent -c ~/proj -f smoke.fth -o /tmp/out.txt
          64Forth --agent --repl < session.txt

        Notes:
          • Prefer invoking the binary inside the app bundle, not `open -a`.
          • GUI instance (if already open) is separate; agent is a new process.
          • Exit 0 = all steps status 0; exit 1 = any failure.

        """
        print(help, terminator: "")
    }
}
