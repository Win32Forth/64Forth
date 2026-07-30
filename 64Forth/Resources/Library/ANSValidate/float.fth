\ float.fth -- ANS Float Tier A/B spot-checks (FP vocabulary)
\
\ Requires: tester.fth already loaded
\ Float words live in the FP wordlist: ALSO FP before use.
\ Prefer Hayes fp/ suite for deep coverage (paranoia, ttester).
\
\ CRITICAL: no interpret-time IF/ELSE/THEN/BEGIN.
\ NOT a formal ANS certificate.

DECIMAL
ONLY FORTH DEFINITIONS
ALSO FP

CR .( === Float ===) CR

\ Clear F-stack (colon only)
: (FCLEAR)  BEGIN FDEPTH WHILE FDROP REPEAT ;

\ Flag helpers (IF only inside colon)
: ENV1  ENVIRONMENT? IF DROP TRUE ELSE FALSE THEN ;
: ENV-FSTK
  S" FLOATING-STACK" ENVIRONMENT?
  IF 16 = ELSE FALSE THEN ;

\ --- ENVIRONMENT? ---
S" FLOATING" ENV1 S" ENV-FLOATING" EXPECT
S" FLOAT-EXT" ENV1 S" ENV-FLOAT-EXT" EXPECT
ENV-FSTK S" ENV-FSTK" EXPECT

\ --- stack depth / empty ---
(FCLEAR)
FDEPTH 0 = S" FDEPTH0" EXPECT

\ --- S>F F>S round-trip ---
42 S>F F>S 42 = S" S>F>S" EXPECT

\ --- arithmetic ---
3 S>F 4 S>F F+ F>S 7 = S" F+" EXPECT
10 S>F 3 S>F F- F>S 7 = S" F-" EXPECT
6 S>F 7 S>F F* F>S 42 = S" F*" EXPECT
15 S>F 3 S>F F/ F>S 5 = S" F/" EXPECT
5 S>F FNEGATE F>S -5 = S" FNEGATE" EXPECT
-9 S>F FABS F>S 9 = S" FABS" EXPECT

\ --- stack ops ---
1 S>F 2 S>F FSWAP F>S 1 = S" FSWAP" EXPECT
FDROP
1 S>F FDUP F>S F>S + 2 = S" FDUP" EXPECT
(FCLEAR)

\ --- FDEPTH after pushes ---
1 S>F 2 S>F 3 S>F
FDEPTH 3 = S" FDEPTH3" EXPECT
(FCLEAR)

\ --- FLOATS / FLOAT+ ---
3 FLOATS 24 = S" FLOATS" EXPECT
0 FLOATS 0 = S" 0FLOATS" EXPECT
HERE FLOAT+ HERE - 8 = S" FLOAT+" EXPECT

\ --- F@ F! ---
CREATE FBUF 8 ALLOT
3 S>F FBUF F!
FBUF F@ F>S 3 = S" F@F!" EXPECT

\ --- D>F F>D ---
100 0 D>F F>S 100 = S" D>F" EXPECT
-5 S>F F>D
-1 = SWAP -5 = AND S" F>D" EXPECT

\ --- float literals (need host parseLit) ---
1.5e0 3e0 F* F>S 4 = S" lit* " EXPECT
\ 1.5*3 = 4.5, F>S truncates toward zero -> 4
0e0 F0= S" 0e" EXPECT
(FCLEAR)

\ --- >FLOAT ---
\ ANS 12.6.1.0558: blanks-only string is a successful conversion to 0e
S" 2.5" >FLOAT S" >FLOAT" EXPECT
F>S 2 = S" >Fval" EXPECT
S"    " >FLOAT S" >Fblank" EXPECT
F0= S" >Fblank0" EXPECT
(FCLEAR)

\ --- FCONSTANT / FVARIABLE ---
2 S>F FCONSTANT FC2
FC2 F>S 2 = S" FCONSTANT" EXPECT
FVARIABLE FV1
7 S>F FV1 F!
FV1 F@ F>S 7 = S" FVARIABLE" EXPECT
(FCLEAR)

\ --- compares ---
1 S>F 2 S>F F< S" F<" EXPECT
2 S>F 1 S>F F> S" F>" EXPECT
3 S>F 3 S>F F= S" F=" EXPECT
3 S>F 4 S>F F<> S" F<>" EXPECT
0 S>F F0= S" F0=" EXPECT
(FCLEAR)

\ --- F~ exact (r1 r2 r3 -- flag); r3=0 exact ---
5 S>F 5 S>F 0 S>F F~ S" F~exact" EXPECT
5 S>F 6 S>F 0 S>F F~ 0= S" F~diff" EXPECT
(FCLEAR)

\ --- FROT ---
1 S>F 2 S>F 3 S>F FROT
F>S 1 = S" FROTa" EXPECT
F>S 3 = S" FROTb" EXPECT
F>S 2 = S" FROTc" EXPECT
(FCLEAR)

\ --- FSQRT ---
9 S>F FSQRT F>S 3 = S" FSQRT" EXPECT
(FCLEAR)

\ --- FSIN 0 ---
0 S>F FSIN F0= S" FSIN0" EXPECT
(FCLEAR)

\ --- SF@ SF! ---
CREATE SFBUF 4 ALLOT
8 S>F SFBUF SF!
SFBUF SF@ F>S 8 = S" SF@SF!" EXPECT
(FCLEAR)

\ restore search order for later modules / driver summary
ONLY FORTH DEFINITIONS

.( --- Float batch done ---) .STACK-DEPTH CR
