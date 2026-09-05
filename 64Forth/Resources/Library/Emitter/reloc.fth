\ reloc.fth — step 3b: retarget out-of-span ARM PC-rel to host VAs
\ Load after target.fth.  Public domain.

ONLY FORTH DEFINITIONS
DECIMAL

: W@  ( addr -- u32 )
  DUP C@
  OVER 1+ C@  8 LSHIFT OR
  OVER 2 + C@ 16 LSHIFT OR
  SWAP 3 + C@ 24 LSHIFT OR ;

: W!  ( u32 addr -- )
  2DUP C!  SWAP 8 RSHIFT SWAP
  2DUP 1+ C!  SWAP 8 RSHIFT SWAP
  2DUP 2 + C!  SWAP 8 RSHIFT SWAP
  3 + C! ;

$D503201F CONSTANT ARM-NOP

: TGT-END-ALIGN4  ( -- )
  TGT-END @ 3 + -4 AND  TGT-END ! ;

: VEN-W,  ( u32 -- )
  TGT-END @  TGT-LIMIT @ 4 - U> IF  ." veneer overflow" CR ABORT  THEN
  TGT-END @ W!
  4 TGT-END +! ;

: VEN-MOV64-X16  ( u64 -- )
  {: val | w bits -- :}
  0 TO w
  BEGIN  w 4 <  WHILE
    val w 16 * RSHIFT $FFFF AND TO bits
    bits 5 LSHIFT
    w 21 LSHIFT OR
    w 0= IF  $D2800000  ELSE  $F2800000  THEN  OR   \ MOVZ/MOVK X16 (Rd=16)
    $10 OR                 \ Rd = 16 already in bits 4:0: 16 = $10
    \ fix: Rd is bits 4:0
    DROP
    w 1+ TO w
  REPEAT ;

\ Correct MOVZ/MOVK X16:
: VEN-MOV64-X16  ( u64 -- )
  {: val | w imm -- :}
  0 TO w
  BEGIN  w 4 <  WHILE
    val w 16 * RSHIFT $FFFF AND TO imm
    imm 5 LSHIFT              \ imm16 at bits 20:5
    16 OR                     \ Rd = X16
    w 21 LSHIFT OR            \ hw
    w 0= IF $D2800000 ELSE $F2800000 THEN OR
    VEN-W,
    w 1+ TO w
  REPEAT ;

$D63F0200 CONSTANT ARM-BLR-X16
$D61F0200 CONSTANT ARM-BR-X16

: ENC-B-TO  ( from to -- insn )     \ B from -> to
  SWAP - 2 ARSHIFT
  $03FFFFFF AND $14000000 OR ;

: ENC-BL-TO ( from to -- insn )
  SWAP - 2 ARSHIFT
  $03FFFFFF AND $94000000 OR ;

: PATCH-BL  ( npc insn tgt -- )
  {: npc insn tgt | ven ret -- :}
  TGT-END-ALIGN4
  TGT-END @ TO ven
  tgt VEN-MOV64-X16
  insn $FC000000 AND $94000000 = IF   \ BL
    ARM-BLR-X16 VEN-W,
    npc 4 + TO ret
    TGT-END @ ret ENC-B-TO VEN-W,     \ B back to npc+4
    ven npc ENC-BL-TO npc W!          \ original site: BL veneer
  ELSE
    ARM-BR-X16 VEN-W,                 \ tail B
    ven npc ENC-B-TO npc W!
  THEN
;

: SEXT26  ( u -- n )
  $03FFFFFF AND
  DUP $02000000 AND IF  $FFFFFFFFFC000000 OR  THEN ;

: SEXT21  ( u -- n )
  $001FFFFF AND
  DUP $00100000 AND IF  $FFFFFFFFFFE00000 OR  THEN ;

: SEXT19  ( u -- n )
  $0007FFFF AND
  DUP $00040000 AND IF  $FFFFFFFFFFF80000 OR  THEN ;

: IN-SPAN?  ( tgt code u -- flag )
  OVER +  WITHIN ;

: -ROT      ( a b c -- c a b)
    ROT ROT ;

\ --- decode: ( insn pc -- tgt | 0 )  0 = not pc-rel we handle ----------

