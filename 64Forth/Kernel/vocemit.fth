\ vocemit.fth — EMITTER vocabulary + native-helper rechain (cold start).
\ Public domain.
\
\ System init (via forth.s .incbin after kernel2): create EMITTER once,
\ move emitter-only boot words out of FORTH so they never appear there,
\ then leave ONLY FORTH DEFINITIONS. Slicer sources FLOAD later under
\ ALSO EMITTER DEFINITIONS (see Emitter/emitter.fth).

ONLY FORTH DEFINITIONS
DECIMAL

DOC" EMITTER ( -- ) vocabulary for the native-code emitter / slicer; execute to ALSO it"
VOCABULARY EMITTER

\ --- Move a header from FORTH-WORDLIST into another wid (same hash thread) ---

: VOC-WID  ( vocab-xt -- wid )
  2 CELLS + ;

: (WL-UNLINK#)  ( xt wid -- thread )
  {: xt wid | slot pred -- :}
  DICT-THREADS 0 DO
    wid I CELLS + TO slot
    BEGIN  slot @ DUP TO pred  WHILE
      pred xt = IF
        pred >LINK @  slot !
        I UNLOOP EXIT
      THEN
      pred >LINK TO slot
    REPEAT
  LOOP
  -1 ;

: (WL-LINK#)  ( xt wid thread -- )
  {: xt wid th | head -- :}
  th 0< IF  ." XT>WL: not in FORTH" CR ABORT  THEN
  wid th CELLS + TO head
  head @  xt >LINK !
  xt head ! ;

: XT>WL  ( xt wid -- )
  OVER FORTH-WORDLIST (WL-UNLINK#)
  (WL-LINK#) ;

: EMITTER-WID  ( -- wid )  ['] EMITTER VOC-WID ;

: >EMITTER  ( xt -- )  EMITTER-WID XT>WL ;

\ Move a FORTH-resident xt into EMITTER if it is still in FORTH (reload-safe).
: FORTH>EMITTER  ( c-addr u -- )
  2DUP FORTH-WORDLIST SEARCH-WORDLIST
  DUP 0= IF  DROP 2DROP EXIT  THEN
  DROP >R 2DROP R> >EMITTER ;

\ Native helpers that exist only for the emitter / CALL-NATIVE path.
S" ALLOCATE-EXEC"    FORTH>EMITTER
S" FREE-EXEC"        FORTH>EMITTER
S" MPROTECT"         FORTH>EMITTER
S" ICACHE-INVAL"     FORTH>EMITTER
S" JIT-WPROTECT"     FORTH>EMITTER
S" CALL-NATIVE"      FORTH>EMITTER
S" CALL-NATIVE-LEAF" FORTH>EMITTER
S" NATIVE-SMOKE"     FORTH>EMITTER

\ ITC runtime entry points exposed as names for the slicer (not user words).
\ DOCOL-ADDR / DOCON-ADDR / *-ADDR / CODE-BOUNDS stay in FORTH for SEE.
S" (NEXT)"           FORTH>EMITTER
S" (DOCOL)"          FORTH>EMITTER
S" (DOVAR)"          FORTH>EMITTER
S" (DOCON)"          FORTH>EMITTER
S" (DODOES)"         FORTH>EMITTER

\ FLAG_EMM CODE helpers: shared asm spans BL'd from other boot prims.
\ Reloc embeds pure (no ADRP) ones under /EMIT-STANDALONE; host-tied → NOP.
S" (UDIVMOD128)"          FORTH>EMITTER
S" (LOCAL-FRAME-EXIT)"    FORTH>EMITTER
S" (FILE-OP-CALL)"        FORTH>EMITTER
S" (LOCAL-COMPILE-RESET)" FORTH>EMITTER
S" (LOCAL-ADD-NAME)"      FORTH>EMITTER
S" (LOCAL-LOOKUP)"        FORTH>EMITTER
S" (LOCAL-FINALIZE)"      FORTH>EMITTER
S" (CURSOR-LOAD)"         FORTH>EMITTER
S" (CURSOR-STORE)"        FORTH>EMITTER
S" (SOURCE-END)"          FORTH>EMITTER
S" (PUTCHAR)"             FORTH>EMITTER
S" (GETCHAR)"             FORTH>EMITTER
S" (WRITE-STDOUT)"        FORTH>EMITTER
S" (PRINT-STRING)"        FORTH>EMITTER
S" (READ-LINE)"           FORTH>EMITTER
S" (NEXT-WORD)"           FORTH>EMITTER
S" (FIND-WORD)"           FORTH>EMITTER
S" (COMPILE-CELL)"        FORTH>EMITTER
S" (.)"                   FORTH>EMITTER
S" (U.)"                  FORTH>EMITTER
S" (LOAD-BASE)"           FORTH>EMITTER
S" (DIGIT-CHAR)"          FORTH>EMITTER
S" (I64>STR)"             FORTH>EMITTER
S" (U64>STR)"             FORTH>EMITTER

\ Rechain helpers: put EMITTER on the order first so we can keep calling them
\ while they are moved one by one.
ALSO EMITTER
' FORTH>EMITTER >EMITTER
' VOC-WID       >EMITTER
' (WL-UNLINK#)  >EMITTER
' (WL-LINK#)    >EMITTER
' XT>WL         >EMITTER
' EMITTER-WID   >EMITTER
' >EMITTER      >EMITTER

ONLY FORTH DEFINITIONS
