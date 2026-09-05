# STATUSDBG64 — Phase 4.0 debugger (64TCOM + 64Forth editor)

**Monitor this file** for TCOM / SIMARM64 debugger progress.  
Canonical plan: session `plan.md` (Phase 4.0).  
Shared roadmap blurb: [`STATUS.md`](STATUS.md) § Debugger.

**Last updated:** 2026-08-31  
**Pack release:** 64TCOM ARM64 **Version 0.9**  
**Phase:** 64TCOM **4.0** utilities (slice 1 **shipped** in 0.9; editor next)  
**Backend:** **SIMARM64 first** (native traps later)  
**64Forth ITC `DEBUG` / `DBG`:** **1.3.0+** (current **1.3.2**) — help column, LIT/branch ±CELLS inline, pause spacing, ok> focus; **1.2.0** source-alias highlight + F8/Esc/⌘Q. Interactive `CODE`/`END-CODE`: see `Assembler/ASSEMBLER.fth` / `STATUSASM64.md`. Emitter (in progress): `Library/Emitter/`.

---

## Goal (slice 1)

Step **TCOM-compiled A64** in the host sim from 64Forth, with SZ-EDITOR support:

- Console / editor command words: `BREAK` `UNBREAK` `STEP` `GO` `WHERE` `TDEBUG` / **`TDBG`**
- Pack hooks (`DBG-PC@` …) filled by ARM64 sim backend
- SZ-EDITOR: Files-column **stack pane**, open **`TSRC-CUR-PATH`**, **highlight** the source token for the word about to run
- When the editor is on screen, **suppress** redundant `>>` console chatter (stacks live in the side pane + highlight)

**Definition of done:** `FLOAD TARGETARM64` → demo → `TDBG ANS` (or `TDEBUG ANS`) steps at BL/BLR/RET boundaries; editor shows stacks + highlighted word; `.RUN-ANS` still OK with debug disarmed; ITC `DEBUG` still works.

---

## Review notes (approved)

- Track progress here in **`STATUSDBG64.md`** (twin under 64Forth `Docs/` when shipped).
- Alias: **`TDBG`** ≡ start debugger (same as `TDEBUG`).
- Editor must **highlight** the current word / next region for F6/F7 — not rely only on `>> NAME` above the data stack.
- With editor visible, debug printouts in the Forth console are **redundant** — keep console quiet; use pane + highlight.

---

## Progress checklist

### P0 — Sim breaks + hooks

- [x] `SIMARM64` break table; stop before taddr; resume-skip; `.RUN-ANS` unchanged when disarmed
- [x] `DBGARM64.fth` installs `DBG-*` hooks (PC, stacks, fetch, break, step, go, sym)
- [x] Forth-step = until next `BL` / `BLR` / `RET` or break (`ISTEP` later)

### P1 — Console UI

- [x] `64TCOMUTILS/TCOMDBG.fth` — `BREAK` `UNBREAK` `WHERE` `STEP` `GO` `TDEBUG` **`TDBG`**
- [x] Pause loop via `EKEY` (F6 over, F7 into, ⌘⇧Y / `g` go, `q` quit)
- [x] Quiet mode DEFER (`TDBG-QUIET` / `TCOMDBG-ED` when editor up)

### P2 — SZ-EDITOR

- [x] Open `TSRC-CUR-PATH` on `TDBG` when set (`TCOMDBG-ED`)
- [x] Side-pane stack paint (`SZ-SIDE-HOOK` + `TCOMDBG-ED`)
- [x] **Highlight** via TCOMNDX map into source (`TCOMDBG-ED`)
- [x] ITC `DEBUG`/`DBG` also highlights upcoming word via `DBG-HL-XT` (64Forth 1.1.8+)
- [x] Key steal: `TDBG-ARM-KEYS` / `kernel_tdebug_armed` (needs 64Forth rebuild in Xcode)
- [x] `TARGETARM64` auto-INCLUDEs `TCOMDBG-ED` when `SZ-TDBG-ARM` exists (GUI AutoLoad)

### P3 — Docs / load

- [x] `TARGETARM64` includes `TCOMDBG` + `DBGARM64`
- [x] `64TCOMUTILS/README.txt` + `STATUS.md` Phase 4.0 note
- [x] 64Forth `Docs/STATUSDBG64.md` twin + short `STATUS.md` pointer

### P4 — Index / xref (in progress)

