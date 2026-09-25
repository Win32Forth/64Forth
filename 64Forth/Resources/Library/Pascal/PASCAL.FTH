\ PASCAL.FTH  Tiny Pascal Forth  (Tom Zimmer, 1987-91)
\ Port to 64Forth, Forth-2012, 64-bit cells.
\ Public domain.  See Library/Pascal/README.txt.

ANEW PASCAL_MODULE

\ FILE-ECHO ON
ONLY FORTH ALSO DEFINITIONS DECIMAL

\ { } comment to next } (Win32Forth-style; spans the current SOURCE refill)
[UNDEFINED] { [IF]
: {  ( -- )  [CHAR] } PARSE 2DROP ; IMMEDIATE
[THEN]

\ ---------- compatibility ----------

: 0MAX  ( n -- n )  0 MAX ;

: BETWEEN  ( n lo hi -- f )  1+ WITHIN ;

\ ulo <= u <= uhi  (WITHIN is lo<=n<hi, so hi+1 makes the high end inclusive)
: UBETWEEN  ( u ulo uhi -- f )  1+ WITHIN ;

\ 64Forth: EXIT before THEN ends the colon definition (like ';'), so
\ "IF EXIT THEN" must not be used.  ?EXIT drops the caller's return.

[UNDEFINED] ?EXIT [IF]
: ?EXIT  ( flag -- )  POSTPONE IF POSTPONE EXIT POSTPONE THEN ; IMMEDIATE
[THEN]

: BOUNDS  ( a n -- a+n a )  OVER + SWAP ;

: NOOP ;

: ,"  ( -- )
    HERE  8 ALLOT
    DUP 8 ERASE
    [CHAR] " PARSE  7 MIN
    ROT PLACE ALIGN ;

\ Jump table after EXEC: in the caller. R> takes the table address (and
\ abandons falling through the table). @ EXECUTE runs the selected word;
\ then EXIT returns to EXEC:'s caller.  (@ >R is DTC-style and faults on
\ 64Forth ITC: EXIT would set IP to a CFA, and NEXT/DOEXIT blow up.)
: EXEC:  ( n -- )  R> SWAP 31 AND CELLS + @ EXECUTE ;

\ at end of definition, return to caller's caller, not caller directly
: R>DROP  R> R> DROP >R ;

: NUMBER?  ( c-addr -- n dummy flag )
    COUNT  OVER C@ [CHAR] - = DUP >R
    IF  1 /STRING  THEN
    0 0  2SWAP  >NUMBER             ( ud a u )
    NIP 0=                          ( ud f )
    R> IF  ROT NEGATE -ROT  THEN    \ negate low if needed
    >R  DROP  0  R> ;               \ n  0  flag
    
\ No locals: EXIT inside {: … :} was dropping the comparison result, so
\ A$SRCH treated every name as a keyword (TYP=0) → "Identifier Expected".
\ BL OR folds A–Z/a–z so "Integer" matches KW-TABLE "integer".
\ No EXIT-before-THEN (truncates the definition on 64Forth).
VARIABLE CAPS-DIFF
\ No LEAVE/EXIT — LEAVE inside CAPS-COMP faulted when called from $INCON's +LOOP.
: CAPS-COMP  ( a1 a2 -- n )
    0 CAPS-DIFF !
    OVER C@ OVER C@ MIN 1+ 1
    ?DO  CAPS-DIFF @ 0= IF
            OVER I + C@ BL OR  OVER I + C@ BL OR  -
            ?DUP IF CAPS-DIFF ! THEN
         THEN
    LOOP
    CAPS-DIFF @ ?DUP IF >R 2DROP R> ELSE SWAP C@ SWAP C@ - THEN ;

\ : TEST 	
\	C" HELLO " C" HELLO" CAPS-COMP .
\	C" HELLO" C" HELLO " CAPS-COMP .
\	C" HELLO"  C" HELLO" CAPS-COMP . 
\	C" HELLO " C" HELLO " CAPS-COMP . ;
	
VARIABLE #OUT
0 VALUE PAS-OUT-FID          \ 0 = console; else file-id for PASCAL-TO-FILE
CREATE PAS-CH 1 ALLOT

: PAS-EMIT  ( c -- )
    PAS-OUT-FID IF
        PAS-CH C!  PAS-CH 1 PAS-OUT-FID WRITE-FILE THROW
    ELSE  EMIT
    THEN ;
: PAS-TYPE  ( a n -- )
    PAS-OUT-FID IF
        PAS-OUT-FID WRITE-FILE THROW
    ELSE  TYPE
    THEN ;
: PAS-CR  ( -- )
    PAS-OUT-FID IF
        S\" \n" PAS-OUT-FID WRITE-FILE THROW
    ELSE  CR
    THEN ;
: PAS-SPACES  ( n -- )
    DUP 0> IF  0 DO BL PAS-EMIT LOOP  ELSE  DROP  THEN ;

: CROUT     PAS-CR  #OUT OFF ;
: CROUT+    CROUT  2 PAS-SPACES  2 #OUT ! ;
: SP>COL    ( n -- )
    #OUT @ - DUP 0> IF DUP PAS-SPACES #OUT +! ELSE DROP THEN ;
: CROUT++
    6 SP>COL  #OUT @ 6 > IF CROUT 6 PAS-SPACES 6 #OUT ! THEN ;

