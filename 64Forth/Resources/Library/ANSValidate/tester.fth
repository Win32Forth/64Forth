\ tester.fth — shared PASS/FAIL harness for ANSValidate modules
\
\ CRITICAL 64Forth rules:
\   1) Do NOT use IF/ELSE/THEN/BEGIN while interpreting — they always compile.
\      Put conditionals only inside colon definitions.
\   2) Use ." for runtime print inside colon words; .( is compile-time and
\      stops at the first ) — never nest parentheses in .( messages.

DECIMAL
ONLY FORTH DEFINITIONS

VARIABLE #PASS
VARIABLE #FAIL
0 #PASS !
0 #FAIL !

: T.PASS  #PASS @ 1+ #PASS ! ;
: T.FAIL  ( ca u -- ) #FAIL @ 1+ #FAIL ! ." FAIL: " TYPE CR ;
: EXPECT  ( flag ca u -- ) ROT IF 2DROP T.PASS ELSE T.FAIL THEN ;

\ Summary for one section or the whole run:  S" Core" .TEST-SUMMARY
: .TEST-SUMMARY  ( ca u -- )
  CR TYPE ." : " #PASS @ . ." passed, " #FAIL @ . ." failed." CR
  #FAIL @ IF ." *** FAILURES ***" CR ELSE ." ALL PASS" CR THEN ;

\ Optional: zero counters between modules without reloading tester
: ZERO-COUNTS  0 #PASS ! 0 #FAIL ! ;
