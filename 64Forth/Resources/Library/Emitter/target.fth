\ target.fth — emitter step 2
\ Requires reach.fth
\ Public domain.

\ Loaded under EMITTER DEFINITIONS (see emitter.fth).
DECIMAL

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

\ 32-bit store (ARM insn). Must not use cell ! — that writes 8 bytes and
\ clobbers the next prim's CFA when stitching a trailing B.
: TGT-W!  ( u32 addr -- )
  2DUP C!  SWAP 8 RSHIFT SWAP
  2DUP 1+ C!  SWAP 8 RSHIFT SWAP
  2DUP 2 + C!  SWAP 8 RSHIFT SWAP
  3 + C! ;
: TGT-W,  ( u32 -- )
  TGT-HERE TGT-W!  4 TGT-ALLOT ;

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
  \ Unknown / non-boot CODE must not be sliced (end=0 ⇒ garbage length).
  DUP >R CODE-BOUNDS
  DUP 0= IF
    DROP DROP
    ." prim: no CODE-BOUNDS for " R> NAME>STRING TYPE CR ABORT
  THEN
  R> DROP
  2DUP SWAP - NIP ;

\ CREATE/VALUE/etc.: keep host xt (TO LIT PFAs and buffers stay valid).
: RESERVE-IMPORT  ( xt -- )
  DUP MAP! ;

: COLON-SPAN  ( xt -- addr u )
  \ Body addr and byte length (branch-aware; see COLON-END in reach.fth).
  DUP COLON-END  SWAP BODY  SWAP ;

: RESERVE-PRIM  {: xt | new u -- :}
  TGT-ALIGN
  TGT-HERE TO new
  xt PRIM-SPAN NIP 7 + -8 AND 8 + TO u
  xt ['] (NEXT) <> IF  u 4 + TO u  THEN
  \ keep following CFA 8-aligned (stitch B is 4 bytes)
  u 7 + -8 AND TO u
  u TGT-ALLOT
  xt new MAP! ;

: RESERVE-COLON  {: xt | new u -- :}
  TGT-ALIGN
  TGT-HERE TO new
  xt COLON-SPAN NIP 8 + TO u
  u 7 + -8 AND TO u
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
  \ Copy full colon body (past mid-colon EXIT from IF EXIT THEN).
  \ Stack walk: ( addr ) with end on return stack.
  COLON-SPAN OVER + >R              \ R: end  ( addr )
  BEGIN
    DUP R@ >= IF  DROP R> DROP EXIT  THEN
    DUP @                           \ addr xt
    DUP ['] EXIT = IF
      MAP-CELL 8 +                  \ mid or final EXIT
    ELSE DUP LIT-ADDR = IF
      MAP-CELL 8 + DUP @ TGT, 8 +
    ELSE DUP BR-OP? IF
      MAP-CELL 8 + DUP @ TGT, 8 +
    ELSE DUP SLIT-ADDR = IF
      MAP-CELL
      8 + DUP @ TGT,
      DUP 8 + OVER @ COPY-BYTES
      SLIT-SKIP
    ELSE
      MAP-CELL 8 +
    THEN THEN THEN THEN
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
    DUP COLON-WORD? IF  ." colon"  CR RESERVE-COLON
    ELSE DUP DATA-WORD? IF  ." import" CR RESERVE-IMPORT
    ELSE                ." prim"   CR RESERVE-PRIM
    THEN THEN
    RI 1+ TO RI
  REPEAT
  ." maps=" TGT-MAPN @ . CR
  TGT-HERE TGT-END ! ;

: TGT-WRITE  {: | RI -- :}
  0 TO RI
  BEGIN  RI REACH-N @ <  WHILE
    RI CELLS REACH-XTS + @
    DUP COLON-WORD? IF  DROP
    ELSE DUP DATA-WORD? IF  DROP
    ELSE  WRITE-PRIM  THEN THEN
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
  \ emit 32-bit B from TGT-HERE to target (see TGT-W!, not cell !)
  TGT-HERE - 2 ARSHIFT
  $03FFFFFF AND $14000000 OR
  TGT-W, ;

: STITCH-NEXT  ( xt -- )
  DUP ['] (NEXT) = IF  DROP EXIT  THEN
  DUP COLON-WORD? IF  DROP EXIT  THEN
  DUP DATA-WORD? IF  DROP EXIT  THEN   \ host import — no copied body
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
  