- [x] Port classic **TCOMNDX** `/INDEX` concepts (`TCOMNDX.fth` + `NDXARM64.fth`)
- [x] Emit call/ret sites on `COMP-CALL` / `END-T:` → `tetra/tetra.NDX` text listing
- [ ] Restore `.FIL` path column reliably; name column from SYM
- [ ] `TDBG` opens `.NDX` and highlights by taddr (started in `TCOMDBG-ED`)
- [ ] Native `BRK` / trampoline
- [ ] Full listing (ls86-style) / assembler XREF.FTH (separate tool)
- [ ] Merge ITC `DEBUG` and `TDBG` into one word
- [ ] `ISTEP` (one machine insn)

---

## Load (intended)

```text
CHDIR …/64TCOMARM64
FLOAD TARGETARM64.fth
ARM64-DEMO          \ or TCOM path/to/app.fth
TDBG ANS            \ alias of TDEBUG ANS
\ F6 over  F7 into  Cmd-Shift-Y/g go  Space/o over  i into  q quit
```

### Key parity vs ITC `DEBUG`

Same *intent* and shared host steal (`kernel_any_debug_armed`), different backends:

| Key | ITC `DEBUG` (1.2.0+) | `TDBG` |
|-----|----------------------|--------|
| F6 / Space / `o` | over (`debug_over`) | over (`TDBG-STEP-OVER-SRC`) |
| F7 / `i` | into | into |
| F8 | step-out (`debug_out`); top word finishes session | not implemented |
| ⌘⇧Y / `g` | go | go |
| Esc / `q` | abort (`DEBUG aborted` → prompt) | `q` quits session |
| ⌘Q | abort stepper + close editor + quit app | same host path when editor up |

**Editor wait must be `EKEY`:** `KEY` skips tagged F-keys `((2<<24)|K-*)`, so F6/F7 never reached `TDBG-HANDLE-KEY` while the editor was up (Space still worked). Fixed in `TCOMDBG-ED` (`TDBG-WAIT-KEY-ED`).

---

## Files

| Path | Role |
|------|------|
| `64TCOMUTILS/TCOMDBG.fth` | Shared UI + public words |
| `64TCOMARM64/DBGARM64.fth` | SIMARM64 backend for `DBG-*` |
| `64TCOMARM64/SIMARM64.fth` | Break checks |
| `STATUSDBG64.md` | This monitor |
| 64Forth kernel / `KernelBridge` | `tdebug_armed` key steal |
| `Editor/sz-screen.fth` | `SZ-SIDE-HOOK` for stack pane |

---

## Success criteria

- [x] Break / step / go on a named `SYM` under SIMARM64 (`tdbg-smoke.fth` → X0=5)
- [x] Forth-step at call/return boundaries (`DBG-STEP-INTO` / `DBG-STEP-OVER`)
- [x] Space/OVER = one *source* token via NDX (`TDBG-STEP-OVER-SRC`) — multi-CALL macros like `/` (TOR#…NIP#) clear in one Space
- [x] Editor stack pane + **highlighted** current word (`TCOMDBG-ED` + `SZ-SIDE-HOOK`)
- [x] Console quiet when editor up (`TDBG-QUIET` via `TCOMDBG-ED`)
- [x] `TDBG` alias works
- [x] ITC `DEBUG` unchanged
- [x] Editor-mode F6/F7 via `EKEY` wait (`TCOMDBG-ED`; was broken under `KEY`)

**Note:** Rebuild 64Forth in Xcode to pick up `TDBG-ARM-KEYS` / `kernel_tdebug_armed` (F6/F7 steal while editor focused). Agent CLI tools already smoke the sim path without that rebuild.

**Bugfix (2026-08-23):** `S" TDBG-ARM-KEYS" FIND` crashed in `XFIND` at address `0xd` (string length 13 used as pointer). Host arm/disarm now binds at load via `[UNDEFINED]` — never `S" … FIND`.

**Bugfix (editor F6/F7):** `TDBG-WAIT-KEY-ED` used `KEY`, which drops Facility Ext F-key tags; switched to `EKEY` so host-stolen F6/F7 reach `TDBG-HANDLE-KEY`.

**SEE vs SEE-T:** Host `SEE` only finds 64Forth dictionary words. TCOM targets live in `SYM-*` — use **`SEE-T ANS`** (hex dump to next symbol; tags RET/BLR/BL).
