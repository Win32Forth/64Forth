\ see.fth — SEE / HELP (always loaded from autoload.fth)
\
\ Self-contained: redefines DOCOL? using boot CODE DOCOL-ADDR so this file
\ works even if late forth_init never finished.

: DOCOL?  ( xt -- flag )  @ DOCOL-ADDR = ;

: (SEE-BR?)  ( xt -- flag )
  >R R@ BRANCH-ADDR = R@ 0BRANCH-ADDR = OR
  R@ ['] (LOOP) = OR R@ ['] (+LOOP) = OR R> DROP ;

: (SEE-HDR)  ( xt -- xt )
  DUP DOCOL? IF
    58 EMIT SPACE
  ELSE
    67 EMIT 79 EMIT 68 EMIT 69 EMIT SPACE
  THEN
  DUP NAME>HELP DUP IF TYPE ELSE 2DROP DUP NAME>STRING TYPE THEN CR ;

: (SEE-PRIM)  ( xt -- )
  DROP
  40 EMIT 112 EMIT 114 EMIT 105 EMIT 109 EMIT
  105 EMIT 116 EMIT 105 EMIT 118 EMIT 101 EMIT 41 EMIT CR ;

\ (SEE-STEP) ( addr -- addr' | 0 )  0 means finished (printed ;)
: (SEE-STEP)
  DUP @ >R
  R@ EXIT-ADDR = IF R> DROP DROP 59 EMIT CR 0 EXIT THEN
  R@ LIT-ADDR = IF R> DROP 8 + DUP @ . SPACE 8 + EXIT THEN
  R@ SLIT-ADDR = IF
    R> DROP 8 + DUP @ >R 8 +
    83 EMIT 34 EMIT SPACE DUP R@ TYPE 34 EMIT SPACE
    R> + ALIGNED EXIT
  THEN
  R@ (SEE-BR?) IF
    R@ NAME>STRING TYPE SPACE R> DROP 8 + DUP @ . SPACE 8 + EXIT
  THEN
  R@ NAME>STRING TYPE SPACE R> DROP 8 + ;

: SEE  ( "name" -- )
  ' DUP (SEE-HDR)
  DUP DOCOL? 0= IF (SEE-PRIM) EXIT THEN
  >BODY BEGIN (SEE-STEP) DUP 0= UNTIL DROP ;

: HELP  ( "name" -- )  SEE ;
