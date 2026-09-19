64Forth Library/Debugger
========================

High-level ITC DEBUG support that does not belong in the kernel cold blob
or under Hyper.

  debugger.fth   Sole entry: VOCABULARY DEBUGGER, hub DEFERs / DBG-SET-*,
                 REQUIREs siblings; arms phase-3 key policy.
  debug-bp.fth   BREAK / UNBREAK / .BREAKS / BPGO
  dbg-pause.fth  Key decode (DBG-PAUSE-DECODE) + optional full pause UI

AutoLoad (before Editor) — one line only:

  FROMLIB REQUIRE Debugger/debugger.fth

Kernel owns when to pause, print/cursor/wait (asm), and thin helpers.
Forth owns key→mode mapping when DBG-KEY-XT is set (phase 3 default).

  DBG-KEY-XT = DBG-PAUSE-DECODE   (default after Autoload)
  DBG-PAUSE-XT = 0                (asm print/wait; full Forth UI not armed)

Modes from DBG-PAUSE-DECODE (u -- mode):
  0 ignore  1 over  2 into  3 out  4 go  5 abort  6 wheel  7 help

Opt-in / out:
  DBG-KEY-INSTALL / DBG-KEY-UNINSTALL
  DBG-PAUSE-INSTALL   \ full Forth UI — known crash; do not use yet
  0 DBG-PAUSE-XT !    \ ensure asm pause UI

Hyper still installs DBG-SHOW-XT / DBG-HL-XT for VIEW + highlight.
Later: move dbg-map.fth here; fix full DBG-PAUSE-UI.
