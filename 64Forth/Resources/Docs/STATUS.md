# 64Forth development status

**Version in progress:** 1.1.1  
**Last updated:** 2026-08-16  

This file tracks design notes and progress for work after 1.0.7.  
Append new design sections as we go; mark items done when implemented.

---

## v1.0.9 summary (released)

Shipped with DMG and GitHub release `v1.0.9`.

| Area | Status |
|------|--------|
| Find next/prev: `SM/REM`, selection token, reverse-video match | **Done** |
| Cmd-F type-in find in status Sel/Find field | **Done** |
| Facility Unicode cells + box-drawing editor chrome | **Done** |
| Help grid; status Select/Find layout | **Done** |
| Version 1.0.9 / build 16; DMG + GitHub release | **Done** |

## v1.1.1 summary (in progress)

| Area | Status |
|------|--------|
| Version 1.1.1 / build 18 | **Done** |
| ⌘-click / ⌘E VIEW from **command pane** while editor KEY waits | **Done** |
| ⌘F / ⌘G / ⌘←→ / Hyper PgUp/Dn while command pane focused | **Done** |
| VIEW word via staged line (`HYPER-VIEW-CU`) when evaluating | **Done** |

## v1.1.0 summary (released)

| Area | Status |
|------|--------|
| Version strings 1.1.0 / build 17 | **Done** |
| Status-bar top-border `[X]` close (⌘W) | **Done** |
| Option A: facility editor **above** + scrollable command pane **below** | **Done** |
| Staged command evaluate while KEY waits (key 133 / `(SZ-CMD@)` / `(SZ-CMD-DONE)`) | **Done** |
| Click either pane; type `ok(n)>` while editor open; stack shared | **Done** |
| Custom 5pt splitter (gray/white/black/white/gray); drag to resize | **Done** |
| Long FLOAD/Hayes/ANS-VALIDATE output scrolls live in command pane | **Done** |
| Nested `EVALUATE` under command `CATCH` (inner Core tests keep running) | **Done** |
| Grid paint never leaks into command transcript during emit bypass | **Done** |
| Help fields: leading/trailing space; facility row fit above divider | **Done** |
| Persist split ratio in UserDefaults | **Not yet** |
| Multi-line paste polish in command pane | **Not yet** |

---

## 1.1.0 design: editor + interactive command pane (Option A)

**Decision (2026-08-15):** Use **Option A** — a **system splitter** and a **regular scrollable text pane** for the command area (same kind of console surface used when *not* in SZ-EDITOR), with the **facility grid only in the upper panel**. Not Option B (command area as extra facility cells).

### Motivation

- Pre-1.1 the host reserved ~5 monospaced lines below the facility for “command entry,” but while SZ-EDITOR owns `KEY` those lines were mostly **dead space**. **1.1.0** replaces that with a real lower command pane (`facilityCommandAreaLines = 0`).
- User wants to:
  1. **Click** the lower area and run arbitrary Forth interactively (`ok>` prompt).
  2. Later **drag a splitter** (represented by the bottom of the help chrome / pane boundary) to grow or shrink that command area.
  3. Have the lower pane **scroll** with a normal **scrollbar**.
  4. Keep the **upper panel** as the monospaced SZ-EDITOR facility.

This is standard IDE layout (editor above, console below). Not a rewrite; real work on focus + evaluate nesting.

### Current layout (before split views)

```text
┌─────────────────────────────────────┐
│  Facility grid (SZ-EDITOR chrome)   │  ← KEY loop, PAGE/AT-XY paint
│  status / text / visit list / help  │
├─────────────────────────────────────┤  ← bottom of help (future splitter)
│  ~5 reserved lines (mostly unused)  │  ← intended for commands
└─────────────────────────────────────┘
```

### Target layout (Option A)

```text
┌─────────────────────────────────────┐
│  Upper: facility / SZ-EDITOR        │  NSView hosting facility paint
│  (status, body, visit list, help)   │  (existing Terminal-REFRESH path)
├════════ splitter (system) ══════════┤  drag → resize panes
│  Lower: scrollable console pane     │  same idea as non-editor console
│  ok> …                              │  transcript + input, scrollbar
│  (history scrolls)                  │
└─────────────────────────────────────┘
```

### Why Option A (not B)

