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
\ INCLUDED (not REQUIRE): ANEW DEBUGGER_MODULE forgets sibling words but the
\ include registry would still skip REQUIRE — always re-read on hub reload.

FROMLIB S" Debugger/debug-bp.fth" INCLUDED
FROMLIB S" Debugger/dbg-pause.fth" INCLUDED
\ Editor/Hyper links (DEFERs) then token maps — no Editor required at load.
FROMLIB S" Debugger/dbg-ed.fth" INCLUDED
FROMLIB S" Debugger/dbg-map.fth" INCLUDED

\ Phase 2 — full Forth pause UI (print / EKEY / step). Revert: 0 DBG-PAUSE-XT !
\ Phase 3 — also arm key decode for asm fallback when PAUSE-XT is cleared.
DBG-PAUSE-INSTALL
DBG-KEY-INSTALL

\ Bind file-backed dbg-map → DBG-HOST-SPAN for 64Edit (no SZ-EDITOR needed).
\ Sets DBG-HL-XT so asm pause fallback also publishes spans before paint.
\ DBG-ED-INSTALL ends with ONLY FORTH ALSO DEBUGGER — do not PREVIOUS here
\ or the (DBG>FORTH) ticks below cannot find NOBREAKS / BREAK / …
\ Must be a colon word: interpret-time IF/THEN leaves TRUE (−1) on the stack.
: (DBG-HUB-ARM-HL)  ( -- )
  DBG-MAP-BIND IF  DBG-ED-HL-XT DBG-SET-HL  THEN ;
(DBG-HUB-ARM-HL)

\ User entry points into FORTH so ONLY FORTH (Autoload / Hayes) still finds them.
\ DEBUGGER vocabulary remains for hub helpers; ALSO DEBUGGER (or DEBUGGER after ALSO).
ALSO SYSVOC
: (DBG>FORTH)  ( xt -- )  ['] DEBUGGER VOC-WID FORTH-WORDLIST XT>WL-FROM ;
' NOBREAKS   (DBG>FORTH)
' BREAK-XT   (DBG>FORTH)
' UNBREAK-XT (DBG>FORTH)
' BREAK      (DBG>FORTH)
' UNBREAK    (DBG>FORTH)
' BREAK-HAS? (DBG>FORTH)
' TOGGLE-BREAK-XT (DBG>FORTH)
' TOGGLE-BREAK (DBG>FORTH)
' DISABLE-BREAK-XT (DBG>FORTH)
' ENABLE-BREAK-XT (DBG>FORTH)
' DISABLE-BREAK (DBG>FORTH)
' ENABLE-BREAK (DBG>FORTH)
' .BREAKS    (DBG>FORTH)
' BPGO-XT    (DBG>FORTH)
' BPGO       (DBG>FORTH)
PREVIOUS

\ Leave ANS-style order for Autoload to finalize (ONLY FORTH ALSO DEFINITIONS).
ONLY FORTH ALSO DEFINITIONS
