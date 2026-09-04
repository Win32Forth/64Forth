FROMLIB FLOAD Emitter/emitter.fth

: MAIN  S" hi" TYPE ;

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

