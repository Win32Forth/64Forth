# 64Forth — Design Document

**Public domain.**  
**Updated:** 2026-07-29 — **v0.6.0** (Core/Core Ext polish, FIND-before-number, Tools `?`, Hayes harness under `src/Harness/`, full Hayes subset green including paranoia Excellent).

**Goal:** A macOS **SwiftUI app** (console + file/library UX from TZForth) driven by an **ARM64 assembly ITC kernel** (PickleForth lineage)—not a pure terminal binary and not the full Swift lbForth / TZForth engine.

---

## 1. What comes from where

| Piece | Source | Role in 64Forth |
|--------|--------|------------------|
| Kernel (ITC, dictionary, CODE/COLON bootstrap) | **PickleForth** `forth.s` + `boot_words.inc` + `colon_words.inc` | Execution engine |
| Console UI, menus, history, protected output region | **TZForth** `ConsoleView` / `ContentView` / app shell | Host REPL surface |
| Resources layout (`AutoLoad/`, `Library/`, `Docs/`) | **TZForth** bundle pattern | Bundled libraries & samples |
| FROMLIB / FLOAD / CHDIR / DIR / EDIT | **TZForth** host file architecture | Path resolution & UX |
| Host multiprecision BI-MUL / BI-DIVMOD / BI-ISQRT | **TZForth** algorithms (`BigIntHost.swift`) | BIG-INTEGER library support |
| Floating-point (IEEE-64 F-stack, parse/print) | **TZForth** `TZForthFloat.swift` → `FloatHost.swift` | **`VOCABULARY FP`** (public names); thin FORTH hooks `FLIT` / `(F-OP)` |
| File-Access + Block volumes | TZForth-style host + kernel CODE | `FileAccess.swift`, block file words, Hayes prepare-blocks |
| XChar / SZ-EDITOR productization | TZForth (optional later) | Not required for Hayes subset |

---

## 2. Architecture (as built)

```text
┌─────────────────────────────────────────────────────────────┐
│  SwiftUI App (SixtyFourForthApp / ContentView / ConsoleView) │
│    • line / multi-line paste → KernelBridge.evaluate          │
│    • menus: FLOAD, CHDIR, EDIT, CLS, Library/AutoLoad/Docs  │
│    • security-scoped bookmarks + last cwd (UserDefaults)     │
│    • LLDB: .lldbinit-64forth passes SIGSEGV/SIGBUS to app    │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│  Host layer (Swift)                                           │
│    • KernelBridge — C ABI, emit/key, eval off-main + UI pump  │
│    • FileHost — FROMLIB, INCLUDE, DIR, EDIT, CHDIR (main panels)│
│    • FileAccess — OPEN-FILE … buffered table                  │
│    • BigIntHost — BI-MUL / BI-DIVMOD / BI-ISQRT (base 10^9)  │
│    • FloatHost — IEEE-64 F-stack (depth 16), float_op hook    │
│    • SIGSEGV/SIGBUS → kernel_on_memory_fault (soft recover)   │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│  Kernel (ARM64 assembly ITC)                                  │
│    • kernel_init / kernel_eval (embed); _kernel_cold_start    │
│    • Dictionary in user_dict_area; CODE bodies in .text       │
│    • INCLUDE nests whole-file SOURCE; FILE-ECHO; \S           │
│    • VOCABULARIES: FORTH, BIG-INTEGER, EDITOR, ASSEMBLER, FP  │
│    • GROWMEMORYMB raises logical dict size (CFA-stable)       │
└─────────────────────────────────────────────────────────────┘
```

**Embed vs terminal**

| Mode | Entry | Loop |
|------|--------|------|
| **App (embed)** | `kernel_init` once, then `kernel_eval` per line | Host owns UI; emit/key hooks |
| **Terminal** | `_kernel_cold_start` | Kernel QUIT / line editor (no SwiftUI) |

Do **not** call `_kernel_cold_start` from the SwiftUI host.

