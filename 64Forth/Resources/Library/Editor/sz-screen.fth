\ sz-screen.fth — SZ-EDITOR mono display / scroll (Phase 5 frame + cursor)
\
\ Uses Facility PAGE/AT-XY/EMIT, then TERMINAL-REFRESH once per frame so the
\ host paints the full screen (PAGE alone must not flush an empty buffer).
\
\ Layout (0-based rows; geometry from SET-EDIT-WINDOW / EDIT-WINDOW settings):
\   row 0              status
\   row 1              top border  +----...----+
\   rows 2..(1+H)      text        |NNNNN|body (W cols)...|
\   row (2+H)          bottom border
\   row (3+H)          help line 1
\   row (4+H)          help line 2
\
\ Text body is SZ-TEXT-WIDTH columns (default 80). Gutter/frame are extra.
\ Facility rows = H + 5 (status, 2 borders, 2 help).
\ User:  width height SET-EDIT-WINDOW   (persists via settings)
\ Query: EDIT-WINDOW  ( -- width height )
\
\ Depends on: sz-host.fth, sz-buffer.fth

DECIMAL

\ Fixed chrome (not changed by SET-EDIT-WINDOW)
   1 CONSTANT SZ-FRAME-TOP
   2 CONSTANT SZ-TEXT-TOP
   1 CONSTANT SZ-LN-COL         \ first column of line-number gutter
   5 CONSTANT SZ-LN-WIDTH       \ digits (right-justified; blank if past EOF)
   6 CONSTANT SZ-LN-SEP         \ column of | between gutter and text
   7 CONSTANT SZ-TEXT-LEFT      \ first column of text body

\ Dynamic geometry (set by SZ-APPLY-EDIT-WINDOW)
VARIABLE SZ-TEXT-WIDTH          \ editable text columns
VARIABLE SZ-TEXT-BOT            \ last text row
VARIABLE SZ-FRAME-BOT           \ bottom border row
VARIABLE SZ-COLS                \ full facility width

\ SZ-CUR / SZ-TOP are defined in sz-buffer.fth (needed by SZ-ENSURE-CAP).

VARIABLE SZ-HCOL                   \ leftmost visible text column (horizontal scroll)
VARIABLE SZ-DRAW-LNO               \ running 1-based line # while painting (not on R stack)
VARIABLE SZ-SAVE-BASE              \ BASE save for gutter (avoid R stack inside DO)

\ ( width height -- )  apply text-body size to layout variables (host has clamped).
: SZ-APPLY-EDIT-WINDOW  ( width height -- )
   SWAP SZ-TEXT-WIDTH !
   SZ-TEXT-TOP + 1- SZ-TEXT-BOT !
   SZ-TEXT-BOT @ 1+ SZ-FRAME-BOT !
   \ cols = TEXT-LEFT + width + 1 (right border) = width + 8
   SZ-TEXT-WIDTH @ SZ-TEXT-LEFT + 1+ SZ-COLS !
;

: SZ-TEXT-ROWS  ( -- n )  SZ-TEXT-BOT @ SZ-TEXT-TOP - 1+ ;

VARIABLE SZ-PREF-COL               \ sticky column for Up/Down (like most editors)

: SZ-VIEW-RESET  ( -- )
   SZ-TBUF DUP SZ-CUR !  SZ-TOP !
   0 SZ-HCOL !
   0 SZ-PREF-COL !
;

: SZ-CUR-COL  ( -- col )
   SZ-CUR @ SZ-LINE-START  SZ-CUR @ SWAP - ;

: SZ-CUR-LINE  ( -- addr )
   SZ-CUR @ SZ-LINE-START ;

\ Length of the logical line containing the cursor (excludes EOL bytes).
: SZ-CUR-LINE-LEN  ( -- n )
   SZ-CUR-LINE SZ-PARSE-LINE NIP ;


: SZ-LINE-STEPS  ( from to -- n )
   SZ-HOST-LINE-STEPS
;

\ 1-based line number — host scan (not STEP-LIMIT-bound Forth loops).
: SZ-LINE-NO  ( line-addr -- n )
   SZ-HOST-LINE-NO ;

: SZ-CUR-LINE-NO  ( -- n )
   SZ-CUR @ SZ-HOST-LINE-NO ;

\ Wheel scroll stubs — redefined in sz-edit.fth so TOP and CUR move together
\ (caret stays on the same screen row; clamped at BOF/EOF).
: SZ-SCROLL-UP    ( -- )  ;
: SZ-SCROLL-DOWN  ( -- )  ;

