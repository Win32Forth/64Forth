\ DOODLECOLOR64.fth — COLOR8 mouse drawing demo for 64Forth GRAPHICS
\
\ Sibling of Sample/DOODLE64.fth (1-bit). Classic TCOM DOODLE color-bar
\ idea on 640×400 indexed pixels. Leaves DOODLE64 untouched.
\
\ Load (not Autoload):
\   FROMLIB FLOAD Sample/DOODLECOLOR64.fth
\   DOODLECOLOR
\
\ Controls
\   Left drag     draw with current COLOR (COLOR8 pen)
\   Right drag    thick stroke (Control-click on trackpad)
\   Middle        clear drawing area
\   Chrome        QUIT / CLEAR / 16-color bar / pen chip
\   Esc or QUIT   leave (returns to console; restores 1BIT)
\   H or F1       help overlay
\   0–9 / A–F     set pen to classic index (CBLACK…CWHITE)
\   C / M         clear canvas
\
\ Requires GRAPHICS mouse + COLOR8 (64Forth color checkpoint+).
\
\ Public domain.

ANEW DOODLECOLOR64_MODULE

\ Console credit must use FORTH CR/." — GRAPHICS CR reopens the window.
ONLY FORTH DEFINITIONS
DECIMAL

: DOODLECOLOR-CREDIT  ( -- )
  CR ." DOODLECOLOR64 is a public domain example by Tom Zimmer,"
  CR ." adapted for 64Forth GRAPHICS COLOR8 (640x400, mouse)." CR
  ;

ONLY FORTH ALSO GRAPHICS DEFINITIONS
DECIMAL

\ Chrome = top of window (high Y). Layout (char rows / pixels):
\   row 0  QUIT / CLEAR labels + pen readout
\   row 1  short help
\   then a full-width 16-color bar (click here to pick a pen)
\   pen chip sits to the right of the bar
64 CONSTANT DC-DRAWTOP       \ 4 char rows of chrome
2  CONSTANT DC-BAR-MARGIN    \ inset from left/right
\ VARIABLEs (not VALUEs): Emitter reach must see the xt in colon bodies.
VARIABLE DC-WASDOWN?  0 DC-WASDOWN? !
VARIABLE DC-PASS#     0 DC-PASS# !
VARIABLE DC-HELP?     0 DC-HELP? !
VARIABLE DC-DONE?     0 DC-DONE? !
VARIABLE DC-LAST-X
VARIABLE DC-LAST-Y
2VARIABLE DC-FROMTO

: DC-CHROME-Y0  ( -- y )  G-PY DC-DRAWTOP - ;

\ Color-bar band (bottom-left Y): below the two text rows, inside chrome.
: DC-BAR-Y0  ( -- y )  DC-CHROME-Y0 4 + ;          \ just above chrome floor
: DC-BAR-Y1  ( -- y )  G-PY G-CELLH 2 * - 4 - ;  \ below text rows 0–1

: DC-BAR0  ( -- x )  DC-BAR-MARGIN ;
: DC-CHIPW  ( -- n )
  G-PX DC-BAR-MARGIN 2 * -  40 -   \ leave ~40px for pen chip + gap
  16 /  1 MAX
  ;

: DC-PEN-X0  ( -- x )  DC-BAR0  DC-CHIPW 16 * +  8 + ;

: DC-IN-CHROME?  ( y -- flag )
  DC-CHROME-Y0 >=
  ;

: DC-IN-COLOR-BAR?  ( x y -- flag )
  DUP DC-BAR-Y0 < IF  2DROP FALSE EXIT  THEN
  DUP DC-BAR-Y1 > IF  2DROP FALSE EXIT  THEN
  DROP                            \ x
  DUP DC-BAR0 < IF  DROP FALSE EXIT  THEN
  DC-PEN-X0 4 - <
  ;

\ Top two character rows only (QUIT / CLEAR labels).
: DC-IN-LABELS?  ( y -- flag )
  G-PY G-CELLH 2 * - >=
  ;

: DC-CLIP-DRAW  ( x y -- x' y' )
  SWAP 1 MAX  G-PX 2 - MIN
  SWAP 0 MAX  DC-CHROME-Y0 2 - MIN
  ;

: DC-WAIT-MOUSE-UP  ( -- )
  BEGIN
    (APP-PUMP)  G-MOUSE
    >R 2DROP R>  0=
  UNTIL
  ;

VARIABLE DC-TX
VARIABLE DC-TY0
VARIABLE DC-TY1

