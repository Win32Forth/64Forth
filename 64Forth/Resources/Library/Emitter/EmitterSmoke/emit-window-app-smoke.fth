\ emit-window-app-smoke.fth — EMIT-WINDOW-APP-TO parses the entry name.
\ Basename = word (W-GO → W-GO.app). Window title may still use
\ LAST-INCLUDED stem when a file was included after Emitter.
\
\ Canonical: Xcode Resources/Library/Emitter (Documents/64Forth/Library is a symlink).
\ Prefer:  FROMLIB FLOAD Emitter/EmitterSmoke/emit-window-app-smoke.fth
\ Agent:   …/64Forth --agent -f $HOME/Documents/64Forth/Library/Emitter/EmitterSmoke/emit-window-app-smoke.fth

ONLY FORTH DEFINITIONS DECIMAL
FROMLIB FLOAD Emitter/emitter.fth

\ Optional title stem (not the .app name).
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

S" /tmp" EMIT-WINDOW-APP-TO W-GO

: (SMOKE-CHECK)  ( -- )
  S" /tmp/W-GO.app/Contents/Resources/app.img" FILE-STATUS NIP IF
    ." FAIL: missing /tmp/W-GO.app (parsed name?)" CR ABORT
  THEN
  ." ok W-GO.app bundle" CR
  S\" EMIT_HEADLESS=1 /tmp/W-GO.app/Contents/MacOS/W-GO" SYSTEM IF
    ." FAIL: headless W-GO exited non-zero" CR ABORT
  THEN
  ." ok headless run" CR
  ;
(SMOKE-CHECK)
CR .( emit-window-app-smoke: OK ) CR
