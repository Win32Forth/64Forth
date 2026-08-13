\ probe.fth — bisect the XSTORE fault (line ~1555)
\ Load from disk (not FROMLIB) so you always get this file:
\
\   INCLUDE /Users/thomaszimmer/Documents/XCodeProjects/64Forth/64Forth/Resources/Library/ANSValidate/probe.fth
\
\ Watch which STEP line is last before a crash.

DECIMAL
ONLY FORTH DEFINITIONS

CR .( STEP 1: plain store ) CR
VARIABLE PV
99 PV !
PV @ . CR

CR .( STEP 2: CREATE buffer + C! ) CR
CREATE PB 16 ALLOT
65 PB C!
PB C@ . CR

CR .( STEP 3: XC!+ euro ) CR
8364 PB XC!+ PB - . CR
PB C@ . PB 1+ C@ . PB 2 + C@ . CR

CR .( STEP 4: XC-SIZE ) CR
8364 XC-SIZE . CR

CR .( STEP 5: ENVIRONMENT? ) CR
S" EXTENDED-CHARACTER" ENVIRONMENT? .S CR
DROP DROP

CR .( STEP 6: EXPECT-like counter without # names ) CR
VARIABLE TP
VARIABLE TF
0 TP !  0 TF !
: POK  1 TP +! ;
: PNG  1 TF +! ;
TRUE IF POK ELSE PNG THEN
TP @ . TF @ . CR

CR .( STEP 7: Squote COMPARE ) CR
S" UTF-8" S" UTF-8" COMPARE . CR

CR .( STEP 8: XC@+ after encode ) CR
8364 PB XC!+ DROP
PB XC@+ . . CR

CR .( STEP 9: XEMIT euro ) CR
8364 XEMIT CR

CR .( STEP 10: pictured XHOLD ) CR
: PH  <# 50 HOLD 8364 XHOLD 49 HOLD 0 0 #> ;
PH TYPE CR

CR .( PROBE COMPLETE — no crash ) CR
.S CR
