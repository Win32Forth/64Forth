\ emit-window-app-smoke.fth — EMIT-WINDOW-APP wraps xt with APP-NAME/WINDOW.
\ Title stem comes from LAST-INCLUDED — load the app .fth *after* Emitter.
\   WinAppSmoke.fth → WINAPPSMOKE.app
\
\   64Forth --agent -f …/EmitterSmoke/emit-window-app-smoke.fth

ONLY FORTH DEFINITIONS DECIMAL
FROMLIB FLOAD Emitter/emitter.fth

\ Seed LAST-INCLUDED after Emitter so the stem is the app file, not app.fth.
S" /tmp/WinAppSmoke.fth" W/O CREATE-FILE THROW
DUP S" \ emit-window-app stem marker" ROT WRITE-FILE THROW
CLOSE-FILE DROP
S" /tmp/WinAppSmoke.fth" INCLUDED

: (CK-LAST)  ( -- )
  LAST-INCLUDED DUP 0= IF
    2DROP ." FAIL: LAST-INCLUDED empty after INCLUDE" CR ABORT
  THEN
  ." ok LAST-INCLUDED " TYPE CR
  ;
(CK-LAST)

ALSO GRAPHICS
\ Body assumes window already open (EMIT-WINDOW-APP supplies WINDOW).
: W-GO  ( -- )
  CLS
  2 1 AT ." win-app-ok"
  ;
ONLY FORTH ALSO SYSVOC ALSO EMITTER

' W-GO S" /tmp" EMIT-WINDOW-APP-TO

: (SMOKE-CHECK)  ( -- )
  S" /tmp/WINAPPSMOKE.app/Contents/Resources/app.img" FILE-STATUS NIP IF
    ." FAIL: missing /tmp/WINAPPSMOKE.app (stem title?)" CR ABORT
  THEN
  ." ok WINAPPSMOKE.app bundle" CR
  S\" EMIT_HEADLESS=1 /tmp/WINAPPSMOKE.app/Contents/MacOS/WINAPPSMOKE" SYSTEM IF
    ." FAIL: headless WINAPPSMOKE exited non-zero" CR ABORT
  THEN
  ." ok headless run" CR
  ;
(SMOKE-CHECK)
CR .( emit-window-app-smoke: OK ) CR
