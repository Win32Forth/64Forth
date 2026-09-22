\ app-points.fth — point graphics for 64Forth GRAPHICS (1 / 8 / 32-bit)
\
\ Host: (APP-CBLIT) ( c-addr u depth -- ) preferred; (APP-PBLIT) = 1-bit legacy.
\ Fallback: PIX>CHAR stamps '*' into cells.
\
\ Coordinates
\   Origin (0,0) is bottom-left. X right, Y up.
\   Size: G-PX × G-PY  (default 640 × 400 = 80 cols × 8  by  25 rows × 16).
\   Out-of-range PLOT/UNPLOT/LINE points are ignored.
\
\ Depth (G-DEPTH)
\   1BIT       packed bits (default; green-on-black host tint)
\   COLOR8     one byte/pixel, palette indices 0..255
\   TRUECOLOR  4 bytes/pixel BGRA (Forth pen = $00RRGGBB; store OR $FF000000)
\   G-PIX is always sized for truecolor (~1 MiB) so mode switches need no RESIZE.
\
\ Ink (G-INK) — modes, not palette indices
\   WHITE   subsequent plots set (1-bit bit; color uses COLOR)
\   BLACK   subsequent plots clear to 0
\   INVERT  subsequent plots xor (1-bit bit; 8-bit xor COLOR; 32-bit xor pen|alpha)
\
\ Pen
\   COLOR   VARIABLE — index (COLOR8) or $00RRGGBB (TRUECOLOR)
\   RGB     ( r g b -- n ) pack truecolor pen
\   CBLACK..CWHITE  classic 16 indices (use with COLOR ! in COLOR8)
\
\ Drawing
\   PLOT / UNPLOT / LINE write G-PIX only.
\   PREFRESH copies G-PIX to the window (and overlays any AT ." text).
\   PCLS clears pixels and characters, then refreshes.
\
\ Typical session
\   ALSO GRAPHICS
\   TRUECOLOR  S" Color" APP-NAME  WINDOW  PCLS
\   255 0 0 RGB COLOR !  WHITE
\   10 10 PLOT   0 0 G-PX 1- G-PY 1- LINE  PREFRESH
\
\ Public domain.
.( Loading: app-point.fth) CR
ONLY FORTH ALSO GRAPHICS DEFINITIONS

DOC" G-CELLW ( -- n ) pixel width of one character cell"
8  CONSTANT G-CELLW

DOC" G-CELLH ( -- n ) pixel height of one character cell"
16 CONSTANT G-CELLH

DOC" G-PX ( -- n ) pixel width of the graphics window"
G-COLS G-CELLW * CONSTANT G-PX          \ 640

DOC" G-PY ( -- n ) pixel height of the graphics window"
G-ROWS G-CELLH * CONSTANT G-PY          \ 400

\ Max buffer = truecolor; 1-bit/COLOR8 use a prefix of the same allot.
DOC" G-PIX ( -- addr ) pixel map (sized for 32-bit; depth selects used bytes)"
CREATE G-PIX  G-PX G-PY * 4 * ALLOT

DOC" G-DEPTH ( -- n ) 1=bits 8=index 32=BGRA"
1 VALUE G-DEPTH

DOC" G-INK ( -- addr ) plot ink: 1=set 0=clear -1=xor"
VARIABLE G-INK   1 G-INK !              \ 1=set  0=clear  -1=xor

DOC" COLOR ( -- addr ) pen: COLOR8 index or TRUECOLOR $00RRGGBB"
VARIABLE COLOR   $FFFFFF COLOR !        \ bright white / full RGB

DOC" G-PMODE? ( -- flag ) true when pixel mode is on"
0 VALUE G-PMODE?                        \ true after PIXEL-ON

DOC" G-PDIRTY? ( -- flag ) true when G-PIX needs PREFRESH"
0 VALUE G-PDIRTY?

DOC" G-PIXBYTES ( -- u ) bytes used by G-PIX at current G-DEPTH"
: G-PIXBYTES  ( -- u )
  G-DEPTH 1 = IF  G-PX 7 + 8 / G-PY *
  ELSE G-DEPTH 8 = IF  G-PX G-PY *
  ELSE  G-PX G-PY * 4 *
  THEN THEN ;

DOC" PIXEL-ON ( -- ) enable pixel mode for this window"
: PIXEL-ON   ( -- )  -1 TO G-PMODE? ;

DOC" PIXEL-OFF ( -- ) return refresh to character-only"
: PIXEL-OFF  ( -- )   0 TO G-PMODE? ;

DOC" WHITE ( -- ) set ink; later PLOT/LINE set pixels (use COLOR in 8/32)"
: WHITE  ( -- )   1 G-INK ! ;

DOC" BLACK ( -- ) set ink; later PLOT/LINE clear pixels to 0"
: BLACK  ( -- )   0 G-INK ! ;

DOC" INVERT ( -- ) set ink; later PLOT/LINE xor pixels"
: INVERT ( -- )  -1 G-INK ! ;

DOC" RGB ( r g b -- n ) pack $00RRGGBB for TRUECOLOR COLOR !"
: RGB  ( r g b -- n )
  $FF AND  SWAP $FF AND 8 LSHIFT OR  SWAP $FF AND 16 LSHIFT OR ;

DOC" >COLOR ( n -- ) n COLOR !"
: >COLOR  ( n -- )  COLOR ! ;

\ Classic TCOLOR indices 0..15 (COLOR8). Not ink words WHITE/BLACK.
0 CONSTANT CBLACK
1 CONSTANT CBLUE
2 CONSTANT CGREEN
3 CONSTANT CCYAN
4 CONSTANT CRED
5 CONSTANT CMAGENTA
6 CONSTANT CBROWN
7 CONSTANT CLTGRAY
8 CONSTANT CDKGRAY
9 CONSTANT CLTBLUE
10 CONSTANT CLTGREEN
11 CONSTANT CLTCYAN
12 CONSTANT CLTRED
13 CONSTANT CLTMAGENTA
14 CONSTANT CYELLOW
15 CONSTANT CWHITE

\ TRUECOLOR pixels use kernel L@ / L! (32-bit ldr w / str w).

DOC" PIX-ERASE ( -- ) zero the used pixel map without blitting"
: PIX-ERASE  ( -- )
  G-PIX  G-PIXBYTES  0 FILL
  -1 TO G-PDIRTY?
  ;

DOC" 1BIT ( -- ) select 1-bit packed pixels (default)"
: 1BIT  ( -- )
  1 TO G-DEPTH
  1 G-INK !
  PIX-ERASE
  ;

DOC" COLOR8 ( -- ) select 8-bit indexed pixels"
: COLOR8  ( -- )
  8 TO G-DEPTH
  CWHITE COLOR !
  1 G-INK !
  PIX-ERASE
  ;

DOC" TRUECOLOR ( -- ) select 32-bit BGRA pixels"
: TRUECOLOR  ( -- )
  32 TO G-DEPTH
  $FFFFFF COLOR !
  1 G-INK !
  PIX-ERASE
  ;

DOC" XY-OK? ( x y -- flag ) true if (x,y) is inside G-PX G-PY"
: XY-OK?  ( x y -- flag )
  SWAP 0 G-PX WITHIN  SWAP 0 G-PY WITHIN  AND
  ;

\ 1-bit: addr + bit mask. y=0 is bottom row.
DOC" XY>PIX ( x y -- addr mask ) byte and bit for 1-bit pixel (x,y)"
: XY>PIX  ( x y -- addr mask )
  G-PY 1- SWAP -                      \ flip y → row from top
  G-PX 7 + 8 / *   OVER 3 RSHIFT +    \ row stride + byte
  G-PIX +
  SWAP 7 AND  1 SWAP LSHIFT           \ mask
  ;

\ Color: byte (8) or cell (32) address for pixel (x,y).
DOC" XY>ADDR ( x y -- addr ) pixel address for COLOR8/TRUECOLOR"
: XY>ADDR  ( x y -- addr )
  G-PY 1- SWAP -                      \ row from top
  G-PX * +
  G-DEPTH 32 = IF  4 *  THEN
  G-PIX +
  ;

: (PLOT1)  ( x y -- )                  \ 1-bit
  XY>PIX
  G-INK @
  DUP 0< IF  DROP                     \ xor
    OVER C@ XOR SWAP C!
  ELSE  IF                             \ set
    OVER C@ OR SWAP C!
  ELSE                                 \ clear
    -1 XOR OVER C@ AND SWAP C!
  THEN THEN
  ;

: (PLOT8)  ( x y -- )
  XY>ADDR
  G-INK @
  DUP 0< IF  DROP
    DUP C@  COLOR @ XOR  SWAP C!
  ELSE  IF
    COLOR @ $FF AND  SWAP C!
  ELSE
    0 SWAP C!
  THEN THEN
  ;

: (PLOT32)  ( x y -- )
  XY>ADDR
  G-INK @
  DUP 0< IF  DROP
    DUP L@  COLOR @ $FF000000 OR  XOR  SWAP L!
  ELSE  IF
    COLOR @ $FF000000 OR  SWAP L!
  ELSE
    0 SWAP L!
  THEN THEN
  ;

DOC" PLOT ( x y -- ) plot one pixel with current ink / COLOR"
: PLOT  ( x y -- )
  WINDOW  PIXEL-ON
  2DUP XY-OK? 0= IF  2DROP EXIT  THEN
  G-DEPTH 1 = IF  (PLOT1)
  ELSE G-DEPTH 8 = IF  (PLOT8)
  ELSE  (PLOT32)
  THEN THEN
  -1 TO G-PDIRTY?  DIRTY
  ;

DOC" UNPLOT ( x y -- ) clear one pixel; restore previous ink"
: UNPLOT  ( x y -- )
  G-INK @ >R  BLACK  PLOT  R> G-INK !
  ;

DOC" POINT-COLOR@ ( x y -- n ) raw pixel: 0/1, index, or $00RRGGBB"
: POINT-COLOR@  ( x y -- n )
  2DUP XY-OK? 0= IF  2DROP 0 EXIT  THEN
  G-DEPTH 1 = IF
    XY>PIX  SWAP C@ AND  0<> ABS
  ELSE G-DEPTH 8 = IF
    XY>ADDR C@
  ELSE
    XY>ADDR L@  $FFFFFF AND
  THEN THEN
  ;

DOC" POINT@ ( x y -- flag ) true if pixel is non-zero / set"
: POINT@  ( x y -- flag )
  POINT-COLOR@ 0<>
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
  [DEFINED] (APP-CBLIT) [IF]
    G-PIX  G-PIXBYTES  G-DEPTH  (APP-CBLIT)
    REFRESH
  [ELSE]
    [DEFINED] (APP-PBLIT) [IF]
      G-PIX  G-PIXBYTES  (APP-PBLIT)
      REFRESH
    [ELSE]
      PIX>CHAR  REFRESH
    [THEN]
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

DOC" POINTS-HELP ( -- ) show point-graphics word summary in the window"
: POINTS-HELP  ( -- )
  WINDOW
  PCLS
  1 1 AT ." Point graphics  (0,0)=bottom-left  "
  G-PX . ." x " G-PY . ."  depth=" G-DEPTH .
  1 3 AT ." 1BIT COLOR8 TRUECOLOR   WHITE BLACK INVERT"
  1 4 AT ." COLOR !  r g b RGB  CBLACK..CWHITE"
  1 5 AT ." x y PLOT  UNPLOT  POINT@  POINT-COLOR@"
  1 6 AT ." x0 y0 x1 y1 LINE   PCLS PREFRESH"
  1 8 AT ." GRAPHICS-PSMOKE  GRAPHICS-CSMOKE"
  PREFRESH
  ;

DOC" GRAPHICS-PSMOKE ( -- ) mono X of lines, prompt, wait for a key"
: GRAPHICS-PSMOKE  ( -- )
  1BIT
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

DOC" GRAPHICS-CSMOKE ( -- ) COLOR8 bar + TRUECOLOR gradient"
: GRAPHICS-CSMOKE  ( -- )
  S" 64Forth COLOR" APP-NAME
  WINDOW
  COLOR8  PCLS  WHITE
  16 0 DO
    I COLOR !
    G-PX 16 / 0 DO
      J G-PX 16 / * I +  0
      OVER  G-PY 2/ 1-  LINE
    LOOP
  LOOP
  2 22 AT ." COLOR8 bar — key → TRUECOLOR"
  PREFRESH  KEY DROP
  TRUECOLOR  PCLS  WHITE
  G-PX 0 DO
    I 255 G-PX */  0  255 I 255 G-PX */ -  RGB COLOR !
    I 0  I G-PY 1-  LINE
  LOOP
  2 22 AT ." TRUECOLOR gradient — any key"
  PREFRESH  KEY DROP
  1BIT
  WINDOW-OFF
  ;

FORTH DEFINITIONS
