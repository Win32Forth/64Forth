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

AutoLoad (v1.5.2+):

  FROMLIB REQUIRE Debugger/debugger.fth   \ loads bp, pause, ed links, maps
  … Emitter, Hyper …                      \ no in-app SZ-EDITOR
  \ DBG-ED-INSTALL skipped — console-only DEBUG

Kernel owns when to pause and thin helpers (_debug_call_xt nest RSP).
Forth owns pause print/EKEY/step (DBG-PAUSE-XT) and key→mode (DBG-KEY-XT).

  DBG-PAUSE-XT = DBG-PAUSE-UI     (default after Autoload)
  DBG-KEY-XT   = DBG-PAUSE-DECODE (asm fallback when PAUSE-XT is 0)

Shared HL: DBG-HL-RUN (Debugger DEFER). DBG-ED-INSTALL would bind
map/editor HL when a host editor is present; Autoload no longer calls it.

Console-only (current default):
  DBG-PAUSE-UI does not call DBG-VIEW-UPDATE.
  Hyper leaves DBG-SHOW-XT / DBG-HL-XT at 0.
  host_debug_paint is a no-op; Autoload skips DBG-ED-INSTALL.
  DEBUG / DBG step only in the Forth console.
  Editing is external 64Edit (https://github.com/Win32Forth/64Edit).
  VIEW opens 64Edit in view mode at path:line; EDIT opens edit mode.

Install / revert:
  DBG-PAUSE-INSTALL / DBG-KEY-INSTALL
  DBG-KEY-UNINSTALL
  0 DBG-PAUSE-XT !    \ back to asm pause UI (phase-3 keys still apply)
  DBG-ED-INSTALL      \ (re)bind Editor after SZ-EDITOR / Hyper load
