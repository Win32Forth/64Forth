\ run.fth — step 3c: trampoline + CALL-NATIVE into a sliced colon
\ Requires target.fth + reloc.fth.  Public domain.

\ Loaded under EMITTER DEFINITIONS (see emitter.fth).
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
\ Encoding: imm16 at bits 20:5, Rd at 4:0, hw at 22:21.
: ARM-MOVZ,  ( imm16 rd hw -- )
  {: imm rd hw -- :}
  hw 21 LSHIFT
  imm 5 LSHIFT OR
  rd OR
  $D2800000 OR  RUN-W, ;

\ MOVK Xd, #imm16, LSL #(hw*16)
: ARM-MOVK,  ( imm16 rd hw -- )
  {: imm rd hw -- :}
  hw 21 LSHIFT
  imm 5 LSHIFT OR
  rd OR
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
\ Set x22=dsp, x23=RSP, x21=colon-CFA, x20=0, x28=0, push a
\ synthetic return IP, then NEXT into the colon body.
\
\ BL veneers in sliced code use BLR and clobber X30. Save CALL-NATIVE's
\ LR on the run RSP at entry; the return gadget restores it before RET.
\
\ Layout: prologue → NEXT into colon → (dead) gadgets after BR.

VARIABLE RET-BODY

: RUN-EMIT  ( colon-xt -- )
  {: xt | cfa retc cfar body patch -- :}
  xt MAP-FIND DUP 0= IF  ." RUN unmapped" CR ABORT  THEN  TO cfa
  RUN-ORG @ RUN-DP !
  $AA1303F6 RUN-W,             \ MOV X22, X19   (DSP)
  0 28 0 ARM-MOVZ,             \ X28 = 0 (no debug NEXT)
  0 20 0 ARM-MOVZ,             \ X20 = 0 (TOS)
  RUN-RSP @ 23 ARM-MOV64,      \ X23 = RSP
  cfa       21 ARM-MOV64,      \ X21 = colon CFA
  $F81F8EFE RUN-W,             \ STR X30, [X23, #-8]!  save LR
  \ Placeholder MOV X0,#body — patched after gadgets are placed
  RUN-HERE TO patch
  0 0 ARM-MOV64,               \ 4 insns; overwritten below
  $F81F8EE0 RUN-W,             \ STR X0, [X23, #-8]!   RPUSH return IP
  $910022B3 RUN-W,             \ ADD X19, X21, #8      IP = body
  $F8408675 RUN-W,             \ LDR X21, [X19], #8    NEXT
  $F94002A1 RUN-W,             \ LDR X1, [X21]
  $D61F0020 RUN-W,             \ BR X1
  \ Gadgets after the BR — never executed by fall-through
  RUN-HERE 7 + -8 AND RUN-DP !
  RUN-HERE TO retc
  $F84086FE RUN-W,             \ LDR X30, [X23], #8    restore LR
  $D65F03C0 RUN-W,             \ RET
  RUN-HERE 7 + -8 AND RUN-DP !
  RUN-HERE TO cfar   retc RUN-HERE !  8 RUN-DP +!   \ CFA -> restore+RET
  RUN-HERE TO body   cfar RUN-HERE !  8 RUN-DP +!   \ IP cell -> CFA
  \ Patch MOV X0, #body at placeholder
  patch RUN-DP !
  body 0 ARM-MOV64,
  ;

: RUN-PROTECT  ( -- )
  RUN-ORG @ RUN-LEN @ 5 MPROTECT THROW
  RUN-ORG @ RUN-LEN @ ICACHE-INVAL ;

\ Patch MAGIC|slot .quads to live _host_app_* VAs (in-process).
\ Called from TGT-BUILD after TGT-RELOC while the image is still RW.
: (HOST-BIND)  ( -- )
  {: | i slot va -- :}
  0 TO i
  BEGIN  i HOST-RELOC-N @ <  WHILE
    i CELLS HOST-RELOC-SLOT + @ TO slot
    slot CELLS HOST-APP-VA + @ TO va
    va 0= IF
      ." HOST-BIND: empty slot " slot . CR ABORT
    THEN
    va  i CELLS HOST-RELOC-OFF + @  !
    i 1+ TO i
  REPEAT ;

' (HOST-BIND) IS HOST-BIND

\ True if first host reloc .quad still holds MAGIC (unbound image).
: HOST-UNBOUND?  ( -- flag )
  HOST-RELOC-N @ 0= IF  FALSE EXIT  THEN
  0 CELLS HOST-RELOC-OFF + @ @
  48 RSHIFT $C0DE = ;

\ For /EMIT-UNBOUND builds (and LOAD-IMAGE): RW → bind → R+X before run.
: HOST-BIND-IF-NEEDED  ( -- )
  HOST-UNBOUND? IF
    HOST-APP-DISCOVER
    TGT-ORG @ TGT-SIZE 3 MPROTECT THROW
    HOST-BIND
    TGT-PROTECT
  THEN ;

\ Like RUN-EMIT but CFA already known (LOAD-IMAGE / no host xt map).
: RUN-EMIT-CFA  ( cfa -- )
  {: cfa | retc cfar body patch -- :}
  RUN-ORG @ RUN-DP !
  $AA1303F6 RUN-W,             \ MOV X22, X19   (DSP)
  0 28 0 ARM-MOVZ,             \ X28 = 0 (no debug NEXT)
  0 20 0 ARM-MOVZ,             \ X20 = 0 (TOS)
  RUN-RSP @ 23 ARM-MOV64,      \ X23 = RSP
  cfa       21 ARM-MOV64,      \ X21 = colon CFA
  $F81F8EFE RUN-W,             \ STR X30, [X23, #-8]!  save LR
  RUN-HERE TO patch
  0 0 ARM-MOV64,
  $F81F8EE0 RUN-W,             \ STR X0, [X23, #-8]!   RPUSH return IP
  $910022B3 RUN-W,             \ ADD X19, X21, #8      IP = body
  $F8408675 RUN-W,             \ LDR X21, [X19], #8    NEXT
  $F94002A1 RUN-W,             \ LDR X1, [X21]
  $D61F0020 RUN-W,             \ BR X1
  RUN-HERE 7 + -8 AND RUN-DP !
  RUN-HERE TO retc
  $F84086FE RUN-W,             \ LDR X30, [X23], #8    restore LR
  $D65F03C0 RUN-W,             \ RET
  RUN-HERE 7 + -8 AND RUN-DP !
  RUN-HERE TO cfar   retc RUN-HERE !  8 RUN-DP +!
  RUN-HERE TO body   cfar RUN-HERE !  8 RUN-DP +!
  patch RUN-DP !
  body 0 ARM-MOV64,
  ;

: TGT-RUN-AT  ( cfa -- )
  HOST-BIND-IF-NEEDED
  RUN-OPEN
  RUN-EMIT-CFA
  RUN-PROTECT
  0  RUN-DSP @  RUN-ORG @  CALL-NATIVE
  DROP
  RUN-CLOSE ;

: TGT-RUN  ( xt -- )
  DUP COLON-WORD? 0= IF  ." TGT-RUN needs a colon xt" CR ABORT  THEN
  DUP MAP-FIND DUP 0= IF  ." TGT-RUN unmapped" CR ABORT  THEN
  NIP TGT-RUN-AT ;