\ Keep HCOL coherent with the *current* line and caret.
\ Critical: after leaving a very long scrolled line, HCOL can exceed the new
\ line length — then every caret position paints at visual column 0 and motion
\ looks "stuck". Short lines that fit the window always force HCOL = 0.
: SZ-ENSURE-HVISIBLE  ( -- )
   \ ( len width -- flag ) via > 0=  is  len<=width; > consumes both, only flag remains
   SZ-CUR-LINE-LEN  SZ-TEXT-WIDTH @ > 0= IF
      0 SZ-HCOL !  EXIT                 \ whole line fits — no leftover HCOL
   THEN
   SZ-CUR-COL                           \ p
   DUP SZ-HCOL @ < IF                   \ left of window
      SZ-HCOL !  EXIT
   THEN
   \ p is past the last visible column (p - HCOL > WIDTH-1)
   DUP SZ-HCOL @ -  SZ-TEXT-WIDTH @ 1- > IF
      SZ-TEXT-WIDTH @ 1- -  0 MAX  SZ-HCOL !   \ HCOL = p - (WIDTH-1)
   ELSE
      DROP
   THEN
;

\ Keep SZ-CUR's line in the text window. Host computes top so we only scroll
\ when the cursor line is actually outside the [TOP, TOP+ROWS) range — not on
\ every Down (old walk-back logic scrolled too early and broke Up).
: SZ-ENSURE-VISIBLE  ( -- )
   SZ-CUR @  SZ-TOP @  SZ-TEXT-ROWS  SZ-HOST-ENSURE-TOP
   SZ-TOP !
   SZ-ENSURE-HVISIBLE
;

: SZ-BLANK-ROW  ( row -- )
   0 SWAP AT-XY
   SZ-COLS @ 0 DO  BL EMIT  LOOP ;

\ Horizontal rule: +----...----+  (width SZ-COLS)
: SZ-DRAW-HBAR  ( row -- )
   0 SWAP AT-XY
   [CHAR] + EMIT
   SZ-COLS @ 2 - 0 DO  [CHAR] - EMIT  LOOP
   [CHAR] + EMIT
;

: SZ-DRAW-FRAME  ( -- )
   SZ-FRAME-TOP SZ-DRAW-HBAR
   SZ-FRAME-BOT @ SZ-DRAW-HBAR
   SZ-TEXT-BOT @ 1+ SZ-TEXT-TOP DO
      0 I AT-XY  [CHAR] | EMIT
      SZ-LN-SEP I AT-XY  [CHAR] | EMIT
      SZ-COLS @ 1- I AT-XY  [CHAR] | EMIT
   LOOP
;

