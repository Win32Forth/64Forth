\ tester-only.fth — load harness alone
\   INCLUDE /Users/thomaszimmer/Documents/XCodeProjects/64Forth/64Forth/Resources/Library/ANSValidate/tester-only.fth

DECIMAL
ONLY FORTH DEFINITIONS
CR .( TO-START) CR

VARIABLE PASSN
VARIABLE FAILN
0 PASSN !
0 FAILN !

: T.PASS  PASSN @ 1+ PASSN ! ;
: T.FAIL  FAILN @ 1+ FAILN ! ." FAIL " ;
: EXPECT  ROT IF 2DROP T.PASS ELSE T.FAIL THEN ;

TRUE S" x" EXPECT
PASSN @ . CR
CR .( TO-END) CR
