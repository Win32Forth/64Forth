\ app-output.fth — Char-graphics window for 64Forth (not the console)
\
\ Forth owns the cell buffer. Thin host CODE words:
\   (APP-OPEN) ( cols rows -- ior )
\   (APP-CLOSE) ( -- )
\   (APP-BLIT)  ( c-addr u -- )
\   (APP-KEY?)  ( -- flag )
\   (APP-KEY)   ( -- c )
\   (APP-NAME)  ( c-addr u -- )
\   (APP-TONE)  ( freq dur -- )   \ freq=Hz, dur=tenths of a second (F-PC TONE)
\   (APP-PUMP)  ( -- )          \ yield for AppKit while spinning
\
\ Usage:
\   S" AppOutput/app-output.fth" FROMLIB INCLUDED
\   ALSO GRAPHICS
\   S" MyApp" APP-NAME  WINDOW
\   CLS  0 0 AT ." Hello " 42 .
\   5 TENTHS  KEY DROP  WINDOW-OFF
\   PREVIOUS
\
\ Classic TCOM names live in GRAPHICS so they do not clash with
\ Facility AT-XY / console CLS / KEY / . / ."
\
\ Public domain.

FORTH DEFINITIONS
DECIMAL

VOCABULARY GRAPHICS
GRAPHICS DEFINITIONS

80 CONSTANT G-COLS
25 CONSTANT G-ROWS

CREATE G-BUF  G-COLS G-ROWS * ALLOT
VARIABLE G-CX
VARIABLE G-CY
0 VALUE G-OPEN?
VARIABLE G-T0-MS                     \ TIME-RESET baseline (MS@)

: REFRESH  ( -- )
  G-OPEN? IF  G-BUF G-COLS G-ROWS * (APP-BLIT)  THEN
  ;

: APP-NAME  ( c-addr u -- )
  (APP-NAME)
  ;

: WINDOW  ( -- )
  G-OPEN? IF EXIT THEN
  G-COLS G-ROWS (APP-OPEN) 0= IF
    -1 TO G-OPEN?
    G-BUF G-COLS G-ROWS * BL FILL
    0 G-CX !  0 G-CY !
    REFRESH
  THEN
  ;

: WINDOW-OFF  ( -- )
  G-OPEN? IF  (APP-CLOSE)  0 TO G-OPEN?  THEN
  ;

: CLS  ( -- )
  WINDOW
  G-BUF G-COLS G-ROWS * BL FILL
  0 G-CX !  0 G-CY !
  REFRESH
  ;

: AT  ( x y -- )
  WINDOW
  G-CY !  G-CX !
  ;

: EMIT  ( c -- )
  WINDOW
  DUP 10 = OVER 13 = OR IF
    DROP  0 G-CX !  G-CY @ 1+ G-ROWS 1- MIN G-CY !
  ELSE
    G-CX @ G-COLS G-CY @ * + G-BUF + C!
    G-CX @ 1+ DUP G-COLS >= IF
      DROP 0 G-CX !  G-CY @ 1+ G-ROWS 1- MIN G-CY !
    ELSE
      G-CX !
    THEN
  THEN
  REFRESH                           \ soft/coalesced blit: next pass
  ;

: TYPE  ( c-addr u -- )
  0 ?DO  DUP I + C@ EMIT  LOOP DROP
  ;

: SPACE  ( -- )  BL EMIT ;
: CR     ( -- )  10 EMIT ;

\ Number / string output must hit the grid, not the console.
: .  ( n -- )
  WINDOW
  BASE @ >R DECIMAL
  DUP ABS 0 <# #S ROT SIGN #> TYPE SPACE
  R> BASE !
  ;

: ."  ( -- )  \ IMMEDIATE — compile/interpret to GRAPHICS TYPE
  [CHAR] " PARSE
  STATE @ IF  POSTPONE SLITERAL  POSTPONE TYPE  ELSE  TYPE  THEN
; IMMEDIATE

: GET-CHAR  ( -- c )
  WINDOW
  G-CX @ G-COLS G-CY @ * + G-BUF + C@
  ;

: KEY?  ( -- flag )
  WINDOW  (APP-KEY?)                \ yields ~1ms when empty
  ;

: KEY  ( -- c )
  WINDOW
  BEGIN  (APP-KEY) DUP 0<  WHILE  DROP  (APP-PUMP)  REPEAT
  ;

\ Timers — Forth-first via MS@; pump/yield so the main AppKit loop runs.
: TIME-RESET  ( -- )
  MS@ G-T0-MS !
  ;

: 10TH-ELAPSED  ( -- n )            \ tenths of a second since TIME-RESET
  (APP-PUMP)
  MS@ G-T0-MS @ - 100 /             \ ms / 100 = tenths
  ;

: TENTHS  ( n -- )                  \ wait at least n tenths
  TIME-RESET
  BEGIN DUP 10TH-ELAPSED > WHILE
    (APP-PUMP)
  REPEAT DROP
  ;

\ TONE — F-PC / TCOM stack: freq in Hz, dur in tenths of a second.
\ Stub today: one system beep (freq/dur ignored until real sound).
: TONE  ( freq dur -- )             \ freq=Hz, dur=tenths of a second
  (APP-TONE)
  ;

\ Smoke: title, draw, ., timer, tone, key, close
: GRAPHICS-SMOKE  ( -- )
  S" 64Forth GRAPHICS" APP-NAME
  WINDOW
  CLS
  2 1 AT ." 64Forth GRAPHICS"
  2 3 AT ." n= " 42 .
  2 5 AT ." beep + 3 tenths…"
  440 1 TONE
  3 TENTHS
  2 7 AT ." Press any key in the graphics window…"
  KEY DROP
  WINDOW-OFF
  ;

FORTH DEFINITIONS

S" AppOutput loaded — ALSO GRAPHICS  GRAPHICS-SMOKE" TYPE CR

