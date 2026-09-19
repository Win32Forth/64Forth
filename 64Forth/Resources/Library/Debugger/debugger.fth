\ debugger.fth — high-level ITC DEBUG hub + loader
\
\ Sole Autoload entry for Library/Debugger/. Loads sibling files in order and
\ owns the DEBUGGER vocabulary.
\
\ Phase 3: Forth key policy (DBG-KEY-XT) — short call_xt; asm prints/waits/applies.
\ Phase 2 full pause UI remains opt-in only (DBG-PAUSE-INSTALL; known crash).
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

\ Phase 3 — Forth maps keys; asm pause UI applies modes.
DBG-KEY-INSTALL
\ Phase 2 full UI — not armed (DBG-PAUSE-INSTALL still unsafe).

\ Session: FORTH + DEBUGGER; define into FORTH by default after load.
ONLY FORTH ALSO DEBUGGER
FORTH-WORDLIST SET-CURRENT
