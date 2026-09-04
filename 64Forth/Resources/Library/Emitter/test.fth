FROMLIB FLOAD Emitter/emitter.fth

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
