\ reach.fth — mark xts reachable from a root (emitter step 1)
\ Public domain.

\ Loaded under EMITTER DEFINITIONS (see emitter.fth).
DECIMAL

\ CELL may already exist in FORTH; keep a local alias only if absent.
[UNDEFINED] CELL [IF]
8 CONSTANT CELL
[THEN]

: COLON-WORD?  ( xt -- flag )
  DUP ['] (DOCOL) = IF  DROP FALSE EXIT  THEN
  @  ['] (DOCOL) @  = ;

: DOVAR?   ( xt -- flag )  @  ['] (DOVAR)  @  = ;
: DOCON?   ( xt -- flag )  @  DOCON-ADDR      = ;
: DODOES?  ( xt -- flag )  @  ['] (DODOES) @  = ;

\ CREATE / VARIABLE / CONSTANT / VALUE / DEFER / VOCABULARY, etc.
\ Default: identity map for in-process TGT-RUN. /EMIT-STANDALONE copies them (target.fth).
\ Exclude the runtime engines themselves — their CFA also matches DOVAR?/DOCON?/DODOES?.
: DATA-WORD?  ( xt -- flag )
  DUP ['] (DOVAR)  = IF  DROP FALSE EXIT  THEN
  DUP ['] (DOCON)  = IF  DROP FALSE EXIT  THEN
  DUP ['] (DODOES) = IF  DROP FALSE EXIT  THEN
  DUP DOVAR? IF  DROP TRUE EXIT  THEN
  DUP DOCON? IF  DROP TRUE EXIT  THEN
  DODOES? ;

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

\ Branch / loop inline: IP at opcode, next cell is byte offset; target =
\ addr_of_offset + offset (see forth.s XBranch / X0Branch).
: BR-OP?  ( xt -- flag )
  DUP 0BRANCH-ADDR =
  OVER BRANCH-ADDR = OR
  OVER ['] (LOOP) = OR
  OVER ['] (+LOOP) = OR
  OVER ['] (?DO) = OR
  SWAP ['] LEAVE = OR ;

\ Exclusive end of colon region still to visit (branch-aware).
\ Needed so IF EXIT THEN does not stop the scan at the mid-colon EXIT.
VARIABLE SCAN-LIM

: SCAN-COVER  ( cell-addr -- )
  \ Ensure the cell at cell-addr is included: exclusive end >= cell+8.
  8 +  SCAN-LIM @ MAX  SCAN-LIM ! ;

VARIABLE SCAN-MARK?   \ nonzero => (MARK) while walking
VARIABLE SCAN-ADDR

\ Lit payload may be a number or an xt (CATCH / [']).
\ Only follow user-dict addresses — @ on small ints SIGSEGVs past CATCH.
: LIT-PAYLOAD-MARK  ( x -- )
  DUP 7 AND IF  DROP EXIT  THEN
  DUP USER-DICT HERE WITHIN 0= IF  DROP EXIT  THEN
  DUP COLON-WORD? IF  (MARK) EXIT  THEN
  DUP DATA-WORD? IF  (MARK) EXIT  THEN
  DROP ;


: (COLON-WALK)  ( body -- )
  \ Updates SCAN-LIM. SCAN-MARK? selects whether to (MARK) xts.
  DUP SCAN-ADDR !
  0 SCAN-LIM !                      \ clear stale lim from a prior walk
  SCAN-COVER
  BEGIN
    SCAN-ADDR @ SCAN-LIM @ >= IF  EXIT  THEN
    SCAN-ADDR @ HERE U< 0= IF  ." scan: overrun" CR EXIT  THEN
    SCAN-ADDR @ @
    DUP ['] EXIT = IF
      SCAN-MARK? @ IF  DUP (MARK)  THEN  DROP
      8 SCAN-ADDR +!                    \ mid-colon EXIT: no fall-through
    ELSE
      SCAN-MARK? @ IF  DUP (MARK)  THEN
      DUP LIT-ADDR = IF
        DROP
        SCAN-MARK? @ IF  SCAN-ADDR @ 8 + @ LIT-PAYLOAD-MARK  THEN
        16 SCAN-ADDR +!  SCAN-ADDR @ SCAN-COVER
      ELSE DUP BR-OP? IF
        DROP
        SCAN-ADDR @ 8 +                 \ offset cell
        DUP @ OVER + SCAN-COVER         \ branch target
        8 + SCAN-ADDR !  SCAN-ADDR @ SCAN-COVER
      ELSE DUP SLIT-ADDR = IF
        DROP
        SCAN-ADDR @ 8 + SLIT-SKIP SCAN-ADDR !
        SCAN-ADDR @ SCAN-COVER
      ELSE
        DROP  8 SCAN-ADDR +!  SCAN-ADDR @ SCAN-COVER
      THEN THEN THEN
    THEN
  AGAIN ;

: SCAN-COLON  ( xt -- )
  TRUE SCAN-MARK? !  BODY (COLON-WALK) ;

: COLON-END  ( xt -- body bytes )
  \ Byte length of colon body including cells past mid-colon EXIT.
  FALSE SCAN-MARK? !
  BODY DUP (COLON-WALK)
  SCAN-LIM @  SWAP - ;

\ DOES> fragment at CFA+8: ITC xt list ending in EXIT (VALUE/CONSTANT/DEFER).
: SCAN-DOES  ( xt -- )
  8 + @                         \ does_ip
  BEGIN
    DUP @ DUP (MARK)
    ['] EXIT = IF  DROP EXIT  THEN
    8 +
  AGAIN ;

\ Colon bodies are walked for callees. DODOES data words contribute their
\ DOES> fragment xts. Plain CODE / DOVAR / DOCON are leaves.
: SCAN-ONE  ( xt -- )
  DUP COLON-WORD? IF  SCAN-COLON EXIT  THEN
  DUP DODOES? IF  SCAN-DOES EXIT  THEN
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
    DUP COLON-WORD? IF ." colon"
    ELSE DUP DATA-WORD? IF ." data"
    ELSE ." code" THEN THEN CR
    DROP 1+
  REPEAT DROP ;
