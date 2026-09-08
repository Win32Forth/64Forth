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
\ 6 name 7 tone 8 pump 9 MS@/gettimeofday 10 malloc 11 free
\ 12 BI-MUL 13 BI-DIVMOD 14 BI-ISQRT (blr x9 hooks → HOST-APP veneers).
\ .quad = HOST-CALL-MAGIC|slot until HOST-BIND.

$C0DE000000000000 CONSTANT HOST-CALL-MAGIC
15 CONSTANT #HOST-APP
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

\ LDR Xt, label (64-bit literal); |to-from| < 1MiB, 8-aligned.
: ENC-LDR64-LIT  ( from to rt -- insn )
  {: from to rt -- :}
  to from - 2 ARSHIFT
  DUP $3FFFF > OVER $FFFC0000 AND 0<> OR IF
    ." sa-bss: LDR-lit out of range" CR ABORT
  THEN
  $7FFFF AND 5 LSHIFT
  rt $1F AND OR  $58000000 OR ;

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
\   (SA-FLOAT)  — FP in-block F-stack (registered below)
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
\ Window builds (?EMIT-WINDOW): ITC FORTH EMIT/TYPE are remapped to GRAPHICS
\ (see IO-REMAP). CODE that still calls _sa_putchar/_sa_write keeps write(1)
\ here until a GRAPHICS-backed host hook is bound into this pool.
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
  pool 0 PTR-RELOC-ADD            \ BASE PFA (data abs)
  z pool 8 + !            \ emit_hook_ptr → zero cell
  pool 8 + 0 PTR-RELOC-ADD        \ code abs of z
  z pool 16 + !           \ emit_buf_ptr  → zero cell
  pool 16 + 0 PTR-RELOC-ADD
  ." sa-print pool @ " pool U.
  ?EMIT-WINDOW IF  ."  (window: ITC I/O→GRAPHICS; sa hooks still write1)"  THEN
  CR ;

\ After MOVE of SA-FILES: last 32 bytes are the literal pool.
\ hook_ptr → in-block zero cell (forces Darwin svc; 0 would ADRP host).
: SA-FILES-PATCH-POOL  ( new u -- )
  {: new u | pool z -- :}
  u 32 U< IF  ." sa-files: block too small" CR ABORT  THEN
  new u + 32 - TO pool
  pool 8 + TO z           \ sa_files_zero_cell
  0 z !
  z pool !                \ hook_ptr → zero → Darwin multiplex
  pool 0 PTR-RELOC-ADD            \ code abs of z
  0 pool 16 + !
  0 pool 24 + !
  ." sa-files pool @ " pool U. CR ;

\ After MOVE of SA-FLOAT: last 32 bytes are the literal pool.
\ hook_ptr → zero (local path); state_ptr → RW TGT-DATA F-stack
\ (depth + prec + 16 cells). Image code is RX at run — cannot keep stack in TEXT.
: SA-FLOAT-STATE-CELL  ( -- addr )
  TGT-DATA @ 0= IF  ." sa-float: no data seg" CR ABORT  THEN
  TGT-DATA-DP @ 7 + -8 AND
  DUP 144 ERASE                    \ depth + prec + 16*8
  6 OVER 8 + !                     \ default PRECISION
  DUP 144 + TGT-DATA-DP !
  144 TGT-DATA-BYTES +! ;

: SA-FLOAT-PATCH-POOL  ( new u -- )
  {: new u | pool z st -- :}
  u 32 U< IF  ." sa-float: block too small" CR ABORT  THEN
  new u + 32 - TO pool
  pool 8 + TO z
  0 z !
  z pool !                         \ hook_ptr → zero → local FP
  pool 0 PTR-RELOC-ADD             \ code abs of z
  SA-FLOAT-STATE-CELL TO st
  st pool 16 + !                   \ state_ptr → RW data
  pool 16 + 0 PTR-RELOC-ADD
  0 pool 24 + !
  ." sa-float pool @ " pool U. ." state @ " st U. CR ;