| | **Option A (chosen)** | Option B (rejected for now) |
|--|----------------------|-----------------------------|
| Upper | Facility SZ-EDITOR (as now) | Same |
| Lower | **Host scrollable text** (like idle console) | More facility cell rows |
| Splitter | **AppKit/SwiftUI splitter** | Manual drag on a facility row |
| Scrollbar | **Free** with `NSScrollView` / text view | Hand-rolled or awkward |
| KEY / evaluate | Console focus submits lines via host evaluate queue | Multiplex KEY for every char in a mini terminal |
| Look | Slightly two-surface, very macOS | One monospaced grid everywhere |

Option A matches “interactive command window that scrolls with a scroll bar” and reuses the **non-editing console** model.

### Hard constraints (from existing architecture)

- While the editor is open, Forth is typically blocked in **`KEY`** (`SZ-EDIT-LOOP`). Nested **`kernel_eval`** mid-KEY is unsafe (learned with ⌘O; solved there with staged path + host).
- Console commands must be run via a **host queue**: when the user presses Return in the command pane, stage the line and evaluate on a safe path (same spirit as menu open / idle evaluate), **not** by nesting evaluate inside the editor KEY wait without a pump plan.
- **Focus** must be as strict as find-edit: typing must not leak into the buffer when the console has focus, and vice versa.

### Focus model (three targets)

| Focus | Click | Keys go to |
|-------|--------|------------|
| **Document** | Editor text body | SZ-EDITOR motion/edit (current) |
| **Find field** | Status type-in (right of Files `│`) | Modal find (current) |
| **Console** | Lower scrollable pane | Command line / transcript selection |

- Esc or click editor → leave console focus (and leave find if needed).
- Click console → console focus (leave find-edit if open).

### Implementation phases

1. **Split the window (host)**  
   - Upper: existing facility paint surface (console body when facility active may shrink to upper pane only).  
   - Lower: dedicated scrollable text view (transcript + input), initially fixed height (~5 monospaced lines or a pixel min height).  
   - System splitter between them (`NSSplitView` / SwiftUI `HSplitView`/`VSplitView` equivalent).

2. **Console focus + one-line evaluate**  
   - Click lower pane → focus.  
   - Type at `ok>` (or `ok(n)>`); Return submits one line.  
   - Host runs evaluate safely relative to the open editor session; append output to the lower transcript.  
   - Do **not** require full dual-KEY multiplexing for every character if the lower pane is host-owned text input.

3. **Scrollable history**  
   - Keep last N lines (or unbounded with soft cap) of command I/O in the lower pane.  
   - Native scrollbar; select/copy like the idle console.

4. **Splitter UX**  
   - Drag boundary under help / between panes to change upper facility height vs lower console height.  
   - Map height → preferred facility rows (`preferredFacilityCells` / `facilityCommandAreaLines` becomes variable or is replaced by split ratios).  
   - Persist ratio in UserDefaults (optional early).  
   - Avoid layout ↔ wake feedback loops (reuse existing resize-wake discipline).

5. **Polish (later)**  
   - Send editor selection to console; multi-line paste in console; dirty interaction if evaluate mutates open buffer; optional “clear console.”

### Feasibility summary

| Question | Answer |
|----------|--------|
| Insane? | No — standard IDE pattern |
| Possible here? | Yes |
| Best shape for 1.1? | **Option A**: system splitter + scrollable command pane; facility only above |
| First milestone | Fixed-height lower console: click → type Forth → see result; Esc/click editor returns focus |
| Second milestone | Draggable splitter grows/shrinks console vs editor |

### Related code (implemented)

- `KernelBridge.facilityCommandAreaLines` (= **0**); `facilityRowSafety` (= **0**); `preferredFacilityCells()` from **upper** pane only  
- Facility paint: `FacilityTerminal` (`gridPaintActive` for PAGE/AT-XY…TERMINAL-REFRESH) + `ConsoleView`  
- Idle console: single `ConsoleTextView` when facility inactive  
- Split: `EditorCommandSplitView` / `EditorCommandNSSplitView` (5pt striped divider)  
- Editor KEY: `sz-edit.fth` `(SZ-EDIT-LOOP)`; command line `SZ-DO-CONSOLE-LINE`  

### Open questions (mostly resolved)

