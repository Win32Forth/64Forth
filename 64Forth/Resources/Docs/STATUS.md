# 64Forth development status

**Version in progress:** 1.0.8  
**Last updated:** 2026-08-13  

This file tracks design notes and progress for work after 1.0.7.  
Append new design sections as we go; mark items done when implemented.

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
