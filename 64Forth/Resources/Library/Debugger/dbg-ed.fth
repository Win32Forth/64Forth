\ dbg-ed.fth — Debugger ↔ Editor deferred links + shared HL primitives
\
\ Loaded from debugger.fth before dbg-map.fth. No Editor/Hyper required
\ at load time; portable SKIP/HIT work against DBG-ED-TBUF (file slurp or
\ SZ-EDITOR). DBG-ED-INSTALL still prefers SZ-* when present.
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
\ Default bindings read VARIABLEs so dbg-map can point them at a slurped file.

VARIABLE DBG-ED-TBUF-VAL   \ buffer base (0 = unbound)
VARIABLE DBG-ED-TEND-VAL   \ one past last
VARIABLE DBG-ED-CUR-CELL   \ search start (file-backed maps set to TBUF)

: DBG-ED-0  ( -- addr )  0 ;

: DBG-ED-TBUF-DFLT  ( -- addr )  DBG-ED-TBUF-VAL @ ;
: DBG-ED-TEND-DFLT  ( -- addr )  DBG-ED-TEND-VAL @ ;
: DBG-ED-CUR-DFLT   ( -- addr )  DBG-ED-CUR-CELL ;  \ VARIABLE addr for @

DEFER DBG-ED-TBUF          \ ( -- addr )  buffer base; 0 if unbound
DEFER DBG-ED-TEND          \ ( -- addr )  one past last
DEFER DBG-ED-CUR           \ ( -- addr )  VARIABLE addr (use @)
DEFER DBG-ED-TOKEN         \ ( -- addr )  counted token buffer

' DBG-ED-TBUF-DFLT IS DBG-ED-TBUF
' DBG-ED-TEND-DFLT IS DBG-ED-TEND
' DBG-ED-CUR-DFLT  IS DBG-ED-CUR

CREATE DBG-ED-TOKEN-BUF  64 ALLOT
: DBG-ED-TOKEN-DFLT  ( -- addr )  DBG-ED-TOKEN-BUF ;
' DBG-ED-TOKEN-DFLT IS DBG-ED-TOKEN

: DBG-ED-SET-BUF  ( tbuf tend -- )  \ bind portable buffer (tend = one past)
  DBG-ED-TEND-VAL !
  DUP DBG-ED-TBUF-VAL !
  DBG-ED-CUR-CELL !
;

: DBG-ED-CLEAR-BUF  ( -- )
  0 DBG-ED-TBUF-VAL !
  0 DBG-ED-TEND-VAL !
  0 DBG-ED-CUR-CELL !
;

