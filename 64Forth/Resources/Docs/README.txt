64Forth — Swift host + PickleForth ARM64 kernel
================================================

Version 1.5.3 (build 47)

Console header (ConsoleView banner), e.g.:
  === 64Forth 1.5.3 === Oct 3, 2026 11:21 AM ===
Update the date/time only when finishing a version change set, just before
DMG + commit/push — not on every intermediate build.

DMG (v1.5.2+) contains 64Forth.app and 64Edit.app. Keep their marketing
versions matched (both 1.5.3 as of this release). Install both into the same
folder (/Applications recommended). They link via
~/Library/Application Support/64Forth/edit.sock — no extra pairing.

Hybrid macOS app: ARM64 ITC kernel (assembly) + SwiftUI console/host
(TZForth-style FileHost, AutoLoad, Library, FROMLIB).

Library/Pascal — Tiny Pascal → Forth translator (`PASCAL"`, `PASCAL-TO-FILE`).
See Library/Pascal/README.txt. Prefer PASY.PAS; PASX.PAS is the older stress sample.

REF / XREF / ANYWORDS — cold-loaded from Kernel/xref.fth (always present after
boot). Classic TCOM source kept at Library/TCOM/REF.FTH. REF does not
cross-reference IMMEDIATE words. See Docs/STATUS.md.

Samples (App Output): Library/Sample/VED64.fth → VED64 (minimal VED);
Library/Sample/MIDNIGHT.FTH → MAIN (Towers of Hanoi). See Docs/STATUS.md.

Editor (v1.5.2+; version lockstep v1.5.3+)
-----------------------------------------
  The in-app SZ-EDITOR (Library/Editor) is removed. Editing moves to the
  separate **64Edit** app (https://github.com/Win32Forth/64Edit), talking to
  64Forth over a local socket (Application Support/64Forth/edit.sock).
  Ship 64Edit at the same marketing version as 64Forth.
  Autoload keeps an empty EDITOR vocabulary so Hyper can ALSO EDITOR.
  SEE / VIEW / DBG print full path:line. EDIT opens 64Edit in edit mode.
  VIEW / EDIT-AT / DEBUG pauses write pending-goto.json (path, line, mode
  "view") and open or scroll 64Edit; tabs keep browse mode per file.
  When edit.sock is already connected, skip open -a to avoid window flash.
  64Edit debug toolbar: Step Over / Into / Out / Continue / Stop (same as
  console F6 / F7 / F8 / g / q). Release finds 64Edit beside 64Forth.app or
  in /Applications; Debug builds prefer Xcode DerivedData first.

Windows (macOS)
---------------
  Console     — Forth REPL.
  App Output  — GRAPHICS / Emitter / stand-alone apps only.
  64Edit      — external editor + DEBUG source (separate app).