---

## 3. Phased delivery (historical + current)

### Phase 0–1 — Scaffold & embed API — **done**

- Repo, Pickle kernel copy (`_kernel_cold_start` not `_main`)
- `kernel_init` / `kernel_eval` / `kernel_set_emit` / `kernel_set_key`
- `kernel_api.h`; host evaluates lines into the console

### Phase 2 — Console parity — **done**

- Protected region, history, Return / multi-line paste
- AppKit `ConsoleTextView`; Tools menus (CLS, FLOAD, CHDIR, folder reveals)

### Phase 3 — File / FROMLIB — **done**

- `FileHost`: logical cwd, FROMLIB → `Resources/Library`, nested relatives
- Kernel `INCLUDE` via `load_file_hook`; `FLOAD` / `REQUIRE` aliases
- Bare FLOAD/CHDIR → panels; `PWD`; quoted paths with spaces

### Phase 4 — AutoLoad — **done**

- Launch: `Resources/AutoLoad/autoload.fth`, cwd = AutoLoad during load, then `MAIN` if defined
- `ANEW` is a **kernel** definition (not AutoLoad/ANEW.fth)

### Phase 5 — Hardening — **done** (+ optional follow-ups)

- **DIR** (wildcards, FROMLIB)
- Eval reentrancy guard; App Sandbox off for v0.1; bookmarks + cwd persistence
- Batched console emit + main-thread open panels (responsive long INCLUDE/Hayes)
- [ ] Later: full App Sandbox for store builds; further editor UX

### Phase 6 — Search-Order, BIG-INTEGER, locals — **done**

- Multi-wordlist FIND / CURRENT; WORDLIST, ONLY, ALSO, DEFINITIONS, ORDER, …
- `VOCABULARY` + `BIG-INTEGER` / `EDITOR` / `ASSEMBLER` / **`FP`**
- Host `ALLOCATE` / `FREE` / `RESIZE`; `BI-MUL` / `BI-DIVMOD` / `BI-ISQRT`
- Locals `{: … :}`, `TO` for stock `big-int.fth` / π

### Phase 7 — Registry, FORGET, KEY, quotes — **done**

- `INCLUDED` / `REQUIRED` / `REQUIRE` / `.INCLUDED` (absolute registry keys)
- Multi-wordlist `FORGET` + USER-DICT fence
- Console KEY (queue + run-loop wait)
- Quoted `INCLUDE "path with spaces.fth"`

### Phase 8 — Product polish (post–Phase 7) — **done**

| Item | Design notes |
|------|----------------|
| **EDIT** | Host opens file in system editor; honors FROMLIB; updates cwd |
| **`\S` / `\s`** | Immediate: pin `>IN` to end of current SOURCE (file/eval/line). Nested INCLUDE only stops the inner file. Console SOURCE-ID 0 sets host multi-line paste stop (`replBatchStop`) |
| **FILE-ECHO** | Echo INCLUDE/FLOAD source through emit_hook (not raw `write(1)`). Advance `file_echo_pos` **before** `_putchar` (emit clobbers caller-saved regs) |
| **ANS pictured `#` / `#S` / `#>`** | Double-cell (ud = lo under, hi TOS). Single-cell `#` broke `BI.` / π (`n 0 <# #S #>` printed only hi → `0.000…`) |
| **`.ELAPSED` / `.H2` / `.HA` / `U.R`** | Use `0 <# #S #>` (or equivalent) for single-cell values as doubles |
| **`ABORT"`** | Must test flag: compile `IF S" …" TYPE CR ABORT THEN` (old body always aborted → bubble-sort “not sorted”) |
| **PI pool** | Generous BI buffer budget; host BI capacity overflow must not soft-zero results |
| **WORDS** | First search-order wordlist only; optional filter. **System** words (CFA &lt; fence after bootstrap): A–Z under banner `64Forth System Words`. **User** words (CFA ≥ fence): load order under `64Forth User Words` (banner only if any) |
| **User dict memory** | See §6 |
| **Fault recovery** | See §7 |

