\ sz-host.fth — SZ-EDITOR host / compatibility shims (TZForth)
\
\ Phase 1: utilities that isolate platform differences from the editor core.
\ F-PC/TCOM/DOS-specific words are stubbed or reimplemented with ANS/TZForth.
\
\ Load after ANEW (optional). Safe to reload only as part of ANEW SZ-EDITOR chain.
\
\ Depends on: standard TZForth Core / Core Ext / File-Access / Facility.

DECIMAL

\ -----------------------------------------------------------------------------
\ Counted-string helpers (classic Forth; not all systems ship PLACE)
\ -----------------------------------------------------------------------------

\ ( c-addr1 u c-addr2 -- )  store counted string at c-addr2 (u clipped to 255)
: SZ-PLACE  ( c-addr1 u c-addr2 -- )
   >R  255 MIN  DUP R@ C!  R> CHAR+ SWAP MOVE ;

\ ( c-addr -- c-addr u )  counted string to addr/len
: SZ-COUNT  ( c-addr -- c-addr' u )
   COUNT ;

\ -----------------------------------------------------------------------------
\ Screen (mono Facility; color is no-op for now)
\ -----------------------------------------------------------------------------

: SZ-PAGE       ( -- )  PAGE ;
: SZ-AT-XY      ( col row -- )  AT-XY ;

\ ( c-addr u -- ) type at current cursor
: SZ-TYPE       ( c-addr u -- )  TYPE ;

: SZ-EMIT-CR    ( -- )  CR ;
: SZ-SPACE      ( -- )  SPACE ;
: SZ-SPACES     ( n -- )  SPACES ;

\ Unsigned compares not always in the kernel vocabulary as U>= / U<=
: SZ-U>=  ( u1 u2 -- flag )  U< 0= ;
: SZ-U<=  ( u1 u2 -- flag )  SWAP U< 0= ;

\ Color attributes from the original editor — stubs (mono console)
: SZ->TEXT-COLOR   ( -- )  ;
: SZ->STAT-COLOR   ( -- )  ;
: SZ->END-COLOR    ( -- )  ;
: SZ->ERR-COLOR    ( -- )  ;
: SZ-COLOR-INIT    ( -- )  ;

\ Cursor init (F-PC BIOS) — no-op
: SZ-INIT-CURSOR   ( -- )  ;

\ -----------------------------------------------------------------------------
\ Keyboard (minimal for early phases)
\ -----------------------------------------------------------------------------

: SZ-KEY        ( -- char )  KEY ;
: SZ-KEY?       ( -- flag )  KEY? ;

\ -----------------------------------------------------------------------------
\ Memory notes
\   Editor text buffer lives on the ANS ALLOCATE heap (see sz-buffer.fth):
\   1 MB initial, RESIZE to grow. These are thin aliases.
\ -----------------------------------------------------------------------------

: SZ-ALLOC      ( u -- a-addr ior )  ALLOCATE ;
: SZ-FREE       ( a-addr -- ior )    FREE ;
: SZ-RESIZE     ( a-addr u -- a-addr ior )  RESIZE ;

\ -----------------------------------------------------------------------------
\ File I/O thin wrappers (ANS File-Access)
\ -----------------------------------------------------------------------------

: SZ-R/O        ( -- fam )  R/O ;
: SZ-W/O        ( -- fam )  W/O ;
: SZ-R/W        ( -- fam )  R/W ;

\ ( c-addr u fam -- fileid ior )
: SZ-OPEN-FILE    OPEN-FILE ;
: SZ-CREATE-FILE  CREATE-FILE ;
: SZ-CLOSE-FILE   CLOSE-FILE ;

\ ( c-addr u fileid -- u2 ior )
: SZ-READ-FILE    READ-FILE ;

\ ( c-addr u fileid -- ior )
: SZ-WRITE-FILE   WRITE-FILE ;

\ ( fileid -- ud ior )  FILE-SIZE
: SZ-FILE-SIZE    FILE-SIZE ;

\ -----------------------------------------------------------------------------
\ Self-check (Phase 1 smoke)
\ -----------------------------------------------------------------------------

: SZ-HOST-SMOKE  ( -- )
   SZ-COLOR-INIT  SZ-INIT-CURSOR
   .( sz-host: OK - PAGE AT-XY KEY File-Access shims ready) CR
;
