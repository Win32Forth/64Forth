8 CONSTANT #BREAKS

: BREAK-XT  ( xt -- )
  BREAK-TABLE #BREAKS 0 DO
    DUP I CELLS + @ 0= IF
      I CELLS + !  UNLOOP EXIT
    THEN
  LOOP
  DROP ." BREAK table full" CR ;

: UNBREAK-XT  ( xt -- )
  BREAK-TABLE #BREAKS 0 DO
    2DUP I CELLS + @ = IF
      0 I CELLS BREAK-TABLE + !  DROP UNLOOP EXIT
    THEN
  LOOP DROP ;

: BREAK    ( "<name>" -- )  ' BREAK-XT ;
: UNBREAK  ( "<name>" -- )  ' UNBREAK-XT ;

: .BREAKS  ( -- )
  CR ." breaks:" CR
  BREAK-TABLE #BREAKS 0 DO
    I CELLS BREAK-TABLE + @ ?DUP IF
      I . NAME>STRING TYPE CR
    THEN
  LOOP ;

: BPGO  ( "<name>" -- )
  >IN @  BL WORD C@ 0= IF
    DROP ." BPGO needs a name" CR EXIT
  THEN  >IN !
  ' DBG-ON (BP-GO)          \ now: set debug_bp_go only
  CATCH
  DBG-OFF
  ?DUP IF THROW THEN
;
