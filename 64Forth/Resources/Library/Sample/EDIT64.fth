\ EDIT64.fth — slim GRAPHICS text editor for 64Forth + Emitter
\
\ Mini editor on the frozen 80×25 App Output grid (not SZ-EDITOR /
\ Facility). Runs interactively and is meant for EMIT-WINDOW-APP.
\
\ Load:
\   FROMLIB FLOAD Sample/EDIT64.fth
\   EDIT64
\
\ Scriptable:
\   S" notes.txt" ED-LOAD
\   EDIT64
\
\ Emit (fresh session):
\   FROMLIB FLOAD Emitter/emitter.fth
\   FROMLIB FLOAD Sample/EDIT64.fth
\   EMIT-WINDOW-APP EDIT64
\
\ Controls
\   Typing / Enter / Backspace   edit (printable chars insert)
\   Arrows                       move caret
\   Click text                   place caret
\   Scroll wheel                 scroll viewport (ED-TOP)
\   Chrome QUIT / SAVE / OPEN / HELP
\   OPEN                         NSOpenPanel + load (APP-FILE-*)
\   SAVE                         write staged path, or Save panel if none
\   Esc                          quit (S=save D=discard Esc=cancel if dirty)
\   H while help                 dismiss help
\
\ Newlines: load normalizes CRLF/CR to LF (EMIT treats CR as a display CR).
\
\ Public domain.

ANEW EDIT64_MODULE

ONLY FORTH DEFINITIONS
DECIMAL

: ED-CREDIT  ( -- )
  CR ." EDIT64 — GRAPHICS mini-editor sample (not SZ-EDITOR)." CR
  ;

ONLY FORTH ALSO GRAPHICS DEFINITIONS
DECIMAL

\ --- layout -----------------------------------------------------------------
3 CONSTANT ED-TEXT0
G-ROWS ED-TEXT0 - CONSTANT ED-VROWS
48 CONSTANT ED-CHROME-PX          \ top chrome height in pixels

\ Fixed dictionary buffer — avoid ALLOCATE/RESIZE in SA images
\ (libc malloc BL is HOST-APP-bound but still a common flash-on-boot fault).
65536 CONSTANT ED-CAP0
255 CONSTANT ED-NAME-MAX

200 CONSTANT ED-K-UP
208 CONSTANT ED-K-DOWN
203 CONSTANT ED-K-LEFT
205 CONSTANT ED-K-RIGHT
210 CONSTANT ED-K-SCRUP          \ host scroll-wheel up (viewport)
211 CONSTANT ED-K-SCRDN          \ host scroll-wheel down (viewport)

0 CONSTANT ED-M-EDIT
3 CONSTANT ED-M-QUIT
4 CONSTANT ED-M-HELP

VARIABLE ED-DONE?     0 ED-DONE? !
VARIABLE ED-DIRTY?    0 ED-DIRTY? !
VARIABLE ED-MODE      0 ED-MODE !
VARIABLE ED-WASDOWN?  0 ED-WASDOWN? !
VARIABLE ED-LEN       0 ED-LEN !
VARIABLE ED-CUR       0 ED-CUR !
VARIABLE ED-TOP       0 ED-TOP !
VARIABLE ED-NR                       \ normalize read index
VARIABLE ED-NW                       \ normalize write index
VARIABLE ED-PENDING                  \ key pushed back after scroll coalesce
0 ED-PENDING !
VARIABLE ED-FIND-T                   \ caret-row search target (not R: DO uses R)
VARIABLE ED-CC                       \ invert-cell col
VARIABLE ED-CR                       \ invert-cell row

CREATE ED-STORE  ED-CAP0 ALLOT
CREATE ED-PATH    256 ALLOT

: ED-MARK-DIRTY  ( -- )  -1 ED-DIRTY? ! ;
: ED-MARK-CLEAN  ( -- )   0 ED-DIRTY? ! ;

\ --- buffer -----------------------------------------------------------------

: ED-ENSURE  ( need -- flag )
  DUP 0< IF DROP 0 EXIT THEN
  ED-CAP0 > 0=                    \ need <= CAP0
;

\ Do not wipe ED-LEN here — console ED-LOAD may have filled the buffer first.
: ED-BOOT-BUF  ( -- ) ;

: ED-END  ( -- addr )  ED-STORE ED-LEN @ + ;
: ED-AT   ( off -- addr )  ED-STORE + ;

