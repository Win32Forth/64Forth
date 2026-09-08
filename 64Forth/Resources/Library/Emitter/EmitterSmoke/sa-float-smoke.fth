\ sa-float-smoke.fth — /EMIT-STANDALONE FP via SA-FLOAT block.
\ Requires rebuilt kernel with (SA-FLOAT). Public domain.
\
\   FROMLIB FLOAD Emitter/emitter.fth
\   FROMLIB FLOAD Emitter/EmitterSmoke/sa-float-smoke.fth
\ Canonical: Xcode Resources/Library/Emitter (Documents/64Forth/Library is a symlink).
\ Prefer:  FROMLIB FLOAD Emitter/EmitterSmoke/sa-float-smoke.fth
\ Agent:   …/64Forth --agent -f $HOME/Documents/64Forth/Library/Emitter/EmitterSmoke/sa-float-smoke.fth

ONLY FORTH ALSO SYSVOC ALSO EMITTER ALSO FP DEFINITIONS DECIMAL

CR .( --- sa-float-smoke ---) CR

: (CK-SA-FLOAT)  ( -- )
  S" (SA-FLOAT)" ['] EMITTER 2 CELLS + SEARCH-WORDLIST
  DUP 0= IF
    DROP
    S" FAIL: SA-FLOAT missing from EMITTER" TYPE CR
    BYE
  THEN
  DROP DROP
  S" ok: SA-FLOAT in EMITTER" TYPE CR ;

(CK-SA-FLOAT)

\ 3 S>F  4 S>F  F+  F>S  → 7
: T-FLOAT  ( -- )
  3 S>F  4 S>F  F+  F>S  . ;

/EMIT-STANDALONE
' T-FLOAT DUP TGT-BUILD
CR .( --- TGT-RUN T-FLOAT expect 7 ---) CR
TGT-RUN
CR .( --- sa-float-smoke done ---) CR
