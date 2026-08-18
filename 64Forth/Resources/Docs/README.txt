64Forth — Swift host + PickleForth ARM64 kernel
================================================

Version 1.1.4

Console header (ConsoleView banner), e.g.:
  === 64Forth 1.1.4 === Aug 18, 2026 11:57 AM ===
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

Quick start (in the console)
----------------------------
  FROMLIB FLOAD BigInteger/big-int.fth
  FROMLIB FLOAD PI/pi-test.fth
  FROMLIB FLOAD HayesTest/HayesTest.fth

  ALSO FP          \ floating-point word set (vocabulary FP)
  1.5e0 2e0 F+ F.

  FROMLIB FLOAD ANSValidate/ANS-VALIDATE.fth

  \ Editor + Hyper (often already loaded via AutoLoad)
  EDIT myfile              \ SZ-EDITOR; appends .fth if leaf has no extension
  FROMLIB EDIT TCOM/SZ
  TextEdit notes.txt         \ system text editor (kernel EDIT renamed)
  LOCATE DUP
  VIEW SWAP                \ ⌘PgDn / ⌘PgUp for other definitions; ⌘E VIEW under caret

  .THREADS         \ hash-chain depths for CONTEXT wordlist
  .VOCABULARIES    \ FORTH + each VOCABULARY, with thread depths

ANS word sets (v1.0)
--------------------
  Core / Core Ext, Double, String (+ String Ext), Exception, File-Access,
  Locals (+ (LOCAL) / LOCALS|), Memory-Allocation, Programming-Tools,
  Search-Order, Facility + Facility Ext (structures, EKEY>FKEY, K-*),
  Block (file volume; LOAD restores BLK), Floating-point (VOCABULARY FP),
  Extended Character (UTF-8 XChar in kernel).

  ENVIRONMENT? reports presence and selected parameters (value then true for
  boolean word-set queries), including FACILITY-EXT. This is not a formal
  ANS System certificate.

Dictionary threads (v0.9+)
--------------------------
  Each wordlist has DICT_THREADS (16) heads; names hash to a thread in
  _header_build / FIND / SEARCH-WORDLIST. LAST tracks the most recently
  defined CFA (IMMEDIATE, ALIAS, RECURSE, MARKER restore all FORTH heads).
  Prompt after interpret: ok(n)> with data-stack depth n.

Facility terminal + SZ-EDITOR (v1.0)
------------------------------------
  PAGE / AT-XY use a host character-cell grid (FacilityTerminal.swift), not raw
  ANSI. SZ-EDITOR paints full-screen via that grid; keys via Facility Ext EKEY
  and classic F-PC codes (arrows, Home/End, Ctrl/Cmd-Home/End, PgUp/Dn, BS, Del).

  EDIT name          open in SZ-EDITOR (FORTH entry; .fth if no extension)
  SZEDIT name         same (legacy name)
  TextEdit name      open in the system editor (former kernel EDIT)
  Bare EDIT / SZEDIT opens a file dialog; FROMLIB is honored for Library paths.

  Cmd-S save, Cmd-W close (S/D if dirty); Cmd-Q same S/D prompt, cancel does
  not quit the app. Cmd-E VIEW (with Hyper loaded). Cmd-←/→ / Cmd-G find in
  buffer. Cmd-X/C/V cut/copy/paste. Mouse click + wheel scroll. Tab → spaces
  (4-column stops).

Hypertext LOCATE / VIEW (v1.0 — Phases 0–5 complete)
----------------------------------------------------
  Loaded via Library/Hyper (often AutoLoad). Words live in HYPER-VOC; search
  order after load is FORTH then HYPER-VOC. HYPER-REINDEX is in FORTH.

  LOCATE name     print path:line  [n/m] if multiple hits
  VIEW name       open SZ-EDITOR at definition
  SEE name        VIEW if editor loaded, else decompile
  Cmd-PgUp/Dn     previous/next hit; Cmd-PgUp also returns from Cmd-E origin
  HYPER-REINDEX   rebuild Config/HYPER.NDX (TYPE 0 in-app; full index via Python)

  Docs: Library/Hyper/README.txt , Config/README.txt

Library paths + Tools menus
---------------------------
  Project sources: 64Forth/Resources/Library/ — copied into the app bundle on
  build. FROMLIB always resolves under Contents/Resources/Library/, independent
  of session cwd. Rebuild after editing Library .fth files.

  Tools → Show Library / AutoLoad / Docs / Config Folder opens that folder in
  Finder (NSWorkspace.open; works for paths inside the .app package).

Hayes suite
-----------
  FROMLIB FLOAD HayesTest/HayesTest.fth
  (driver: src/Harness/prepare-blocks.fth + src/Harness/runfptests.fth;
   stock tests under src/ and src/fp/)
  Expect: all *ERRORS counters 0, "FP tests finished", paranoia Excellent,
  "=== 64Forth Hayes subset complete ==="
  Failures print a clearer banner (not whole-file SOURCE dump).

ANS-VALIDATE - Library Forth spot-checks
----------------------------------------
  FROMLIB FLOAD ANSValidate/ANS-VALIDATE.fth
  Modules: tester, core, core-ext, search, string, facility, exception,
  memory, double, locals, tools, file, block, xchar, float, host.
  Expect: ANS-VALIDATE: 383 passed, 0 failed. ALL PASS
  Batch lines show stack(n); EMPTY-DATA at suite end.

Optional / not full TZForth parity
----------------------------------
  Line-at-a-time INCLUDE via fileid, App Sandbox for store builds,
  editor dual-buffer, Forth reindex TYPE 1/2/4 (offline Python is fuller).

See DESIGN.md and README.md in the project root.
  Also ANS_COMPLIANCE.rtf and THROW_CODES.rtf in this Docs folder.
