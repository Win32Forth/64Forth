\ emit-catch-wrap-smoke.fth — EMIT-APP auto-CATCH wrap marks CATCH.
\ Public domain.
\
\ Does not pack a .app; only checks (EMIT-CATCH-WRAP) + REACH-FROM.
\ Checks run inside a colon word — interpret-state IF/THEN is not used.
\ Canonical: Xcode Resources/Library/Emitter (Documents/64Forth/Library is a symlink).
\ Prefer:  FROMLIB FLOAD Emitter/EmitterSmoke/emit-catch-wrap-smoke.fth
\ Agent:   …/64Forth --agent -f $HOME/Documents/64Forth/Library/Emitter/EmitterSmoke/emit-catch-wrap-smoke.fth

FROMLIB FLOAD Emitter/emitter.fth

ONLY FORTH ALSO SYSVOC ALSO EMITTER DEFINITIONS

: T-SMOKE-BODY  ( -- )  ;

: T-MY-THROW  ( n -- )  DROP ;

: EMIT-CATCH-WRAP-SMOKE  ( -- )
  CR ." === emit-catch-wrap: auto CATCH === " CR
  ['] T-SMOKE-BODY (EMIT-CATCH-WRAP)
  REACH-FROM
  TGT-MARK-CATCH-OK
  ['] CATCH MARKED? 0= IF
    ." FAIL: CATCH not marked" CR ABORT
  THEN
  (CATCH-OK-XT) MARKED? 0= IF
    ." FAIL: (CATCH-OK) not marked" CR ABORT
  THEN
  ['] T-SMOKE-BODY MARKED? 0= IF
    ." FAIL: LIT xt (T-SMOKE-BODY) not marked" CR ABORT
  THEN
  ['] THROW MARKED? 0= IF
    \ THROW may appear only when ABORT is reachable; auto wrap uses CATCH alone.
    ." note: THROW not in reach (OK without ABORT)" CR
  THEN
  ." PASS: auto-CATCH wrap reaches CATCH + (CATCH-OK) + body xt" CR

  CR ." === emit-catch-wrap: EMIT-ON-THROW override visible === " CR
  ACTION-OF EMIT-ON-THROW
  ['] T-MY-THROW IS EMIT-ON-THROW
  ACTION-OF EMIT-ON-THROW ['] T-MY-THROW <> IF
    ." FAIL: IS EMIT-ON-THROW did not stick" CR ABORT
  THEN
  IS EMIT-ON-THROW   \ restore previous (xt still under)
  ." PASS: EMIT-ON-THROW IS works" CR
;

EMIT-CATCH-WRAP-SMOKE

ONLY FORTH DEFINITIONS