\ Filled vertical strip of width DC-CHIPW.
: DC-FILL-STRIP  ( color x0 y0 y1 -- )
  DC-TY1 !  DC-TY0 !  DC-TX !
  COLOR @ >R  G-INK @ >R
  COLOR !  WHITE
  DC-CHIPW 0 DO
    DC-TX @ I +
    DC-TY0 @
    OVER
    DC-TY1 @
    LINE
  LOOP
  R> G-INK !  R> COLOR !
  ;

: DC-SHOW-COLORS  ( -- )
  16 0 DO
    I  DC-BAR0 I DC-CHIPW * +  DC-BAR-Y0 DC-BAR-Y1  DC-FILL-STRIP
  LOOP
  ;

: DC-SHOW-PEN  ( -- )
  COLOR @  DC-PEN-X0  DC-BAR-Y0 DC-BAR-Y1  DC-FILL-STRIP
  ;

: DC-.PEN-LABEL  ( -- )
  48 0 AT ." pen=" COLOR @ 2 .R
  ;

: DC-.DRAW-INFO  ( -- )
  0 0 AT ." QUIT   CLEAR"
  14 0 AT ."  (click a color below)"
  DC-.PEN-LABEL
  0 1 AT ." drag=draw  R-drag=thick  M=clear  Esc=quit  H=help"
  \ canvas border
  CWHITE COLOR !  WHITE
  0 0  G-PX 1- 0  LINE
  0 DC-CHROME-Y0 1-  G-PX 1- DC-CHROME-Y0 1- LINE
  0 0  0 DC-CHROME-Y0 1- LINE
  G-PX 1- 0  G-PX 1- DC-CHROME-Y0 1- LINE
  DC-SHOW-COLORS
  DC-SHOW-PEN
  PREFRESH
  ;

: DC-.HELP-INFO  ( -- )
  -1 DC-HELP? !
  4 5 AT ."  DOODLECOLOR64 — COLOR8 mouse demo"
  4 7 AT ."  Click a swatch in the color BAR (below QUIT/CLEAR)."
  4 8 AT ."  Left drag draws; right drag = thick line."
  4 9 AT ."  Middle button or CLEAR erases the canvas."
  4 10 AT ."  Keys 0-9 A-F set pen; Esc or QUIT to leave."
  4 12 AT ."  Click or press a key to dismiss help."
  PREFRESH
  ;

: DC-CLEAR-CANVAS  ( -- )
  PIX-ERASE
  G-BUF G-COLS G-ROWS * BL FILL
  0 G-CX !  0 G-CY !
  DC-.DRAW-INFO
  0 DC-HELP? !
  ;

: DC-#.POSITION  ( x y n -- x y )
  DC-PASS# @ AND 0= IF
    2DUP SWAP 55 0 AT 4 .R SPACE 4 .R SPACE ." p=" COLOR @ 2 .R
    PREFRESH
  THEN
  DC-PASS# @ 1+ DC-PASS# !
  ;

: DC-GRAPH-BYE  ( -- )
  DOODLECOLOR-CREDIT
  ;

: DC-COL-OF  ( x -- col )  G-CELLW / ;

: DC-HIT-COLOR-BAR  ( x -- )
  DC-BAR0 - 0 MAX  DC-CHIPW /  15 MIN  COLOR !
  DC-SHOW-PEN
  DC-.PEN-LABEL
  PREFRESH
  ;

\ QUIT/CLEAR only in the label rows; color picks only in the bar band.
: DC-HIT-CHROME  ( x y -- )
  2DUP DC-IN-COLOR-BAR? IF
    DROP  DC-HIT-COLOR-BAR  EXIT
  THEN
  DUP DC-IN-LABELS? 0= IF
    2DROP EXIT                    \ chrome padding — ignore
  THEN
  DROP  DC-COL-OF                 ( col )
  DUP 5 < IF                      \ QUIT (cols 0..4)
    DROP  -1 DC-DONE? !  EXIT
  THEN
  DUP 7 < IF  DROP EXIT  THEN     \ gap
  DUP 13 < IF                     \ CLEAR (cols 7..12)
    DROP  DC-CLEAR-CANVAS  EXIT
  THEN
  DROP
  ;

: DC-BUTTON-LEFT  ( x y -- x y )
  DUP DC-IN-CHROME?  DC-WASDOWN? @ 0= AND IF
    2DUP DC-HIT-CHROME
    DC-WAIT-MOUSE-UP
    0 DC-WASDOWN? !
  ELSE
    DC-CLIP-DRAW
    DC-WASDOWN? @ 0= IF
      2DUP DC-LAST-Y ! DC-LAST-X !
      -1 DC-WASDOWN? !
    THEN
    255 DC-#.POSITION
    DC-LAST-X @ DC-LAST-Y @  2OVER LINE
    2DUP DC-LAST-Y ! DC-LAST-X !
    PREFRESH
  THEN
  ;

