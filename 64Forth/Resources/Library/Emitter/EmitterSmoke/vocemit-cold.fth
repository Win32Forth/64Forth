\ vocemit-cold.fth — cold-start checks for Kernel/vocemit.fth (no AutoLoad).
\ Public domain.

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
