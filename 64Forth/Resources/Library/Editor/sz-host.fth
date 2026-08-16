\ sz-host.fth — SZ-EDITOR host / compatibility shims (64Forth)
\
\ Phase 1: utilities that isolate platform differences from the editor core.
\ Line-scan words (SZ-HOST-NEXT-EOL …) live in sz-buffer.fth after SZ-TEND.
\ Open-panel / session words are stubs + optional host flags (KernelBridge).
\
\ Depends on: Core / Core Ext / File-Access / Facility.

DECIMAL

\ -----------------------------------------------------------------------------
\ Counted-string helpers
\ -----------------------------------------------------------------------------

: SZ-PLACE  ( c-addr1 u c-addr2 -- )
   >R  255 MIN  DUP R@ C!  R> CHAR+ SWAP MOVE ;

: SZ-COUNT  ( c-addr -- c-addr' u )
   COUNT ;

\ -----------------------------------------------------------------------------
\ Screen (mono Facility)
\ -----------------------------------------------------------------------------

: SZ-PAGE       ( -- )  PAGE ;
: SZ-AT-XY      ( col row -- )  AT-XY ;
: SZ-TYPE       ( c-addr u -- )  TYPE ;
: SZ-EMIT-CR    ( -- )  CR ;
: SZ-SPACE      ( -- )  SPACE ;
: SZ-SPACES     ( n -- )  SPACES ;

: SZ-U>=  ( u1 u2 -- flag )  U< 0= ;
: SZ-U<=  ( u1 u2 -- flag )  SWAP U< 0= ;

: SZ->TEXT-COLOR   ( -- )  ;
: SZ->STAT-COLOR   ( -- )  ;
: SZ->END-COLOR    ( -- )  ;
: SZ->ERR-COLOR    ( -- )  ;
: SZ-COLOR-INIT    ( -- )  ;
: SZ-INIT-CURSOR   ( -- )  ;

\ TERMINAL-REFRESH / FACILITY-OFF / PAGE / AT-XY / CLS are kernel CODE (host).
\   PAGE           clear facility cell grid (SZ-EDITOR paint). Bare PAGE from the
\                  idle console is recovered by the host (does not lock the REPL).
\   FACILITY-OFF   leave facility mode; restore console (editor exit / ⌘W path).
\   CLS            clear the *host* console transcript + ok prompt (menu CLS).
\                  Not editor exit — do not redefine as FACILITY-OFF.

\ -----------------------------------------------------------------------------
\ Keyboard — map Facility Ext EKEY events to classic F-PC codes used by sz-edit
\ -----------------------------------------------------------------------------

: SZ-KEY?       ( -- flag )  KEY? ;

\ F-PC style codes expected by SZ-HANDLE-KEY (sz-edit.fth)
\  2 left  6 right  14 down  16 up  1 home-line  5 end-line
\  23 pgup  24 pgdn  28 home-file  29 end-file  127 del
: SZ-MAP-FKEY  ( k-id -- c | 0 )
   DUP K-LEFT   = IF  DROP  2 EXIT  THEN
   DUP K-RIGHT  = IF  DROP  6 EXIT  THEN
   DUP K-DOWN   = IF  DROP 14 EXIT  THEN
   DUP K-UP     = IF  DROP 16 EXIT  THEN
   DUP K-HOME   = IF  DROP  1 EXIT  THEN
   DUP K-END    = IF  DROP  5 EXIT  THEN
   DUP K-PRIOR  = IF  DROP 23 EXIT  THEN
   DUP K-NEXT   = IF  DROP 24 EXIT  THEN
   DUP K-DELETE = IF  DROP 127 EXIT  THEN
   DROP 0 ;

: SZ-KEY  ( -- c )
   EKEY
   \ Tagged function-key event (2<<24)|K-*
   DUP $FF000000 AND $02000000 = IF
      $FFFFFF AND SZ-MAP-FKEY
      DUP IF  EXIT  THEN
      DROP 0 EXIT                   \ unknown fkey → ignore as NUL
   THEN
   DUP $FF000000 AND $01000000 = IF
      $1FFFFF AND
   THEN
   255 AND
   \ normalize CR to LF for Enter
   DUP 13 = IF  DROP 10  THEN
   \ Host may already deliver F-PC motion codes 1..29 directly (no tag)
;

\ -----------------------------------------------------------------------------
\ Memory
\ -----------------------------------------------------------------------------

: SZ-ALLOC      ( u -- a-addr ior )  ALLOCATE ;
: SZ-FREE       ( a-addr -- ior )    FREE ;
: SZ-RESIZE     ( a-addr u -- a-addr ior )  RESIZE ;

\ -----------------------------------------------------------------------------
\ File I/O
\ -----------------------------------------------------------------------------

: SZ-R/O        ( -- fam )  R/O ;
: SZ-W/O        ( -- fam )  W/O ;
: SZ-R/W        ( -- fam )  R/W ;
: SZ-OPEN-FILE    OPEN-FILE ;
: SZ-CREATE-FILE  CREATE-FILE ;
: SZ-CLOSE-FILE   CLOSE-FILE ;
: SZ-READ-FILE    READ-FILE ;
: SZ-WRITE-FILE   WRITE-FILE ;
: SZ-FILE-SIZE    FILE-SIZE ;

\ -----------------------------------------------------------------------------
\ Edit window geometry (host settings in TZForth; local defaults here)
\ -----------------------------------------------------------------------------

VARIABLE SZ-WIN-W
VARIABLE SZ-WIN-H
80 SZ-WIN-W !
20 SZ-WIN-H !

: SET-EDIT-WINDOW  ( width height -- )
   SZ-WIN-H !  SZ-WIN-W !
;

: EDIT-WINDOW  ( -- width height )
   SZ-WIN-W @  SZ-WIN-H @ ;

\ -----------------------------------------------------------------------------
\ Session / open panel (host-assisted; works without panel for named paths)
\ -----------------------------------------------------------------------------

VARIABLE SZ-EDITOR-ACTIVE
CREATE SZ-PENDING-PATH  512 ALLOT
VARIABLE SZ-PENDING-LEN
0 SZ-PENDING-LEN !

: SZ-HOST-EDITOR-ACTIVE!  ( flag -- )
   SZ-EDITOR-ACTIVE ! ;

\ Bare SZEDIT / no path: ask host to show an open panel after this evaluate
\ (KernelBridge takes (SZ-OPEN-REQ) flag; FROMLIB starts the panel at Library).
: SZ-HOST-REQUEST-OPEN  ( -- )
   (SZ-OPEN-REQ)
;

\ ( -- c-addr u )  path staged by host after open panel; empty if none.
\ Prefers host-staged Cmd-O path via (SZ-PATH@) (works while KEY is waiting
\ without nested EVALUATE); else SZ-HOST-SET-PATH buffer from evaluate.
: SZ-HOST-TAKE-PATH  ( -- c-addr u )
   SZ-PENDING-PATH 511 (SZ-PATH@) DUP IF
      SZ-PENDING-PATH SWAP EXIT
   THEN DROP
   SZ-PENDING-PATH SZ-PENDING-LEN @
   0 SZ-PENDING-LEN !
;

\ Host helper: store path bytes for TAKE-PATH
: SZ-HOST-SET-PATH  ( c-addr u -- )
   511 MIN DUP SZ-PENDING-LEN !
   SZ-PENDING-PATH SWAP MOVE ;

\ -----------------------------------------------------------------------------
\ Self-check
\ -----------------------------------------------------------------------------

: SZ-HOST-SMOKE  ( -- )
   SZ-COLOR-INIT  SZ-INIT-CURSOR
   ." sz-host: OK - PAGE AT-XY KEY File-Access shims ready" CR
;
