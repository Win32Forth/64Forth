# 64Forth — Design Document

**Public domain.**  
**Updated:** 2026-08-19 — **v1.1.5** (console mid-line backspace caret; v1.1.4 GRAPHICS + tetra `\ANS` + TONE).

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
| XChar | Kernel UTF-8 CODE + high-level words; bulk `emit_buf` for multi-byte TYPE | ANS 18; validate via `ANSValidate/all-in-one.fth` |
| Facility terminal grid | TZForth-style host | `FacilityTerminal.swift` — `PAGE`/`AT-XY` cell buffer for SZ-EDITOR |
| SZ-EDITOR | TZForth Library/Editor port | Full-screen facility editor; `EDIT` entry; find/clip/mouse/wheel; Cmd-S/W/Q |
| Hypertext | F-PC HYPER lineage | LOCATE/VIEW, multi-hit ⌘PgUp/Dn, ⌘E, `HYPER-REINDEX`, `HYPER-VOC` |

---

## 2. Architecture (as built)

```text
┌─────────────────────────────────────────────────────────────┐
│  SwiftUI App (SixtyFourForthApp / ContentView / ConsoleView) │
│    • line / multi-line paste → KernelBridge.evaluate          │
│    • menus: FLOAD, CHDIR, EDIT, CLS; Show Library/AutoLoad/Docs (Finder) │
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
│    • FacilityTerminal — PAGE/AT-XY character cell grid         │
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
- AppKit `ConsoleTextView`; Tools menus (CLS, FLOAD, CHDIR, EDIT; Show Library/AutoLoad/Docs via `NSWorkspace.open`)

### Phase 3 — File / FROMLIB — **done**

- `FileHost`: logical cwd, FROMLIB → `Resources/Library`, nested relatives
- Kernel `INCLUDE` via `load_file_hook`; `FLOAD` / `REQUIRE` aliases
- Bare FLOAD/CHDIR → panels; `PWD`; quoted paths with spaces
- **Bundle copy (TZForth-style):** Xcode Run Script phases **Copy AutoLoad**,
  **Copy Library**, **Copy Docs** wipe and re-copy
  `64Forth/Resources/{AutoLoad,Library,Docs}` →
  `Contents/Resources/…` on every build (`alwaysOutOfDate`,
  `ENABLE_USER_SCRIPT_SANDBOXING = NO`). Avoids stale folder-reference
  copies that left FROMLIB serving old `.fth` sources.

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
| **`ABORT"`** | Compile: `IF S" …" TYPE CR -2 LITERAL THROW THEN`. Must `POSTPONE LITERAL` for `-2` (bare `-2` corrupts IF/THEN stack → memory fault compiling `BI-ENSURE`) |
| **PI pool** | Generous BI buffer budget; host BI capacity overflow must not soft-zero results |
| **WORDS** | First search-order wordlist only; optional filter. **System** words (CFA &lt; fence after bootstrap): A–Z under banner `64Forth System Words`. **User** words (CFA ≥ fence): load order under `64Forth User Words` (banner only if any) |
| **User dict memory** | See §6 |
| **Fault recovery** | See §7 |

---

## 3b. Word-set coverage — **v0.7.0 (Hayes subset green)**

| Word set | Status | Notes |
|----------|--------|--------|
| Core / Core Ext | **done** | CODE + `forth_init_str`; Tools `[IF]`/`[DEFINED]`/`[UNDEFINED]` |
| Double + String | **done** | Double CODE; `COMPARE`/`SEARCH`; pictured `#` double-cell |
| Exception | **done** | `CATCH`/`THROW`; soft uncaught THROW under embed |
| File-Access | **done** | Host `FileAccess` + CODE (`OPEN-FILE` … `FLUSH-FILE`) |
| Locals / Memory / Search-Order | **done** | `{: :}`, `ALLOCATE`, multi-wordlist |
| Facility + Facility Ext | **done** | `MS`; `KEY`/`KEY?`/`EKEY`; `EKEY>CHAR`/`EKEY>FKEY`; `K-*` constants; host maps arrows/F-keys; structures; `ENVIRONMENT? FACILITY` / `FACILITY-EXT` |
| Block | **done** | File volume; `LOAD` pushes SOURCE and restores outer `BLK` (source-stack frame includes BLK) |
| **Floating-point** | **done** | Host `FloatHost` (IEEE-64, 16-deep F-stack); public words in **`VOCABULARY FP`**; FORTH holds `FLIT` / `(F-OP)` / `FLIT-ADDR` only; float literals in outer interpreter |
| String Ext (17.6.2) | **done** | `REPLACES` / `SUBSTITUTE` / `UNESCAPE` (high-level) |
| Locals Ext | **done** | `(LOCAL)`, `LOCALS|`, `{: … :}`; `#LOCALS` = 32 |
| **Extended Character (18)** | **done** | UTF-8 in kernel; validate via modular `ANSValidate/` or `all-in-one.fth` |

**Honesty:** Word-set presence means required **names** (and working semantics for the Hayes/ANSValidate paths exercised). This is **not** a formal ANS System certificate.

**ANS-VALIDATE (pure Forth modules):**  
`FROMLIB FLOAD ANSValidate/ANS-VALIDATE.fth` — tester → core … block → xchar → float → host. Expect **ALL PASS** (~383/0). Nested relative `FLOAD` uses per-file load cwd. Batch done lines print `stack(n)`; suite ends with `EMPTY-DATA`.

### Floating-point design (v0.5+)