80 VALUE COLS
: ?NLINE  ( n -- )  #OUT @ + COLS 10 - > IF CROUT++ THEN ;
\ Track width without DUP after TYPE (that underflows or duplicates buried cells).
: "OUT    ( a n -- )
    127 MIN  DUP ?NLINE  2DUP PAS-TYPE  BL PAS-EMIT  NIP #OUT +!  1 #OUT +! ;
: $OUT    ( a -- )  COUNT "OUT ;
: CHROUT  ( c -- )  PAS-EMIT  BL PAS-EMIT  2 #OUT +! ;
: COUT    ( c -- )  1 ?NLINE PAS-EMIT  1 #OUT +! ;
: ##OUT   ( n -- )
    0 <# #S #>  DUP ?NLINE  2DUP PAS-TYPE  BL PAS-EMIT  NIP #OUT +!  1 #OUT +! ;


\ ---------- file input (ANS File-Access, no TSREAD) ----------

CREATE PASTIB  256 ALLOT
VARIABLE PASIN
VARIABLE PASLEN
VARIABLE PASFID          \ 0 = closed
VARIABLE SAV-IN
VARIABLE SAV-LEN
CREATE SAV-TIB  256 ALLOT
CREATE WORD-PAD 256 ALLOT

: INSAVE
    PASIN @ SAV-IN !  PASLEN @ SAV-LEN !
    PASTIB SAV-TIB 256 MOVE ;

: INREC
    SAV-IN @ PASIN !  SAV-LEN @ PASLEN !
    SAV-TIB PASTIB 256 MOVE ;

: INSET  ( a n -- )
    INSAVE  DUP PASLEN !  PASTIB SWAP MOVE  PASIN OFF ;

\ Skip blanks, then gather a blank-delimited word into WORD-PAD.
: PASWORD  ( -- c-addr )
    BEGIN
        PASIN @ PASLEN @ >= IF TRUE ELSE
        PASIN @ PASTIB + C@ BL > IF TRUE ELSE
        1 PASIN +! FALSE THEN THEN
    UNTIL
    0 WORD-PAD C!
    BEGIN
        PASIN @ PASLEN @ >= IF TRUE ELSE
        PASIN @ PASTIB + C@ BL > 0= IF TRUE ELSE
        PASIN @ PASTIB + C@ WORD-PAD COUNT + C!
        WORD-PAD C@ 1+ WORD-PAD C!
        1 PASIN +! FALSE THEN THEN
    UNTIL
    WORD-PAD ;

0 VALUE PAS-EOF

: PAS-CLOSE  ( -- )
    PASFID @ IF  PASFID @ CLOSE-FILE DROP  0 PASFID !  THEN
    PASIN OFF  PASLEN OFF  FALSE TO PAS-EOF ;

: PAS-OPEN  ( c-addr u -- )
    PAS-CLOSE
    R/O OPEN-FILE ABORT" Couldn't open file."
    PASFID ! ;

\ READ-LINE flag false = EOF.  A blank line is flag true with u=0 —
\ that must NOT be treated as EOF (CHARREAD used to ABORT on PASLEN=0).
: PASQUERY  ( -- )
    PASFID @ 0= ABORT" A file MUST be open."
    PASTIB 255 PASFID @ READ-LINE ABORT" READ-LINE failed"
    0= IF  PASLEN OFF  PASIN OFF  TRUE TO PAS-EOF  EXIT  THEN
    FALSE TO PAS-EOF
    PASLEN !
    PASIN OFF
    #OUT @ DUP >R 39 > IF CROUT THEN
    40 SP>COL  S" \ " PAS-TYPE  PASTIB PASLEN @ PAS-TYPE
    CROUT  R> 6 > IF 6 PAS-SPACES 6 #OUT ! THEN ;

: CHARREAD  ( -- c )
    BEGIN
        PASIN @ PASLEN @ >= IF
            PAS-EOF ABORT" End of file"
            PASQUERY
        ELSE
            PASTIB PASIN @ + C@
            1 PASIN +!
            EXIT
        THEN
    AGAIN ;

\ ---------- translator state ----------

0 VALUE NO-CONST-OR-VARS
0 VALUE CHRPR
0 VALUE TYP
0 VALUE CHAR-
0 VALUE ARRAYSIZE
0 VALUE VARCNT
0 VALUE PTYP
0 VALUE PARCNT
0 VALUE CMD-INDEX

256 CONSTANT A$/SIZE
CREATE A$   A$/SIZE ALLOT
CREATE VAR$ A$/SIZE ALLOT

DEFER LIMTYP

: CLRBUF  ( a -- )  DUP A$/SIZE ERASE  0 SWAP C! ;

: TOKENPRON   TRUE  TO CHRPR ;
: TOKENPROFF  FALSE TO CHRPR ;

: A-Z  ( c -- f )  BL OR  [CHAR] a [CHAR] z BETWEEN ;
: A-F  ( c -- f )  BL OR  [CHAR] a [CHAR] f BETWEEN ;

: NOT0-F  ( c -- f )
    BL OR DUP [CHAR] 0 [CHAR] f BETWEEN 0=
    SWAP [CHAR] 9 [CHAR] a BETWEEN OR ;

: NOTA-ZOR0-9  ( c -- f )
    BL OR DUP [CHAR] 0 [CHAR] z BETWEEN 0=
    SWAP [CHAR] 9 [CHAR] a WITHIN OR ;

