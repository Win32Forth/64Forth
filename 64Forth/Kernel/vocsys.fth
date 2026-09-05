\ vocsys.fth — SYSVOC + generalized FORTH→vocab rechain (cold start).
\ Public domain.
\
\ Loaded after app-points.fth (see forth.s). Creates SYSVOC, moves
\ non-user support words out of FORTH into SYSVOC / EDITOR / GRAPHICS,
\ then leaves ONLY FORTH DEFINITIONS.
\
\ EMITTER rechain stays in vocemit.fth (earlier in the cold blob).

ONLY FORTH DEFINITIONS
DECIMAL

\ --- Generalized header move (FORTH → any wid / VOCABULARY) ---

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
  th 0< IF  ." XT>WL: not in source wid" CR ABORT  THEN
  wid th CELLS + TO head
  head @  xt >LINK !
  xt head ! ;

: XT>WL-FROM  ( xt from-wid to-wid -- )
  {: xt from to -- :}
  xt from (WL-UNLINK#)
  xt to ROT (WL-LINK#) ;

: XT>WL  ( xt to-wid -- )
  {: xt to -- :}
  xt FORTH-WORDLIST to XT>WL-FROM ;

: FORTH>WL  ( c-addr u wid -- )
  >R 2DUP FORTH-WORDLIST SEARCH-WORDLIST
  DUP 0= IF  DROP 2DROP R> DROP EXIT  THEN
  DROP >R 2DROP R> R> XT>WL ;

: FORTH>VOC  ( c-addr u vocab-xt -- )
  VOC-WID FORTH>WL ;

DOC" SYSVOC ( -- ) vocabulary for system / support words; execute to ALSO it"
VOCABULARY SYSVOC

: FORTH>SYSVOC   ( c-addr u -- )  ['] SYSVOC   FORTH>VOC ;
: FORTH>EDITOR   ( c-addr u -- )  ['] EDITOR   FORTH>VOC ;
: FORTH>GRAPHICS ( c-addr u -- )  ['] GRAPHICS FORTH>VOC ;

\ --- Phase A: SEE, vocab dump, SUBSTITUTE / XCHAR temps, host guts → SYSVOC ---

S" (SEE-BR?)"       FORTH>SYSVOC
S" (SEE-HDR)"       FORTH>SYSVOC
S" (SEE-PRIM)"      FORTH>SYSVOC
S" (SEE-STEP)"      FORTH>SYSVOC

S" (THREAD-DEPTH)"  FORTH>SYSVOC
S" (CONTEXT)"       FORTH>SYSVOC
S" (WID.THREADS)"   FORTH>SYSVOC
S" (TYPE-FIELD)"    FORTH>SYSVOC
S" (IS-VOCAB)"      FORTH>SYSVOC
S" (SHOW-VOCAB)"    FORTH>SYSVOC
S" (VW-T)"          FORTH>SYSVOC
S" (VW-F)"          FORTH>SYSVOC
S" (CHK-VOC-WID)"   FORTH>SYSVOC
S" (VOCAB-WID?)"    FORTH>SYSVOC
S" (SHOW-BARE-WL)"  FORTH>SYSVOC
S" (SHOW-WL-REG)"   FORTH>SYSVOC

S" (SUBST-MAX)"     FORTH>SYSVOC
S" (SUBST-NAMES)"   FORTH>SYSVOC
S" (SUBST-TEXTS)"   FORTH>SYSVOC
S" (SUBST-CNT)"     FORTH>SYSVOC
S" (SF-I)"          FORTH>SYSVOC
S" (SS-I)"          FORTH>SYSVOC
S" (SUBST-NAME)"    FORTH>SYSVOC
S" (SUBST-TEXT)"    FORTH>SYSVOC
S" (SUBST-FIND)"    FORTH>SYSVOC
S" (UE-B)"          FORTH>SYSVOC
S" (UE-D)"          FORTH>SYSVOC
S" (SS-DEST)"       FORTH>SYSVOC
S" (SS-MAX)"        FORTH>SYSVOC
S" (SS-LEN)"        FORTH>SYSVOC
S" (SS-N)"          FORTH>SYSVOC
S" (SS-ERR)"        FORTH>SYSVOC
S" (SS-NBUF)"       FORTH>SYSVOC
S" (SS-ADD)"        FORTH>SYSVOC
S" (SS-ADDS)"       FORTH>SYSVOC
S" (SS-LOOK)"       FORTH>SYSVOC

S" (XQ-SZ)"         FORTH>SYSVOC
S" (XQ-MAX)"        FORTH>SYSVOC
S" (TGA)"           FORTH>SYSVOC
S" (TGU)"           FORTH>SYSVOC
S" (TGP)"           FORTH>SYSVOC
S" -TRAILING-GARBAGE" FORTH>SYSVOC
S" (XH-A)"          FORTH>SYSVOC
S" (XH-U)"          FORTH>SYSVOC
S" (XWA)"           FORTH>SYSVOC
S" (XWU)"           FORTH>SYSVOC
S" (XWS)"           FORTH>SYSVOC

S" (BLOCK-SEEK)"    FORTH>SYSVOC
S" (BLOCK-WRITE)"   FORTH>SYSVOC
S" (BLOCK-READ)"    FORTH>SYSVOC

S" (XFACILITY-OP-GO)" FORTH>SYSVOC
S" (FILE-OP-CALL)"    FORTH>SYSVOC

\ Compiler / block / locals / float / debug internals (not user words).
S" (DOES>)"            FORTH>SYSVOC
S" (F-OP)"             FORTH>SYSVOC
S" (DO)"               FORTH>SYSVOC
S" (?DO)"              FORTH>SYSVOC
S" (LOOP)"             FORTH>SYSVOC
S" (+LOOP)"            FORTH>SYSVOC
S" (COMP,)"            FORTH>SYSVOC
S" (BLOCK-BUF)"        FORTH>SYSVOC
S" (BLOCK-NR)"         FORTH>SYSVOC
S" (BLOCK-UPD)"        FORTH>SYSVOC
S" (CATCH-OK)"         FORTH>SYSVOC
S" (LOCAL-FRAME-EXIT)" FORTH>SYSVOC
S" DBG-SHOW-XT"        FORTH>SYSVOC
S" DBG-HL-XT"          FORTH>SYSVOC
S" DBG-INLINE"         FORTH>SYSVOC
S" TDBG-ARM-KEYS"      FORTH>SYSVOC
S" TDBG-DISARM-KEYS"   FORTH>SYSVOC

S\" (.)"               FORTH>SYSVOC
S\" (U.)"              FORTH>SYSVOC
S\" (C\")"             FORTH>SYSVOC
S" (LOAD-ENTER)"       FORTH>SYSVOC
S" (LOAD-RUN)"         FORTH>SYSVOC
S" (LOCAL!)"           FORTH>SYSVOC
S" (LOCAL@)"           FORTH>SYSVOC

\ --- Phase B: editor host hooks → EDITOR ---

S" (SZ-VIEW-CELLS)"   FORTH>EDITOR
S" (SZ-CLICK)"        FORTH>EDITOR
S" (SZ-CLIP!)"        FORTH>EDITOR
S" (SZ-CLIP@)"        FORTH>EDITOR
S" (SZ-PATH@)"        FORTH>EDITOR
S" (SZ-CMD@)"         FORTH>EDITOR
S" (SZ-CONSOLE-EMIT)" FORTH>EDITOR
S" (SZ-CMD-DONE)"     FORTH>EDITOR
S" (SZ-SAVE-AS-REQ)"  FORTH>EDITOR
S" (SZ-OPEN-REQ)"     FORTH>EDITOR
S" (SZ-CLR-APP-QUIT)" FORTH>EDITOR
S" (FACILITY-SIZE)"   FORTH>EDITOR

\ --- Phase C: graphics host hooks → GRAPHICS ---

S" (APP-OPEN)"   FORTH>GRAPHICS
S" (APP-CLOSE)"  FORTH>GRAPHICS
S" (APP-BLIT)"   FORTH>GRAPHICS
S" (APP-PBLIT)"  FORTH>GRAPHICS
S" (APP-KEY?)"   FORTH>GRAPHICS
S" (APP-KEY)"    FORTH>GRAPHICS
S" (APP-NAME)"   FORTH>GRAPHICS
S" (APP-TONE)"   FORTH>GRAPHICS
S" (APP-PUMP)"   FORTH>GRAPHICS

\ Rechain helpers into SYSVOC (ALSO so we can keep calling them while moving).
ALSO SYSVOC
: >SYSVOC  ( xt -- )  ['] SYSVOC VOC-WID XT>WL ;
' FORTH>GRAPHICS >SYSVOC
' FORTH>EDITOR   >SYSVOC
' FORTH>SYSVOC   >SYSVOC
' FORTH>VOC      >SYSVOC
' FORTH>WL       >SYSVOC
' XT>WL          >SYSVOC
' XT>WL-FROM     >SYSVOC
' (WL-LINK#)     >SYSVOC
' (WL-UNLINK#)   >SYSVOC
' VOC-WID        >SYSVOC
' >SYSVOC        >SYSVOC

ONLY FORTH DEFINITIONS