: ED-CLAMP-CUR  ( -- )
  ED-CUR @ 0 MAX ED-LEN @ MIN ED-CUR !
;

\ --- lines ------------------------------------------------------------------
\ Treat LF and CR as end-of-line. After load we normalize CRLF/CR → LF so
\ TYPE never sees raw CR (GRAPHICS EMIT treats CR as a cursor newline and
\ used to paint text several rows below the caret).

: ED-EOL?  ( c -- flag )  DUP 10 = SWAP 13 = OR ;

: ED-LINE-START  ( off -- off' )
  DUP 0= IF EXIT THEN
  BEGIN DUP WHILE
    1- DUP ED-AT C@ ED-EOL? IF 1+ EXIT THEN
  REPEAT
;

: ED-NEXT-EOL  ( off -- off' )
  BEGIN DUP ED-LEN @ < WHILE
    DUP ED-AT C@ ED-EOL? IF EXIT THEN
    1+
  REPEAT
;

: ED-NEXT-LINE  ( off -- off' )
  ED-NEXT-EOL
  DUP ED-LEN @ < IF
    DUP ED-AT C@ 13 = IF 1+ THEN          \ skip CR
    DUP ED-LEN @ < IF
      DUP ED-AT C@ 10 = IF 1+ THEN        \ skip LF (LF or CRLF)
    THEN
  THEN
;

: ED-PREV-LINE  ( off -- off' )
  ED-LINE-START DUP 0= IF EXIT THEN
  1- ED-LINE-START
;

\ In-place CRLF / lone CR → LF so the buffer is LF-only.
: ED-NORMALIZE  ( -- )
  0 ED-NR !  0 ED-NW !
  BEGIN ED-NR @ ED-LEN @ < WHILE
    ED-NR @ ED-AT C@
    DUP 13 = IF
      DROP
      ED-NR @ 1+ DUP ED-LEN @ < IF
        ED-AT C@ 10 = IF
          1 ED-NR +!                      \ skip CR; copy LF next pass
        ELSE
          10 ED-NW @ ED-AT C!
          1 ED-NR +!  1 ED-NW +!
        THEN
      ELSE
        10 ED-NW @ ED-AT C!
        1 ED-NR +!  1 ED-NW +!
      THEN
    ELSE
      ED-NW @ ED-AT C!
      1 ED-NR +!  1 ED-NW +!
    THEN
  REPEAT
  ED-NW @ ED-LEN !
;

: ED-LINE-COL  ( -- n )
  ED-CUR @ DUP ED-LINE-START -
;

: ED-LINE-NO  ( -- n )
  ED-CUR @ ED-LINE-START >R           \ R: target
  0 0                                 ( scan row )
  BEGIN OVER R@ U< WHILE              \ scan < target
    SWAP ED-NEXT-LINE SWAP 1+
  REPEAT
  NIP R> DROP 1+
;

: ED-GOTO-COL  ( off col -- )
  >R DUP ED-NEXT-EOL OVER - R> MIN + ED-CUR !
;

: ED-ENSURE-VISIBLE  ( -- )
  ED-CLAMP-CUR
  ED-CUR @ ED-LINE-START
  DUP ED-TOP @ U< IF ED-TOP ! EXIT THEN
  ED-TOP @ ED-VROWS 0 DO
    DUP ED-CUR @ ED-LINE-START = IF DROP UNLOOP EXIT THEN
    ED-NEXT-LINE
  LOOP DROP
  ED-CUR @ ED-LINE-START
  ED-VROWS 1- 0 DO ED-PREV-LINE LOOP
  ED-TOP !
;

\ --- path -------------------------------------------------------------------

: ED-SET-PATH  ( c-addr u -- )
  ED-NAME-MAX MIN DUP ED-PATH C!
  >R ED-PATH 1+ R@ 0 ?DO OVER C@ OVER C! 1+ SWAP 1+ SWAP LOOP 2DROP R> DROP
;

: ED-GET-PATH  ( -- c-addr u )
  ED-PATH DUP C@ SWAP 1+ SWAP
;
: ED-HAS-PATH?  ( -- flag )  ED-PATH C@ 0<> ;

\ --- edit ops ---------------------------------------------------------------

: ED-OPEN-GAP  ( -- )   \ shift ED-CUR..end one byte right
  ED-LEN @ ED-CUR @ - 0= IF EXIT THEN
  ED-LEN @ 1-
  BEGIN DUP ED-CUR @ >= WHILE
    DUP ED-AT C@  OVER 1+ ED-AT C!
    1-
  REPEAT DROP
;

: ED-INSERT  ( c -- )
  ED-LEN @ 1+ ED-ENSURE 0= IF DROP EXIT THEN
  ED-OPEN-GAP
  ED-CUR @ ED-AT C!
  1 ED-LEN +!  1 ED-CUR +!
  ED-MARK-DIRTY
  ED-ENSURE-VISIBLE
;

: ED-BACKSPACE  ( -- )
  ED-CUR @ 0= IF EXIT THEN
  -1 ED-CUR +!
  ED-CUR @
  BEGIN DUP ED-LEN @ 1- < WHILE
    DUP 1+ ED-AT C@  OVER ED-AT C!
    1+
  REPEAT DROP
  -1 ED-LEN +!
  ED-MARK-DIRTY
  ED-ENSURE-VISIBLE
;

: ED-NEWLINE  ( -- )  10 ED-INSERT ;

: ED-LEFT  ( -- )
  ED-CUR @ IF -1 ED-CUR +! THEN ED-ENSURE-VISIBLE ;
: ED-RIGHT  ( -- )
  ED-CUR @ ED-LEN @ < IF 1 ED-CUR +! THEN ED-ENSURE-VISIBLE ;
: ED-UP  ( -- )
  ED-LINE-COL >R
  ED-CUR @ ED-LINE-START DUP 0= IF DROP R> DROP EXIT THEN
  ED-PREV-LINE R> ED-GOTO-COL ED-ENSURE-VISIBLE ;
: ED-DOWN  ( -- )
  ED-LINE-COL >R
  ED-CUR @ DUP ED-NEXT-LINE
  2DUP = IF 2DROP R> DROP EXIT THEN       \ no further line
  NIP DUP ED-LEN @ > IF DROP R> DROP EXIT THEN
  R> ED-GOTO-COL ED-ENSURE-VISIBLE ;

\ --- redraw -----------------------------------------------------------------

: ED-PUT-LINE  ( row off -- next-off )
  SWAP 0 SWAP AT
  DUP ED-NEXT-EOL OVER - G-COLS MIN >R
  DUP ED-AT R@ TYPE
  G-COLS R> - 0 MAX 0 ?DO BL EMIT LOOP
  ED-NEXT-LINE
;

: ED-.CHROME  ( -- )
  0 0 AT ." QUIT  SAVE  OPEN  HELP"
  0 1 AT
  ED-DIRTY? @ IF [CHAR] * ELSE BL THEN EMIT
  ED-HAS-PATH? IF
    ED-GET-PATH G-COLS 2 - MIN TYPE
  ELSE
    ." (untitled)"
  THEN
  0 2 AT
  ED-MODE @ ED-M-QUIT = IF
    ." Quit: S=save  D=discard  Esc=cancel"
  ELSE
    ." edit  Esc=quit  OPEN=file dialog  SAVE=write"
  THEN
;

\ Viewport row of caret line, or -1 if off-screen.
\ Do NOT keep the target on R across DO/LOOP — DO uses the return stack.
: ED-FIND-CARET-ROW  ( -- row | -1 )
  ED-CUR @ ED-LINE-START ED-FIND-T !
  ED-TOP @ 0                            ( scan row )
  ED-VROWS 0 DO
    OVER ED-FIND-T @ = IF               \ scan == target?
      NIP UNLOOP EXIT                   \ leave row
    THEN
    SWAP ED-NEXT-LINE SWAP 1+
  LOOP
  2DROP -1
;

\ XOR COLOR8 pixels in one character cell (white paper ↔ black).
: ED-INVERT-CELL  ( col row -- )
  ED-CR ! ED-CC !
  G-CELLH 0 DO                          \ J = sy
    G-CELLW 0 DO                        \ I = sx
      ED-CC @ G-CELLW * I +             \ x
      G-PY 1- ED-CR @ G-CELLH * J + -   \ y (PLOT origin)
      2DUP XY-OK? IF
        XY>ADDR DUP C@ CWHITE XOR SWAP C!
      ELSE 2DROP THEN
    LOOP
  LOOP
  -1 TO G-PDIRTY?
;

: ED-CARET-CHAR  ( -- c )
  ED-CUR @ ED-LEN @ < IF ED-CUR @ ED-AT C@ ELSE BL THEN
  DUP 10 = OVER 13 = OR IF DROP BL EXIT THEN
  DUP BL < IF DROP BL THEN
;

\ Reverse-video caret: invert cell paper, then draw the real character
\ (host uses white glyphs on dark COLOR8 paper).
\ AT and ED-INVERT-CELL both want ( col row ).
: ED-PAINT-CARET  ( -- )
  ED-FIND-CARET-ROW DUP 0< IF DROP EXIT THEN
  ED-TEXT0 +                            \ screen row
  ED-LINE-COL G-COLS 1- MIN             \ ( row col )
  SWAP                                  \ ( col row )
  2DUP ED-INVERT-CELL
  AT ED-CARET-CHAR EMIT
;

: ED-REDRAW  ( -- )
  \ Keep white COLOR8 paper (spaces show pixels; host draws black glyphs).
  G-PIX G-PIXBYTES CWHITE FILL
  G-BUF G-COLS G-ROWS * BL FILL
  0 G-CX ! 0 G-CY !
  ED-.CHROME
  ED-MODE @ ED-M-HELP = IF
    4 5 AT ."  EDIT64 — GRAPHICS mini-editor"
    4 7 AT ."  Type to insert; Enter = newline; BS = delete left."
    4 8 AT ."  Arrows move; click places caret; wheel scrolls."
    4 9 AT ."  OPEN = file dialog; SAVE writes (Save As if untitled)."
    4 10 AT ."  Esc quits (S save / D discard). Not SZ-EDITOR."
    4 12 AT ."  Click HELP or press a key to dismiss."
    PREFRESH EXIT
  THEN
  ED-TOP @
  ED-VROWS 0 DO I ED-TEXT0 + SWAP ED-PUT-LINE LOOP
  DROP
  ED-MODE @ ED-M-EDIT = IF ED-PAINT-CARET THEN
  PREFRESH
;

\ Viewport scroll (wheel) — move ED-TOP; drain same-direction wheel keys, one redraw.
\ Non-wheel keys are stashed in ED-PENDING (avoids forward ref to ED-DO-KEY).
: ED-VIEW-UP1  ( -- )
  ED-TOP @ DUP 0= IF DROP EXIT THEN
  ED-PREV-LINE ED-TOP ! ;
: ED-VIEW-DOWN1  ( -- )
  ED-TOP @ ED-NEXT-LINE
  DUP ED-TOP @ = IF DROP EXIT THEN
  DUP ED-LEN @ > IF DROP EXIT THEN
  ED-TOP ! ;
: ED-VIEW-UP  ( -- )
  BEGIN
    ED-VIEW-UP1
    KEY? 0= IF ED-REDRAW EXIT THEN
    KEY DUP ED-K-SCRUP = IF DROP ELSE ED-PENDING ! ED-REDRAW EXIT THEN
  AGAIN ;
: ED-VIEW-DOWN  ( -- )
  BEGIN
    ED-VIEW-DOWN1
    KEY? 0= IF ED-REDRAW EXIT THEN
    KEY DUP ED-K-SCRDN = IF DROP ELSE ED-PENDING ! ED-REDRAW EXIT THEN
  AGAIN ;

\ --- chrome actions ---------------------------------------------------------

\ Host file panels + slurp/spew (no ANS OPEN-FILE in the ED-GRAPH emit reach).
: ED-TAKE-HOST-PATH  ( -- flag )
  ED-PATH 1+ ED-NAME-MAX (APP-FILE-PATH) DUP IF ED-PATH C! -1 ELSE DROP 0 THEN
;

: ED-DO-OPEN  ( -- )
  (APP-FILE-CHOOSE) IF ED-REDRAW EXIT THEN          \ cancel/fail
  ED-TAKE-HOST-PATH DROP
  ED-STORE ED-CAP0 (APP-FILE-SLURP)                 \ u ior
  IF DROP ED-REDRAW EXIT THEN                       \ fail
  ED-LEN !
  ED-NORMALIZE
  0 ED-CUR ! 0 ED-TOP !  ED-MARK-CLEAN
  ED-M-EDIT ED-MODE ! ED-REDRAW
;

: ED-DO-SAVEAS  ( -- )
  (APP-FILE-SAVE-AS) IF ED-REDRAW EXIT THEN
  ED-TAKE-HOST-PATH DROP
  ED-STORE ED-LEN @ (APP-FILE-SPEW)
  IF ED-REDRAW EXIT THEN
  ED-MARK-CLEAN ED-M-EDIT ED-MODE ! ED-REDRAW
;

: ED-DO-SAVE  ( -- )
  ED-HAS-PATH? 0= IF ED-DO-SAVEAS EXIT THEN
  ED-STORE ED-LEN @ (APP-FILE-SPEW)
  DUP 0= IF DROP ED-MARK-CLEAN ED-M-EDIT ED-MODE ! ED-REDRAW EXIT THEN
  \ -1 = host has no staged path (e.g. console ED-LOAD) → Save panel
  -1 = IF ED-DO-SAVEAS ELSE ED-REDRAW THEN
;

: ED-TOGGLE-HELP  ( -- )
  ED-MODE @ ED-M-HELP = IF ED-M-EDIT ELSE ED-M-HELP THEN ED-MODE !
  ED-REDRAW ;
: ED-ASK-QUIT  ( -- )
  ED-DIRTY? @ IF ED-M-QUIT ED-MODE ! ED-REDRAW ELSE -1 ED-DONE? ! THEN ;

: ED-COL-OF  ( x -- col )  G-CELLW / ;

: ED-ROW-OF  ( y -- row )  G-PY 1- SWAP - G-CELLH / ;

\ Only the top label row ("QUIT  SAVE  OPEN  HELP") is clickable.
\ Path / status rows sit in the chrome band too — ignoring Y made
\ clicks on the left of those rows fire QUIT (felt like Esc).
: ED-HIT-CHROME  ( x y -- )
  ED-ROW-OF 0<> IF DROP EXIT THEN       \ not the button row
  ED-COL-OF
  DUP 4 < IF DROP ED-ASK-QUIT EXIT THEN
  DUP 6 < IF DROP EXIT THEN
  DUP 10 < IF DROP ED-DO-SAVE EXIT THEN
  DUP 12 < IF DROP EXIT THEN
  DUP 16 < IF DROP ED-DO-OPEN EXIT THEN
  DUP 18 < IF DROP EXIT THEN
  DUP 22 < IF DROP ED-TOGGLE-HELP EXIT THEN
  DROP
;

: ED-CHROME-Y0  ( -- y )  G-PY ED-CHROME-PX - ;
: ED-IN-CHROME?  ( y -- flag )  ED-CHROME-Y0 >= ;

: ED-CLICK-TEXT  ( x y -- )
  G-PY 1- SWAP - G-CELLH /            ( x srow-from-top )
  ED-TEXT0 - DUP 0< IF 2DROP EXIT THEN
  DUP ED-VROWS >= IF 2DROP EXIT THEN  ( x vrow )
  SWAP G-CELLW /                      ( vrow col )
  ED-TOP @ ROT 0 ?DO ED-NEXT-LINE LOOP
  SWAP ED-GOTO-COL
  ED-ENSURE-VISIBLE ED-REDRAW
;

\ --- keys -------------------------------------------------------------------

: ED-QUIT-KEY  ( c -- )
  DUP [CHAR] s = OVER [CHAR] S = OR IF
    DROP ED-DO-SAVE
    ED-DIRTY? @ 0= IF -1 ED-DONE? ! THEN   \ quit only if save cleared dirty
    EXIT
  THEN
  DUP [CHAR] d = OVER [CHAR] D = OR IF DROP -1 ED-DONE? ! EXIT THEN
  DUP 27 = IF DROP ED-M-EDIT ED-MODE ! ED-REDRAW EXIT THEN
  DROP
;

: ED-EDIT-KEY  ( c -- )
  DUP 27 = IF DROP ED-ASK-QUIT EXIT THEN
  DUP ED-K-LEFT  = IF DROP ED-LEFT  ED-REDRAW EXIT THEN
  DUP ED-K-RIGHT = IF DROP ED-RIGHT ED-REDRAW EXIT THEN
  DUP ED-K-UP    = IF DROP ED-UP    ED-REDRAW EXIT THEN
  DUP ED-K-DOWN  = IF DROP ED-DOWN  ED-REDRAW EXIT THEN
  DUP ED-K-SCRUP = IF DROP ED-VIEW-UP EXIT THEN
  DUP ED-K-SCRDN = IF DROP ED-VIEW-DOWN EXIT THEN
  DUP 13 = OVER 10 = OR IF DROP ED-NEWLINE ED-REDRAW EXIT THEN
  DUP 8 = OVER 127 = OR IF DROP ED-BACKSPACE ED-REDRAW EXIT THEN
  DUP BL < IF DROP EXIT THEN
  DUP 127 > IF DROP EXIT THEN
  ED-INSERT ED-REDRAW
;

: ED-DO-KEY  ( c -- )
  ED-MODE @ ED-M-HELP = IF DROP ED-TOGGLE-HELP EXIT THEN
  ED-MODE @ ED-M-QUIT = IF ED-QUIT-KEY EXIT THEN
  ED-EDIT-KEY
;

: ED-HANDLE-MOUSE  ( x y buttons -- )
  ED-MODE @ ED-M-HELP = IF
    DUP IF DROP 2DROP ED-TOGGLE-HELP ELSE DROP 2DROP THEN EXIT
  THEN
  DUP 1 <> IF DROP 2DROP 0 ED-WASDOWN? ! EXIT THEN
  DROP
  ED-WASDOWN? @ IF 2DROP EXIT THEN
  -1 ED-WASDOWN? !
  DUP ED-IN-CHROME? IF
    ED-HIT-CHROME
    BEGIN (APP-PUMP) G-MOUSE >R 2DROP R> 0= UNTIL
    0 ED-WASDOWN? !
  ELSE
    ED-CLICK-TEXT
  THEN
;

\ --- main -------------------------------------------------------------------

: ED-GRAPH  ( -- )
  DECIMAL
  S" 64Forth EDIT64" APP-NAME
  WINDOW PIXEL-ON COLOR8              \ white paper + black text (host depth 8)
  ED-BOOT-BUF
  ED-M-EDIT ED-MODE !
  0 ED-DONE? !
  0 ED-WASDOWN? !
  0 ED-PENDING !
  ED-REDRAW
  BEGIN ED-DONE? @ 0= WHILE
    (APP-PUMP)
    G-MOUSE ED-HANDLE-MOUSE
    DEPTH IF BEGIN DEPTH WHILE DROP REPEAT THEN
    ED-PENDING @ IF
      ED-PENDING @ 0 ED-PENDING ! ED-DO-KEY
    ELSE KEY? IF KEY ED-DO-KEY THEN THEN
  REPEAT
  1BIT PIXEL-OFF                      \ restore mono kit defaults for next app
  ED-CREDIT
;

\ Console file I/O helpers (File-Access). Not called from ED-GRAPH.
: ED-(LOAD)  ( c-addr u -- ior )
  2DUP ED-SET-PATH
  R/O OPEN-FILE  DUP IF NIP 0 ED-PATH C! EXIT THEN
  DROP >R
  R@ FILE-SIZE ?DUP IF NIP NIP R> CLOSE-FILE DROP 0 ED-PATH C! EXIT THEN
  IF DROP R> CLOSE-FILE DROP -59 0 ED-PATH C! EXIT THEN
  DUP ED-ENSURE 0= IF DROP R> CLOSE-FILE DROP -59 0 ED-PATH C! EXIT THEN
  ED-STORE SWAP R@ READ-FILE
  ?DUP IF R> CLOSE-FILE DROP 0 ED-PATH C! EXIT THEN
  ED-LEN !
  R> CLOSE-FILE DROP
  ED-NORMALIZE
  0 ED-CUR ! 0 ED-TOP !  ED-MARK-CLEAN  0
;

: ED-(SAVE-AS)  ( c-addr u -- ior )
  2DUP ED-SET-PATH
  W/O CREATE-FILE  DUP IF NIP 0 ED-PATH C! EXIT THEN
  DROP >R
  ED-STORE ED-LEN @ R@ WRITE-FILE
  ?DUP IF R> CLOSE-FILE DROP EXIT THEN
  R> CLOSE-FILE
  DUP 0= IF ED-MARK-CLEAN THEN
;

ONLY FORTH DEFINITIONS ALSO GRAPHICS
: EDIT64  ( -- )
  ED-GRAPH
  WINDOW-OFF
  ;
: EDMAIN  ( -- )  EDIT64 ;

\ Single FORTH names — call GRAPHICS helpers (not same-name wrappers).
: ED-LOAD  ( c-addr u -- ior )  ALSO GRAPHICS ED-(LOAD) PREVIOUS ;
: ED-SAVE-AS  ( c-addr u -- ior )  ALSO GRAPHICS ED-(SAVE-AS) PREVIOUS ;

PREVIOUS
CR .( EDIT64 loaded — EDIT64 to run; S" file" ED-LOAD first optional.) CR

