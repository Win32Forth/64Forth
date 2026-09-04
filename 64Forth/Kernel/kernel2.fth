\ --- 4b. Pictured numeric output ---
DOC" HLD ( -- addr ) pictured output pointer variable"
VARIABLE HLD
DOC" <# ( -- ) begin pictured numeric output"
: <# PAD 256 + HLD ! ;
DOC" HOLD ( char -- ) insert char into pictured output"
: HOLD -1 HLD +! HLD @ C! ;
DOC" #> ( xd -- c-addr u ) end pictured numeric, return string"
: #> 2DROP HLD @ PAD 256 + OVER - ;
DOC" # ( ud1 -- ud2 ) convert one digit of pictured numeric output"
: # 0 BASE @ UM/MOD >R BASE @ UM/MOD R> ROT DUP 9 > IF 7 + THEN 48 + HOLD ;
DOC" #S ( ud1 -- ud2 ) convert remaining digits of pictured numeric output"
: #S BEGIN # 2DUP OR 0= UNTIL ;
DOC" SIGN ( n -- ) insert minus sign if n<0 into pictured"
: SIGN 0< IF 45 HOLD THEN ;
DOC" UD. ( ud -- ) print unsigned double"
: UD. <# #S #> TYPE SPACE ;
DOC" D. ( n -- ) print signed single in current BASE via pictured output"
: D. DUP 0< IF NEGATE 0 <# #S 45 HOLD #> ELSE 0 <# #S #> THEN TYPE SPACE ;

DOC" FILL ( addr u b -- ) fill u bytes at addr with b"
: FILL >R BEGIN DUP WHILE OVER R@ SWAP C! SWAP 1+ SWAP 1- REPEAT R> DROP 2DROP ;
DOC" ERASE ( addr u -- ) fill u bytes at addr with zero"
: ERASE 0 FILL ;
DOC" CMOVE ( c-addr1 c-addr2 u -- ) copy u chars from c-addr1 to c-addr2 (low→high)"
: CMOVE BEGIN DUP WHILE >R OVER C@ OVER C! CHAR+ SWAP CHAR+ SWAP R> 1- REPEAT DROP 2DROP ;
DOC" CMOVE> ( c-addr1 c-addr2 u -- ) copy u chars from c-addr1 to c-addr2 (high→low)"
: CMOVE> DUP >R + 1- SWAP R@ + 1- SWAP R> BEGIN DUP WHILE >R OVER C@ OVER C! 1- SWAP 1- SWAP R> 1- REPEAT DROP 2DROP ;
DOC" MOVE ( addr1 addr2 u -- ) copy u bytes"
: MOVE DUP 0= IF DROP 2DROP EXIT THEN >R 2DUP U< IF R> CMOVE> ELSE R> CMOVE THEN ;

