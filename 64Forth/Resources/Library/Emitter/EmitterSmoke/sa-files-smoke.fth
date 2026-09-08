\ sa-files-smoke.fth — /EMIT-STANDALONE File-Access via SA-FILES block.
\ Requires rebuilt kernel with (SA-FILES). Public domain.
\
\   FROMLIB FLOAD Emitter/emitter.fth
\   FROMLIB FLOAD Emitter/EmitterSmoke/sa-files-smoke.fth
\ Canonical: Xcode Resources/Library/Emitter (Documents/64Forth/Library is a symlink).
\ Prefer:  FROMLIB FLOAD Emitter/EmitterSmoke/sa-files-smoke.fth
\ Agent:   …/64Forth --agent -f $HOME/Documents/64Forth/Library/Emitter/EmitterSmoke/sa-files-smoke.fth

ONLY FORTH ALSO SYSVOC ALSO EMITTER DEFINITIONS DECIMAL

CR .( --- sa-files-smoke ---) CR

: (CK-SA-FILES)  ( -- )
  S" (SA-FILES)" ['] EMITTER 2 CELLS + SEARCH-WORDLIST
  DUP 0= IF
    DROP
    S" FAIL: SA-FILES missing from EMITTER" TYPE CR
    BYE
  THEN
  DROP DROP
  S" ok: SA-FILES in EMITTER" TYPE CR ;

(CK-SA-FILES)

\ Create / write / close / open / read / close under /tmp.
\ Use . for status (TYPE may not appear in agent transcript the same way).
VARIABLE SF-FID
CREATE SF-BUF  16 ALLOT

: T-FILES  ( -- )
  S" /tmp/64forth-sa-files.txt" W/O CREATE-FILE
  IF  1 . EXIT  THEN                 \ 1 = CREATE fail
  SF-FID !
  S" hi" SF-FID @ WRITE-FILE
  IF  2 . EXIT  THEN                 \ 2 = WRITE fail
  SF-FID @ CLOSE-FILE
  IF  3 . EXIT  THEN                 \ 3 = CLOSE fail
  S" /tmp/64forth-sa-files.txt" R/O OPEN-FILE
  IF  4 . EXIT  THEN                 \ 4 = OPEN fail
  SF-FID !
  SF-BUF 2 SF-FID @ READ-FILE
  IF  5 . EXIT  THEN                 \ 5 = READ ior fail
  2 = 0= IF  6 . EXIT  THEN          \ 6 = bad length
  SF-BUF C@ [CHAR] h = 0= IF  7 . EXIT  THEN
  SF-BUF 1+ C@ [CHAR] i = 0= IF  8 . EXIT  THEN
  SF-FID @ CLOSE-FILE DROP
  S" /tmp/64forth-sa-files.txt" DELETE-FILE DROP
  42 .                               \ success marker like sa-print-smoke
  ;

/EMIT-STANDALONE
' T-FILES DUP TGT-BUILD
CR .( --- TGT-RUN T-FILES expect 42 ---) CR
TGT-RUN
CR .( --- sa-files-smoke done ---) CR
