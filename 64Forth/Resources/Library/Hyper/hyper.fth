\ hyper.fth — HYPER.NDX: LOCATE / VIEW
\
\ Load: FROMLIB FLOAD Hyper/hyper.fth
\ Use:  LOCATE DUP

ANEW HYPER-MODULE
ONLY FORTH DEFINITIONS

0 VALUE HYPER-BUF
0 VALUE HYPER-LEN
0 VALUE HYPER-OK
0 VALUE HYPER-POS
0 VALUE HYPER-LC
0 VALUE HYPER-LINE#

CREATE HYPER-CUR   256 ALLOT
CREATE HYPER-HIT   256 ALLOT
CREATE HYPER-LINE  256 ALLOT
CREATE HYPER-SEEK   64 ALLOT
CREATE HYPER-CMD   512 ALLOT

CREATE HYPER-NDX-NAME  32 ALLOT
S" Config/HYPER.NDX" HYPER-NDX-NAME PLACE

\ Try open path; on success leave fileid and set HYPER-NDX-NAME. flag true = ok.
: HYPER-TRY-OPEN  ( c-addr u -- fileid true | false )
   2DUP R/O OPEN-FILE
   IF  DROP 2DROP FALSE EXIT  THEN     \ ior: fail
   >R                                  \ R: fid  ( c-addr u )
   HYPER-NDX-NAME PLACE
   R> TRUE ;

\ Config/HYPER.NDX first (HYPER-REINDEX + shipped index), else cwd HYPER.NDX.
: HYPER-OPEN-NDX  ( -- fileid true | false )
   S" Config/HYPER.NDX" HYPER-TRY-OPEN DUP IF  EXIT  THEN  DROP
   S" HYPER.NDX" HYPER-TRY-OPEN ;

