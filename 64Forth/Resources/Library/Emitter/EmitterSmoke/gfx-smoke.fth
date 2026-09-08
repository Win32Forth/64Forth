\ gfx-smoke.fth — Emitter + GRAPHICS mini (AT/EMIT path via WINDOW).
\ Lives under Library/Emitter/EmitterSmoke (shipped with Emitter).
\ Public domain.
\
\ Opens the GRAPHICS window when not in agent mode. Under --agent,
\ (APP-OPEN) returns -1 (no window) but sliced CODE still veneers to the
\ host — enough to prove the emit path for (APP-*).
\
\
\ Interactive (real window flash):
\   FROMLIB FLOAD Emitter/emitter.fth
\   ALSO GRAPHICS
\   S" …/Library/Emitter/EmitterSmoke/gfx-smoke.fth" INCLUDED   \ or paste T-GFX + TRY-RUN
\ Canonical: Xcode Resources/Library/Emitter (Documents/64Forth/Library is a symlink).
\ Prefer:  FROMLIB FLOAD Emitter/EmitterSmoke/gfx-smoke.fth
\ Agent:   …/64Forth --agent -f $HOME/Documents/64Forth/Library/Emitter/EmitterSmoke/gfx-smoke.fth

ONLY FORTH DEFINITIONS DECIMAL
FROMLIB FLOAD Emitter/emitter.fth
\ Define helpers BEFORE ALSO GRAPHICS (GRAPHICS shadows TYPE/EMIT/CR/.).

: CHECK-HOST-SLOTS  ( -- )
  \ After TGT-BUILD, HOST-BIND has filled .quads with live host VAs.
  HOST-RELOC-N @ 0= IF
    ." FAIL: expected HOST-RELOC-N > 0 after TGT-BUILD" CR ABORT
  THEN
  HOST-RELOC-N @ 0 DO
    I CELLS HOST-RELOC-OFF + @ @
    I CELLS HOST-RELOC-SLOT + @ CELLS HOST-APP-VA + @ <> IF
      ." FAIL: reloc not bound to HOST-APP-VA" CR ABORT
    THEN
  LOOP
  ." host-slots ok n=" HOST-RELOC-N @ U. CR ;

: TRY-RUN  ( xt -- )
  DUP TGT-BUILD  CHECK-HOST-SLOTS  TGT-RUN ;

ALSO GRAPHICS

: T-GFX  ( -- )
  S" Emitter GFX" APP-NAME
  WINDOW
  CLS
  2 1 AT ." emitter-gfx"
  WINDOW-OFF
  ;

CR .( === GRAPHICS mini: APP-NAME WINDOW CLS AT ." …" WINDOW-OFF === ) CR
['] T-GFX TRY-RUN
CR .( T-GFX returned ) CR

CR .( === reach sample: expect G-* import and APP-* prim === ) CR
.REACHABLE

CR .( DONE gfx-smoke ) CR
