# STATUSASM64 — ASMARM64 dual-load toolkit

**64Forth Docs copy** of `Documents/64TCOM/STATUSASM64.md` (keep both in sync).

**Monitor this file** for assembler completion progress.  
Canonical plan source: session `plan.md` (assembler toolkit).  
Canonical code: `64TCOMARM64/ASMARM64.fth`.

**Last updated:** 2026-08-23 3:16 PM (assembler twins synced)  
**Phase target:** 3.2 Assembler toolkit  
**Pack release:** 64TCOM ARM64 **Version 0.9** (with 64Forth **1.2.1**; last dual ship was **1.1.9** / pack with **1.2.0**)  
**Assembler sync stamp:** `Synced Aug 23, 2026 3:16 PM` in both `ASMARM64.fth` headers

---

## Goal

Make **`64TCOMARM64/ASMARM64.fth`** a **practical AArch64 assembler toolkit** that:

1. Extension authors can use confidently when adding 64TCOM features (LIB/OPT/demos/CODE leaves).
2. Loads as **the same file** under **TCOM** and **interactive 64Forth** (`\ANS` / `\TCOM` dual-load).
3. On 64Forth, emits into a **host assembly buffer** with optional **`CALL-NATIVE`** execution — not into the ITC dictionary CODE area, and not requiring a full `TARGETARM64` load.
4. Can be **loaded, used, then discarded** via an **overlay** (`ANEW` / `FORGET` / `ASMARM64-DISCARD`) so dictionary and buffers do not permanently consume the session.

**Definition of done (practical STC/Forth toolkit):** finish the gaps authors hit — W-regs, shifts/extends/bitfield, ADR/ADRP, LDP/STP suite, richer LDR/STR, CSEL, real BTI — plus API docs, dual-load, overlay discard, and smoke tests. **Explicitly defer** NEON / FP / SVE and most system / barrier / atomics encodings.

---

## Progress checklist

### P0 — Dual-load + overlay + 64Forth load path

- [x] Emit backend abstraction (`HERE-T` / `C,-T` / `C!-T` / `C@-T` / `,-T` on both hosts)
- [x] `\ANS` bootstrap (no full `TARGETARM64`): DIRECTIVE, `TCOM-ANEW`, DEFERs, host buffer, `U>=`
- [x] **Overlay:** `MARKER ASMARM64-OVERLAY`; `ASMARM64-DISCARD` (before marker) frees buffers + runs marker
- [x] 64Forth `Library/Assembler/asmarm64.fth` load helper
- [x] Smoke: host load → `ASM-HOST-SMOKE` → discard (agent verified 2026-08-23)
- [x] Regression: `FLOAD TARGETARM64.fth` full pack load OK (agent verified)

### P1 — Public API docs

- [x] `64TCOMARM64/ASMARM64.md` (ABI, load, emit model, catalog, add-emitter recipe, overlay, host buffer)
- [x] `.ASMARM64` banner → toolkit 3.2 / dual-load
- [x] Cross-links from `STATUS.md` / pack `README.txt` / Library README

### P2 — Practical ISA gaps

- [x] Shifts / bitfield (`ASR-IMM,` `ASR-X,` `UBFM-X,` `SBFM-X,`; existing LSL/LSR)
- [x] W-register parallel suite (MOV/logic/ALU/LDR/STR/CBZ-W)
- [x] General `ADR,` / `ADRP,`
- [x] LDP/STP suite (`STP-OFF,` `LDP-OFF,` `STP-PRE,` `LDP-POST,`)
- [x] Richer LDR/STR (`LDR-PRE,` `STR-POST,` `LDR-REG,` `STR-REG,`)
- [x] `CSEL-X,` / `CSINC-X,` (existing `CSET-X,`)
- [x] Real `BTI,` / `BTI-C,` / `BTI-J,` / `BTI-JC,`
- [ ] Optional: more extends on ADD/SUB (only if a feature needs them)

### P3 — 64Forth runnable smoke

- [x] Host leaf → `ASM-MAKE-EXEC` → `CALL-NATIVE-LEAF` → 7 (`ASM-HOST-SMOKE`)
- [x] Document JIT / entitlements note in `ASMARM64.md`

### P4 — Extension ergonomics

- [x] “Writing a LIB leaf” note in `ASMARM64.md`
- [x] Clear `TCOM-ABORT` on bad imm fields (existing + new range checks)
- [ ] Optional golden encode self-tests (partial via `ASM-HOST-SMOKE`)

### P5 — STATUS / README polish

- [x] `STATUS.md` points at STATUSASM64; `64DESIGN/STATUS.txt` ASM toolkit line
- [x] Pack `README.txt` + 64Forth Library README
- [x] Deferred categories stated in `ASMARM64.md` / README

### Success criteria

