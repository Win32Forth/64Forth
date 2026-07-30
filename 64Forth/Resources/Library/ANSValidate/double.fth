\ double.fth — ANS Double-Number spot-checks from TZForth ANS-VALIDATE / FTEST
\
\ Requires: tester.fth already loaded
\ Doubles: lo under, hi TOS. Trailing-dot literals: 123. → lo=123 hi=0 (or sign).
\
\ NOT a formal ANS certificate. Prefer Hayes doubletest.fth.

DECIMAL
ONLY FORTH DEFINITIONS

CR .( === Double ===) CR

\ --- D+ ---
1 0 2 0 D+
0 = SWAP 3 = AND S" D+" EXPECT

\ --- D- ---
5 0 2 0 D-
0 = SWAP 3 = AND S" D-" EXPECT

\ --- D2* / D2/ ---
3 0 D2*
0 = SWAP 6 = AND S" D2*" EXPECT
6 0 D2/
0 = SWAP 3 = AND S" D2/" EXPECT

\ --- DNEGATE / DABS ---
7 0 DNEGATE
-1 = SWAP -7 = AND S" DNEGATE" EXPECT
-9 -1 DABS
0 = SWAP 9 = AND S" DABS" EXPECT

\ --- D= / D< / DU< ---
100 0 100 0 D= S" D=" EXPECT
100 0 101 0 D= 0= S" D=f" EXPECT
1 0 2 0 D< S" D<" EXPECT
2 0 1 0 D< 0= S" D<f" EXPECT
1 0 2 0 DU< S" DU<" EXPECT

\ --- DMAX / DMIN ---
3 0 5 0 DMAX
0 = SWAP 5 = AND S" DMAX" EXPECT
3 0 5 0 DMIN
0 = SWAP 3 = AND S" DMIN" EXPECT

\ --- D>S ---
1234 0 D>S 1234 = S" D>S" EXPECT

\ --- M+ ---
1 0 5 M+
0 = SWAP 6 = AND S" M+" EXPECT

\ --- S>D ---
-5 S>D
-1 = SWAP -5 = AND S" S>D" EXPECT

\ --- trailing-dot double literal ---
123.
0 = SWAP 123 = AND S" lit." EXPECT

\ --- 2CONSTANT ---
100 0 2CONSTANT DB-C
DB-C 0 = SWAP 100 = AND S" 2CONSTANT" EXPECT

\ --- 2VARIABLE ---
2VARIABLE DB-V
200 0 DB-V 2!
DB-V 2@ 0 = SWAP 200 = AND S" 2VARIABLE" EXPECT

\ --- 2VALUE / TO via body store if needed ---
50 0 2VALUE DB-DV
DB-DV 0 = SWAP 50 = AND S" 2VALUE" EXPECT
\ interpret TO for 2VALUE: two cells
200 0 TO DB-DV
DB-DV 0 = SWAP 200 = AND S" 2VALUE-TO" EXPECT

\ --- 2ROT ---
1 0 2 0 3 0 2ROT
\ expect top double is 1 0 after 2ROT of three doubles? 
\ 2ROT ( d1 d2 d3 -- d2 d3 d1 )
\ stack after: d2 d3 d1 with d1 TOS pair
0 = SWAP 1 = AND S" 2ROT-top" EXPECT
2DROP 2DROP

\ --- ENVIRONMENT? DOUBLE ---
S" DOUBLE" ENVIRONMENT? NIP S" ENV-DOUBLE" EXPECT

\ --- D0= / D0< if present ---
0 0 D0= S" D0=" EXPECT
-1 -1 D0< S" D0<" EXPECT

.( --- Double batch done ---) .STACK-DEPTH CR
