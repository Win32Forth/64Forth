\ catch-require-smoke.fth — ABORT without CATCH must fail TGT-BUILD.
\ Public domain.
\
\ Expect: TGT-BUILD of T-ABORT-ONLY throws 1 (CATCH requirement).
\ Then REACH-FROM + TGT-REQUIRE-CATCH passes when CATCH is in the graph.
\ Canonical: Xcode Resources/Library/Emitter (Documents/64Forth/Library is a symlink).
\ Prefer:  FROMLIB FLOAD Emitter/EmitterSmoke/catch-require-smoke.fth
\ Agent:   …/64Forth --agent -f $HOME/Documents/64Forth/Library/Emitter/EmitterSmoke/catch-require-smoke.fth

FROMLIB FLOAD Emitter/emitter.fth

ONLY FORTH ALSO EMITTER DEFINITIONS

: T-ABORT-ONLY  ( -- )  ABORT ;
: TRY-ABORT-ONLY  ( -- )  ['] T-ABORT-ONLY TGT-BUILD ;

: T-ABORT-CAUGHT  ( -- )
  ['] ABORT CATCH DROP ;

: CATCH-REQUIRE-SMOKE  ( -- )
  CR ." === catch-require: ABORT without CATCH === " CR
  ['] TRY-ABORT-ONLY CATCH
  DUP 1 <> IF
    ." FAIL: expected throw 1, got " . CR ABORT
  THEN DROP
  ." PASS: TGT-BUILD refused ABORT without CATCH" CR

  CR ." === catch-require: REACH allows ABORT with CATCH === " CR
  ['] T-ABORT-CAUGHT REACH-FROM
  TGT-MARK-CATCH-OK
  ['] TGT-REQUIRE-CATCH CATCH IF
    ." FAIL: TGT-REQUIRE-CATCH threw" CR ABORT
  THEN
  ['] CATCH MARKED? 0= IF  ." FAIL: CATCH not marked" CR ABORT  THEN
  (CATCH-OK-XT) MARKED? 0= IF  ." FAIL: (CATCH-OK) not marked" CR ABORT  THEN
  ." PASS: CATCH + (CATCH-OK) marked; requirement OK" CR
;

CATCH-REQUIRE-SMOKE

ONLY FORTH DEFINITIONS
