\ Emitter/test.fth — build+run ladder (empty, S" hi" TYPE, IF/ELSE).
\ Canonical copy lives under Resources/Library/Emitter; sync into
\ Documents/64Forth/Library/Emitter after edits (RESTORE-SHIPPED stomps Library).
\ Public domain.
\
\   FROMLIB FLOAD Emitter/test.fth
\ Or via agent (outside Library):
\   /Applications/64Forth.app/Contents/MacOS/64Forth --agent \
\     -f $HOME/Documents/64Forth/EmitterSmoke/agent-smoke.fth

ONLY FORTH DEFINITIONS DECIMAL
FROMLIB FLOAD Emitter/emitter.fth
\ emitter.fth leaves ALSO EMITTER on the search order.

: T-EMPTY ;
: T-HI    S" hi" TYPE ;
: MAIN2   1 0= IF  2 THEN 3 . ;
: MAIN4   1 IF 2 ELSE 3 THEN . ;

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

CR .( DONE ) CR
