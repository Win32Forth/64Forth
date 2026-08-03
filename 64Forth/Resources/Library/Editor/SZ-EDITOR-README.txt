SZ-EDITOR — Small Zimmer Editor for 64Forth (TZForth port)
=========================================================

Location
--------
  Project:  64Forth/Resources/Library/Editor/
  Runtime:  app bundle Contents/Resources/Library/Editor/  (Copy Library)

Status
------
  Phases 1–5 load on 64Forth (pure-Forth line scans; no TZForth Swift host
  primitives required). Open-panel for bare SZEDIT is not wired yet — pass a
  path. Arrow keys use Facility Ext EKEY → F-PC codes via SZ-KEY.
  Ctrl-Home / Ctrl-End (or Cmd-Home/End, Cmd-Up/Down) jump to start/end of file.

How to load
-----------
  FROMLIB FLOAD Editor/SZ-EDITOR.fth

  Rebuild the app after editing .fth files so the bundle Library is refreshed.

How to edit a file
------------------
  SZEDIT /tmp/notes.txt
  S" /tmp/notes.txt" SZ-EDIT-FILE
  FROMLIB SZEDIT Editor/SZ-EDITOR-README.txt
  SZ-EDIT-NEW

  Bare SZEDIT (no path) opens a macOS file dialog (like TZForth).
  FROMLIB SZEDIT  — dialog starts in Resources/Library.
  FROMLIB is also honored by OPEN-FILE for Library-relative paths.

Vocabulary
----------
  Body words live in the EDITOR vocabulary.
  SZEDIT is defined in FORTH (no ALSO EDITOR needed for the entry point).
  Body / smoke:  ALSO EDITOR  SZ-HOST-SMOKE  SZ-.INFO  PREVIOUS

Keys while editing (SZ-KEY)
---------------------------
  Arrows, Home/End, PgUp/PgDn  (Facility Ext K-* mapped to editor codes)
  Ctrl-Home / Ctrl-End  start / end of file  (also Cmd-Home/End, Cmd-Up/Down)
  Enter, BS, Del, printable insert
  Cmd-S / Ctrl-S save   Cmd-W / Ctrl-Q close

Display
-------
  width height SET-EDIT-WINDOW   \ e.g. 100 30 SET-EDIT-WINDOW
  EDIT-WINDOW                    \ ( -- width height )

Main words
----------
  SZ-LOAD  SZ-SAVE  SZ-SAVE-AS  SZ-.INFO
  SZ-EDIT  SZ-EDIT-FILE  SZ-EDIT-NEW  SZEDIT
  SZ-GOTO-LINE ( n -- )          1-based line, start of line
  SZ-EDIT-FILE-AT ( c-addr u n -- )  load file, go to line n, edit
  SZ-REDRAW  SZ-VIEW-RESET

Limits
------
  Buffer starts at 1 MB (ALLOCATE), grows as needed
  Default text body 80×20 (+ chrome)
  No dual file, no search yet

Reference
---------
  TZForth Library/Editor — Swift registered SZ-HOST-* scans; 64Forth reimplements
  those in sz-buffer.fth so the same high-level modules work.
