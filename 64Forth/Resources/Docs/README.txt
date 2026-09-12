64Forth — Swift host + PickleForth ARM64 kernel
================================================

Version 1.3.8

Console header (ConsoleView banner), e.g.:
  === 64Forth 1.3.8 === Sep 12, 2026 3:51 PM ===
Update the date/time only when finishing a version change set, just before
DMG + commit/push — not on every intermediate build.

Hybrid macOS app: ARM64 ITC kernel (assembly) + SwiftUI console/host
(TZForth-style FileHost, AutoLoad, Library, FROMLIB).

Three windows (v1.3.8+, macOS)
-----------------------------
  Console     — Forth REPL only (live while the editor KEY loop runs).
  SZ-EDITOR   — Facility grid in its own window (FacilityEditorHost).
  App Output  — GRAPHICS / Emitter / stand-alone apps only (never the editor).

  VIEW / Cmd-E / Cmd-click open the editor; SEE decompiles to the Console.
  iOS: Console only (no SZ-EDITOR host). See STATUS.md for details.
