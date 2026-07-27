# 64Forth — Design & Integration Plan

**Public domain.**  
**Goal:** A macOS **SwiftUI app** (console + file/library UX from TZForth) driven by an **ARM64 assembly ITC kernel** (PickleForth lineage), not a pure terminal binary and not the full Swift lbForth engine.

---

## 1. What comes from where

| Piece | Source | Role in 64Forth |
|--------|--------|------------------|
| Kernel (ITC, dictionary, CODE/COLON bootstrap) | **PickleForth** `forth.s` + `boot_words.inc` + `colon_words.inc` | Execution engine |
| Console UI, menus, history, protected output region | **TZForth** `ConsoleView` / `ContentView` / `TZForthApp` | Host REPL surface |
| Resources layout (`AutoLoad/`, `Library/`, `Docs/`) | **TZForth** `Contents/Resources` pattern | Bundled libraries & samples |
| FROMLIB / FROM-LIBRARY, named FLOAD, CHDIR, sandbox scope | **TZForth** host file architecture | Path resolution for loads |
| Float/BigInt/Block/XChar (optional later) | TZForth or new ports | Not required for v0.1 |

---

## 2. Target architecture

```text
┌─────────────────────────────────────────────────────────┐
│  SwiftUI App (64ForthApp / ContentView / ConsoleView)   │
│    • line commit → host.feedLine(String)                │
│    • menus: FLOAD, CHDIR, AutoLoad, Library, Docs       │
│    • security-scoped bookmarks (as TZForth)               │
└───────────────────────────┬─────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────┐
│  Host layer (Swift)                                       │
│    • KernelBridge — C ABI to assembly                     │
│    • FileHost — resolve paths, FROMLIB, open/read files  │
│    • I/O: capture kernel putchar → console append        │
│    • KEY: deliver keystrokes into kernel when blocked    │
└───────────────────────────┬─────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────┐
│  Kernel (ARM64 assembly)                                  │
│    • _kernel_cold_start / _kernel_init / feed API (phased)│
│    • Dictionary, NEXT, BOOT_WORD, DOC", INCLUDE/FLOAD    │
│    • Eventually: host-hooked EMIT/KEY instead of raw TTY  │
└─────────────────────────────────────────────────────────┘
```

**v0.1 reality:** Kernel still has terminal-style I/O (`svc` read/write) and a standalone cold start. The app builds, shows a console stub, and documents the bridge. Full line feed + FROMLIB is Phase 2–3.

---

## 3. Phased plan

### Phase 0 — Scaffold (this check-in)
- [x] Repo/folder under `XCodeProjects/64Forth`
- [x] Copy Pickle kernel; rename entry `_kernel_cold_start` (no clash with Swift `@main`)
- [x] Minimal SwiftUI app + `KernelBridge` stubs
- [x] Resource folders: AutoLoad, Library (samples), Docs
- [x] DESIGN.md + README.md

### Phase 1 — Embeddable kernel API
- Export C-callable:
  - `kernel_init(void)` — cold dictionary build, no infinite QUIT
  - `kernel_eval(const char *line, size_t n)` — interpret one line / buffer
  - `kernel_set_emit(void (*fn)(int c))` / `kernel_set_key(int (*fn)(void))`
- Split PickleForth’s `_quit_loop` so init does not block the UI thread forever
- Host: `KernelBridge.shared.eval(line)` → console

### Phase 2 — Console parity (TZForth UX)
- Port ConsoleView patterns: protected region, history, Return handling
- Wire feedLine → kernel_eval; append emit buffer to consoleText
- Menus: CLS, FLOAD panel, CHDIR, open Library/AutoLoad/Docs in Finder

### Phase 3 — File / FROMLIB architecture
- Port TZForth resolution:
  - `logicalCurrentDirectory`
  - FROMLIB sets “next path base = Bundle Resources/Library”
  - Named FLOAD: resolve relative to cwd or library; host opens file, passes text to kernel (or kernel open via host callback)
- Kernel `INCLUDE`/`FLOAD`: either keep syscalls with host-supplied absolute paths, or host loads entire file and `EVALUATE`s / nested SOURCE (Pickle already has SOURCE stack)

### Phase 4 — AutoLoad
- On launch: if `Resources/AutoLoad/autoload.fth` exists, load after kernel_init (TZForth `runAutoLoadIfPresent`)

### Phase 5 — Hardening
- No blocking QUIT on main thread (background or cooperative REPL)
- Sandbox entitlements / bookmarks as TZForth
- Optional: port Hayes suite under Library/HayesTest when INCLUDE is solid

---

## 4. FROMLIB (intended semantics)

From TZForth:

- `FROMLIB` (or FROM-LIBRARY) sets a flag / next-resolve-root to  
  `Bundle.main.resourceURL/Library`
- Next `FLOAD` / `INCLUDE` / `EDIT` / `CHDIR` / open-file uses that root
- Relative names: `FROMLIB FLOAD BigInteger/big-int.fth`
- Session cwd for user files remains separate (Documents / last CHDIR)

64Forth will implement this in **Swift FileHost**, not by re-creating the whole TZForth engine.

---

## 5. Kernel vs host ownership

| Concern | Owner |
|---------|--------|
| Dictionary, compilation, arithmetic, SEE/HELP | Kernel |
| Display buffer, menus, panels | Host |
| Path resolution, bundle roots, sandbox | Host |
| Opening file bytes for FLOAD | Host (preferred) or kernel syscall with absolute path from host |
| EMIT / KEY while UI owns the window | Host callbacks into kernel |

---

## 6. Relationship to PickleForth & TZForth

- **PickleForth** remains the pure terminal / kernel lab (fast iteration on assembly).
- **TZForth** remains the full Swift Forth product.
- **64Forth** is the hybrid product: pick the best of both.
- Kernel fixes can be cherry-picked between PickleForth ↔ 64Forth/Kernel until they diverge.

---

## 7. Open decisions (for later)

1. App sandbox on/off for first public builds  
2. Whether INCLUDE stays raw `open`/`read` or always host-injected  
3. Single-threaded kernel only vs re-entrancy rules for KEY  
4. Branding / icon (TZForth icons vs new)

---

## 8. Chat / Grok workflow (see also README)

Work on **64Forth** with Grok’s working directory set to:

`/Users/thomaszimmer/Documents/XCodeProjects/64Forth`

Keep **PickleForth** sessions separate for terminal-kernel-only work.  
Do not mix “commit PickleForth” and “scaffold 64Forth” in one ambiguous chat if avoidable.
