\ reloc.fth — step 3b: retarget out-of-span ARM PC-rel to host VAs
\ Load after target.fth.  Public domain.

\ Loaded under EMITTER DEFINITIONS (see emitter.fth).
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

\ --- host_app_* slots (Phase 2a) ----------------------------------------
\ Slot map (append only): 0 open 1 close 2 blit 3 pblit 4 keyq 5 key
\ 6 name 7 tone 8 pump.  .quad = HOST-CALL-MAGIC|slot until HOST-BIND.

$C0DE000000000000 CONSTANT HOST-CALL-MAGIC
9 CONSTANT #HOST-APP
128 CONSTANT #HOST-RELOC

CREATE HOST-APP-VA     #HOST-APP CELLS ALLOT
CREATE HOST-RELOC-OFF  #HOST-RELOC CELLS ALLOT
CREATE HOST-RELOC-SLOT #HOST-RELOC CELLS ALLOT
VARIABLE HOST-RELOC-N
0 HOST-RELOC-N !

: HOST-RELOC-CLEAR  ( -- )  0 HOST-RELOC-N ! ;

: HOST-RELOC-ADD  ( slot -- )
  HOST-RELOC-N @ #HOST-RELOC U< 0= IF
    ." too many host-call relocs" CR ABORT
  THEN
  TGT-END @  HOST-RELOC-N @ CELLS HOST-RELOC-OFF + !
  DUP HOST-RELOC-N @ CELLS HOST-RELOC-SLOT + !
  DROP
  1 HOST-RELOC-N +! ;

: HOST-SLOT-OF  ( va -- slot | -1 )
  #HOST-APP 0 DO
    DUP I CELLS HOST-APP-VA + @ = IF  DROP I UNLOOP EXIT  THEN
  LOOP  DROP -1 ;

: TGT-END-ALIGN8  ( -- )
  TGT-END @ 7 + -8 AND  TGT-END ! ;

: VEN-,  ( u64 -- )
  TGT-END @  TGT-LIMIT @ 8 - U> IF  ." veneer overflow" CR ABORT  THEN
  TGT-END @ !  8 TGT-END +! ;

\ LDR Xt, label — A64 literal offset is SignExtend(imm19)*4 (not *8).
\ For 64-bit LDR the address must still be 8-aligned (imm19 even).
: ENC-LDR64-LIT-X16  ( from to -- insn )
  SWAP - 2 ARSHIFT
  $7FFFF AND 5 LSHIFT
  16 OR  $58000000 OR ;

: PATCH-BL-HOST  ( npc insn slot -- )
  \ Veneer (8-aligned): LDR X16,lit / BLR|BR / B ret|NOP / NOP / .quad
  \ lit at ven+16 → imm19=4 (PC+16).
  {: npc insn slot | ven ret lit -- :}
  TGT-END-ALIGN8
  TGT-END @ TO ven
  ven 16 + TO lit
  ven lit ENC-LDR64-LIT-X16 VEN-W,
  insn $FC000000 AND $94000000 = IF   \ BL
    ARM-BLR-X16 VEN-W,
    npc 4 + TO ret
    TGT-END @ ret ENC-B-TO VEN-W,
    ARM-NOP VEN-W,
    slot HOST-RELOC-ADD
    HOST-CALL-MAGIC slot OR VEN-,
    npc ven ENC-BL-TO npc W!
  ELSE
    ARM-BR-X16 VEN-W,
    ARM-NOP VEN-W,
    ARM-NOP VEN-W,
    slot HOST-RELOC-ADD
    HOST-CALL-MAGIC slot OR VEN-,
    npc ven ENC-B-TO npc W!
  THEN
;

\ SA out-of-span BL: deferred so HOST-PRIM-VA can be defined first.
\ Default NOPs (EXIT→_local_frame_try_exit). Real handler installed below.
DEFER SA-PATCH-BL-HELPER  ( npc tgt -- )
: (SA-PATCH-BL-NOP)  ( npc tgt -- )  DROP ARM-NOP SWAP W! ;
' (SA-PATCH-BL-NOP) IS SA-PATCH-BL-HELPER

