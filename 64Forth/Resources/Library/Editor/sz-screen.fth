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
\   row (3+H)          help
\
\ Text body is SZ-TEXT-WIDTH columns (default 80). Gutter/frame are extra.
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

: SZ-SCROLL-UP  ( -- )
   SZ-TOP @ SZ-TBUF = IF  EXIT  THEN
   SZ-TOP @ SZ-PREV-LINE SZ-TOP !
;

: SZ-SCROLL-DOWN  ( -- )
   SZ-TOP @ SZ-NEXT-LINE
   DUP SZ-TEND SZ-U>= IF  DROP EXIT  THEN
   SZ-TOP !
;

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

\ ( n row -- )  right-justified 1-based line number in gutter; n=0 blanks gutter.
: SZ-SHOW-GUTTER  ( n row -- )
   SZ-LN-COL SWAP AT-XY
   DUP 0= IF
      DROP  SZ-LN-WIDTH 0 DO  BL EMIT  LOOP  EXIT
   THEN
   BASE @ SZ-SAVE-BASE !  DECIMAL
   0 <# #S #>                       ( c-addr u )
   SZ-LN-WIDTH OVER - 0 MAX 0 ?DO  BL EMIT  LOOP
   TYPE
   SZ-SAVE-BASE @ BASE !
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

\ Status must fit on one facility row (no wrap). Long paths used to wrap past
\ cols, scroll the facility buffer, wipe the status, and shift the caret down.
: SZ-SHOW-STATUS  ( -- )
   0 SZ-BLANK-ROW
   0 0 AT-XY
   .( SZ-EDITOR )
   SZ-HAS-NAME? IF
      SZ-GET-NAME
      \ keep name short: leave room for " L… C… b/… WxH"
      DUP 28 > IF  DROP 28  THEN
      TYPE
   ELSE
      .( untitled)
   THEN
   SZ-MODIFIED @ IF  .( *)  THEN
   .(  L) SZ-CUR-LINE-NO 0 .R
   .( C) SZ-CUR-COL 1+ 0 .R
   .(  ) SZ-TLEN @ 0 .R .( b)
   .( /) SZ-TBUF-CAP @ 0 .R
   .(  ) SZ-TEXT-WIDTH @ 0 .R .( x) SZ-TEXT-ROWS 0 .R
;

: SZ-SHOW-HELP  ( -- )
   SZ-TEXT-BOT @ 2 + SZ-BLANK-ROW
   0 SZ-TEXT-BOT @ 2 + AT-XY
   \ ASCII only (facility is a byte grid; non-ASCII used to blank the whole help row).
   .( Cmd-S save  Cmd-O open  Cmd-W close | arrows Home/End PgUp/Dn BS Del)
;

\ True if SZ-CUR lies on the logical line starting at `ls`.
\ No return stack — safe to call from inside DO (I is the loop index on R).
VARIABLE SZ-TMP-CUR
: SZ-CUR-ON-LINE  ( ls -- flag )
   SZ-CUR @ SZ-TMP-CUR !
   DUP SZ-NEXT-LINE                     ( ls nx )
   OVER SZ-TMP-CUR @ U> IF  2DROP 0 EXIT  THEN   \ cur < ls
   DUP SZ-TMP-CUR @ U> IF  2DROP -1 EXIT  THEN   \ cur < nx
   \ nx <= cur: still on line if both at TEND
   DUP SZ-TEND =  SZ-TMP-CUR @ SZ-TEND =  AND IF  2DROP -1 EXIT  THEN
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

: SZ-REDRAW  ( -- )
   SZ-ENSURE-VISIBLE
   0 SZ-HAVE-AT !
   PAGE
   SZ-SHOW-STATUS
   SZ-DRAW-FRAME
   \ Line numbers must use a VARIABLE — R@ inside DO is the loop index, not our
   \ counter (old R> 1+ >R produced 2,4,6… and broke the DO frame).
   SZ-TOP @ SZ-LINE-NO SZ-DRAW-LNO !
   SZ-TOP @
   SZ-TEXT-BOT @ 1+ SZ-TEXT-TOP DO
      DUP SZ-TEND SZ-U>= IF
         \ past EOF — blank gutter; still allow cursor on empty TEND line
         0 I SZ-SHOW-GUTTER
         DUP I SZ-NOTE-CUR
      ELSE
         SZ-DRAW-LNO @ I SZ-SHOW-GUTTER
         DUP I SZ-SHOW-LINE
         DUP I SZ-NOTE-CUR
         SZ-NEXT-LINE
         1 SZ-DRAW-LNO +!
      THEN
   LOOP
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
   .( sz-screen: OK) CR
;

\ Sync layout from host settings (default 80×20 text body).
EDIT-WINDOW SZ-APPLY-EDIT-WINDOW
