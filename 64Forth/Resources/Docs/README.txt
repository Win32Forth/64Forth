64Forth — Swift host + PickleForth ARM64 kernel
================================================

Version 1.4.1

Console header (ConsoleView banner), e.g.:
  === 64Forth 1.4.1 === Sep 19, 2026 9:40 PM ===
Update the date/time only when finishing a version change set, just before
DMG + commit/push — not on every intermediate build.

Hybrid macOS app: ARM64 ITC kernel (assembly) + SwiftUI console/host
(TZForth-style FileHost, AutoLoad, Library, FROMLIB).

Library/Pascal — Tiny Pascal → Forth translator (`PASCAL"`, `PASCAL-TO-FILE`).
See Library/Pascal/README.txt. Prefer PASY.PAS; PASX.PAS is the older stress sample.

Three windows (v1.3.8+, macOS)
-----------------------------
  Console     — Forth REPL only (live while the editor KEY loop runs).
  SZ-EDITOR   — Facility grid in its own window (FacilityEditorHost).
  App Output  — GRAPHICS / Emitter / stand-alone apps only (never the editor).

  VIEW / Cmd-E / Cmd-click open the editor; SEE decompiles to the Console.
  iOS: Console only (no SZ-EDITOR host). See STATUS.md for details.
