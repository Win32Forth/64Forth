\ sa-print-smoke.fth — /EMIT-STANDALONE numeric print via SA-PRINT block.
\ Requires rebuilt kernel with (SA-PRINT). Public domain.
\
\   FROMLIB FLOAD Emitter/emitter.fth
\   FROMLIB FLOAD Emitter/EmitterSmoke/sa-print-smoke.fth
\ Canonical: Xcode Resources/Library/Emitter (Documents/64Forth/Library is a symlink).
\ Prefer:  FROMLIB FLOAD Emitter/EmitterSmoke/sa-print-smoke.fth
\ Agent:   …/64Forth --agent -f $HOME/Documents/64Forth/Library/Emitter/EmitterSmoke/sa-print-smoke.fth

ONLY FORTH ALSO SYSVOC ALSO EMITTER DEFINITIONS DECIMAL

CR .( --- sa-print-smoke ---) CR

: (CK-SA-PRINT)  ( -- )
  S" (SA-PRINT)" ['] EMITTER 2 CELLS + SEARCH-WORDLIST
  DUP 0= IF
    DROP
    S" FAIL: SA-PRINT missing from EMITTER" TYPE CR
    BYE
  THEN
  DROP DROP
  S" ok: SA-PRINT in EMITTER" TYPE CR ;

(CK-SA-PRINT)

: T-DOT  42 . ;

/EMIT-STANDALONE
' T-DOT DUP TGT-BUILD
CR .( --- TGT-RUN T-DOT expect 42 ---) CR
TGT-RUN
CR .( --- sa-print-smoke done ---) CR
