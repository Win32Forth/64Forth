\ FROMLIB FLOAD Emitter/emitter.fth



.( Loading test.fth ) CR

: TMAIN  S" hi" TYPE ;

: BUILD-TMAIN
    ['] TMAIN TGT-BUILD
\    HEX  RUN-ORG @ U.  RUN-ORG @ W@ U.  DECIMAL
\    RUN-ORG @ 4096 5 MPROTECT .
\    ['] TMAIN TGT-RUN
    ;
.( running TGT-BUILD ) CR
BUILD-TMAIN
.( Ran TGT-BUILD ) CR

\s
HEX
: TST ( a1 -- n1 )
    MAP-FIND dup U.
    dup 0= IF ." DIDN'T FIND IT" EXIT THEN
    8 +
    DUP U. CR
    DUP W@ U. CR          \ first insn of TYPE
    ;
    
' TYPE TST
' EXIT TST
DECIMAL

\S

: TMAIN  S" hi" TYPE ;
' TMAIN REACH-FROM
.REACHABLE
' TMAIN TGT-BUILD
' TYPE MAP-FIND U.

HEX
' TYPE MAP-FIND 8 +            \ payload
' TYPE PRIM-SPAN NIP +        \ address of B
DUP U. SPACE
@ U. CR
' (NEXT) MAP-FIND 8 + U. CR
DECIMAL

\ NATIVE-SMOKE .                 \ must be 0
\ FROMLIB FLOAD Emitter/test.fth
\ ' MAIN TGT-BUILD
\ HEX
\ ' TYPE MAP-FIND 8 +            \ TYPE payload
\  ' TYPE PRIM-SPAN NIP +       \ should be the B
\ 4 - @ U.                     \ expect 14xxxxxx
\ ' (NEXT) dbg MAP-FIND 8 + U.
\ DECIMAL

\S      \ Stop interpreting HERE **********

: MAIN  S" hi" TYPE ;
: MAIN2  1 0= IF  2 THEN 3 . ;
: MAIN4  1 IF 2 ELSE 3 THEN . ;

: .SPANS
  CR ." n=" REACH-N @ . CR
  0 BEGIN
    DUP REACH-N @ <
  WHILE
    DUP . SPACE
    DUP CELLS REACH-XTS + @
    DUP NAME>STRING TYPE SPACE
    DUP COLON-WORD? IF
      ." colon " COLON-SPAN NIP
    ELSE
      ." prim " CODE-BOUNDS SWAP -
    THEN
    . CR
    1+
  REPEAT ;
  
' MAIN REACH-FROM
['] (DOCOL) (MARK)
['] (NEXT)  (MARK)
['] EXIT    (MARK)
.SPANS

: TRY  ( xt -- )
  DUP REACH-FROM
  ['] (DOCOL) (MARK)  ['] (NEXT) (MARK)  ['] EXIT (MARK)
  .REACHABLE CR
  TGT-BUILD
  TGT-SIZE . CR
  .MAP ;

' MAIN TRY
' MAIN2 TRY
' MAIN4 TRY
