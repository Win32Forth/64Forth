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

: HYPER-NAME=  ( a1 u1 a2 u2 -- flag )
   ROT OVER <> IF  2DROP DROP FALSE EXIT  THEN
   DUP 64 > IF  2DROP DROP FALSE EXIT  THEN
   BEGIN  DUP WHILE
      1- >R
      DUP C@ HYPER-UPC >R
      OVER C@ HYPER-UPC R> <> IF  R> DROP 2DROP FALSE EXIT  THEN
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

: HYPER-SET-HIT  ( n -- )
   TO HYPER-LINE#
   HYPER-CUR COUNT HYPER-HIT HYPER-PLACE ;

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

: (HYPER-FIND-SEEK)  ( -- flag )
   HYPER-ENSURE 0= IF  FALSE EXIT  THEN
   0 TO HYPER-POS
   0 HYPER-CUR C!
   0 HYPER-HIT C!
   0 TO HYPER-LINE#
   BEGIN  HYPER-EOF? 0= WHILE
      HYPER-READ-LINE
      DUP 0= IF
         2DROP
      ELSE  OVER C@ [CHAR] # = IF
         2DROP
      ELSE  OVER C@ 64 = IF
         DUP 1 < IF  2DROP
         ELSE
            HYPER-SKIP1 HYPER-SKIP-BL
            DUP 0= IF  2DROP  ELSE  HYPER-SET-CUR  THEN
         THEN
      ELSE
         HYPER-FIRST-WORD
         2SWAP
         DUP HYPER-SEEK C@ <> IF
            2DROP 2DROP
         ELSE
            HYPER-SEEK COUNT HYPER-NAME= IF
               HYPER->LINE IF
                  HYPER-SET-HIT TRUE EXIT
               THEN
            ELSE
               2DROP
            THEN
         THEN
      THEN THEN THEN
   REPEAT
   FALSE ;

: (HYPER-FIND)  ( c-addr u -- flag )
   63 MIN HYPER-SEEK HYPER-PLACE
   (HYPER-FIND-SEEK) ;

: LOCATE  ( "name" -- )
   PARSE-NAME
   DUP 0= IF  2DROP ." LOCATE needs a name" CR EXIT  THEN
   (HYPER-FIND) 0= IF
      HYPER-OK 0= IF  ." HYPER: index not loaded" CR
      ELSE  HYPER-SEEK COUNT TYPE ."  not in HYPER.NDX" CR  THEN
      EXIT
   THEN
   HYPER-HIT COUNT TYPE [CHAR] : EMIT HYPER-LINE# . CR ;

\ FIND leaves ( xt 1|−1 ) or ( c-addr 0 ). IF consumes the flag only —
\ do NOT DROP the xt (that was the XEXECUTE crash: line# used as CFA).
VARIABLE HYPER-XT

: HYPER-OPEN-AT  ( c-addr u line -- )
   >R 2>R
   ALSO EDITOR
   S" SZ-EDIT-FILE-AT" HYPER-CMD HYPER-PLACE
   HYPER-CMD FIND
   PREVIOUS
   IF                              \ stack: xt   (1/−1 already consumed by IF)
      HYPER-XT !
      2R> R>                       \ a u line
      HYPER-XT @ EXECUTE
   ELSE                            \ stack: c-addr (failed FIND)
      DROP
      R> DROP
      2R>
      ." VIEW: load SZ-EDITOR first:" CR
      ."   FROMLIB FLOAD Editor/SZ-EDITOR.fth" CR
      ." Path: " TYPE CR
   THEN ;

: VIEW  ( "name" -- )
   PARSE-NAME
   DUP 0= IF  2DROP ." VIEW needs a name" CR EXIT  THEN
   (HYPER-FIND) 0= IF
      HYPER-OK 0= IF  ." HYPER: index not loaded" CR
      ELSE  HYPER-SEEK COUNT TYPE ."  not in HYPER.NDX" CR  THEN
      EXIT
   THEN
   HYPER-HIT COUNT TYPE [CHAR] : EMIT HYPER-LINE# . CR
   HYPER-HIT COUNT HYPER-LINE# HYPER-OPEN-AT ;

: SEE-SOURCE  ( "name" -- )  VIEW ;

: HYPER-RELOAD  ( -- )
   HYPER-LOAD IF  ." HYPER: " HYPER-NDX-NAME COUNT TYPE
      ."  " HYPER-LEN . ." bytes" CR
   ELSE  ." HYPER: cannot open index" CR  THEN ;

: .HYPER  ( -- )
   CR ." HYPER " HYPER-NDX-NAME COUNT TYPE
   HYPER-OK IF  ."  " HYPER-LEN . ." bytes" CR
   ELSE  ."  not loaded" CR  THEN ;

: HYPER-HELP  ( -- )
   CR
   ." LOCATE <name>     print path:line" CR
   ." VIEW <name>       open in SZ-EDITOR at line (load editor first)" CR
   ." HYPER-REINDEX     rebuild Config/HYPER.NDX, reload" CR
   ." HYPER-RELOAD  .HYPER" CR ;

\ Phase 3a in-app indexer (defines HYPER-REINDEX)
FLOAD hyper-index.fth

HYPER-LOAD DROP

ONLY FORTH DEFINITIONS