: HYPER-UPC  ( c -- c' )
   DUP [CHAR] a [CHAR] z 1+ WITHIN IF  32 -  THEN ;

: HYPER-SKIP1  ( a u -- a' u' )
   SWAP 1+ SWAP 1- ;

: HYPER-SKIP-BL  ( a u -- a' u' )
   BEGIN
      DUP 0= IF  EXIT  THEN
      OVER C@ BL <> IF  EXIT  THEN
      HYPER-SKIP1
   AGAIN ;

\ ( src u dest -- ) counted string at dest (kernel CMOVE)
: HYPER-PLACE  ( src u dest -- )
   >R                              \ R: dest  (CMOVE uses its own R frame)
   255 MIN
   DUP R@ C!                       \ count at dest
   R@ CHAR+ SWAP CMOVE             \ ( src dest+1 u ) → CMOVE
   R> DROP ;

\ ( a1 u1 a2 u2 -- flag )  case-insensitive; always consumes all four args.
: HYPER-NAME=  ( a1 u1 a2 u2 -- flag )
   ROT OVER <> IF  2DROP 2DROP FALSE EXIT  THEN   \ len mismatch
   DUP 64 > IF  2DROP 2DROP FALSE EXIT  THEN
   BEGIN  DUP WHILE
      1- >R                             \ R: remaining-1  ( a1 a2 )
      DUP C@ HYPER-UPC >R               \ R: rem ch2
      OVER C@ HYPER-UPC R> <> IF        \ chars differ
         R> DROP                        \ drop rem
         2DROP FALSE EXIT               \ drop a1 a2
      THEN
      1+ SWAP 1+ SWAP
      R>
   REPEAT
   DROP 2DROP TRUE ;

: HYPER-FREE  ( -- )
   HYPER-BUF IF  HYPER-BUF FREE DROP  THEN
   0 TO HYPER-BUF  0 TO HYPER-LEN  0 TO HYPER-POS
   FALSE TO HYPER-OK
   0 HYPER-CUR C!  0 HYPER-HIT C!
   0 TO HYPER-LINE# ;

\ Prefer Config/HYPER.NDX, else cwd HYPER.NDX.
: HYPER-LOAD  ( -- flag )
   HYPER-FREE
   HYPER-OPEN-NDX 0= IF  FALSE EXIT  THEN
   >R                                  \ R: fid
   R@ FILE-SIZE
   IF  2DROP R> CLOSE-FILE DROP FALSE EXIT  THEN
   IF  DROP R> CLOSE-FILE DROP FALSE EXIT  THEN
   DUP 0= IF  DROP R> CLOSE-FILE DROP FALSE EXIT  THEN
   \ ( size ) ALLOCATE → ( size addr ior )
   DUP ALLOCATE IF                 \ fail
      2DROP R> CLOSE-FILE DROP FALSE EXIT
   THEN                            \ ( size addr )
   TO HYPER-BUF                    \ ( size )
   DUP TO HYPER-LEN
   HYPER-BUF SWAP R@ READ-FILE
   R> CLOSE-FILE DROP
   IF  HYPER-FREE FALSE EXIT  THEN
   TO HYPER-LEN
   TRUE TO HYPER-OK
   TRUE ;

: HYPER-ENSURE  ( -- flag )
   HYPER-OK IF  TRUE EXIT  THEN  HYPER-LOAD ;

: HYPER-EOF?  ( -- flag )  HYPER-POS HYPER-LEN U< 0= ;

: HYPER-CH  ( -- c | -1 )
   HYPER-EOF? IF  -1 EXIT  THEN
   HYPER-BUF HYPER-POS + C@
   HYPER-POS 1+ TO HYPER-POS ;

: HYPER-READ-LINE  ( -- a u | 0 0 )
   0 TO HYPER-LC
   BEGIN
      HYPER-CH
      DUP 0< IF
         DROP
         HYPER-LC IF  HYPER-LC HYPER-LINE C! HYPER-LINE COUNT
         ELSE  0 0  THEN EXIT
      THEN
      DUP 10 = IF
         DROP HYPER-LC HYPER-LINE C! HYPER-LINE COUNT EXIT
      THEN
      DUP 13 = IF
         DROP
         HYPER-EOF? 0= IF
            HYPER-BUF HYPER-POS + C@ 10 = IF  HYPER-CH DROP  THEN
         THEN
         HYPER-LC HYPER-LINE C! HYPER-LINE COUNT EXIT
      THEN
      HYPER-LC 255 < IF
         HYPER-LINE 1+ HYPER-LC + C!
         HYPER-LC 1+ TO HYPER-LC
      ELSE
         DROP
         BEGIN
            HYPER-CH
            DUP 0< OVER 10 = OR OVER 13 = OR 0=
         WHILE  DROP
         REPEAT
         DUP 13 = IF
            DROP
            HYPER-EOF? 0= IF
               HYPER-BUF HYPER-POS + C@ 10 = IF  HYPER-CH DROP  THEN
            THEN
         ELSE  DROP  THEN
         HYPER-LC HYPER-LINE C! HYPER-LINE COUNT EXIT
      THEN
   AGAIN ;

\ Stack while scanning: ( a u wlen ) — three cells.
\ ANS PICK: 0=TOS=wlen, 1=u, 2=a.  (3 PICK is out of range → bogus C@)
: HYPER-FIRST-WORD  ( a u -- wa wu ra ru )
   HYPER-SKIP-BL
   DUP 0= IF  2DUP EXIT  THEN
   0
   BEGIN
      1 PICK OVER >                \ u > wlen ?
   WHILE
      2 PICK OVER + C@ BL = IF     \ a[wlen] blank?
         >R                        \ R: wlen
         OVER R@  2SWAP            \ a wlen a u
         SWAP R@ + SWAP R@ -       \ a wlen (a+wlen) (u-wlen)
         R> DROP EXIT
      THEN
      1+
   REPEAT
   DROP
   2DUP + 0 ;

: HYPER-SET-CUR  ( a u -- )
   HYPER-CUR HYPER-PLACE ;

: HYPER->LINE  ( a u -- n true | false )
   HYPER-SKIP-BL
   DUP 0= IF  2DROP FALSE EXIT  THEN
   0 >R
   BEGIN  DUP WHILE
      OVER C@ DUP [CHAR] 0 [CHAR] 9 1+ WITHIN 0= IF
         DROP 2DROP R> DROP FALSE EXIT
      THEN
      [CHAR] 0 - R> 10 * + >R
      HYPER-SKIP1
   REPEAT
   2DROP R> TRUE ;

\ -----------------------------------------------------------------------------
\ Multi-hit table (Phase 5)
\ Entry layout (64 bytes): byte0 = path count, bytes1..55 = path, cell @56 = line
\ -----------------------------------------------------------------------------

 56 CONSTANT HYPER-HOFF            \ offset of line cell within entry
 64 CONSTANT HYPER-HESZ
 32 CONSTANT HYPER-HMAX

CREATE HYPER-HTAB  HYPER-HMAX HYPER-HESZ * ALLOT
0 VALUE HYPER-HN
0 VALUE HYPER-HI
0 VALUE HYPER-VIEWING

: HYPER-HENT  ( i -- addr )  HYPER-HESZ * HYPER-HTAB + ;

: HYPER-CLEAR-HITS  ( -- )
   0 TO HYPER-HN  0 TO HYPER-HI
   0 HYPER-HIT C!  0 TO HYPER-LINE# ;

\ Store HYPER-CUR path + line into next table slot. ( line -- )
: HYPER-STORE-HIT  ( line -- )
   HYPER-HN HYPER-HMAX >= IF  DROP EXIT  THEN
   HYPER-HN HYPER-HENT >R                \ R: ent  ( line )
   HYPER-CUR COUNT 55 MIN                \ line a u
   DUP R@ C!                             \ count at ent
   R@ 1+ SWAP CMOVE                      \ copy chars; leaves ( line )
   R@ HYPER-HOFF + !                     \ line → ent+56
   R> DROP
   HYPER-HN 1+ TO HYPER-HN ;

\ Copy hit i into HYPER-HIT / HYPER-LINE#. ( i -- )
: HYPER-SELECT  ( i -- )
   DUP 0< IF  DROP EXIT  THEN
   DUP HYPER-HN >= IF  DROP EXIT  THEN
   TO HYPER-HI
   HYPER-HI HYPER-HENT                   \ ent
   DUP C@ 55 MIN >R                      \ ent  R: n
   R@ HYPER-HIT C!
   1+ HYPER-HIT 1+ R@ CMOVE              \ src dest u
   R> DROP
   HYPER-HI HYPER-HENT HYPER-HOFF + @ TO HYPER-LINE# ;

: HYPER-SHOW-HIT  ( -- )
   HYPER-HIT COUNT TYPE [CHAR] : EMIT HYPER-LINE# .
   HYPER-HN 1 > IF
      ."  [" HYPER-HI 1+ 0 .R [CHAR] / EMIT HYPER-HN 0 .R ." ]"
   THEN
   CR ;

\ ( a u -- ) try one NDX body line; stack-clean
: (HYPER-TRY-LINE)  ( a u -- )
   HYPER-FIRST-WORD                      \ wa wu ra ru
   2SWAP                                 \ ra ru wa wu
   DUP HYPER-SEEK C@ <> IF  2DROP 2DROP EXIT  THEN
   HYPER-SEEK COUNT HYPER-NAME=          \ ra ru flag
   IF  HYPER->LINE IF  HYPER-STORE-HIT  THEN
   ELSE  2DROP  THEN ;

: (HYPER-COLLECT)  ( -- n )
   HYPER-ENSURE 0= IF  0 EXIT  THEN
   HYPER-CLEAR-HITS
   0 TO HYPER-POS
   0 HYPER-CUR C!
   BEGIN  HYPER-EOF? 0= WHILE
      HYPER-READ-LINE
      DUP 0= IF  2DROP
      ELSE  OVER C@ [CHAR] # = IF  2DROP
      ELSE  OVER C@ 64 = IF
         DUP 1 < IF  2DROP
         ELSE  HYPER-SKIP1 HYPER-SKIP-BL
            DUP 0= IF  2DROP  ELSE  HYPER-SET-CUR  THEN
         THEN
      ELSE  (HYPER-TRY-LINE)
      THEN THEN THEN
   REPEAT
   HYPER-HN ;

: (HYPER-FIND)  ( c-addr u -- flag )
   63 MIN HYPER-SEEK HYPER-PLACE
   (HYPER-COLLECT) 0= IF  FALSE EXIT  THEN
   0 HYPER-SELECT
   TRUE ;

\ Cached XTs (avoid ALSO/PREVIOUS/FIND every time — search order got stuck
\ after editor exit and FIND missed SZ-EDIT-FILE-AT).
0 VALUE HYPER-EDIT-XT                \ SZ-EDIT-FILE-AT
0 VALUE HYPER-GOTO-XT                \ SZ-HYPER-GOTO
0 VALUE HYPER-ACTIVE-XT              \ SZ-EDITOR-ACTIVE variable xt

: HYPER-BIND-EDITOR  ( -- flag )
   ONLY FORTH ALSO EDITOR
   S" SZ-EDIT-FILE-AT" HYPER-CMD HYPER-PLACE
   HYPER-CMD FIND IF  TO HYPER-EDIT-XT  ELSE  DROP 0 TO HYPER-EDIT-XT  THEN
   S" SZ-HYPER-GOTO" HYPER-CMD HYPER-PLACE
   HYPER-CMD FIND IF  TO HYPER-GOTO-XT  ELSE  DROP 0 TO HYPER-GOTO-XT  THEN
   S" SZ-EDITOR-ACTIVE" HYPER-CMD HYPER-PLACE
   HYPER-CMD FIND IF  TO HYPER-ACTIVE-XT  ELSE  DROP 0 TO HYPER-ACTIVE-XT  THEN
   ONLY FORTH
   HYPER-EDIT-XT 0<> ;

: HYPER-EDITOR?  ( -- flag )
   HYPER-EDIT-XT IF  TRUE EXIT  THEN
   HYPER-BIND-EDITOR ;

: HYPER-EDITOR-ACTIVE?  ( -- flag )
   HYPER-ACTIVE-XT 0= IF  HYPER-BIND-EDITOR DROP  THEN
   HYPER-ACTIVE-XT IF  HYPER-ACTIVE-XT EXECUTE @  ELSE  FALSE  THEN ;

\ ( c-addr u line -- ) open in SZ-EDITOR; rebinds if needed
: HYPER-OPEN-AT  ( c-addr u line -- )
   HYPER-EDIT-XT 0= IF  HYPER-BIND-EDITOR DROP  THEN
   HYPER-EDIT-XT 0= IF
      DROP 2DROP
      ." VIEW: load SZ-EDITOR first" CR
      ."   FROMLIB FLOAD Editor/SZ-EDITOR.fth" CR
      EXIT
   THEN
   HYPER-EDIT-XT EXECUTE ;

\ In-editor: SZ-HYPER-GOTO ( a u line )
: HYPER-APPLY-HIT  ( -- )
   HYPER-HN 0= IF  EXIT  THEN
   HYPER-EDITOR-ACTIVE? IF
      HYPER-GOTO-XT 0= IF  HYPER-BIND-EDITOR DROP  THEN
      HYPER-GOTO-XT 0= IF  EXIT  THEN
      HYPER-HIT COUNT HYPER-LINE#
      HYPER-GOTO-XT EXECUTE
   ELSE
      HYPER-VIEWING IF
         HYPER-HIT COUNT HYPER-LINE# HYPER-OPEN-AT
      THEN
   THEN ;

: HYPER-SHOW-HIT-SAFE  ( -- )
   HYPER-EDITOR-ACTIVE? IF  EXIT  THEN
   HYPER-SHOW-HIT ;

\ No wrap — stop cleanly at ends
: HYPER-NEXT  ( -- )
   HYPER-HN 0= IF  ." HYPER: no hits" CR EXIT  THEN
   HYPER-HI 1+
   DUP HYPER-HN >= IF
      DROP
      HYPER-EDITOR-ACTIVE? 0= IF  ." HYPER: last hit [" HYPER-HN . ." ]" CR  THEN
      EXIT
   THEN
   HYPER-SELECT
   HYPER-SHOW-HIT-SAFE
   HYPER-APPLY-HIT ;

: HYPER-PREV  ( -- )
   HYPER-HN 0= IF  ." HYPER: no hits" CR EXIT  THEN
   HYPER-HI 0= IF
      HYPER-EDITOR-ACTIVE? 0= IF  ." HYPER: first hit" CR  THEN
      EXIT
   THEN
   HYPER-HI 1- HYPER-SELECT
   HYPER-SHOW-HIT-SAFE
   HYPER-APPLY-HIT ;

: LOCATE  ( "name" -- )
   PARSE-NAME
   DUP 0= IF  2DROP ." LOCATE needs a name" CR EXIT  THEN
   FALSE TO HYPER-VIEWING
   (HYPER-FIND) 0= IF
      HYPER-OK 0= IF  ." HYPER: index not loaded" CR
      ELSE  HYPER-SEEK COUNT TYPE ."  not in HYPER.NDX" CR  THEN
      EXIT
   THEN
   HYPER-SHOW-HIT ;

\ c-addr u already a name (for Cmd-E / programmatic VIEW)
\ (HYPER-FIND) consumes c-addr u (copies into HYPER-SEEK) — do NOT 2DROP after.
: (VIEW)  ( c-addr u -- )
   DUP 0= IF  2DROP EXIT  THEN
   TRUE TO HYPER-VIEWING
   (HYPER-FIND) 0= IF
      HYPER-OK 0= IF  ." HYPER: index not loaded" CR
      ELSE  HYPER-SEEK COUNT TYPE ."  not in HYPER.NDX" CR  THEN
      EXIT
   THEN
   HYPER-SHOW-HIT
   HYPER-HIT COUNT HYPER-LINE# HYPER-OPEN-AT ;

: VIEW  ( "name" -- )
   PARSE-NAME
   DUP 0= IF  2DROP ." VIEW needs a name" CR EXIT  THEN
   (VIEW) ;

: SEE-SOURCE  ( "name" -- )  VIEW ;

\ SEE: prefer VIEW when editor is loaded; else original decompiler.
' SEE CONSTANT (SEE-OLD)

: SEE  ( "name" -- )
   >IN @ >R
   PARSE-NAME
   DUP 0= IF  R> DROP 2DROP ." SEE needs a name" CR EXIT  THEN
   2DUP (HYPER-FIND) IF
      HYPER-EDITOR? IF
         R> DROP 2DROP
         TRUE TO HYPER-VIEWING
         HYPER-SHOW-HIT
         HYPER-HIT COUNT HYPER-LINE# HYPER-OPEN-AT
         EXIT
      THEN
   THEN
   2DROP
   R> >IN !
   (SEE-OLD) EXECUTE ;

\ Cmd-E / host: VIEW name if editor present; silent no-op otherwise.
: HYPER-VIEW-CU  ( c-addr u -- )
   HYPER-EDITOR? 0= IF  2DROP EXIT  THEN
   (VIEW) ;

: HYPER-RELOAD  ( -- )
   HYPER-LOAD IF  ." HYPER: " HYPER-NDX-NAME COUNT TYPE
      ."  " HYPER-LEN . ." bytes" CR
   ELSE  ." HYPER: cannot open index" CR  THEN ;

: .HYPER  ( -- )
   CR ." HYPER " HYPER-NDX-NAME COUNT TYPE
   HYPER-OK IF  ."  " HYPER-LEN . ." bytes" CR
   ELSE  ."  not loaded" CR  THEN
   HYPER-HN IF
      ."   hits " HYPER-HN . ."  current " HYPER-HI 1+ . CR
      HYPER-SHOW-HIT
   THEN ;

: HYPER-HELP  ( -- )
   CR
   ." LOCATE <name>     print path:line  [n/m] if multiple" CR
   ." VIEW <name>       open in SZ-EDITOR at line" CR
   ." SEE <name>        VIEW if editor loaded, else decompile" CR
   ." HYPER-NEXT/PREV   next/prev hit  (Ctrl-PgDn / Ctrl-PgUp)" CR
   ." Cmd-E             VIEW word under console caret (editor required)" CR
   ." HYPER-REINDEX     rebuild Config/HYPER.NDX, reload" CR
   ." HYPER-RELOAD  .HYPER" CR ;

\ Phase 3a in-app indexer (defines HYPER-REINDEX)
FLOAD hyper-index.fth

HYPER-LOAD DROP
HYPER-BIND-EDITOR DROP

ONLY FORTH DEFINITIONS
