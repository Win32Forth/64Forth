\ emit-app-smoke.fth — EMIT-APP-TO packages a tiny GRAPHICS entry as .app
\ Lives under Library/Emitter/EmitterSmoke.
\
\   /Applications/64Forth.app/Contents/MacOS/64Forth --agent \
\     -f $HOME/Documents/64Forth/Library/Emitter/EmitterSmoke/emit-app-smoke.fth

ONLY FORTH DEFINITIONS DECIMAL
FROMLIB FLOAD Emitter/emitter.fth

ALSO GRAPHICS
: T-GFX  ( -- )
  S" Emitter GFX" APP-NAME
  WINDOW
  CLS
  2 1 AT ." emit-app-ok"
  WINDOW-OFF
  ;
ONLY FORTH ALSO SYSVOC ALSO EMITTER

' T-GFX S" /tmp" EMIT-APP-TO

\ Checks must be colon words — interpret-time IF is not reliable here.
: (SMOKE-CHECK)  ( -- )
  S" /tmp/T-GFX.app/Contents/Resources/app.img" FILE-STATUS NIP IF
    ." FAIL: missing /tmp/T-GFX.app/Contents/Resources/app.img" CR ABORT
  THEN
  ." ok bundle image" CR
  S\" EMIT_HEADLESS=1 /tmp/T-GFX.app/Contents/MacOS/T-GFX" SYSTEM IF
    ." FAIL: headless T-GFX.app exited non-zero" CR ABORT
  THEN
  ." ok headless run" CR
  ;
(SMOKE-CHECK)
CR .( emit-app-smoke: OK ) CR
