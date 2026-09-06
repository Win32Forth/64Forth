\ target.fth — emitter step 2
\ Requires reach.fth
\ Public domain.

\ Loaded under EMITTER DEFINITIONS (see emitter.fth).
DECIMAL

DEFER TGT-RELOC
DEFER HOST-BIND

: TGT-RELOC-NONE  ( -- )  ;
' TGT-RELOC-NONE  IS TGT-RELOC

: HOST-BIND-NONE  ( -- )  ;
' HOST-BIND-NONE  IS HOST-BIND

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

VARIABLE TGT-DATA         \ RW ALLOCATE base (stand-alone data segment)
VARIABLE TGT-DATA-ORG
VARIABLE TGT-DATA-DP
VARIABLE TGT-DATA-LIMIT
VARIABLE TGT-DATA-ALLOC

: TGT-DATA-CLOSE  ( -- )
  TGT-DATA @ IF  TGT-DATA @ FREE DROP  THEN
  0 TGT-DATA !  0 TGT-DATA-ORG !  0 TGT-DATA-DP !
  0 TGT-DATA-LIMIT !  0 TGT-DATA-ALLOC ! ;

: TGT-CLOSE  ( -- )
  TGT @ IF
    TGT @ TGT-ALLOC @ FREE-EXEC DROP
  THEN
  0 TGT !  0 TGT-ORG !  0 TGT-DP !  0 TGT-LIMIT !  0 TGT-END !
  0 TGT-ALLOC !
  TGT-DATA-CLOSE ;

: TGT-DATA-OPEN  ( u -- )
  TGT-DATA-CLOSE
  DUP TGT-DATA-ALLOC !
  DUP ALLOCATE IF  DROP ." data ALLOCATE failed" CR ABORT  THEN
  DUP TGT-DATA !
  DUP TGT-DATA-ORG !
  DUP TGT-DATA-DP !
  + TGT-DATA-LIMIT ! ;

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

\ CREATE/VALUE/CONSTANT/DOES>: default identity map (in-process TGT-RUN).
\ /EMIT-STANDALONE copies each data region into the target image (Phase 1).
FALSE VALUE ?EMIT-STANDALONE
: /EMIT-STANDALONE  ( -- )  TRUE  TO ?EMIT-STANDALONE ;
: /EMIT-HOSTDATA    ( -- )  FALSE TO ?EMIT-STANDALONE ;

\ Phase 2b: leave MAGIC|slot .quads unbound so SAVE-IMAGE can persist them.
\ Default false — TGT-BUILD still HOST-BINDs for interactive TGT-RUN.
FALSE VALUE ?EMIT-UNBOUND
: /EMIT-UNBOUND  ( -- )  TRUE  TO ?EMIT-UNBOUND ;
: /EMIT-BOUND    ( -- )  FALSE TO ?EMIT-UNBOUND ;

VARIABLE TGT-DATA-BYTES

\ Phase 2b: absolute pointer cells in the image (ITC xts, CFAs).
\ Blind u64 walks corrupt ARM prims; SAVE-IMAGE persists this table instead.
1024 CONSTANT #PTR-RELOC
CREATE PTR-RELOC-OFF  #PTR-RELOC CELLS ALLOT
CREATE PTR-RELOC-SPC  #PTR-RELOC ALLOT   \ 0=code 1=data
VARIABLE PTR-RELOC-N
: PTR-RELOC-CLEAR  ( -- )  0 PTR-RELOC-N ! ;

: PTR-RELOC-ADD  ( addr space -- )
  {: a sp -- :}
  PTR-RELOC-N @ #PTR-RELOC U< 0= IF
    ." too many ptr relocs" CR ABORT
  THEN
  a  PTR-RELOC-N @ CELLS PTR-RELOC-OFF + !
  sp PTR-RELOC-N @ PTR-RELOC-SPC + C!
  1 PTR-RELOC-N +! ;

: PTR,  ( x -- )  \ TGT, of an absolute pointer into the image
  TGT-HERE 0 PTR-RELOC-ADD
  TGT, ;

\ End of a data word = smallest HFA of another reachable xt above this CFA,
\ else CFA+24 (does_ip + one cell) for a lone VALUE/CONSTANT.
: DATA-END  ( xt -- addr )
  {: xt | best i w h -- :}
  0 TO best
  0 TO i
  BEGIN  i REACH-N @ <  WHILE
    i CELLS REACH-XTS + @ TO w
    w xt <> IF
      w HFA TO h
      h xt U> IF
        best 0= IF  h TO best
        ELSE  h best U< IF  h TO best  THEN
        THEN
      THEN
    THEN
    i 1+ TO i
  REPEAT
  best 0= IF  xt 24 +  ELSE  best  THEN ;

: DATA-SPAN  ( xt -- addr u )
  DUP DATA-END  OVER - ;