: B/BL?  ( insn -- flag )
  DUP $FC000000 AND  $14000000 =          \ B
  SWAP $FC000000 AND  $94000000 = OR ;    \ BL

: B/BL-TGT  ( insn pc -- tgt )
  SWAP SEXT26 4 * + ;

: ADRP?  ( insn -- flag )
  $9F000000 AND  $90000000 = ;

: ADRP-TGT  ( insn pc -- tgt )
  SWAP
  DUP $60000000 AND 29 RSHIFT          \ immlo
  SWAP $00FFFFE0 AND 5 RSHIFT 2 LSHIFT OR
  SEXT21 12 LSHIFT
  SWAP $FFFFFFFFFFFFF000 AND + ;

: CBNZ-X28?  ( insn -- flag )
  $FF00001F AND  $B500001C = ;         \ CBNZ X28, *

: CBNZ-TGT  ( insn pc -- tgt )
  SWAP 5 RSHIFT SEXT19 4 * + ;

: REL-TGT  ( insn pc -- tgt | 0 )
  OVER B/BL?     IF  B/BL-TGT    EXIT  THEN
  OVER ADRP?     IF  ADRP-TGT    EXIT  THEN
  OVER CBNZ-X28? IF  CBNZ-TGT    EXIT  THEN
  2DROP 0 ;

\ --- re-encode from new pc to same tgt --------------------------------

: ENC-B/BL  ( tgt pc old-insn -- insn )
  \ keep B vs BL opcode
  $94000000 AND  $94000000 = IF $94000000 ELSE $14000000 THEN
  -ROT                          \ opc tgt pc
  - 2 ARSHIFT                   \ opc imm26
  $03FFFFFF AND OR ;

: ENC-ADRP  ( tgt pc old-insn -- insn )
  $0000001F AND                 \ Rd
  -ROT                          \ Rd tgt pc
  $FFFFFFFFFFFFF000 AND         \ Rd tgt pcpage
  SWAP $FFFFFFFFFFFFF000 AND SWAP -
  12 ARSHIFT                    \ Rd pages
  DUP $001FFFFF AND             \ Rd pages imm21
  DUP 2 RSHIFT $00FFFFE0 AND    \ immhi at bits 23:5
  SWAP $00000003 AND 29 LSHIFT OR
  $90000000 OR                  \ ADRP
  ROT OR ;                      \ Rd

: PATCH  {: npc insn tgt -- :}
  npc TGT-ORG @ TGT-END @ WITHIN 0= IF
    ." PATCH bad npc=" npc U.
    ." org=" TGT-ORG @ U.
    ." end=" TGT-END @ U. CR
    ABORT
  THEN
  insn CBNZ-X28? IF  ARM-NOP npc W!  EXIT  THEN
  insn B/BL?     IF  npc insn tgt PATCH-BL  EXIT  THEN
  insn ADRP?     IF  tgt npc insn ENC-ADRP npc W!  EXIT  THEN
  ;

\ REL-TGT needs ( insn pc ). Fix the loop without nested mess:

: RELOC-PRIM  {: xt | new code u off insn tgt npc -- :}
  xt COLON-WORD? IF  EXIT  THEN
  xt NAME>STRING TYPE SPACE ." RELOC" CR
  xt MAP-FIND DUP 0= IF  ." no map" CR DROP EXIT  THEN
  8 + TO new
  xt PRIM-SPAN TO u TO code
  ." new=" new U. SPACE ." code=" code U. SPACE ." u=" u . CR
  0 TO off
  BEGIN  off u <  WHILE
    new off + TO npc
    code off + W@ TO insn
    insn code off + REL-TGT TO tgt
    tgt IF
      tgt code u IN-SPAN? 0= IF
        npc insn tgt PATCH
      THEN
    THEN
    off 4 + TO off
  REPEAT ;

: (TGT-RELOC)  {: | i -- :}
  0 TO i
  BEGIN  i TGT-MAPN @ <  WHILE
    i CELLS TGT-OLD + @ RELOC-PRIM
    i 1+ TO i
  REPEAT ;

' (TGT-RELOC) IS TGT-RELOC  \ fill forward reference.
