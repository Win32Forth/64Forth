64Forth — Swift host + PickleForth ARM64 kernel
================================================

Version 1.5.2 (build 46)

Console header (ConsoleView banner), e.g.:
  === 64Forth 1.5.2 === Oct 2, 2026 1:48 PM ===
Update the date/time only when finishing a version change set, just before
DMG + commit/push — not on every intermediate build.

Hybrid macOS app: ARM64 ITC kernel (assembly) + SwiftUI console/host
(TZForth-style FileHost, AutoLoad, Library, FROMLIB).

Library/Pascal — Tiny Pascal → Forth translator (`PASCAL"`, `PASCAL-TO-FILE`).
See Library/Pascal/README.txt. Prefer PASY.PAS; PASX.PAS is the older stress sample.

REF / XREF / ANYWORDS — cold-loaded from Kernel/xref.fth (always present after
boot). Classic TCOM source kept at Library/TCOM/REF.FTH. REF does not
cross-reference IMMEDIATE words. See Docs/STATUS.md.

Samples (App Output): Library/Sample/VED64.fth → VED64 (minimal VED);
Library/Sample/MIDNIGHT.FTH → MAIN (Towers of Hanoi). See Docs/STATUS.md.

Editor (v1.5.2+)
----------------
  The in-app SZ-EDITOR (Library/Editor) is removed. Editing moves to the
  separate **64Edit** app (https://github.com/Win32Forth/64Edit), talking to
  64Forth over a local socket (Application Support/64Forth/edit.sock).
  Autoload keeps an empty EDITOR vocabulary so Hyper can ALSO EDITOR.
  DEBUG / DBG stay console-only; SEE / VIEW / DBG print full path:line.
  EDIT opens 64Edit in edit mode. VIEW / EDIT-AT write pending-goto.json
  (path, line, mode "view") so 64Edit scrolls to the definition and stays
  read-only until the user switches to Edit (dialog or banner button).

Windows (macOS)
---------------
  Console     — Forth REPL.
  App Output  — GRAPHICS / Emitter / stand-alone apps only.
  64Edit      — external editor (separate app), not inside 64Forth.
