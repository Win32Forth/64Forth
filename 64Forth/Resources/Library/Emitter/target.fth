\ target.fth — emitter step 2
\ Requires reach.fth
\ Public domain.

ONLY FORTH DEFINITIONS DECIMAL

DEFER TGT-RELOC

: TGT-RELOC-NONE  ( -- )  ;
' TGT-RELOC-NONE  IS TGT-RELOC

VARIABLE TGT
VARIABLE TGT-ORG
VARIABLE TGT-DP
VARIABLE TGT-LIMIT
VARIABLE TGT-END
VARIABLE TGT-ALLOC    \ length given to ALLOCATE-EXEC / FREE-EXEC

: TGT-HERE  TGT-DP @ ;

: TGT-ALLOT  ( n -- )
  TGT-DP @ + DUP TGT-LIMIT @ U> IF
    ." tgt: overflow" CR ABORT
  THEN TGT-DP ! ;

: TGT,   TGT-HERE !  8 TGT-ALLOT ;
: TGT-C, TGT-HERE C!  1 TGT-ALLOT ;
: TGT-ALIGN  TGT-HERE 7 + -8 AND TGT-DP ! ;

: TGT-CLOSE  ( -- )
  TGT @ IF
    TGT @ TGT-ALLOC @ FREE-EXEC DROP
  THEN
  0 TGT !  0 TGT-ORG !  0 TGT-DP !  0 TGT-LIMIT !  0 TGT-END !
  0 TGT-ALLOC ! ;
  
: TGT-OPEN  ( u -- )
  TGT-CLOSE
  DUP TGT-ALLOC !
  DUP ALLOCATE-EXEC IF  DROP ." ALLOCATE-EXEC failed" CR ABORT  THEN
  DUP TGT !
  DUP TGT-ORG !
  DUP TGT-DP !
  + TGT-LIMIT ! ;

CREATE TGT-OLD REACH-MAX CELLS ALLOT
CREATE TGT-NEW REACH-MAX CELLS ALLOT
VARIABLE TGT-MAPN

: MAP-FIND  {: old | i -- new :}
  0 TO i
  BEGIN  i TGT-MAPN @ <  WHILE
    i CELLS TGT-OLD + @  old = IF
      i CELLS TGT-NEW + @ EXIT
    THEN
    i 1+ TO i
  REPEAT
  0 ;

: .MAP  {: | i -- :}
  CR ." map " TGT-MAPN @ . CR
  0 TO i
  BEGIN  i TGT-MAPN @ <  WHILE
    i . SPACE
    i CELLS TGT-OLD + @ DUP NAME>STRING TYPE SPACE U. SPACE
    i CELLS TGT-NEW + @ U. CR
    i 1+ TO i
  REPEAT ;

: MAP!  ( old new -- )
  TGT-MAPN @ CELLS TGT-NEW + !
  TGT-MAPN @ CELLS TGT-OLD + !
  1 TGT-MAPN +! ;

: PRIM-SPAN  ( xt -- code u )
  CODE-BOUNDS 2DUP SWAP -  NIP ;

