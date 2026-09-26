\ classes.fth
\ Portable subset of the Win32Forth object system
\ (Andrew McKewan / Tom Zimmer, Class.f, public domain, April 2002).
\
\ Forth-2012 only. Limits and host differences: README.txt in this folder.

[DEFINED] ANEW [IF] ANEW CLASSES_MODULE [THEN]

DECIMAL

\ Core requires CELL+ . CELL- is also Core; 64Forth does not provide it.
: CELL- ( a-addr -- a-addr ) 1 CELLS - ;

\ ANS >BODY of a CREATE word is the address HERE had after CREATE.
\ 64Forth keeps a does-pointer in that cell and puts user data one
\ cell later. The probe picks the cell that actually holds 123.
CREATE XTPROBE 123 ,
: XT>DATA ( xt -- a-addr )
    >BODY DUP @ 123 = IF EXIT THEN CELL+ ;

\ ----- string buffers ------------------------------------------------------

VARIABLE STR-A
VARIABLE STR-U

: +STR ( da du sa su -- da du' )
    STR-U ! STR-A !
    2DUP + STR-A @ SWAP STR-U @ MOVE
    STR-U @ + ;

: CH+ ( da du char -- da du' )
    >R 2DUP + R> SWAP C! 1+ ;

: UPCASE ( c-addr u -- )
    OVER + SWAP
    BEGIN 2DUP > WHILE
        DUP C@ DUP [CHAR] a [CHAR] z 1+ WITHIN IF
            [CHAR] a - [CHAR] A + OVER C!
        ELSE DROP THEN
        1+
    REPEAT 2DROP ;

CREATE NAMEBUF 128 ALLOT
VARIABLE NAMELEN
CREATE SELBUF 128 ALLOT
VARIABLE SELLEN
VARIABLE PN-A
VARIABLE PN-U
CREATE SRC 320 ALLOT
CREATE FINDBUF 128 ALLOT
CREATE DOTB 128 ALLOT
VARIABLE DOTBU

: SAVE-NAME ( c-addr u -- )
    DUP 127 > ABORT" name too long"
    DUP NAMELEN ! NAMEBUF SWAP CMOVE
    NAMEBUF NAMELEN @ UPCASE ;

: FIND-NAME ( -- xt true | false )
    NAMELEN @ FINDBUF C!
    NAMEBUF FINDBUF 1+ NAMELEN @ CMOVE
    FINDBUF FIND
    DUP 0= IF DROP DROP FALSE ELSE DROP TRUE THEN ;

: >DOTB ( c-addr u -- )
    DUP 127 > ABORT" name too long"
    DUP DOTBU ! DOTB SWAP CMOVE ;

\ ----- class / ivar layout -------------------------------------------------
\ class: 0 magic 1 link 2 super 3 dfa 4 xfa 5 ivars 6 mwid 7 name 8 flags 9 iwid
\ flags bit 0 = headerless. xfa -1 = not indexed, else element width in bytes.
\ ivar:  0 link 1 off 2 kind 3 a1 4 a2 5 name
\ kind: 1 byte 2 short 3 cell 4 dcell 5 bytes 6 bits 7 object

255 CONSTANT OOP-MAGIC

: CF ( class i -- addr ) CELLS + ;
: CLASS? ( a -- f ) DUP 0= IF EXIT THEN @ OOP-MAGIC = ;

VARIABLE CLASS-LIST
VARIABLE ^CLASS
VARIABLE IN-METHOD
VARIABLE OLD-CURRENT
VARIABLE SAVED-CURRENT
VARIABLE OPEN-OBJECT
VARIABLE BITCNT
VARIABLE BITMAX
VARIABLE REC-START
VARIABLE P-N
VARIABLE P-C
VARIABLE CLONE-SRC

0 VALUE ^BASE

: IV-OFF  ( iv -- a ) 1 CELLS + ;
: IV-KIND ( iv -- a ) 2 CELLS + ;
: IV-A1   ( iv -- a ) 3 CELLS + ;
: IV-A2   ( iv -- a ) 4 CELLS + ;
: IV-NAME ( iv -- a ) 5 CELLS + ;

\ ----- scalar ops (SHORT is little-endian; INT is one cell) ---------------

: (B@)  ( base off -- n ) + C@ ;
: (B!)  ( n base off -- ) + C! ;
: (B+!) ( n base off -- ) + DUP >R C@ + R> C! ;
: (H@)  ( base off -- u ) + DUP C@ SWAP 1+ C@ 8 LSHIFT OR ;
: (H!)  ( n base off -- ) + >R DUP 255 AND R@ C! 8 RSHIFT 255 AND R> 1+ C! ;
: (H+!) ( n base off -- ) 2>R 2R@ (H@) + 2R> (H!) ;
: (C@)  ( base off -- n ) + @ ;
: (C!)  ( n base off -- ) + ! ;
: (C+!) ( n base off -- ) + +! ;
: (D@)  ( base off -- lo hi ) + 2@ ;
: (D!)  ( lo hi base off -- ) + 2! ;
VARIABLE DLO
VARIABLE DCARRY
: (D+!) ( lo hi base off -- )
    + >R SWAP DUP DLO ! R@ @ + DUP DLO @ U< DCARRY !
    SWAP R@ CELL+ @ DCARRY @ + + R> 2! ;
: (ADDR)  ( base off -- a ) + ;
: (OADDR) ( base off -- a ) + CELL+ ;
: (BF@) ( base off shift mask -- n ) >R >R + @ R> RSHIFT R> AND ;
VARIABLE BF-S
: (BF!) ( n base off shift mask -- )
    SWAP BF-S !
    BF-S @ LSHIFT >R
    + SWAP BF-S @ LSHIFT
    R@ AND OVER @ R> INVERT AND OR SWAP ! ;

: IV-GET-XT ( iv -- xt )
    IV-KIND @
    DUP 1 = IF DROP ['] (B@)   EXIT THEN
    DUP 2 = IF DROP ['] (H@)   EXIT THEN
    DUP 3 = IF DROP ['] (C@)   EXIT THEN
    DUP 4 = IF DROP ['] (D@)   EXIT THEN
    DUP 5 = IF DROP ['] (ADDR) EXIT THEN
    DUP 7 = IF DROP ['] (OADDR) EXIT THEN
    DROP ['] (C@) ;

: IV-PUT-XT ( iv -- xt )
    IV-KIND @
    DUP 1 = IF DROP ['] (B!) EXIT THEN
    DUP 2 = IF DROP ['] (H!) EXIT THEN
    DUP 3 = IF DROP ['] (C!) EXIT THEN
    DUP 4 = IF DROP ['] (D!) EXIT THEN
    -1 ABORT" this ivar cannot be stored" ;

: IV-ADD-XT ( iv -- xt )
    IV-KIND @
    DUP 1 = IF DROP ['] (B+!) EXIT THEN
    DUP 2 = IF DROP ['] (H+!) EXIT THEN
    DUP 3 = IF DROP ['] (C+!) EXIT THEN
    -1 ABORT" this ivar cannot be added" ;

\ LIT, / SLIT, perform LITERAL / SLITERAL when a non-immediate word runs.
: LIT, ( n -- ) POSTPONE LITERAL ;
: SLIT, ( c-addr u -- ) POSTPONE SLITERAL ;

: COMPILE-BASE ( off xt -- )
    ['] ^BASE COMPILE, SWAP LIT, COMPILE, ;

: RUN-GET ( iv -- n )
    DUP IV-KIND @ 6 = IF
        ^BASE OVER IV-OFF @ OVER IV-A1 @ SWAP IV-A2 @ (BF@)
    ELSE
        DUP IV-OFF @ SWAP IV-GET-XT ^BASE -ROT EXECUTE
    THEN ;

: RUN-PUT ( x iv -- )
    DUP IV-KIND @ 6 = IF
        >R ^BASE R@ IV-OFF @ R@ IV-A1 @ R> IV-A2 @ (BF!)
    ELSE
        >R ^BASE R@ IV-OFF @ R> IV-PUT-XT EXECUTE
    THEN ;

: COMPILE-GET ( iv -- )
    DUP IV-KIND @ 6 = IF
        ['] ^BASE COMPILE, DUP IV-OFF @ LIT,
        DUP IV-A1 @ LIT, IV-A2 @ LIT, ['] (BF@) COMPILE,
    ELSE
        DUP IV-OFF @ SWAP IV-GET-XT COMPILE-BASE
    THEN ;

: COMPILE-PUT ( iv -- )
    DUP IV-KIND @ 6 = IF
        ['] ^BASE COMPILE, DUP IV-OFF @ LIT,
        DUP IV-A1 @ LIT, IV-A2 @ LIT, ['] (BF!) COMPILE,
    ELSE
        DUP IV-OFF @ SWAP IV-PUT-XT COMPILE-BASE
    THEN ;

: DO-FETCH ( iv -- ) STATE @ IF COMPILE-GET ELSE RUN-GET THEN ;

\ ----- sends ---------------------------------------------------------------

: (SEND) ( obj xt -- )
    ^BASE >R SWAP TO ^BASE CATCH R> TO ^BASE THROW ;

: FIND-METHOD ( c-addr u class -- xt true | false )
    >R BEGIN
        R@ 0= IF R> DROP FALSE EXIT THEN
        2DUP R@ 6 CF @ SEARCH-WORDLIST IF
            >R 2DROP R> R> DROP TRUE EXIT
        THEN
        R> 2 CF @ >R
    AGAIN ;

: SEND-NAME ( obj c-addr u -- )
    2>R DUP CELL- @ 2R> ROT
    FIND-METHOD 0= ABORT" selector not understood" (SEND) ;

: SEND-IF ( obj c-addr u -- )
    2>R DUP CELL- @ 2R> ROT
    FIND-METHOD IF (SEND) ELSE DROP THEN ;

\ ----- instance image ------------------------------------------------------
\ [class pointer][dfa bytes][width][count][elements if indexed]
\ Every object address, including ^BASE, is the first data byte.

: PAYLOAD ( n class -- nbytes )
    DUP >R 3 CF @
    R@ 4 CF @ 0> IF SWAP R> 4 CF @ * + 2 CELLS +
    ELSE NIP R> DROP THEN ;

: SEAT ( n class data -- data )
    >R P-C ! P-N !
    R@ P-C @ 3 CF @ ERASE
    P-C @ 4 CF @ 0> IF
        P-C @ 4 CF @ R@ P-C @ 3 CF @ + !
        P-N @ R@ P-C @ 3 CF @ + CELL+ !
        P-C @ 4 CF @ P-N @ *
        R@ P-C @ 3 CF @ + 2 CELLS + SWAP ERASE
    THEN
    R> ;

DEFER INIT-OBJECT

: INIT-ONE ( data iv -- )
    DUP IV-KIND @ 7 <> IF 2DROP EXIT THEN
    DUP IV-A2 @ P-N !
    DUP IV-A1 @ >R
    IV-OFF @ +
    R@ OVER !
    CELL+
    P-N @ R@ ROT SEAT
    R> INIT-OBJECT ;

: WALK-OLD ( data iv -- )
    DUP 0= IF 2DROP EXIT THEN
    DUP @ >R OVER R> RECURSE INIT-ONE ;

: (INIT-OBJECT) ( data class -- )
    OVER SWAP 5 CF @ WALK-OLD
    S" CLASSINIT:" SEND-IF ;

' (INIT-OBJECT) IS INIT-OBJECT

: PLACE-OBJ ( n class addr -- data )
    ROT >R 2DUP ! CELL+ R> -ROT SEAT ;

: HEAP-OBJ ( n class -- data )
    2DUP PAYLOAD CELL+ ALLOCATE THROW
    PLACE-OBJ DUP DUP CELL- @ INIT-OBJECT ;

: DICT-OBJ ( n class -- data )
    ALIGN 2DUP PAYLOAD CELL+ HERE >R ALLOT
    R> PLACE-OBJ DUP DUP CELL- @ INIT-OBJECT ;

\ ----- defining ivars ------------------------------------------------------

: ",NAME" ( -- c-addr )
    HERE >R NAMELEN @ C,
    NAMEBUF NAMELEN @ R@ 1+ SWAP CMOVE
    NAMELEN @ ALLOT ALIGN R> ;

: MAKE-NODE ( off kind a1 a2 -- iv )
    ALIGN HERE >R
    >R >R >R
    ^CLASS @ 5 CF @ ,
    , R> , R> , R> , 0 ,
    ",NAME" R@ 5 CELLS + !
    R@ ^CLASS @ 5 CF !
    R> ;

: (IVWORD) ( iv "name" -- ) ALIGN CREATE , DOES> @ DO-FETCH ;
: MARK-IMM ( -- ) ['] IMMEDIATE EXECUTE ;

: (FIELD) ( off kind a1 a2 "name" -- )
    ^CLASS @ 0= ABORT" not inside a class"
    SAVE-INPUT PARSE-NAME SAVE-NAME RESTORE-INPUT THROW
    MAKE-NODE
    GET-CURRENT >R
    ^CLASS @ 9 CF @ SET-CURRENT
    (IVWORD) MARK-IMM
    R> SET-CURRENT ;

: +DFA ( n -- ) ^CLASS @ 3 CF +! ;
: (BITMAX) ( n -- ) DUP BITCNT ! BITMAX ! ;
: MASK-N ( n -- mask ) 0 SWAP 0 ?DO 1 LSHIFT 1 OR LOOP ;

: BYTE ( "name" -- )
    ^CLASS @ 3 CF @ 1 +DFA 1 0 0 (FIELD) 8 (BITMAX) ;

: SHORT ( "name" -- )
    ^CLASS @ 3 CF @ 2 +DFA 2 0 0 (FIELD) 16 (BITMAX) ;

: INT ( "name" -- )
    ^CLASS @ 3 CF @ 1 CELLS +DFA 3 0 0 (FIELD) 1 CELLS 8 * (BITMAX) ;

: DINT ( "name" -- )
    ^CLASS @ 3 CF @ 2 CELLS +DFA 4 0 0 (FIELD) 0 (BITMAX) ;

: BYTES ( n "name" -- )
    ^CLASS @ 3 CF @ SWAP DUP +DFA 5 SWAP 0 (FIELD) 0 (BITMAX) ;

: BITS ( n "name" -- )
    DUP 0= ABORT" zero length bit field"
    BITCNT @ BITMAX @ = IF 0 BITCNT ! THEN
    BITCNT @ OVER + BITMAX @ > ABORT" bit field does not fit"
    >R
    ^CLASS @ 3 CF @ 1 CELLS -
    6 BITCNT @ R@ MASK-N
    (FIELD)
    R> BITCNT +! ;

\ ----- classes -------------------------------------------------------------

VARIABLE NB-A  VARIABLE NB-U  VARIABLE NB-F

: LINK-CLASS ( class c-addr flags -- )
    >R >R
    DUP 7 CF R> SWAP !
    DUP 8 CF R> SWAP !
    DUP CLASS-LIST @ SWAP 1 CF !
    CLASS-LIST ! ;

: NEW-CLASS ( c-addr u flags -- class )
    NB-F ! NB-U ! NB-A !
    WORDLIST WORDLIST ALIGN HERE >R
    OOP-MAGIC , 0 , 0 , 0 , -1 , 0 , SWAP , 0 , 0 , ,
    R@ NB-A @ NB-U @ SAVE-NAME ",NAME" NB-F @ LINK-CLASS
    R> ;

: XT-CLASS? ( xt -- f ) XT>DATA CLASS? ;
: XT-OBJ?   ( xt -- f ) XT>DATA @ CLASS? ;

: ADD-OBJ-IVAR ( n class "name" -- )
    2DUP PAYLOAD CELL+ >R
    ^CLASS @ 3 CF @ R> +DFA
    SWAP >R SWAP 7 SWAP R> SWAP
    (FIELD) ;

: MAKE-NAMED ( n class "name" -- )
    ALIGN CREATE
        HERE >R 2DUP PAYLOAD CELL+ ALLOT
        R> PLACE-OBJ DUP DUP CELL- @ INIT-OBJECT
        CLONE-SRC @ IF
            >R CLONE-SRC @ R@ R@ CELL- @ 3 CF @ CMOVE R> DROP
        ELSE DROP THEN
    DOES> CELL+ ;

: (BUILD) ( class -- )
    DUP 4 CF @ 0> IF SWAP ELSE 0 SWAP THEN
    ^CLASS @ IF
        ADD-OBJ-IVAR
    ELSE
        DUP 8 CF @ 1 AND IF DICT-OBJ ELSE MAKE-NAMED THEN
    THEN ;

VARIABLE CLASS-FLAGS
VARIABLE MWID
VARIABLE IWID

: LAY-BODY ( -- class )
    ALIGN HERE >R
    OOP-MAGIC , 0 , 0 , 0 , -1 , 0 , MWID @ , 0 , 0 , IWID @ ,
    R@
    ",NAME"
    CLASS-FLAGS @ LINK-CLASS
    R> ;

: (CLASS) ( "name" -- )
    GET-CURRENT OLD-CURRENT !
    FALSE OPEN-OBJECT !
    SAVE-INPUT PARSE-NAME SAVE-NAME RESTORE-INPUT THROW
    WORDLIST MWID ! WORDLIST IWID !
    ALIGN CREATE
        LAY-BODY ^CLASS !
    DOES> (BUILD) ;

: :CLASS ( "name" -- ) 0 CLASS-FLAGS ! (CLASS) ;
: |CLASS ( "name" -- ) 1 CLASS-FLAGS ! (CLASS) ;

: <SUPER ( "name" -- )
    ^CLASS @ 0= ABORT" not inside a class"
    PARSE-NAME SAVE-NAME FIND-NAME 0= ABORT" superclass not found"
    DUP XT-CLASS? IF XT>DATA
    ELSE DUP XT-OBJ? 0= ABORT" not a class or an object" XT>DATA @ THEN
    DUP ^CLASS @ 2 CF !
    DUP 3 CF @ ^CLASS @ 3 CF !
    5 CF @ ^CLASS @ 5 CF ! ;

: <INDEXED ( width -- )
    ^CLASS @ 0= ABORT" not inside a class" ^CLASS @ 4 CF ! ;

: ;CLASS ( -- )
    OPEN-OBJECT @ ABORT" ;OBJECT closes :OBJECT"
    ^CLASS @ 0= ABORT" ;CLASS without :CLASS or |CLASS"
    0 ^CLASS ! OLD-CURRENT @ SET-CURRENT ;

CREATE ONAME 128 ALLOT
VARIABLE OLEN

: :OBJECT ( "name" -- )
    GET-CURRENT OLD-CURRENT !
    TRUE OPEN-OBJECT !
    PARSE-NAME SAVE-NAME
    NAMEBUF ONAME NAMELEN @ CMOVE NAMELEN @ OLEN !
    NAMEBUF NAMELEN @ 0 NEW-CLASS ^CLASS ! ;

: ;OBJECT ( -- )
    OPEN-OBJECT @ 0= ABORT" ;CLASS closes :CLASS"
    ^CLASS @ 0= ABORT" ;OBJECT without :OBJECT"
    0 ^CLASS @
    0 ^CLASS ! FALSE OPEN-OBJECT ! OLD-CURRENT @ SET-CURRENT
    SRC 0 S" MAKE-NAMED " +STR ONAME OLEN @ +STR
    EVALUATE ;

\ ----- methods, TO, selectors ----------------------------------------------

CREATE ORD 24 CELLS ALLOT
VARIABLE ORDN
CREATE NORD 24 CELLS ALLOT
VARIABLE NORDN
WORDLIST CONSTANT OOP-WL

: REMEMBER-ORDER ( -- )
    GET-ORDER DUP 24 > ABORT" search order too deep"
    DUP ORDN ! 0 ?DO I CELLS ORD + ! LOOP ;

: PUSH-NORD ( wid -- ) NORD NORDN @ CELLS + ! 1 NORDN +! ;

: APPLY-NORD ( -- )
    NORDN @ 0 ?DO NORDN @ I - 1- CELLS NORD + @ LOOP
    NORDN @ SET-ORDER ;

: METHOD-ORDER ( class -- )
    0 NORDN ! OOP-WL PUSH-NORD
    BEGIN DUP WHILE DUP 9 CF @ PUSH-NORD 2 CF @ REPEAT DROP
    ORDN @ 0 ?DO I CELLS ORD + @ PUSH-NORD LOOP
    APPLY-NORD ;

: RESTORE-ORDER ( -- )
    ORDN @ 0 ?DO ORDN @ I - 1- CELLS ORD + @ LOOP
    ORDN @ SET-ORDER ;

: FIND-IVAR ( c-addr u class -- iv true | false )
    >R SAVE-NAME
    BEGIN R@ 0= IF R> DROP FALSE EXIT THEN
        R@ 5 CF @
        BEGIN DUP WHILE
            DUP IV-NAME @ COUNT NAMEBUF NAMELEN @ COMPARE 0= IF
                R> DROP TRUE EXIT
            THEN
            @
        REPEAT DROP
        R> 2 CF @ >R
    AGAIN ;

' TO VALUE SYS-TO
GET-CURRENT             \ ( -- wid )
OOP-WL SET-CURRENT      \ set the wordlist to the OOP-WL while defining TO
WARNING @               \ ( -- wid warning-flag )
0 WARNING !             \ no warning when we redefine TO

: TO ( x "name" -- )
    >IN @ >R PARSE-NAME
    ^CLASS @ IF 2DUP ^CLASS @ FIND-IVAR IF
        NIP NIP R> DROP
        STATE @ IF COMPILE-PUT ELSE RUN-PUT THEN EXIT
    THEN THEN
    R> >IN ! SYS-TO EXECUTE ; IMMEDIATE

( wid warning-flag -- ) WARNING ! SET-CURRENT

VARIABLE MWARN

: (LATE) ( obj c-addr u -- ) SEND-NAME ;

: APPLY-IVAR ( iv c-addr u -- )
    ROT >R
    DUP SELLEN ! SELBUF SWAP CMOVE
    SELBUF SELLEN @ UPCASE
    R>
    SELBUF SELLEN @ S" PUT:" COMPARE 0= IF
        STATE @ IF COMPILE-PUT ELSE RUN-PUT THEN EXIT THEN
    SELBUF SELLEN @ S" ADD:" COMPARE 0= IF
        DUP IV-KIND @ 4 = IF
            STATE @ IF ['] ^BASE COMPILE, IV-OFF @ LIT, ['] (D+!) COMPILE,
            ELSE ^BASE SWAP IV-OFF @ (D+!) THEN
        ELSE
            DUP IV-ADD-XT >R IV-OFF @ R>
            STATE @ IF COMPILE-BASE ELSE ^BASE -ROT EXECUTE THEN
        THEN EXIT THEN
    DUP IV-KIND @ 7 = IF
        DUP IV-A1 @ SELBUF SELLEN @ ROT FIND-METHOD
        0= ABORT" selector not understood"
        SWAP IV-OFF @ SWAP
        STATE @ IF
            ['] ^BASE COMPILE, SWAP LIT, ['] + COMPILE, ['] CELL+ COMPILE,
            LIT, ['] (SEND) COMPILE,
        ELSE >R ^BASE SWAP + CELL+ R> (SEND) THEN
        EXIT THEN
    SELBUF SELLEN @ S" AND:" COMPARE 0=
    SELBUF SELLEN @ S" OR:"  COMPARE 0= OR
    SELBUF SELLEN @ S" XOR:" COMPARE 0= OR IF
        >R STATE @ IF
            R@ COMPILE-GET
            SELBUF C@ [CHAR] A = IF ['] AND COMPILE, THEN
            SELBUF C@ [CHAR] O = IF ['] OR  COMPILE, THEN
            SELBUF C@ [CHAR] X = IF ['] XOR COMPILE, THEN
            R> COMPILE-PUT
        ELSE
            R@ RUN-GET
            SELBUF C@ [CHAR] A = IF AND THEN
            SELBUF C@ [CHAR] O = IF OR  THEN
            SELBUF C@ [CHAR] X = IF XOR THEN
            R> RUN-PUT
        THEN EXIT THEN
    STATE @ IF COMPILE-GET ELSE RUN-GET THEN ;

: TAKE-HEAD ( -- more? )
    0 BEGIN DUP DOTBU @ < WHILE
        DUP DOTB + C@ [CHAR] . = IF
            DOTB OVER SAVE-NAME
            DUP 1+ DOTB + DOTB ROT
            DOTBU @ OVER - 1- CMOVE
            DOTBU @ SWAP - 1- DOTBU !
            TRUE EXIT
        THEN
        1+
    REPEAT DROP
    DOTB DOTBU @ SAVE-NAME 0 DOTBU ! FALSE ;

: DOT-RUNTIME ( data class c-addr u sel-addr sel-u -- )
    DUP SELLEN ! SELBUF SWAP CMOVE DROP
    SELBUF SELLEN @ UPCASE
    >DOTB
    BEGIN
        TAKE-HEAD >R
        NAMEBUF NAMELEN @ 2 PICK FIND-IVAR 0= ABORT" no such ivar"
        R> IF
            DUP IV-KIND @ 7 <> ABORT" dotted name is not an object"
            >R NIP R@ IV-OFF @ SWAP + CELL+ R> IV-A1 @
        ELSE
            DUP IV-KIND @ 7 = IF
                >R NIP R@ IV-OFF @ SWAP + CELL+ R> IV-A1 @
                SELBUF SELLEN @ SEND-NAME EXIT
            THEN
            >R DROP ^BASE >R TO ^BASE
            R> SELBUF SELLEN @ APPLY-IVAR
            R> TO ^BASE EXIT
        THEN
    AGAIN ;

: HEAD-REST ( c-addr u -- ha hu ra ru )
    DUP 0= IF 0 0 EXIT THEN
    0 BEGIN DUP 2 PICK < WHILE
        DUP 3 PICK + C@ [CHAR] . = IF
            >R OVER R@ 2SWAP R> 1+ /STRING EXIT
        THEN
        1+
    REPEAT DROP
    0 0 ;

: BIND-KNOWN ( data class -- )
    SELBUF SELLEN @ ROT FIND-METHOD
    STATE @ IF
        IF SWAP LIT, LIT, ['] (SEND) COMPILE,
        ELSE DROP LIT, SELBUF SELLEN @ SLIT, ['] (LATE) COMPILE, THEN
    ELSE
        IF (SEND) ELSE SELBUF SELLEN @ (LATE) THEN
    THEN ;

: BIND-BASE ( class -- )
    SELBUF SELLEN @ ROT FIND-METHOD
    STATE @ IF
        IF ['] ^BASE COMPILE, LIT, ['] (SEND) COMPILE,
        ELSE ['] ^BASE COMPILE, SELBUF SELLEN @ SLIT, ['] (LATE) COMPILE, THEN
    ELSE
        IF ^BASE SWAP (SEND) ELSE ^BASE SELBUF SELLEN @ (LATE) THEN
    THEN ;

: DOTTED ( c-addr u -- )
    HEAD-REST
    2SWAP
    ^CLASS @ IF 2DUP ^CLASS @ FIND-IVAR IF
        >R 2DROP R>
        DUP IV-KIND @ 7 <> ABORT" dotted name is not an object"
        DUP IV-A1 @ SWAP IV-OFF @
        ( class off  and rest is under )
        \ stack: ra ru class off
        STATE @ IF
            ['] ^BASE COMPILE, SWAP LIT, ['] + COMPILE, ['] CELL+ COMPILE,
            LIT,
            2SWAP SLIT,
            SELBUF SELLEN @ SLIT, ['] DOT-RUNTIME COMPILE,
        ELSE
            ^BASE SWAP + CELL+ SWAP
            2SWAP SELBUF SELLEN @ DOT-RUNTIME
        THEN
        EXIT
    THEN THEN
    SAVE-NAME FIND-NAME 0= ABORT" object not found"
    DUP XT-OBJ? 0= ABORT" not an object"
    DUP XT>DATA CELL+ SWAP XT>DATA @
    ( data class ) 2SWAP
    STATE @ IF
        2SWAP SWAP LIT, LIT,
        2SWAP SLIT, SELBUF SELLEN @ SLIT, ['] DOT-RUNTIME COMPILE,
    ELSE
        2SWAP SELBUF SELLEN @ DOT-RUNTIME
    THEN ;

\ Runs as the last word of a bracketed receiver. The bracket text is
\ EVALUATEd and this word performs the send, so nothing has to run
\ after EVALUATE (64Forth does not resume the caller).
: LATE-TAIL ( -- )
    STATE @ IF
        SELBUF SELLEN @ SLIT, ['] (LATE) COMPILE,
    ELSE
        SELBUF SELLEN @ (LATE)
    THEN ; IMMEDIATE

: DO-BRACKETS ( -- )
    [CHAR] ] PARSE
    SRC 0 2SWAP +STR
    S"  LATE-TAIL" +STR
    EVALUATE ;

: MESSAGE ( c-addr u -- )
    DUP SELLEN ! SELBUF SWAP CMOVE SELBUF SELLEN @ UPCASE
    PARSE-NAME DUP 0= ABORT" selector needs a receiver"
    2DUP S" [" COMPARE 0= IF 2DROP DO-BRACKETS EXIT THEN
    2DUP S" SELF" COMPARE 0= IF
        2DROP ^CLASS @ 0= ABORT" SELF outside a method"
        ^CLASS @ BIND-BASE EXIT
    THEN
    2DUP S" SUPER" COMPARE 0= IF
        2DROP ^CLASS @ 0= ABORT" SUPER outside a method"
        ^CLASS @ 2 CF @ DUP 0= ABORT" no superclass"
        BIND-BASE EXIT
    THEN
    ^CLASS @ IF 2DUP ^CLASS @ FIND-IVAR IF
        >R 2DROP R> SELBUF SELLEN @ APPLY-IVAR EXIT
    THEN THEN
    PN-U ! PN-A !
    0 PN-U @ BEGIN 2DUP > WHILE
        OVER PN-A @ + C@ [CHAR] . = IF
            2DROP PN-A @ PN-U @ DOTTED EXIT
        THEN
        1+
    REPEAT 2DROP
    PN-A @ PN-U @
    SAVE-NAME FIND-NAME 0= ABORT" receiver not found"
    DUP XT-OBJ? IF DUP XT>DATA CELL+ SWAP XT>DATA @ BIND-KNOWN EXIT THEN
    XT-CLASS? ABORT" send to a class is not supported"
    -1 ABORT" receiver is not an object" ;

: (SEL) ( -- )
    ALIGN CREATE ",NAME" DROP DOES> COUNT MESSAGE ;

: MAKE-SELECTOR ( -- )
    RESTORE-INPUT THROW
    SAVE-INPUT
    GET-CURRENT >R
    FORTH-WORDLIST SET-CURRENT
    (SEL) MARK-IMM
    R> SET-CURRENT ;

: :M ( "name" -- )
    ^CLASS @ 0= ABORT" not inside a class"
    IN-METHOD @ ABORT" nested :M"
    SAVE-INPUT
    PARSE-NAME DUP 0= ABORT" :M needs a name" SAVE-NAME
    NAMEBUF NAMELEN @ ^CLASS @ 6 CF @ SEARCH-WORDLIST
    IF DROP NAMEBUF NAMELEN @ TYPE ."  is redefined" CR THEN
    NAMEBUF NAMELEN @ FORTH-WORDLIST SEARCH-WORDLIST
    IF DROP ELSE MAKE-SELECTOR THEN
    RESTORE-INPUT THROW
    REMEMBER-ORDER
    GET-CURRENT SAVED-CURRENT !
    ^CLASS @ 6 CF @ SET-CURRENT
    ^CLASS @ METHOD-ORDER
    WARNING @ MWARN !
    0 WARNING !
    TRUE IN-METHOD ! ALIGN : ;

: ;M ( -- )
    IN-METHOD @ 0= ABORT" ;M without :M"
    POSTPONE ;
    MWARN @ WARNING !
    FALSE IN-METHOD !
    SAVED-CURRENT @ SET-CURRENT
    RESTORE-ORDER ; IMMEDIATE

\ ----- heap, clone, records, root class ------------------------------------

: NEW> ( "class" -- data )
    PARSE-NAME SAVE-NAME FIND-NAME 0= ABORT" NEW> needs a class"
    DUP XT-CLASS? 0= ABORT" NEW> needs a class" XT>DATA
    DUP 4 CF @ 0> IF
        STATE @ IF LIT, ['] HEAP-OBJ COMPILE, ELSE HEAP-OBJ THEN
    ELSE
        STATE @ IF 0 LIT, LIT, ['] HEAP-OBJ COMPILE,
        ELSE 0 SWAP HEAP-OBJ THEN
    THEN ; IMMEDIATE

: DISPOSE ( data -- )
    DUP >R DROP
    R@ CELL- @ S" ~:" ROT FIND-METHOD
    IF R@ SWAP (SEND) ELSE 2DROP THEN
    R> CELL- FREE THROW ;

: CLONE ( obj-xt "name" -- )
    DUP XT-OBJ? 0= ABORT" CLONE needs an object"
    DUP XT>DATA CELL+ >R
    XT>DATA @
    DUP 4 CF @ 0> IF DUP 3 CF @ R@ + CELL+ @ ELSE 0 THEN
    SWAP R> CLONE-SRC ! MAKE-NAMED
    0 CLONE-SRC ! ;

: .CLASSES ( -- )
    CLASS-LIST @ BEGIN DUP WHILE CR DUP 7 CF @ COUNT TYPE 1 CF @ REPEAT DROP ;

: RECORD: ( -- )
    ^CLASS @ 0= ABORT" not inside a class" ^CLASS @ 3 CF @ REC-START ! ;

: ;RECORD ( -- ) ;

: ;RECORDSIZE: ( "name" -- )
    ^CLASS @ 3 CF @ REC-START @ - ALIGN CONSTANT ;

: SELF ( -- addr ) STATE @ IF ['] ^BASE COMPILE, ELSE ^BASE THEN ; IMMEDIATE

:CLASS OBJECT
:M CLASSINIT: ;M
:M ~: ;M
:M ADDR: ( -- addr ) ^BASE ;M
:M PRINT: ( -- ) ." Object@" ^BASE U. ;M
;CLASS

.( classes.fth loaded) CR
