\ xref.fth — 64Forth adaptation of TCOM REF.FTH
\
\ Classic REF (Leon Dent; modified by Tom Zimmer for F-PC / TCOM) walks
\ every vocabulary and lists colon (and DEFER) words that reference a
\ given name. Same idea on 64Forth wordlists.
\
\ Cold-loaded: Kernel/forth.s .incbin "xref.fth" (after vocsys.fth).
\ Original TCOM source: Library/TCOM/REF.FTH (unchanged).
\
\ Use (always present after boot):
\   REF DUP
\   XREF WINDOW
\   USEDIN +
\   CALLS EXECUTE
\   ANYWORDS / ANYWORDS OVER   ( all vocabs; optional filter )
\   BL WORD FINDANY   ( c-addr -- xtn … xt1 n )
\
\ Wordlists scanned: FORTH plus every named VOCABULARY (via FORTH traverse),
\ plus any extra wids currently in GET-ORDER. Avoids the raw WORDLISTS
\ registry, which can contain garbage pointers that crash SEARCH/TRAVERSE.
\
\ Space pauses (Space/Return continues; Esc or Q aborts).
\ Needs KEY fed during console evaluate (Esc/Space) — see KernelBridge.
\
\ Public domain (same spirit as REF.FTH).
.( Loading: xref.fth) CR
ONLY FORTH DEFINITIONS
DECIMAL

32 CONSTANT FINDANY-MAX
CREATE FINDANY-BUF  FINDANY-MAX CELLS ALLOT
VARIABLE FINDANY-CNT
VARIABLE FA-CA
VARIABLE FA-U

32 CONSTANT XREF-WID-MAX
CREATE XREF-WIDS  XREF-WID-MAX CELLS ALLOT
CREATE XREF-WID-NTS  XREF-WID-MAX CELLS ALLOT  \ VOCABULARY nt per wid (0=FORTH/bare)
VARIABLE XREF-WIDN

VARIABLE XREF-XT          \ target xt we are hunting
VARIABLE XREF-N           \ hits printed
VARIABLE XREF-STOP        \ nonzero → abort scan
VARIABLE XREF-WID-TMP     \ wid while resolving vocabulary name
VARIABLE XREF-VOC-FOUND   \ true once .WID-NAME printed a VOCABULARY name

\ --- wordlist set (FORTH + named VOCABULARYs + search order) ----------------

: XREF-XT-OK?  ( xt -- flag )
  $10000 U>
;

\ wid is a pointer to thread heads — reject null/low garbage (XFETCH 0x8/0x10).
: XREF-WID-OK?  ( wid -- flag )
  $10000 U>
;

\ Heads must be 0 or a plausible xt — rejects WORDLISTS garbage like a huge
\ non-pointer that still passes XREF-WID-OK?.
: XREF-WID-SANE?  ( wid -- flag )
  DUP XREF-WID-OK? 0= IF DROP FALSE EXIT THEN
  DICT-THREADS 0 ?DO
    DUP I CELLS + @ ?DUP IF
      XREF-XT-OK? 0= IF DROP FALSE UNLOOP EXIT THEN
    THEN
  LOOP DROP TRUE
;

: XREF-WID-HAS?  ( wid -- flag )
  \ ?DO: plain DO with count 0 runs the body once here (stale-buf false hit).
  XREF-WIDN @ 0 ?DO
    DUP XREF-WIDS I CELLS + @ = IF DROP TRUE UNLOOP EXIT THEN
  LOOP DROP FALSE
;

\ Add wid with optional VOCABULARY nt (0 for FORTH / bare wordlist).
: XREF-WID-ADD-NT  ( nt wid -- )
  DUP XREF-WID-SANE? 0= IF 2DROP EXIT THEN
  DUP XREF-WID-HAS? IF 2DROP EXIT THEN
  XREF-WIDN @ XREF-WID-MAX >= IF 2DROP EXIT THEN
  XREF-WIDN @ >R
  XREF-WIDS R@ CELLS + !
  XREF-WID-NTS R> CELLS + !
  1 XREF-WIDN +!
;

: XREF-WID-ADD  ( wid -- )
  0 SWAP XREF-WID-ADD-NT
;

