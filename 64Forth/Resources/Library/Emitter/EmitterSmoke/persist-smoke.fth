\ persist-smoke.fth — Phase 2b.1: SAVE-IMAGE / LOAD-IMAGE round-trip.
\ Lives under Library/Emitter/EmitterSmoke (shipped with Emitter).
\ Public domain.
\
\ Canonical: Xcode Resources/Library/Emitter (Documents/64Forth/Library is a symlink).
\ Prefer:  FROMLIB FLOAD Emitter/EmitterSmoke/persist-smoke.fth
\ Agent:   …/64Forth --agent -f $HOME/Documents/64Forth/Library/Emitter/EmitterSmoke/persist-smoke.fth

ONLY FORTH DEFINITIONS DECIMAL
FROMLIB FLOAD Emitter/emitter.fth

\ Helpers before ALSO GRAPHICS (shadows TYPE/EMIT/CR/.).
CREATE IMG-PATH 256 ALLOT
S" /tmp/64emit-persist-smoke.img" IMG-PATH PLACE

: CHECK-MAGIC-RELOCS  ( -- )
  HOST-RELOC-N @ 0= IF
    ." FAIL: expected HOST-RELOC-N > 0" CR ABORT
  THEN
  HOST-RELOC-N @ 0 DO
    I CELLS HOST-RELOC-OFF + @ @
    48 RSHIFT $C0DE <> IF
      ." FAIL: reloc .quad not MAGIC before bind" CR ABORT
    THEN
  LOOP
  ." magic-relocs ok n=" HOST-RELOC-N @ U. CR ;

: CHECK-BOUND-RELOCS  ( -- )
  HOST-RELOC-N @ 0 DO
    I CELLS HOST-RELOC-OFF + @ @
    I CELLS HOST-RELOC-SLOT + @ CELLS HOST-APP-VA + @ <> IF
      ." FAIL: reloc not bound to HOST-APP-VA" CR ABORT
    THEN
  LOOP
  ." bound-relocs ok n=" HOST-RELOC-N @ U. CR ;

ALSO GRAPHICS

: T-GFX  ( -- )
  S" Emitter Persist" APP-NAME
  WINDOW
  CLS
  2 1 AT ." persist-ok"
  WINDOW-OFF
  ;

ONLY FORTH ALSO SYSVOC ALSO EMITTER

CR .( === unbound standalone build === ) CR
/EMIT-STANDALONE
/EMIT-UNBOUND
['] T-GFX TGT-BUILD
CHECK-MAGIC-RELOCS

CR .( === SAVE-IMAGE === ) CR
['] T-GFX IMG-PATH COUNT SAVE-IMAGE

CR .( === TGT-CLOSE + LOAD-IMAGE === ) CR
TGT-CLOSE
IMG-PATH COUNT LOAD-IMAGE
CHECK-MAGIC-RELOCS

CR .( === bind + TGT-RUN-LOADED === ) CR
TGT-RUN-LOADED
CHECK-BOUND-RELOCS

CR .( T-GFX returned via LOAD-IMAGE ) CR
CR .( DONE persist-smoke ) CR