| Question | Resolution |
|----------|------------|
| Embed both panes vs `NSSplitView`? | Custom `NSSplitView` (macOS); stacked panes on iOS |
| Shared dictionary/stack while editor open? | **Yes** — same `kernel_eval` session; command line is nested `EVALUATE` under CATCH |
| Facility still reserve 5 command rows? | **No** — `facilityCommandAreaLines = 0`; lower host pane owns the REPL |

### 2026-08-15 — Option A implementation (as shipped for DMG)

**Host UI**
- `isEditorSplitActive` → upper facility + lower command `ConsoleTextView`.
- macOS: **`EditorCommandSplitView`** — 5pt divider (gray/white/black/white/gray), drag to resize.
- Command pane: protected `ok(n)>` prefix, history Up/Down, append-only TYPE + live scroll-to-end.
- Upper pane metrics only drive `preferredFacilityCells` (command pane must not overwrite cell size).
- On `FACILITY-OFF`: fold command transcript under `--- command pane ---`.

**Safe evaluate while KEY waits**
- Return → `stageCommandLine` + `pushKey(133)` (`SZ-CMD-EVAL`); no nested host `kernel_eval`.
- `SZ-DO-CONSOLE-LINE`: `(SZ-CMD@)` → `(SZ-CONSOLE-EMIT) on` → `['] EVALUATE CATCH` → emit off → `(SZ-CMD-DONE)` → `SZ-REDRAW`.
- `(SZ-CMD-DONE)` calls `_vm_save` so host `ok(n)>` sees live stack depth.
- Sticky `isCommandPaneFocused` (not first-responder inference) routes KEY vs command typing.

**Kernel (nested EVALUATE)**
- Completing an `EVALUATE` under CATCH must not end `kernel_eval` (would kill SZ-EDITOR).
- Resume CATCH **only** when outermost evaluate nest finishes (`source_sp == 0` after pop).
- Inner `EVALUATE` during FLOAD (ANS Core, Hayes, …) continues the outer file — verified with ANS-VALIDATE + Hayes while editor open.

**Emit routing**
- Command bypass: non-paint TYPE → lower pane.
- `PAGE`/`AT-XY`…`TERMINAL-REFRESH` always paints cells (`gridPaintActive`) so SEE/VIEW does not dump the frame into the command transcript.

**Still open / later 1.1.x**
- Persist split ratio (UserDefaults); multi-line paste polish; optional clear-command-pane.

---

## Editor UX: caret and selection (1.0.8+)

### Short answer

| Feature | Difficulty | Rough effort | Status |
|--------|------------|--------------|--------|
| **I-beam / line caret** (not reverse-video block) | Easy | ~½–1 day | **Done** (host paint) |
| **Click–drag selection** (like a normal editor) | Moderate | ~2–4 days for solid UX | **Done** (host + Forth) |

Neither needs a kernel rewrite. Most work is **host (Swift) input + paint** and **Forth selection/redraw**.

---

### What we have now

**Caret**

- SZ-EDITOR does not draw a glyph caret.
- After each frame it parks the facility cursor with `AT-XY` (`SZ-PLACE-CURSOR` in `sz-screen.fth`).
- Swift paints a **thin vertical I-beam** at that cell (`applyFacilityCursorHighlight` → `ConsoleNSTextView.showFacilityLineCaret` / iOS twin).
- System insertion point is suppressed while the facility terminal is active.

**Mouse**

- `ConsoleTextView` delivers **down / drag / up** into the facility as key 25 + `(SZ-CLICK)`.
- Flag: bit0 valid, bit1 ⌘, bits2–3 phase (0=down, 1=drag, 2=up). Drag coalesces on the host.
- Forth: plain click → word/line; drag → `[SZ-SEL-BEG, SZ-SEL-END)` + reverse-video paint; ⌘-click → VIEW.

---

### 1. Regular (line) cursor — easy

**Idea:** stop reverse-video of the whole cell; draw a thin vertical bar (or underline) at the insert point.

**Where:** mainly `applyFacilityCursorHighlight()` (and the facility paint path). Optionally a small flag “I-beam vs block” if we want both.

**Gotchas (small):**

- Character cell grid is monospaced — bar position is col × cell width (col/row already known).
- Blink is optional polish (timer on main).
- Insert vs overwrite: for insert, bar is *before* the character; current block is *on* the character — same coord as today, different drawing.

**Does not require** Forth changes unless we want a user-facing `BLOCK-CURSOR` / `LINE-CURSOR` toggle.