- **Not** pure assembly: same hybrid as BigInteger — Swift host + thin kernel multiplex (`kernel_set_float_op`).
- **Vocabulary:** `ALSO FP` to use `F+`, `F.`, `FVARIABLE`, …; default FORTH search order stays clean.
- **Literals:** `1.5e0` / `3.14` recognized by the outer interpreter (trailing-only `123.` remains double).
- **ENVIRONMENT?:** boolean/word-set queries return **value then true** (ttester double-`[IF]` idiom). Float: `FLOATING`, `FLOAT-EXT`, `FLOATING-STACK` (16), `MAX-FLOAT`.

### Extended Character design (v0.7)

- **Encoding:** UTF-8; `MAX-XCHAR` = `$10FFFF`; `XCHAR-MAXMEM` = 4; `XCHAR-ENCODING` → `"UTF-8"`.
- **CODE:** `XC!+`, `XC@+`, `XEMIT` (multi-byte via host `emit_buf` when set).
- **High-level:** `XC-SIZE`, `XCHAR+`/`XCHAR-`, `+X/STRING`, `-TRAILING-GARBAGE`, `XC-WIDTH`/`X-WIDTH`, `XHOLD`, `XC!+?`, `XC,`, `EKEY>XCHAR`, …
- **Validate (disk preferred after editing `.fth`):**  
  `INCLUDE …/Resources/Library/ANSValidate/all-in-one.fth`  
  (Bundle `FROMLIB` may be stale until rebuild.)

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

- Line-at-a-time INCLUDE driven by real ANS fileids (whole-file SOURCE model today)  
- Optional polish: multi-buffer block cache, compiled `TO` for FVALUE, App Sandbox for store  
- Editor extras: search/replace, dual buffers (core SZ-EDITOR is usable)

### Present and validated (v0.9.0)

- Hayes subset: core through File/Block/FP (`FROMLIB FLOAD HayesTest/HayesTest.fth`)  
- Modular ANSValidate: Core … Float + host.fth (~383/0); cleaner residual stack  
- Facility Ext: structures + `EKEY>FKEY` + `K-*` + host special-key mapping  
- FacilityTerminal grid + SZ-EDITOR (Library/Editor; FROMLIB open; Cmd-S/W/Q)  
- `S"` / `."` / `C"` / `S\"`: only the WORD delimiter blank is skipped; further spaces are content  
- String Ext, Locals Ext, Search-Order, Memory-Allocation, full Facility  
- **Multi-thread dict:** each wid has `DICT_THREADS` (16) hash heads; `_dict_hash` in `_header_build` / FIND / SEARCH-WORDLIST / WORDS / FORGET prune / MARKER; `LAST` / `last_cfa` for IMMEDIATE, DOES>, ALIAS, RECURSE  
- **File multi-result stack:** `OPEN-FILE`/`CREATE-FILE`/`READ-LINE`/`FILE-POSITION`/`FILE-SIZE`/`FILE-STATUS` etc. restore TOS under via `FILE_POP_UNDER` before pushing results (no leftover fam/fileid)  
- **Prompt:** `ok(n)>` where *n* is data-stack depth (`kernel_data_depth`)  
- **Tools → Show * Folder:** `FileHost.revealInFinder` uses `NSWorkspace.open` (works inside `.app` Resources)

---

## 11. Open decisions

1. App sandbox on/off for public builds  
2. Whether to add TZForth-style “no GROWMEMORYMB after ALLOCATE” (currently N/A)  
3. Editor search / dual-buffer vs keep host-only EDIT for casual files  
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
| `64Forth/App/AppMain.swift` | Process entry: agent branch or GUI |
| `64Forth/App/AgentChannel.swift` | Headless `--agent` load/eval/transcript |
| `64Forth/Resources/Library/` | BigInteger, PI, HayesTest, Editor samples |
| `64Forth/Resources/Docs/Agent-channel.md` | Agent channel user/dev docs |
| `tools/64forth-agent` | Shell wrapper for agent binary |
| `.lldbinit-64forth` | LLDB: pass memory faults to process |
| `64Forth.xcodeproj/.../64Forth.xcscheme` | `customLLDBInitFile` → that lldbinit |

---

## Agent channel (v1.1.2)

Headless automation path for Grok/CI: same kernel as the GUI, EMIT to stdout + optional `-o` file. Not a socket into a live window.

- Activate: `--agent` or `FORTH64_AGENT=1`
- Detail: [`64Forth/Resources/Docs/Agent-channel.md`](64Forth/Resources/Docs/Agent-channel.md), status in [`STATUS.md`](64Forth/Resources/Docs/STATUS.md)

## Console header stamp (release hygiene)

GUI banner in `ConsoleView.swift`:

```text
=== 64Forth M.N.P === Mon D, YYYY H:MM AM/PM ===
```

Update the **date/time only** when finishing a set of changes on a version, **just before** DMG creation and commit/push to the repo. Not required on every intermediate build. Version number in the same string tracks `MARKETING_VERSION`.

## Known issue → 1.1.3 (optional): DMG `/Volumes/` open noise

Seen when **two** volumes named `64Forth-1.1.2-macOS` were mounted (stale build + new). After ejecting both and remounting one DMG, run-from-volume worked. Message is INCLUDE of a **directory** (volume root) via `FileHost.pinFileContents`. Soften to optional hardening + eject hygiene: [`Resources/Docs/STATUS.md`](64Forth/Resources/Docs/STATUS.md) section **v1.1.3 backlog**.