- [x] `INCLUDED` assembler on interactive 64Forth **without** `TARGETARM64`
- [x] Same file still loads under `FLOAD TARGETARM64.fth`
- [x] Overlay discard restores a clean dictionary (assembler words gone; buffers freed)
- [x] Documented emitter catalog + “add an emitter” recipe
- [x] Checklist categories implemented (core set)
- [x] At least one host `CALL-NATIVE` leaf smoke
- [x] Deferred categories (NEON/FP/SVE, most system/atomics) documented

---

## Overlay / discard (requirement)

**Use case:** load assembler from source → assemble some code into the host buffer → optionally run it → **discard** the assembler definitions so the session is clean again.

| Mechanism | Role |
|-----------|------|
| `ASMARM64-OVERLAY` | `MARKER` at start of ANS/host load (restores dict when executed) |
| `ASMARM64-DISCARD` | Defined *before* marker; frees ASM/EXEC buffers then runs the marker |
| Reload | Re-`INCLUDED` / load helper again after discard |

**Rules:**

- Under **`\ANS` (64Forth alone):** all assembler words, DEFERs installed by the load, and buffer state live **at or after** the overlay marker so one `FORGET` removes them. Assembled **bytes** in a host buffer are freed by discard (or left only if the user copied them out).
- Under **`\TCOM` (full pack):** keep today’s `TCOM-ANEW ASMARM64` reload behavior. Discarding *only* the assembler while OPT/LIB/SIM remain loaded is **unsupported** (would leave dangling `SETASSEM` / cookie refs). Document: discard = ANS/host toolkit use; pack reload = full `TARGETARM64` / restart if needed.
- Do **not** assemble into the ITC dictionary CODE area; overlay is for **Forth definitions**, buffer is for **machine bytes**.

**Typical ANS session:**

```forth
FROMLIB FLOAD Assembler/asmarm64.fth   \ or INCLUDED canonical path
SETASSEM
  ... emitters ...
END-CODE
\ use ASM-BUF / CALL-NATIVE as needed
ASMARM64-DISCARD                       \ forget words + free buffers
```

---

## Current state

| Item | Today |
|------|--------|
| Pack home | `64TCOM/64TCOMARM64/ASMARM64.fth` — loaded by `TARGETARM64` only |
| Library home | `64Forth/.../Library/Assembler/asmarm64.fth` — `FROMLIB` only; **not** loaded by TCOM |
| Sync | Edit both (or copy pack → Library) when changing the assembler |
| Load path (TCOM) | `FLOAD TARGETARM64.fth` → `64HOST` → pack `ASMARM64` → OPT/LIB/SIM/… |
| Emit backend | `W,` → `C,-T` / `HERE-T` / `PATCH-W` / `W@-T` (target CODE image) |
| Vocab lifecycle | `SETASSEM` / `END-CODE` / `C;` → `ASMARM64` vocab + `LL-INIT` |
| Dual-load precedent | `\ANS` / `\TCOM` via `DIRECTIVE` in `64HOST.fth` and `app-output.fth` |
| 64Forth native helpers | `ALLOCATE-EXEC`, `FREE-EXEC`, `MPROTECT`, `ICACHE-INVAL`, `JIT-WPROTECT`, `CALL-NATIVE` |
| Documented ISA gaps | W-regs; most shifts/extends; ADRP/ADR; rich addressing; full LDP/STP; CSEL; real BTI; system/atomics; NEON/FP (non-goal) |

---

## Design principles

1. **One source file** for encoders (`ASMARM64.fth`). Dual-load with `\ANS` / `\TCOM`; do not fork a second assembler.
2. **Thin emit abstraction** so the same `W,` / patch / align words work on both backends.
3. **Two layers, documented clearly:**
   - **ISA emitters** — `ADD-X-X,`, `LDR-OFF,`, `B.COND,`, …
   - **Forth-ABI / structured helpers** — `TIF`/`TTHEN`, `TDO`/`TLOOP`, `CALL-ABS,`, `LIT-PUSH-X0,`
4. **Grow ISA on purpose**, not full-ISA tourism.
5. **Canonical home stays in 64TCOM.** 64Forth Library helper `INCLUDE`s that path (optional later ship-in-app copy).
6. **Overlay discard** for ANS/host toolkit sessions (see above).

---

## Architecture

```text
                    ┌─────────────────────────────────────┐
                    │           ASMARM64.fth               │
                    │  encoders + structured helpers       │
                    │  (shared body)                       │
                    └──────────────┬──────────────────────┘
                                   │ HERE-T C,-T C!-T C@-T
                                   ▼
              ┌────────────────────┴────────────────────┐
              │                                         │
     \TCOM (after 64HOST)                      \ANS (64Forth alone)
     target CODE image                         host ASM buffer
                                               optional ALLOCATE-EXEC
                                               → CALL-NATIVE
                                               overlay FORGET discard
```

### Emit backend

| Word | Role |
|------|------|
| `HERE-T` | Current emit address (taddr under TCOM; host pointer or offset under ANS — pick one model and document) |
| `C,-T` | Append one byte |
| `C!-T` / `C@-T` | Patch / fetch byte |
| `W,` | LE 32-bit via four `C,-T` |
| `PATCH-W` / `W@-T` | 32-bit patch/fetch |