\ Emit n spaces (no DO — safe inside REDRAW's DO/LOOP).
: SZ-SPACES1  ( n -- )
   BEGIN  DUP 0> WHILE  1- BL EMIT  REPEAT  DROP
;

CREATE SZ-GUT-DIG  8 ALLOT
VARIABLE SZ-GUT-N
VARIABLE SZ-GUT-U

\ ( n row -- )  right-justified line number; n=0 blanks the gutter.
\ /MOD is ( n d -- rem quot ). Store rem as ASCII digit; continue with quot.
: SZ-SHOW-GUTTER  ( n row -- )
   SZ-LN-COL SWAP AT-XY
   DUP 0= IF  DROP SZ-LN-WIDTH SZ-SPACES1 EXIT  THEN
   0 SZ-GUT-N !
   BEGIN  DUP WHILE
      10 /MOD                               \ rem quot
      SWAP [CHAR] 0 +                       \ quot digit
      SZ-GUT-N @ 8 < IF
         SZ-GUT-DIG SZ-GUT-N @ + C!
         1 SZ-GUT-N +!
      ELSE  DROP  THEN
   REPEAT
   DROP
   \ digits LSD-first; emit MSD-first
   SZ-LN-WIDTH SZ-GUT-N @ - 0 MAX SZ-SPACES1
   SZ-GUT-N @
   BEGIN  DUP WHILE
      1-
      DUP SZ-GUT-DIG + C@ EMIT
   REPEAT
   DROP
;

\ Map buffer byte to a single-column glyph (TAB/controls must not reach the host;
\ NSTextView expands TAB and shifts the right border left on long lines).
: SZ-GLYPH  ( c -- c' )
   DUP BL 1- > OVER 127 < AND IF  EXIT  THEN   \ 32..126 keep
   DROP [CHAR] .
;

\ Clear text field + redraw right border for one row (prevents leftover glyphs).
: SZ-CLEAR-TEXT-ROW  ( row -- )
   SZ-TEXT-LEFT OVER AT-XY
   SZ-TEXT-WIDTH @ 0 DO  BL EMIT  LOOP
   SZ-COLS @ 1- SWAP AT-XY  [CHAR] | EMIT
;

\ Paint one text row with horizontal scroll (SZ-HCOL = first visible column).
\ No >R here — REDRAW is inside DO and must not nest return-stack temps.
VARIABLE SZ-SKIP
VARIABLE SZ-PAINTED
: SZ-SHOW-LINE  ( line-addr row -- )
   DUP SZ-CLEAR-TEXT-ROW
   SZ-TEXT-LEFT SWAP AT-XY
   SZ-PARSE-LINE                    ( a u )
   SZ-HCOL @ OVER MIN SZ-SKIP !     ( a u )
   SZ-SKIP @ - 0 MAX                ( a u' )
   SWAP SZ-SKIP @ + SWAP            ( a' u' )
   SZ-TEXT-WIDTH @ MIN
   DUP SZ-PAINTED !
   DUP 0= IF  2DROP EXIT  THEN
   0 DO
      DUP I + C@ SZ-GLYPH EMIT
   LOOP
   DROP
   \ Pad to full TEXT-WIDTH so the border never rides on leftover content
   SZ-TEXT-WIDTH @ SZ-PAINTED @ - 0 MAX 0 ?DO  BL EMIT  LOOP
;

\ Selected word under cursor (click / find). Counted string, max 16 chars.
CREATE SZ-SEL-WORD  18 ALLOT
0 SZ-SEL-WORD C!
\ Find note shown to the right of Selected: (e.g. no next / no prev).
CREATE SZ-FIND-STAT  18 ALLOT
0 SZ-FIND-STAT C!

\ Status must fit on one facility row (no wrap). Long paths used to wrap past
\ cols, scroll the facility buffer, wipe the status, and shift the caret down.
: SZ-SHOW-STATUS  ( -- )
   0 SZ-BLANK-ROW
   0 0 AT-XY
   ." SZ-EDITOR "
   SZ-HAS-NAME? IF
      SZ-GET-NAME
      \ keep name short: leave room for L/C/size + Selected:
      DUP 18 > IF  DROP 18  THEN
      TYPE
   ELSE
      ." untitled"
   THEN
   SZ-MODIFIED @ IF  ." *"  THEN
   ."  L" SZ-CUR-LINE-NO 0 .R
   ."  C" SZ-CUR-COL 1+ 0 .R
   ."  " SZ-TLEN @ 0 .R ." b/"
   SZ-TBUF-CAP @ 0 .R
   ."  " SZ-TEXT-WIDTH @ 0 .R ." x" SZ-TEXT-ROWS 0 .R
   ."  Selected: "
   [CHAR] " EMIT
   SZ-SEL-WORD COUNT TYPE
   [CHAR] " EMIT
   SZ-FIND-STAT C@ IF  SPACE SZ-FIND-STAT COUNT TYPE  THEN
;

\ Two help rows below the bottom border (TEXT-BOT+2 and TEXT-BOT+3).
\ ASCII only — facility is a byte grid.
: SZ-SHOW-HELP  ( -- )
   SZ-TEXT-BOT @ 2 + SZ-BLANK-ROW
   SZ-TEXT-BOT @ 3 + SZ-BLANK-ROW
   0 SZ-TEXT-BOT @ 2 + AT-XY
   ." Cmd-E VIEW word | Cmd-PgUp/Dn Hyper | Cmd-G/arrows find | wheel scroll"
   0 SZ-TEXT-BOT @ 3 + AT-XY
   ." Cmd-X/C/V cut/copy/paste | gutter=line | Cmd-click range | Cmd-S/W save/close"
;

\ True if SZ-CUR lies on the logical line starting at `ls`.
\ No return stack — safe to call from inside DO (I is the loop index on R).
VARIABLE SZ-TMP-CUR
: SZ-CUR-ON-LINE  ( ls -- flag )
   SZ-CUR @ SZ-TMP-CUR !
   DUP SZ-TMP-CUR @ U> IF  DROP 0 EXIT  THEN    \ ls > cur
   DUP SZ-NEXT-LINE                             ( ls nx )
   \ cur < nx → clearly on this line
   DUP SZ-TMP-CUR @ U> IF  2DROP -1 EXIT  THEN
   \ nx <= cur: still on line only if both at TEND (append on last line)
   OVER SZ-TEND =  SZ-TMP-CUR @ SZ-TEND =  AND IF  2DROP -1 EXIT  THEN
   2DROP 0
;

VARIABLE SZ-AT-COL
VARIABLE SZ-AT-ROW
VARIABLE SZ-HAVE-AT

\ Record screen cell for CUR while painting this line (matches what the user sees).
: SZ-NOTE-CUR  ( line-start row -- )
   OVER SZ-CUR-ON-LINE 0= IF  2DROP EXIT  THEN
   ( ls row )
   SWAP  SZ-CUR @ SWAP -                ( row col )  \ col = cur - ls
   SZ-HCOL @ -  0 MAX  SZ-TEXT-WIDTH @ 1- MIN
   SZ-TEXT-LEFT +  SZ-AT-COL !
   SZ-AT-ROW !
   -1 SZ-HAVE-AT !
;

: SZ-PLACE-CURSOR  ( -- )
   SZ-HAVE-AT @ IF
      SZ-AT-COL @ SZ-AT-ROW @ AT-XY
   ELSE
      \ Fallback if CUR not in the window (should be rare after ENSURE-VISIBLE)
      SZ-CUR-COL SZ-HCOL @ -  0 MAX  SZ-TEXT-WIDTH @ 1- MIN
      SZ-TEXT-LEFT +
      SZ-TOP @ SZ-CUR-LINE SZ-LINE-STEPS SZ-TEXT-TOP +
      SZ-TEXT-BOT @ MIN
      AT-XY
   THEN
;

VARIABLE SZ-DID-EMPTY-TEND             \ painted empty append line at TEND once

\ True if buffer ends with EOL (there is an empty line at TEND).
: SZ-ENDS-WITH-EOL  ( -- flag )
   SZ-TEND SZ-TBUF U> IF
      SZ-TEND 1- C@ SZ-CH-LF =
      SZ-TEND 1- C@ SZ-CH-CR = OR
   ELSE  0  THEN
;

VARIABLE SZ-PAINT-ROW                  \ current facility row while painting

: SZ-REDRAW  ( -- )
   SZ-ENSURE-VISIBLE
   0 SZ-HAVE-AT !
   0 SZ-DID-EMPTY-TEND !
   PAGE
   SZ-SHOW-STATUS
   SZ-DRAW-FRAME
   SZ-TOP @ SZ-LINE-NO SZ-DRAW-LNO !
   SZ-TOP @                               \ addr of first visible line
   SZ-TEXT-TOP SZ-PAINT-ROW !
   BEGIN
      SZ-PAINT-ROW @ SZ-TEXT-BOT @ > 0=
   WHILE
      DUP SZ-TEND U< IF
         SZ-DRAW-LNO @ SZ-PAINT-ROW @ SZ-SHOW-GUTTER
         DUP SZ-PAINT-ROW @ SZ-SHOW-LINE
         DUP SZ-PAINT-ROW @ SZ-NOTE-CUR
         SZ-NEXT-LINE
         1 SZ-DRAW-LNO +!
      ELSE
         SZ-DID-EMPTY-TEND @ 0=
         SZ-ENDS-WITH-EOL AND IF
            SZ-DRAW-LNO @ SZ-PAINT-ROW @ SZ-SHOW-GUTTER
            SZ-PAINT-ROW @ SZ-CLEAR-TEXT-ROW
            DUP SZ-PAINT-ROW @ SZ-NOTE-CUR
            1 SZ-DRAW-LNO +!
            -1 SZ-DID-EMPTY-TEND !
         ELSE
            0 SZ-PAINT-ROW @ SZ-SHOW-GUTTER
            SZ-PAINT-ROW @ SZ-CLEAR-TEXT-ROW
         THEN
      THEN
      1 SZ-PAINT-ROW +!
   REPEAT
   DROP
   SZ-SHOW-HELP
   SZ-PLACE-CURSOR
   TERMINAL-REFRESH
;

: SZ-SCREEN-SMOKE  ( -- )
   S" sz-smoke-out.txt" SZ-LOAD DROP
   SZ-VIEW-RESET
   SZ-REDRAW
   KEY DROP
   FACILITY-OFF
   CLS
   ." sz-screen: OK" CR
;

\ Sync layout from host settings (default 80×20 text body).
\ Apply default geometry from EDIT-WINDOW (sz-host variables)
EDIT-WINDOW SZ-APPLY-EDIT-WINDOW

\ Re-bind SET-EDIT-WINDOW so size changes update layout + facility grid
: SET-EDIT-WINDOW  ( width height -- )
   SZ-WIN-H !  SZ-WIN-W !
   SZ-WIN-W @  SZ-WIN-H @  SZ-APPLY-EDIT-WINDOW
   \ Facility chrome: width+8 cols, height+5 rows (status, borders, 2 help)
   SZ-WIN-W @ 8 +  SZ-WIN-H @ 5 +  (FACILITY-SIZE)
;

\ Apply current window size to facility grid at load
SZ-WIN-W @ 8 +  SZ-WIN-H @ 5 +  (FACILITY-SIZE)
