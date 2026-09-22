\ IMAGEVIEW64.fth — macOS image viewer for 64Forth GRAPHICS TRUECOLOR
\
\ Opens any format NSImage/macOS supports (JPEG, PNG, HEIC, TIFF, …)
\ via a file dialog, renders into the 640×400 TRUECOLOR window, and
\ zooms on click.
\
\ Load:
\   FROMLIB FLOAD Sample/IMAGEVIEW64.fth
\   IMAGEVIEW
\
\ Controls
\   O / chrome OPEN   NSOpenPanel
\   Left click        zoom in around click (×2)
\   Right click       zoom out around click (÷2)
\   F / chrome FIT    fit image to window
\   1                 100% (1:1)
\   Esc / Q / QUIT    leave (restores 1BIT)
\   H                 toggle help
\
\ Scriptable load (no panel):
\   S" /path/to/pic.jpg" IV-LOAD
\
\ Requires (APP-IMG-*) host words (interactive 64Forth).
\
\ Public domain.

ANEW IMAGEVIEW64_MODULE

ONLY FORTH DEFINITIONS
DECIMAL

: IV-CREDIT  ( -- )
  CR ." IMAGEVIEW64 — public domain sample; uses macOS image codecs." CR
  ;

ONLY FORTH ALSO GRAPHICS DEFINITIONS
DECIMAL

48 CONSTANT IV-DRAWTOP
VARIABLE IV-WASDOWN?  0 IV-WASDOWN? !
VARIABLE IV-HELP?     0 IV-HELP? !
VARIABLE IV-DONE?     0 IV-DONE? !
VARIABLE IV-CX        0 IV-CX !
VARIABLE IV-CY        0 IV-CY !
VARIABLE IV-ZOOM      100 IV-ZOOM !
VARIABLE IV-IMG-W     0 IV-IMG-W !
VARIABLE IV-IMG-H     0 IV-IMG-H !

: IV-CHROME-Y0  ( -- y )  G-PY IV-DRAWTOP - ;
: IV-IN-CHROME?  ( y -- flag )  IV-CHROME-Y0 >= ;
: IV-COL-OF  ( x -- col )  G-CELLW / ;

: IV-CLIP-CANVAS  ( x y -- x' y' )
  SWAP 0 MAX G-PX 1- MIN
  SWAP 0 MAX IV-CHROME-Y0 1- MIN
  ;

: IV-WAIT-UP  ( -- )
  BEGIN (APP-PUMP) G-MOUSE >R 2DROP R> 0= UNTIL
  ;

: IV-SYNC-SIZE  ( -- )
  (APP-IMG-SIZE) IV-IMG-H ! IV-IMG-W !
  ;

: IV-FIT-ZOOM  ( -- z )
  IV-IMG-W @ 0= IF 100 EXIT THEN
  G-PX 100 IV-IMG-W @ */
  G-PY IV-DRAWTOP - 100 IV-IMG-H @ */
  MIN  1 MAX  800 MIN
  ;

: IV-CENTER-IMAGE  ( -- )
  IV-IMG-W @ 2/ IV-CX !
  IV-IMG-H @ 2/ IV-CY !
  ;

\ Forth click (bottom-left) → image coords at current view.
: IV-CLICK>IMG  ( fx fy -- ix iy )
  G-PY 1- SWAP -                         \ sy (top-down)
  SWAP                                   \ sy fx
  G-PX 2/ -  100 IV-ZOOM @ */  IV-CX @ + \ ix
  SWAP                                   \ ix sy
  G-PY 2/ -  100 IV-ZOOM @ */  IV-CY @ + \ iy
  ;

: IV-RENDER  ( -- )
  IV-IMG-W @ 0= IF  PIX-ERASE EXIT  THEN
  G-PIX G-PX G-PY IV-CX @ IV-CY @ IV-ZOOM @
  (APP-IMG-RENDER) DROP
  -1 TO G-PDIRTY?
  ;

: IV-.STATUS  ( -- )
  40 0 AT
  IV-IMG-W @ IF
    IV-IMG-W @ . ." x" IV-IMG-H @ . ." z=" IV-ZOOM @ 4 .R
  ELSE
    ." (no image)      "
  THEN
  ;