**Checklist**

- [x] Replace reverse-video cell with thin vertical bar (I-beam)
- [x] Facility I-beam blink (~0.53s); system insertion point suppressed in facility mode
- [ ] Optional: Forth toggle for block vs line caret
- [ ] Verify redraw after motion, scroll, and status updates (manual in SZ-EDITOR)

---

### 2. Click-and-drag selection — moderate

**Idea:** treat mouse as a *stream of positions*, not one click.

#### Host (Swift) — necessary

Today: only `mouseDown` → one facility click.

Need something like:

- `mouseDown` → start selection at cell  
- `mouseDragged` → update end cell (throttled)  
- `mouseUp` → finish  

Map view points → facility **col/row** (same math as click), inject into Forth (new key codes or a host op with col/row/flags: down/drag/up).

**Gotchas:**

- Throttle drag updates (every N ms or when cell changes) so we don’t flood `kernel_eval`.
- Don’t fight NSTextView’s own selection; keep facility mode capturing mouse (already special-cased in `ConsoleTextView`).
- Scroll while dragging near top/bottom (nice-to-have, extra work).

#### Forth (SZ-EDITOR) — necessary

Selection storage already exists; wire it to drag:

1. **Down:** set `SZ-CUR`, clear or start `SZ-SEL-BEG = SZ-SEL-END = cur`
2. **Drag:** map cell → buffer index (reuse `SZ-MOUSE-PLACE` logic), set `SZ-SEL-END`, keep `SZ-CUR` at end
3. **Up:** finalize `SZ-SEL-OK`
4. **Paint:** while drawing a line, if bytes fall in `[min(beg,end), max)` use reverse-video (or a second attribute)
5. **Typing / motion:** replace selection on type; optional Shift+arrows later

**Gotchas:**

- Multi-line highlight across gutters and h-scrolled lines (`SZ-HCOL`)
- Interaction with existing **word** / **line** / **⌘-click VIEW** (don’t break Cmd-click)
- Cut/copy already exist; they need a real byte range from drag

**Checklist**

- [x] Host: mouseDown / mouseDragged / mouseUp → facility (col, row, phase)
- [x] Host: throttle drag to cell changes (+ coalesce pending drags)
- [x] Forth: map drag phases to `SZ-SEL-*` / `SZ-CUR`
- [x] Forth: paint selection range on redraw (`FACILITY-REV` + host reverse attrs)
- [x] Type / paste / delete replaces selection
- [x] Preserve Cmd-click VIEW and word/line click modes
- [x] Scroll-on-drag at edges (vertical TOP + horizontal HCOL; selection kept)
- [x] Shift+click extend (from anchor; before or after)
- [x] Double-click word (space-delimited)
- [x] Triple-click line (whole logical line; host bit6, `SZ-TRI-CLICK`)

---

### Suggested order of attack

1. **I-beam caret only** — quick win, pure host paint.
2. **Drag selection** — host mouse stream, then Forth range + paint, then “type replaces selection.”
3. Optional: Shift+click extend, double-click word, triple-click line — **done**.

---

### Bottom line

- **Line cursor:** low risk, mostly one Swift highlight routine.
- **Click-drag select:** very doable, but a **real editor feature** (input path + selection paint + interaction with existing mouse modes), not a one-line change.

**Default plan for 1.0.8:** caret first for immediate “real editor” feel, then drag selection.

---

## Design notes log

_Further design suggestions and decisions go below as work proceeds._

### 2026-08-13 — Editor caret & drag selection

- Captured initial design (sections above).
- Status file created under `Resources/Docs/` for in-app / tree visibility.

### 2026-08-13 — Line (I-beam) caret

- Replaced reverse-video cell paint with a 2pt vertical bar overlay on the monospaced grid.
- macOS: `ConsoleNSTextView.showFacilityLineCaret` / `hideFacilityLineCaret`; `shouldDrawInsertionPoint` off in facility mode.
- iOS: same API on `UITextView` (tagged subview + clear `tintColor` while active).
- No Forth changes; still driven by facility `AT-XY` row/col after each `TERMINAL-REFRESH`.

### 2026-08-14 — Facility caret blink + hide system caret

- System caret: `shouldDrawInsertionPoint`, `drawInsertionPoint`, `insertionPointColor` clear, and
  forced collapsed selection at 0 while facility is active (stops top-left blink leak).
