64Forth Hyper / VIEW (Phase 2–3a)
=================================

Load
----
  FROMLIB FLOAD Editor/SZ-EDITOR.fth   \ required for VIEW
  FROMLIB FLOAD Hyper/hyper.fth

Commands
--------
  LOCATE <name>     Print defining path:line from HYPER.NDX
  VIEW <name>       Open file in SZ-EDITOR at that line
  SEE-SOURCE        Alias of VIEW
  HYPER-REINDEX     Rebuild Config/HYPER.NDX, reload
  HYPER-RELOAD      Re-read index (Config/HYPER.NDX, else cwd HYPER.NDX)
  .HYPER            Status
  HYPER-HELP        Short help

Editor (ALSO EDITOR)
--------------------
  SZ-GOTO-LINE ( n -- )                 1-based line, cursor at start
  SZ-EDIT-FILE-AT ( c-addr u n -- )     load path, go to line n, edit

Index load order
----------------
  1. Config/HYPER.NDX  (HYPER-REINDEX output + shipped / Python index)
  2. HYPER.NDX in session cwd (legacy fallback)

  Config/ resolve (host, same family as FROMLIB → Library/):
    - App Support overlay if present (writable reindex when bundle is RO)
    - Developer source tree Resources/Config (Xcode / HYPER_ROOT)
    - Bundled Resources/Config (reads; writes mirrored to App Support)

In-app reindex (Phase 3a)
-------------------------
  HYPER-REINDEX
    → scans fixed Kernel/ + Library/ SPECS (no DIR walk yet)
    → TYPE 0 prefixes + BOOT_WORD → X* labels in Kernel/forth.s
    → CREATE-FILE Config/HYPER.NDX, then HYPER-RELOAD

  Limits vs tools/build_hyper_index.py:
    - Fixed file list (HayesTest / ANSValidate / Benchmarks omitted)
    - BOOT_WORD resolves CodeLabel → Kernel/forth.s (e.g. DUP → XDUP:)
    - Kernel .s/.inc: TYPE 0 only on .ascii / .asciz lines

Offline rebuild (full index, CI / ship Config/)
-----------------------------------------------
  python3 tools/build_hyper_index.py
  → 64Forth/Resources/Config/HYPER.NDX

Path resolution (host)
----------------------
  Config/…   → Resources/Config
  Library/…  → Resources/Library
  Kernel/…   → developer source tree (HYPER_ROOT or Xcode #filePath)

  LOCATE works without the tree; VIEW of Kernel/… needs SrcTree so OPEN-FILE
  can read the sources.

Files
-----
  hyper.fth         LOCATE / VIEW / load
  hyper-index.fth   HYPER-REINDEX (FLOAD'd from hyper.fth)