: IV-.CHROME  ( -- )
  0 0 AT ." QUIT  OPEN  FIT"
  IV-.STATUS
  0 1 AT ." L-click=zoom+  R-click=zoom-  O=open  F=fit  1=100%  H=help  Esc=quit"
  128 128 128 RGB COLOR ! WHITE
  0 IV-CHROME-Y0 1-  G-PX 1- IV-CHROME-Y0 1- LINE
  ;

: IV-REFRESH  ( -- )
  IV-RENDER
  \ Full char clear — help text lives below the chrome rows.
  G-BUF G-COLS G-ROWS * BL FILL
  0 G-CX ! 0 G-CY !
  IV-.CHROME
  IV-IMG-W @ 0= IF
    2 3 AT ."  No image — press O or click OPEN"
  THEN
  PREFRESH
  ;

: IV-.HELP  ( -- )
  -1 IV-HELP? !
  G-BUF G-COLS G-ROWS * BL FILL
  0 G-CX ! 0 G-CY !
  IV-.CHROME
  4 5 AT ."  IMAGEVIEW64 — macOS image viewer"
  4 7 AT ."  OPEN / O  — JPEG, PNG, HEIC, TIFF, GIF, …"
  4 8 AT ."  Left click zooms in; right click zooms out."
  4 9 AT ."  FIT fits the image; 1 = 100% pixels."
  4 11 AT ."  H again (or click) to dismiss."
  PREFRESH
  ;

: IV-TOGGLE-HELP  ( -- )
  IV-HELP? @ IF
    0 IV-HELP? !  IV-REFRESH
  ELSE
    IV-.HELP
  THEN
  ;

: IV-AFTER-LOAD  ( ior -- )
  DUP 0= IF
    DROP
    IV-SYNC-SIZE
    IV-CENTER-IMAGE
    IV-FIT-ZOOM IV-ZOOM !
    IV-REFRESH
  ELSE
    DUP -1 = IF
      DROP  IV-REFRESH  2 3 AT ."  Open cancelled" PREFRESH
    ELSE
      DROP  IV-REFRESH  2 3 AT ."  Could not load image" PREFRESH
    THEN
  THEN
  ;

: IV-OPEN  ( -- )
  (APP-IMG-CHOOSE) IV-AFTER-LOAD
  ;

: IV-LOAD  ( c-addr u -- )
  (APP-IMG-LOAD) IV-AFTER-LOAD
  ;

: IV-FIT  ( -- )
  IV-IMG-W @ 0= IF EXIT THEN
  IV-CENTER-IMAGE
  IV-FIT-ZOOM IV-ZOOM !
  IV-REFRESH
  ;

: IV-ZOOM-AT  ( fx fy factor -- )   \ +2 = ×2, -2 = ÷2
  >R
  2DUP IV-CLICK>IMG IV-CY ! IV-CX !  2DROP
  R> 0< IF
    IV-ZOOM @ 2/ 1 MAX IV-ZOOM !
  ELSE
    IV-ZOOM @ 2* 3200 MIN IV-ZOOM !
  THEN
  IV-REFRESH
  ;

: IV-HIT-CHROME  ( x y -- )
  DROP IV-COL-OF
  DUP 4 < IF  DROP -1 IV-DONE? ! EXIT  THEN
  DUP 6 < IF  DROP EXIT  THEN
  DUP 10 < IF DROP IV-OPEN EXIT  THEN
  DUP 12 < IF DROP EXIT  THEN
  DUP 15 < IF DROP IV-FIT EXIT  THEN
  DROP
  ;

: IV-BUTTON-LEFT  ( x y -- )
  IV-WASDOWN? @ IF  2DROP EXIT  THEN
  -1 IV-WASDOWN? !
  DUP IV-IN-CHROME? IF
    IV-HIT-CHROME
    IV-WAIT-UP
    0 IV-WASDOWN? !
  ELSE
    IV-CLIP-CANVAS
    2 IV-ZOOM-AT
  THEN
  ;

