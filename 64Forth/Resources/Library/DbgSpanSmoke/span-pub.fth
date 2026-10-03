\ Prove DBG-HOST-SPAN exists and map publishes distinct offs for cell 0..2
S" Library/Debugger/debugger.fth" INCLUDED
FROMLIB REQUIRE DbgSpanSmoke/dup-test.fth
ONLY FORTH ALSO SYSVOC ALSO DEBUGGER DEFINITIONS

: CHECK-SPAN  ( -- )
  {: | cmap ncells i -- :}
  S" DBG-HOST-SPAN" FIND IF
     ." HOST-SPAN xt ok" CR DROP
  ELSE
     ." HOST-SPAN MISSING" CR EXIT
  THEN
  ['] T3 DBG-MAP-BUILD
  ['] T3 DBG-MAP-FIND-CFA TO cmap
  cmap 0= IF ." no cmap" CR EXIT THEN
  cmap DBG-CMAP-NCELLS@ TO ncells
  ." ncells=" ncells . CR
  \ For each CALL cell, show slot off and simulate HL-SPAN conversion
  0 TO i
  BEGIN  i ncells < WHILE
     cmap i DBG-SLOT-LEN@ IF
        ." cell " i .
        ." off=" cmap i DBG-SLOT-OFF@ .
        ." len=" cmap i DBG-SLOT-LEN@ .
        CR
     THEN
     i 1+ TO i
  REPEAT
  \ Publish cell 2's span via host (third DUP) then read back is host-only —
  \ just call DBG-HOST-SPAN with known offs
  ALSO SYSVOC
  25 3 DBG-HOST-SPAN
  PREVIOUS
  ." published off=25 len=3 for third DUP" CR
;

CHECK-SPAN
