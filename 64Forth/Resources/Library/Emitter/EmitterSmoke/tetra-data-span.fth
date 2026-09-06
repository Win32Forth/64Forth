\ tetra-data-span.fth — CREATE FIGURE (,) and NOTES (ALLOT) under Emitter.
\ Expect: dict-scan DATA-SPAN covers comma/ALLOT bodies; standalone fill-notes
\ + FILL.CURR succeed without ABORT/THROW in the target.
\ Public domain.

ONLY FORTH DEFINITIONS DECIMAL
FROMLIB FLOAD Emitter/emitter.fth
ALSO GRAPHICS
S" /Users/thomaszimmer/Documents/64TCOM/64TCOMARM64/tetra/tetra.fth" INCLUDED
ONLY FORTH ALSO SYSVOC ALSO EMITTER DEFINITIONS

: CHECK-SPAN  ( xt min-u -- )
  {: xt minu | u -- :}
  xt DATA-SPAN NIP TO u
  xt NAME>STRING TYPE ."  span=" u .
  u minu < IF ." FAIL need>=" minu . CR ABORT THEN
  ." ok" CR ;

CR .( --- dict-scan spans --- ) CR
' FIGURE 456 CHECK-SPAN
' NOTES  200 CHECK-SPAN
' CURR    64 CHECK-SPAN

0 VALUE T-OK
: T-FN
  0 TO T-OK
  fill-notes
  NOTES @ 0= IF  EXIT  THEN
  0 TO FIGURE.NO
  FILL.CURR
  CURR @ 8 <> IF  EXIT  THEN
  1 TO T-OK
  ;

/EMIT-STANDALONE
: GO
  ['] T-FN DUP TGT-BUILD TGT-RUN
  T-OK IF ." fn-ok" CR ELSE ." FAIL T-FN" CR ABORT THEN
  ;
GO
CR .( tetra-data-span: OK ) CR
BYE
