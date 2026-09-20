64Forth Library/Debugger
========================

High-level ITC DEBUG support that does not belong in the kernel cold blob
or under Hyper.

  debugger.fth   Sole Autoload entry: VOCABULARY DEBUGGER, hub DEFERs /
                 DBG-SET-*, REQUIREs siblings; arms phase-2/3.
  debug-bp.fth   BREAK / UNBREAK / .BREAKS / BPGO
  dbg-pause.fth  Key decode (DBG-PAUSE-DECODE) + full Forth pause UI
  dbg-ed.fth     Shared DBG-CMD/DBG-PLACE + DBG-HL-RUN; deferred DBG-ED-*
                 to Editor SZ-*; DBG-ED-INSTALL binds when Editor exists
  dbg-map.fth    Debug-time colon token maps; uses DBG-ED-* only
                 (loaded inside debugger.fth — not after Hyper)
                 (no Editor/Hyper required at load)

AutoLoad:

  FROMLIB REQUIRE Debugger/debugger.fth   \ loads bp, pause, ed links, maps
  … Editor, Emitter, Hyper …
  ALSO DEBUGGER  DBG-ED-INSTALL DROP      \ fill SZ-* / Hyper HL (autoload.fth)

Kernel owns when to pause and thin helpers (_debug_call_xt nest RSP).
Forth owns pause print/EKEY/step (DBG-PAUSE-XT) and key→mode (DBG-KEY-XT).

  DBG-PAUSE-XT = DBG-PAUSE-UI     (default after Autoload)
  DBG-KEY-XT   = DBG-PAUSE-DECODE (asm fallback when PAUSE-XT is 0)

Shared HL: DBG-HL-RUN (Debugger DEFER). DBG-ED-INSTALL sets it to
DBG-MAP-HL when maps+editor are live, else SZ-HIGHLIGHT-NAME, and
mirrors that xt into Hyper's HYPER-HL-XT for DBG-HIGHLIGHT-NAME.

Install / revert:
  DBG-PAUSE-INSTALL / DBG-KEY-INSTALL
  DBG-KEY-UNINSTALL
  0 DBG-PAUSE-XT !    \ back to asm pause UI (phase-3 keys still apply)
  DBG-ED-INSTALL      \ (re)bind Editor after SZ-EDITOR / Hyper load