DOC" (COMP,) ( xt -- ) compile xt (for POSTPONE)"
: (COMP,) , ;
DOC" POSTPONE ( 'name' -- ) compile compilation semantics of name (immediate)"
: POSTPONE ?COMP BL WORD FIND DUP 0= IF 2DROP EXIT THEN
  1 = IF , ELSE LIT-ADDR , , ['] (COMP,) , THEN ; IMMEDIATE

DOC" CASE ( -- ) start CASE structure (immediate)"
: CASE ?COMP 0 ; IMMEDIATE
DOC" OF ( x x -- | x ) CASE of branch (immediate)"
: OF ?COMP 1+ >R POSTPONE OVER POSTPONE = POSTPONE IF POSTPONE DROP R> ; IMMEDIATE
DOC" ENDOF ( -- ) end of OF, branch to ENDCASE (immediate)"
: ENDOF ?COMP >R POSTPONE ELSE R> ; IMMEDIATE

DOC" [DEFINED] ( 'name' -- flag ) true if name is found (immediate)"
: [DEFINED] BL WORD FIND NIP 0<> ; IMMEDIATE
DOC" [UNDEFINED] ( 'name' -- flag ) true if name is not found (immediate)"
: [UNDEFINED] BL WORD FIND NIP 0= ; IMMEDIATE
DOC" [THEN] ( -- ) end of [IF] (immediate no-op)"
: [THEN] ; IMMEDIATE
DOC" [ELSE] ( -- ) skip to matching [THEN] (immediate)"
: [ELSE]
  1 BEGIN
    BEGIN BL WORD COUNT DUP WHILE
      2DUP S" [IF]" COMPARE 0= IF 2DROP 1+
      ELSE 2DUP S" [ELSE]" COMPARE 0= IF 2DROP 1- DUP IF 1+ THEN
      ELSE 2DUP S" [THEN]" COMPARE 0= IF 2DROP 1- ELSE 2DROP THEN THEN THEN
      DUP 0= IF DROP EXIT THEN
    REPEAT 2DROP REFILL 0= UNTIL DROP ; IMMEDIATE
DOC" [IF] ( flag -- ) interpret if true else skip to [ELSE]/[THEN] (immediate)"
: [IF] 0= IF POSTPONE [ELSE] THEN ; IMMEDIATE
DOC" ENDCASE ( -- ) end CASE, resolve branches (immediate)"
: ENDCASE ?COMP POSTPONE DROP BEGIN DUP WHILE 1- >R POSTPONE THEN R> REPEAT DROP ; IMMEDIATE

\ --- 5. Tools / extensions ---
DOC" DOCOL? ( xt -- flag ) true if colon definition"
: DOCOL? @ DOCOL-ADDR = ;
DOC" ALIAS ( xt 'name' -- ) define name with same CODE field as xt"
: ALIAS CREATE LAST SWAP @ SWAP ! ;
DOC" SYNONYM ( 'newname' 'oldname' -- ) newname behaves as oldname"
: SYNONYM >IN @ >R PARSE-NAME 2DROP ' R> >IN ! ALIAS ;

DOC" (SEE-BR?) ( xt -- flag ) SEE helper: branch/loop xt?"
: (SEE-BR?) >R R@ BRANCH-ADDR = R@ 0BRANCH-ADDR = OR
  R@ ['] (LOOP) = OR R@ ['] (+LOOP) = OR R> DROP ;
DOC" (SEE-HDR) ( xt -- xt ) print C/colon tag, help or name, CR"
: (SEE-HDR) DUP DOCOL? IF 58 EMIT SPACE ELSE 67 EMIT 79 EMIT 68 EMIT 69 EMIT SPACE THEN
  DUP >HELP COUNT DUP IF TYPE ELSE 2DROP DUP NAME>STRING TYPE THEN CR ;
DOC" (SEE-PRIM) ( xt -- ) print (primitive) for non-colon"
: (SEE-PRIM) DROP 40 EMIT 112 EMIT 114 EMIT 105 EMIT 109 EMIT 105 EMIT 116 EMIT 105 EMIT 118 EMIT 101 EMIT 41 EMIT CR ;
DOC" (SEE-STEP) ( addr -- addr' ) decompile one body cell; advances addr"
: (SEE-STEP)
  DUP @ >R
  R@ EXIT-ADDR = IF R> DROP DROP 59 EMIT CR 0 EXIT THEN
  R@ LIT-ADDR = IF R> DROP 8 + DUP @ . SPACE 8 + EXIT THEN
  R@ SLIT-ADDR = IF R> DROP 8 + DUP @ >R 8 + 83 EMIT 34 EMIT SPACE DUP R@ TYPE 34 EMIT SPACE R> + ALIGNED EXIT THEN
  R@ (SEE-BR?) IF R@ NAME>STRING TYPE SPACE R> DROP 8 + DUP @ . SPACE 8 + EXIT THEN
  R@ NAME>STRING TYPE SPACE R> DROP 8 + ;
DOC" SEE ( 'name' -- ) show help and decompile word"
: SEE ' DUP (SEE-HDR) DUP DOCOL? 0= IF (SEE-PRIM) EXIT THEN
  >BODY BEGIN (SEE-STEP) DUP 0= UNTIL DROP ;
DOC" DEBUG ( 'name' -- ) F6 over, F7 into, F8 out, Esc/q abort, Cmd-Shift-Y go"
\ Esc/q aborts with THROW -1; swallow that so we return to the prompt quietly.
: DEBUG ' DBG-ON CATCH DBG-OFF DUP -1 = IF DROP ELSE THROW THEN ;
DOC" HELP ( 'name' -- ) show help and decompile word (same as SEE)"
: HELP SEE ;
DOC" FLOAD ( 'name' -- ) synonym of INCLUDE; load and interpret a file"
' INCLUDE ALIAS FLOAD
DOC" REQUIRE ( 'name' -- ) load file once (PARSE-NAME REQUIRED)"
: REQUIRE PARSE-NAME REQUIRED ;

DOC" .FREE ( -- ) print free dictionary bytes remaining"
: .FREE UNUSED U. SPACE S" bytes free" TYPE CR ;
DOC" .2DIG ( n -- ) print n as 2 decimal digits"
: .2DIG 10 /MOD 48 + EMIT 48 + EMIT ;
DOC" .3DIG ( n -- ) print n as 3 decimal digits"
: .3DIG 100 /MOD 48 + EMIT .2DIG ;
DOC" .ELAPSED ( ms -- ) print ms as HH:MM:SS.mmm"
: .ELAPSED BASE @ >R DECIMAL 1000 /MOD SWAP >R 60 /MOD SWAP >R 60 /MOD SWAP >R
  DUP 10 < IF 48 EMIT THEN 0 <# #S #> TYPE 58 EMIT R> .2DIG 58 EMIT R> .2DIG 46 EMIT R> .3DIG R> BASE ! ;
DOC" ELAPSED ( 'name' -- ) run name once and print elapsed time"
: ELAPSED ' MS@ >R EXECUTE MS@ R> - .ELAPSED CR ;
DOC" ? ( a-addr -- ) display the cell at a-addr (@ .)"
: ? @ . ;

DOC" .H2 ( b -- ) print byte as 2 hex digits"
: .H2 255 AND 0 <# # # #> TYPE ;
DOC" .HA ( addr -- ) print address as 16 hex digits"
: .HA 0 <# # # # # # # # # # # # # # # # # #> TYPE ;
DOC" DUMP-END ( -- addr ) variable end of DUMP range"
VARIABLE DUMP-END
DOC" DUMP-LINE ( addr -- addr' ) dump one line"
: DUMP-LINE
  DUP .HA SPACE SPACE DUP
  16 0 DO DUP I + DUMP-END @ U< IF DUP I + C@ .H2 SPACE ELSE SPACE SPACE SPACE THEN LOOP
  SPACE SPACE
  16 0 DO DUP I + DUMP-END @ U< IF DUP I + C@ DUP BL 127 WITHIN 0= IF DROP BL THEN EMIT ELSE BL EMIT THEN LOOP
  DROP 16 + ;
DOC" DUMP ( addr u -- ) hex dump u bytes from addr (16 per line, ASCII gutter)"
: DUMP BASE @ >R HEX OVER + DUMP-END ! BEGIN DUP DUMP-END @ U< WHILE CR DUMP-LINE REPEAT DROP CR R> BASE ! ;

DOC" */MOD ( n1 n2 n3 -- rem quot ) multiply then divmod"
: */MOD >R M* R> SM/REM ;
DOC" */ ( n1 n2 n3 -- n4 ) multiply to double-cell, divide (quotient)"
: */ */MOD SWAP DROP ;
DOC" ABORT ( -- ) THROW -1 (catchable)"
: ABORT -1 THROW ;
DOC" ABORT quote ( x -- ) if x nonzero type message and THROW -2 (immediate)"
: ABORT" STATE @ IF
    POSTPONE IF POSTPONE S" POSTPONE TYPE POSTPONE CR
    -2 POSTPONE LITERAL POSTPONE THROW POSTPONE THEN
  ELSE 34 PARSE ROT IF TYPE CR -2 THROW THEN 2DROP THEN ; IMMEDIATE

DOC" ANEW ( 'name' -- ) FORGET name if present, then CREATE reload marker"
: ANEW
  >IN @ >R BL WORD FIND IF
    DROP R@ >IN ! S" Reloading module: " TYPE BL WORD COUNT TYPE CR
    R@ >IN ! FORGET
  ELSE
    DROP R@ >IN ! S" Loading module: " TYPE BL WORD COUNT TYPE CR
  THEN R> >IN ! CREATE ;

DOC" ON ( addr -- ) store 1 at addr"
: ON 1 SWAP ! ;
DOC" OFF ( addr -- ) store 0 at addr"
: OFF 0 SWAP ! ;

\ --- 6. Core Ext ---
DOC" U.R ( u n -- ) print u right-justified in n field"
: U.R >R 0 <# #S #> R> OVER - 0 MAX SPACES TYPE ;
DOC" .R ( n n -- ) print n right-justified in field (no trailing space)"
: .R >R DUP ABS 0 <# #S ROT SIGN #> R> OVER - 0 MAX SPACES TYPE ;

DOC" (THREAD-DEPTH) ( head -- n ) count words in one hash chain"
: (THREAD-DEPTH) 0 SWAP BEGIN DUP WHILE SWAP 1+ SWAP 2 CELLS - @ REPEAT DROP ;
DOC" (CONTEXT) ( -- wid ) first search-order wordlist, or FORTH"
: (CONTEXT) GET-ORDER ?DUP 0= IF FORTH-WORDLIST EXIT THEN
  BEGIN DUP 1 > WHILE SWAP DROP 1- REPEAT DROP ;
DOC" (WID.THREADS) ( wid -- ) print all thread depths for wid in aligned columns"
: (WID.THREADS) DICT-THREADS 0 DO DUP I CELLS + @ (THREAD-DEPTH) 5 .R LOOP DROP ;
DOC" .THREADS ( -- ) print CONTEXT wordlist hash-chain depths in aligned columns"
: .THREADS (CONTEXT) (WID.THREADS) CR ;
DOC" (TYPE-FIELD) ( c-addr u n -- ) type string left-justified in field n"
: (TYPE-FIELD) >R 2DUP TYPE NIP R> SWAP - 0 MAX SPACES ;
DOC" (IS-VOCAB) ( nt -- flag ) true if nt was defined by VOCABULARY"
: (IS-VOCAB) CELL+ @ ['] FP CELL+ @ = ;
DOC" (SHOW-VOCAB) ( nt -- true ) print vocabulary name and thread depths"
: (SHOW-VOCAB) DUP (IS-VOCAB) IF DUP NAME>STRING 16 (TYPE-FIELD) 2 CELLS + (WID.THREADS) CR ELSE DROP THEN TRUE ;
VARIABLE (VW-T)  VARIABLE (VW-F)
DOC" (CHK-VOC-WID) ( nt -- cont ) TRAVERSE helper for (VOCAB-WID?)"
: (CHK-VOC-WID) DUP (IS-VOCAB) IF 2 CELLS + (VW-T) @ = IF -1 (VW-F) ! FALSE ELSE TRUE THEN ELSE DROP TRUE THEN ;
DOC" (VOCAB-WID?) ( wid -- flag ) true if wid is a named VOCABULARY head array"
: (VOCAB-WID?) (VW-T) ! 0 (VW-F) ! ['] (CHK-VOC-WID) FORTH-WORDLIST TRAVERSE-WORDLIST (VW-F) @ ;
DOC" (SHOW-BARE-WL) ( wid -- ) print one non-named wordlist from the registry"
: (SHOW-BARE-WL)
  DUP FORTH-WORDLIST = IF DROP EXIT THEN
  DUP (VOCAB-WID?) IF DROP EXIT THEN
  S" (wordlist)" 16 (TYPE-FIELD) (WID.THREADS) CR ;
DOC" (SHOW-WL-REG) ( -- ) print bare WORDLIST entries not already named"
: (SHOW-WL-REG) WORDLISTS 0 ?DO DUP I CELLS + @ (SHOW-BARE-WL) LOOP DROP ;
DOC" .VOCABULARIES ( -- ) list FORTH, VOCABULARY lists, and bare WORDLISTs"
: .VOCABULARIES
  S" FORTH" 16 (TYPE-FIELD) FORTH-WORDLIST (WID.THREADS) CR
  ['] (SHOW-VOCAB) FORTH-WORDLIST TRAVERSE-WORDLIST (SHOW-WL-REG) ;
DOC" .WORDLISTS ( -- ) synonym of .VOCABULARIES"
: .WORDLISTS .VOCABULARIES ;

DOC" HOLDS ( c-addr u -- ) add string to pictured numeric output (prepend via HOLD)"
: HOLDS BEGIN DUP WHILE 1- 2DUP + C@ HOLD REPEAT 2DROP ;
DOC" COMPILE, ( xt -- ) compile the execution token xt"
: COMPILE, , ;
DOC" [COMPILE] ( 'name' -- ) force-compile name even if immediate (immediate)"
: [COMPILE] ?COMP BL WORD FIND 0= IF DROP EXIT THEN DROP , ; IMMEDIATE
DOC" BUFFER: ( u 'name' -- ) create a buffer of u bytes"
: BUFFER: CREATE ALLOT ;
DOC" VALUE ( x 'name' -- ) create a value; change with TO"
: VALUE CREATE , DOES> @ ;
DOC" DEFER ( 'name' -- ) create a deferred word (set with IS)"
: DEFER CREATE ['] ABORT , DOES> @ EXECUTE ;
DOC" DEFER@ ( xt1 -- xt2 ) get the xt that defer xt1 currently executes"
: DEFER@ >BODY CELL+ @ ;
DOC" DEFER! ( xt1 xt2 -- ) set defer xt2 to execute xt1"
: DEFER! >BODY CELL+ ! ;
DOC" IS ( xt 'name' -- ) set DEFER named (immediate)"
: IS STATE @ IF POSTPONE ['] POSTPONE DEFER! ELSE ' DEFER! THEN ; IMMEDIATE
DOC" ACTION-OF ( 'name' -- xt ) xt currently in deferred name (immediate)"
: ACTION-OF STATE @ IF POSTPONE ['] POSTPONE DEFER@ ELSE ' DEFER@ THEN ; IMMEDIATE

DOC" MARKER ( 'name' -- ) restore point: HERE + all FORTH hash heads"
: MARKER
  HERE DICT-THREADS 0 DO LATEST I CELLS + @ LOOP
  CREATE
  DICT-THREADS 1+ 0 DO DICT-THREADS I - PICK , LOOP
  DICT-THREADS 1+ 0 DO DROP LOOP
  DOES>
    DUP @ DP !
    CELL+ DICT-THREADS 0 DO DUP @ LATEST I CELLS + ! CELL+ LOOP DROP ;

\ --- 7. Double-Number ---
DOC" 2CONSTANT ( x1 x2 'name' -- ) create double constant"
: 2CONSTANT CREATE SWAP , , DOES> 2@ ;
DOC" 2VARIABLE ( 'name' -- ) create double variable"
: 2VARIABLE CREATE 0 , 0 , ;
DOC" 2VALUE ( x1 x2 'name' -- ) double value; change with TO"
: 2VALUE CREATE SWAP , , DOES> 2@ ;
DOC" 2LITERAL ( x1 x2 -- ) compile double literal (immediate)"
: 2LITERAL ?COMP SWAP POSTPONE LITERAL POSTPONE LITERAL ; IMMEDIATE
DOC" D. ( d -- ) print signed double with space"
: D. 2DUP D0< IF DNEGATE -1 ELSE 0 THEN >R <# #S R> SIGN #> TYPE SPACE ;
DOC" D.R ( d n -- ) print signed double right-justified"
: D.R >R 2DUP D0< IF DNEGATE -1 ELSE 0 THEN >R <# #S R> SIGN #> R> OVER - 0 MAX SPACES TYPE ;
DOC" M*/ ( d1 n1 +n2 -- d2 ) multiply double by n1 then divide by n2"
: M*/ >R >R D>S R> R> */ S>D ;

\ --- 8. String word set ---
DOC" BLANK ( c-addr u -- ) fill with spaces"
: BLANK BL FILL ;
DOC" -TRAILING ( c-addr u1 -- c-addr u2 ) remove trailing spaces"
: -TRAILING BEGIN DUP WHILE 1- 2DUP + C@ BL <> IF 1+ EXIT THEN REPEAT ;
DOC" SLITERAL ( c-addr u -- ) compile string literal (immediate)"
: SLITERAL ?COMP SLIT-ADDR , DUP ,
  BEGIN DUP WHILE OVER C@ C, 1 /STRING REPEAT 2DROP ALIGN ; IMMEDIATE
DOC" PLACE ( c-addr1 u c-addr2 -- ) copy as counted string at c-addr2"
: PLACE 2DUP 2>R CHAR+ SWAP MOVE 2R> C! ;
32 CONSTANT (SUBST-MAX)
CREATE (SUBST-NAMES) 32 32 * ALLOT
CREATE (SUBST-TEXTS) 32 256 * ALLOT
VARIABLE (SUBST-CNT) 0 (SUBST-CNT) !
VARIABLE (SF-I) VARIABLE (SS-I)
: (SUBST-NAME) ( i -- c-addr ) 32 * (SUBST-NAMES) + ;
: (SUBST-TEXT) ( i -- c-addr ) 256 * (SUBST-TEXTS) + ;
: (SUBST-FIND) ( c-addr u -- i true | false )
  0 (SF-I) ! BEGIN (SF-I) @ (SUBST-CNT) @ < WHILE
    2DUP (SF-I) @ (SUBST-NAME) COUNT COMPARE 0= IF 2DROP (SF-I) @ TRUE EXIT THEN
    1 (SF-I) +! REPEAT 2DROP FALSE ;
DOC" REPLACES ( c-addr1 u1 c-addr2 u2 -- ) set substitution text for name"
: REPLACES 2DUP (SUBST-FIND) IF NIP NIP (SUBST-TEXT) PLACE
  ELSE (SUBST-CNT) @ (SUBST-MAX) >= IF 2DROP 2DROP EXIT THEN
  (SUBST-CNT) @ >R R@ (SUBST-NAME) PLACE R@ (SUBST-TEXT) PLACE R> DROP 1 (SUBST-CNT) +! THEN ;
VARIABLE (UE-B) VARIABLE (UE-D)
DOC" UNESCAPE ( c-addr1 u1 c-addr2 -- c-addr2 u2 ) double each % character"
: UNESCAPE DUP (UE-B) ! (UE-D) ! 0 (SS-I) !
  BEGIN (SS-I) @ OVER < WHILE
    2 PICK (SS-I) @ + C@ DUP 37 = IF DROP 37 (UE-D) @ C! 1 (UE-D) +! 37 THEN
    (UE-D) @ C! 1 (UE-D) +! 1 (SS-I) +!
  REPEAT 2DROP (UE-B) @ (UE-D) @ OVER - ;
VARIABLE (SS-DEST) VARIABLE (SS-MAX) VARIABLE (SS-LEN) VARIABLE (SS-N) VARIABLE (SS-ERR)
CREATE (SS-NBUF) 64 ALLOT
: (SS-ADD) ( c -- )
  (SS-LEN) @ (SS-MAX) @ < IF (SS-DEST) @ (SS-LEN) @ + C! 1 (SS-LEN) +! ELSE DROP -1 (SS-ERR) ! THEN ;
: (SS-ADDS) ( c-addr u -- ) BEGIN DUP WHILE OVER C@ (SS-ADD) 1 /STRING REPEAT 2DROP ;
: (SS-LOOK) ( c-addr u -- )
  2DUP (SUBST-FIND) IF NIP NIP (SUBST-TEXT) COUNT (SS-ADDS) 1 (SS-N) +!
  ELSE 37 (SS-ADD) (SS-ADDS) 37 (SS-ADD) THEN ;
DOC" SUBSTITUTE ( c-addr1 u1 c-addr2 u2 -- c-addr2 u3 n ) expand %name% substitutions"
: SUBSTITUTE
  OVER >R 3 PICK R@ = IF 2DROP DROP R> 0 -1 EXIT THEN R> DROP
  (SS-MAX) ! (SS-DEST) ! 0 (SS-LEN) ! 0 (SS-N) ! 0 (SS-ERR) !
  BEGIN DUP 0> WHILE
    OVER C@ 37 <> IF OVER C@ (SS-ADD) 1 /STRING
    ELSE DUP 1 > IF OVER 1+ C@ 37 = IF 37 (SS-ADD) 2 /STRING
      ELSE 0 (SS-I) ! BEGIN 1 (SS-I) +!
        DUP (SS-I) @ > 0= IF (SS-ADDS) 0 0 TRUE
        ELSE OVER (SS-I) @ + C@ 37 = IF
          OVER 1+ (SS-I) @ 1- (SS-NBUF) PLACE (SS-NBUF) COUNT (SS-LOOK)
          (SS-I) @ 1+ /STRING TRUE
        ELSE FALSE THEN THEN UNTIL
      THEN ELSE 37 (SS-ADD) 1 /STRING THEN THEN
  REPEAT 2DROP (SS-DEST) @ (SS-LEN) @ (SS-ERR) @ IF (SS-ERR) @ ELSE (SS-N) @ THEN ;

\ --- 9. Facility ---
DOC" EKEY? ( -- flag ) true if a key event is available"
: EKEY? KEY? ;
DOC" EKEY>CHAR ( u -- u false | char true ) decode character event"
: EKEY>CHAR DUP $FF000000 AND $02000000 = IF FALSE EXIT THEN
  DUP $FF000000 AND $01000000 = IF $1FFFFF AND TRUE EXIT THEN
  DUP 0 256 WITHIN IF TRUE ELSE FALSE THEN ;
DOC" EKEY>FKEY ( u -- u false | k true ) decode K-* function-key event"
: EKEY>FKEY DUP $FF000000 AND $02000000 = IF $FFFFFF AND TRUE ELSE FALSE THEN ;
DOC" EMIT? ( -- flag ) always true (console always ready)"
: EMIT? TRUE ;
DOC" BEGIN-STRUCTURE ( 'name' -- struct-sys 0 ) start structure definition"
: BEGIN-STRUCTURE CREATE HERE 0 0 , DOES> @ ;
DOC" END-STRUCTURE ( struct-sys +n -- ) finish structure; name returns size"
: END-STRUCTURE SWAP ! ;
DOC" +FIELD ( n1 n2 'name' -- n3 ) field of n2 bytes at offset n1"
: +FIELD CREATE OVER , + DOES> @ + ;
DOC" FIELD: ( n1 'name' -- n2 ) aligned cell field"
: FIELD: ALIGNED 1 CELLS +FIELD ;
DOC" CFIELD: ( n1 'name' -- n2 ) character field"
: CFIELD: 1 CHARS +FIELD ;
DOC" K-LEFT ( -- u ) EKEY>FKEY code: left arrow"
1 CONSTANT K-LEFT
DOC" K-RIGHT ( -- u ) EKEY>FKEY code: right arrow"
2 CONSTANT K-RIGHT
DOC" K-UP ( -- u ) EKEY>FKEY code: up arrow"
3 CONSTANT K-UP
DOC" K-DOWN ( -- u ) EKEY>FKEY code: down arrow"
4 CONSTANT K-DOWN
DOC" K-HOME ( -- u ) EKEY>FKEY code: Home"
5 CONSTANT K-HOME
DOC" K-END ( -- u ) EKEY>FKEY code: End"
6 CONSTANT K-END
DOC" K-PRIOR ( -- u ) EKEY>FKEY code: Page Up"
7 CONSTANT K-PRIOR
DOC" K-NEXT ( -- u ) EKEY>FKEY code: Page Down"
8 CONSTANT K-NEXT
DOC" K-INSERT ( -- u ) EKEY>FKEY code: Insert"
9 CONSTANT K-INSERT
DOC" K-DELETE ( -- u ) EKEY>FKEY code: Delete"
10 CONSTANT K-DELETE
DOC" K-F1 ( -- u ) EKEY>FKEY code: function key F1"
11 CONSTANT K-F1
DOC" K-F2 ( -- u ) EKEY>FKEY code: function key F2"
12 CONSTANT K-F2
DOC" K-F3 ( -- u ) EKEY>FKEY code: function key F3"
13 CONSTANT K-F3
DOC" K-F4 ( -- u ) EKEY>FKEY code: function key F4"
14 CONSTANT K-F4
DOC" K-F5 ( -- u ) EKEY>FKEY code: function key F5"
15 CONSTANT K-F5
DOC" K-F6 ( -- u ) EKEY>FKEY code: function key F6"
16 CONSTANT K-F6
DOC" K-F7 ( -- u ) EKEY>FKEY code: function key F7"
17 CONSTANT K-F7
DOC" K-F8 ( -- u ) EKEY>FKEY code: function key F8"
18 CONSTANT K-F8
DOC" K-F9 ( -- u ) EKEY>FKEY code: function key F9"
19 CONSTANT K-F9
DOC" K-F10 ( -- u ) EKEY>FKEY code: function key F10"
20 CONSTANT K-F10
DOC" K-F11 ( -- u ) EKEY>FKEY code: function key F11"
21 CONSTANT K-F11
DOC" K-F12 ( -- u ) EKEY>FKEY code: function key F12"
22 CONSTANT K-F12
DOC" K-SHIFT-MASK ( -- u ) bit mask: Shift held with K-* key"
$2000 CONSTANT K-SHIFT-MASK
DOC" K-CTRL-MASK ( -- u ) bit mask: Ctrl held with K-* key"
$4000 CONSTANT K-CTRL-MASK
DOC" K-ALT-MASK ( -- u ) bit mask: Alt/Option held with K-* key"
$8000 CONSTANT K-ALT-MASK
DOC" LOCALS| ( name...name | -- ) declare locals (obsolescent; immediate)"
: LOCALS| BEGIN BL WORD COUNT OVER C@ 124 - OVER 1 - OR WHILE (LOCAL) REPEAT 2DROP 0 0 (LOCAL) ; IMMEDIATE
DOC" WARNING ( -- addr ) variable; used by some test suites"
VARIABLE WARNING ;

\ --- 10. Block word set ---
DOC" (BLOCK-SEEK) ( u -- ior ) seek BLOCK-FILE to start of block u"
: (BLOCK-SEEK) 1024 UM* BLOCK-FILE @ REPOSITION-FILE ;
DOC" (BLOCK-WRITE) ( u -- ior ) write block buffer to mass storage block u"
: (BLOCK-WRITE) BLOCK-FILE @ 0= IF DROP 0 EXIT THEN
  DUP (BLOCK-SEEK) ?DUP IF NIP EXIT THEN DROP (BLOCK-BUF) 1024 BLOCK-FILE @ WRITE-FILE ;
DOC" (BLOCK-READ) ( u -- ior ) read mass storage block u into block buffer"
: (BLOCK-READ) BLOCK-FILE @ 0= IF DROP (BLOCK-BUF) 1024 BL FILL 0 EXIT THEN
  DUP (BLOCK-SEEK) ?DUP IF NIP EXIT THEN DROP (BLOCK-BUF) 1024 BLOCK-FILE @ READ-FILE NIP ;
DOC" UPDATE ( -- ) mark current block buffer dirty"
: UPDATE -1 (BLOCK-UPD) ! ;
DOC" SAVE-BUFFERS ( -- ) write dirty buffers; keep assignment"
: SAVE-BUFFERS
  (BLOCK-UPD) @ IF (BLOCK-NR) @ DUP 0< 0= IF (BLOCK-WRITE) DROP THEN 0 (BLOCK-UPD) ! THEN
  BLOCK-FILE @ IF BLOCK-FILE @ FLUSH-FILE DROP THEN ;
DOC" EMPTY-BUFFERS ( -- ) unassign buffers; discard dirty without writing"
: EMPTY-BUFFERS 0 (BLOCK-UPD) ! -1 (BLOCK-NR) ! ;
DOC" FLUSH ( -- ) SAVE-BUFFERS then EMPTY-BUFFERS"
: FLUSH SAVE-BUFFERS EMPTY-BUFFERS ;
DOC" BLOCK ( u -- a-addr ) a-addr is the address of the block buffer for block u"
: BLOCK
  DUP (BLOCK-NR) @ = IF DROP (BLOCK-BUF) EXIT THEN
  (BLOCK-UPD) @ IF (BLOCK-NR) @ DUP 0< 0= IF (BLOCK-WRITE) DROP THEN 0 (BLOCK-UPD) ! THEN
  DUP (BLOCK-NR) ! DUP (BLOCK-READ) DROP DROP (BLOCK-BUF) ;
DOC" BUFFER ( u -- a-addr ) like BLOCK; contents may be unspecified"
: BUFFER BLOCK ;
DOC" OPEN-BLOCK-FILE ( c-addr u -- fileid ior ) open existing .blk volume R/W"
: OPEN-BLOCK-FILE R/W BIN OPEN-FILE ;
DOC" CREATE-BLOCK-FILE ( c-addr u n -- fileid ior ) create .blk with n blank blocks"
: CREATE-BLOCK-FILE
  >R R/W BIN CREATE-FILE DUP IF R> DROP EXIT THEN DROP
  R> 0 ?DO DUP (BLOCK-BUF) 1024 BL FILL (BLOCK-BUF) 1024 ROT WRITE-FILE DROP LOOP
  DUP >R 0 0 R@ REPOSITION-FILE DROP R> 0 ;
DOC" USE-BLOCK-FILE ( fileid -- ) select volume as current; flush previous"
: USE-BLOCK-FILE FLUSH BLOCK-FILE ! ;
DOC" CLOSE-BLOCK-FILE ( fileid -- ior ) flush if current, then CLOSE-FILE"
: CLOSE-BLOCK-FILE DUP BLOCK-FILE @ = IF FLUSH 0 BLOCK-FILE ! THEN CLOSE-FILE ;
DOC" LOAD ( i*x u -- j*x ) interpret block u"
: LOAD (LOAD-ENTER) BLOCK 1024 (LOAD-RUN) ;
DOC" THRU ( i*x u1 u2 -- j*x ) LOAD u1..u2 inclusive"
: THRU 1+ SWAP ?DO I LOAD LOOP ;
DOC" LIST ( u -- ) display block u as 16 lines of 64 chars"
: LIST DUP SCR ! BLOCK 16 0 DO CR I 3 .R SPACE DUP 64 TYPE 64 + LOOP DROP CR ;

\ --- Floating-point word set in FP vocabulary ---
\ DOC" lines are minimal; F: marks the floating-point stack.
ALSO FP DEFINITIONS
DOC" FDEPTH ( -- n ) floating-point stack depth"
: FDEPTH 1 (F-OP) ;
DOC" FDROP ( F: r -- ) drop float"
: FDROP 2 (F-OP) ;
DOC" FDUP ( F: r -- r r ) duplicate float"
: FDUP 3 (F-OP) ;
DOC" FSWAP ( F: r1 r2 -- r2 r1 ) swap floats"
: FSWAP 4 (F-OP) ;
DOC" FOVER ( F: r1 r2 -- r1 r2 r1 ) copy second float"
: FOVER 5 (F-OP) ;
DOC" FROT ( F: r1 r2 r3 -- r2 r3 r1 ) rotate top three floats"
: FROT 6 (F-OP) ;
DOC" F+ ( F: r1 r2 -- r3 ) add floats"
: F+ 7 (F-OP) ;
DOC" F- ( F: r1 r2 -- r3 ) subtract floats"
: F- 8 (F-OP) ;
DOC" F* ( F: r1 r2 -- r3 ) multiply floats"
: F* 9 (F-OP) ;
DOC" F/ ( F: r1 r2 -- r3 ) divide floats"
: F/ 10 (F-OP) ;
DOC" FNEGATE ( F: r1 -- r2 ) negate float"
: FNEGATE 11 (F-OP) ;
DOC" FABS ( F: r1 -- r2 ) absolute value"
: FABS 12 (F-OP) ;
DOC" FMAX ( F: r1 r2 -- r3 ) maximum"
: FMAX 13 (F-OP) ;
DOC" FMIN ( F: r1 r2 -- r3 ) minimum"
: FMIN 14 (F-OP) ;
DOC" F0= ( F: r -- ) ( -- flag ) true if float is zero"
: F0= 15 (F-OP) ;
DOC" F0< ( F: r -- ) ( -- flag ) true if float is negative"
: F0< 16 (F-OP) ;
DOC" F< ( F: r1 r2 -- ) ( -- flag ) true if r1 < r2"
: F< 17 (F-OP) ;
DOC" F> ( F: r1 r2 -- ) ( -- flag ) true if r1 > r2"
: F> 18 (F-OP) ;
DOC" F= ( F: r1 r2 -- ) ( -- flag ) true if r1 = r2"
: F= 19 (F-OP) ;
DOC" F<> ( F: r1 r2 -- ) ( -- flag ) true if r1 <> r2"
: F<> 20 (F-OP) ;
DOC" F~ ( F: r1 r2 r3 -- ) ( -- flag ) approximately equal (r3 tolerance)"
: F~ 21 (F-OP) ;
DOC" F@ ( addr -- ) ( F: -- r ) fetch 64-bit float"
: F@ 22 (F-OP) ;
DOC" F! ( addr -- ) ( F: r -- ) store 64-bit float"
: F! 23 (F-OP) ;
DOC" SF@ ( addr -- ) ( F: -- r ) fetch 32-bit float"
: SF@ 24 (F-OP) ;
DOC" SF! ( addr -- ) ( F: r -- ) store 32-bit float"
: SF! 25 (F-OP) ;
DOC" DF@ ( addr -- ) ( F: -- r ) fetch 64-bit float (synonym of F@)"
: DF@ 26 (F-OP) ;
DOC" DF! ( addr -- ) ( F: r -- ) store 64-bit float (synonym of F!)"
: DF! 27 (F-OP) ;
DOC" S>F ( n -- ) ( F: -- r ) single integer to float"
: S>F 28 (F-OP) ;
DOC" F>S ( -- n ) ( F: r -- ) float to single integer"
: F>S 29 (F-OP) ;
DOC" D>F ( d -- ) ( F: -- r ) double integer to float"
: D>F 30 (F-OP) ;
DOC" F>D ( -- d ) ( F: r -- ) float to double integer"
: F>D 31 (F-OP) ;
DOC" >FLOAT ( c-addr u -- true | false ) ( F: -- r | ) parse float from string"
: >FLOAT 32 (F-OP) ;
DOC" F. ( F: r -- ) print float (fixed style)"
: F. 33 (F-OP) ;
DOC" FS. ( F: r -- ) print float scientific"
: FS. 34 (F-OP) ;
DOC" FE. ( F: r -- ) print float engineering"
: FE. 35 (F-OP) ;
DOC" PRECISION ( -- u ) digits used by F. / FS. / FE."
: PRECISION 36 (F-OP) ;
DOC" SET-PRECISION ( u -- ) set float print precision"
: SET-PRECISION 37 (F-OP) ;
DOC" REPRESENT ( c-addr u -- n flag1 flag2 ) ( F: r -- ) classic float→text"
: REPRESENT 38 (F-OP) ;
DOC" FLOATS ( n1 -- n2 ) n1 floats in address units"
: FLOATS 39 (F-OP) ;
DOC" FLOAT+ ( addr1 -- addr2 ) add size of one float"
: FLOAT+ 40 (F-OP) ;
DOC" SFLOATS ( n1 -- n2 ) n1 single-floats in address units"
: SFLOATS 41 (F-OP) ;
DOC" SFLOAT+ ( addr1 -- addr2 ) add size of one single-float"
: SFLOAT+ 42 (F-OP) ;
DOC" DFLOATS ( n1 -- n2 ) n1 double-floats in address units"
: DFLOATS 43 (F-OP) ;
DOC" DFLOAT+ ( addr1 -- addr2 ) add size of one double-float"
: DFLOAT+ 44 (F-OP) ;
DOC" FSQRT ( F: r1 -- r2 ) square root"
: FSQRT 45 (F-OP) ;
DOC" F** ( F: r1 r2 -- r3 ) r1 raised to r2"
: F** 46 (F-OP) ;
DOC" FEXP ( F: r1 -- r2 ) e**r1"
: FEXP 47 (F-OP) ;
DOC" FEXPM1 ( F: r1 -- r2 ) e**r1 - 1"
: FEXPM1 48 (F-OP) ;
DOC" FLN ( F: r1 -- r2 ) natural log"
: FLN 49 (F-OP) ;
DOC" FLNP1 ( F: r1 -- r2 ) ln(1+r1)"
: FLNP1 50 (F-OP) ;
DOC" FLOG ( F: r1 -- r2 ) log base 10"
: FLOG 51 (F-OP) ;
DOC" FALOG ( F: r1 -- r2 ) 10**r1"
: FALOG 52 (F-OP) ;
DOC" FSIN ( F: r1 -- r2 ) sine (radians)"
: FSIN 53 (F-OP) ;
DOC" FCOS ( F: r1 -- r2 ) cosine (radians)"
: FCOS 54 (F-OP) ;
DOC" FTAN ( F: r1 -- r2 ) tangent (radians)"
: FTAN 55 (F-OP) ;
DOC" FASIN ( F: r1 -- r2 ) arcsine"
: FASIN 56 (F-OP) ;
DOC" FACOS ( F: r1 -- r2 ) arccosine"
: FACOS 57 (F-OP) ;
DOC" FATAN ( F: r1 -- r2 ) arctangent"
: FATAN 58 (F-OP) ;
DOC" FATAN2 ( F: r1 r2 -- r3 ) atan2(r1,r2)"
: FATAN2 59 (F-OP) ;
DOC" FSINCOS ( F: r1 -- r2 r3 ) sine and cosine"
: FSINCOS 60 (F-OP) ;
DOC" FSINH ( F: r1 -- r2 ) hyperbolic sine"
: FSINH 61 (F-OP) ;
DOC" FCOSH ( F: r1 -- r2 ) hyperbolic cosine"
: FCOSH 62 (F-OP) ;
DOC" FTANH ( F: r1 -- r2 ) hyperbolic tangent"
: FTANH 63 (F-OP) ;
DOC" FASINH ( F: r1 -- r2 ) inverse hyperbolic sine"
: FASINH 64 (F-OP) ;
DOC" FACOSH ( F: r1 -- r2 ) inverse hyperbolic cosine"
: FACOSH 65 (F-OP) ;
DOC" FATANH ( F: r1 -- r2 ) inverse hyperbolic tangent"
: FATANH 66 (F-OP) ;
DOC" FLOOR ( F: r1 -- r2 ) floor"
: FLOOR 67 (F-OP) ;
DOC" FROUND ( F: r1 -- r2 ) round to nearest"
: FROUND 68 (F-OP) ;
DOC" FMOD ( F: r1 r2 -- r3 ) floating remainder"
: FMOD 69 (F-OP) ;
DOC" FALIGNED ( addr -- a-addr ) next float-aligned address"
: FALIGNED 73 (F-OP) ;
DOC" SFALIGNED ( addr -- a-addr ) next single-float-aligned address"
: SFALIGNED 74 (F-OP) ;
DOC" DFALIGNED ( addr -- a-addr ) next double-float-aligned address"
: DFALIGNED 75 (F-OP) ;
DOC" FALIGN ( -- ) align HERE for float"
: FALIGN HERE DUP FALIGNED SWAP - ALLOT ;
DOC" SFALIGN ( -- ) align HERE for single-float"
: SFALIGN HERE DUP SFALIGNED SWAP - ALLOT ;
DOC" DFALIGN ( -- ) align HERE for double-float"
: DFALIGN FALIGN ;
DOC" F, ( F: r -- ) compile a float into the dictionary"
: F, HERE 8 ALLOT F! ;
DOC" FVARIABLE ( 'name' -- ) create a float variable"
: FVARIABLE CREATE 8 ALLOT ;
DOC" FCONSTANT ( F: r 'name' -- ) create a float constant"
: FCONSTANT CREATE F, DOES> F@ ;
DOC" FVALUE ( F: r 'name' -- ) create a float value; change with TO"
: FVALUE CREATE F, DOES> F@ ;
DOC" FLITERAL ( F: r -- ) compile float literal (immediate)"
: FLITERAL 102 (F-OP) FLIT-ADDR , , ; IMMEDIATE
ONLY FORTH DEFINITIONS

\ --- Extended-Character word set (ANS 18, UTF-8) ---
DOC" XC-SIZE ( xchar -- u ) UTF-8 byte count for code point"
: XC-SIZE DUP 127 > IF DUP 2047 > IF DUP 65535 > IF DROP 4 ELSE DROP 3 THEN ELSE DROP 2 THEN ELSE DROP 1 THEN ;
DOC" X-SIZE ( xc-addr u -- u ) size of first UTF-8 xchar in buffer"
: X-SIZE DROP C@ DUP 128 < IF DROP 1 ELSE DUP 224 < IF DROP 2 ELSE DUP 240 < IF DROP 3 ELSE DROP 4 THEN THEN THEN ;
VARIABLE (XQ-SZ) VARIABLE (XQ-MAX)
DOC" XC!+? ( xchar xc-addr u1 -- xc-addr' u2 flag ) store if fits"
: XC!+? (XQ-MAX) ! OVER XC-SIZE DUP (XQ-SZ) ! (XQ-MAX) @ > IF
  NIP (XQ-MAX) @ FALSE ELSE XC!+ (XQ-MAX) @ (XQ-SZ) @ - TRUE THEN ;
DOC" XC, ( xchar -- ) append UTF-8 xchar to dictionary"
: XC, HERE XC!+ HERE - ALLOT ;
DOC" XCHAR+ ( xc-addr1 -- xc-addr2 ) skip one UTF-8 xchar forward"
: XCHAR+ DUP 1 X-SIZE + ;
DOC" XCHAR- ( xc-addr1 -- xc-addr2 ) skip one UTF-8 xchar backward"
: XCHAR- BEGIN 1- DUP C@ 192 AND 128 <> UNTIL ;
DOC" +X/STRING ( xc-addr1 u1 -- xc-addr2 u2 ) skip one xchar in string"
: +X/STRING DUP 0= IF EXIT THEN 2DUP X-SIZE /STRING ;
DOC" X\STRING- ( xc-addr u1 -- xc-addr u2 ) trim last xchar from string"
: X\STRING- DUP 0= IF EXIT THEN OVER + XCHAR- OVER - ;
VARIABLE (TGA) VARIABLE (TGU) VARIABLE (TGP)
DOC" -TRAILING-GARBAGE ( xc-addr u1 -- xc-addr u2 ) trim incomplete trailing UTF-8"
: -TRAILING-GARBAGE DUP 0= IF EXIT THEN OVER (TGA) ! DUP (TGU) !
  (TGA) @ (TGU) @ + 1- (TGP) !
  BEGIN (TGP) @ C@ 192 AND 128 = (TGP) @ (TGA) @ U> AND WHILE
    (TGP) @ 1- (TGP) ! REPEAT
  DROP DROP
  (TGP) @ C@ DUP 128 < IF DROP (TGA) @ (TGU) @ EXIT THEN
  DUP 224 < IF DROP 2 ELSE DUP 240 < IF DROP 3 ELSE DROP 4 THEN THEN
  (TGU) @ (TGP) @ (TGA) @ - - > IF (TGA) @ (TGP) @ (TGA) @ - ELSE (TGA) @ (TGU) @ THEN ;
DOC" XKEY? ( -- flag ) true if a key/xchar is available"
: XKEY? KEY? ;
DOC" XKEY ( -- xchar ) read next UTF-8 xchar from KEY"
: XKEY KEY DUP 128 < IF EXIT THEN
  DUP 224 < IF 31 AND KEY 63 AND SWAP 6 LSHIFT OR EXIT THEN
  DUP 240 < IF 15 AND KEY 63 AND SWAP 6 LSHIFT OR KEY 63 AND SWAP 6 LSHIFT OR EXIT THEN
  7 AND KEY 63 AND SWAP 6 LSHIFT OR KEY 63 AND SWAP 6 LSHIFT OR KEY 63 AND SWAP 6 LSHIFT OR ;
DOC" EKEY>XCHAR ( u -- u false | xchar true ) convert EKEY to xchar"
: EKEY>XCHAR DUP 0 128 WITHIN IF TRUE ELSE FALSE THEN ;
VARIABLE (XH-A) VARIABLE (XH-U)
DOC" XHOLD ( xchar -- ) hold UTF-8 xchar in pictured numeric"
: XHOLD PAD SWAP OVER XC!+ OVER - (XH-U) ! (XH-A) !
  BEGIN (XH-U) @ WHILE (XH-U) @ 1- DUP (XH-U) ! (XH-A) @ + C@ HOLD REPEAT ;
DOC" XC-WIDTH ( xchar -- +n ) display width of one xchar"
: XC-WIDTH DUP 32 < IF DROP 0 EXIT THEN DUP 127 <= IF DROP 1 EXIT THEN
  DUP 4352 < IF DROP 1 EXIT THEN DUP 4448 < IF DROP 2 EXIT THEN
  DUP 11904 < IF DROP 1 EXIT THEN DUP 42192 < IF DROP 2 EXIT THEN
  DUP 44032 < IF DROP 1 EXIT THEN DUP 55204 < IF DROP 2 EXIT THEN DROP 1 ;
VARIABLE (XWA) VARIABLE (XWU) VARIABLE (XWS)
DOC" X-WIDTH ( xc-addr u -- +n ) total display width of string"
: X-WIDTH (XWU) ! (XWA) ! 0 (XWS) !
  BEGIN (XWU) @ WHILE
    (XWA) @ XC@+ XC-WIDTH (XWS) @ + (XWS) !
    DUP (XWA) @ - (XWU) @ SWAP - (XWU) ! (XWA) !
  REPEAT (XWS) @ ;
DOC" CHAR ( '<spaces>name' -- xchar ) first xchar of next word"
: CHAR BL WORD COUNT DROP XC@+ SWAP DROP ;
DOC" [CHAR] ( compile: '<spaces>name' -- ) compile xchar literal (immediate)"
: [CHAR] ?COMP CHAR LIT-ADDR , , ; IMMEDIATE

\ BOOT_WORD display list for assembly words
8 5 * CONSTANT /BOOT-WORD   \ name help imm code end
: BOOT-WORD-NAME  ( row -- c-addr )  @ ;
: BOOT-WORD-HELP  ( row -- c-addr )  8 + @ ;
: BOOT-WORD-IMM   ( row -- n )       16 + @ ;
: BOOT-WORD-CODE  ( row -- addr )    24 + @ ;
: BOOT-WORD-END   ( row -- addr )    32 + @ ;   \ 0 if unlabeled

: ZCOUNT  ( zaddr -- zaddr u )
  DUP BEGIN DUP C@ WHILE 1+ REPEAT OVER - ;
: ZTYPE  ( zaddr -- )  ZCOUNT TYPE ;
: .BOOT-WORDS  ( -- )
  BASE @ HEX
  BOOT-WORD-TABLE
  BEGIN
    DUP @ ?DUP
  WHILE
    ZTYPE  2 SPACES
    DUP 8 + @ ZTYPE  2 SPACES
    DUP 24 + @ U. SPACE    \ code
    DUP 32 + @ U. CR  \ end (use 24 + @ only if 4-quad rows)
    /BOOT-WORD +
  REPEAT DROP
  BASE ! ;
: CODE-BOUNDS  ( xt -- code end )
  @                                 \ code*
  BOOT-WORD-TABLE
  BEGIN  DUP @ WHILE
    2DUP 24 + @ = IF                \ this row's code
      NIP  DUP 24 + @  SWAP 32 + @  EXIT
    THEN
    /BOOT-WORD +
  REPEAT
  DROP  0 ;                         \ not a boot primitive; end unknown
: .BOUNDS  ( xt -- )
  CODE-BOUNDS
  BASE @ >R HEX
  2DUP SWAP U. SPACE U. SPACE
  SWAP - U.
  R> BASE ! ;
  DOC" MAIN ( -- ) default app entry; AutoLoad may redefine"
: MAIN ;