: RESERVE-IMPORT  ( xt -- )
  ?EMIT-STANDALONE 0= IF  DUP MAP! EXIT  THEN
  {: xt | new u -- :}
  TGT-DATA-DP @ 7 + -8 AND DUP TGT-DATA-DP !  TO new
  xt DATA-SPAN NIP TO u
  u 0= IF
    ." data: empty span for " xt NAME>STRING TYPE CR ABORT
  THEN
  u 7 + -8 AND TO u
  new u + DUP TGT-DATA-LIMIT @ U> IF
    ." data: overflow" CR ABORT
  THEN
  TGT-DATA-DP !
  u TGT-DATA-BYTES +!
  xt new MAP! ;

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

\ Stand-alone 0BRANCH: host prim ADRPs to data_stack SP0 (in-process only).
\ Emit a guard-free body; STITCH still places a trailing B after host span.
: B-ABS,  ( target -- )
  TGT-HERE - 2 ARSHIFT
  $03FFFFFF AND $14000000 OR  TGT-W, ;

: WRITE-0BRANCH-SA  ( -- )
  $AA1403E0 TGT-W,                    \ MOV X0, X20
  $F84086D4 TGT-W,                    \ LDR X20, [X22], #8
  $B4000060 TGT-W,                    \ CBZ X0, +3
  $91002273 TGT-W,                    \ ADD X19, X19, #8
  ['] (NEXT) MAP-FIND 8 + B-ABS,
  $F9400260 TGT-W,                    \ LDR X0, [X19]
  $8B000273 TGT-W,                    \ ADD X19, X19, X0
  ['] (NEXT) MAP-FIND 8 + B-ABS,
  ;

: WRITE-PRIM  ( xt -- )
  DUP NAME>STRING TYPE SPACE ." prim" CR
  DUP MAP-FIND DUP 0= IF ." no map" CR ABORT THEN
  DUP TGT-DP !                 \ ( xt new )
  DUP 8 + OVER !               \ CFA cell → payload; ( xt new )
  DUP 0 PTR-RELOC-ADD          \ record CFA pointer cell
  DROP                         \ ( xt )
  8 TGT-ALLOT
  ?EMIT-STANDALONE IF
    DUP 0BRANCH-ADDR = IF
      DROP WRITE-0BRANCH-SA EXIT
    THEN
  THEN
  PRIM-SPAN COPY-BYTES ;

\ --- DOES> fragments (stand-alone) ---------------------------------------
\ Host does_ip points at an ITC xt list ending in EXIT. Slice once per
\ unique host IP into the code image (appended at TGT-END) and retarget.

16 CONSTANT #DOES-FRAG
CREATE DOES-HOST  #DOES-FRAG CELLS ALLOT
CREATE DOES-NEW   #DOES-FRAG CELLS ALLOT
VARIABLE DOES-N
: DOES-CLEAR  ( -- )  0 DOES-N ! ;

: DOES-FIND  ( host-ip -- new|0 )
  {: hip | i -- :}
  0 TO i
  BEGIN  i DOES-N @ <  WHILE
    i CELLS DOES-HOST + @ hip = IF
      i CELLS DOES-NEW + @ EXIT
    THEN
    i 1+ TO i
  REPEAT
  0 ;

: MAP-CELL  ( old -- )
  DUP MAP-FIND ?DUP IF  NIP PTR,  ELSE
    ." unmapped " NAME>STRING TYPE CR ABORT
  THEN ;

: DOES-EMIT  ( host-ip -- new )
  {: hip | new -- :}
  DOES-N @ #DOES-FRAG U< 0= IF
    ." does: too many fragments" CR ABORT
  THEN
  TGT-END @ 7 + -8 AND TGT-DP !
  TGT-HERE TO new
  hip
  BEGIN
    DUP @ MAP-CELL
    DUP @ ['] EXIT = IF
      DROP
      TGT-HERE TGT-END !
      hip DOES-N @ CELLS DOES-HOST + !
      new DOES-N @ CELLS DOES-NEW + !
      1 DOES-N +!
      new EXIT
    THEN
    8 +
  AGAIN ;

: DOES-SLICE  ( host-ip -- new )
  DUP DOES-FIND ?DUP IF  NIP EXIT  THEN
  DOES-EMIT ;

\ If addr falls inside a mapped DATA-WORD's host span, slide it to the
\ sliced copy (for LIT PFAs from TO, etc.).
: DATA-REBASE  ( addr -- addr' flag )
  {: a | i w new -- :}
  0 TO i
  BEGIN  i TGT-MAPN @ <  WHILE
    i CELLS TGT-OLD + @ TO w
    w DATA-WORD? IF
      a w U< 0= IF
        a w DATA-END U< IF
          w MAP-FIND DUP 0= IF  DROP a FALSE EXIT  THEN  TO new
          a w - new +  TRUE EXIT
        THEN
      THEN
    THEN
    i 1+ TO i
  REPEAT
  a FALSE ;

: LIT-PAYLOAD,  ( host-lit -- )
  \ LIT cells live in the code image (colon bodies).
  DATA-REBASE IF  TGT-HERE 0 PTR-RELOC-ADD  THEN
  TGT, ;

\ Copy CFA..DATA-END into the RW data segment; retarget CFA to sliced
\ (DOVAR)/(DOCON)/(DODOES). DOES> does_ip is sliced into code (DOES-SLICE).
: WRITE-IMPORT  ( xt -- )
  ?EMIT-STANDALONE 0= IF  DROP EXIT  THEN
  {: xt | new u code -- :}
  xt NAME>STRING TYPE SPACE ." data" SPACE
  xt DATA-SPAN NIP DUP TO u . CR
  xt MAP-FIND DUP 0= IF  ." no map" CR ABORT  THEN  TO new
  xt new u MOVE
  \ Prefer sliced runtime CFA if already written; else host code addr
  \ (WRITE order writes prims before imports — see TGT-WRITE).
  xt DOVAR? IF  ['] (DOVAR)
  ELSE xt DOCON? IF  ['] (DOCON)
  ELSE  ['] (DODOES)  THEN THEN
  DUP MAP-FIND ?DUP IF  NIP @  ELSE  @  THEN  TO code
  code new !
  new 1 PTR-RELOC-ADD
  xt DODOES? IF
    new 8 + @ DOES-SLICE
    new 8 + !
    new 8 + 1 PTR-RELOC-ADD
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
      MAP-CELL 8 + DUP @ LIT-PAYLOAD, 8 +
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
  @ PTR,
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
    ELSE DUP DATA-WORD? IF
      ?EMIT-STANDALONE IF ." data" ELSE ." import" THEN CR RESERVE-IMPORT
    ELSE                ." prim"   CR RESERVE-PRIM
    THEN THEN
    RI 1+ TO RI
  REPEAT
  ." maps=" TGT-MAPN @ . CR
  ?EMIT-STANDALONE IF  ." data-bytes " TGT-DATA-BYTES @ . CR  THEN
  TGT-HERE TGT-END ! ;

: TGT-WRITE  {: | RI -- :}
  \ 1) CODE prims first so DATA CFA patches can MAP-FIND (DOVAR)/…
  0 TO RI
  BEGIN  RI REACH-N @ <  WHILE
    RI CELLS REACH-XTS + @
    DUP COLON-WORD? IF  DROP
    ELSE DUP DATA-WORD? IF  DROP
    ELSE  WRITE-PRIM  THEN THEN
    RI 1+ TO RI
  REPEAT
  \ 2) DATA into RW segment
  0 TO RI
  BEGIN  RI REACH-N @ <  WHILE
    RI CELLS REACH-XTS + @
    DUP DATA-WORD? IF  WRITE-IMPORT  ELSE DROP THEN
    RI 1+ TO RI
  REPEAT
  \ 3) Colon bodies
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
  0 TGT-DATA-BYTES !
  PTR-RELOC-CLEAR
  DOES-CLEAR
  REACH-FROM
  ['] (DOCOL) (MARK)
  ['] (NEXT)  (MARK)
  ['] EXIT    (MARK)
  ?EMIT-STANDALONE IF
    ['] (DOVAR)  (MARK)
    ['] (DOCON)  (MARK)
    ['] (DODOES) (MARK)
  THEN
  65536 TGT-OPEN
  ?EMIT-STANDALONE IF  65536 TGT-DATA-OPEN  THEN
  ." opened " TGT-ORG @ U.  TGT-LIMIT @ U.  ."  cap " TGT-SIZE . CR
  TGT-RESERVE
  ." reserved " TGT-SIZE . CR
  TGT-WRITE
  TGT-STITCH
  TGT-RELOC
  \ Phase 2a: bind MAGIC|slot .quads while image is still RW (before R+X).
  \ /EMIT-UNBOUND (Phase 2b): skip bind so SAVE-IMAGE keeps MAGIC|slot;
  \ TGT-RUN binds later via HOST-BIND-IF-NEEDED.
  ?EMIT-UNBOUND 0= IF  HOST-BIND  THEN
  TGT-PROTECT
  ." written " TGT-SIZE . CR
  ?EMIT-UNBOUND IF  ." unbound (MAGIC|slot)" CR  THEN
  ?EMIT-STANDALONE IF
    ." standalone data-bytes " TGT-DATA-BYTES @ . CR
    ." data-seg " TGT-DATA-ORG @ U. TGT-DATA-DP @ U. CR
  THEN
  ;

: TGT-DUMP  ( -- )
  HEX
  TGT-ORG @
  BEGIN  DUP TGT-END @ U<  WHILE
    CR DUP U. SPACE  DUP @ U.
    8 +
  REPEAT DROP
  DECIMAL CR ;
  