: PATCH-BL-ABS  ( npc insn tgt -- )
  {: npc insn tgt | ven ret -- :}
  \ Stand-alone: no host process. SA-PATCH-BL-HELPER embeds pure helpers
  \ (e.g. _udivmod128); host-only BLs (EXIT locals) stay NOP.
  ?EMIT-STANDALONE IF
    insn $FC000000 AND $94000000 = IF
      npc tgt SA-PATCH-BL-HELPER  EXIT
    THEN
    ." PATCH-BL-ABS: stand-alone cannot veneer abs B to " tgt U. CR ABORT
  THEN
  TGT-END-ALIGN4
  TGT-END @ TO ven
  tgt VEN-MOV64-X16
  insn $FC000000 AND $94000000 = IF   \ BL
    ARM-BLR-X16 VEN-W,
    npc 4 + TO ret
    TGT-END @ ret ENC-B-TO VEN-W,
    npc ven ENC-BL-TO npc W!
  ELSE
    ARM-BR-X16 VEN-W,
    npc ven ENC-B-TO npc W!
  THEN
;

: PATCH-BL  ( npc insn tgt -- )
  {: npc insn tgt | slot -- :}
  tgt HOST-SLOT-OF TO slot
  slot 0< 0= IF  npc insn slot PATCH-BL-HOST EXIT  THEN
  npc insn tgt PATCH-BL-ABS ;


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

\ First out-of-span BL/B target in a CODE prim (= _host_app_* VA).
: HOST-PRIM-VA  ( xt -- va | 0 )
  {: xt | code u off insn tgt -- :}
  xt PRIM-SPAN TO u TO code
  0 TO off
  BEGIN  off u <  WHILE
    code off + W@ TO insn
    insn B/BL? IF
      insn code off + B/BL-TGT TO tgt
      tgt code u IN-SPAN? 0= IF  tgt EXIT  THEN
    THEN
    off 4 + TO off
  REPEAT
  0 ;

\ --- stand-alone FLAG_EMM helpers (BOOT_WORD + CODE-BOUNDS) ----------------
\ Out-of-span BL targets that land in a FLAG_EMM boot span are copied into
\ the image when the span has no ADRP (pure ALU/control, e.g. (UDIVMOD128)).
\ Host-tied spans (ADRP to BSS/hooks) stay NOP — same as EXIT→locals.
32 CONSTANT #SA-HELP
CREATE SA-HELP-HOST  #SA-HELP CELLS ALLOT
CREATE SA-HELP-NEW   #SA-HELP CELLS ALLOT
VARIABLE SA-HELP-N
: SA-HELP-CLEAR  ( -- )  0 SA-HELP-N ! ;

: SA-HELP-FIND  ( host -- new|0 )
  {: h | i -- :}
  0 TO i
  BEGIN  i SA-HELP-N @ <  WHILE
    i CELLS SA-HELP-HOST + @ h = IF
      i CELLS SA-HELP-NEW + @ EXIT
    THEN
    i 1+ TO i
  REPEAT
  0 ;

: SA-HELP-COPY  ( host u -- new )
  {: host u | new -- :}
  TGT-END-ALIGN4
  TGT-END @ TO new
  new u + TGT-LIMIT @ U> IF  ." sa-help overflow" CR ABORT  THEN
  host new u MOVE
  u TGT-END +!
  SA-HELP-N @ #SA-HELP U< 0= IF  ." too many sa helpers" CR ABORT  THEN
  host SA-HELP-N @ CELLS SA-HELP-HOST + !
  new  SA-HELP-N @ CELLS SA-HELP-NEW  + !
  1 SA-HELP-N +!
  ." sa-help " u U. ." bytes @ " new U. CR
  new ;

: SA-HELP-ENSURE  ( host u -- new )
  OVER SA-HELP-FIND ?DUP IF  NIP NIP EXIT  THEN
  SA-HELP-COPY ;

