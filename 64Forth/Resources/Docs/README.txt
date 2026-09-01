64Forth — Swift host + PickleForth ARM64 kernel
================================================

Version 1.2.1

Console header (ConsoleView banner), e.g.:
  === 64Forth 1.2.1 === Aug 31, 2026 11:04 PM ===
Update the date/time only when finishing a version change set, just before
DMG + commit/push — not on every intermediate build.

Hybrid macOS app: ARM64 ITC kernel (assembly) + SwiftUI console/host
(TZForth-style FileHost, AutoLoad, Library, FROMLIB).

Editor + command pane (v1.1.0)
------------------------------
  While SZ-EDITOR is open, the window splits: facility grid above, scrollable
  ok(n)> command pane below (drag the striped splitter). Type Forth in the
  lower pane without leaving the editor KEY session (shared data stack).
  Long FLOAD output (Hayes, ANS-VALIDATE) scrolls live in the command pane.
  See STATUS.md in this folder for design notes and status.