- Our I-beam blinks on a 0.53s timer (common modes so it ticks during KEY pump); motion/redraw
  restarts visible phase like a normal editor.

### 2026-08-14 — Scroll-on-drag at edges

- While drag-selecting, holding the pointer on the top/bottom or left/right of the text band
  auto-pans the view (~10 Hz) and re-extends the free end of the selection.
- Vertical: `SZ-VIEW-UP` / `SZ-VIEW-DN` move `SZ-TOP` only (do not clear selection).
- Horizontal: `SZ-HSCROLL-LEFT` / `RIGHT` adjust `SZ-HCOL` by `SZ-HSCROLL-STEP` (4).
- Host: edge timer + clamped text-band cell; wheel scroll still moves caret with view.

### 2026-08-14 — Fix dynamic window resize while editor open

- `applyPreferredFacilityCellsIfChanged` skipped `pushKey(0)` when `isPumpingEvents`
  (true during almost all KEY waits), so lastPreferred updated but SZ-SYNC-SIZE never ran.
- Wake again on real cell-grid change; defer one main turn if already pumping layout.

### 2026-08-13 — Click-drag selection

- Host: `mouseDown` / `mouseDragged` / `mouseUp` → `reportFacilityMouse` with phase; cell-change throttle; drag coalesce in event queue.
- `(SZ-CLICK)` flag bits 2–3 = phase (0 down / 1 drag / 2 up); bit1 still ⌘ for VIEW on down.
- Forth: `SZ-MOUSE-DOWN` / `DRAG` / `UP`; drag sets `SZ-SEL-*` and copies on mouse-up; no-drag up → word/line via `SZ-PLAIN-CLICK`.
- Paint: `FACILITY-REV` CODE word + facility attr grid; `SZ-SHOW-LINE` marks selected bytes; host applies reverse-video on refresh.
- Typing, BS, Del, Tab, Enter, Paste replace an active selection; motion clears it.

### 2026-08-13 — Double-click word + Shift-click extend

- Host flag bit4 = ⇧, bit5 = double-click (`clickCount == 2`).
- Double-click: `SZ-SPACE-WORD-RANGE` (space/blank/CR/LF only) → full reverse-video word + clipboard; `SZ-EXT-ANCHOR` at word start.
- Shift-click / shift-drag: free end moves; fixed end is `SZ-EXT-ANCHOR` (set on plain down, drag start, or double-click); range ordered so click may be before or after.

### 2026-08-14 — Triple-click line

- Host flag bit6 = triple-click (`clickCount >= 3`); double is exactly 2 so triple is not also a word select.
- `SZ-TRI-CLICK`: place caret, `SZ-LINE-RANGE-AT-CUR` → `SZ-COMMIT-RANGE` (selection + clipboard), `SZ-SET-LINE-ANCHOR` for ⇧-extend.

### 2026-08-13 — Gutter click no longer line-selects

- Line-number column click only places the caret at line start (`SZ-CLICK-ZONE` 1).
- Whole-line select / gutter paste-here unbound; `SZ-LINE-SELECT` remains for later use.
- Gutter reserved (e.g. breakpoints).

### 2026-08-13 — Dynamic editor size + quiet exit

- Host reports console visible size in monospaced cells (`updateConsoleVisibleSize`).
- `(SZ-VIEW-CELLS)` → facility cols/rows; **5 lines reserved** below facility for command entry.
- `SZ-SYNC-SIZE` at each `SZ-REDRAW` maps cells → `SET-EDIT-WINDOW` (width=cols-8, height=rows-5).
- Window resize while editing wakes KEY (`pushKey 0`) so the grid updates live.
- Cmd-W exit: no `SZ-EDITOR: done` / `SZ-.INFO` dump (modified warning kept).

### 2026-08-14 — Fix dynamic window resize while editor open

- Regression: `applyPreferredFacilityCellsIfChanged` skipped `pushKey(0)` when
  `isPumpingEvents` (true during almost all KEY waits), so preferred size updated
  but `SZ-SYNC-SIZE` never ran and the facility grid stayed fixed.
- Fix: wake on real cell-grid change again; if already pumping, defer `pushKey(0)`
  one main turn. `guard changed` still prevents a layout↔wake feedback loop.