\ --- Portable comment skip + whole-word hit (no SZ-EDITOR) -----------------
\ Only whitespace-delimited "\" and "(" are comments — never [CHAR] \ or
\ names like (SLURP). No {: :} locals (SKIP uses >R; EXIT-in-locals hangs).

: DBG-ED-BLANK?  ( c -- flag )
  DUP BL = IF  DROP TRUE EXIT  THEN
  DUP 9 = IF  DROP TRUE EXIT  THEN
  DUP 10 = IF  DROP TRUE EXIT  THEN
  DUP 13 = IF  DROP TRUE EXIT  THEN
  DROP FALSE ;

: DBG-ED-CH=  ( c1 c2 -- flag )
  DUP [CHAR] a [CHAR] z 1+ WITHIN IF  32 -  THEN
  SWAP
  DUP [CHAR] a [CHAR] z 1+ WITHIN IF  32 -  THEN
  = ;

\ True if [a,a+1) is a 1-char whole word equal to c (whitespace or edges).
: DBG-ED-1CHAR-WORD?  ( a end c -- flag )
  >R                                \ R: c
  2DUP SWAP - 1 < IF  2DROP R> DROP FALSE EXIT  THEN
  OVER C@ R> <> IF  2DROP FALSE EXIT  THEN
  OVER DBG-ED-TBUF = IF
     TRUE
  ELSE
     OVER 1- C@ DBG-ED-BLANK?
  THEN
  0= IF  2DROP FALSE EXIT  THEN
  OVER 1+ OVER U< IF
     OVER 1+ C@ DBG-ED-BLANK?
  ELSE
     TRUE
  THEN
  NIP NIP ;

\ ( a end -- a' ) skip \…EOL or ( … ); unchanged if not a comment word.
: DBG-ED-SKIP-COMMENT-PORT  ( a end -- a' )
  2DUP [CHAR] \ DBG-ED-1CHAR-WORD? IF
     DROP 1+                        \ past "\"
     BEGIN
        DUP DBG-ED-TEND U< IF
           DUP C@ DUP 10 = SWAP 13 = OR 0=
        ELSE  FALSE  THEN
     WHILE  1+  REPEAT
     DUP DBG-ED-TEND U< IF  1+  THEN   \ consume EOL if present
     EXIT
  THEN
  2DUP [CHAR] ( DBG-ED-1CHAR-WORD? IF
     DROP 1+                        \ past "("
     BEGIN
        DUP DBG-ED-TEND U< IF
           DUP C@ [CHAR] ) <>
        ELSE  FALSE  THEN
     WHILE  1+  REPEAT
     DUP DBG-ED-TEND U< IF  1+  THEN   \ consume ")"
     EXIT
  THEN
  DROP ;                            \ leave a

: DBG-ED-MATCH-AT  ( ha -- flag )
  DBG-ED-TOKEN C@ 0= IF  DROP FALSE EXIT  THEN
  >R
  0
  BEGIN  DUP DBG-ED-TOKEN C@ < WHILE
     DUP DBG-ED-TOKEN 1+ + C@
     OVER R@ + C@
     DBG-ED-CH= 0= IF  DROP R> DROP FALSE EXIT  THEN
     1+
  REPEAT
  DROP R> DROP TRUE ;

: DBG-ED-BOUND-OK  ( addr u -- flag )
  OVER DBG-ED-TBUF = IF  TRUE
  ELSE  OVER 1- C@ DBG-ED-BLANK?  THEN
  0= IF  2DROP FALSE EXIT  THEN
  2DUP +                               \ addr u end
  DUP DBG-ED-TEND U< 0= IF  DROP 2DROP TRUE EXIT  THEN
  C@ DBG-ED-BLANK? NIP NIP ;

: DBG-ED-WORD-HIT-PORT  ( ha -- flag )
  DUP DBG-ED-MATCH-AT 0= IF  DROP FALSE EXIT  THEN
  DBG-ED-TOKEN C@ DBG-ED-BOUND-OK ;

: DBG-ED-2DROP     ( c-addr u -- ) 2DROP ;
: DBG-ED-NOP       ( -- )  ;

DEFER DBG-ED-SKIP-COMMENT  \ ( a end -- a' )
DEFER DBG-ED-WORD-HIT?     \ ( a -- flag )
DEFER DBG-ED-HL-SPAN       \ ( addr u -- )  buffer addr + len → host/editor
DEFER DBG-ED-HL-NAME       \ ( c-addr u -- )
DEFER DBG-ED-HL-HIST-CLR   \ ( -- )

' DBG-ED-SKIP-COMMENT-PORT IS DBG-ED-SKIP-COMMENT
' DBG-ED-WORD-HIT-PORT     IS DBG-ED-WORD-HIT?
' DBG-ED-2DROP             IS DBG-ED-HL-SPAN
' DBG-ED-2DROP             IS DBG-ED-HL-NAME
' DBG-ED-NOP               IS DBG-ED-HL-HIST-CLR

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

\ Cached kernel DBG-HOST-SPAN xt (filled by dbg-map DBG-HOST-SPAN-BIND).
\ Never ALSO/PREVIOUS/FIND on the pause hot path — search order sticks (Hyper).
VARIABLE DBG-ED-HOST-SPAN-XT

\ Publish file-relative span to 64Edit via DBG-HOST-SPAN (kernel CODE).
\ ( addr u -- ) addr is inside DBG-ED-TBUF; converts to off+len.
: DBG-ED-HL-SPAN-HOST  ( addr u -- )
  DUP 0= IF  2DROP EXIT  THEN
  DBG-ED-TBUF 0= IF  2DROP EXIT  THEN
  SWAP DBG-ED-TBUF - SWAP               \ off len
  DBG-ED-HOST-SPAN-XT @ DUP IF
     EXECUTE
  ELSE
     DROP 2DROP
  THEN ;

\ --- Install ---------------------------------------------------------------
\ No {: :} locals — ONLY/ALSO and DEFER! inside locals have been flaky here.

VARIABLE DBG-ED-NAME-XT
VARIABLE DBG-ED-MAP-XT

: DBG-ED-INSTALL  ( -- flag )  \ true if a highlight path is armed
  0 DBG-ED-NAME-XT !
  0 DBG-ED-MAP-XT !
  ONLY FORTH ALSO DEBUGGER
  DBG-ED-ALSO-EDITOR

  \ Prefer SZ-EDITOR buffer/helpers when present; else keep portable defaults.
  ['] DBG-ED-TBUF          S" SZ-TBUF"           DBG-ED-SET-DEFER DROP
  ['] DBG-ED-TEND          S" SZ-TEND"           DBG-ED-SET-DEFER DROP
  ['] DBG-ED-CUR           S" SZ-CUR"            DBG-ED-SET-DEFER DROP
  ['] DBG-ED-TOKEN         S" SZ-TOKEN"          DBG-ED-SET-DEFER DROP
  ['] DBG-ED-SKIP-COMMENT  S" SZ-SKIP-COMMENT"   DBG-ED-SET-DEFER DROP
  ['] DBG-ED-WORD-HIT?     S" SZ-WORD-HIT?"      DBG-ED-SET-DEFER DROP
  ['] DBG-ED-HL-HIST-CLR   S" SZ-HL-HIST-CLEAR"  DBG-ED-SET-DEFER DROP
  S" SZ-HIGHLIGHT-SPAN" DBG-ED-FIND IF
     ['] DBG-ED-HL-SPAN DEFER!
  ELSE
     DROP
     \ 64Edit path: publish off+len through host_debug_set_span.
     ['] DBG-ED-HL-SPAN-HOST ['] DBG-ED-HL-SPAN DEFER!
  THEN
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
