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

**v0.1 reality:** Phase 1 embed API is wired: host sets emit/key hooks, calls `kernel_init` once, then `kernel_eval` per line. Fallback TTY syscalls remain for terminal `_kernel_cold_start` and when hooks are unset. Console protected-region parity and FROMLIB→kernel FLOAD are Phase 2–3.

---

## 3. Phased plan

### Phase 0 — Scaffold (this check-in)
- [x] Repo/folder under `XCodeProjects/64Forth`
- [x] Copy Pickle kernel; rename entry `_kernel_cold_start` (no clash with Swift `@main`)
- [x] Minimal SwiftUI app + `KernelBridge` stubs
- [x] Resource folders: AutoLoad, Library (samples), Docs
- [x] DESIGN.md + README.md

### Phase 1 — Embeddable kernel API
- [x] Export C-callable:
  - `kernel_init(void)` — cold dictionary build, no infinite QUIT
  - `kernel_eval(const char *line, size_t n)` — interpret one line / buffer
  - `kernel_set_emit(void (*fn)(int c))` / `kernel_set_key(int (*fn)(void))`
- [x] Split PickleForth’s `_quit_loop` so init does not block the UI thread forever
- [x] Host: `KernelBridge.shared.evaluate(line)` → emit → console
- [x] `kernel_api.h` documents the ABI; `_kernel_cold_start` remains terminal-only
- Notes: KEY queue is stubby (−1 when empty); ACCEPT/REFILL still TTY-oriented; full console protected region is Phase 2

### Phase 2 — Console parity (TZForth UX)
- [x] Port ConsoleView patterns: protected region, history, Return handling
- [x] AppKit `ConsoleTextView` (NSTextView): editableStart, scroll-to-caret
- [x] Wire feedLine → `KernelBridge.evaluate`; emit → console
- [x] Menus: CLS, FLOAD panel, CHDIR, open Library/AutoLoad/Docs in Finder
- Notes: KEY still stubby; FLOAD uses kernel `INCLUDE` with absolute path (spaces fragile); full FROMLIB resolve is Phase 3

### Phase 3 — File / FROMLIB architecture
- [x] Port TZForth resolution in `FileHost`:
  - `logicalCurrentDirectory`
  - FROMLIB sets “next path base = Bundle Resources/Library” (+ cwd switch for nested relatives)
  - Named FLOAD/INCLUDE/REQUIRE: host opens file, pins buffer, kernel nests SOURCE
- [x] Kernel: `FROMLIB`/`FROM-LIBRARY` CODE words → `fromlib_hook`
- [x] Kernel: `INCLUDE` uses `load_file_hook` when set (else terminal open/read)
- [x] `FLOAD` / `REQUIRE` aliases of `INCLUDE`; `word_scratch` 512 for long paths
- [x] TZForth-style host words: bare `FLOAD`/`INCLUDE` → open panel; `CHDIR` path|dialog; `PWD`
- [x] Bare FLOAD no longer mis-reports `can't open: FLOAD` (stale word_scratch)
- Notes: library `.fth` may need TZForth words (ALLOCATE, vocabularies, …) not in Pickle kernel; path-with-spaces still limited by WORD parse; AutoLoad on launch is Phase 4

### Phase 4 — AutoLoad
- [x] On launch: if `Resources/AutoLoad/autoload.fth` exists, load after console attaches (TZForth `runAutoLoadIfPresent`)
- [x] During load: cwd = AutoLoad/ so nested relative FLOAD works; restore cwd after
- [x] Run `MAIN` if defined (plain `MAIN` after load)
- [x] Default `autoload.fth` (MAIN); `ANEW` is a single kernel definition

### Phase 5 — Hardening (+ DIR)
- [x] **DIR** host word (TZForth-style: bare cwd, path, `*`/`?` filters, FROMLIB → Library)
- [x] Eval **reentrancy guard** (`isEvaluating` / try-lock; kernel not re-entrant)
- [x] **Entitlements**: App Sandbox off for v0.1 (`64Forth.entitlements`); ready to flip later
- [x] **Security-scoped bookmarks** + last cwd persistence (UserDefaults) for panel picks / CHDIR
- [ ] Optional later: background kernel_eval for huge loads; full sandbox + Hayes suite

### Phase 6 — Search-Order, BIG-INTEGER, host BI math
- [x] Multi-wordlist FIND + CURRENT linking (`_header_build` / `_find_word`)
- [x] Search-Order words: WORDLIST, ONLY, ALSO, DEFINITIONS, FORTH, ORDER, GET/SET-ORDER, …
- [x] `VOCABULARY` + `BIG-INTEGER` / `EDITOR` / `ASSEMBLER` at bootstrap
- [x] `ALLOCATE` / `FREE` host hooks
- [x] Host `BI-MUL` / `BI-DIVMOD` / `BI-ISQRT` (`BigIntHost.swift`, TZForth algorithms)
- [x] Locals: `{: … :}`, `TO`, `(LOCAL-INIT)` / `(LOCAL@)` / `(LOCAL!)` for stock `big-int.fth`

### Phase 7 — File registry, FORGET, RESIZE, KEY
- [x] ANS-shaped `INCLUDED` / `REQUIRED` / `REQUIRE` (`PARSE-NAME REQUIRED`)
- [x] Absolute-path REQUIRE registry keys (host resolve + last-load key hooks)
- [x] `.INCLUDED` lists the load-once registry
- [x] `FORGET` multi-wordlist prune + USER-DICT fence (CODE)
- [x] `RESIZE` (libc realloc)
- [x] Quoted paths with spaces: `INCLUDE "path with spaces.fth"`
- [x] Console KEY: pushKey from typing + run-loop wait in host KEY hook

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
