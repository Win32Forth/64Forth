\ debug-bp.fth — BREAK / UNBREAK / BPGO (ITC DEBUG breakpoints)
\ Loaded only via Debugger/debugger.fth (DEBUGGER vocabulary / CURRENT).
\ Kernel provides BREAK-TABLE, BREAK-ENABLES, and (BP-GO); this file is the Forth UI.

8 CONSTANT #BREAKS

: NOBREAKS  ( -- )
    #BREAKS 0 DO
        0 I CELLS BREAK-TABLE + !
        0 I CELLS BREAK-ENABLES + !
    LOOP ;

: BREAK-XT  ( xt -- )
  BREAK-TABLE #BREAKS 0 DO
    DUP I CELLS + @ 0= IF
      I CELLS + !
      -1 I CELLS BREAK-ENABLES + !
      UNLOOP EXIT
    THEN
  LOOP
  2DROP ." BREAK table full" CR ;

: UNBREAK-XT  ( xt -- )
  BREAK-TABLE #BREAKS 0 DO
    2DUP I CELLS + @ = IF
      0 I CELLS BREAK-TABLE + !
      0 I CELLS BREAK-ENABLES + !
      2DROP UNLOOP EXIT
    THEN
  LOOP 2DROP ;

: BREAK    ( "<name>" -- )  ' BREAK-XT ;
: UNBREAK  ( "<name>" -- )  ' UNBREAK-XT ;

\ Was OVER: first `=` ate BREAK-TABLE, next OVER underflowed, `@` of 0 → XFETCH crash.
: BREAK-HAS?  ( xt -- flag )
  BREAK-TABLE #BREAKS 0 DO
    2DUP I CELLS + @ = IF 2DROP TRUE UNLOOP EXIT THEN
  LOOP 2DROP FALSE ;

: TOGGLE-BREAK-XT  ( xt -- )
  DUP BREAK-HAS? IF UNBREAK-XT ELSE BREAK-XT THEN ;

: TOGGLE-BREAK  ( "<name>" -- )  ' TOGGLE-BREAK-XT ;

: DISABLE-BREAK-XT  ( xt -- )
  BREAK-TABLE #BREAKS 0 DO
    2DUP I CELLS + @ = IF
      0 I CELLS BREAK-ENABLES + !
      2DROP UNLOOP EXIT
    THEN
  LOOP 2DROP ;

: ENABLE-BREAK-XT  ( xt -- )
  BREAK-TABLE #BREAKS 0 DO
    2DUP I CELLS + @ = IF
      -1 I CELLS BREAK-ENABLES + !
      2DROP UNLOOP EXIT
    THEN
  LOOP 2DROP ;

: DISABLE-BREAK  ( "<name>" -- )  ' DISABLE-BREAK-XT ;
: ENABLE-BREAK   ( "<name>" -- )  ' ENABLE-BREAK-XT ;

: .BREAKS  ( -- )
  CR ." breaks:" CR
  #BREAKS 0 DO
    I CELLS BREAK-TABLE + @ ?DUP IF
      I . NAME>STRING TYPE
      I CELLS BREAK-ENABLES + @ 0= IF ."  (off)" THEN
      CR
    THEN
  LOOP ;

: BPGO-XT  ( xt -- )
  DBG-ON (BP-GO)          \ now: set debug_bp_go only
  CATCH
  DBG-OFF
  ?DUP IF THROW THEN ;

: BPGO  ( "<name>" -- )
  >IN @  BL WORD C@ 0= IF
    DROP ." BPGO needs a name" CR EXIT
  THEN  >IN !
  ' BPGO-XT ;