: IV-BUTTON-RIGHT  ( x y -- )
  IV-WASDOWN? @ IF  2DROP EXIT  THEN
  -1 IV-WASDOWN? !
  DUP IV-IN-CHROME? IF
    2DROP EXIT
  THEN
  IV-CLIP-CANVAS
  -2 IV-ZOOM-AT
  ;

: IV-DO-KEY  ( c -- flag )
  DUP 27 = IF DROP TRUE EXIT THEN
  DUP [CHAR] q = OVER [CHAR] Q = OR IF DROP TRUE EXIT THEN
  \ H toggles help even while the overlay is up (must be before generic dismiss).
  DUP [CHAR] h = OVER [CHAR] H = OR IF DROP IV-TOGGLE-HELP FALSE EXIT THEN
  IV-HELP? @ IF DROP 0 IV-HELP? ! IV-REFRESH FALSE EXIT THEN
  DUP [CHAR] o = OVER [CHAR] O = OR IF DROP IV-OPEN FALSE EXIT THEN
  DUP [CHAR] f = OVER [CHAR] F = OR IF DROP IV-FIT FALSE EXIT THEN
  DUP [CHAR] 1 = IF DROP 100 IV-ZOOM ! IV-REFRESH FALSE EXIT THEN
  DROP FALSE
  ;

: IV-HANDLE-MOUSE  ( x y buttons -- )
  IV-HELP? @ IF
    DUP IF DROP 2DROP 0 IV-HELP? ! IV-REFRESH
    ELSE DROP 2DROP THEN
    EXIT
  THEN
  DUP 1 = IF  DROP IV-BUTTON-LEFT EXIT  THEN
  DUP 2 = IF  DROP IV-BUTTON-RIGHT EXIT  THEN
  DUP IF  DROP 2DROP  0 IV-WASDOWN? !  EXIT  THEN
  DROP  0 IV-WASDOWN? !  2DROP
  ;

\ Sync from host cache (argv --image preload, or after choose/load).
: IV-SYNC-FROM-HOST  ( -- )
  (APP-IMG-SIZE)
  2DUP OR 0= IF  2DROP  0 IV-IMG-W ! 0 IV-IMG-H !  EXIT  THEN
  IV-IMG-H ! IV-IMG-W !
  IV-CENTER-IMAGE
  IV-FIT-ZOOM IV-ZOOM !
  ;

: IV-GRAPH  ( -- )
  DECIMAL
  S" 64Forth IMAGEVIEW64" APP-NAME
  WINDOW PIXEL-ON
  TRUECOLOR
  CWHITE COLOR ! WHITE
  PIX-ERASE
  G-BUF G-COLS G-ROWS * BL FILL
  0 G-CX ! 0 G-CY !
  0 IV-IMG-W ! 0 IV-IMG-H !
  100 IV-ZOOM !
  IV-SYNC-FROM-HOST
  IV-REFRESH
  0 IV-DONE? !
  BEGIN IV-DONE? @ 0= WHILE
    (APP-PUMP)
    G-MOUSE IV-HANDLE-MOUSE
    DEPTH IF BEGIN DEPTH WHILE DROP REPEAT THEN
    KEY? IF KEY IV-DO-KEY IF -1 IV-DONE? ! THEN THEN
  REPEAT
  IV-CREDIT
  \ Credit only — WINDOW-OFF is FORTH IMAGEVIEW / EMIT-WINDOW-APP.
  1BIT
  ;

\ Export as a real colon (Emitter must see IV-GRAPH in the body).
ONLY FORTH DEFINITIONS ALSO GRAPHICS
: IMAGEVIEW  ( -- )
  IV-GRAPH
  WINDOW-OFF
  ;
: IMAGEVIEW64  ( -- )  IMAGEVIEW ;

\ Re-export IV-LOAD for scripts (path string).
: IV-LOAD  ( c-addr u -- )  ALSO GRAPHICS IV-LOAD PREVIOUS ;

PREVIOUS
CR .( IMAGEVIEW64 loaded — type IMAGEVIEW to run.) CR
