64Forth Hyper / VIEW (Phase 2–5)
================================

Load
----
  FROMLIB FLOAD Editor/SZ-EDITOR.fth   \ required for VIEW
  FROMLIB FLOAD Hyper/hyper.fth

Vocabulary
----------
  Almost all Hyper words are defined in HYPER-VOC (not FORTH).
  HYPER-REINDEX is in FORTH (thin wrapper).

  After load, search order is FORTH then HYPER-VOC, so VIEW / LOCATE /
  .HYPER work at the console without ALSO. Do not bare FORTH after that
  if you still want Hyper commands (FORTH replaces order[0] and drops HYPER-VOC);
  use:  ONLY FORTH ALSO HYPER-VOC  GET-ORDER >R SWAP R> SET-ORDER

  HYPER-VOC WORDS              list Hyper words only
  ORDER                        show search order

Commands (from HYPER-VOC unless noted)
-------------------------------------
  LOCATE <name>     Print defining path:line  (shows [n/m] if multiple hits)
  VIEW <name>       Open file in SZ-EDITOR at that line
  SEE <name>        VIEW if SZ-EDITOR loaded, else decompile (kernel SEE)
  SEE-SOURCE        Alias of VIEW
  HYPER-NEXT        Next hit for last LOCATE/VIEW   (Cmd-PgDn)
  HYPER-PREV        Previous hit                    (Cmd-PgUp)
  HYPER-REINDEX     Rebuild Config/HYPER.NDX, reload (FORTH)
  HYPER-RELOAD      Re-read index (Config/HYPER.NDX, else cwd HYPER.NDX)
  .HYPER            Status
  HYPER-HELP        Short help
  MIN-HYPER-NOISE   ON quiet reindex  e.g.  HYPER-VOC MIN-HYPER-NOISE ON FORTH

  Cmd-E             VIEW word under caret (console or SZ-EDITOR);
                    in editor, saves origin so Cmd-PgUp can return
  Cmd-PgDn          next hit for current name
  Cmd-PgUp          previous hit, or return to Cmd-E origin
  Cmd-Left/Right    prev/next same-word occurrence in the open file only

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

In-app reindex (Phase 3a / 4)
-----------------------------
  HYPER-REINDEX   (FORTH; implementation helpers in HYPER-VOC)
    → TYPE 0 from Config/HYPER.CFG
    → SPECS/*EXCLUDE via host (OPEN Config/HYPER.SPECS = expanded list)
    → BOOT_WORD → CodeLabel in Kernel/forth.s
    → CREATE-FILE Config/HYPER.NDX, then HYPER-RELOAD
  Quiet:  HYPER-VOC MIN-HYPER-NOISE ON FORTH  then  HYPER-REINDEX

  Limits vs tools/build_hyper_index.py:
    - TYPE 0 only in Forth (no TYPE 1/2/4 yet)
    - Kernel .s/.inc: TYPE 0 only on .ascii / .asciz lines

Editor (Phase 4a)
-----------------
  Mouse click in the facility/SZ-EDITOR window moves the buffer cursor
  to the clicked cell (text body only; chrome ignored).

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