---

## 3b. Word-set coverage — **v0.6.0 (Hayes subset green)**

| Word set | Status | Notes |
|----------|--------|--------|
| Core / Core Ext | **done** | CODE + `forth_init_str`; Tools `[IF]`/`[DEFINED]`/`[UNDEFINED]` |
| Double + String | **done** | Double CODE; `COMPARE`/`SEARCH`; pictured `#` double-cell |
| Exception | **done** | `CATCH`/`THROW`; soft uncaught THROW under embed |
| File-Access | **done** | Host `FileAccess` + CODE (`OPEN-FILE` … `FLUSH-FILE`) |
| Locals / Memory / Search-Order | **done** | `{: :}`, `ALLOCATE`, multi-wordlist |
| Facility | **done** | `MS` nanosleep; `KEY`/`KEY?`; `PAGE`/`AT-XY`; `TIME&DATE` |
| Block | **done** | File volume: `OPEN-BLOCK-FILE` / `CREATE-BLOCK-FILE` / `USE-BLOCK-FILE`; `prepare-blocks.fth` → Application Support |
| **Floating-point** | **done** | Host `FloatHost` (IEEE-64, 16-deep F-stack); public words in **`VOCABULARY FP`**; FORTH holds `FLIT` / `(F-OP)` / `FLIT-ADDR` only; float literals in outer interpreter |
| Extended Character | optional | Not required for current Hayes driver |

### Floating-point design (v0.5)

- **Not** pure assembly: same hybrid as BigInteger — Swift host + thin kernel multiplex (`kernel_set_float_op`).
- **Vocabulary:** `ALSO FP` to use `F+`, `F.`, `FVARIABLE`, …; default FORTH search order stays clean.
- **Literals:** `1.5e0` / `3.14` recognized by the outer interpreter (trailing-only `123.` remains double).
- **ENVIRONMENT?:** `FLOATING`, `FLOAT-EXT`, `FLOATING-STACK` (16), `MAX-FLOAT` (ttester double-`[IF]` needs value+true for FLOATING).

**Hayes driver:** `FROMLIB FLOAD HayesTest/HayesTest.fth`

- Resets `ONLY FORTH` then `ALSO FP` before FP suite (searchordertest leaves odd orders).
- Expect: `Running FP Tests` … `FP tests finished`, all `*ERRORS @ = 0`, including `FPERRORS` and `BERRORS`.

**File-Access / Block:** relative paths use logical cwd; bundle writes remap to `Application Support/64Forth/`; Hayes blocks file under `Application Support/64Forth/hayes-blocks.blk`.

## 4. FROMLIB semantics

- `FROMLIB` / `FROM-LIBRARY` arms the next path resolve root to  
  `Bundle.main.resourceURL/Library` (via host hook).
- Applies to next `FLOAD` / `INCLUDE` / `REQUIRE` / `EDIT` / `CHDIR` / `DIR` as implemented.
- Relative names: `FROMLIB FLOAD BigInteger/big-int.fth`
- Session cwd for user files remains separate (Documents / last CHDIR / bookmarks).
- **Nested relatives:** each successful FLOAD/INCLUDE temporarily sets logical cwd to that
  file's directory (stack + `end_include` hook when SOURCE ends), so
  `FROMLIB FLOAD HayesTest/HayesTest.fth` can `FLOAD src/test.fth` and then sibling
  loads under `src/`. Session cwd is restored when the outer load finishes.
- Bare `FROMLIB FLOAD` (dialog): panel starts at Library; session CHDIR is not changed
  permanently, but nested relatives still resolve next to the picked file.
- Implemented in **Swift FileHost**, not by re-creating the TZForth engine.

---

## 5. Kernel vs host ownership

