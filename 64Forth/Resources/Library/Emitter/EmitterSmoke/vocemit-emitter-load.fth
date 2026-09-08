\ vocemit-emitter-load.fth — load slicer after cold vocemit; check TGT-BUILD.
\ Public domain.
\ Canonical: Xcode Resources/Library/Emitter (Documents/64Forth/Library is a symlink).
\ Prefer:  FROMLIB FLOAD Emitter/EmitterSmoke/vocemit-emitter-load.fth
\ Agent:   …/64Forth --agent -f $HOME/Documents/64Forth/Library/Emitter/EmitterSmoke/vocemit-emitter-load.fth

FROMLIB FLOAD Emitter/emitter.fth

: (IN-FORTH?)  ( c-addr u -- flag )
  FORTH-WORDLIST SEARCH-WORDLIST DUP 0= IF EXIT THEN 2DROP TRUE ;

: (IN-EMIT?)  ( c-addr u -- flag )
  ['] EMITTER 2 CELLS + SEARCH-WORDLIST DUP 0= IF EXIT THEN 2DROP TRUE ;

: (CHECK-EMIT)  ( c-addr u -- )
  {: addr len -- :}
  addr len (IN-EMIT?) IF
    ." ok: " addr len TYPE ."  in EMITTER" CR
  ELSE
    ." FAIL: " addr len TYPE ."  missing from EMITTER" CR
  THEN
  addr len (IN-FORTH?) IF
    ." FAIL: " addr len TYPE ."  in FORTH" CR
  ELSE
    ." ok: " addr len TYPE ."  not in FORTH" CR
  THEN ;

S" TGT-BUILD" (CHECK-EMIT)
S" ALLOCATE-EXEC" (CHECK-EMIT)

." depth=" DEPTH . CR
CR ." --- vocemit-emitter-load done ---" CR
