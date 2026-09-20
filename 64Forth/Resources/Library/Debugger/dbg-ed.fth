\ dbg-ed.fth — Debugger ↔ Editor deferred links + shared HL primitives
\
\ Loaded from debugger.fth before dbg-map.fth. No Editor/Hyper required
\ at load time; DBG-ED-INSTALL fills the links when SZ-* exist.
\
\ Shared basis (usable by Debugger + Hyper):
\   DBG-CMD / DBG-PLACE  — FIND scratch (replaces Hyper-only HYPER-CMD/PLACE)
\   DBG-HL-RUN           — highlight dispatch DEFER (maps or name-HL)

\ --- Shared FIND scratch ----------------------------------------------------

CREATE DBG-CMD  512 ALLOT

: DBG-PLACE  ( c-addr u dest -- )  \ counted string at dest (≤255)
  >R  255 MIN  DUP R@ C!  R@ CHAR+ SWAP MOVE  R> DROP ;

\ --- Highlight dispatch (maps + Hyper name-HL) -----------------------------

: DBG-HL-RUN-NOP  ( c-addr u -- )  2DROP ;

DEFER DBG-HL-RUN
' DBG-HL-RUN-NOP IS DBG-HL-RUN

\ --- Editor buffer / token links -------------------------------------------

: DBG-ED-0  ( -- addr )  0 ;

DEFER DBG-ED-TBUF          \ ( -- addr )  buffer base; 0 if unbound
DEFER DBG-ED-TEND          \ ( -- addr )  one past last
DEFER DBG-ED-CUR           \ ( -- addr )  VARIABLE addr (use @)
DEFER DBG-ED-TOKEN         \ ( -- addr )  counted token buffer

' DBG-ED-0 IS DBG-ED-TBUF
' DBG-ED-0 IS DBG-ED-TEND
' DBG-ED-0 IS DBG-ED-CUR

CREATE DBG-ED-TOKEN-BUF  64 ALLOT
: DBG-ED-TOKEN-DFLT  ( -- addr )  DBG-ED-TOKEN-BUF ;
' DBG-ED-TOKEN-DFLT IS DBG-ED-TOKEN

: DBG-ED-SKIP-NOP  ( a end -- a )  DROP ;
: DBG-ED-HIT-NOP   ( a -- flag )   DROP FALSE ;
: DBG-ED-2DROP     ( c-addr u -- ) 2DROP ;
: DBG-ED-NOP       ( -- )  ;

DEFER DBG-ED-SKIP-COMMENT  \ ( a end -- a' )
DEFER DBG-ED-WORD-HIT?     \ ( a -- flag )
DEFER DBG-ED-HL-SPAN       \ ( addr u -- )
DEFER DBG-ED-HL-NAME       \ ( c-addr u -- )
DEFER DBG-ED-HL-HIST-CLR   \ ( -- )

' DBG-ED-SKIP-NOP IS DBG-ED-SKIP-COMMENT
' DBG-ED-HIT-NOP  IS DBG-ED-WORD-HIT?
' DBG-ED-2DROP    IS DBG-ED-HL-SPAN
' DBG-ED-2DROP    IS DBG-ED-HL-NAME
' DBG-ED-NOP      IS DBG-ED-HL-HIST-CLR

\ --- FIND helpers (Hyper-style: FIND IF … ELSE DROP) ----------------------

: DBG-ED-FIND  ( c-addr u -- xt true | false )
  \ FIND: xt 1|-1 | c-addr 0. DUP IF leaves ( xt flag ); DROP the flag — not NIP.
  DBG-CMD DBG-PLACE
  DBG-CMD FIND DUP IF  DROP TRUE  ELSE  2DROP FALSE  THEN ;

\ ( defer-xt c-addr u -- flag )  bind defer to found xt; drop defer on miss
: DBG-ED-SET-DEFER  ( defer-xt c-addr u -- flag )
  DBG-ED-FIND IF  SWAP DEFER!  TRUE  ELSE  DROP FALSE  THEN ;

\ Runtime ALSO EDITOR — do not bake [DEFINED] EDITOR at dbg-ed compile time.
: DBG-ED-ALSO-EDITOR  ( -- )
  S" EDITOR" DBG-CMD DBG-PLACE
  DBG-CMD FIND IF  ALSO EXECUTE  ELSE  DROP  THEN ;

\ --- Install ---------------------------------------------------------------
\ No {: :} locals — ONLY/ALSO and DEFER! inside locals have been flaky here.

VARIABLE DBG-ED-NAME-XT
VARIABLE DBG-ED-MAP-XT

: DBG-ED-INSTALL  ( -- flag )  \ true if a highlight path is armed
  0 DBG-ED-NAME-XT !
  0 DBG-ED-MAP-XT !
  ONLY FORTH ALSO DEBUGGER
  DBG-ED-ALSO-EDITOR

  ['] DBG-ED-TBUF          S" SZ-TBUF"           DBG-ED-SET-DEFER DROP
  ['] DBG-ED-TEND          S" SZ-TEND"           DBG-ED-SET-DEFER DROP
  ['] DBG-ED-CUR           S" SZ-CUR"            DBG-ED-SET-DEFER DROP
  ['] DBG-ED-TOKEN         S" SZ-TOKEN"          DBG-ED-SET-DEFER DROP
  ['] DBG-ED-SKIP-COMMENT  S" SZ-SKIP-COMMENT"   DBG-ED-SET-DEFER DROP
  ['] DBG-ED-WORD-HIT?     S" SZ-WORD-HIT?"      DBG-ED-SET-DEFER DROP
  ['] DBG-ED-HL-SPAN       S" SZ-HIGHLIGHT-SPAN" DBG-ED-SET-DEFER DROP
  ['] DBG-ED-HL-HIST-CLR   S" SZ-HL-HIST-CLEAR"  DBG-ED-SET-DEFER DROP
  S" SZ-HIGHLIGHT-NAME" DBG-ED-FIND IF
     DUP DBG-ED-NAME-XT !
     ['] DBG-ED-HL-NAME DEFER!
  ELSE  DROP  THEN

  ONLY FORTH ALSO DEBUGGER
  S" DBG-MAP-HL" DBG-ED-FIND IF  DBG-ED-MAP-XT !  ELSE  DROP  THEN

  DBG-ED-MAP-XT @ IF
     DBG-ED-MAP-XT @ ['] DBG-HL-RUN DEFER!
     TRUE
  ELSE
     DBG-ED-NAME-XT @ IF
        DBG-ED-NAME-XT @ ['] DBG-HL-RUN DEFER!
        TRUE
     ELSE
        FALSE
     THEN
  THEN
  >R
  ONLY FORTH ALSO DEBUGGER
  R>
;

: DBG-ED-HL-XT  ( -- xt )  ACTION-OF DBG-HL-RUN ;
