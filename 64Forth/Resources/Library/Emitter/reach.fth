\ reach.fth — mark xts reachable from a root (emitter step 1)
\ Public domain.

ONLY FORTH DEFINITIONS
DECIMAL

8 CONSTANT CELL

: COLON-WORD?  ( xt -- flag )
  DUP ['] (DOCOL) = IF  DROP FALSE EXIT  THEN
  @  ['] (DOCOL) @  = ;

: DOVAR?   ( xt -- flag )  @  ['] (DOVAR)  @  = ;
: DOCON?   ( xt -- flag )  @  DOCON-ADDR      = ;
: DODOES?  ( xt -- flag )  @  ['] (DODOES) @  = ;

: BODY  ( xt -- addr )  8 + ;

512 CONSTANT REACH-MAX
CREATE REACH-XTS  REACH-MAX CELLS ALLOT
VARIABLE REACH-N
VARIABLE REACH-WORK

: REACH-CLEAR  ( -- )  0 REACH-N !  0 REACH-WORK ! ;

: MARKED?  ( xt -- flag )
  REACH-N @ 0 ?DO
    DUP I CELLS REACH-XTS + @ = IF  DROP TRUE UNLOOP EXIT  THEN
  LOOP DROP FALSE ;

: (MARK)  ( xt -- )
  DUP MARKED? IF  DROP EXIT  THEN
  REACH-N @ REACH-MAX >= IF  ." reach: full" CR DROP EXIT  THEN
  REACH-N @ CELLS REACH-XTS + !
  1 REACH-N +! ;

: SLIT-SKIP  ( addr -- addr' )   \ addr of length cell
  DUP @  SWAP 8 + +  7 + -8 AND ;

: SCAN-COLON  ( xt -- )
  BODY
  BEGIN
    DUP HERE U< 0= IF  ." scan: no EXIT" CR DROP EXIT  THEN
    DUP @
    DUP ['] EXIT = IF  (MARK) DROP EXIT  THEN
    DUP (MARK)
    DUP LIT-ADDR = IF  DROP 8 +
    ELSE DUP 0BRANCH-ADDR = OVER BRANCH-ADDR = OR
         OVER ['] (LOOP) = OR OVER ['] (+LOOP) = OR
         OVER ['] (?DO) = OR OVER ['] LEAVE = OR IF  DROP 8 +
    ELSE DUP SLIT-ADDR = IF  DROP 8 + SLIT-SKIP 8 -
    ELSE DROP
    THEN THEN THEN
    8 +
  AGAIN ;

: SCAN-ONE  ( xt -- )
  DUP COLON-WORD? IF  SCAN-COLON EXIT  THEN
  DROP ;

: REACH-FROM  ( xt -- )
  REACH-CLEAR
  (MARK)
  BEGIN
    REACH-WORK @ REACH-N @ <
  WHILE
    REACH-WORK @ CELLS REACH-XTS + @
    SCAN-ONE
    1 REACH-WORK +!
  REPEAT ;

: .REACHABLE  ( -- )
  CR ." reachable: " REACH-N @ . CR
  0 BEGIN
    DUP REACH-N @ <
  WHILE
    DUP CELLS REACH-XTS + @
    DUP NAME>STRING TYPE SPACE
    DUP COLON-WORD? IF ." colon" ELSE ." code" THEN CR
    DROP 1+
  REPEAT DROP ;