\ va inside a FLAG_EMM boot span → ( code u ); else 0 0.
: EMM-SPAN-OF  ( va -- code u | 0 0 )
  {: va | row code end -- :}
  BOOT-WORD-TABLE
  BEGIN  DUP @ WHILE
    DUP TO row
    row BOOT-WORD-EMM? IF
      row BOOT-WORD-CODE TO code
      row BOOT-WORD-END TO end
      end IF
        va code end WITHIN IF
          DROP  code  end code -  EXIT
        THEN
      THEN
    THEN
    /BOOT-WORD +
  REPEAT DROP 0 0 ;

\ --- SA-BLOCK registry ----------------------------------------------------
\ Contiguous closed runtimes preferred over leaf FLAG_EMM embeds.
\ Registered blocks skip SPAN-SA-PURE? (may contain gated ADRP + pool).
\ Pool layout is owned by each block's patch xt (new u --); not assumed here.
\
\ Known / planned boot names:
\   (SA-PRINT)  — numeric/string emit (registered below)
\   (SA-FILES)  — File-Access Darwin multiplex (registered below)
\   (SA-FLOAT)  — FP without float_op_hook (asm TBD)
\   (SA-ARITH)  — optional later mega-block around udivmod (optional)

8 CONSTANT #SA-BLOCK
CREATE SA-BLOCK-HOST   #SA-BLOCK CELLS ALLOT
CREATE SA-BLOCK-U      #SA-BLOCK CELLS ALLOT
CREATE SA-BLOCK-PATCH  #SA-BLOCK CELLS ALLOT   \ xt ( new u -- ) or 0
VARIABLE SA-BLOCK-N
: SA-BLOCK-CLEAR  ( -- )  0 SA-BLOCK-N ! ;

\ Boot catalog: name → ( code u | 0 0 ).
: BOOT-SPAN-NAMED  ( c-addr u -- code u | 0 0 )
  {: addr len | row code end -- :}
  BOOT-WORD-TABLE
  BEGIN  DUP @ WHILE
    DUP TO row
    row @ ZCOUNT addr len COMPARE 0= IF
      row BOOT-WORD-CODE TO code
      row BOOT-WORD-END TO end
      end 0= IF  DROP 0 0 EXIT  THEN
      DROP  code  end code -  EXIT
    THEN
    /BOOT-WORD +
  REPEAT DROP 0 0 ;

: SA-BLOCK-REGISTER  ( c-addr u patch-xt -- )
  {: addr len patch | code u i -- :}
  addr len BOOT-SPAN-NAMED TO u TO code
  code 0= IF
    ." sa-block missing " addr len TYPE CR ABORT
  THEN
  SA-BLOCK-N @ #SA-BLOCK U< 0= IF
    ." too many sa-blocks" CR ABORT
  THEN
  SA-BLOCK-N @ TO i
  code  i CELLS SA-BLOCK-HOST  + !
  u     i CELLS SA-BLOCK-U     + !
  patch i CELLS SA-BLOCK-PATCH + !
  1 SA-BLOCK-N +!
  ." sa-block " addr len TYPE ."  " u U. ." bytes" CR ;

: SA-BLOCK-OF  ( va -- code u | 0 0 )
  {: va | i code u -- :}
  0 TO i
  BEGIN  i SA-BLOCK-N @ <  WHILE
    i CELLS SA-BLOCK-HOST + @ TO code
    i CELLS SA-BLOCK-U    + @ TO u
    va code u IN-SPAN? IF  code u EXIT  THEN
    i 1+ TO i
  REPEAT
  0 0 ;

: SA-BLOCK-PATCH-OF  ( host -- xt|0 )
  {: host | i -- :}
  0 TO i
  BEGIN  i SA-BLOCK-N @ <  WHILE
    i CELLS SA-BLOCK-HOST + @ host = IF
      i CELLS SA-BLOCK-PATCH + @ EXIT
    THEN
    i 1+ TO i
  REPEAT
  0 ;

