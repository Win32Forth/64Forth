\ app-point.fth — 1-bit point graphics for 64Forth GRAPHICS
\
\ Host must provide (APP-PBLIT) ( c-addr u -- ) or plots fall back to '*' cells.
\
\ Coordinates
\   Origin (0,0) is bottom-left. X right, Y up.
\   Size: G-PX × G-PY  (default 640 × 400 = 80 cols × 8  by  25 rows × 16).
\   Out-of-range PLOT/UNPLOT/LINE points are ignored.
\
\ Ink (G-INK)
\   WHITE   subsequent plots set the bit
\   BLACK   subsequent plots clear the bit
\   INVERT  subsequent plots xor the bit
\
\ Drawing
\   PLOT / UNPLOT / LINE write G-PIX only.
\   PREFRESH copies G-PIX to the window (and overlays any AT ." text).
\   PCLS clears pixels and characters, then refreshes.
\   Character words (AT EMIT TYPE .") still work; spaces do not cover pixels.
\
\ Typical session
\   ALSO GRAPHICS
\   S" My plot" APP-NAME
\   WINDOW  PCLS  WHITE
\   10 10 PLOT
\   0 0  G-PX 1- G-PY 1- LINE
\   2 22 AT ." diagonal"
\   PREFRESH
\   KEY DROP  WINDOW-OFF
\
\ Smoke test:  GRAPHICS-PSMOKE
\
\ Public domain.

ONLY FORTH ALSO GRAPHICS DEFINITIONS

DOC" G-CELLW ( -- n ) pixel width of one character cell"
8  CONSTANT G-CELLW

DOC" G-CELLH ( -- n ) pixel height of one character cell"
16 CONSTANT G-CELLH

DOC" G-PX ( -- n ) pixel width of the graphics window"
G-COLS G-CELLW * CONSTANT G-PX          \ 640

DOC" G-PY ( -- n ) pixel height of the graphics window"
G-ROWS G-CELLH * CONSTANT G-PY          \ 400

\ packed bits, row-major, LSB = leftmost pixel in the byte
DOC" G-PIX ( -- addr ) 1-bit packed pixel map"
CREATE G-PIX  G-PX 7 + 8 / G-PY * ALLOT

DOC" G-INK ( -- addr ) plot ink: 1=set 0=clear -1=xor"
VARIABLE G-INK   1 G-INK !              \ 1=set  0=clear  -1=xor

DOC" G-PMODE? ( -- flag ) true when pixel mode is on"
0 VALUE G-PMODE?                        \ true after PIXEL-ON

DOC" G-PDIRTY? ( -- flag ) true when G-PIX needs PREFRESH"
0 VALUE G-PDIRTY?

DOC" PIXEL-ON ( -- ) enable pixel mode for this window"
: PIXEL-ON   ( -- )  -1 TO G-PMODE? ;

DOC" PIXEL-OFF ( -- ) return refresh to character-only"
: PIXEL-OFF  ( -- )   0 TO G-PMODE? ;

DOC" WHITE ( -- ) set ink; later PLOT and LINE set bits"
: WHITE  ( -- )   1 G-INK ! ;

DOC" BLACK ( -- ) set ink; later PLOT and LINE clear bits"
: BLACK  ( -- )   0 G-INK ! ;

DOC" INVERT ( -- ) set ink; later PLOT and LINE xor bits"
: INVERT ( -- )  -1 G-INK ! ;

DOC" PIX-ERASE ( -- ) zero the pixel map without blitting"
: PIX-ERASE  ( -- )
  G-PIX  G-PX 7 + 8 / G-PY *  0 FILL
  -1 TO G-PDIRTY?
  ;

DOC" XY-OK? ( x y -- flag ) true if (x,y) is inside G-PX G-PY"
: XY-OK?  ( x y -- flag )
  SWAP 0 G-PX WITHIN  SWAP 0 G-PY WITHIN  AND
  ;

\ addr and bit mask for (x,y); y=0 is bottom row
DOC" XY>PIX ( x y -- addr mask ) byte and bit for pixel (x,y)"
: XY>PIX  ( x y -- addr mask )
  G-PY 1- SWAP -                      \ flip y → row from top
  G-PX 7 + 8 / *   OVER 3 RSHIFT +    \ row stride + byte
  G-PIX +
  SWAP 7 AND  1 SWAP LSHIFT           \ mask
  ;

DOC" PLOT ( x y -- ) plot one pixel with current ink"
: PLOT  ( x y -- )
  WINDOW  PIXEL-ON
  2DUP XY-OK? 0= IF  2DROP EXIT  THEN
  XY>PIX
  G-INK @
  DUP 0< IF  DROP                     \ xor
    OVER C@ XOR SWAP C!
  ELSE  IF                             \ set
    OVER C@ OR SWAP C!
  ELSE                                 \ clear
    INVERT OVER C@ AND SWAP C!
  THEN THEN
  -1 TO G-PDIRTY?  DIRTY
  ;

DOC" UNPLOT ( x y -- ) clear one pixel; restore previous ink"
: UNPLOT  ( x y -- )
  G-INK @ >R  BLACK  PLOT  R> G-INK !
  ;

DOC" POINT@ ( x y -- flag ) true if pixel (x,y) is set"
: POINT@  ( x y -- flag )              \ 0 or -1
  2DUP XY-OK? 0= IF  2DROP 0 EXIT  THEN
  XY>PIX  SWAP C@ AND  0<>
  ;

VARIABLE LX0  VARIABLE LY0
VARIABLE LX1  VARIABLE LY1
VARIABLE LDX  VARIABLE LDY
VARIABLE LSX  VARIABLE LSY
VARIABLE LERR

DOC" LINE ( x0 y0 x1 y1 -- ) Bresenham line in current ink"
: LINE  ( x0 y0 x1 y1 -- )
  WINDOW  PIXEL-ON
  LY1 ! LX1 ! LY0 ! LX0 !
  LX1 @ LX0 @ - DUP 0< IF NEGATE -1 ELSE 1 THEN LSX !  ABS LDX !
  LY1 @ LY0 @ - DUP 0< IF NEGATE -1 ELSE 1 THEN LSY !  ABS LDY !
  LDX @ LDY @ - LERR !
  BEGIN
    LX0 @ LY0 @ PLOT
    LX0 @ LX1 @ =  LY0 @ LY1 @ =  AND IF EXIT THEN
    LERR @ 2*
    DUP LDY @ NEGATE > IF
      LDY @ NEGATE LERR +!  LSX @ LX0 +!
    THEN
    LDX @ < IF
      LDX @ LERR +!  LSY @ LY0 +!
    THEN
  AGAIN
  ;

\ clearer PIX>CHAR
DOC" CELL-LIT? ( col row -- flag ) true if any pixel in that char cell is set"
: CELL-LIT?  ( col row -- flag )
  G-CELLH 0 DO                          \ sy
    G-CELLW 0 DO                        \ sx
      OVER G-CELLW * I +                \ x
      OVER G-ROWS SWAP - 1- G-CELLH * J +
      G-PY SWAP - 1-                    \ y  (bottom-left origin)
      POINT@ IF  2DROP  -1 UNLOOP UNLOOP EXIT  THEN
    LOOP
  LOOP  2DROP  0
  ;

DOC" PIX>CHAR ( -- ) stamp lit cells as * into G-BUF (no host pixels)"
: PIX>CHAR  ( -- )
  G-ROWS 0 DO
    G-COLS 0 DO
      I J CELL-LIT? IF
        [CHAR] *  I J G-COLS * + G-BUF + C!
      THEN
    LOOP
  LOOP
  DIRTY
  ;

DOC" PREFRESH ( -- ) blit pixel map and any text to the window"
: PREFRESH  ( -- )
  G-PMODE? 0= IF  REFRESH EXIT  THEN
  [DEFINED] (APP-PBLIT) [IF]
    G-PIX  G-PX 7 + 8 / G-PY *  (APP-PBLIT)
    REFRESH                         \ overlay any AT ." text
  [ELSE]
    PIX>CHAR  REFRESH
  [THEN]
  0 TO G-PDIRTY?  0 TO G-DIRTY?
  ;
  
DOC" PCLS ( -- ) clear pixels and chars, home cursor, blit"
: PCLS  ( -- )
  WINDOW  PIX-ERASE
  G-BUF G-COLS G-ROWS * BL FILL
  0 G-CX !  0 G-CY !
  PREFRESH
  ;

DOC" POINTS-HELP ( -- ) show point-graphics word summary in the window": POINTS-HELP  ( -- )
  WINDOW
  PCLS
  1 1 AT ." Point graphics  (0,0)=bottom-left  "
  G-PX . ." x " G-PY . ." pixels"
  1 3 AT ." WHITE BLACK INVERT   ink for PLOT/LINE"
  1 4 AT ." x y PLOT   x y UNPLOT   x y POINT@"
  1 5 AT ." x0 y0 x1 y1 LINE"
  1 6 AT ." PCLS  PREFRESH  GRAPHICS-PSMOKE"
  1 8 AT ." Example:  PCLS WHITE  0 0 G-PX 1- G-PY 1- LINE PREFRESH"
  PREFRESH
  ;

DOC" GRAPHICS-PSMOKE ( -- ) demo X of lines, prompt, wait for a key"
: GRAPHICS-PSMOKE  ( -- )
  S" 64Forth POINTS" APP-NAME
  WINDOW  PCLS  WHITE
  0 0  G-PX 1- G-PY 1- LINE
  G-PX 1- 0  0 G-PY 1- LINE
  G-PX 2/ 0  G-PX 2/ G-PY 1- LINE
  0 G-PY 2/  G-PX 1- G-PY 2/ LINE
  20 20 AT ." X through the window — any key"
  PREFRESH
  KEY DROP
  WINDOW-OFF
  ;

FORTH DEFINITIONS