\ VOCABULARY words live in FORTH; their wid is at nt + 2 CELLS (same as FP).
\ Record nt alongside wid so titles need no second FORTH walk.
: XREF-COLLECT-VOC  ( nt -- cont )
  DUP XREF-XT-OK? 0= IF DROP TRUE EXIT THEN
  DUP DOCOL? IF DROP TRUE EXIT THEN
  DUP CELL+ @ ['] FP CELL+ @ = IF
    DUP 2 CELLS + XREF-WID-ADD-NT
  ELSE DROP THEN
  TRUE
;

\ FORTH + every named VOCABULARY + current search-order wids.
: XREF-COLLECT-WIDS  ( -- )
  0 XREF-WIDN !
  FORTH-WORDLIST XREF-WID-ADD
  ['] XREF-COLLECT-VOC FORTH-WORDLIST TRAVERSE-WORDLIST
  GET-ORDER 0 ?DO XREF-WID-ADD LOOP
;

\ Print wid title from cached VOCABULARY nt when possible.
\ Must use the stack index — not I — so it is safe inside TRAVERSE visitors.
: XREF-.WID-NAME-I  ( i -- )
  DUP CELLS XREF-WID-NTS + @ ?DUP IF NIP NAME>STRING TYPE EXIT THEN
  CELLS XREF-WIDS + @
  DUP FORTH-WORDLIST = IF DROP ." FORTH" EXIT THEN
  DROP ." (wordlist)"
;

\ --- FINDANY: counted name → xts in those wordlists -------------------------

: FINDANY-HAS?  ( xt -- flag )
  \ ?DO required: 0 0 DO runs once and compares against stale FINDANY-BUF[0].
  FINDANY-CNT @ 0 ?DO
    DUP FINDANY-BUF I CELLS + @ = IF DROP TRUE UNLOOP EXIT THEN
  LOOP DROP FALSE
;

: FINDANY-ADD  ( xt -- )
  DUP XREF-XT-OK? 0= IF DROP EXIT THEN
  DUP FINDANY-HAS? IF DROP EXIT THEN
  FINDANY-CNT @ FINDANY-MAX >= IF DROP EXIT THEN
  FINDANY-BUF FINDANY-CNT @ CELLS + !
  1 FINDANY-CNT +!
;

\ FINDANY ( c-addr -- xtn … xt1 n )
\ Counted string (WORD style). Unique xts; n=0 if not found.
: FINDANY  ( c-addr -- xtn … xt1 n )
  COUNT FA-U ! FA-CA !
  0 FINDANY-CNT !
  FA-U @ 0= IF 0 EXIT THEN
  XREF-COLLECT-WIDS
  XREF-WIDN @ 0 ?DO
    FA-CA @ FA-U @
    XREF-WIDS I CELLS + @ SEARCH-WORDLIST       \ 0 | xt flag
    IF FINDANY-ADD ELSE DROP THEN               \ IF ate flag
  LOOP
  FINDANY-CNT @ 0 ?DO
    FINDANY-BUF I CELLS + @
  LOOP
  FINDANY-CNT @
;

\ --- pause ------------------------------------------------------------------

: XREF-STOPKEY?  ( c -- flag )
  DUP 27 = OVER [CHAR] q = OR SWAP [CHAR] Q = OR
;

: XREF-?PAUSE  ( -- )
  XREF-STOP @ IF EXIT THEN
  KEY? 0= IF EXIT THEN
  KEY
  DUP XREF-STOPKEY? IF DROP -1 XREF-STOP ! EXIT THEN
  BL = IF
    BEGIN
      KEY
      DUP XREF-STOPKEY? IF DROP -1 XREF-STOP ! EXIT THEN
      DUP BL = OVER 13 = OR IF DROP EXIT THEN
      DROP
    AGAIN
  THEN
;

\ --- vocabulary name for a wid ----------------------------------------------

: XREF-VOCAB?  ( nt -- flag )
  DUP XREF-XT-OK? 0= IF DROP FALSE EXIT THEN
  DUP DOCOL? IF DROP FALSE EXIT THEN
  CELL+ @ ['] FP CELL+ @ =
;

: XREF-MATCH-VOC  ( nt -- cont )
  DUP XREF-VOCAB? IF
    DUP 2 CELLS + XREF-WID-TMP @ = IF
      NAME>STRING TYPE
      -1 XREF-VOC-FOUND !
      FALSE EXIT
    THEN
  THEN
  DROP TRUE
;

: XREF-.WID-NAME  ( wid -- )
  DUP FORTH-WORDLIST = IF DROP ." FORTH" EXIT THEN
  XREF-WID-TMP !
  0 XREF-VOC-FOUND !
  ['] XREF-MATCH-VOC FORTH-WORDLIST TRAVERSE-WORDLIST
  XREF-VOC-FOUND @ 0= IF ." (wordlist)" THEN
;

\ --- colon / DEFER body scan ------------------------------------------------

: XREF-BR?  ( xt -- flag )
  DUP BRANCH-ADDR = IF DROP TRUE EXIT THEN
  0BRANCH-ADDR =
;

: XREF-HIT-COLON?  ( xt -- flag )
  >BODY
  BEGIN
    DUP @ EXIT-ADDR = IF DROP FALSE EXIT THEN
    DUP @ LIT-ADDR = IF
      CELL+ CELL+
    ELSE DUP @ SLIT-ADDR = IF
      CELL+ DUP @ >R CELL+ R> + ALIGNED
    ELSE DUP @ XREF-BR? IF
      CELL+ CELL+
    ELSE
      DUP @ XREF-XT @ = IF DROP TRUE EXIT THEN
      CELL+
    THEN THEN THEN
  AGAIN
;

: XREF-DEFER?  ( xt -- flag )
  DUP DOCOL? IF DROP FALSE EXIT THEN
  CELL+ @ ['] SEE CELL+ @ =
;

: XREF-.HIT  ( xt -- )
  NAME>STRING TYPE
  1 XREF-N +!
  XREF-N @ 4 MOD 0= IF CR ELSE 2 SPACES THEN
  XREF-?PAUSE
;

: XREF-ONE  ( nt -- cont )
  XREF-STOP @ IF DROP FALSE EXIT THEN
  XREF-?PAUSE
  XREF-STOP @ IF DROP FALSE EXIT THEN
  DUP XREF-XT-OK? 0= IF DROP TRUE EXIT THEN
  DUP XREF-XT @ = IF DROP TRUE EXIT THEN
  DUP DOCOL? IF
    DUP XREF-HIT-COLON? IF XREF-.HIT ELSE DROP THEN
  ELSE DUP XREF-DEFER? IF
    DUP DEFER@ XREF-XT @ = IF XREF-.HIT ELSE DROP THEN
  ELSE
    DROP
  THEN THEN
  XREF-STOP @ 0=
;

: XREF-WID  ( wid -- )
  XREF-STOP @ IF DROP EXIT THEN
  DUP XREF-WID-OK? 0= IF DROP EXIT THEN
  ['] XREF-ONE SWAP TRAVERSE-WORDLIST
;

: (XREF)  ( -- )
  0 XREF-N !
  0 XREF-STOP !
  XREF-COLLECT-WIDS
  CR ." * SPACE=pause  Esc or Q=stop *" CR
  XREF-WIDN @ 0 ?DO
    XREF-STOP @ IF LEAVE THEN
    CR ." Searching: " I XREF-.WID-NAME-I CR
    XREF-WIDS I CELLS + @ XREF-WID
  LOOP
  CR XREF-N @ U. ." words printed" CR
;

\ Leaf after last / or \ (VIEW-PATH may be a long absolute path).
: XREF-LEAF  ( c-addr u -- c-addr' u' )
  DUP 0= IF EXIT THEN
  DUP
  BEGIN
    1- DUP 0< IF DROP EXIT THEN          \ ca u i
    2 PICK OVER + C@
    DUP [CHAR] / = SWAP [CHAR] \ = OR IF
      1+                                 \ ca u leaf-off
      >R SWAP R@ + SWAP R> -             \ (ca+off) (u-off)
      EXIT
    THEN
  AGAIN
;

\ Print "leaf:line" from VIEW stamp, or "(no source)" if unstamped.
: XREF-.LOC  ( xt -- )
  DUP VIEW-FILE# ?DUP 0= IF DROP ." (no source)" EXIT THEN
  VIEW-PATH DUP 0= IF 2DROP DROP ." (no source)" EXIT THEN
  XREF-LEAF TYPE
  [CHAR] : EMIT
  VIEW-LINE 0 .R
;

: XREF-ONE-TARGET  ( xt -- )
  DUP XREF-XT-OK? 0= IF DROP EXIT THEN
  XREF-XT !
  CR ." -------- references to: "
  XREF-XT @ DUP NAME>STRING TYPE SPACE XREF-.LOC
  ."  --------" CR
  (XREF)
;

: REF  ( "<spaces>name" -- )
  BL WORD
  DUP C@ 0= IF DROP CR ." REF needs a name" CR EXIT THEN
  FINDANY
  DUP 0= IF DROP CR ." Undefined word" CR -13 THROW THEN
  DUP >R
  0 ?DO DROP LOOP
  R>
  DUP 1 > IF
    CR ." Found " DUP U. ." definitions:" CR
    DUP 0 ?DO
      FINDANY-BUF I CELLS + @
      DUP NAME>STRING TYPE SPACE ." (" XREF-.LOC ." )"
      I 1+ OVER < IF ." , " THEN
    LOOP CR
  THEN
  0 ?DO
    XREF-STOP @ IF LEAVE THEN
    FINDANY-BUF I CELLS + @ XREF-ONE-TARGET
  LOOP
;

: ANYREF REF ;
: XREF   REF ;
: USEDIN REF ;
: CALLS  REF ;

\ --- ANYWORDS: WORDS-like listing across every XREF vocabulary --------------
\ Headers only (TRAVERSE names). One pass per wid — no body walk, no second
\ FORTH scan for vocabulary titles (nts cached at collect). Pause every 32 names.

64 CONSTANT AW-FILTER-MAX
CREATE AW-FILTER  AW-FILTER-MAX ALLOT
VARIABLE AW-FILTER-U
VARIABLE AW-H-CA
VARIABLE AW-H-U
VARIABLE AW-COL
VARIABLE AW-SEC-N
VARIABLE AW-HDR?                  \ true once section header printed
VARIABLE AW-CUR-I                 \ current wid index for title

: AW-SET-FILTER  ( c-addr -- )   \ counted string from WORD (may be empty)
  COUNT DUP AW-FILTER-MAX > IF DROP AW-FILTER-MAX THEN
  DUP AW-FILTER-U !
  0 ?DO DUP I + C@ UPC AW-FILTER I + C! LOOP DROP
;

: AW-AT-EQ?  ( off -- flag )     \ haystack at off equals filter (upc)
  AW-FILTER-U @ 0 ?DO
    AW-H-CA @ OVER I + + C@ UPC
    AW-FILTER I + C@ <> IF DROP FALSE UNLOOP EXIT THEN
  LOOP DROP TRUE
;

\ Case-insensitive substring match against optional filter (empty = all).
: AW-MATCH?  ( nt -- flag )
  AW-FILTER-U @ 0= IF DROP TRUE EXIT THEN
  NAME>STRING AW-H-U ! AW-H-CA !
  AW-H-U @ AW-FILTER-U @ < IF FALSE EXIT THEN
  AW-H-U @ AW-FILTER-U @ - 1+ 0 ?DO
    I AW-AT-EQ? IF TRUE UNLOOP EXIT THEN
  LOOP FALSE
;

: AW-?PAUSE  ( -- )
  XREF-N @ 31 AND 0= IF XREF-?PAUSE THEN
;

: AW-.HDR  ( -- )
  AW-HDR? @ IF EXIT THEN
  -1 AW-HDR? !
  CR ." --- " AW-CUR-I @ XREF-.WID-NAME-I ."  ---" CR
  0 AW-COL !
;

: AW-ONE  ( nt -- cont )
  XREF-STOP @ IF DROP FALSE EXIT THEN
  AW-?PAUSE
  XREF-STOP @ IF DROP FALSE EXIT THEN
  DUP XREF-XT-OK? 0= IF DROP TRUE EXIT THEN
  DUP AW-MATCH? 0= IF DROP TRUE EXIT THEN
  AW-.HDR
  NAME>STRING TYPE
  1 XREF-N +!
  1 AW-SEC-N +!
  1 AW-COL +!
  AW-COL @ 8 = IF CR 0 AW-COL ! ELSE 2 SPACES THEN
  XREF-STOP @ 0=
;

: AW-DO-WID  ( i -- )
  XREF-STOP @ IF DROP EXIT THEN
  DUP AW-CUR-I !
  XREF-WIDS OVER CELLS + @
  DUP XREF-WID-OK? 0= IF 2DROP EXIT THEN
  0 AW-SEC-N !
  0 AW-HDR? !
  0 AW-COL !
  ['] AW-ONE SWAP TRAVERSE-WORDLIST
  DROP                               \ drop index
  AW-COL @ IF CR THEN
  AW-SEC-N @ IF ." (" AW-SEC-N @ 0 .R SPACE ." words)" CR THEN
;

\ ANYWORDS [filter] — list names in FORTH + every named VOCABULARY (and
\ GET-ORDER extras). Same wid set as REF. Optional substring filter like WORDS.
: ANYWORDS  ( "<optional-filter>" -- )
  BL WORD AW-SET-FILTER
  0 XREF-N !
  0 XREF-STOP !
  XREF-COLLECT-WIDS
  CR ." * SPACE=pause  Esc or Q=stop *" CR
  XREF-WIDN @ 0 ?DO
    XREF-STOP @ IF LEAVE THEN
    I AW-DO-WID
  LOOP
  CR XREF-N @ U. ." words printed" CR
;

.( Finished Loading: xref.fth) CR
