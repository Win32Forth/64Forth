SZ-EDITOR — TZForth port of Small Zimmer's Editor
=================================================

Location
--------
  Project:  TZForth/Library/Editor/
  Runtime:  Resources/Library/Editor/  (via Copy Library)

Status
------
  Phase 0  Scaffolding                 done
  Phase 1  sz-host.fth                 done
  Phase 2  sz-buffer.fth               done
  Phase 3  sz-screen.fth               done mono redraw/scroll
  Phase 4  sz-edit.fth                 done minimal edit loop
  Phase 5  navigation + frame/cursor   done

Files
-----
  SZ-EDITOR.fth           ANEW driver + load chain
  sz-host.fth             Host shims
  sz-buffer.fth           Buffer + load/save
  sz-screen.fth           PAGE/AT-XY display
  sz-edit.fth             Interactive keys
  SZ-EDITOR-README.txt    This note

Reference: Legacy/SmallZimmerEditor.fth — DO NOT MODIFY

How to load
-----------
  Product boot (autoload.fth) already does:
    FROMLIB FLOAD Editor/SZ-EDITOR.fth
  so the editor is available at the REPL after launch.

  Reload after source edits: FROMLIB FLOAD Editor/SZ-EDITOR.fth again

File menu (macOS)
-----------------
  ⌘N / File → New     empty untitled buffer and enter the editor
  ⌘O / File → Open…   open a file in the editor
  ⌘S / File → Save    save (while editing)
  ⌘W / File → Close   leave the editor (dirty prompt if modified)
  ⌘Q                  quit TZForth (application)

Console / Forth
---------------
  S" /path/to/file.txt" SZ-EDIT-FILE
  SZEDIT /path/to/file.txt
  SZEDIT                 \ open panel (same as File → Open)
  FROMLIB SZEDIT Editor/SZ-EDITOR-README.txt
  FROMLIB SZEDIT         \ open panel starting at Resources/Library
  SZ-EDIT-NEW
  SZ-BUFFER-SMOKE     sample file for quick tests

Vocabulary
----------
  Body words live in the standard EDITOR vocabulary (boot VOCABULARY EDITOR).
  SZEDIT is defined in FORTH so the console entry point needs no ALSO EDITOR.
  To reach body words from the REPL:  ALSO EDITOR  ...  PREVIOUS
  Host File menu (⌘N / ⌘O) temporarily searches EDITOR when starting New/Open.

Display
-------
  Status bar: name, modified flag, L (line), C (column), bytes used/capacity, WxH.
  Text body: user-sized (default 80×20). Facility adds gutter/frame/help
  (cols = width+8, rows = height+4).
  Text rows:  |NNNN|text body...|

  width height SET-EDIT-WINDOW   \ e.g. 100 30 SET-EDIT-WINDOW (live + saved)
  EDIT-WINDOW                    \ ( -- width height )
  .SETTINGS                      \ shows current edit window
  SAVE-SETTINGS                  \ also persists edit window with other prefs

Buffer
------
  Heap-backed (ALLOCATE), initial 1 MB, grows as needed for inserts / large loads
  (and future copy-paste).

Editor keys (while editing)
---------------------------
  Arrow keys   move
  Home / ^A    start of line
  End  / ^E    end of line
  Ctrl-Home    start of file
  Ctrl-End     end of file
  PgUp / PgDn  page up / down
  Enter        newline CRLF
  BS           backspace
  Del / ^D     delete under cursor
  other printable  insert

  Display: framed text area; insert point reverse-video (accent color)

After quit
----------
  Editor calls FACILITY-OFF and CLS so PAGE/AT-XY mode ends and the
  normal console/menu work again. If the screen keeps clearing, type CLS.

Main words
----------
  SZ-LOAD  SZ-SAVE  SZ-SAVE-AS  SZ-.INFO
  SZ-EDIT  SZ-EDIT-FILE  SZ-EDIT"
  SZ-REDRAW  SZ-VIEW-RESET

Limits
------
  Buffer max 262144 bytes
  Display 80 cols, text rows 1..22
  No color, no dual file yet, no search
