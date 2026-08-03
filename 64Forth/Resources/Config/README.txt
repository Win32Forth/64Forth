64Forth Config (hypertext and related data)
===========================================

This folder is copied into the app as:

  64Forth.app/Contents/Resources/Config/

Purpose
-------
  Hand-maintained and generated files for the hypertext / VIEW system
  (F-PC HYPER.NDX lineage) and, later, other non-source configuration.

Files
-----
  HYPER.CFG     Scanner rules for the offline index builder.
  HYPER.NDX     Word → file:line index (generated — do not hand-edit).
  README.txt    This note.

Rebuild the index (Phase 1)
---------------------------
  From the repository root:

    python3 tools/build_hyper_index.py

  Options:

    python3 tools/build_hyper_index.py --help
    python3 tools/build_hyper_index.py --src-root 64Forth --cfg 64Forth/Resources/Config/HYPER.CFG
    python3 tools/build_hyper_index.py -q

  Defaults: --src-root = <repo>/64Forth, writes Config/HYPER.NDX next to HYPER.CFG.

  Rebuild after adding/renaming defining words in Kernel or Library sources.
  (Optional future: Xcode Run Script phase to regenerate on each build.)

HYPER.NDX format (v1 text)
--------------------------
  # comment lines are ignored
  @ relative/path
  WORDNAME linenumber

  - Lines starting with @ set the current source file for following entries.
  - Paths are relative, forward-slash style:
        Kernel/forth.s
        Library/Editor/sz-edit.fth
    (Library/* is rewritten from Resources/Library/* at build time.)
  - Lookup is case-insensitive (matches 64Forth FIND).
  - CODE words from BOOT_WORD are resolved to their X* implementation line
    in Kernel/forth.s when that label exists.
  - Multiple hits for one name may appear (redefines across files).

Resolution roots (runtime — Phase 2 VIEW)
-----------------------------------------
  1. Load index from:  Contents/Resources/Config/HYPER.NDX
  2. Open source path by resolving against:
       - Developer checkout (64Forth/…) when running from Xcode, and/or
       - Bundle Resources for Library/* shipped with the app, and/or
       - A user-configured source root (future HYPER-ROOT)

HYPER.CFG (summary)
-------------------
  SPECS globs (relative to --src-root), *EXCLUDE, TYPE 0 "prefix " rules,
  STOPAT, AFTER/BEFORE — see HYPER.CFG comments. Compatible in spirit with
  F-PC/NEWZ/TCOM HYPER.CFG.

Tools menu
----------
  Tools → Show Config Folder — open this directory in Finder.

Status
------
  Phase 0: folder + format + fixture
  Phase 1: builder + full generated NDX  ← current
  Phase 2: VIEW / LOCATE Forth words (not yet)
  Phase 3: SZ-GOTO-LINE / editor key (not yet)