\ After MOVE of SA-PRINT: last 32 bytes are the literal pool.
\ base_ptr → image BASE PFA; hook ptrs → in-block zero cell (forces write(1)).
\ (Leaving hook ptrs 0 would select host ADRP fallback — wrong after MOVE.)
: SA-PRINT-BASE-CELL  ( -- addr )
  ['] BASE MAP-FIND ?DUP IF  16 + EXIT  THEN
  \ BASE not reachable — private DECIMAL cell in the RW data segment.
  TGT-DATA @ 0= IF  ." sa-print: no data seg for BASE" CR ABORT  THEN
  TGT-DATA-DP @ 7 + -8 AND
  DUP 10 SWAP !
  DUP 8 + TGT-DATA-DP !
  8 TGT-DATA-BYTES +! ;

: SA-PRINT-PATCH-POOL  ( new u -- )
  {: new u | pool z -- :}
  u 32 U< IF  ." sa-print: block too small" CR ABORT  THEN
  new u + 32 - TO pool
  pool 24 + TO z          \ sa_print_zero_cell in the copy
  0 z !
  SA-PRINT-BASE-CELL pool !
  z pool 8 + !            \ emit_hook_ptr → zero cell
  z pool 16 + !           \ emit_buf_ptr  → zero cell
  ." sa-print pool @ " pool U. CR ;

\ After MOVE of SA-FILES: last 32 bytes are the literal pool.
\ hook_ptr → in-block zero cell (forces Darwin svc; 0 would ADRP host).
: SA-FILES-PATCH-POOL  ( new u -- )
  {: new u | pool z -- :}
  u 32 U< IF  ." sa-files: block too small" CR ABORT  THEN
  new u + 32 - TO pool
  pool 8 + TO z           \ sa_files_zero_cell
  0 z !
  z pool !                \ hook_ptr → zero → Darwin multiplex
  0 pool 16 + !
  0 pool 24 + !
  ." sa-files pool @ " pool U. CR ;

: SA-BLOCK-SETUP  ( -- )
  SA-BLOCK-CLEAR
  S" (SA-PRINT)" ['] SA-PRINT-PATCH-POOL SA-BLOCK-REGISTER
  S" (SA-FILES)" ['] SA-FILES-PATCH-POOL SA-BLOCK-REGISTER
  \ Future (when asm exists):
  \ S" (SA-FLOAT)" ['] SA-FLOAT-PATCH-POOL SA-BLOCK-REGISTER
  ;

: SPAN-HAS-ADRP?  ( code u -- flag )
  {: code u | off -- :}
  0 TO off
  BEGIN  off u <  WHILE
    code off + W@ ADRP? IF  TRUE EXIT  THEN
    off 4 + TO off
  REPEAT
  FALSE ;

\ True if any B/BL lands outside [code, code+u). Copied helpers must be
\ closed: e.g. (.) bls to _i64_to_str — MOVE would leave stale PC-rel.
: SPAN-HAS-EXT-BL?  ( code u -- flag )
  {: code u | off insn tgt -- :}
  0 TO off
  BEGIN  off u <  WHILE
    code off + W@ TO insn
    insn B/BL? IF
      insn code off + B/BL-TGT TO tgt
      tgt code u IN-SPAN? 0= IF  TRUE EXIT  THEN
    THEN
    off 4 + TO off
  REPEAT
  FALSE ;

: SPAN-SA-PURE?  ( code u -- flag )
  2DUP SPAN-HAS-ADRP? IF  2DROP FALSE EXIT  THEN
  SPAN-HAS-EXT-BL? 0= ;

: (SA-PATCH-BL-HELPER)  ( npc tgt -- )
  {: npc tgt | code u new patch -- :}
  \ Prefer registered SA-* blocks over leaf FLAG_EMM (leaves often have ext BLs).
  tgt SA-BLOCK-OF TO u TO code
  code IF
    code SA-HELP-FIND ?DUP IF
      TO new
    ELSE
      code u SA-HELP-COPY TO new
      code SA-BLOCK-PATCH-OF TO patch
      patch IF  new u patch EXECUTE  THEN
    THEN
    npc  new tgt code - +  ENC-BL-TO npc W!
    EXIT
  THEN
  tgt EMM-SPAN-OF TO u TO code
  code 0= IF  ARM-NOP npc W!  EXIT  THEN
  code u SPAN-SA-PURE? 0= IF  ARM-NOP npc W!  EXIT  THEN
  code u SA-HELP-ENSURE TO new
  npc  new tgt code - +  ENC-BL-TO npc W!
  ;
' (SA-PATCH-BL-HELPER) IS SA-PATCH-BL-HELPER

: HOST-APP-SET  ( xt slot -- )
  SWAP HOST-PRIM-VA  SWAP CELLS HOST-APP-VA + ! ;

\ (APP-*) live in GRAPHICS (FORTH>GRAPHICS). wid = VOCABULARY PFA+CELL
\ (does_ip at >BODY, heads at >BODY CELL+). Do not ALSO GRAPHICS while
\ compiling Emitter — it shadows TYPE/EMIT/CR.
: GRAPHICS-WID  ( -- wid )  ['] GRAPHICS >BODY CELL+ ;

: HOST-APP-XT  ( c-addr u -- xt )
  2DUP GRAPHICS-WID SEARCH-WORDLIST
  ?DUP 0= IF  ." host-app missing " TYPE CR ABORT  THEN
  DROP >R 2DROP R> ;

: HOST-APP-DISCOVER  ( -- )
  S" (APP-OPEN)"  HOST-APP-XT 0 HOST-APP-SET
  S" (APP-CLOSE)" HOST-APP-XT 1 HOST-APP-SET
  S" (APP-BLIT)"  HOST-APP-XT 2 HOST-APP-SET
  S" (APP-PBLIT)" HOST-APP-XT 3 HOST-APP-SET
  S" (APP-KEY?)"  HOST-APP-XT 4 HOST-APP-SET
  S" (APP-KEY)"   HOST-APP-XT 5 HOST-APP-SET
  S" (APP-NAME)"  HOST-APP-XT 6 HOST-APP-SET
  S" (APP-TONE)"  HOST-APP-XT 7 HOST-APP-SET
  S" (APP-PUMP)"  HOST-APP-XT 8 HOST-APP-SET ;

\ --- re-encode from new pc to same tgt --------------------------------

: ENC-B/BL  ( tgt pc old-insn -- insn )
  \ keep B vs BL opcode
  $94000000 AND  $94000000 = IF $94000000 ELSE $14000000 THEN
  -ROT                          \ opc tgt pc
  - 2 ARSHIFT                   \ opc imm26
  $03FFFFFF AND OR ;

: ENC-ADRP  ( tgt pc old-insn -- insn )
  \ page delta = (tgt_page - pc_page) / 4096 as signed imm21
  $0000001F AND                 \ Rd
  -ROT                          \ Rd tgt pc
  $FFFFFFFFFFFFF000 AND         \ Rd tgt pcpage
  SWAP $FFFFFFFFFFFFF000 AND SWAP -
  12 ARSHIFT                    \ Rd pages
  $001FFFFF AND                 \ Rd imm21
  DUP 3 LSHIFT $00FFFFE0 AND    \ Rd imm21 immhi@23:5
  OVER $00000003 AND 29 LSHIFT OR  \ Rd imm21 (immhi|immlo)
  NIP                           \ Rd imm
  $90000000 OR OR ;             \ ADRP | imm | Rd

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
  xt DATA-WORD? IF  EXIT  THEN   \ host import — never patch host CFA/PFA
  \ 0BRANCH is always a custom guard-free body (no host data_stack ADRP).
  \ PAD/BASE etc. are DOVAR data under /EMIT-STANDALONE (see SA-GLOBAL-PRIM?).
  xt 0BRANCH-ADDR = IF  EXIT  THEN
  ?EMIT-STANDALONE IF
    xt SA-GLOBAL-PRIM? IF  EXIT  THEN
  THEN
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
  HOST-RELOC-CLEAR
  SA-HELP-CLEAR
  SA-BLOCK-SETUP
  HOST-APP-DISCOVER
  0 TO i
  BEGIN  i TGT-MAPN @ <  WHILE
    i CELLS TGT-OLD + @ RELOC-PRIM
    i 1+ TO i
  REPEAT
  ." host-relocs " HOST-RELOC-N @ . CR ;

' (TGT-RELOC) IS TGT-RELOC  \ fill forward reference.
