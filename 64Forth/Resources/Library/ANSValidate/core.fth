\ core.fth — ANS Core spot-checks ported from TZForth ANS-VALIDATE / FTEST TEST6
\
\ Requires: tester.fth already loaded - EXPECT / #PASS / #FAIL
\ Loaded by ANS-VALIDATE.fth via relative FLOAD - siblings under ANSValidate/
\
\ Port status: first Core batch - arithmetic, logic, compare, stack, return
\ stack, memory, constants, pictured numeric, basic control, EXECUTE.
\ (Core Ext is core-ext.fth; Search-Order / String / … still later.)
\
\ NOT a formal ANS certificate. Prefer Hayes for stock suite coverage.

DECIMAL
ONLY FORTH DEFINITIONS

CR .( === Core ===) CR

\ Kernel TUCK was ( x1 x1 x2 ); fixed in forth.s — redefine until rebuild.
: TUCK  SWAP OVER ;

CREATE T6MEM 256 ALLOT

\ --- Arithmetic ---
3 4 + 7 = S" +" EXPECT
10 3 - 7 = S" -" EXPECT
6 7 * 42 = S" *" EXPECT
10 3 /MOD 3 = SWAP 1 = AND S" /MOD" EXPECT
10 3 / 3 = S" /" EXPECT
10 3 4 */MOD 7 = SWAP 2 = AND S" */MOD" EXPECT
7 2 3 */ 4 = S" */" EXPECT
-7 2 3 */ -4 = S" */neg" EXPECT
21 2* 42 = S" 2*" EXPECT
42 2/ 21 = S" 2/" EXPECT
1000 1000 M* 0 = SWAP 1000000 = AND S" M*" EXPECT
10 0 3 FM/MOD 3 = SWAP 1 = AND S" FM/MOD" EXPECT
10 0 3 SM/REM 3 = SWAP 1 = AND S" SM/REM" EXPECT
1 2 U< S" U<" EXPECT
2 1 U> S" U>" EXPECT
1 2 U> 0= S" U>f" EXPECT
100 100 UM* 0 = SWAP 10000 = AND S" UM*" EXPECT
100 0 10 UM/MOD 10 = SWAP 0 = AND S" UM/MOD" EXPECT
10 3 MOD 1 = S" MOD" EXPECT
41 1+ 42 = S" 1+" EXPECT
43 1- 42 = S" 1-" EXPECT
-5 ABS 5 = S" ABS" EXPECT
5 NEGATE -5 = S" NEGATE" EXPECT
3 7 MIN 3 = S" MIN" EXPECT
3 7 MAX 7 = S" MAX" EXPECT

\ --- Logic and shifts ---
5 3 AND 1 = S" AND" EXPECT
5 3 OR 7 = S" OR" EXPECT
5 3 XOR 6 = S" XOR" EXPECT
0 INVERT -1 = S" INVERT" EXPECT
1 3 LSHIFT 8 = S" LSHIFT" EXPECT
8 2 RSHIFT 2 = S" RSHIFT" EXPECT

\ --- Comparisons ---
5 5 = S" =" EXPECT
5 6 = 0= S" =f" EXPECT
3 5 < S" <" EXPECT
5 3 > S" >" EXPECT
5 5 <> 0= S" <>f" EXPECT
5 6 <> S" <>" EXPECT
0 0= S" 0=" EXPECT
1 0= 0= S" 0=f" EXPECT
-1 0< S" 0<" EXPECT
1 0> S" 0>" EXPECT
5 1 10 WITHIN S" WITHIN" EXPECT
0 1 10 WITHIN 0= S" WITHINf" EXPECT