: TYPCK  ( n -- )  CREATE C,  DOES> C@ TYP = ;

 0 TYPCK KEYWORD?     1 TYPCK IDENT?
 2 TYPCK ==?          3 TYPCK CHAR?
 4 TYPCK #?           5 TYPCK :=?
 6 TYPCK :?           7 TYPCK <?
 8 TYPCK <=?          9 TYPCK <>?
10 TYPCK >=?         11 TYPCK >?
12 TYPCK STRING?     14 TYPCK (?
15 TYPCK )?

: KEYCK  ( n -- )  CREATE C,  DOES> C@ CMD-INDEX = KEYWORD? AND ;

 0 KEYCK AND?         1 KEYCK ARRAY?
 2 KEYCK BEGIN?       3 KEYCK NEWLINE?
 4 KEYCK CASE?        5 KEYCK CONST?
 6 KEYCK DIV?         7 KEYCK DO???
 8 KEYCK DOWNTO?      9 KEYCK ELSE?
10 KEYCK ENDD?       11 KEYCK FOR?
12 KEYCK FUNC?       13 KEYCK IF?
14 KEYCK INTEGER?    15 KEYCK MEM?
16 KEYCK MOD?        17 KEYCK NOT?
18 KEYCK OF?         19 KEYCK OR?
20 KEYCK PROC?       21 KEYCK READ?
22 KEYCK REPEAT?     23 KEYCK SHL?
24 KEYCK SHR?        25 KEYCK THEN?
26 KEYCK TO?         27 KEYCK TYPE?
28 KEYCK UNTIL?      29 KEYCK VAR?
30 KEYCK WHILE?      31 KEYCK WRITE?
32 KEYCK IN?

: CRCK  ( c -- )  CREATE C,  DOES> C@ CHAR- = CHAR? AND ;

CHAR ; CRCK ;?     CHAR . CRCK .?
CHAR [ CRCK [?     CHAR ] CRCK ]?
CHAR * CRCK *?     CHAR - CRCK -?
CHAR + CRCK +?     CHAR , CRCK ,?
CHAR # CRCK ##?

: A$=A$+CHAR  ( c -- )  
	DUP 0 >					\ if c is not null 
	IF 	A$ COUNT + C!  A$ C@ 1+ A$ C! 	\ then append it to A$
	ELSE	DROP				\ other wise discard it
	THEN 	;

\ Pack A$ into VAR$ with a trailing blank separator for later PASWORD/INSET.
\ Must use A$ COUNT — scanning for BL past A$ faults when the name has no
\ trailing blank in the buffer (common after TOKEN; also breaks "a, b, c").
: VAR$MOVE
    A$ COUNT  DUP >R  VAR$ COUNT +  SWAP MOVE
    BL  VAR$ 1+ VAR$ C@ + R@ +  C!
    R> 1+ VAR$ C@ + VAR$ C!
    VARCNT 1+ TO VARCNT ;

: "PABORT  ( f a n -- )
    ROT IF
        CROUT  PASTIB PASLEN @ "OUT
        CROUT  PASIN @ SPACES  S" ^ - " "OUT
        "OUT  TRUE ABORT" Pascal Error"
    ELSE  2DROP
    THEN ;

: TO-OR-DOWNTO??  TO? DOWNTO? OR 0=  S" To Expected !"            "PABORT ;
: IDENT??     IDENT?   0=  S" Identifier Expected !"             "PABORT ;
: KEYWORD??   KEYWORD? 0=  S" Keyword Expected !"                "PABORT ;
: :??         :?       0=  S" ':' Expected !"                    "PABORT ;
: (??         (?       0=  S" '(' Expected !"                    "PABORT ;
: )??         )?       0=  S" ')' Expected !"                    "PABORT ;
: :=??        :=?      0=  S" ':=' Expected !"                   "PABORT ;
: ==??        ==?      0=  S" '=' Expected !"                    "PABORT ;
: ;??         ;?       0=  S" ';' Expected !"                    "PABORT ;
: .??         .?       0=  S" '.' Expected !"                    "PABORT ;
: [??         [?       0=  S" '[' Expected !"                    "PABORT ;
: ]??         ]?       0=  S" ']' Expected !"                    "PABORT ;
: #??         #?       0=  S" Number Expected !"                 "PABORT ;
: #A??        #?       0=  S" No Consts or Vars Allowed here !"  "PABORT ;
: INTEGER??   INTEGER? 0=  S" Integer Expected !"                "PABORT ;
: UNTIL??     UNTIL?   0=  S" Until Expected !"                  "PABORT ;
: MEM??       MEM?     0=  S" Incorrect Keyword !"               "PABORT ;
: DO??        DO???    0=  S" Do Expected !"                     "PABORT ;
: TO??        TO?      0=  S" To Expected !"                     "PABORT ;
: OF??        OF?      0=  S" Of Expected !"                     "PABORT ;
: END??       ENDD?    0=  S" End Expected !"                    "PABORT ;
: THEN??      THEN?    0=  S" Then Expected !"                   "PABORT ;
: STRING??    STRING?  0=  S" Number Expected !"                 "PABORT ;
: FOUND??     0= S" Error in variable create process"            "PABORT ;
: NO-CONST-OR-VARS??
    NO-CONST-OR-VARS  S" No Consts or Vars Allowed here !"       "PABORT ;

: \=  ( c -- f )  [CHAR] \ = ;
: '=  ( c -- f )  [CHAR] ' = ;