**Under `\TCOM`:** existing 64HOST implementations (no behavior change).

**Under `\ANS`:** host buffer (`ASM-BUF` / `ASM-DP` / `ASM-LIMIT`); `ASM-CLEAR` / `ASM-ORG`; `ASM-MAKE-EXEC` for runnable pages.

### Bootstrap on `\ANS`

- `DIRECTIVE` / `\ANS` / `\TCOM` if undefined
- `TCOM-ANEW`, `TCOM-ABORT`, `DEFER SETASSEM` / `A;` / `END-CODE` if missing
- Overlay marker + host emit backend
- Do **not** pull `64DIR`, OPT, LIB, SIM, MACHO

---

## Instruction completion checklist (in scope)

| Category | Work |
|----------|------|
| **W-register forms** | MOVZ/MOVK/MOV, AND/ORR/EOR, ADD/SUB(/S), CMP, LDR/STR, CBZ/CBNZ-W as needed |
| **Shifts / extends / bitfield** | LSL/LSR/ASR imm+reg; UBFM/SBFM; basic extend on ADD/SUB if needed |
| **ADR / ADRP** | General `ADR,` / `ADRP,` |
| **LDP / STP suite** | Signed-offset and pre/post pair forms |
| **Richer LDR/STR** | Imm9 pre/post; scaled imm12; optional reg+reg |
| **Conditional select** | `CSEL,` / generalized `CSET,` |
| **BTI** | Real HINT encodings |
| **Docs + tests** | Catalog supported vs deferred; smoke on both hosts |

**Out of scope:** NEON / FP / SVE; full barriers / atomics / MRS/MSR; full A64 ISA; rewriting OPT/LIB except where a new emitter is required; ITC host CODE words.

---

## Work packages (summary)

| ID | Focus |
|----|--------|
| **P0** | Dual-load scaffolding, overlay discard, 64Forth load helper, smoke |
| **P1** | `ASMARM64.md` public API |
| **P2** | Practical ISA emitters |
| **P3** | Host `CALL-NATIVE` smoke |
| **P4** | Extension-author ergonomics |
| **P5** | STATUS / README polish |

**Order:** P0 → P1 → P2 → P3 → P4–P5.

---

## File touch list

| Path | Change |
|------|--------|
| `64TCOM/STATUSASM64.md` | **This monitor file** |
| `64TCOM/64TCOMARM64/ASMARM64.fth` | Emit abstraction; `\ANS`/`\TCOM`; overlay; new emitters |
| `64TCOM/64TCOMARM64/ASMARM64.md` | Public API |
| `64TCOM/64TCOMARM64/README.txt` | Dual-load / 64Forth / discard |
| `64TCOM/STATUS.md` | Point at STATUSASM64 + Phase 3.2 |
| `64TCOM/64DESIGN/STATUS.txt` | Phase checkbox |
| `64Forth/.../Library/Assembler/asmarm64.fth` | Load helper |
| `64Forth/.../Library/README.txt` | Assembler entry |

---

## Testing plan

| Gate | How |
|------|-----|
| TCOM regression | `FLOAD TARGETARM64.fth` then known demos |
| 64Forth load | Include helper; `.ASMARM64`; NOP+RET dump |
| 64Forth discard | `ASMARM64-DISCARD`; assembler words gone; buffer freed |
| 64Forth run | Leaf → `CALL-NATIVE*` → expected X0 |
| Encode goldens | Fixed `W,` results match hand-encoded A64 |
| No full TARGET | Cold 64Forth loads assembler alone |

---

## Locked decisions

| Topic | Decision |
|-------|----------|
| Completeness | Practical STC toolkit, not full ISA |
| Dual-load | Same `ASMARM64.fth`; `\ANS` / `\TCOM` |
| 64Forth sink | Host ASM buffer + optional `CALL-NATIVE` |
| Discard | Overlay marker + `ASMARM64-DISCARD` (ANS/host); pack-only discard unsupported |
| Source of truth | `64TCOMARM64/ASMARM64.fth`; 64Forth Library is a loader |
| NEON/FP/atomics | Deferred |
| ITC CODE words | Out of scope |

---

## Work log

| Date | Note |
|------|------|
| 2026-08-23 | Plan approved; STATUSASM64.md created; overlay/discard requirement added |
| 2026-08-23 | P0–P5 largely done: dual-load host buffer, MARKER overlay, ISA toolkit expansions, docs, agent smoke (host + TARGETARM64) |
| 2026-08-23 | ASMARMTESTS.fth extracted/expanded (64 encode+run checks); IMM7-PAIR signed scale fix; synced Library + 64TCOMARM64 |
| 2026-08-23 3:16 PM | Twins stamped; pack order/`AHEAD,`/`TSRC-HOST-EXEC` fixes; `TCOM tetra/tetra.fth` builds `.app`; docs updated both trees |
