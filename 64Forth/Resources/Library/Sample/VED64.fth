\ VED64.fth — minimal 64Forth port of VED (Tom Zimmer, F-PC / TCOM)
\
\ Reference: Resources/Library/TCOM/VED.FTH
\
\ This cut runs in the App Output window (same grid as EDIT64). It is a
\ line editor over one flat buffer, not the original 40MB swap-file cache.
\ DOS paragraphs (recseg&, @L, cmoveL, ALLOC/SETBLOCK) are cells in a
\ fixed ALLOT buffer. Page records are not kept yet; the status line
\ shows a 512-byte page index so the old page size is still visible.
\
\ Load:
\   FROMLIB FLOAD Sample/VED64.fth
\   VED64
\   S" notes.txt" VED-LOAD     \ optional, before or instead of OPEN
\
\ Window: QUIT SAVE OPEN FIND HELP on the top row.
\   Type / Enter / Backspace    edit
\   Arrows                      move
\   Wheel                       scroll
\   Click                       place caret
\   FIND                        type a string, Enter searches forward
\   Esc                         quit (S=save, D=discard, Esc=cancel)
\
\ Files larger than VED-CAP are truncated on OPEN (host slurps at most
\ VED-CAP bytes). Resizable grid and Emitter stand-alone are later.
\
\ Public domain, same as VED.

ANEW VED64_MODULE

ONLY FORTH DEFINITIONS
DECIMAL

\ --- ANS fallbacks (no-ops when the host already has the word) ----------

[UNDEFINED] /STRING [IF]
: /STRING  ( c-addr u n -- c-addr' u' )
  >R SWAP R@ + SWAP R> -
;
[THEN]

[UNDEFINED] WITHIN [IF]
: WITHIN  ( n lo hi -- flag )   \ lo <= n < hi
  OVER - >R - R> U<
;
[THEN]

[UNDEFINED] SCAN [IF]
: SCAN  ( c-addr u c -- c-addr' u' )
  >R
  BEGIN DUP WHILE
    OVER C@ R@ = IF R> DROP EXIT THEN
    1 /STRING
  REPEAT
  R> DROP
;
[THEN]

[UNDEFINED] BOUNDS [IF]
: BOUNDS  ( c-addr u -- c-addr+u c-addr )  OVER + SWAP ;
[THEN]

\ 64Forth window / file words. Real definitions win; these only exist
\ so the file still compiles on a system that has not loaded GRAPHICS.

[UNDEFINED] APP-NAME [IF]
: APP-NAME  ( c-addr u -- )  2DROP ;
[THEN]
[UNDEFINED] WINDOW [IF]
: WINDOW  ( -- )  ;
[THEN]
[UNDEFINED] WINDOW-OFF [IF]
: WINDOW-OFF  ( -- )  ;
[THEN]
[UNDEFINED] PIXEL-ON [IF]
: PIXEL-ON  ( -- )  ;
[THEN]
[UNDEFINED] PIXEL-OFF [IF]
: PIXEL-OFF  ( -- )  ;
[THEN]
[UNDEFINED] COLOR8 [IF]
: COLOR8  ( -- )  ;
[THEN]
[UNDEFINED] 1BIT [IF]
: 1BIT  ( -- )  ;
[THEN]
[UNDEFINED] (APP-PUMP) [IF]
: (APP-PUMP)  ( -- )  ;
[THEN]
[UNDEFINED] G-MOUSE [IF]
: G-MOUSE  ( -- x y buttons )  0 0 0 ;
[THEN]
[UNDEFINED] (APP-FILE-CHOOSE) [IF]
: (APP-FILE-CHOOSE)  ( -- ior )  -1 ;
[THEN]
[UNDEFINED] (APP-FILE-SAVE-AS) [IF]
: (APP-FILE-SAVE-AS)  ( -- ior )  -1 ;
[THEN]
[UNDEFINED] (APP-FILE-PATH) [IF]
: (APP-FILE-PATH)  ( c-addr max -- n )  2DROP 0 ;
[THEN]
[UNDEFINED] (APP-FILE-SLURP) [IF]
: (APP-FILE-SLURP)  ( c-addr max -- u ior )  2DROP 0 -1 ;
[THEN]
[UNDEFINED] (APP-FILE-SPEW) [IF]
: (APP-FILE-SPEW)  ( c-addr u -- ior )  2DROP -1 ;
[THEN]