### 2026-08-14 — Multi-hit nav updates visit / Files list

- Cmd-PgUp/Dn multi-hit (e.g. VIEW MAIN then walk 1/7…7/7) only did GOTO; side list
  stayed on the first hit.
- `HYPER-HIST-ENSURE-HIT`: if path+line already in VTAB, select it; else RECORD
  after current. Called from `HYPER-APPLY-HIT` so each multi-hit appears with line#.

### 2026-08-14 — File → Open… (⌘O)

- Menu + shortcut; open panel start dir = current file’s folder (VIEW/Cmd-click),
  else Library after FROMLIB session, else session cwd.
- In-editor: stage path via `(SZ-PATH@)` / host (no nested EVALUATE), key 30
  `SZ-DO-MENU-OPEN` (dirty confirm, load, visit RECORD).
- Idle: same panel then `openInSzEditor`.

### 2026-08-14 — Side [X] closes visit and switches buffer

- Closing the **current** visit: dirty Save/Discard/Cancel; remove visit; load
  previous row (or untitled if list empty). Closing a **non-current** row only
  drops the list entry.

### 2026-08-14 — Side panel file list

- 16-col panel right of editor (no "Files" title); status stays full width.
- `SZ-FL-*` stores full paths; shows leaf `name.ext` (≤16 chars).
- Recorded after successful open (EDIT / Hyper VIEW).
- Current file reverse-video; list scrolls so the current entry stays visible.
- Click a side-panel row → `SZ-FL-GOTO` reloads that file (same as Hyper switch).
- Dirty buffer on switch: centered dialog Save / Discard / Cancel (`S`/`D`/`Esc` or click).
- Hyper Cmd-click / Cmd-PgUp/PgDn: `HYPER-NOTE-HIT` + `SZ-HYPER-GOTO` register
  the destination path (e.g. `Library/Sources/forth.s`) before redraw so the
  side list and highlight stay in sync; leaf-name match merges path variants.
- **Bugfix:** `SZ-FL-LEAF` left the full path under the leaf `a u` (stack leak).
  Every side-panel paint and leaf find polluted the stack, so a second file
  (`forth.s`) never stayed on the list / highlight broke. Fixed with `2DROP`
  after saving base/len in temps. Automated suite: `Editor/sz-fl-test.fth`
  (host: `SZFLTEST=1`).
- Side panel = **visit list** (one row per path+line): leaf, line#, trailing **X**.
  Wider panel (28 cols). Click row → goto; click **X** → remove visit.
  List **persists** across editor exit / re-VIEW (session).
- Cmd-click VIEW notes origin **before** moving the caret (return to pre-click
  position, e.g. original VIEW line if you never plain-clicked elsewhere).
- New visits **insert after** the current visit (branch mid-list; later kept).
- Cmd-PgUp/PgDn: visit history first; multi-hit only if visit cannot move.
- Tests: `Editor/sz-fl-test.fth` / `SZFLTEST=1` (visit record/insert/remove/line).
- **Bug fix (list order / blank / dead top row):** `SZ-FL-CLEAR` now **ERASE**s the
  table (stale `forth.s` no longer paints above `hyper.fth` after a partial PUT).
  Hyper panel rebuild uses **bound XTs** (no silent FIND-skip holes). Empty paths
  rejected in `HYPER-V-STORE` / `SZ-FL-PUT`. `SZ-FL-GOTO` no longer no-ops when
  `i = CUR` (dead click on highlighted row). VI clamped before insert-after.
  Tests: CLEAR-ERASES, VTAB-MIRROR, PUT-EMPTY.
- **Bug fix (Cmd-W exit looks stuck):** `FACILITY-OFF` now restores the pre-editor
  console transcript (snapshot on first facility paint). Previously the last
  SZ-EDITOR frame stayed on screen until Return; exit worked but was not obvious.

### 2026-08-15 — Find next/prev: SM/REM, selection, highlight (1.0.9)

- Assembly name chars include `/` so `SM/REM` is one find token (was `REM` only).
- Cmd-← / Cmd-→ / ⌘G prefer active multi-byte selection; else word at cursor.
- Match is reverse-video selected; caret at match start; Selected: shows query.
- `SZ-FIND-GOTO` no longer re-expands the token (avoids splitting at `/`).
- Files: `sz-edit.fth` (`SZ-ASM-NAME-CHAR?`, `SZ-FIND-LOAD-TOKEN`, `SZ-FIND-GOTO`,
  `SZ-FIND-SHOW-TOKEN`).

