\ span-tests.fth — validate dbg-map build, span lookup, and host publish
\
\ Run (Debug DerivedData binary, never Applications):
\   …/64Forth --agent -f $HOME/Documents/64Forth/Library/DbgSpanSmoke/span-tests.fth
\ Or from a live console after Autoload:
\   FROMLIB FLOAD DbgSpanSmoke/span-tests.fth
\
\ Exit code: agent DONE (ok) when SPAN-FAILS is 0; else prints FAIL lines.

ONLY FORTH DEFINITIONS DECIMAL

\ Ensure debugger maps are loaded (safe to re-INCLUDE via hub ANEW).
FROMLIB S" Debugger/debugger.fth" INCLUDED

ONLY FORTH ALSO SYSVOC ALSO DEBUGGER DEFINITIONS

VARIABLE SPAN-FAILS
VARIABLE SPAN-CHECKS
0 SPAN-FAILS !
0 SPAN-CHECKS !

: SPAN-OK  ( flag c-addr u -- )
  SPAN-CHECKS @ 1+ SPAN-CHECKS !
  IF  2DROP
  ELSE
     SPAN-FAILS @ 1+ SPAN-FAILS !
     ." FAIL: " TYPE CR
  THEN ;

: SPAN-EQ  ( got exp c-addr u -- )
  {: got exp -- :}
  SPAN-CHECKS @ 1+ SPAN-CHECKS !
  got exp = IF  2DROP
  ELSE
     SPAN-FAILS @ 1+ SPAN-FAILS !
     ." FAIL: " TYPE ."  got=" got . ." exp=" exp . CR
  THEN ;

\ --- 1) BIND: cached XT must resolve (counted-string FIND via DBG-ED-FIND) ---

: T-BIND  ( -- )
  CR ." === T-BIND: DBG-HOST-SPAN XT ===" CR
  DBG-HOST-SPAN-BIND
  DBG-HOST-SPAN-XT @ 0<> S" DBG-HOST-SPAN-XT bound" SPAN-OK
  DBG-ED-HOST-SPAN-XT @ 0<> S" DBG-ED-HOST-SPAN-XT bound" SPAN-OK
  DBG-HOST-SPAN-XT @ DBG-ED-HOST-SPAN-XT @ = S" both caches same XT" SPAN-OK
  \ Direct kernel word still present in SYSVOC
  ALSO SYSVOC
  S" DBG-HOST-SPAN" DBG-ED-FIND
  PREVIOUS
  IF
     DBG-HOST-SPAN-XT @ = S" cache matches FIND XT" SPAN-OK
  ELSE
     FALSE S" DBG-HOST-SPAN findable in SYSVOC" SPAN-OK
  THEN
  \ Peek word required for host readback tests
  ALSO SYSVOC
  S" DBG-HOST-SPAN@" DBG-ED-FIND
  PREVIOUS
  IF  DROP TRUE  ELSE  FALSE  THEN
  S" DBG-HOST-SPAN@ present (rebuild kernel if missing)" SPAN-OK
;

\ --- 2) Host round-trip: set pending, peek without paint ---

: T-HOST-PUB  ( -- )
  CR ." === T-HOST-PUB: DBG-HOST-SPAN → DBG-HOST-SPAN@ ===" CR
  DBG-HOST-SPAN-XT @ 0= IF
     FALSE S" skip host pub — XT unbound" SPAN-OK EXIT
  THEN
  ALSO SYSVOC
  S" DBG-HOST-SPAN@" DBG-ED-FIND 0= IF
     PREVIOUS
     FALSE S" DBG-HOST-SPAN@ missing — rebuild Debug kernel" SPAN-OK
     EXIT
  THEN
  DROP
  PREVIOUS
  0 0 DBG-HOST-SPAN!
  DBG-HOST-SPAN-OK @ S" clear publish OK flag" SPAN-OK
  ALSO SYSVOC  DBG-HOST-SPAN@  PREVIOUS
  0= SWAP 0= AND S" peek after clear is 0 0" SPAN-OK
  4726 3 DBG-HOST-SPAN!
  DBG-HOST-SPAN-OK @ S" publish 4726 3 sets OK" SPAN-OK
  DBG-LAST-PUB-OFF @ 4726 = S" Forth echo off=4726" SPAN-OK
  DBG-LAST-PUB-LEN @ 3 = S" Forth echo len=3" SPAN-OK
  ALSO SYSVOC  DBG-HOST-SPAN@  PREVIOUS   \ ( off len )
  3 = S" host peek len=3" SPAN-OK
  4726 = S" host peek off=4726" SPAN-OK
  \ Second distinct span (multi-instance)
  4804 3 DBG-HOST-SPAN!
  ALSO SYSVOC  DBG-HOST-SPAN@  PREVIOUS
  3 = SWAP 4804 = AND S" host peek updates to 4804 3" SPAN-OK
;

\ --- 3) T3 map: three consecutive DUPs, distinct increasing offs ---

ANEW T3MOD
: T3  DUP DUP DUP  0= 0= ;

