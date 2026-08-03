64Forth Hyper / VIEW (Phase 2–3)
================================

Load
----
  FROMLIB FLOAD Editor/SZ-EDITOR.fth   \ required for VIEW
  FROMLIB FLOAD Hyper/hyper.fth

Commands
--------
  LOCATE <name>     Print defining path:line from Config/HYPER.NDX
  VIEW <name>       Open file in SZ-EDITOR at that line
  SEE-SOURCE        Alias of VIEW
  HYPER-RELOAD      Re-read Config/HYPER.NDX
  .HYPER            Status
  HYPER-HELP        Short help

Editor (ALSO EDITOR)
--------------------
  SZ-GOTO-LINE ( n -- )                 1-based line, cursor at start
  SZ-EDIT-FILE-AT ( c-addr u n -- )     load path, go to line n, edit

Index
-----
  python3 tools/build_hyper_index.py
  → 64Forth/Resources/Config/HYPER.NDX

Path resolution (host)
----------------------
  Config/…   → Resources/Config
  Library/…  → Resources/Library
  Kernel/…   → developer source tree (HYPER_ROOT or Xcode #filePath)

  LOCATE works without the tree; VIEW of Kernel/… needs SrcTree so OPEN-FILE
  can read the sources.
