\ timer-sa-smoke.fth — stand-alone MS@ / 10TH-ELAPSED must advance.
\ Regression for tetra WAIT-DROP (SPACE worked; gravity timer did not
\ because SA NOP'd MS@'s bl _gettimeofday).
\
\   /Applications/64Forth.app/Contents/MacOS/64Forth --agent \
\     -f $HOME/Documents/64Forth/Library/Emitter/EmitterSmoke/timer-sa-smoke.fth

ONLY FORTH DEFINITIONS DECIMAL
FROMLIB FLOAD Emitter/emitter.fth

ALSO GRAPHICS
\ Spin until two tenths elapse (MS@ + (APP-PUMP)). No WINDOW needed.
: T-TIMER  ( -- )
  TIME-RESET
  BEGIN  10TH-ELAPSED 2 >  UNTIL
  42 .
  ;
ONLY FORTH ALSO SYSVOC ALSO EMITTER

' T-TIMER S" /tmp" EMIT-APP-TO

: (SMOKE-CHECK)  ( -- )
  S" /tmp/T-TIMER.app/Contents/Resources/app.img" FILE-STATUS NIP IF
    ." FAIL: missing /tmp/T-TIMER.app image" CR ABORT
  THEN
  ." ok bundle image" CR
  S\" EMIT_HEADLESS=1 /tmp/T-TIMER.app/Contents/MacOS/T-TIMER" SYSTEM IF
    ." FAIL: headless T-TIMER.app exited non-zero (timer stuck?)" CR ABORT
  THEN
  ." ok headless timer run" CR
  ;
(SMOKE-CHECK)
CR .( timer-sa-smoke: OK ) CR
