\ debugger.fth — high-level ITC DEBUG hub + loader
\
\ Sole Autoload entry for Library/Debugger/. Loads sibling files in order and
\ owns the DEBUGGER vocabulary.
\
\ Phase 2: full Forth pause UI via DBG-PAUSE-INSTALL (default after Autoload).
\ Phase 3: Forth key policy (DBG-KEY-XT) — used when DBG-PAUSE-XT is 0 (asm UI).
\
\ Kernel: DBG-SHOW-XT, DBG-HL-XT, DBG-WHEEL-XT, DBG-PAUSE-XT, DBG-KEY-XT,
\ DBG-SYNC-OK, BREAK-TABLE, (BP-GO), DBG-*@, DBG-STEP-*, DBG-.SR, …

ANEW DEBUGGER_MODULE

ONLY FORTH DEFINITIONS
VOCABULARY DEBUGGER

\ Hub + siblings compile into DEBUGGER. ALSO SYSVOC so DBG-* kernel words resolve.
ONLY FORTH ALSO SYSVOC ALSO DEBUGGER DEFINITIONS

\ --- Pause / print policy ---------------------------------------------------

DEFER DBG-PRINT-TOKEN   \ ( -- )  print >> / I>> / LIT line for current pause
DEFER DBG-PRINT-STACKS  \ ( -- )  data + return stack columns
DEFER DBG-PAUSE         \ ( -- )  full pause UI: print, wait key, set step mode

: DBG-PRINT-TOKEN-NOP   ( -- )  ;
: DBG-PRINT-STACKS-NOP  ( -- )  ;
: DBG-PAUSE-NOP         ( -- )  ;

' DBG-PRINT-TOKEN-NOP   IS DBG-PRINT-TOKEN
' DBG-PRINT-STACKS-NOP  IS DBG-PRINT-STACKS
' DBG-PAUSE-NOP         IS DBG-PAUSE

\ --- Install helpers (editor / Hyper / pause / keys) ------------------------

: DBG-SET-SHOW  ( xt -- )  DBG-SHOW-XT ! ;
: DBG-SET-HL    ( xt -- )  DBG-HL-XT ! ;
: DBG-SET-WHEEL ( xt -- )  DBG-WHEEL-XT ! ;
: DBG-SET-PAUSE ( xt -- )  DBG-PAUSE-XT ! ;
: DBG-SET-KEY   ( xt -- )  DBG-KEY-XT ! ;

: DBG-CLEAR-HOOKS  ( -- )
  0 DBG-SHOW-XT !
  0 DBG-HL-XT !
  0 DBG-WHEEL-XT !
  0 DBG-PAUSE-XT !
  0 DBG-KEY-XT !
  ['] DBG-PRINT-TOKEN-NOP   IS DBG-PRINT-TOKEN
  ['] DBG-PRINT-STACKS-NOP  IS DBG-PRINT-STACKS
  ['] DBG-PAUSE-NOP         IS DBG-PAUSE
;

\ --- Sibling loads (extend here; Autoload only REQUIREs this file) ----------

FROMLIB REQUIRE Debugger/debug-bp.fth
FROMLIB REQUIRE Debugger/dbg-pause.fth
\ Editor/Hyper links (DEFERs) then token maps — no Editor required at load.
FROMLIB REQUIRE Debugger/dbg-ed.fth
FROMLIB REQUIRE Debugger/dbg-map.fth

\ Phase 2 — full Forth pause UI (print / EKEY / step). Revert: 0 DBG-PAUSE-XT !
\ Phase 3 — also arm key decode for asm fallback when PAUSE-XT is cleared.
DBG-PAUSE-INSTALL
DBG-KEY-INSTALL

\ Session: FORTH + DEBUGGER; define into FORTH by default after load.
ONLY FORTH ALSO DEBUGGER
FORTH-WORDLIST SET-CURRENT
