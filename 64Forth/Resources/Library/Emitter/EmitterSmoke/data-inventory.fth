\ data-inventory.fth — list DATA-WORD? reachables from MAIN (Phase 0).
\ Public domain.
\
\ Canonical: Xcode Resources/Library/Emitter (Documents/64Forth/Library is a symlink).
\ Prefer:  FROMLIB FLOAD Emitter/EmitterSmoke/data-inventory.fth
\ Agent:   …/64Forth --agent -f $HOME/Documents/64Forth/Library/Emitter/EmitterSmoke/data-inventory.fth

ONLY FORTH DEFINITIONS DECIMAL
FROMLIB FLOAD Emitter/emitter.fth
ALSO GRAPHICS

S" /Users/thomaszimmer/Documents/64TCOM/64TCOMARM64/tetra/tetra.fth" INCLUDED

\ GRAPHICS shadows EMIT/TYPE/. — inventory must use console IO.
ONLY FORTH ALSO SYSVOC ALSO EMITTER DEFINITIONS

0 VALUE ND

: .1DATA  ( xt -- )
  DUP NAME>STRING TYPE SPACE
  DUP DOVAR? IF  ." DOVAR"
  ELSE DUP DOCON? IF  ." DOCON"
  ELSE  ." DODOES"  THEN THEN
  SPACE HEX DUP U. DECIMAL CR DROP ;

: SCAN-DATA  ( -- )
  0 TO ND
  0 BEGIN  DUP REACH-N @ <  WHILE
    DUP CELLS REACH-XTS + @
    DUP DATA-WORD? IF
      ND 1+ TO ND
      .1DATA
    ELSE DROP THEN
    1+
  REPEAT DROP ;

CR .( reach MAIN ) CR
['] MAIN REACH-FROM
CR .( REACH-N ) REACH-N @ . CR

CR .( === DATA words === ) CR
SCAN-DATA
CR .( data count ) ND . CR

CR .( G-BUF DOVAR? ) ['] G-BUF DOVAR? . CR
CR .( G-COLS G-ROWS cells ) G-COLS . G-ROWS . G-COLS G-ROWS * . CR

CR .( DONE data-inventory ) CR