\ Defined in FORTH so this hits the console, not the app grid.
: VED-CREDIT  ( -- )
  CR ." VED64 done." CR
;

ONLY FORTH ALSO GRAPHICS DEFINITIONS
DECIMAL

\ --- capacity (cells, not F-PC 16-bit paragraph counts) -----------------

512 CONSTANT VED-PAGE          \ original PAGEBYTES
262144 CONSTANT VED-CAP        \ flat text window (was the page cache)
255 CONSTANT VED-NAME-MAX
48 CONSTANT VED-FIND-MAX
3 CONSTANT VED-TEXT0

200 CONSTANT VED-K-UP
208 CONSTANT VED-K-DOWN
203 CONSTANT VED-K-LEFT
205 CONSTANT VED-K-RIGHT
210 CONSTANT VED-K-SCRUP
211 CONSTANT VED-K-SCRDN

0 CONSTANT VED-M-EDIT
3 CONSTANT VED-M-QUIT
4 CONSTANT VED-M-HELP
5 CONSTANT VED-M-FIND

VARIABLE VED-COLS
VARIABLE VED-ROWS
VARIABLE VED-DONE?
VARIABLE VED-DIRTY?
VARIABLE VED-MODE
VARIABLE VED-WASDOWN?
VARIABLE VED-LEN
VARIABLE VED-CUR
VARIABLE VED-TOP
VARIABLE VED-TRUNC?            \ OPEN hit VED-CAP
VARIABLE VED-PENDING
VARIABLE VED-FIND-T            \ caret search; not held on R across DO
VARIABLE VED-CC
VARIABLE VED-CR
VARIABLE VED-NR
VARIABLE VED-NW

0 VED-PENDING !

CREATE VED-BUF    VED-CAP ALLOT
CREATE VED-PATH   256 ALLOT
CREATE VED-FIND   VED-FIND-MAX 1+ ALLOT

: VED-VROWS  ( -- n )  VED-ROWS @ VED-TEXT0 - 1 MAX ;

\ DOS CODE ROW/COL! read BIOS $40:$4A (cols) and $40:$84 (rows).
\ There is no BIOS area here. The app grid publishes G-COLS and G-ROWS.
\ Call this whenever the window size may have changed.
: ROW/COL!  ( -- )
  G-COLS VED-COLS !
  G-ROWS DUP 24 < IF DROP 25 THEN VED-ROWS !
;

\ Arm64 for Kernel/forth.s — not compiled by this file.
\ High-level ROW/COL! above is the one that runs.
\ Registers follow forth.s: do not clobber x19-x24 or x28.
\ Paste only after G-COLS / G-ROWS have real addresses (they are Forth
\ constants today, both 80 and 25 on the frozen grid).
\
\ // ROW/COL! ( -- )   store grid size; stack unused
\ row_col_bang:
\     mov  w0, #80              // G-COLS
\     adrp x1, ved_cols@PAGE
\     str  x0, [x1, ved_cols@PAGEOFF]
\     mov  w0, #25              // G-ROWS (original forced at least 25)
\     adrp x1, ved_rows@PAGE
\     str  x0, [x1, ved_rows@PAGEOFF]
\     NEXT

: VED-MARK-DIRTY  ( -- )  -1 VED-DIRTY? ! ;
: VED-MARK-CLEAN  ( -- )   0 VED-DIRTY? ! ;

: VED-EOL?  ( c -- flag )  DUP 10 = SWAP 13 = OR ;

: VED-AT  ( off -- addr )  VED-BUF + ;

