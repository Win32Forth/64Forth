SZ-EDITOR — Small Zimmer Editor for 64Forth (TZForth port)
=========================================================

Location
--------
  Project:  64Forth/Resources/Library/Editor/
  Runtime:  app bundle Contents/Resources/Library/Editor/  (Copy Library)

Status (v1.0.2)
---------------
  Phases 1–5 complete on 64Forth (pure-Forth line scans; FacilityTerminal host).
  Full-screen edit, save/close, find, selection/clipboard, mouse + wheel, Tab
  indent, Hyper VIEW integration, EDIT entry word.

How to load
-----------
  FROMLIB FLOAD Editor/SZ-EDITOR.fth

  Often already loaded via Resources/AutoLoad/autoload.fth.
  Rebuild the app after editing .fth files so the bundle Library is refreshed.

How to edit a file
------------------
  EDIT /tmp/notes.txt              \ preferred FORTH entry (same as SZEDIT)
  SZEDIT /tmp/notes.txt            \ legacy name
  S" /tmp/notes.txt" SZ-EDIT-FILE
  FROMLIB EDIT Editor/SZ-EDITOR-README.txt
  FROMLIB EDIT TCOM/SZ             \ .fth added if leaf has no extension
  SZ-EDIT-NEW

  Bare EDIT / SZEDIT (no path) opens a macOS file dialog.
  FROMLIB EDIT  — dialog starts in Resources/Library.
  FROMLIB is also honored by OPEN-FILE for Library-relative paths.

  TextEdit path   \ system text editor (former kernel EDIT)

Vocabulary
----------
  Body words live in the EDITOR vocabulary.
  EDIT and SZEDIT are defined in FORTH (no ALSO EDITOR for the entry point).
  Body / smoke:  ALSO EDITOR  SZ-HOST-SMOKE  SZ-.INFO  PREVIOUS

Keys while editing (SZ-KEY)
---------------------------
  Arrows, Home/End, PgUp/PgDn  (Facility Ext K-* mapped to editor codes)
  Ctrl-Home / Ctrl-End  start / end of file  (also Cmd-Home/End)
  Enter, BS, Del, printable insert
  Tab               insert spaces to next 4-column tab stop
  Cmd-S / Ctrl-S    save
  Cmd-W / Ctrl-Q    close (S/D if dirty)
  Cmd-E             VIEW word under cursor (Hyper loaded)
  Cmd-PgUp / Cmd-PgDn   previous / next Hyper hit (return from Cmd-E)
  Cmd-Left / Cmd-Right  previous / next same-word in this file only
                        (.s/.inc/.asm: identifier rules so labels work —
                        XROT: and bl XROT match; Forth files stay blank-delimited)
  Cmd-G / Cmd-Shift-G   find next / prev (same as arrows)
  Mouse click       place caret; body shows word under click in status
  Mouse drag / ⇧    range select; double-click = space-delimited word
  Cmd-click         VIEW word under click (same as click + Cmd-E; needs Hyper)
  Wheel / trackpad  pan view (caret/highlight stay in file; short files locked)
  Line# gutter      place caret only (reserved; e.g. future breakpoints)
  Cmd-X / Cmd-C / Cmd-V   cut / copy / paste

Display
-------
  width height SET-EDIT-WINDOW   \ e.g. 100 50 SET-EDIT-WINDOW
  EDIT-WINDOW                    \ ( -- width height )
  Status bar shows trailing path segment when the name is long.

Main words
----------
  SZ-LOAD  SZ-SAVE  SZ-SAVE-AS  SZ-.INFO
  SZ-EDIT-FILE  SZ-EDIT-NEW  SZEDIT  EDIT
  SZ-GOTO-LINE ( n -- )          1-based line, start of line
  SZ-EDIT-FILE-AT ( c-addr u n -- )  load file, go to line n, edit
  SZ-REDRAW  SZ-VIEW-RESET

Limits
------
  Buffer starts at 1 MB (ALLOCATE), grows as needed
  Default text body 80×20 (+ chrome); AutoLoad often sets 100×50
  No dual file buffer yet

Reference
---------
  TZForth Library/Editor — Swift registered SZ-HOST-* scans; 64Forth reimplements
  those in sz-buffer.fth so the same high-level modules work.