| Concern | Owner |
|---------|--------|
| Dictionary, compilation, arithmetic, control flow, SEE/HELP | Kernel |
| Display buffer, menus, panels, paste/history | Host |
| Path resolution, bundle roots, bookmarks | Host |
| Opening file bytes for INCLUDE/FLOAD | Host (`load_file_hook`) preferred |
| EMIT / KEY while UI owns the window | Host hooks |
| Multiprecision mul/divmod/isqrt | Host (`BigIntHost`), CODE entry in BIG-INTEGER |
| Soft recovery from bad pointers | Kernel signal handler + host `sigaction` + LLDB init |

---

## 6. User dictionary & GROWMEMORYMB

### Layout

| Region | Content |
|--------|---------|
| **`.text`** | Machine code for CODE words (`XDUP`, `NEXT`, …). CFAs **point here**. Not limited by the 1 MiB logical dict. |
| **`user_dict_area`** | Headers, names, help, colon bodies, `ALLOT` data. `HERE` grows upward. |
| **Host malloc** | `ALLOCATE` / `FREE` / `RESIZE` — separate from the Forth dict |

Cold start: `HERE := user_dict_area`, then `_boot_kernel` + `forth_init_str`. Kernel **headers and colon definitions consume part of the logical dict** (~30–40 KiB today); assembly **implementations** stay in `.text`.

### Sizes

| Constant | Value | Role |
|----------|--------|------|
| Logical default | **1 MiB** | Initial `user_dict_size_cell`; ALLOT / `,` / `C,` bound |
| Physical reserve | **64 MiB** BSS (demand-zero) | Max without relocating CFAs |
| `GROWMEMORYMB` | `( n -- )` | Set logical size to **n MiB**, once per session |

### GROWMEMORYMB rules (TZForth-aligned, adapted)

- **Once per process/session**
- **Cannot shrink** (n MiB must be **greater** than current logical size)
- **1 ≤ n ≤ 64**
- Base address **never moves** (unlike a moving `realloc`), so existing CFAs remain valid
- **No** “forbidden after ALLOCATE” rule (host heap is separate from the dict)

Example:

```forth
.FREE                 \ ~1 MiB free after boot (minus kernel headers)
8 GROWMEMORYMB        \ before large ALLOT / PLDI-style codegen
```

On overflow: clear messages (`ALLOT: dictionary full…`, `dictionary full (code/data space exhausted)`), not a silent SEGV when bounds checks run.

### Design note (not implemented)

Putting **primitive machine code** inside the 1 MiB dict (so every CFA is “in-dict”) is possible via boot-time copy or generated code into executable pages; 64Forth intentionally keeps primitives in `.text` and only dict data in `user_dict_area`.

---

## 7. Fault recovery (vs TZForth)

**TZForth** rarely SIGSEGVs: memory is a bounds-checked byte array; errors become soft throws.

**64Forth** uses real pointers. Recovery:

1. Kernel installs **`sigaction(SIGSEGV/SIGBUS)`** → `kernel_on_memory_fault` → sticky flag + **`siglongjmp`** to `kernel_eval` / QUIT setjmp  
2. Host reinstalls the same handlers from Swift  
3. After longjmp: reset stacks/STATE/locals, emit `memory access error` via **emit_hook**, `kernel_eval` returns **−1**  
4. Xcode: scheme **`customLLDBInitFile`** = `.lldbinit-64forth` so LLDB **passes** SIGSEGV/SIGBUS to the process (`-p true -s false`) instead of stopping on EXC_BAD_ACCESS first  

`BYE` returns **1** → host may terminate the app (intentional). Accidental `Bye` in a loaded `.fth` file will quit the app.

---

## 8. Source loading model

| Topic | 64Forth behavior |
|-------|------------------|
| INCLUDE/FLOAD | Host loads **entire file** into one nested SOURCE (`SOURCE-ID` &gt; 0) |
| REFILL on file | False (whole file already in SOURCE) |
| FILE-ECHO | Line-oriented echo of pending source through emit_hook |
| `\S` | Stop rest of **current** SOURCE only; outer INCLUDE continues |
| REQUIRE | Load-once by absolute registry key |

