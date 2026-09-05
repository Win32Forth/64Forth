\ run.fth — step 3c: trampoline + CALL-NATIVE into a sliced colon
\ Requires target.fth + reloc.fth.  Public domain.

ONLY FORTH DEFINITIONS
DECIMAL

VARIABLE RUN-ORG
VARIABLE RUN-DP
VARIABLE RUN-LEN
VARIABLE RUN-DSP
VARIABLE RUN-RSP
VARIABLE RUN-DSP-MEM
VARIABLE RUN-RSP-MEM

4096 CONSTANT RUN-CODE-U
8192 CONSTANT RUN-STACK-U

: RUN-HERE  ( -- addr )  RUN-DP @ ;

: RUN-W,  ( u32 -- )
  RUN-HERE W!  4 RUN-DP +! ;

\ MOVZ Xd, #imm16, LSL #(hw*16)     hw = 0,1,2,3
: ARM-MOVZ,  ( imm16 rd hw -- )
  21 LSHIFT SWAP 5 LSHIFT OR OR
  $D2800000 OR  RUN-W, ;

\ MOVK Xd, #imm16, LSL #(hw*16)
: ARM-MOVK,  ( imm16 rd hw -- )
  21 LSHIFT SWAP 5 LSHIFT OR OR
  $F2800000 OR  RUN-W, ;

: ARM-MOV64,  ( u64 rd -- )
  {: val rd | w -- :}
  0 TO w
  BEGIN  w 4 <  WHILE
    val w 16 * RSHIFT $FFFF AND
    rd w
    w 0= IF  ARM-MOVZ,  ELSE  ARM-MOVK,  THEN
    w 1+ TO w
  REPEAT ;

: ARM-BR,  ( rd -- )        \ BR Xd
  5 LSHIFT $D61F0000 OR  RUN-W, ;

: ARM-MOVZ-X,  ( rd -- )    \ MOV Xd, #0  = MOVZ Xd, #0
  0 SWAP 0 ARM-MOVZ, ;

: RUN-CLOSE  ( -- )
  RUN-ORG @ IF
    RUN-ORG @ RUN-LEN @ FREE-EXEC DROP
  THEN
  RUN-DSP-MEM @ IF  RUN-DSP-MEM @ FREE DROP  THEN
  RUN-RSP-MEM @ IF  RUN-RSP-MEM @ FREE DROP  THEN
  0 RUN-ORG !  0 RUN-DP !  0 RUN-LEN !
  0 RUN-DSP !  0 RUN-RSP !
  0 RUN-DSP-MEM !  0 RUN-RSP-MEM ! ;

: RUN-OPEN  ( -- )
  RUN-CLOSE
  RUN-CODE-U DUP RUN-LEN !
  ALLOCATE-EXEC IF  DROP ." RUN ALLOCATE-EXEC failed" CR ABORT  THEN
  DUP RUN-ORG !  RUN-DP !
  RUN-STACK-U ALLOCATE IF  DROP ." RUN DSP failed" CR ABORT  THEN
  DUP RUN-DSP-MEM !
  RUN-STACK-U + 64 -  RUN-DSP !
  RUN-STACK-U ALLOCATE IF  DROP ." RUN RSP failed" CR ABORT  THEN
  DUP RUN-RSP-MEM !
  RUN-STACK-U + 64 -  RUN-RSP ! ;

\ Emit trampoline at RUN-ORG.
\ On entry from CALL-NATIVE: x19 = dsp we passed, x0 unused.
\ We set x22=x19, x23=RSP, x21=colon-CFA, x20=0, x28=0, BR DOCOL.
VARIABLE RET-BODY

: RUN-EMIT  ( colon-xt -- )
  {: xt | cfa retc cfar body -- :}
  xt MAP-FIND DUP 0= IF  ." RUN unmapped" CR ABORT  THEN  TO cfa
  RUN-ORG @ RUN-DP !
  $D503245F RUN-W,
  $AA1303F6 RUN-W,
  0 28 0 ARM-MOVZ,
  0 20 0 ARM-MOVZ,
  RUN-RSP @ 23 ARM-MOV64,
  cfa       21 ARM-MOV64,
  \ gadget at end of page-ish: RET, CFA, BODY
  RUN-HERE 7 + -8 AND RUN-DP !
  RUN-HERE TO retc   $D65F03C0 RUN-W,
  RUN-HERE 7 + -8 AND RUN-DP !
  RUN-HERE TO cfar   retc  RUN-HERE !  8 RUN-DP +!
  RUN-HERE TO body   cfar  RUN-HERE !  8 RUN-DP +!
  body 0 ARM-MOV64,            \ X0 = BODY-RET
  $F81F8EE0 RUN-W,             \ STR X0, [X23, #-8]!
  $910022B3 RUN-W,             \ ADD X19, X21, #8
  $F8408675 RUN-W,
  $F94002A1 RUN-W,
  $D61F0020 RUN-W, ;

\ note: ARM-MOV64, into X0 must be BEFORE STR/NEXT. It is.

: RUN-PROTECT  ( -- )
  RUN-ORG @ RUN-LEN @ 5 MPROTECT THROW
  RUN-ORG @ RUN-LEN @ ICACHE-INVAL ;

: TGT-RUN  ( xt -- )
  DUP COLON-WORD? 0= IF  ." TGT-RUN needs a colon xt" CR ABORT  THEN
  RUN-OPEN
  RUN-EMIT
  RUN-PROTECT
  0  RUN-DSP @  RUN-ORG @  CALL-NATIVE
  DROP
  RUN-CLOSE ;
