# 64Forth agent channel

**Public domain.** Headless control so tools (Grok, CI, scripts) can load Forth files and capture console output without driving the GUI.

**Status:** shipped (**64Forth 1.1.2+**; current **1.3.2**, build 31). Rebuild the app in Xcode before the installed binary supports `--agent`. See also [STATUS.md](STATUS.md) (section **v1.1.2 — agent channel**).

## Why

The GUI app does not treat stdin as a REPL. Accessibility can type keys but cannot reliably read the SwiftUI console. The agent channel runs the same kernel (`kernel_eval`) with EMIT captured to **stdout** and an optional transcript file.

## Activation

Either:

```text
64Forth --agent …
```

or:

```text
FORTH64_AGENT=1 64Forth …
```

Invoke the **binary inside the bundle**, not `open -a` (open does not give a clean stdout pipe):

```bash
/Applications/64Forth.app/Contents/MacOS/64Forth --agent -e '2 2 + .'
```

Helper:

```bash
./tools/64forth-agent -e '2 2 + .'
./tools/64forth-agent --help
```

## Options

| Flag | Meaning |
|------|---------|
| `-e` / `--eval <line>` | Evaluate one line |
| `-f` / `--file <path>` | `INCLUDE` a file (`--fload` / `--include` aliases) |
| `-c` / `--cwd <path>` | `chdir` before work |
| `-o` / `--out <path>` | Write full transcript to path (stdout always has it) |
| `--autoload` | Run AutoLoad + MAIN first |
| `--no-autoload` | Default in agent mode — skip AutoLoad |
| `--repl` | After `-e`/`-f`, read more lines from stdin until EOF or `BYE` |
| `-h` / `--help` | Help |

`-e` and `-f` may repeat; order is preserved.

## Exit status

- `0` — every eval/load returned status 0  
- `1` — usage error, kernel init failure, any non-zero status, or transcript write failure  

Each step is tagged in the transcript:

```text
[64Forth agent] eval: 2 2 + .
4
[64Forth agent] status=0 depth=0
```

## Relation to GUI

Agent mode is a **separate process**. Your interactive 64Forth window is untouched. It does not inject into a running GUI session (that would need a future socket).

## Relation to 64TCOM

Cross-project note: 64TCOM’s project-root `STATUS.md` (under Documents) documents host automation for TCOM demos. Typical:

```bash
…/64Forth --agent -c ~/Documents/64TCOM/64TCOMARM64 \
  -e 'FLOAD TARGETARM64.fth' -f IFDEMO.fth -o /tmp/ifdemo.txt
```

## Grok / AI sessions

You do **not** need to restart Grok from the 64Forth project folder. A session rooted at `Documents` (or 64TCOM) can still edit and run tools under `XCodeProjects/64Forth`. After source changes: **rebuild the app** in Xcode; restarting the chat does not install a new binary.

## Implementation notes

| File | Role |
|------|------|
| `App/AppMain.swift` | `@main` — agent branch or `SixtyFourForthApp.main()` |
| `App/AgentChannel.swift` | Args, cwd, eval/load, transcript, exit codes |
| `Host/KernelBridge.swift` | `setAgentSyncEmit`, `forceFlushEmitSync`; skip key monitor in agent mode |
| `tools/64forth-agent` | Find binary + pass `--agent` |
| `SZFLTEST=1` | Separate specialized Editor harness (unchanged) |

## Build

1. Open `64Forth.xcodeproj` in **Xcode** (full Xcode, not only Command Line Tools).  
2. Build (Debug or Release).  
3. Run the **built** binary, or copy/install to `/Applications/64Forth.app`.  
4. Smoke: `…/MacOS/64Forth --agent -e '2 2 + .'` → expect `4` and `DONE (ok)`.

Optional: `FORTH64_APP=/path/to/64Forth.app ./tools/64forth-agent -e '2 2 + .'`
