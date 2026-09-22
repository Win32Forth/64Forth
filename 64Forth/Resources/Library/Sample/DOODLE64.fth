\ DOODLE64.fth — simple mouse drawing demo for 64Forth GRAPHICS
\
\ Port of classic TCOM DOODLE.FTH (Tom Zimmer, public domain) to
\ 64Forth 640×400 1-bit points + host mouse.
\
\ Load (not Autoload):
\   FROMLIB FLOAD Sample/DOODLE64.fth
\   DOODLE
\
\ Controls
\   Left drag     draw with current ink
\   Right drag    thick stroke (Control-click on trackpad)
\   Middle        clear drawing area
\   Chrome bar    QUIT / CLEAR / WHITE / BLACK / INVERT
\   Esc or QUIT   leave (returns to console; no BYE)
\   H or F1       help overlay
\   W / B / I     ink shortcuts
\
\ Requires GRAPHICS mouse: (APP-MOUSE) / G-MOUSE (64Forth 1.4.2+).
\
\ Public domain.

\ Console credit must use FORTH CR/." — GRAPHICS CR reopens the window.
ONLY FORTH DEFINITIONS
DECIMAL

: DOODLE-CREDIT  ( -- )
  CR ." DOODLE64 is a public domain example by Tom Zimmer,"
  CR ." adapted for 64Forth GRAPHICS (640x400, mouse)." CR
  ;

ONLY FORTH ALSO GRAPHICS DEFINITIONS
DECIMAL

48 CONSTANT DRAWTOP          \ chrome height in pixels (3 char rows)
\ VARIABLEs (not VALUEs): Emitter reach must see the xt in colon bodies.
\ TO on VALUE compiles a host PFA literal that was previously left unmapped.
VARIABLE WASDOWN?  0 WASDOWN? !
VARIABLE PASS#     0 PASS# !
VARIABLE HELP?     0 HELP? !
VARIABLE DONE?     0 DONE? !
VARIABLE LAST-X
VARIABLE LAST-Y
2VARIABLE FROMTO

: CHROME-Y0  ( -- y )  G-PY DRAWTOP - ;   \ first pixel row of chrome (bottom-left origin)

: IN-CHROME?  ( y -- flag )
  CHROME-Y0 >=
  ;

: CLIP-DRAW  ( x y -- x' y' )
  SWAP 1 MAX  G-PX 2 - MIN
  SWAP 0 MAX  CHROME-Y0 2 - MIN
  ;

: WAIT-MOUSE-UP  ( -- )
  BEGIN
    (APP-PUMP)  G-MOUSE           \ x y buttons
    >R 2DROP R>  0=
  UNTIL
  ;

: SHOW-INK-CHIP  ( -- )          \ small bar at right of chrome
  G-INK @ >R
  WHITE
  G-PX 16 -  CHROME-Y0 2 +
  G-PX 4 -   G-PY 3 -
  LINE
  R> G-INK !
  ;

: .DRAW-INFO  ( -- )
  0 0 AT ." QUIT  CLEAR     WHITE  BLACK  INVERT"
  0 1 AT ." drag=draw  R-drag=thick  M=clear  Esc=quit  H=help"
  \ border around draw area
  WHITE
  0 0  G-PX 1- 0  LINE
  0 CHROME-Y0 1-  G-PX 1- CHROME-Y0 1- LINE
  0 0  0 CHROME-Y0 1- LINE
  G-PX 1- 0  G-PX 1- CHROME-Y0 1- LINE
  SHOW-INK-CHIP
  PREFRESH
  ;

: .HELP-INFO  ( -- )
  -1 HELP? !
  8 6 AT ."  DOODLE64 — 64Forth GRAPHICS demo"
  8 8 AT ."  Left drag draws with WHITE/BLACK/INVERT."
  8 9 AT ."  Right drag (or Control-click) = thick line."
  8 10 AT ."  Middle button or CLEAR erases the canvas."
  8 11 AT ."  Click QUIT or press Esc to leave."
  8 13 AT ."  Click or press a key to dismiss help."
  PREFRESH
  ;

: CLEAR-CANVAS  ( -- )
  PIX-ERASE
  \ wipe char cells used by help / chrome then redraw chrome
  G-BUF G-COLS G-ROWS * BL FILL
  0 G-CX !  0 G-CY !
  .DRAW-INFO
  0 HELP? !
  ;

: #.POSITION  ( x y n -- x y )
  PASS# @ AND 0= IF
    2DUP SWAP 60 2 AT 4 .R SPACE 4 .R
    PREFRESH
  THEN
  PASS# @ 1+ PASS# !
  ;

\ Credit only — do not WINDOW-OFF here. EMIT-WINDOW-APP owns the window;
\ console DOODLE closes after GRAPH-DRAW (see FORTH export below).
: GRAPH-BYE  ( -- )
  DOODLE-CREDIT
  ;

: COL-OF  ( x -- col )  G-CELLW / ;
: ROW-OF  ( y -- row )  G-PY 1- SWAP - G-CELLH / ;   \ 0 = top char row

\ Chrome text: "QUIT  CLEAR     WHITE  BLACK  INVERT"
\ cols:         0123456789...   16     23     30
: HIT-CHROME  ( x y -- )
  DROP  COL-OF                    ( col )
  DUP 4 < IF                      \ QUIT
    DROP  -1 DONE? !  EXIT
  THEN
  DUP 6 < IF  DROP EXIT  THEN     \ gap
  DUP 11 < IF                     \ CLEAR
    DROP  CLEAR-CANVAS  EXIT
  THEN
  DUP 16 < IF  DROP EXIT  THEN
  DUP 21 < IF  DROP WHITE SHOW-INK-CHIP PREFRESH EXIT  THEN
  DUP 23 < IF  DROP EXIT  THEN
  DUP 28 < IF  DROP BLACK SHOW-INK-CHIP PREFRESH EXIT  THEN
  DUP 30 < IF  DROP EXIT  THEN
  DUP 36 < IF  DROP INVERT SHOW-INK-CHIP PREFRESH EXIT  THEN
  DROP
  ;

