\ vocsys-cold.fth — cold-start checks for Kernel/vocsys.fth.
\ Public domain.
\ Canonical: Xcode Resources/Library/Emitter (Documents/64Forth/Library is a symlink).
\ Prefer:  FROMLIB FLOAD Emitter/EmitterSmoke/vocsys-cold.fth
\ Agent:   …/64Forth --agent -f $HOME/Documents/64Forth/Library/Emitter/EmitterSmoke/vocsys-cold.fth

CR ." --- vocsys cold ---" CR
.VOCABULARIES

: (IN-WL?)  ( c-addr u wid -- flag )
  SEARCH-WORDLIST DUP 0= IF EXIT THEN 2DROP TRUE ;

: (IN-FORTH?)  ( c-addr u -- flag )
  FORTH-WORDLIST (IN-WL?) ;

: (VWID)  ( vocab-xt -- wid )  2 CELLS + ;

: (CHECK-TO)  ( c-addr u vocab-xt -- )
  {: addr len vxt -- :}
  addr len (IN-FORTH?) IF
    ." FAIL: " addr len TYPE ."  still in FORTH" CR
  ELSE
    ." ok: " addr len TYPE ."  not in FORTH" CR
  THEN
  addr len vxt (VWID) (IN-WL?) IF
    ." ok: " addr len TYPE ."  in target" CR
  ELSE
    ." FAIL: " addr len TYPE ."  missing from target" CR
  THEN ;

S" (SEE-STEP)"       ['] SYSVOC   (CHECK-TO)
S" (SHOW-VOCAB)"     ['] SYSVOC   (CHECK-TO)
S" (SUBST-FIND)"     ['] SYSVOC   (CHECK-TO)
S" (XQ-SZ)"          ['] SYSVOC   (CHECK-TO)
\ (FILE-OP-CALL) → EMITTER (FLAG_EMM)
S" FORTH>VOC"        ['] SYSVOC   (CHECK-TO)
S" (SZ-CLICK)"       ['] EDITOR   (CHECK-TO)
S" (FACILITY-SIZE)"  ['] EDITOR   (CHECK-TO)
S" (APP-BLIT)"       ['] GRAPHICS (CHECK-TO)
S" (APP-OPEN)"       ['] GRAPHICS (CHECK-TO)

S" (DOES>)"          ['] SYSVOC (CHECK-TO)
S" (F-OP)"           ['] SYSVOC (CHECK-TO)
S" (DO)"             ['] SYSVOC (CHECK-TO)
S" (?DO)"            ['] SYSVOC (CHECK-TO)
S" (LOOP)"           ['] SYSVOC (CHECK-TO)
S" (+LOOP)"          ['] SYSVOC (CHECK-TO)
S" (COMP,)"          ['] SYSVOC (CHECK-TO)
S" (BLOCK-BUF)"      ['] SYSVOC (CHECK-TO)
S" (BLOCK-NR)"       ['] SYSVOC (CHECK-TO)
S" (BLOCK-UPD)"      ['] SYSVOC (CHECK-TO)
S" (CATCH-OK)"       ['] SYSVOC (CHECK-TO)
\ (LOCAL-FRAME-EXIT) (.) (U.) → EMITTER (FLAG_EMM); see vocemit-cold.fth
S" DBG-SHOW-XT"      ['] SYSVOC (CHECK-TO)
S" DBG-HL-XT"        ['] SYSVOC (CHECK-TO)
S" DBG-INLINE"       ['] SYSVOC (CHECK-TO)
S" TDBG-ARM-KEYS"    ['] SYSVOC (CHECK-TO)
S" TDBG-DISARM-KEYS" ['] SYSVOC (CHECK-TO)
S\" (C\")"           ['] SYSVOC (CHECK-TO)
S" (LOAD-ENTER)"     ['] SYSVOC (CHECK-TO)
S" (LOAD-RUN)"       ['] SYSVOC (CHECK-TO)
S" (LOCAL!)"         ['] SYSVOC (CHECK-TO)
S" (LOCAL@)"         ['] SYSVOC (CHECK-TO)
S" -TRAILING-GARBAGE" ['] SYSVOC (CHECK-TO)

: (STAY)  ( c-addr u -- )
  {: addr len -- :}
  addr len (IN-FORTH?) IF
    ." ok: " addr len TYPE ."  still in FORTH" CR
  ELSE
    ." FAIL: " addr len TYPE ."  missing from FORTH" CR
  THEN ;

S" SEE" (STAY)
S" SUBSTITUTE" (STAY)
S" DOCOL-ADDR" (STAY)
S" (" (STAY)
S" LOCAL-INIT" (STAY)

CR ." SEE DUP:" CR  SEE DUP
CR ." depth=" DEPTH . CR
CR ." --- vocsys-cold done ---" CR
