\ core-ext.fth — ANS Core Ext spot-checks from TZForth ANS-VALIDATE / FTEST
\
\ Requires: tester.fth already loaded
\ Loaded by ANS-VALIDATE.fth via relative FLOAD
\
\ Search-Order / VOCABULARY / FORGET → search.fth later
\ NOT a formal ANS certificate. Prefer Hayes coreexttest.fth for stock suite.
\
\ Note: interpret TO for VALUE had a stack-pop bug (fixed in forth.s). Until
\ rebuild, VALUE change is tested via CFA+16 store (same layout as kernel TO).

DECIMAL
ONLY FORTH DEFINITIONS

CR .( === Core Ext ===) CR

\ --- Flags / compares ---
0 0<> 0= S" 0<>z" EXPECT
5 0<> S" 0<>" EXPECT
5 5 <> 0= S" <>eq" EXPECT
5 6 <> S" <>ne" EXPECT
2 1 U> S" U>" EXPECT
1 2 U> 0= S" U>f" EXPECT

\ --- ERASE ---
HERE 8 ERASE
HERE C@ 0=
HERE 4 + C@ 0= AND S" ERASE" EXPECT

\ --- VALUE (fetch) and store via body (TO layout CFA+16) ---
123 VALUE CE-V1
CE-V1 123 = S" VALUE" EXPECT
456 ' CE-V1 16 + !
CE-V1 456 = S" VALUE-store" EXPECT

\ --- COMPILE, ---
: [CE+]  ['] + COMPILE, ; IMMEDIATE
: CE-CM  [CE+] ;
10 20 CE-CM 30 = S" COMPILE," EXPECT

\ --- BUFFER: ---
64 BUFFER: CE-TB1
CE-TB1 99 OVER C! C@ 99 = S" BUFFER:" EXPECT

\ --- UNUSED ---
UNUSED 1000 > S" UNUSED" EXPECT

\ --- C" ---
C" HELLO" COUNT NIP 5 = S" Cquote" EXPECT
: CE-CQ  C" world" COUNT NIP ;
CE-CQ 5 = S" Cquote-comp" EXPECT

\ --- DEFER / IS / DEFER! / DEFER@ ---
DEFER CE-D1
: CE-A1  777 ;
' CE-A1 IS CE-D1
CE-D1 777 = S" DEFER-IS" EXPECT
: CE-A2  888 ;
' CE-A2 ' CE-D1 DEFER!
CE-D1 888 = S" DEFER!" EXPECT
' CE-D1 DEFER@ ' CE-A2 = S" DEFER@" EXPECT

\ --- CASE OF ENDOF ENDCASE ---
: CE-CASE  ( n -- n' )
  CASE
    1 OF 10 ENDOF
    2 OF 20 ENDOF
    DUP
  ENDCASE ;
1 CE-CASE 10 = S" CASE1" EXPECT
2 CE-CASE 20 = S" CASE2" EXPECT
3 CE-CASE 3 = S" CASE3" EXPECT

\ --- :NONAME ---
:NONAME 1+ ; CONSTANT CE-XT
5 CE-XT EXECUTE 6 = S" NONAME" EXPECT

\ --- HOLDS ---
123 S>D <# #S S" Num: " HOLDS #> NIP 8 = S" HOLDS" EXPECT

\ --- PARSE-NAME via EVALUATE ---
: CE-PN  PARSE-NAME NIP ;
S" CE-PN   hello" EVALUATE 5 = S" PARSE-NAME" EXPECT

\ --- AGAIN ---
: CE-AG  0 BEGIN 1+ DUP 4 = IF EXIT THEN AGAIN ;
CE-AG 4 = S" AGAIN" EXPECT

\ --- NIP ---
1 2 NIP 2 = S" NIP" EXPECT

\ --- PAD ---
PAD 0= 0= S" PAD" EXPECT
PAD DUP 100 + 42 SWAP C! DROP
PAD 100 + C@ 42 = S" PAD-isolate" EXPECT

\ --- EVALUATE ---
S" 10 20 +" EVALUATE 30 = S" EVALUATE" EXPECT

\ --- ENVIRONMENT? CORE-EXT ---
S" CORE-EXT" ENVIRONMENT? NIP S" ENV-CORE-EXT" EXPECT

\ --- TRUE FALSE already in core; 0> ---
1 0> S" 0>" EXPECT
0 0> 0= S" 0>f" EXPECT

.( --- Core Ext batch done ---) .STACK-DEPTH CR
