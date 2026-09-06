# Emitter stand-alone app kit (GRAPHICS)

**Status:** design freeze for the window/IO surface (2026-09-05).  
**Menus** and **File-Access-in-kit** are deferred.  
**First emit target:** `tetra/tetra.fth` (64TCOM tree) — already runs under interactive 64Forth **GRAPHICS**.

This document names the runtime base that Emitter-built stand-alone apps will sit on. It is **not** a second GUI toolkit: it is the existing **GRAPHICS** vocabulary plus host `(APP-*)` hooks, with room for a later **MENUS** vocabulary.

---

## Product workflow

1. Write and debug the app on **interactive 64Forth** with `ONLY FORTH ALSO GRAPHICS` (char grid + optional points).
2. When Emitter can emit a stand-alone image, slice/link that app against the same GRAPHICS surface (host still provides the AppKit window).
3. Do **not** depend on the IDE console, Facility/`PAGE`, SZ-EDITOR, or Hyper for the stand-alone product path.

Entry pattern (unchanged): load sources, then `MAIN` (AutoLoad may call `APP-RUN`).

---

## Window / IO surface (in kit now)

### Dimensions (frozen for now)

| Layer | Size |
|--------|------|
| Char grid | **80 × 25** (`G-COLS` / `G-ROWS`) |
| Pixels | **640 × 400** (`G-PX` / `G-PY` = 80×8 × 25×16) |
| Cell | 8 × 16 px |

### Forth words (GRAPHICS)

Char / IO: `WINDOW` `WINDOW-OFF` `APP-NAME` `CLS` `AT` `EMIT` `TYPE` `SPACE` `CR` `.` `."` `GET-CHAR` `KEY` `KEY?` `REFRESH` `?REFRESH`

Time / sound: `TIME-RESET` `10TH-ELAPSED` `TENTHS` `TONE`

Points: `WHITE` `BLACK` `INVERT` `PLOT` `UNPLOT` `LINE` `PCLS` `PREFRESH` (plus helpers as needed)

Smoke: `GRAPHICS-SMOKE` `GRAPHICS-PSMOKE`

### Host CODE ABI (must remain imports for Emitter)

`(APP-OPEN)` `(APP-CLOSE)` `(APP-BLIT)` `(APP-PBLIT)` `(APP-KEY?)` `(APP-KEY)` `(APP-NAME)` `(APP-TONE)` `(APP-PUMP)` plus `MS@` for timers.

Swift: `Host/AppOutputHost.swift`. Hooks live in the **GRAPHICS** vocabulary after cold `vocsys.fth` rechain.

Forth owns `G-BUF` / `G-PIX`; the host owns the `NSWindow`, blit, key queue, tone, and pump.

---

## Explicitly out of kit (for now)

| Deferred | Notes |
|----------|--------|
| **MENUS** vocabulary | Limited menu construction/handling — later |
| File-Access as Emitter kit fence | ANS file words already exist in the kernel/host; not part of this freeze |
| IDE surfaces | Console, Facility, SZ-EDITOR, Hyper, Tools menus |

---

## Triple-load line directives

Apps that also build under 64TCOM (and later Emitter) use line prefixes:

| Directive | When true | Typical use |
|-----------|-----------|-------------|
| `\ANS` | Interactive **64Forth** | GRAPHICS `WINDOW-OFF`, stack HUD, etc. |
| `\TCOM` | **64TCOM** / `TARGETARM64` | Mach-O exit status, TCOM BYE paths |
| `\EMITTER` | Emitter-armed source load | Emitter-only lines in **shared** sources |

`DIRECTIVE` / `\ANS` / `\TCOM` / `\EMITTER` are defined in cold `Kernel/app-output.fth` (and mirrored under `Library/Sources/`). On interactive 64Forth: `\ANS` **true**, `\TCOM` and `\EMITTER` **false**.

**Shared app sources** (e.g. `tetra/tetra.fth`) are used by 64Forth, 64TCOM, **and** Emitter. Any line that is specific to one host must be prefixed with that directive so the others skip it. If Emitter-specific code is added to those shared files, it **must** start with `\EMITTER` (and the Emitter load path must arm `\EMITTER` true, typically with `\ANS`/`\TCOM` false for that include).

**Normal in-process slice** still develops under `\ANS` and copies already-compiled ITC (`TGT-BUILD` / `TGT-RUN`) without re-INCLUDING the app — so many emit sessions never need `\EMITTER` lines. Packaging / runner work belongs in `Library/Emitter/` and `Library/Emitter/EmitterSmoke/`, not in shared tetra sources, unless a true triple-load difference appears.

Example (from tetra): Esc quits differently for TCOM vs interactive ANS:

```forth
\TCOM               $1B OF 0 23 AT BYE              ENDOF
\ANS                $1B OF WINDOW-OFF EXIT          ENDOF
\EMITTER            $1B OF WINDOW-OFF EXIT          ENDOF   \ only if Emitter exit must differ / be explicit
```

---

## First example: tetra

Canonical dual/triple-load source:

`/Users/thomaszimmer/Documents/64TCOM/64TCOMARM64/tetra/tetra.fth`

Interactive load sketch:

```forth
ONLY FORTH ALSO GRAPHICS
S" /Users/thomaszimmer/Documents/64TCOM/64TCOMARM64/tetra/tetra.fth" INCLUDED
MAIN
```