: DC-BUTTON-RIGHT  ( x y -- x y )
  DUP DC-IN-CHROME? IF
    DC-BUTTON-LEFT EXIT
  THEN
  DC-CLIP-DRAW
  DC-WASDOWN? @ 0= IF
    2DUP DC-FROMTO 2!
    -1 DC-WASDOWN? !
  THEN
  2 -2 DO
    DC-FROMTO 2@ I +  2OVER I + LINE
  LOOP
  2DUP DC-FROMTO 2!
  63 DC-#.POSITION
  PREFRESH
  ;

: DC-BUTTON-MIDDLE  ( -- )
  DC-CLEAR-CANVAS
  DC-WAIT-MOUSE-UP
  0 DC-WASDOWN? !
  ;

: DC-?STACK-OK  ( -- )
  DEPTH 0= IF EXIT THEN
  BEGIN DEPTH WHILE DROP REPEAT
  ;

: DC-SET-PEN  ( n -- )
  $F AND COLOR !
  DC-SHOW-PEN PREFRESH
  ;

: DC-DO-KEY  ( c -- flag )          \ true = quit
  DUP 27 = IF  DROP TRUE EXIT  THEN
  DUP [CHAR] q = OVER [CHAR] Q = OR IF  DROP TRUE EXIT  THEN
  DUP [CHAR] h = OVER [CHAR] H = OR IF  DROP DC-.HELP-INFO FALSE EXIT  THEN
  DUP 187 = IF  DROP DC-.HELP-INFO FALSE EXIT  THEN
  DUP [CHAR] m = OVER [CHAR] M = OR IF  DROP DC-CLEAR-CANVAS FALSE EXIT  THEN
  DUP [CHAR] c = OVER [CHAR] C = OR IF  DROP DC-CLEAR-CANVAS FALSE EXIT  THEN
  DUP [CHAR] 0 [CHAR] : WITHIN IF  [CHAR] 0 - DC-SET-PEN FALSE EXIT  THEN
  DUP [CHAR] a [CHAR] g WITHIN IF  [CHAR] a - 10 + DC-SET-PEN FALSE EXIT  THEN
  DUP [CHAR] A [CHAR] G WITHIN IF  [CHAR] A - 10 + DC-SET-PEN FALSE EXIT  THEN
  DC-HELP? @ IF  DROP  0 DC-HELP? !  DC-CLEAR-CANVAS  FALSE EXIT  THEN
  DROP FALSE
  ;

: DC-HANDLE-MOUSE  ( x y buttons -- )
  DC-HELP? @ IF
    DUP IF
      DROP 2DROP
      0 DC-HELP? !  DC-CLEAR-CANVAS
      0 DC-WASDOWN? !
    ELSE
      DROP 2DROP
    THEN
    EXIT
  THEN
  DUP 1 = IF  DROP DC-BUTTON-LEFT  2DROP EXIT  THEN
  DUP 2 = IF  DROP DC-BUTTON-RIGHT 2DROP EXIT  THEN
  DUP 4 = IF  DROP 2DROP DC-BUTTON-MIDDLE EXIT  THEN
  DUP IF
    DROP 2DROP  0 DC-WASDOWN? !  EXIT
  THEN
  DROP  4095 DC-#.POSITION  0 DC-WASDOWN? !  2DROP
  ;

: DC-GRAPH-DRAW  ( -- )
  DECIMAL
  S" 64Forth DOODLECOLOR64" APP-NAME
  WINDOW  PIXEL-ON
  COLOR8
  CWHITE COLOR !
  WHITE
  DC-CLEAR-CANVAS                 \ shows color bar immediately (H = help)
  0 DC-DONE? !
  0 DC-WASDOWN? !
  0 DC-PASS# !
  BEGIN
    DC-DONE? @ 0=
  WHILE
    (APP-PUMP)
    G-MOUSE  DC-HANDLE-MOUSE
    DC-?STACK-OK
    KEY? IF
      KEY DC-DO-KEY IF  -1 DC-DONE? !  THEN
    THEN
  REPEAT
  DC-GRAPH-BYE
  1BIT                    \ restore default depth for the session
  ;

DOC" DOODLECOLOR ( -- ) run the COLOR8 DOODLECOLOR64 mouse demo"
: DOODLECOLOR  ( -- )  DC-GRAPH-DRAW ;

: DOODLECOLOR64  ( -- )  DOODLECOLOR ;

ONLY FORTH DEFINITIONS ALSO GRAPHICS
: DOODLECOLOR  ( -- )
  DC-GRAPH-DRAW
  WINDOW-OFF
  ;
: DOODLECOLOR64  ( -- )  DOODLECOLOR ;
PREVIOUS
CR .( DOODLECOLOR64 loaded — type DOODLECOLOR to run.) CR