---

## 9. Pictured numeric & multiprecision I/O

ANS Core pictured output is **double-cell**:

```forth
\ ud = lo under, hi TOS
: #  0 BASE @ UM/MOD >R BASE @ UM/MOD R> ROT ... HOLD ;
: #S BEGIN # 2DUP OR 0= UNTIL ;
: #> 2DROP HLD @ ... ;
```

Single-cell values must be presented as doubles, e.g. `n 0 <# #S #>` (used by `BI.`, `BI-U.9`, `.ELAPSED` hours, `.H2`, `.HA`, `U.R`, `D.`).

Library π: `Resources/Library/PI/pi-chudnovsky.fth` + `BigInteger/big-int.fth`; demos via `FROMLIB FLOAD PI/pi-test.fth`.

---

## 10. Relationship to PickleForth & TZForth

| Project | Role |
|---------|------|
| **PickleForth** | Terminal kernel lab; fast assembly iteration |
| **TZForth** | Full Swift Forth product; reference for UX, FileHost, BI algorithms, ANS breadth |
| **64Forth** | Hybrid product: TZForth host + Pickle kernel |

Kernel improvements can be cherry-picked PickleForth ↔ `64Forth/Kernel` until they diverge.

### Still missing vs full TZForth (high level)

- **Extended-Character** (XChar) word set  
- **SZ-EDITOR** as a polished in-app library path (sources exist under Library/Editor)  
- Line-at-a-time INCLUDE driven by real ANS fileids (whole-file SOURCE model today)  
- Optional polish: multi-buffer block cache, compiled `TO` for FVALUE, store sandbox  

### Present and Hayes-validated (v0.5)

- File-Access, Facility, Block (file volume), Floating-point (FP vocab), core through tools/search/string  

---

## 11. Open decisions

1. App sandbox on/off for public builds  
2. Whether to add TZForth-style “no GROWMEMORYMB after ALLOCATE” (currently N/A)  
3. Further editor / XChar ports vs keep host-only features  
4. Release packaging / branding beyond current AppIcon  

---

## 12. Chat / Grok workflow (see also README)

Primary working directory for 64Forth work:

`/Users/thomaszimmer/Documents/XCodeProjects/64Forth`

| Work on… | Prefer cwd / chat |
|----------|-------------------|
| **64Forth** hybrid app | This repo |
| **PickleForth** kernel-only | Separate PickleForth chat/cwd |
| **TZForth** reference | Read-only from sibling tree when needed |

Prefer writing only under `64Forth` unless explicitly changing PickleForth/TZForth.

---

## 13. Key source map

| Path | Role |
|------|------|
| `64Forth/Kernel/forth.s` | ITC kernel, colon bootstrap, WORDS, faults, dict |
| `64Forth/Kernel/boot_words.inc` | CODE word catalog |
| `64Forth/Kernel/kernel_api.h` | C ABI for host |
| `64Forth/Host/KernelBridge.swift` | Embed bridge, eval, signals, float_op hook |
| `64Forth/Host/FileHost.swift` | Paths, INCLUDE, DIR, EDIT |
| `64Forth/Host/FileAccess.swift` | File-Access table |
| `64Forth/Host/BigIntHost.swift` | Multiprecision host ops |
| `64Forth/Host/FloatHost.swift` | IEEE-64 F-stack + float ops (TZForthFloat port) |
| `64Forth/App/ConsoleView.swift` | REPL, paste, `\S` batch stop, batched emit follow |
| `64Forth/Resources/Library/` | BigInteger, PI, HayesTest, Editor samples |
| `.lldbinit-64forth` | LLDB: pass memory faults to process |
| `64Forth.xcodeproj/.../64Forth.xcscheme` | `customLLDBInitFile` → that lldbinit |