### 2026-08-15 — Facility Unicode + box-drawing editor chrome (1.0.9)

**Host (`FacilityTerminal.swift`)**

- Cells store one **Unicode scalar** each (was ASCII-only `UInt8` → `.` for non-ASCII).
- UTF-8 decode across `EMIT` / `TYPE` / `XEMIT` byte streams so multi-byte glyphs
  (box-drawing) occupy a single monospaced cell.
- `render()` emits full scalars; selection/caret still assume BMP (1 UTF-16 unit/cell).

**Layout (`sz-screen.fth`) — facility rows = text height + 7 chrome**

```
row 0     ╭──────────────── full width ────────────────╮
row 1     │ status (path, L/C, size, Sel: …)           │
row 2     ├─────┬──────────────────────┬───────────────┤
rows 3…   │ NNN │ text body            │ visit list    │
          ├─────┴──────────────────────┴───────────────┤
          │ help col │ help col │ help col │ help col  │
          │ help col │ help col │ help col │ help col  │
          ╰──────────┴──────────┴──────────┴───────────╯
```

- Outer box: light arcs `╭╮╰╯`, edges `─│`, mid rules `├┤` with column tees `┬┴`
  aligned to gutter / text / side-panel separators.
- Dirty Save/Discard dialog uses the same box characters (`sz-edit.fth`).
- `SZ-CHROME-ROWS = 7`; `SZ-TEXT-TOP = 3`; host `facilityTextBand` matches
  (`KernelBridge.swift`).

### 2026-08-15 — Status path + Selected: (1.0.9)

- Path **tail at most 30** characters (`SZ-STAT-PATHMAX`); longer paths show the
  useful suffix (not a 3-dot ellipsis).
- **Bug fix:** early tail math subtracted 30 from the **address** (`>R R@ - +`)
  after `MIN` had already replaced `u`, producing garbage / “…”-looking junk.
  Correct form: `DUP 30 > IF  30 - + 30  THEN` (same pattern as the old 33-char clip).
- `SZ-ROOM-KEEP` reserves width for `Sel: "word"` [find note] so path/meta cannot
  clip it; then pad and draw **Selected: flush right** in the status box.
- Status/help content uses room-limited emit so text never wraps into chrome rows.

### 2026-08-15 — Help grid with aligned separators (1.0.9)

- Four fixed-width help fields + graphic `│` (not ASCII `|`); both help rows share
  widths so separators line up vertically.
  - W1=16 `Cmd-E/click VIEW` / `drag/Shift-click` (padded)
  - W2=18 `Cmd-PgUp/Dn visits` / `dbl-word tri-line`
  - W3=15 `side: line# [X]` / `Cmd-click VIEW`
  - W4 = remaining inner width / `find Cmd-F/G` / `Cmd-X/C/V/S/W`
- Outer bottom bar `SZ-DRAW-HELP-BOT` places `┴` under each help separator so the
  help area is a closed grid (last col grows with window zoom).

### 2026-08-15 — Cmd-F type-in find on status line (1.0.9)

- **⌘F** opens status type-in find (key 131); host wires letter `f` like ⌘G.
- Status layout:
  - path/meta on the left
  - **`Select/Find` title ends at the Files-column `│`** (`SZ-EDIT-RIGHT`)
  - type-in / highlighted query is **right of that `│`** (under the visit list)
  - Files `│` is drawn on the status row between title and type-in area
- ⌘F with **no selection**: empty field, no word-under-cursor seed, no auto-highlight.
  With a selection: seed query and live-match as before.
- Typing edits `SZ-TOKEN` (reverse-video in type-in area); caret blinks there.
- **Modal until Esc or document click:** arrows move the find caret only; other
  keys are swallowed (never reach the document). **Click** in the type-in field
  enters/stays in find-edit and places the caret; **click in the document** leaves
  find-edit and resumes normal editing. **Enter** = find next and **stay** in the
  field (avoids Return deleting a match in the buffer); **Esc** = leave; **⌘G /
  ⌘←→** next/prev while staying in the field.
- Typed / selection queries use **substring** search (`SZ-FIND-TYPED`); word-under-
  cursor find stays **whole-word**.