(Cold start already provides GRAPHICS; an extra `FLOAD` of `app-output` is unnecessary on current 64Forth.)

Emitter milestone: emit **tetra** as a stand-alone macOS app that still uses the GRAPHICS host window — after reach/copy covers what tetra needs and host `(APP-*)` stay as imports.

---

## Sources

| Piece | Path |
|-------|------|
| Char GRAPHICS | `Kernel/app-output.fth` |
| Points | `Kernel/app-points.fth` |
| Hook rechain | `Kernel/vocsys.fth` |
| Host window | `Host/AppOutputHost.swift` |
| Emitter (WIP) | `Library/Emitter/` |
| This doc | `Docs/APPKIT.md` (Resources + user Docs mirrors) |

---

## Next (ordered)

1. Keep developing apps against GRAPHICS on 64Forth (tetra is the reference).
2. Grow Emitter reach/target so tetra’s colon graph + CODE imports build/run in-process.
   - **Done (in-process):** `DATA-WORD?` — CREATE / VALUE / DOVAR / DOCON / DODOES stay **host imports** (identity map); `CODE-BOUNDS` unknown aborts; smoke covers VALUE/`TO`, CREATE cell, `DO`/`LOOP` (`Emitter/test.fth`, `Library/Emitter/EmitterSmoke/agent-smoke.fth`).
   - **Done (in-process):** branch-aware colon walk (so `IF EXIT THEN` in `WINDOW` still reaches `(APP-OPEN)`); reloc skips imports; GRAPHICS mini smoke `Library/Emitter/EmitterSmoke/gfx-smoke.fth` (`APP-NAME`/`WINDOW`/`CLS`/`AT`/`."`/`WINDOW-OFF` via `TGT-BUILD`+`TGT-RUN`; under `--agent` the window does not open but `(APP-*)` still veneer).
   - **Done (in-process):** tetra subset + MAIN build — `Library/Emitter/EmitterSmoke/tetra-smoke.fth` loads `64TCOMARM64/tetra/tetra.fth`, runs `T-TETRA-SUB` (FIELD/SETUP/BORDER/`FILL.CURR`/`DRAW.CURR`, no KEY loop), and `TGT-BUILD` of `MAIN` (~169 reachable). Does not run `GAME`’s KEY loop under agent.
   - **Done (howto):** interactive emit of `MAIN`/`GAME` — `Library/Emitter/EmitterSmoke/tetra-gui-smoke.fth` builds `MAIN` under agent; from the GUI console run `EMIT-TETRA` (`TGT-BUILD`+`TGT-RUN`) for a real GRAPHICS window + KEY loop. ESC uses the existing `\ANS` `WINDOW-OFF EXIT` arms (play + game-over). Do not `TGT-RUN` under `--agent` (KEY blocks). User-verified: focus Graphics window, Space drops, ESC quits.
   - **Note:** `\EMITTER` line prefixes are required **when** Emitter-only code is added to shared sources (`tetra.fth`, etc.); normal ITC slice of `\ANS`-compiled words does not re-INCLUDE those files. Packaging code lives under `Library/Emitter/` / `Library/Emitter/EmitterSmoke/`.
3. **Stand-alone packaging (in progress):**
   - **Done (Phase 1):** `/EMIT-STANDALONE` — copy reachable CREATE/VALUE/… into a RW data segment (`TGT-DATA-*`); `/EMIT-HOSTDATA` keeps identity map for interactive emit. Bundle recipe scaffold: `Library/Emitter/app-build.sh.template` (from TCOM `*-build.sh`). Smoke: `Library/Emitter/EmitterSmoke/data-standalone-smoke.fth`.
   - **Done (Phase 2a, in-process):** relocatable `host_app_*` slots — `(APP-*)` out-of-span `BL`s get `LDR X16,.quad` / `BLR` veneers with `.quad = $C0DE…|slot`; `HOST-BIND` fills live VAs before `TGT-PROTECT`. Slots 0–8 = open/close/blit/pblit/keyq/key/name/tone/pump. Smoke: `Library/Emitter/EmitterSmoke/gfx-smoke.fth` asserts `HOST-RELOC-N` and bound quads.
   - **Done (Phase 2b.1):** `64EMIT02` image persist — `/EMIT-UNBOUND` keeps `MAGIC|slot`; `SAVE-IMAGE` / `LOAD-IMAGE` (`Library/Emitter/save.fth`) write code+data+host reloc offsets+emit bases; load rebases ITC pointers and restores relocs; `TGT-RUN-LOADED` binds and runs. Smoke: `Library/Emitter/EmitterSmoke/persist-smoke.fth`.
   - **Done (Phase 2b.2):** thin runner `Library/Emitter/runner/emit-run` (+ `emit-host.inc`) loads `64EMIT02`, binds slots 0–8, runs ITC. Headless: `EMIT_HEADLESS=1`. Return gadget uses `adr` so `run_itc`’s C epilogue runs (saving caller LR alone skips it and breaks the stack).
   - **Done (Phase 2b.3):** `Library/Emitter/app-build.sh NAME image.img [out-dir]` bundles `emit-run` as `MacOS/NAME` + `Resources/app.img`. No-arg launch resolves the bundle image. Smoke: `Library/Emitter/EmitterSmoke/gfx-app-smoke.sh` → `Gfx.app`.
4. Later: **MENUS** vocab; document File-Access as part of the kit fence when stand-alone apps need declared file imports.
