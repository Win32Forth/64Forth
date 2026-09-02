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
\   (APP-PUMP)  ( -- )            \ yield for AppKit while spinning
\
\ Dual-load (tetra etc.):
\   ONLY FORTH ALSO GRAPHICS
\   S" /path/to/tetra/tetra.fth" INCLUDED
\   MAIN
\
\ Or smoke:
\   ALSO GRAPHICS  GRAPHICS-SMOKE
\
\ Public domain.

FORTH DEFINITIONS
DECIMAL

\ --- Helpers needed by TCOM-class sources under ANS (if not already present) ---
[UNDEFINED] NOT [IF]
: NOT  ( x -- flag )  0= ;
[THEN]

[UNDEFINED] UPC [IF]
: UPC  ( c -- c' )
  DUP [CHAR] a >= OVER [CHAR] z <= AND IF  32 -  THEN
  ;
[THEN]

[UNDEFINED] ?EXIT [IF]
: ?EXIT  ( flag -- )  IF EXIT THEN ;
[THEN]

\ F-PC multi-line block comment: \\ … {  (opener is the word "\\")
[UNDEFINED] \\ [IF]
: \\  ( -- )  \ IMMEDIATE — skip input until '{'
  BEGIN
    >IN @ SOURCE NIP >= IF
      REFILL 0= IF  EXIT  THEN
    ELSE
      SOURCE DROP >IN @ + C@ [CHAR] { = IF
        1 >IN +!  EXIT
      THEN
      1 >IN +!
    THEN
  AGAIN
; IMMEDIATE
[THEN]

\ Dual-load line directives (classic F-PC DIRECTIVE / \FPC / \TCOM).
\ Interactive 64Forth: \ANS true, \TCOM false. TARGETARM64 flips these.
[UNDEFINED] DIRECTIVE [IF]
\ False directive skips to end of the *current line* only. SOURCE for a
\ file may be the whole file — do NOT set >IN to SOURCE length (that
\ would drop the rest of the file). Avoid ['] \ (line-comments this def).
: SKIP-REST  ( -- )
  BEGIN
    >IN @ SOURCE NIP >= IF EXIT THEN
    SOURCE DROP >IN @ + C@
    DUP 10 = OVER 13 = OR IF  DROP 1 >IN +! EXIT  THEN
    DROP 1 >IN +!
  AGAIN
  ;
: DIRECTIVE  ( flag "<spaces>name" -- )
  CREATE , IMMEDIATE
  DOES> @ 0= IF  SKIP-REST  THEN
  ;
[THEN]

[UNDEFINED] \ANS [IF]
TRUE  DIRECTIVE \ANS          \ ANS Forth / 64Forth host load
FALSE DIRECTIVE \TCOM         \ TCOM compile path
[THEN]

VOCABULARY GRAPHICS
GRAPHICS DEFINITIONS

80 CONSTANT G-COLS
25 CONSTANT G-ROWS

CREATE G-BUF  G-COLS G-ROWS * ALLOT
VARIABLE G-CX
VARIABLE G-CY
0 VALUE G-OPEN?
0 VALUE G-DIRTY?                    \ coalesced blit — set by EMIT, cleared by REFRESH
VARIABLE G-T0-MS                     \ TIME-RESET baseline (MS@)

: REFRESH  ( -- )
  G-OPEN? IF
    G-BUF G-COLS G-ROWS * (APP-BLIT)
  THEN
  0 TO G-DIRTY?
  ;

: DIRTY  ( -- )  -1 TO G-DIRTY? ;

\ Flush pending EMIT/TYPE pixels before input/time waits.
: ?REFRESH  ( -- )
  G-DIRTY? IF  REFRESH  THEN
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
  G-OPEN? IF  (APP-CLOSE)  0 TO G-OPEN?  0 TO G-DIRTY?  THEN
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

\ Buffer only — no host blit per character (coalesced via DIRTY + ?REFRESH).
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
  DIRTY
  ;

: TYPE  ( c-addr u -- )
  0 ?DO  DUP I + C@ EMIT  LOOP DROP
  ?REFRESH                          \ one blit after the string
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
  WINDOW  ?REFRESH  (APP-KEY?)      \ yields ~1ms when empty
  ;

: KEY  ( -- c )
  WINDOW  ?REFRESH
  BEGIN  (APP-KEY) DUP 0<  WHILE  DROP  (APP-PUMP)  REPEAT
  ;

\ Timers — Forth-first via MS@; pump/yield so the main AppKit loop runs.
: TIME-RESET  ( -- )
  MS@ G-T0-MS !
  ;

: 10TH-ELAPSED  ( -- n )            \ tenths of a second since TIME-RESET
  ?REFRESH
  (APP-PUMP)
  MS@ G-T0-MS @ - 100 /             \ ms / 100 = tenths
  ;

: TENTHS  ( n -- )                  \ wait at least n tenths
  ?REFRESH
  TIME-RESET
  BEGIN DUP 10TH-ELAPSED > WHILE
    (APP-PUMP)
  REPEAT DROP
  ;

\ TONE — F-PC / TCOM: freq in Hz, dur in tenths of a second (host plays sine).
: TONE  ( freq dur -- )             \ freq=Hz, dur=tenths of a second
  ?REFRESH
  (APP-TONE)
  ;

\ Smoke: title, draw, ., timer, tone, key, close
: GRAPHICS-SMOKE  ( -- )
  S" 64Forth GRAPHICS" APP-NAME
  WINDOW
  CLS
  2 1 AT ." 64Forth GRAPHICS"
  2 3 AT ." n= " 42 .
  2 5 AT ." 440 Hz for 3 tenths…"
  440 3 TONE
  2 7 AT ." Press any key in the graphics window…"
  KEY DROP
  WINDOW-OFF
  ;

FORTH DEFINITIONS
