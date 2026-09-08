\ Emitter/test.fth — build+run ladder (empty, TYPE, IF/ELSE, VALUE, CREATE, DO).
\ Canonical tree: XCodeProjects/64Forth/64Forth/Resources/Library/Emitter
\ Documents/64Forth/Library is a symlink to that tree — edit either path.
\ Public domain.
\
\ Interactive (preferred):
\   FROMLIB FLOAD Emitter/test.fth
\ Smokes (same tree via FROMLIB or the Documents symlink):
\   FROMLIB FLOAD Emitter/EmitterSmoke/agent-smoke.fth
\   FROMLIB FLOAD Emitter/EmitterSmoke/gfx-smoke.fth
\   FROMLIB FLOAD Emitter/EmitterSmoke/tetra-smoke.fth
\   FROMLIB FLOAD Emitter/EmitterSmoke/emit-app-smoke.fth
\   FROMLIB FLOAD Emitter/EmitterSmoke/emit-window-app-smoke.fth
\ Agent (path through the symlink — same files as the project):
\   …/64Forth --agent -f $HOME/Documents/64Forth/Library/Emitter/EmitterSmoke/agent-smoke.fth
\ GUI tetra:
\   FROMLIB FLOAD Emitter/EmitterSmoke/tetra-gui-smoke.fth   then  EMIT-TETRA


ONLY FORTH DEFINITIONS DECIMAL
FROMLIB FLOAD Emitter/emitter.fth
\ emitter.fth leaves ALSO EMITTER on the search order.

: T-EMPTY ;
: T-HI    S" hi" TYPE ;
: MAIN2   1 0= IF  2 THEN 3 . ;
: MAIN4   1 IF 2 ELSE 3 THEN . ;

0 VALUE V1
CREATE C1  3 CELLS ALLOT
: T-VAL  7 TO V1  V1 . ;
: T-CR   1 C1 !  C1 @ . ;
: T-DO   0 3 0 DO I + LOOP . ;   \ expect 3

: TRY-RUN  ( xt -- )
  DUP TGT-BUILD  TGT-RUN ;

CR .( === empty colon === ) CR
['] T-EMPTY TRY-RUN
.( empty ok ) CR

CR .( === S" hi" TYPE === ) CR
['] T-HI TRY-RUN
CR .( hi returned ) CR

CR .( === MAIN2: 1 0= IF 2 THEN 3 .  expect 3 === ) CR
['] MAIN2 TRY-RUN
CR .( MAIN2 returned ) CR

CR .( === MAIN4: 1 IF 2 ELSE 3 THEN .  expect 2 === ) CR
['] MAIN4 TRY-RUN
CR .( MAIN4 returned ) CR

CR .( === T-VAL: TO VALUE  expect 7 === ) CR
['] T-VAL TRY-RUN
CR .( T-VAL returned ) CR

CR .( === T-CR: CREATE cell  expect 1 === ) CR
['] T-CR TRY-RUN
CR .( T-CR returned ) CR

CR .( === T-DO: DO LOOP  expect 3 === ) CR
['] T-DO TRY-RUN
CR .( T-DO returned ) CR

CR .( DONE ) CR
