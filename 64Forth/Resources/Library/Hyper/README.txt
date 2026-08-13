64Forth Hyper / VIEW (Phases 0–5 + header VIEW — v1.0.x)
===================================================

Load
----
  FROMLIB FLOAD Editor/SZ-EDITOR.fth   \ required for VIEW
  FROMLIB FLOAD Hyper/hyper.fth

  Often already loaded via AutoLoad (with HYPER-REINDEX on startup).

Vocabulary
----------
  Internals / indexer live in HYPER-VOC. Public commands are defined once
  in FORTH while the search order includes HYPER-VOC:

    ONLY FORTH DEFINITIONS ALSO HYPER-VOC
    : VIEW … (HYPER-FIND) … ;   \ name → FORTH, callees → HYPER-VOC

  so ONLY FORTH still finds VIEW / LOCATE / SEE / HYPER-NEXT / …

  HYPER-VOC WORDS              list Hyper implementation words
  ORDER                        show search order

Commands (from HYPER-VOC unless noted)
-------------------------------------
  LOCATE <name>     Print defining path:line  (shows [n/m] if multiple hits)
  VIEW <name>       Open file in SZ-EDITOR at that line
  SEE <name>        VIEW if SZ-EDITOR loaded, else decompile (kernel SEE)
  SEE-SOURCE        Alias of VIEW
  HYPER-NEXT        Visit history forward, else next multi-hit   (Cmd-PgDn)
  HYPER-PREV        Visit history back, else previous multi-hit  (Cmd-PgUp)
  HYPER-REINDEX     Rebuild Config/HYPER.NDX, reload (FORTH)
  HYPER-RELOAD      Re-read index (Config/HYPER.NDX, else cwd HYPER.NDX)
  .HYPER            Status (includes visit n/m when history non-empty)
  HYPER-HELP        Short help
  MIN-HYPER-NOISE   ON quiet reindex  e.g.  HYPER-VOC MIN-HYPER-NOISE ON FORTH

  Visit history     Cmd-click / Cmd-E / VIEW build a list of path+line
                    (up to 32). Cmd-PgUp/PgDn move in that list. A new
                    visit while mid-list inserts after the current entry
                    and keeps later entries (context is not discarded).

  Header VIEW       FLOAD/INCLUDE stamps file-id + line into each new word's
                    FLAGS (VIEW-FILE# VIEW-LINE VIEW-PATH). LOCATE/VIEW always
                    search dictionary VIEW first (search order, then WORDLISTS
                    via SEARCH-WORDLIST — not a full WORDS walk), then HYPER.NDX
                    for CODE words, assembly labels, multi-hit.
                    HYPER-REINDEX only rebuilds NDX — it does not rewrite headers.

  Cmd-E             VIEW word under caret (console or SZ-EDITOR)
  Cmd-click         VIEW word under click (console or SZ-EDITOR; same as Cmd-E)
  Cmd-PgDn          history forward, else next hit for current name
  Cmd-PgUp          history back, else previous hit
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
    → BOOT_WORD → CodeLabel in Library/Sources/forth.s
    → CREATE-FILE Config/HYPER.NDX, then HYPER-RELOAD
  Quiet:  HYPER-VOC MIN-HYPER-NOISE ON FORTH  then  HYPER-REINDEX

  Limits vs tools/build_hyper_index.py (optional polish):
    - TYPE 0 only in Forth (no TYPE 1/2/4 yet)
    - Kernel .s/.inc: TYPE 0 only on .ascii / .asciz lines

Phase status
------------
  0–1  format, offline builder, NDX          done
  2    LOCATE / VIEW                         done
  3    editor open-at-line                   done
  3a   in-app HYPER-REINDEX                  done
  4    CFG SPECS + HYPER.SPECS host list     done
  4a   mouse click in SZ-EDITOR              done
  5    multi-hit, ⌘PgUp/Dn, ⌘E, SEE→VIEW    done

Editor (Phase 4a+)
------------------
  Mouse click in the facility/SZ-EDITOR window moves the buffer cursor
  to the clicked cell (text body only; chrome ignored). Wheel scrolls
  with caret on-row; see Library/Editor/SZ-EDITOR-README.txt.

Offline rebuild (full index, CI / ship Config/)
-----------------------------------------------
  python3 tools/build_hyper_index.py
  → 64Forth/Resources/Config/HYPER.NDX

Path resolution (host)
----------------------
  Config/…              → Resources/Config
  Library/…             → Resources/Library (bundle)
  Library/Sources/…     → shipped kernel sources (release VIEW of assembly)
  Kernel/…              → Library/Sources/… if present, else developer tree

  Kernel sources are copied into Library/Sources on each Xcode build so a
  DMG can VIEW forth.s without HYPER_ROOT / a checkout.

Files
-----
  hyper.fth         LOCATE / VIEW / load (HYPER-VOC)
  hyper-index.fth   HX-* + HX-DO-REINDEX; HYPER-REINDEX in FORTH