: VED-LINE-START  ( off -- off' )
  DUP 0= IF EXIT THEN
  BEGIN DUP WHILE
    1- DUP VED-AT C@ VED-EOL? IF 1+ EXIT THEN
  REPEAT
;

: VED-NEXT-EOL  ( off -- off' )
  BEGIN DUP VED-LEN @ < WHILE
    DUP VED-AT C@ VED-EOL? IF EXIT THEN
    1+
  REPEAT
;

: VED-NEXT-LINE  ( off -- off' )
  VED-NEXT-EOL
  DUP VED-LEN @ < IF
    DUP VED-AT C@ 13 = IF 1+ THEN
    DUP VED-LEN @ < IF
      DUP VED-AT C@ 10 = IF 1+ THEN
    THEN
  THEN
;

: VED-PREV-LINE  ( off -- off' )
  VED-LINE-START DUP 0= IF EXIT THEN
  1- VED-LINE-START
;

\ CRLF and lone CR become LF so EMIT does not treat CR as a cursor move.
: VED-NORMALIZE  ( -- )
  0 VED-NR !  0 VED-NW !
  BEGIN VED-NR @ VED-LEN @ < WHILE
    VED-NR @ VED-AT C@
    DUP 13 = IF
      DROP
      VED-NR @ 1+ DUP VED-LEN @ < IF
        VED-AT C@ 10 = IF
          1 VED-NR +!
        THEN
      ELSE DROP THEN
      10 VED-NW @ VED-AT C!
      1 VED-NR +!  1 VED-NW +!
    ELSE
      VED-NW @ VED-AT C!
      1 VED-NR +!  1 VED-NW +!
    THEN
  REPEAT
  VED-NW @ VED-LEN !
;

: VED-LINE-COL  ( -- n )
  VED-CUR @ DUP VED-LINE-START -
;

: VED-LINE-NO  ( -- n )
  VED-CUR @ VED-LINE-START >R
  0 0
  BEGIN OVER R@ U< WHILE
    SWAP VED-NEXT-LINE SWAP 1+
  REPEAT
  NIP R> DROP 1+
;

\ 1-based page using the original 512-byte page, from the byte offset.
: VED-PAGE-NO  ( -- n )
  VED-CUR @ VED-PAGE / 1+
;

: VED-GOTO-COL  ( off col -- )
  >R DUP VED-NEXT-EOL OVER - R> MIN + VED-CUR !
;

: VED-CLAMP  ( -- )
  VED-CUR @ 0 MAX VED-LEN @ MIN VED-CUR !
;

: VED-ENSURE-VISIBLE  ( -- )
  VED-CLAMP
  VED-CUR @ VED-LINE-START
  DUP VED-TOP @ U< IF VED-TOP ! EXIT THEN
  VED-TOP @
  VED-VROWS 0 DO
    DUP VED-CUR @ VED-LINE-START = IF DROP UNLOOP EXIT THEN
    VED-NEXT-LINE
  LOOP DROP
  VED-CUR @ VED-LINE-START
  VED-VROWS 1- 0 ?DO VED-PREV-LINE LOOP
  VED-TOP !
;

: VED-SET-PATH  ( c-addr u -- )
  VED-NAME-MAX MIN DUP VED-PATH C!
  >R VED-PATH 1+ R@ 0 ?DO OVER C@ OVER C! 1+ SWAP 1+ SWAP LOOP 2DROP R> DROP
;
: VED-GET-PATH  ( -- c-addr u )  VED-PATH DUP C@ SWAP 1+ SWAP ;
: VED-HAS-PATH?  ( -- flag )  VED-PATH C@ 0<> ;

: VED-OPEN-GAP  ( -- )
  VED-LEN @ VED-CUR @ - 0= IF EXIT THEN
  VED-LEN @ 1-
  BEGIN DUP VED-CUR @ >= WHILE
    DUP VED-AT C@  OVER 1+ VED-AT C!
    1-
  REPEAT DROP
;

: PAGEINS  ( c -- )
  VED-LEN @ 1+ VED-CAP < 0= IF DROP EXIT THEN
  VED-OPEN-GAP
  VED-CUR @ VED-AT C!
  1 VED-LEN +!  1 VED-CUR +!
  VED-MARK-DIRTY
  VED-ENSURE-VISIBLE
;

: BACKDEL  ( -- )
  VED-CUR @ 0= IF EXIT THEN
  -1 VED-CUR +!
  VED-CUR @
  BEGIN DUP VED-LEN @ 1- < WHILE
    DUP 1+ VED-AT C@  OVER VED-AT C!
    1+
  REPEAT DROP
  -1 VED-LEN +!
  VED-MARK-DIRTY
  VED-ENSURE-VISIBLE
;

: PAGECR  ( -- )  10 PAGEINS ;

: -SCOL  ( -- )
  VED-CUR @ IF -1 VED-CUR +! THEN VED-ENSURE-VISIBLE ;
: +SCOL  ( -- )
  VED-CUR @ VED-LEN @ < IF 1 VED-CUR +! THEN VED-ENSURE-VISIBLE ;

: -SLINE  ( -- )
  VED-LINE-COL >R
  VED-CUR @ VED-LINE-START DUP 0= IF DROP R> DROP EXIT THEN
  VED-PREV-LINE R> VED-GOTO-COL VED-ENSURE-VISIBLE
;
: +SLINE  ( -- )
  VED-LINE-COL >R
  VED-CUR @ DUP VED-NEXT-LINE
  2DUP = IF 2DROP R> DROP EXIT THEN
  NIP DUP VED-LEN @ > IF DROP R> DROP EXIT THEN
  R> VED-GOTO-COL VED-ENSURE-VISIBLE
;

: LHOME  ( -- )  VED-CUR @ VED-LINE-START VED-CUR ! VED-ENSURE-VISIBLE ;
: LEND   ( -- )  VED-CUR @ VED-NEXT-EOL VED-CUR ! VED-ENSURE-VISIBLE ;

: -SCRLLINE  ( -- )
  VED-TOP @ DUP 0= IF DROP EXIT THEN
  VED-PREV-LINE VED-TOP !
;
: +SCRLLINE  ( -- )
  VED-TOP @ VED-NEXT-LINE
  DUP VED-TOP @ = IF DROP EXIT THEN
  DUP VED-LEN @ > IF DROP EXIT THEN
  VED-TOP !
;

\ --- find (forward, case-sensitive) --------------------------------------

: VED-FIND-U  ( -- u )  VED-FIND C@ ;

: VED-MATCH?  ( off -- flag )
  DUP VED-FIND-U + VED-LEN @ > IF DROP 0 EXIT THEN
  VED-FIND 1+ VED-FIND-U
  ROT
  0 ?DO
    OVER I + C@  OVER I + C@ <> IF
      2DROP UNLOOP 0 EXIT
    THEN
  LOOP
  2DROP -1
;

: VED-DO-FIND  ( -- )
  VED-FIND-U 0= IF EXIT THEN
  VED-CUR @ 1+
  BEGIN DUP VED-LEN @ < WHILE
    DUP VED-MATCH? IF VED-CUR ! VED-ENSURE-VISIBLE EXIT THEN
    1+
  REPEAT DROP
;

\ --- draw ----------------------------------------------------------------

: VED-PUT-LINE  ( row off -- next-off )
  SWAP 0 SWAP AT
  DUP VED-NEXT-EOL OVER - VED-COLS @ MIN >R
  DUP VED-AT R@ TYPE
  VED-COLS @ R> - 0 MAX 0 ?DO BL EMIT LOOP
  VED-NEXT-LINE
;

\ <# #> leaves a string. TYPE here is the graphics TYPE, not console U.R.
: VED-.U  ( u -- )
  0 <# #S #> TYPE
;

: VED-.CHROME  ( -- )
  0 0 AT ." QUIT  SAVE  OPEN  FIND  HELP"
  0 1 AT
  VED-DIRTY? @ IF [CHAR] * ELSE BL THEN EMIT
  VED-HAS-PATH? IF
    VED-GET-PATH VED-COLS @ 2 - MIN TYPE
  ELSE
    ." (untitled)"
  THEN
  VED-TRUNC? @ IF ."  [truncated]" THEN
  0 2 AT
  VED-MODE @ VED-M-QUIT = IF
    ." Quit: S=save  D=discard  Esc=cancel"
  ELSE VED-MODE @ VED-M-FIND = IF
    ." Find: " VED-FIND 1+ VED-FIND-U TYPE ." _   Enter=search  Esc=cancel"
  ELSE
    ." L" VED-LINE-NO VED-.U ."  C" VED-LINE-COL 1+ VED-.U
    ."  P" VED-PAGE-NO VED-.U
    ."   Esc=quit  FIND=search"
  THEN THEN
;

: VED-FIND-CARET-ROW  ( -- row | -1 )
  VED-CUR @ VED-LINE-START VED-FIND-T !
  VED-TOP @ 0
  VED-VROWS 0 DO
    OVER VED-FIND-T @ = IF
      NIP UNLOOP EXIT
    THEN
    SWAP VED-NEXT-LINE SWAP 1+
  LOOP
  2DROP -1
;

: VED-INVERT-CELL  ( col row -- )
  VED-CR ! VED-CC !
  G-CELLH 0 DO
    G-CELLW 0 DO
      VED-CC @ G-CELLW * I +
      G-PY 1- VED-CR @ G-CELLH * J + -
      2DUP XY-OK? IF
        XY>ADDR DUP C@ CWHITE XOR SWAP C!
      ELSE 2DROP THEN
    LOOP
  LOOP
  -1 TO G-PDIRTY?
;

: VED-CARET-CHAR  ( -- c )
  VED-CUR @ VED-LEN @ < IF VED-CUR @ VED-AT C@ ELSE BL THEN
  DUP VED-EOL? IF DROP BL EXIT THEN
  DUP BL < IF DROP BL THEN
;

: VED-PAINT-CARET  ( -- )
  VED-FIND-CARET-ROW DUP 0< IF DROP EXIT THEN
  VED-TEXT0 +
  VED-LINE-COL VED-COLS @ 1- MIN
  SWAP
  2DUP VED-INVERT-CELL
  AT VED-CARET-CHAR EMIT
;

: VED-.HELP  ( -- )
  2 4 AT ." VED64 — minimal port of VED"
  2 6 AT ." Type inserts. Enter splits the line. Backspace deletes left."
  2 7 AT ." Arrows move. Wheel scrolls. Click places the caret."
  2 8 AT ." OPEN reads a file (longer than the buffer is truncated)."
  2 9 AT ." SAVE writes it. FIND then Enter searches forward."
  2 10 AT ." Esc quits: S save, D discard, Esc stay."
  2 12 AT ." Not the 40MB swap-file VED. Page size on the status line is"
  2 13 AT ." 512 bytes, counted from the caret, not a disk page cache."
  2 15 AT ." Press a key or click to return."
;

: DOPAGE  ( -- )
  ROW/COL!
  G-PIX G-PIXBYTES CWHITE FILL
  G-BUF G-COLS G-ROWS * BL FILL
  0 G-CX !  0 G-CY !
  VED-.CHROME
  VED-MODE @ VED-M-HELP = IF
    VED-.HELP PREFRESH EXIT
  THEN
  VED-TOP @
  VED-VROWS 0 DO I VED-TEXT0 + SWAP VED-PUT-LINE LOOP
  DROP
  VED-MODE @ VED-M-EDIT = IF VED-PAINT-CARET THEN
  VED-MODE @ VED-M-FIND = IF VED-PAINT-CARET THEN
  PREFRESH
;

\ --- file ------------------------------------------------------------------

: VED-TAKE-PATH  ( -- flag )
  VED-PATH 1+ VED-NAME-MAX (APP-FILE-PATH)
  DUP IF VED-PATH C! -1 ELSE DROP 0 THEN
;

: VED-AFTER-LOAD  ( u -- )
  DUP VED-CAP >= VED-TRUNC? !
  VED-CAP MIN VED-LEN !
  VED-NORMALIZE
  0 VED-CUR !  0 VED-TOP !
  VED-MARK-CLEAN
;

: VED-DO-OPEN  ( -- )
  (APP-FILE-CHOOSE) IF DOPAGE EXIT THEN
  VED-TAKE-PATH DROP
  VED-BUF VED-CAP (APP-FILE-SLURP)
  IF DROP DOPAGE EXIT THEN
  VED-AFTER-LOAD
  VED-M-EDIT VED-MODE ! DOPAGE
;

: VED-DO-SAVEAS  ( -- )
  (APP-FILE-SAVE-AS) IF DOPAGE EXIT THEN
  VED-TAKE-PATH DROP
  VED-BUF VED-LEN @ (APP-FILE-SPEW)
  IF DOPAGE EXIT THEN
  VED-MARK-CLEAN
  VED-M-EDIT VED-MODE ! DOPAGE
;

: VED-DO-SAVE  ( -- )
  VED-HAS-PATH? 0= IF VED-DO-SAVEAS EXIT THEN
  VED-BUF VED-LEN @ (APP-FILE-SPEW)
  DUP 0= IF DROP VED-MARK-CLEAN VED-M-EDIT VED-MODE ! DOPAGE EXIT THEN
  -1 = IF VED-DO-SAVEAS ELSE DOPAGE THEN
;

\ --- keys / mouse ----------------------------------------------------------

: VED-ASK-QUIT  ( -- )
  VED-DIRTY? @ IF VED-M-QUIT VED-MODE ! DOPAGE ELSE -1 VED-DONE? ! THEN
;

: VED-QUIT-KEY  ( c -- )
  DUP [CHAR] s = OVER [CHAR] S = OR IF
    DROP VED-DO-SAVE
    VED-DIRTY? @ 0= IF -1 VED-DONE? ! THEN
    EXIT
  THEN
  DUP [CHAR] d = OVER [CHAR] D = OR IF DROP -1 VED-DONE? ! EXIT THEN
  DUP 27 = IF DROP VED-M-EDIT VED-MODE ! DOPAGE EXIT THEN
  DROP
;

: VED-FIND-KEY  ( c -- )
  DUP 27 = IF DROP VED-M-EDIT VED-MODE ! DOPAGE EXIT THEN
  DUP 13 = OVER 10 = OR IF
    DROP VED-DO-FIND VED-M-EDIT VED-MODE ! DOPAGE EXIT
  THEN
  DUP 8 = OVER 127 = OR IF
    DROP VED-FIND C@ DUP IF 1- VED-FIND C! ELSE DROP THEN DOPAGE EXIT
  THEN
  DUP BL < IF DROP EXIT THEN
  DUP 127 > IF DROP EXIT THEN
  VED-FIND C@ VED-FIND-MAX < IF
    VED-FIND 1+ VED-FIND C@ + C!
    VED-FIND C@ 1+ VED-FIND C!
  ELSE DROP THEN
  DOPAGE
;

: VED-EDIT-KEY  ( c -- )
  DUP 27 = IF DROP VED-ASK-QUIT EXIT THEN
  DUP VED-K-LEFT  = IF DROP -SCOL DOPAGE EXIT THEN
  DUP VED-K-RIGHT = IF DROP +SCOL DOPAGE EXIT THEN
  DUP VED-K-UP    = IF DROP -SLINE DOPAGE EXIT THEN
  DUP VED-K-DOWN  = IF DROP +SLINE DOPAGE EXIT THEN
  DUP VED-K-SCRUP = IF DROP -SCRLLINE DOPAGE EXIT THEN
  DUP VED-K-SCRDN = IF DROP +SCRLLINE DOPAGE EXIT THEN
  DUP 13 = OVER 10 = OR IF DROP PAGECR DOPAGE EXIT THEN
  DUP 8 = OVER 127 = OR IF DROP BACKDEL DOPAGE EXIT THEN
  DUP BL < IF DROP EXIT THEN
  DUP 127 > IF DROP EXIT THEN
  PAGEINS DOPAGE
;

: VED-DO-KEY  ( c -- )
  VED-MODE @ VED-M-HELP = IF DROP VED-M-EDIT VED-MODE ! DOPAGE EXIT THEN
  VED-MODE @ VED-M-QUIT = IF VED-QUIT-KEY EXIT THEN
  VED-MODE @ VED-M-FIND = IF VED-FIND-KEY EXIT THEN
  VED-EDIT-KEY
;

: VED-COL-OF  ( x -- col )  G-CELLW / ;
: VED-ROW-OF  ( y -- row )  G-PY 1- SWAP - G-CELLH / ;

: VED-HIT-CHROME  ( x y -- )
  VED-ROW-OF 0<> IF DROP EXIT THEN
  VED-COL-OF
  DUP 4 < IF DROP VED-ASK-QUIT EXIT THEN
  DUP 6 < IF DROP EXIT THEN
  DUP 10 < IF DROP VED-DO-SAVE EXIT THEN
  DUP 12 < IF DROP EXIT THEN
  DUP 16 < IF DROP VED-DO-OPEN EXIT THEN
  DUP 18 < IF DROP EXIT THEN
  DUP 22 < IF DROP 0 VED-FIND C! VED-M-FIND VED-MODE ! DOPAGE EXIT THEN
  DUP 24 < IF DROP EXIT THEN
  DUP 28 < IF DROP VED-M-HELP VED-MODE ! DOPAGE EXIT THEN
  DROP
;

: VED-CHROME-Y0  ( -- y )  G-PY VED-TEXT0 G-CELLH * - ;
: VED-IN-CHROME?  ( y -- flag )  VED-CHROME-Y0 >= ;

\ G-PY origin is the bottom. Chrome is the top three character rows.
: VED-CLICK-TEXT  ( x y -- )
  VED-ROW-OF VED-TEXT0 -
  DUP 0< IF 2DROP EXIT THEN
  DUP VED-VROWS >= IF 2DROP EXIT THEN
  SWAP VED-COL-OF
  VED-TOP @ ROT 0 ?DO VED-NEXT-LINE LOOP
  SWAP VED-GOTO-COL
  VED-ENSURE-VISIBLE DOPAGE
;

: VED-HANDLE-MOUSE  ( x y buttons -- )
  VED-MODE @ VED-M-HELP = IF
    DUP IF DROP 2DROP VED-M-EDIT VED-MODE ! DOPAGE ELSE DROP 2DROP THEN
    EXIT
  THEN
  DUP 1 <> IF DROP 2DROP 0 VED-WASDOWN? ! EXIT THEN
  DROP
  VED-WASDOWN? @ IF 2DROP EXIT THEN
  -1 VED-WASDOWN? !
  DUP VED-IN-CHROME? IF
    VED-HIT-CHROME
    BEGIN (APP-PUMP) G-MOUSE >R 2DROP R> 0= UNTIL
    0 VED-WASDOWN? !
  ELSE
    VED-CLICK-TEXT
  THEN
;

: VED-GRAPH  ( -- )
  DECIMAL
  S" 64Forth VED64" APP-NAME
  WINDOW PIXEL-ON COLOR8
  ROW/COL!
  VED-M-EDIT VED-MODE !
  0 VED-DONE? !
  0 VED-WASDOWN? !
  0 VED-PENDING !
  DOPAGE
  BEGIN VED-DONE? @ 0= WHILE
    (APP-PUMP)
    G-MOUSE VED-HANDLE-MOUSE
    DEPTH IF BEGIN DEPTH WHILE DROP REPEAT THEN
    VED-PENDING @ IF
      VED-PENDING @ 0 VED-PENDING ! VED-DO-KEY
    ELSE KEY? IF KEY VED-DO-KEY THEN THEN
  REPEAT
  1BIT PIXEL-OFF
  VED-CREDIT
;

\ Console load (File Access). Not used by the window OPEN button.
: VED-(LOAD)  ( c-addr u -- ior )
  2DUP VED-SET-PATH
  R/O OPEN-FILE DUP IF NIP 0 VED-PATH C! EXIT THEN
  DROP >R
  R@ FILE-SIZE ?DUP IF NIP NIP R> CLOSE-FILE DROP 0 VED-PATH C! EXIT THEN
  IF DROP R> CLOSE-FILE DROP -59 0 VED-PATH C! EXIT THEN
  DUP VED-CAP > IF DROP VED-CAP -1 VED-TRUNC? ! ELSE 0 VED-TRUNC? ! THEN
  VED-BUF SWAP R@ READ-FILE
  ?DUP IF R> CLOSE-FILE DROP 0 VED-PATH C! EXIT THEN
  VED-LEN !
  R> CLOSE-FILE DROP
  VED-NORMALIZE
  0 VED-CUR !  0 VED-TOP !  VED-MARK-CLEAN
  0
;

ONLY FORTH DEFINITIONS ALSO GRAPHICS

: VED64  ( -- )
  VED-GRAPH
  WINDOW-OFF
;

: VED-LOAD  ( c-addr u -- ior )
  ALSO GRAPHICS VED-(LOAD) PREVIOUS
;

PREVIOUS
CR .( VED64 loaded — VED64 to edit; S" file" VED-LOAD optional.) CR
