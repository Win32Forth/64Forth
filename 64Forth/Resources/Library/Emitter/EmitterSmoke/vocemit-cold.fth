\ vocemit-cold.fth — cold-start checks for Kernel/vocemit.fth (no AutoLoad).
\ Public domain.
\ Canonical: Xcode Resources/Library/Emitter (Documents/64Forth/Library is a symlink).
\ Prefer:  FROMLIB FLOAD Emitter/EmitterSmoke/vocemit-cold.fth
\ Agent:   …/64Forth --agent -f $HOME/Documents/64Forth/Library/Emitter/EmitterSmoke/vocemit-cold.fth

CR ." --- cold vocab ---" CR
.VOCABULARIES

: (IN-FORTH?)  ( c-addr u -- flag )
  FORTH-WORDLIST SEARCH-WORDLIST DUP 0= IF EXIT THEN 2DROP TRUE ;

: (IN-EMIT?)  ( c-addr u -- flag )
  ['] EMITTER 2 CELLS + SEARCH-WORDLIST DUP 0= IF EXIT THEN 2DROP TRUE ;

: (CHECK)  ( c-addr u -- )
  {: addr len -- :}
  addr len (IN-FORTH?) IF
    ." FAIL: " addr len TYPE ."  still in FORTH" CR
  ELSE
    ." ok: " addr len TYPE ."  not in FORTH" CR
  THEN
  addr len (IN-EMIT?) IF
    ." ok: " addr len TYPE ."  in EMITTER" CR
  ELSE
    ." FAIL: " addr len TYPE ."  missing from EMITTER" CR
  THEN ;

S" ALLOCATE-EXEC" (CHECK)
S" JIT-WPROTECT" (CHECK)
S" (NEXT)" (CHECK)
S" (DOCOL)" (CHECK)
S" (DOVAR)" (CHECK)
S" (DOCON)" (CHECK)
S" (DODOES)" (CHECK)
S" (UDIVMOD128)" (CHECK)
S" (SA-PRINT)" (CHECK)
S" (SA-FILES)" (CHECK)
S" (SA-FLOAT)" (CHECK)
S" (PUTCHAR)" (CHECK)
S" (COMPILE-CELL)" (CHECK)
S" (LOCAL-FRAME-EXIT)" (CHECK)
S\" (.)" (CHECK)
S\" (U.)" (CHECK)
S" (FILE-OP-CALL)" (CHECK)

\ Must remain visible in FORTH for SEE / kernel.
: (STAY-FORTH)  ( c-addr u -- )
  {: addr len -- :}
  addr len (IN-FORTH?) IF
    ." ok: " addr len TYPE ."  still in FORTH" CR
  ELSE
    ." FAIL: " addr len TYPE ."  missing from FORTH" CR
  THEN ;

S" DOCOL-ADDR" (STAY-FORTH)
S" DOCON-ADDR" (STAY-FORTH)
S" CODE-BOUNDS" (STAY-FORTH)
S" LIT-ADDR" (STAY-FORTH)

." depth=" DEPTH . CR
CR ." --- vocemit-cold done ---" CR