\ --- Stack ---
42 DUP 42 = SWAP 42 = AND S" DUP" EXPECT
1 2 DROP 1 = S" DROP" EXPECT
1 2 SWAP 1 = SWAP 2 = AND S" SWAP" EXPECT
1 2 OVER 1 = SWAP 2 = AND SWAP 1 = AND S" OVER" EXPECT
0 ?DUP 0 = S" ?DUPz" EXPECT
5 ?DUP 5 = SWAP 5 = AND S" ?DUP" EXPECT
1 2 3 ROT 1 = SWAP 3 = AND SWAP 2 = AND S" ROT" EXPECT
1 2 NIP 2 = S" NIP" EXPECT
\ TUCK ( a b -- b a b )
1 2 TUCK 2 = SWAP 1 = AND SWAP 2 = AND S" TUCK" EXPECT
10 20 30 1 PICK 20 = S" PICK" EXPECT
\ leave clean stack after PICK test
DROP DROP DROP
\ 1 ROLL swaps top two of three: ( 10 20 30 -- 10 30 20 )
10 20 30 1 ROLL 20 = SWAP 30 = AND SWAP 10 = AND S" ROLL" EXPECT

\ --- Return stack and 2-stack ---
42 >R R> 42 = S" >R R>" EXPECT
99 >R R@ R> DROP 99 = S" R@" EXPECT
1 2 2>R 2R> 2 = SWAP 1 = AND S" 2>R 2R>" EXPECT
1 2 3 4 2DROP 2 = SWAP 1 = AND S" 2DROP" EXPECT
1 2 2DUP 2 = SWAP 1 = AND SWAP 2 = AND SWAP 1 = AND S" 2DUP" EXPECT
1 2 3 4 2OVER 2 = SWAP 1 = AND SWAP 4 = AND SWAP 3 = AND S" 2OVER" EXPECT
DROP DROP
1 2 3 4 2SWAP 2 = SWAP 1 = AND SWAP 4 = AND SWAP 3 = AND S" 2SWAP" EXPECT

\ --- Memory ---
123 T6MEM ! T6MEM @ 123 = S" ! @" EXPECT
65 T6MEM C! T6MEM C@ 65 = S" C! C@" EXPECT
0 T6MEM ! 5 T6MEM +! T6MEM @ 5 = S" +!" EXPECT
T6MEM 3 65 FILL T6MEM C@ 65 = S" FILL" EXPECT
T6MEM 8 + 3 66 FILL
T6MEM 16 + 3 0 FILL
T6MEM 8 + T6MEM 16 + 3 MOVE
T6MEM 16 + C@ 66 = S" MOVE" EXPECT

\ --- Constants / base ---
TRUE -1 = S" TRUE" EXPECT
FALSE 0 = S" FALSE" EXPECT
BL 32 = S" BL" EXPECT
HEX 10 DECIMAL 16 = S" HEX" EXPECT
DECIMAL
10 BASE ! 42 42 = S" BASE" EXPECT
DECIMAL

\ --- DEPTH ---
1 2 3 DEPTH 3 = S" DEPTH" EXPECT
DROP DROP DROP

\ --- S" and pictured numeric ---
S" HELLO" NIP 5 = S" Squote-len" EXPECT
123 S>D <# #S #> NIP 3 = S" #S" EXPECT

\ --- Control via colon helpers only ---
: T6IF  5 0= IF 99 ELSE 88 THEN ;
T6IF 88 = S" IF ELSE THEN" EXPECT

: T6UNTIL  0 BEGIN 1+ DUP 3 > UNTIL ;
T6UNTIL 4 = S" BEGIN UNTIL" EXPECT

: T6DO  0 3 0 DO I + LOOP ;
T6DO 3 = S" DO LOOP I" EXPECT

: T6QDO  0 5 0 ?DO 1+ LOOP ;
T6QDO 5 = S" ?DO LOOP" EXPECT

: T6J  0 2 0 DO 0 2 0 DO J + LOOP LOOP ;
T6J 2 = S" J" EXPECT

: T6REC  1- DUP 0= IF DROP 99 ELSE RECURSE THEN ;
5 T6REC 99 = S" RECURSE" EXPECT

3 4 ' + EXECUTE 7 = S" EXECUTE" EXPECT

\ --- EVALUATE / ENVIRONMENT? ---
S" 3 4 +" EVALUATE 7 = S" EVALUATE" EXPECT
S" CORE" ENVIRONMENT? NIP S" ENV-CORE" EXPECT
S" CORE-EXT" ENVIRONMENT? NIP S" ENV-CORE-EXT" EXPECT
S" FLOORED" ENVIRONMENT? DROP 0= S" ENV-FLOORED" EXPECT

CR .( --- Core batch done ---) CR
