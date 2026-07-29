\ tools.fth — ANS Programming-Tools spot-checks from TZForth ANS-VALIDATE / FTEST
\
\ Requires: tester.fth already loaded
\ Conservative subset — MARKER/SYNONYM/SEE can interact badly with later loads.
\
\ NOT a formal ANS certificate. Prefer Hayes toolstest.fth.

DECIMAL
ONLY FORTH DEFINITIONS

CR .( === Programming-Tools ===) CR

VARIABLE TL-V
VARIABLE TL-TR

\ --- @ ---
42 TL-V !
TL-V @ 42 = S" fetch" EXPECT

\ --- NAME>STRING ---
' DUP NAME>STRING NIP 3 = S" NAME>STRING-u" EXPECT
' DUP NAME>STRING DROP C@ CHAR D = S" NAME>STRING-c" EXPECT

\ --- NAME>INTERPRET ---
' DUP NAME>INTERPRET ' DUP = S" NAME>INTERPRET" EXPECT

\ --- AHEAD ---
: TL-AH  AHEAD 111 THEN 222 ;
TL-AH 222 = S" AHEAD" EXPECT

\ --- N>R NR> ---
: TL-NR  10 20 2 N>R NR> ;
TL-NR 2 = SWAP 20 = AND SWAP 10 = AND S" N>R" EXPECT

\ --- [DEFINED] / [UNDEFINED] ---
: TL-DEF  [DEFINED] DUP DUP [THEN] ;
5 TL-DEF 5 = SWAP 5 = AND S" DEFINED" EXPECT

: TL-UNDEF  [UNDEFINED] NOPE99ZZ 88 [THEN] ;
TL-UNDEF 88 = S" UNDEFINED" EXPECT

\ --- TRAVERSE-WORDLIST ---
: TL-TW  DROP 1 TL-TR ! TRUE ;
0 TL-TR !
' TL-TW GET-CURRENT TRAVERSE-WORDLIST
TL-TR @ 1 = S" TRAVERSE" EXPECT

\ --- words exist ---
' AHEAD 0= 0= S" AHEAD-xt" EXPECT
' N>R 0= 0= S" N>R-xt" EXPECT
' NR> 0= 0= S" NR>-xt" EXPECT
' BYE 0= 0= S" BYE-xt" EXPECT
' CS-PICK 0= 0= S" CS-PICK" EXPECT
' CS-ROLL 0= 0= S" CS-ROLL" EXPECT
' TRAVERSE-WORDLIST 0= 0= S" TRAVERSE-xt" EXPECT

\ --- ENVIRONMENT? TOOLS-EXT optional ---
: (TL-ENV)
  S" TOOLS-EXT" ENVIRONMENT?
  DUP 0= IF DROP TRUE ELSE DROP TRUE THEN ;
(TL-ENV) S" ENV-TOOLS" EXPECT

ONLY FORTH

CR .( --- Programming-Tools batch done ---) CR