: BUTTON-LEFT  ( x y -- x y )
  \ DUP tests y only — 2DUP IN-CHROME? left a stray x and broke the stack
  DUP IN-CHROME?  WASDOWN? @ 0= AND IF
    2DUP HIT-CHROME
    WAIT-MOUSE-UP
    0 WASDOWN? !
  ELSE
    CLIP-DRAW
    WASDOWN? @ 0= IF
      2DUP LAST-Y ! LAST-X !          \ y then x (! takes TOS first)
      -1 WASDOWN? !
    THEN
    255 #.POSITION
    LAST-X @ LAST-Y @  2OVER LINE
    2DUP LAST-Y ! LAST-X !
    PREFRESH
  THEN
  ;

: BUTTON-RIGHT  ( x y -- x y )
  DUP IN-CHROME? IF
    BUTTON-LEFT EXIT
  THEN
  CLIP-DRAW
  WASDOWN? @ 0= IF
    2DUP FROMTO 2!
    -1 WASDOWN? !
  THEN
  2 -2 DO
    FROMTO 2@ I +  2OVER I + LINE
  LOOP
  2DUP FROMTO 2!
  63 #.POSITION
  PREFRESH
  ;

: BUTTON-MIDDLE  ( -- )
  CLEAR-CANVAS
  WAIT-MOUSE-UP
  0 WASDOWN? !
  ;

: ?STACK-OK  ( -- )
  DEPTH 0= IF EXIT THEN
  \ Recover; do not exit the demo (old chrome bug used to trip this).
  BEGIN DEPTH WHILE DROP REPEAT
  ;

: DO-KEY  ( c -- flag )          \ true = quit
  DUP 27 = IF  DROP TRUE EXIT  THEN                    \ Esc
  DUP [CHAR] q = OVER [CHAR] Q = OR IF  DROP TRUE EXIT  THEN
  DUP [CHAR] h = OVER [CHAR] H = OR IF  DROP .HELP-INFO FALSE EXIT  THEN
  DUP 187 = IF  DROP .HELP-INFO FALSE EXIT  THEN       \ F1 if tagged
  DUP [CHAR] m = OVER [CHAR] M = OR IF  DROP CLEAR-CANVAS FALSE EXIT  THEN
  DUP [CHAR] c = OVER [CHAR] C = OR IF  DROP CLEAR-CANVAS FALSE EXIT  THEN
  DUP [CHAR] w = OVER [CHAR] W = OR IF  DROP WHITE SHOW-INK-CHIP PREFRESH FALSE EXIT  THEN
  DUP [CHAR] b = OVER [CHAR] B = OR IF  DROP BLACK SHOW-INK-CHIP PREFRESH FALSE EXIT  THEN
  DUP [CHAR] i = OVER [CHAR] I = OR IF  DROP INVERT SHOW-INK-CHIP PREFRESH FALSE EXIT  THEN
  HELP? @ IF  DROP  0 HELP? !  CLEAR-CANVAS  FALSE EXIT  THEN
  DROP FALSE
  ;

: HANDLE-MOUSE  ( x y buttons -- )
  HELP? @ IF
    \ Only a button click dismisses help — idle polls used to clear it immediately
    DUP IF
      DROP 2DROP
      0 HELP? !  CLEAR-CANVAS
      0 WASDOWN? !
    ELSE
      DROP 2DROP
    THEN
    EXIT
  THEN
  DUP 1 = IF  DROP BUTTON-LEFT  2DROP EXIT  THEN
  DUP 2 = IF  DROP BUTTON-RIGHT 2DROP EXIT  THEN
  DUP 4 = IF  DROP 2DROP BUTTON-MIDDLE EXIT  THEN
  DUP IF
    DROP 2DROP  0 WASDOWN? !  EXIT      \ other combo
  THEN
  DROP  4095 #.POSITION  0 WASDOWN? !  2DROP
  ;

: GRAPH-DRAW  ( -- )
  DECIMAL
  S" 64Forth DOODLE64" APP-NAME
  WINDOW  PIXEL-ON
  WHITE
  CLEAR-CANVAS
  .HELP-INFO
  0 DONE? !
  0 WASDOWN? !
  0 PASS# !
  BEGIN
    DONE? @ 0=
  WHILE
    (APP-PUMP)
    G-MOUSE  HANDLE-MOUSE
    ?STACK-OK
    KEY? IF
      KEY DO-KEY IF  -1 DONE? !  THEN
    THEN
  REPEAT
  GRAPH-BYE
  ;

DOC" DOODLE ( -- ) run the DOODLE64 mouse drawing demo"
: DOODLE  ( -- )  GRAPH-DRAW ;

\ alias used by some classic scripts
: DOODLE64  ( -- )  DOODLE ;

\ Export into FORTH as a real colon (not CONSTANT+EXECUTE).
\ Emitter must see GRAPH-DRAW in the body; a CONSTANT PFA xt was left as a
\ host CFA in stand-alone images and EXECUTE crashed after the first KEY.
ONLY FORTH DEFINITIONS ALSO GRAPHICS
: DOODLE  ( -- )
  GRAPH-DRAW
  WINDOW-OFF          \ console return; EMIT-WINDOW-APP also WINDOW-OFFs
  ;
: DOODLE64  ( -- )  DOODLE ;
PREVIOUS
CR .( DOODLE64 loaded — type DOODLE to run.) CR