: T-MAP-T3  ( -- )
  {: | cmap n i off0 len0 prev xt -- :}
  CR ." === T-MAP-T3: three DUP spans ===" CR
  ['] T3 DBG-MAP-BUILD
  ['] T3 DBG-MAP-FIND-CFA TO cmap
  cmap 0<> S" T3 cmap built" SPAN-OK
  cmap 0= IF  EXIT  THEN
  cmap DBG-CMAP-NCELLS@ TO n
  n 3 >= S" T3 ncells >= 3" SPAN-OK
  0 TO i  0 TO prev  0 TO off0
  BEGIN  i n < WHILE
     cmap i DBG-SLOT-KIND@ DBG-K-CALL = IF
        cmap i DBG-SLOT-XT@ TO xt
        xt ['] DUP = IF
           cmap i DBG-SLOT-LEN@ TO len0
           cmap i DBG-SLOT-OFF@ TO off0
           len0 3 = S" T3 DUP len=3" SPAN-OK
           off0 0> S" T3 DUP off>0" SPAN-OK
           prev IF
              off0 prev > S" T3 DUP offs increase" SPAN-OK
           THEN
           off0 TO prev
           \ Publish + host peek for this slot
           off0 len0 DBG-HOST-SPAN!
           DBG-HOST-SPAN-OK @ S" T3 slot host OK" SPAN-OK
           ALSO SYSVOC  DBG-HOST-SPAN@  PREVIOUS
           len0 = SWAP off0 = AND S" T3 slot host peek matches map" SPAN-OK
        THEN
     THEN
     i 1+ TO i
  REPEAT
  prev 0<> S" T3 found at least one DUP" SPAN-OK
;

\ --- 4) (SEE-HDR): every CALL DUP slot has off/len; offs match source scan ---

\ Count whole-word "DUP" hits in [tbuf+lo, tbuf+hi) via portable HL helpers.
: SPAN-COUNT-DUP  ( lo hi -- n )
  {: lo hi | tbuf tend scan n ha -- :}
  0 TO n
  DBG-ED-TBUF TO tbuf
  tbuf 0= IF  0 EXIT  THEN
  DBG-ED-TEND TO tend
  tbuf lo + TO scan
  tbuf hi + tend MIN TO tend
  S" DUP" DBG-SET-TOKEN
  BEGIN
     scan tend DBG-SEARCH-TO TO ha
     ha
  WHILE
     n 1+ TO n
     ha DBG-ED-TOKEN C@ + TO scan
  REPEAT
  n ;

: T-MAP-SEE-HDR  ( -- )
  {: | cmap n i off len xt nslot prev -- :}
  CR ." === T-MAP-SEE-HDR: DUP instances ===" CR
  ['] (SEE-HDR) DBG-MAP-BUILD
  ['] (SEE-HDR) DBG-MAP-FIND-CFA TO cmap
  cmap 0<> S" (SEE-HDR) cmap built" SPAN-OK
  cmap 0= IF  EXIT  THEN
  cmap DBG-CMAP-FSEC@ DUP IF  DBG-MAP-BIND-FSEC-BUF  ELSE  DROP  THEN
  cmap DBG-CMAP-NCELLS@ TO n
  0 TO i  0 TO nslot  0 TO prev
  BEGIN  i n < WHILE
     cmap i DBG-SLOT-KIND@ DBG-K-CALL = IF
        cmap i DBG-SLOT-XT@ TO xt
        xt ['] DUP = IF
           cmap i DBG-SLOT-OFF@ TO off
           cmap i DBG-SLOT-LEN@ TO len
           len 3 = S" (SEE-HDR) DUP len=3" SPAN-OK
           off 0> S" (SEE-HDR) DUP off>0" SPAN-OK
           prev IF  off prev > S" (SEE-HDR) DUP offs increase" SPAN-OK  THEN
           off TO prev
           nslot 1+ TO nslot
           \ SPAN@ must return tbuf+off / len when TBUF bound
           cmap i DBG-MAP-SPAN@                    \ addr u
           DUP len = >R                            \ addr u | R: len-ok
           DROP DBG-ED-TBUF - off =                \ off-ok
           R> AND S" (SEE-HDR) SPAN@ addr/len" SPAN-OK
           off len DBG-HOST-SPAN!
           DBG-HOST-SPAN-OK @ S" (SEE-HDR) DUP host OK" SPAN-OK
           ALSO SYSVOC  DBG-HOST-SPAN@  PREVIOUS
           len = SWAP off = AND S" (SEE-HDR) DUP host peek=map" SPAN-OK
        THEN
     THEN
     i 1+ TO i
  REPEAT
  nslot 4 = S" (SEE-HDR) has exactly 4 DUP call slots" SPAN-OK
  ."   map DUP slots=" nslot . ."  last-off=" prev . CR
;

\ --- 5) Simulate BODY# → map cell# for nested Into path ---

\ Kernel DBG-BODY# counts from CFA+8; map index is BODY#-1 (see DBG-MAP-CELL#).
: T-CELL-MATH  ( -- )
  CR ." === T-CELL-MATH: BODY# → map# ===" CR
  \ Mirror DBG-MAP-CELL#: body# 0 → 0; else body#-1
  0 DUP IF  1-  THEN  0 = S" body#0 → map#0" SPAN-OK
  1 DUP IF  1-  THEN  0 = S" body#1 → map#0" SPAN-OK
  2 DUP IF  1-  THEN  1 = S" body#2 → map#1" SPAN-OK
  26 DUP IF  1-  THEN  25 = S" body#26 → map#25 (first nested DUP area)" SPAN-OK
;

\ --- runner ---

: SPAN-TESTS  ( -- )
  \ Hub INCLUDED should be stack-clean; belt-and-suspenders for older hubs.
  DEPTH IF DROP THEN
  0 SPAN-FAILS !
  0 SPAN-CHECKS !
  T-BIND
  T-HOST-PUB
  T-MAP-T3
  T-MAP-SEE-HDR
  T-CELL-MATH
  DEPTH 0= S" SPAN-TESTS stack clean" SPAN-OK
  CR ." === SPAN-TESTS done: checks=" SPAN-CHECKS @ .
  ." fails=" SPAN-FAILS @ . CR
  SPAN-FAILS @ 0= IF  ." ALL PASS" CR  ELSE  ." SOME FAILED" CR  THEN
;

SPAN-TESTS
ONLY FORTH DEFINITIONS
