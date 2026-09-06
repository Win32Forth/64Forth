\ hyper-sysvoc.fth — Hyper hooks moved to SYSVOC
\ Public domain.

CR ." --- hyper → SYSVOC ---" CR

FROMLIB FLOAD Editor/SZ-EDITOR.fth
FROMLIB FLOAD Hyper/hyper.fth

: (IN-WL?)  ( c-addr u wid -- flag )
  SEARCH-WORDLIST DUP 0= IF EXIT THEN 2DROP TRUE ;

: (VWID)  ( vocab-xt -- wid )  2 CELLS + ;

: CHK-SYS  ( c-addr u -- )
  {: addr len -- :}
  addr len FORTH-WORDLIST (IN-WL?) IF
    ." FAIL in FORTH: " addr len TYPE CR EXIT
  THEN
  addr len ['] SYSVOC (VWID) (IN-WL?) IF
    ." ok SYSVOC: " addr len TYPE CR EXIT
  THEN
  ." FAIL missing: " addr len TYPE CR ;

: CHK-FORTH  ( c-addr u -- )
  {: addr len -- :}
  addr len FORTH-WORDLIST (IN-WL?) IF
    ." ok FORTH: " addr len TYPE CR EXIT
  THEN
  ." FAIL not FORTH: " addr len TYPE CR ;

S" HYPER-NEXT"         CHK-SYS
S" HYPER-PREV"         CHK-SYS
S" HYPER-FLASH-HERE"   CHK-SYS
S" HYPER-VIEW-NAME"    CHK-SYS
S" HYPER-VIEW-CU"      CHK-SYS
S" (VIEW)"             CHK-SYS
S" DBG-UNTITLED"       CHK-SYS
S" DBG-SYNC-VIEW"      CHK-SYS
S" DBG-HIGHLIGHT-NAME" CHK-SYS

S" VIEW"   CHK-FORTH
S" LOCATE" CHK-FORTH
S" SEE"    CHK-FORTH
S" DBG"    CHK-FORTH

ALSO SYSVOC
: (CHK-XTS)  ( -- )
  DBG-SHOW-XT @ IF ." ok DBG-SHOW-XT set" CR ELSE ." FAIL DBG-SHOW-XT unset" CR THEN
  DBG-HL-XT @ IF ." ok DBG-HL-XT set" CR ELSE ." FAIL DBG-HL-XT unset" CR THEN
  S" HYPER-NEXT" PAD PLACE
  PAD FIND IF DROP ." ok FIND HYPER-NEXT via SYSVOC" CR
  ELSE DROP ." FAIL FIND HYPER-NEXT" CR THEN ;
(CHK-XTS)
PREVIOUS

CR ." depth=" DEPTH . CR
CR ." --- hyper-sysvoc done ---" CR