: GET$  ( xt -- c )
    	IS LIMTYP
    	A$ CLRBUF
    	BEGIN  A$=A$+CHAR  CHARREAD DUP LIMTYP  OVER 0= OR  UNTIL 
\	CR S" --[" "OUT A$ $OUT S" ]--" "OUT
	;

\ Skip \...\ comments without buffering in A$.  A long comment used to
\ overflow the 80-byte A$ and corrupt VAR$/translator state.  Source lines
\ are already echoed by PASQUERY; do not re-emit the body (multi-line
\ bodies would break the generated Forth).
: BSLSH  ( c -- )
    DROP
    BEGIN
        CHARREAD DUP [CHAR] \ <> OVER AND
    WHILE  DROP
    REPEAT
    DROP ;

: A$>#  ( -- n )  A$ NUMBER? 2DROP ;

: SKIPBLANKS  ( -- c )
    BL BEGIN DROP CHARREAD DUP BL - UNTIL ;

: STRING  ( c -- )
    DROP BL ['] '= GET$ DROP  0 A$=A$+CHAR  12 TO TYP ;

: NUMBR  ( c -- n )
    ['] NOT0-F GET$ DROP  4 TO TYP  -1 PASIN +!  A$># ;

: COLN  ( c -- )
    DROP  6 TO TYP
    CHARREAD [CHAR] = =
    IF  5 TO TYP  ELSE  -1 PASIN +!  THEN ;

: GTHAN  ( c -- )
    DROP  CHARREAD [CHAR] = =
    IF  10 TO TYP  ELSE  11 TO TYP  -1 PASIN +!  THEN ;

: LTHAN  ( c -- )
    DROP  CHARREAD DUP [CHAR] > =
    IF  DROP  9 TO TYP
    ELSE  [CHAR] = =
        IF  8 TO TYP  ELSE  7 TO TYP  -1 PASIN +!  THEN
    THEN ;

CREATE KW-TABLE
    ," and"     ," array"   ," begin"   ," newline"
    ," case"    ," const"   ," div"     ," do"
    ," downto"  ," else"    ," end"     ," for"
    ," func"    ," if"      ," integer" ," mem"
    ," mod"     ," not"     ," of"      ," or"
    ," proc"    ," read"    ," repeat"  ," shl"
    ," shr"     ," then"    ," to"      ," type"
    ," until"   ," var"     ," while"   ," write"
    ," in"
33 CONSTANT TABLE-SIZE

\ No locals: DO/LOOP uses the return stack; locals+LEAVE is fragile here.
: A$SRCH  ( -- f )
    FALSE
    TABLE-SIZE 0
    DO  A$
        KW-TABLE I 8 * +
        CAPS-COMP 0=
        IF  DROP TRUE  I TO CMD-INDEX  LEAVE  THEN
    LOOP ;

: A-IDENT  ( c -- f )
    DUP A-Z IF
        ['] NOTA-ZOR0-9 GET$ DROP    \ GET$ consumes lead char as first of A$
        -1 PASIN +!
        A$SRCH 0= 1 AND TO TYP
\	S" (identifier)" "OUT
        TRUE
    ELSE FALSE THEN ;

\ {  --- begin A-* token-label tracers ---
\ : A-#  ( c -- n ) DUP NOT0-F  0= IF  NUMBR  	     A$ $OUT S"  (number)" "OUT   TRUE EXIT THEN FALSE ;
\ : A-:  ( c -- )   DUP [CHAR] : = IF  COLN  	     A$ $OUT S"  :       " "OUT   TRUE EXIT THEN FALSE ;
\ : A-<  ( c -- )   DUP [CHAR] < = IF  LTHAN 	     A$ $OUT S"  <       " "OUT   TRUE EXIT THEN FALSE ;
\ : A->  ( c -- )   DUP [CHAR] > = IF  GTHAN 	     A$ $OUT S"  >       " "OUT   TRUE EXIT THEN FALSE ;
\ : A-$  ( c -- )   DUP [CHAR] ' = IF  STRING 	     A$ $OUT S"  ' (tick)" "OUT   TRUE EXIT THEN FALSE ;
\ : A-(  ( c -- )   DUP [CHAR] ( = IF  DROP 14 TO TYP  A$ $OUT S"  (       " "OUT   TRUE EXIT THEN FALSE ;
\ : A-)  ( c -- )   DUP [CHAR] ) = IF  DROP 15 TO TYP  A$ $OUT S"  )       " "OUT   TRUE EXIT THEN FALSE ;
\ : A-=  ( c -- )   DUP [CHAR] = = IF  DROP  2 TO TYP  A$ $OUT S"  =       " "OUT   TRUE EXIT THEN FALSE ;
\ }  --- end A-* token-label tracers ---
: A-#  ( c -- n true | c false ) DUP NOT0-F 0= IF NUMBR TRUE ELSE FALSE THEN ;
: A-:  ( c -- true | c false ) DUP [CHAR] : = IF COLN TRUE ELSE FALSE THEN ;
: A-<  ( c -- true | c false ) DUP [CHAR] < = IF LTHAN TRUE ELSE FALSE THEN ;
: A->  ( c -- true | c false ) DUP [CHAR] > = IF GTHAN TRUE ELSE FALSE THEN ;
: A-$  ( c -- true | c false ) DUP [CHAR] ' = IF STRING TRUE ELSE FALSE THEN ;
: A-(  ( c -- true | c false ) DUP [CHAR] ( = IF DROP 14 TO TYP TRUE ELSE FALSE THEN ;
: A-)  ( c -- true | c false ) DUP [CHAR] ) = IF DROP 15 TO TYP TRUE ELSE FALSE THEN ;
: A-=  ( c -- true | c false ) DUP [CHAR] = = IF DROP  2 TO TYP TRUE ELSE FALSE THEN ;


: TOKEN  ( -- )
    	BEGIN
        	BEGIN SKIPBLANKS ?DUP UNTIL
        	DUP [CHAR] \ =
    	WHILE  BSLSH
    	REPEAT \ S" TOKEN " "OUT
    	A-IDENT ?EXIT
	A-# 	?EXIT
	A-: 	?EXIT
	A-< 	?EXIT
	A-> 	?EXIT
	A-$ 	?EXIT
	A-( 	?EXIT
	A-) 	?EXIT
	A-= 	?EXIT
    	3 TO TYP  TO CHAR- ;

256 CONSTANT MAXCON   32 CONSTANT B/CON
768 CONSTANT MAXVAR   32 CONSTANT B/VAR

0 VALUE CON#
0 VALUE PCONS
0 VALUE VAR#
0 VALUE PVARS

: >C_NAME  ( n -- a )  B/CON * PCONS + CELL+ ;
: >V_NAME  ( n -- a )  B/VAR * PVARS + CELL+ ;

: PCONSTANT  ( n -- )
    CON# B/CON * PCONS +  SWAP OVER !
    PASWORD SWAP CELL+  OVER C@ 1 +  B/CON CELL - MIN  MOVE
    CON# 1+ TO CON# ;

: PVARIABLE  ( -- )
    VAR# B/VAR * PVARS +  DUP OFF
    PASWORD SWAP CELL+  OVER C@ 1 +  B/VAR CELL - MIN  MOVE
    VAR# 1+ TO VAR# ;

VARIABLE IN-ADDR
\ CAPS-COMP takes two counted-string addresses. No LEAVE (nested +LOOP unsafe).
\ Miss: leave original a with false so PDEFINED can try $INVAR.
: $INCON  ( a -- a2 f )
    0 IN-ADDR !
    PCONS  CON# B/CON *  BOUNDS
    ?DO  DUP I CELL+ CAPS-COMP 0=
         IF  I CELL+ IN-ADDR !  THEN
    B/CON +LOOP
    IN-ADDR @ IF DROP IN-ADDR @ TRUE ELSE FALSE THEN ;

: $INVAR  ( a -- a2 f )
    0 IN-ADDR !
    PVARS  VAR# B/VAR *  BOUNDS
    ?DO  DUP I CELL+ CAPS-COMP 0=
         IF  I CELL+ IN-ADDR !  THEN
    B/VAR +LOOP
    IN-ADDR @ IF DROP IN-ADDR @ TRUE ELSE FALSE THEN ;

\ Avoid ?EXIT here — keep (a f) and fall through cleanly.
: PDEFINED  ( -- a f )
    PASWORD $INCON DUP IF ELSE DROP $INVAR THEN ;

: A$CONSTANT  ( -- a )
    A$ COUNT INSET  -1 PCONSTANT  INREC
    CON# 1 - >C_NAME ;

: A$PLACE  ( -- a )
    A$ COUNT INSET PDEFINED INREC 0=
    IF  DROP A$CONSTANT  THEN ;

: A$VARIABLE  ( -- a )
    A$ COUNT INSET PDEFINED INREC 0=
    IF  DROP
        A$ COUNT INSET PVARIABLE INREC
        VAR# 1- >V_NAME
    THEN ;

: A$FIND??  ( -- a )
    A$ COUNT INSET PDEFINED INREC 0=
    IF  CR S" Unspecified Identifier ->" TYPE COUNT TYPE
        A$CONSTANT CROUT+
    THEN ;

DEFER STATMENT
DEFER BLOCK-
DEFER EXPR-

: CREATE-CONSTANT
    BEGIN
        A$CONSTANT >R
        TOKEN ==??
        TOKEN #??
        CROUT ##OUT S" CONSTANT" "OUT R> $OUT
        TOKEN ;??
        TOKEN IDENT? 0=
    UNTIL ;

: CONST-  NO-CONST-OR-VARS??  TOKEN IDENT??  CREATE-CONSTANT ;

: MAKEVARS  ( -- f )
    INTEGER??
    VAR$ COUNT INSET  VARCNT >R
    BEGIN
        PVARIABLE CROUT S" VARIABLE" "OUT
        VAR# 1- >V_NAME $OUT
        VARCNT 1 - TO VARCNT
        VARCNT 1 <
    UNTIL
    R> TO VARCNT
    INREC TOKEN ;? DUP
    IF  DROP TOKEN IDENT?  THEN  0= ;

: MAKEARRAYS  ( -- f )
    TOKEN [??  TOKEN
    #A??  CELLS TO ARRAYSIZE
    TOKEN ]??  TOKEN OF??
    TOKEN INTEGER??  TOKEN ;??
    VAR$ COUNT INSET
    BEGIN
        PVARIABLE CROUT
        S" CREATE" "OUT  VAR# 1- >V_NAME $OUT
        ARRAYSIZE ##OUT S" ALLOT" "OUT
        VARCNT 1- TO VARCNT
        VARCNT 1 <
    UNTIL
    INREC TOKEN IDENT? 0= ;

: VAR-
    NO-CONST-OR-VARS?? TOKEN
    BEGIN
        0 TO VARCNT  0 VAR$ C!
        BEGIN  IDENT?? VAR$MOVE TOKEN ,?
        WHILE  TOKEN
        REPEAT  :??
        TOKEN ARRAY?
        IF  MAKEARRAYS  ELSE  MAKEVARS  THEN
    UNTIL ;

: PAR-PASS  ( a -- )
    >R VAR- CROUT S" :" "OUT R> $OUT 16 SP>COL
    VAR$ COUNT INSET  VARCNT TO PARCNT
    BEGIN  PDEFINED FOUND??
        VARCNT 1- TO VARCNT
        VARCNT 1 <
    UNTIL  INREC  PARCNT TO VARCNT
    BEGIN  $OUT S" !" "OUT
        VARCNT 1 - TO VARCNT  VARCNT 1 <
    UNTIL  )?? TOKEN ;

: PROC-
    TOKEN IDENT??  TRUE TO PTYP  A$PLACE
    TOKEN (?
    IF  FALSE TO PTYP  PAR-PASS  TRUE TO NO-CONST-OR-VARS  THEN
    ;?? TOKEN BLOCK- S" ;" "OUT
    TRUE TO PTYP  ;?? TOKEN BLOCK- ;

: BEGIN-
    BEGIN  TOKEN STATMENT  ;? 0=  UNTIL  END?? TOKEN ;

: PAR-TO-STK
    BEGIN  TOKEN EXPR-  ,? 0=  UNTIL  )?? TOKEN ;

: VARIABLE?  ( a -- f )
    PVARS DUP B/VAR MAXVAR * + UBETWEEN ;

: VARIABLE??  ( a -- )
    DUP VARIABLE? 0=
    IF  CROUT S" Assignment to NON-Variable->" "OUT
        COUNT "OUT CROUT
    ELSE  DROP
    THEN ;

: VARCONOUT  ( a -- )
    DUP $OUT VARIABLE? IF S" @" "OUT THEN ;

: CONSTANT-
    IDENT?
    IF  A$FIND?? TOKEN [?
        IF  $OUT TOKEN EXPR-  S" CELLS + @" "OUT  ]?? TOKEN
        ELSE  (? IF  PAR-TO-STK $OUT  ELSE  VARCONOUT  THEN
        THEN
    ELSE  #?
        IF  ##OUT TOKEN
        ELSE  S" CHAR" "OUT A$PLACE $OUT TOKEN
        THEN
    THEN ;

: +-OR?  ( -- a n f | f )
    -?  IF S" -"  TRUE ELSE
    +?  IF S" +"  TRUE ELSE
    OR? IF S" OR" TRUE ELSE FALSE
    THEN THEN THEN ;

: TERM-OPER?  ( -- a n f | f )
    DIV? IF S" /"   TRUE ELSE
    MOD? IF S" MOD" TRUE ELSE
    AND? IF S" AND" TRUE ELSE
    SHL? IF S" LSHIFT" TRUE ELSE
    SHR? IF S" RSHIFT" TRUE ELSE
      *? IF S" *"   TRUE ELSE FALSE
    THEN THEN THEN THEN THEN THEN ;

: FACTOR-
    NOT? IF  TOKEN RECURSE ( FACTOR- ) S" 0=" "OUT  THEN
    KEYWORD?
    IF  MEM?? TOKEN [?? TOKEN EXPR- ]??  S" @" "OUT TOKEN
    ELSE  (?
        IF  TOKEN EXPR- )?? TOKEN
        ELSE  CONSTANT-
        THEN
    THEN ;

: TERM-
    FACTOR- TERM-OPER?
    IF  BEGIN  TOKEN FACTOR-  "OUT  TERM-OPER? 0=  UNTIL  THEN ;

: SIMP-EXPR
    -?
    IF  TOKEN TERM-  S" NEGATE" "OUT
    ELSE  +? IF TOKEN THEN  TERM-
    THEN
    +-OR? IF  BEGIN  TOKEN RECURSE ( SIMP-EXPR ) "OUT  +-OR? 0=  UNTIL  THEN ;

: IN-
    [?? S" DUP" "OUT TOKEN SIMP-EXPR S" =" "OUT ,?
    IF  BEGIN  TOKEN CROUT++ S" OVER" "OUT
              SIMP-EXPR S" = OR" "OUT  ,? 0=
        UNTIL
    THEN  ]?? S" NIP" "OUT TOKEN ;

: (EXPR-)
    SIMP-EXPR
    ==? IF TOKEN SIMP-EXPR S" ="  "OUT THEN
     <? IF TOKEN SIMP-EXPR S" <"  "OUT THEN
     >? IF TOKEN SIMP-EXPR S" >"  "OUT THEN
    <>? IF TOKEN SIMP-EXPR S" <>" "OUT THEN
    <=? IF TOKEN SIMP-EXPR S" <=" "OUT THEN
    >=? IF TOKEN SIMP-EXPR S" >=" "OUT THEN
    IN? IF TOKEN IN- THEN ;
' (EXPR-) IS EXPR-

: VAR-ASSIGN
    IDENT?? A$FIND?? TOKEN (?
    IF  PAR-TO-STK  THEN
    DUP >R VARIABLE?
    IF  [?
        IF  TOKEN EXPR-  S" CELLS " "OUT  ]?? TOKEN
            :=?? TOKEN EXPR-  R> $OUT  S" ROT + !" "OUT
        ELSE  :=?? TOKEN EXPR-  R> $OUT  S" !" "OUT
        THEN
    ELSE  R> $OUT
    THEN ;

: IF-
    TOKEN EXPR- THEN??
    CROUT+ S" IF     " "OUT TOKEN STATMENT ELSE?
    IF  CROUT+ S" ELSE   " "OUT TOKEN STATMENT  THEN
    CROUT+ S" THEN   " "OUT ;

: CASES-
    S" DUP" "OUT TOKEN CONSTANT- S" =" "OUT ,?
    IF  BEGIN  TOKEN CROUT++ S" OVER" "OUT
              CONSTANT- S" = OR" "OUT  ,? 0=
        UNTIL
    THEN  :??
    CROUT+ S" IF     " "OUT TOKEN STATMENT
    CROUT+ S" ELSE   " "OUT ;

: CASE-
    TOKEN EXPR- OF??
    CROUT+ S" CASE    " "OUT
    BEGIN  CASES-  ;? 0=  UNTIL
    S" DROP" "OUT ELSE?
    IF  TOKEN STATMENT  THEN
    END??
    CROUT+ S" ENDCASE" "OUT TOKEN ;

: WHILE-
    CROUT+ S" BEGIN  " "OUT TOKEN EXPR- DO???
    IF  CROUT+ S" WHILE  " "OUT TOKEN STATMENT
        CROUT+ S" REPEAT " "OUT
    THEN ;

: REPEAT-
    CROUT+ S" BEGIN  " "OUT
    BEGIN  TOKEN STATMENT ;? 0=  UNTIL
    UNTIL?? TOKEN EXPR-
    CROUT+ S" UNTIL  " "OUT ;

: FOR-
    TOKEN IDENT?? A$FIND?? >R TOKEN :=??
    TOKEN EXPR- TO-OR-DOWNTO?? R> TO?
    IF  1 >R  ELSE  -1 >R  THEN  >R
    TOKEN EXPR- DO??  R> R@ ##OUT >R
    S" + SWAP" "OUT CROUT+ S" DO     " "OUT
    TOKEN S" I" "OUT R> $OUT S" !" "OUT STATMENT
    R> ##OUT CROUT+ S" +LOOP  " "OUT ;

: A$COMPILE
    [CHAR] . COUT  [CHAR] " CHROUT
    A$ COUNT 1 /STRING "OUT  [CHAR] " CHROUT ;

: WRITE-
    TOKEN (??
    BEGIN  CROUT++
        TOKEN STRING?
        IF  A$COMPILE TOKEN
        ELSE  ##?
            IF  TOKEN EXPR- S" ." "OUT
            ELSE  EXPR- S" EMIT" "OUT
            THEN
        THEN  ,? 0=
    UNTIL  )?? TOKEN ;

: READ-
    TOKEN (??
    BEGIN  CROUT++
        TOKEN ##?
        IF  S" KEY" "OUT TOKEN
        ELSE  S" KEY DUP EMIT" "OUT
        THEN
        IDENT?? A$FIND??
        DUP VARIABLE?? $OUT
        TOKEN [?
        IF  TOKEN EXPR- ]?? S" CELLS + " "OUT TOKEN  THEN
        S" !" "OUT
        ,? 0=
    UNTIL  )?? TOKEN ;

: MEM-
    TOKEN [?? TOKEN EXPR- ]??
    TOKEN :=?? TOKEN EXPR- S" SWAP !" "OUT ;

: NEWLIN-  CROUT++ S" CR" "OUT TOKEN ;

: DO-STATMENT
    CMD-INDEX DUP TABLE-SIZE <
	IF	EXEC:
    		NOOP NOOP BEGIN- NEWLIN- CASE- NOOP NOOP NOOP
    		NOOP NOOP NOOP FOR-  NOOP IF-   NOOP MEM-
    		NOOP NOOP NOOP NOOP  NOOP READ- REPEAT- NOOP
   		NOOP NOOP NOOP NOOP  NOOP NOOP  WHILE- WRITE- 
	THEN ;

: (STATMENT)
    CROUT++
    KEYWORD? IF DO-STATMENT ELSE VAR-ASSIGN THEN ;
' (STATMENT) IS STATMENT ;

: BEGIN-1
    PTYP IF  CROUT S" :" "OUT $OUT 16 SP>COL  THEN
    BEGIN- ;

0 VALUE ?STP
: STP  TRUE TO ?STP ;

: DO-BLOCK
    CMD-INDEX 31 AND EXEC:
    STP STP BEGIN-1 STP STP CONST- STP STP
    STP STP STP STP PROC- STP STP STP
    STP STP STP STP PROC- STP STP STP
    STP STP STP STP STP VAR- STP STP ;

: (BLOCK-)
    KEYWORD?
    IF  FALSE TO ?STP
        BEGIN DO-BLOCK ?STP UNTIL
    THEN ;
' (BLOCK-) IS BLOCK- ;

: PAS_INIT  PASLEN OFF  PASIN OFF  0 TO CON#  0 TO VAR# ;

: PROGRAM
    PAS_INIT
    FALSE TO NO-CONST-OR-VARS
    TOKEN  TOKEN IDENT?? A$PLACE
    TOKEN (?  TRUE TO PTYP
    IF  PAR-PASS TRUE TO NO-CONST-OR-VARS  FALSE TO PTYP  THEN
    ;?? TOKEN BLOCK-
    CROUT+ S" ; " "OUT .??
    CROUT CROUT ;

: INIT_ARRAYS
    PCONS 0= IF
        MAXCON B/CON * DUP ALLOCATE THROW TO PCONS  PCONS SWAP ERASE
        MAXVAR B/VAR * DUP ALLOCATE THROW TO PVARS  PVARS SWAP ERASE
        VAR$ OFF  A$ OFF
    THEN ;

CREATE PAS-NAMEBUF 256 ALLOT
CREATE PAS-OUTBUF  256 ALLOT

: PAS-ABS?  ( c-addr u -- flag )
    DUP 0= IF  2DROP FALSE EXIT  THEN
    OVER C@ [CHAR] / = IF  2DROP TRUE EXIT  THEN
    OVER C@ [CHAR] ~ = IF  2DROP TRUE EXIT  THEN
    2DROP FALSE ;

: PAS-S+  ( c-addr u dest -- )
    >R  R@ COUNT +  SWAP DUP >R MOVE
    R> R@ C@ + R> C! ;

\ If FROMLIB is armed, rewrite a relative path under LIBRARY-PATH and clear
\ the arm (folder translation for Library-relative names). Absolute or ~
\ paths are unchanged. Without FROMLIB, the path stays cwd-relative.
\ Done here — not in PAS-OPEN — so PASCAL / PASCAL" / PASCAL-TO-FILE share
\ one commented resolve step.
: PAS-RESOLVE  ( c-addr u -- c-addr' u' )
    2DUP PAS-ABS? IF EXIT THEN
    FROMLIB? 0= IF EXIT THEN
    >R >R
    LIBRARY-PATH DUP 0= IF
        2DROP R> R> 2DROP FROMLIB-OFF
        TRUE ABORT" PASCAL: FROMLIB armed but LIBRARY-PATH empty"
    THEN
    0 PAS-NAMEBUF C!
    PAS-NAMEBUF PLACE
    S" /" PAS-NAMEBUF PAS-S+
    R> R> PAS-NAMEBUF PAS-S+
    FROMLIB-OFF
    PAS-NAMEBUF COUNT ;

\ Require a .pas (any case) suffix so a .fth is never mistaken for source.
: PAS-MUST-.PAS  ( c-addr u -- c-addr u )
    DUP 4 < IF
        TRUE ABORT" Pascal source must have a .pas extension"
    THEN
    2DUP + 4 -
    DUP C@ [CHAR] . <> IF
        DROP TRUE ABORT" Pascal source must have a .pas extension"
    THEN
    1+ DUP C@ BL OR [CHAR] P BL OR <> IF
        DROP TRUE ABORT" Pascal source must have a .pas extension"
    THEN
    1+ DUP C@ BL OR [CHAR] A BL OR <> IF
        DROP TRUE ABORT" Pascal source must have a .pas extension"
    THEN
    1+ C@ BL OR [CHAR] S BL OR <> IF
        TRUE ABORT" Pascal source must have a .pas extension"
    THEN ;

: PAS-OUT-NAME  ( c-addr u -- c-addr2 u2 )
    DUP 4 < IF
        TRUE ABORT" PASCAL-TO-FILE: path too short"
    THEN
    PAS-OUTBUF PLACE
    PAS-OUTBUF COUNT + 4 -
    [CHAR] . OVER C!
    [CHAR] f OVER 1+ C!
    [CHAR] t OVER 2 + C!
    [CHAR] h SWAP 3 + C!
    PAS-OUTBUF COUNT ;

: (PASCAL-TRANS)  ( c-addr u -- )
    INIT_ARRAYS
    PAS-OPEN
    CROUT PROGRAM
    PAS-CLOSE ;

: PASCAL"  ( c-addr u -- )
    DECIMAL
    PAS-RESOLVE PAS-MUST-.PAS
    (PASCAL-TRANS) ;

: PASCAL  ( "name" -- )
    DECIMAL
    BL WORD COUNT
    PAS-RESOLVE PAS-MUST-.PAS
    (PASCAL-TRANS) ;

\ Translate .pas → sibling .fth (same folder, same stem). Honors FROMLIB
\ via PAS-RESOLVE before opening either file.
: PASCAL-TO-FILE  ( c-addr u -- )
    DECIMAL
    PAS-RESOLVE PAS-MUST-.PAS
    2DUP PAS-OUT-NAME
    2DUP W/O CREATE-FILE ABORT" PASCAL-TO-FILE: can't create .fth"
    TO PAS-OUT-FID
    >R >R
    ['] (PASCAL-TRANS) CATCH
    PAS-OUT-FID IF
        PAS-OUT-FID CLOSE-FILE DROP
        0 TO PAS-OUT-FID
    THEN
    ?DUP IF  R> R> 2DROP THROW  THEN
    CR  ." Wrote "  R> R> TYPE  CR ;

: PASFILE ( 'name' -- )
    DECIMAL
    BL WORD COUNT
    PASCAL-TO-FILE ;

.( Loaded PASCAL.fth ) CR

\ Example:
\   FROMLIB S" Pascal/PASY.PAS" PASCAL"
\   FROMLIB S" Pascal/PASY.PAS" PASCAL-TO-FILE
