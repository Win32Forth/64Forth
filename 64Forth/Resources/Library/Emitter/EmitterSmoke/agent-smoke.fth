\ agent-smoke.fth — lives under Library/Emitter/EmitterSmoke (shipped with Emitter)
\ Mirrors Emitter/test.fth ladder: empty, hi, MAIN2, MAIN4, VALUE, CREATE, DO.
\ Public domain.
\
\   /Applications/64Forth.app/Contents/MacOS/64Forth --agent \
\     -f $HOME/Documents/64Forth/Library/Emitter/EmitterSmoke/agent-smoke.fth

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
: T-DO   0 3 0 DO I + LOOP . ;

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

CR .( vocabulary check ) CR
: (GONE?)  ( c-addr u -- flag )  \ true if absent from FORTH
  FORTH-WORDLIST SEARCH-WORDLIST IF DROP FALSE ELSE TRUE THEN ;
: (HERE?)  ( c-addr u -- flag )  \ true if present in EMITTER
  ['] EMITTER 2 CELLS + SEARCH-WORDLIST IF DROP TRUE ELSE FALSE THEN ;
: .VOC-CHECK  ( -- )
  S" TGT-BUILD" (GONE?) 0= IF ." FAIL: TGT-BUILD still in FORTH" CR THEN
  S" ALLOCATE-EXEC" (GONE?) 0= IF ." FAIL: ALLOCATE-EXEC still in FORTH" CR THEN
  S" TGT-BUILD" (HERE?) 0= IF ." FAIL: TGT-BUILD missing from EMITTER" CR THEN
  S" ALLOCATE-EXEC" (HERE?) 0= IF ." FAIL: ALLOCATE-EXEC missing from EMITTER" CR THEN
  S" DATA-WORD?" (HERE?) 0= IF ." FAIL: DATA-WORD? missing from EMITTER" CR THEN
  ." vocab ok" CR ;
.VOC-CHECK

CR .( DONE ) CR