: SA-BLOCK-SETUP  ( -- )
  SA-BLOCK-CLEAR
  S" (SA-PRINT)" ['] SA-PRINT-PATCH-POOL SA-BLOCK-REGISTER
  S" (SA-FILES)" ['] SA-FILES-PATCH-POOL SA-BLOCK-REGISTER
  S" (SA-FLOAT)" ['] SA-FLOAT-PATCH-POOL SA-BLOCK-REGISTER
  \ EXIT bls here to pop {: … :} frames. Has ADRP to local_frame_*;
  \ as an SA-BLOCK it is copied and SA-HELP-RELOC-BSS retargets those
  \ cells (already sized by SA-LOCALS-DISCOVER). Leaving it NOP made
  \ nested locals (PI-POOL→PI-ALLOC1) leak frames → garbage ALLOCATE sizes.
  S" (LOCAL-FRAME-EXIT)" 0 SA-BLOCK-REGISTER
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

\ Real (SA-PATCH-BL-HELPER) is defined once below, after SA-HELP-RELOC-BSS.
\ DEFER stays on (SA-PATCH-BL-NOP) until then — avoids a redefine warning.

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

\ --- Window I/O remap (EMIT-WINDOW-APP / ?EMIT-WINDOW) ---------------------
\ App colon bodies keep FORTH EMIT/TYPE/CR/./KEY xts (console compile).
\ At MAP-CELL time those xts become GRAPHICS counterparts so stand-alone
\ output hits G-BUF + (APP-BLIT), not SA-PRINT write(1).
\ SA-PRINT's emit_hook pool is the *native* remap point for CODE that already
\ calls _sa_putchar/_sa_write (e.g. .); ITC apps need this xt remap until
\ EMIT/TYPE are retargeted into SA-PRINT and the pool feeds GRAPHICS.

: (GFX-IO-XT)  ( c-addr u -- xt )
  2DUP GRAPHICS-WID SEARCH-WORDLIST
  ?DUP 0= IF  ." window-io: missing GRAPHICS " TYPE CR ABORT  THEN
  DROP >R 2DROP R> ;

S" EMIT"  (GFX-IO-XT) CONSTANT GFX-EMIT
S" TYPE"  (GFX-IO-XT) CONSTANT GFX-TYPE
S" CR"    (GFX-IO-XT) CONSTANT GFX-CR
S" SPACE" (GFX-IO-XT) CONSTANT GFX-SPACE
S" ."     (GFX-IO-XT) CONSTANT GFX-DOT
S" KEY"   (GFX-IO-XT) CONSTANT GFX-KEY
S" KEY?"  (GFX-IO-XT) CONSTANT GFX-KEY?

\ FORTH console I/O (search order at Emitter load — not GRAPHICS).
' EMIT  CONSTANT FORTH-EMIT
' TYPE  CONSTANT FORTH-TYPE
' CR    CONSTANT FORTH-CR
' SPACE CONSTANT FORTH-SPACE
' .     CONSTANT FORTH-DOT
' KEY   CONSTANT FORTH-KEY
' KEY?  CONSTANT FORTH-KEY?

: (IO-REMAP)  ( xt -- xt' )
  ?EMIT-WINDOW 0= IF  EXIT  THEN
  DUP FORTH-EMIT  = IF  DROP GFX-EMIT  EXIT  THEN
  DUP FORTH-TYPE  = IF  DROP GFX-TYPE  EXIT  THEN
  DUP FORTH-CR    = IF  DROP GFX-CR    EXIT  THEN
  DUP FORTH-SPACE = IF  DROP GFX-SPACE EXIT  THEN
  DUP FORTH-DOT   = IF  DROP GFX-DOT   EXIT  THEN
  DUP FORTH-KEY   = IF  DROP GFX-KEY   EXIT  THEN
  DUP FORTH-KEY?  = IF  DROP GFX-KEY?  EXIT  THEN
  ;

' (IO-REMAP) IS IO-REMAP

\ Pull GRAPHICS I/O into the reach graph so MAP-FIND succeeds after remap.
: REACH-CONTINUE  ( -- )
  BEGIN
    REACH-WORK @ REACH-N @ <
  WHILE
    REACH-WORK @ CELLS REACH-XTS + @ SCAN-ONE
    1 REACH-WORK +!
  REPEAT ;

: (TGT-MARK-WINDOW-IO)  ( -- )
  ?EMIT-WINDOW 0= IF  EXIT  THEN
  GFX-EMIT  (MARK)
  GFX-TYPE  (MARK)
  GFX-CR    (MARK)
  GFX-SPACE (MARK)
  GFX-DOT   (MARK)
  GFX-KEY   (MARK)
  GFX-KEY?  (MARK)
  REACH-CONTINUE
  ;

' (TGT-MARK-WINDOW-IO) IS TGT-MARK-WINDOW-IO

: HOST-APP-DISCOVER  ( -- )
  S" (APP-OPEN)"  HOST-APP-XT 0 HOST-APP-SET
  S" (APP-CLOSE)" HOST-APP-XT 1 HOST-APP-SET
  S" (APP-BLIT)"  HOST-APP-XT 2 HOST-APP-SET
  S" (APP-PBLIT)" HOST-APP-XT 3 HOST-APP-SET
  S" (APP-KEY?)"  HOST-APP-XT 4 HOST-APP-SET
  S" (APP-KEY)"   HOST-APP-XT 5 HOST-APP-SET
  S" (APP-NAME)"  HOST-APP-XT 6 HOST-APP-SET
  S" (APP-TONE)"  HOST-APP-XT 7 HOST-APP-SET
  S" (APP-PUMP)"  HOST-APP-XT 8 HOST-APP-SET
  \ MS@ bls _gettimeofday — without a slot, SA NOP'd the BL and timers froze
  \ (tetra WAIT-DROP never exited except on SPACE/alldown).
  ['] MS@ 9 HOST-APP-SET
  \ ALLOCATE/FREE bl libc — SA would NOP those BLs and crash on first heap use.
  ['] ALLOCATE 10 HOST-APP-SET
  ['] FREE 11 HOST-APP-SET ;
  \ Slots 12–14 (BI-*) are wired by SA-FIX-BI-HOOKS (blr x9, not bl host).

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

\ --- SA-BSS: host ADRP+ADD → RW TGT-DATA via LDR-lit ---------------------
\ Stand-alone cannot keep host BSS (throw_handler, host_tmp*, debug_*, …).
\ Each distinct host absolute gets a zeroed TGT-DATA span; ADRP+ADD is
\ replaced with LDR-lit from a PTR-RELOC'd .quad (ADRP cannot reach a
\ distant ALLOCATE data segment). cfa_catch_ok is filled after map.
\
\ Default span is one cell. Locals runtime BSS is larger (see
\ SA-LOCALS-DISCOVER): a 1-cell stand-in for local_frames made {: digits :}
\ store/fetch into the wrong place so (LOCAL@) returned 0 — PI-COMPUTE then
\ aborted with "digits must be > 0" even when 250 was on the stack.

128 CONSTANT #SA-BSS
CREATE SA-BSS-HOST  #SA-BSS CELLS ALLOT
CREATE SA-BSS-DATA  #SA-BSS CELLS ALLOT
CREATE SA-BSS-LEN   #SA-BSS CELLS ALLOT   \ byte length of each span
VARIABLE SA-BSS-N
VARIABLE SA-XC   \ host cfa_catch_ok (for FIX-CFA)
VARIABLE SA-DC   \ data cfa_catch_ok

\ Locals BSS sizes must match Kernel/forth.s LOCAL_* layout.
8    CONSTANT /SA-LOC-DEPTH     \ local_frame_depth
4096 CONSTANT /SA-LOC-FRAMES    \ LOCAL_FRAME_MAX * LOCAL_MAX * 8
128  CONSTANT /SA-LOC-AUX       \ local_frame_rsp / local_frame_n

\ host_tmp0 is .skip 32 in forth.s (BI-DIVMOD stores rem at +24).
32   CONSTANT /SA-HOST-TMP

: ADD64-IMM12?  ( insn -- flag )
  $FFC00000 AND $91000000 = ;

: ADD64-IMM12@  ( insn -- imm )
  10 RSHIFT $FFF AND ;

: ADD64-IMM12!  ( imm insn -- insn' )
  $FFC003FF AND  SWAP $FFF AND 10 LSHIFT OR ;

\ Absolute symbol at code+off if ADRP ; ADD Xd,Xn,#imm12 follows.
: ADRP-ADD-ABS  ( code off -- abs | 0 )
  {: code off | insn -- :}
  code off + W@ TO insn
  insn ADRP? 0= IF  0 EXIT  THEN
  code off 4 + + W@ ADD64-IMM12? 0= IF  0 EXIT  THEN
  insn code off + ADRP-TGT
  code off 4 + + W@ ADD64-IMM12@ + ;

\ ADRP cannot reach TGT-DATA on a distant heap (±4GiB). LDR-lit + PTR-RELOC.
: PATCH-ADRP-ADD  ( npc new-abs -- )
  {: npc abs | insn rt lit -- :}
  npc W@ TO insn
  insn $1F AND TO rt
  npc 4 + W@ ADD64-IMM12? 0= IF
    ." sa-bss: expected ADD after ADRP @ " npc U. CR ABORT
  THEN
  TGT-END-ALIGN8
  TGT-END @ TO lit
  abs VEN-,
  lit 0 PTR-RELOC-ADD
  npc lit rt ENC-LDR64-LIT npc W!
  ARM-NOP npc 4 + W! ;

: SA-BSS-RESET  ( -- )
  0 SA-BSS-N !
  0 SA-XC !  0 SA-DC ! ;

: SA-BSS-FIND  ( host -- data|0 )
  {: h | i -- :}
  0 TO i
  BEGIN  i SA-BSS-N @ <  WHILE
    i CELLS SA-BSS-HOST + @ h = IF
      i CELLS SA-BSS-DATA + @ EXIT
    THEN
    i 1+ TO i
  REPEAT
  0 ;

\ Allocate / register a host BSS symbol with an explicit byte span.
\ If already registered but too small (e.g. 1-cell default before
\ SA-LOCALS-DISCOVER), grow by allocating a new span and updating the slot.
: SA-BSS-ENSURE-SZ  ( host u -- data )
  {: h u | d i old -- :}
  u 7 + -8 AND TO u
  u 0= IF  8 TO u  THEN
  0 TO i
  BEGIN  i SA-BSS-N @ <  WHILE
    i CELLS SA-BSS-HOST + @ h = IF
      i CELLS SA-BSS-DATA + @ TO d
      i CELLS SA-BSS-LEN  + @ TO old
      old u U< 0= IF  d EXIT  THEN
      \ undersized: allocate a larger span and retarget the slot
      TGT-DATA @ 0= IF  ." sa-bss: no data seg" CR ABORT  THEN
      TGT-DATA-DP @ 7 + -8 AND TO d
      d u + TGT-DATA-LIMIT @ U> IF  ." sa-bss: data overflow" CR ABORT  THEN
      d u 0 FILL
      d u + TGT-DATA-DP !
      u old - TGT-DATA-BYTES +!
      d i CELLS SA-BSS-DATA + !
      u i CELLS SA-BSS-LEN  + !
      d EXIT
    THEN
    i 1+ TO i
  REPEAT
  TGT-DATA @ 0= IF  ." sa-bss: no data seg" CR ABORT  THEN
  SA-BSS-N @ #SA-BSS U< 0= IF  ." sa-bss: too many cells" CR ABORT  THEN
  TGT-DATA-DP @ 7 + -8 AND TO d
  d u + TGT-DATA-LIMIT @ U> IF  ." sa-bss: data overflow" CR ABORT  THEN
  d u 0 FILL
  d u + TGT-DATA-DP !
  u TGT-DATA-BYTES +!
  h SA-BSS-N @ CELLS SA-BSS-HOST + !
  d SA-BSS-N @ CELLS SA-BSS-DATA + !
  u SA-BSS-N @ CELLS SA-BSS-LEN  + !
  1 SA-BSS-N +!
  d ;

: SA-BSS-ENSURE  ( host -- data )
  8 SA-BSS-ENSURE-SZ ;

\ LOCAL-INIT ADRP order (forth.s): depth, frames, rsp, n.
\ Pre-size those spans so nested {: … :} (PI./PI-COMPUTE) keep digits.
\ Use VARIABLEs (not locals): nested {: … :} around ADRP-ADD-ABS can
\ fault under the agent/host when the callee also uses locals.
VARIABLE SA-LOC-CODE
VARIABLE SA-LOC-U
VARIABLE SA-LOC-OFF
VARIABLE SA-LOC-N
VARIABLE SA-LOC-ABS

: SA-LOCALS-DISCOVER  ( -- )
  ['] LOCAL-INIT PRIM-SPAN SA-LOC-U ! SA-LOC-CODE !
  0 SA-LOC-OFF !  0 SA-LOC-N !
  BEGIN  SA-LOC-OFF @ 4 + SA-LOC-U @ <  SA-LOC-N @ 4 < AND  WHILE
    SA-LOC-CODE @ SA-LOC-OFF @ ADRP-ADD-ABS SA-LOC-ABS !
    SA-LOC-ABS @ IF
      SA-LOC-N @ 0 = IF  SA-LOC-ABS @ /SA-LOC-DEPTH  SA-BSS-ENSURE-SZ DROP  THEN
      SA-LOC-N @ 1 = IF  SA-LOC-ABS @ /SA-LOC-FRAMES SA-BSS-ENSURE-SZ DROP  THEN
      SA-LOC-N @ 2 = IF  SA-LOC-ABS @ /SA-LOC-AUX    SA-BSS-ENSURE-SZ DROP  THEN
      SA-LOC-N @ 3 = IF  SA-LOC-ABS @ /SA-LOC-AUX    SA-BSS-ENSURE-SZ DROP  THEN
      1 SA-LOC-N +!
      8 SA-LOC-OFF +!
    ELSE
      4 SA-LOC-OFF +!
    THEN
  REPEAT
  SA-LOC-N @ 4 < IF
    ." sa-bss: LOCAL-INIT ADRP discover failed (n=" SA-LOC-N @ . ." )" CR ABORT
  THEN
  ." sa-bss locals depth/frames/rsp/n sized" CR ;

\ BI-MUL/DIVMOD/ISQRT are kernel BOOT_WORDs on FORTH.
\ Use VARIABLEs (not locals): nested {: … :} around ADRP-ADD-ABS / PATCH
\ faults under agent — same rule as SA-LOCALS-DISCOVER.

VARIABLE SA-BI-CODE
VARIABLE SA-BI-U
VARIABLE SA-BI-OFF
VARIABLE SA-BI-ABS
VARIABLE SA-BI-NEW
VARIABLE SA-BI-NPC
VARIABLE SA-BI-INSN
VARIABLE SA-BI-NFIX
VARIABLE SA-BI-XT
VARIABLE SA-BI-SLOT

\ Pre-size host_tmp0 to 32 bytes (BI-DIVMOD uses +24). First ADRP in BI-MUL.
: SA-HOST-TMP-DISCOVER  ( -- )
  ['] BI-MUL PRIM-SPAN SA-BI-U ! SA-BI-CODE !
  0 SA-BI-OFF !
  BEGIN  SA-BI-OFF @ 4 + SA-BI-U @ <  WHILE
    SA-BI-CODE @ SA-BI-OFF @ ADRP-ADD-ABS SA-BI-ABS !
    SA-BI-ABS @ IF
      SA-BI-ABS @ /SA-HOST-TMP SA-BSS-ENSURE-SZ DROP
      ." sa-bss host_tmp0 " /SA-HOST-TMP . ." bytes" CR
      EXIT
    THEN
    4 SA-BI-OFF +!
  REPEAT
  ." sa-bss: BI-MUL host_tmp0 discover failed" CR ABORT
  ;

\ BI-* : ldr x9,[hook]; cbz x9,1f; …; blr x9
\ SA zeroes the hook → CBZ always skips → PI-COMPUTE spins (Dock bounce).
\ NOP the CBZ; retarget BLR X9 to HOST-APP veneer (slots 12–14).
$D63F0120 CONSTANT ARM-BLR-X9

: CBZ-X9?  ( insn -- flag )
  $FF00001F AND  $B4000009 = ;

: SA-FIX-BI-HOOK  ( xt slot -- )
  ?EMIT-STANDALONE 0= IF  2DROP EXIT  THEN
  SA-BI-SLOT !  SA-BI-XT !
  SA-BI-XT @ MAP-FIND DUP 0= IF  DROP EXIT  THEN
  8 + SA-BI-NEW !
  SA-BI-XT @ PRIM-SPAN NIP SA-BI-U !
  0 SA-BI-OFF !  0 SA-BI-NFIX !
  BEGIN  SA-BI-OFF @ SA-BI-U @ <  WHILE
    SA-BI-NEW @ SA-BI-OFF @ + SA-BI-NPC !
    SA-BI-NPC @ W@ SA-BI-INSN !
    SA-BI-INSN @ CBZ-X9? IF  ARM-NOP SA-BI-NPC @ W!  THEN
    SA-BI-INSN @ ARM-BLR-X9 = IF
      SA-BI-NPC @ $94000000 SA-BI-SLOT @ PATCH-BL-HOST
      1 SA-BI-NFIX !
    THEN
    4 SA-BI-OFF +!
  REPEAT
  SA-BI-NFIX @ 0= IF
    ." sa-bi: no BLR X9 in " SA-BI-XT @ NAME>STRING TYPE CR ABORT
  THEN
  ." sa-bi " SA-BI-XT @ NAME>STRING TYPE ."  -> slot " SA-BI-SLOT @ . CR
  ;

: SA-FIX-BI-HOOKS  ( -- )
  ?EMIT-STANDALONE 0= IF  EXIT  THEN
  ['] BI-MUL    12 SA-FIX-BI-HOOK
  ['] BI-DIVMOD 13 SA-FIX-BI-HOOK
  ['] BI-ISQRT  14 SA-FIX-BI-HOOK
  ;


\ npc at ADRP; resolve full host abs from original prim bytes at code+off.
: SA-BSS-TRY-PATCH  ( npc code off -- flag )
  {: npc code off | abs -- :}
  code off ADRP-ADD-ABS TO abs
  abs 0= IF  FALSE EXIT  THEN
  npc abs SA-BSS-ENSURE PATCH-ADRP-ADD
  TRUE ;

\ First three ADRP+ADD in CATCH → ensure shared cells; remember cfa_catch_ok.
: SA-EXCEPT-DISCOVER  ( -- )
  {: code u off n abs -- :}
  SA-XC @ IF  EXIT  THEN
  ['] CATCH PRIM-SPAN TO u TO code
  0 TO off  0 TO n
  BEGIN  off 4 + u <  WHILE
    code off ADRP-ADD-ABS TO abs
    abs IF
      abs SA-BSS-ENSURE DROP
      n 1 = IF
        abs SA-XC !
        abs SA-BSS-FIND SA-DC !
      THEN
      n 1+ TO n
      off 8 + TO off
    ELSE
      off 4 + TO off
    THEN
  REPEAT
  n 3 < IF
    ." sa-bss: CATCH ADRP discover failed (n=" n . ." )" CR ABORT
  THEN
  ." sa-bss catch cells n=" SA-BSS-N @ .
  ."  cfa-ok data=" SA-DC @ U. CR ;

: SA-EXCEPT-FIX-CFA  ( -- )
  ?EMIT-STANDALONE 0= IF  EXIT  THEN
  SA-DC @ 0= IF  EXIT  THEN
  S" (CATCH-OK)" ['] SYSVOC 2 CELLS + SEARCH-WORDLIST
  0= IF  ." sa-bss: (CATCH-OK) missing" CR ABORT  THEN
  MAP-FIND ?DUP 0= IF
    ." sa-bss: (CATCH-OK) not mapped" CR ABORT
  THEN
  SA-DC @ !
  ." sa-bss cfa-ok fixed " SA-DC @ @ U. CR ;

: SA-EXCEPT-SETUP  ( -- )
  ?EMIT-STANDALONE 0= IF  EXIT  THEN
  SA-BSS-RESET
  SA-LOCALS-DISCOVER
  SA-HOST-TMP-DISCOVER
  SA-EXCEPT-DISCOVER ;

\ After SA-HELP MOVE (+ optional pool patch): retarget host BSS ADRP+ADD.
\ In-span ADRP is re-encoded into the copy; out-of-span → SA-BSS LDR-lit.
: SA-HELP-RELOC-BSS  ( host new u -- )
  {: host new u | off abs npc -- :}
  0 TO off
  BEGIN  off 4 + u <  WHILE
    host off ADRP-ADD-ABS TO abs
    abs IF
      new off + TO npc
      abs host u IN-SPAN? IF
        npc W@  npc  abs host - new +  npc W@ ENC-ADRP npc W!
      ELSE
        npc abs SA-BSS-ENSURE PATCH-ADRP-ADD
      THEN
      off 8 + TO off
    ELSE
      off 4 + TO off
    THEN
  REPEAT
  ;

\ Install once SA-HELP-RELOC-BSS exists (DEFER was NOP above).
: (SA-PATCH-BL-HELPER)  ( npc tgt -- )
  {: npc tgt | code u new patch -- :}
  tgt SA-BLOCK-OF TO u TO code
  code IF
    code SA-HELP-FIND ?DUP IF
      TO new
    ELSE
      code u SA-HELP-COPY TO new
      code SA-BLOCK-PATCH-OF TO patch
      patch IF  new u patch EXECUTE  THEN
      code new u SA-HELP-RELOC-BSS
    THEN
    npc  new tgt code - +  ENC-BL-TO npc W!
    EXIT
  THEN
  tgt EMM-SPAN-OF TO u TO code
  code 0= IF  ARM-NOP npc W!  EXIT  THEN
  code u SPAN-SA-PURE? 0= IF  ARM-NOP npc W!  EXIT  THEN
  code SA-HELP-FIND ?DUP IF
    TO new
  ELSE
    code u SA-HELP-COPY TO new
    code new u SA-HELP-RELOC-BSS
  THEN
  npc  new tgt code - +  ENC-BL-TO npc W!
  ;
' (SA-PATCH-BL-HELPER) IS SA-PATCH-BL-HELPER

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
        ?EMIT-STANDALONE insn ADRP? AND IF
          npc code off SA-BSS-TRY-PATCH 0= IF
            npc insn tgt PATCH
          THEN
        ELSE
          npc insn tgt PATCH
        THEN
      THEN
    THEN
    off 4 + TO off
  REPEAT ;

: (TGT-RELOC)  {: | i -- :}
  HOST-RELOC-CLEAR
  SA-HELP-CLEAR
  SA-BLOCK-SETUP
  SA-EXCEPT-SETUP
  HOST-APP-DISCOVER
  0 TO i
  BEGIN  i TGT-MAPN @ <  WHILE
    i CELLS TGT-OLD + @ RELOC-PRIM
    i 1+ TO i
  REPEAT
  SA-EXCEPT-FIX-CFA
  SA-FIX-BI-HOOKS
  ." host-relocs " HOST-RELOC-N @ . CR ;

' (TGT-RELOC) IS TGT-RELOC  \ fill forward reference.
