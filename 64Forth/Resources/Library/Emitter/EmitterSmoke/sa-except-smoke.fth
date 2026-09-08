\ sa-except-smoke.fth — stand-alone TGT-BUILD with auto-CATCH past SA-EXCEPT patch.
\ Public domain. Does not pack a .app (stops after TGT-BUILD / before SYSTEM).
\ Canonical: Xcode Resources/Library/Emitter (Documents/64Forth/Library is a symlink).
\ Prefer:  FROMLIB FLOAD Emitter/EmitterSmoke/sa-except-smoke.fth
\ Agent:   …/64Forth --agent -f $HOME/Documents/64Forth/Library/Emitter/EmitterSmoke/sa-except-smoke.fth

FROMLIB FLOAD Emitter/emitter.fth
ONLY FORTH ALSO SYSVOC ALSO EMITTER DEFINITIONS

: T-SA-BODY  ( -- )  ;

: SA-EXCEPT-SMOKE  ( -- )
  CR ." === sa-except: TGT-BUILD auto-CATCH wrap === " CR
  /EMIT-STANDALONE
  /EMIT-UNBOUND
  ['] T-SA-BODY (EMIT-CATCH-WRAP)
  ['] TGT-BUILD CATCH
  DUP IF
    ." FAIL: TGT-BUILD threw " . CR ABORT
  THEN DROP
  ." PASS: TGT-BUILD with CATCH completed (SA-EXCEPT ok)" CR
  TGT-CLOSE
;

SA-EXCEPT-SMOKE
ONLY FORTH DEFINITIONS