: COLON-SPAN  ( xt -- addr u )
  BODY DUP
  BEGIN
    DUP HERE U< 0= IF SWAP - EXIT THEN
    DUP @ DUP ['] EXIT = IF DROP 8 + SWAP - EXIT THEN
    DUP LIT-ADDR = OVER 0BRANCH-ADDR = OR OVER BRANCH-ADDR = OR
    OVER ['] (LOOP) = OR OVER ['] (+LOOP) = OR
    OVER ['] (?DO) = OR OVER ['] LEAVE = OR IF DROP 8 +
    ELSE DUP SLIT-ADDR = IF DROP 8 + SLIT-SKIP
    ELSE DROP 8 + THEN THEN
  AGAIN ;

: RESERVE-PRIM  {: xt | new u -- :}
  TGT-HERE TO new
  xt PRIM-SPAN NIP 7 + -8 AND 8 + TO u
  xt ['] (NEXT) <> IF  u 4 + TO u  THEN
  u TGT-ALLOT
  xt new MAP! ;

: RESERVE-COLON  {: xt | new u -- :}
  TGT-HERE TO new
  xt COLON-SPAN NIP 8 + TO u
  u TGT-ALLOT
  xt new MAP! ;
  
: COPY-BYTES  ( src u -- )
  0 ?DO DUP I + C@ TGT-C, LOOP DROP TGT-ALIGN ;

: WRITE-PRIM  ( xt -- )
  DUP NAME>STRING TYPE SPACE ." prim" CR
  DUP MAP-FIND DUP 0= IF ." no map" CR ABORT THEN
  DUP TGT-DP !
  DUP 8 + SWAP !
  8 TGT-ALLOT
  PRIM-SPAN COPY-BYTES ;

: MAP-CELL  ( old -- )
  DUP MAP-FIND ?DUP IF  NIP TGT,  ELSE
    ." unmapped " NAME>STRING TYPE CR ABORT
  THEN ;

: WRITE-BODY  ( xt -- )
  BODY
  BEGIN
    DUP @
    DUP ['] EXIT = IF MAP-CELL DROP EXIT THEN
    DUP LIT-ADDR = IF
      MAP-CELL 8 + DUP @ TGT, 8 +
    ELSE DUP 0BRANCH-ADDR = OVER BRANCH-ADDR = OR
         OVER ['] (LOOP) = OR OVER ['] (+LOOP) = OR
         OVER ['] (?DO) = OR OVER ['] LEAVE = OR IF
      MAP-CELL 8 + DUP @ TGT, 8 +
    ELSE DUP SLIT-ADDR = IF
      MAP-CELL               \ emit new (S")
      8 + DUP                \ addr of len
      DUP @ TGT,             \ copy len
      DUP 8 + OVER @ COPY-BYTES
      SLIT-SKIP
    ELSE
      MAP-CELL 8 +
    THEN THEN THEN
  AGAIN ;

: WRITE-COLON  ( xt -- )
  DUP NAME>STRING TYPE SPACE ." colon" CR
  DUP MAP-FIND DUP 0= IF ." no map" CR ABORT THEN
  TGT-DP !
  ['] (DOCOL) MAP-FIND DUP 0= IF ." no DOCOL map" CR ABORT THEN
  @ TGT,
  WRITE-BODY ;

: TGT-RESERVE  {: | RI -- :}
  0 TO RI
  0 TGT-MAPN !
  ." reserve n=" REACH-N @ . CR
  BEGIN  RI REACH-N @ <  WHILE
    RI . SPACE
    RI CELLS REACH-XTS + @
    DUP NAME>STRING TYPE SPACE
    DUP COLON-WORD? IF  ." colon" CR RESERVE-COLON
    ELSE                ." prim"  CR RESERVE-PRIM
    THEN
    RI 1+ TO RI
  REPEAT
  ." maps=" TGT-MAPN @ . CR
  TGT-HERE TGT-END ! ;

: TGT-WRITE  {: | RI -- :}
  0 TO RI
  BEGIN  RI REACH-N @ <  WHILE
    RI CELLS REACH-XTS + @
    DUP COLON-WORD? 0= IF  WRITE-PRIM ELSE DROP THEN
    RI 1+ TO RI
  REPEAT
  0 TO RI
  BEGIN  RI REACH-N @ <  WHILE
    RI CELLS REACH-XTS + @
    DUP COLON-WORD? IF  WRITE-COLON ELSE DROP THEN
    RI 1+ TO RI
  REPEAT ;

: TGT-SIZE  ( -- u )  TGT-END @ TGT-ORG @ - ;

\ --- step 3a: stitch ITC dispatch -----------------------------------------

: ARM-B,  ( target -- )
  \ ( target -- )  emit B from TGT-HERE to target
  TGT-HERE - 4 /                    \ /4, signed
  $03FFFFFF AND $14000000 OR
  TGT-HERE !  4 TGT-ALLOT ;

: STITCH-NEXT  ( xt -- )
  DUP ['] (NEXT) = IF  DROP EXIT  THEN
  DUP COLON-WORD? IF  DROP EXIT  THEN
  DUP MAP-FIND 8 +                  \ payload
  SWAP PRIM-SPAN NIP +              \ addr just after copied bytes
  TGT-DP !
  ['] (NEXT) MAP-FIND 8 +           \ NEXT payload
  ARM-B, ;

: TGT-STITCH  {: | i -- :}
  0 TO i
  BEGIN  i TGT-MAPN @ <  WHILE
    i CELLS TGT-OLD + @  STITCH-NEXT
    i 1+ TO i
  REPEAT ;

: TGT-PROTECT  ( -- )
  TGT-ORG @ TGT-SIZE 5 MPROTECT THROW
  TGT-ORG @ TGT-SIZE ICACHE-INVAL ;

: TGT-BUILD  ( xt -- )
  TGT-CLOSE
  REACH-FROM
  ['] (DOCOL) (MARK)
  ['] (NEXT)  (MARK)
  ['] EXIT    (MARK)
  65536 TGT-OPEN
  ." opened " TGT-ORG @ U.  TGT-LIMIT @ U.  ."  cap " TGT-SIZE . CR
  TGT-RESERVE
  ." reserved " TGT-SIZE . CR
  TGT-WRITE
  TGT-STITCH
  TGT-RELOC
  TGT-PROTECT
  ." written " TGT-SIZE . CR
  ;

: TGT-DUMP  ( -- )
  HEX
  TGT-ORG @
  BEGIN  DUP TGT-END @ U<  WHILE
    CR DUP U. SPACE  DUP @ U.
    8 +
  REPEAT DROP
  DECIMAL CR ;
  
