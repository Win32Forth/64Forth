\ sz-edit.fth — SZ-EDITOR interactive loop (Phase 5 navigation)
\
\ Keys (Control = ⌃, not Command/Apple ⌘):
\   printable       insert
\   Enter           CRLF
\   BS              backspace
\   Del / Ctrl-D    delete under cursor
\   arrows          move (host delivers codes 2/6/14/16)
\   Home / Ctrl-A   start of line
\   End  / Ctrl-E   end of line
\   Ctrl-Home       start of file
\   Ctrl-End        end of file
\   PgUp / PgDn     page up / down
\   mouse click     move cursor to cell (Phase 4a, host key 25)
\   Ctrl-S          save
\   Ctrl-Q          quit
\
\ Depends on: sz-host, sz-buffer, sz-screen

DECIMAL

  1 CONSTANT SZ-HOME-LINE      \ Ctrl-A / Home
  2 CONSTANT SZ-LEFT           \ ← arrow (host)
  4 CONSTANT SZ-DEL-FWD        \ Ctrl-D / forward delete
  5 CONSTANT SZ-END-LINE       \ Ctrl-E / End
  6 CONSTANT SZ-RIGHT          \ → arrow (host)
  8 CONSTANT SZ-BS
 10 CONSTANT SZ-LF-KEY
 13 CONSTANT SZ-ENTER
 14 CONSTANT SZ-DOWN           \ ↓ arrow (host)
 16 CONSTANT SZ-UP             \ ↑ arrow (host)
 17 CONSTANT SZ-CTRL-Q
 19 CONSTANT SZ-CTRL-S
 23 CONSTANT SZ-PGUP
 24 CONSTANT SZ-PGDN
 28 CONSTANT SZ-HOME-FILE      \ Ctrl-Home
 29 CONSTANT SZ-END-FILE       \ Ctrl-End
 25 CONSTANT SZ-MOUSE          \ host mouse click in facility (Phase 4a)
 26 CONSTANT SZ-HYPER-PREV     \ Ctrl-PgUp — previous HYPER hit
 27 CONSTANT SZ-HYPER-NEXT     \ Ctrl-PgDn — next HYPER hit
 30 CONSTANT SZ-CMD-OPEN       \ host File→Open while KEY waiting
 31 CONSTANT SZ-CMD-NEW        \ host File→New while KEY waiting
127 CONSTANT SZ-DEL            \ also delete-forward (legacy)

VARIABLE SZ-DONE

\ -----------------------------------------------------------------------------
\ Insert / delete at SZ-CUR
\ -----------------------------------------------------------------------------

\ Open a gap of u bytes at SZ-CUR (MOVE is src dest u).
: SZ-OPEN-HOLE  ( u -- flag )
   DUP 0= IF  DROP -1 EXIT  THEN
   \ Grow capacity if needed (1 MB initial; doubles / expands for paste-sized inserts).
   DUP SZ-TLEN @ + SZ-ENSURE-CAP 0= IF  DROP 0 EXIT  THEN
   >R                                   \ R: gap size
   SZ-TEND SZ-CUR @ -                   \ n = bytes after cursor
   DUP 0> IF
      SZ-CUR @                          ( n src )
      SZ-CUR @ R@ +                     ( n src dest )
      ROT                               ( src dest n )
      MOVE
   ELSE
      DROP
   THEN
   R@ SZ-TLEN +!
   R> DROP
   -1
;

: SZ-INSERT-CH  ( c -- )
   DUP BL < OVER 126 > OR IF  DROP EXIT  THEN
   1 SZ-OPEN-HOLE 0= IF  DROP EXIT  THEN
   SZ-CUR @ C!
   1 SZ-CUR +!
   SZ-CUR-COL SZ-PREF-COL !             \ SZ-PREF-COL lives in sz-screen
   SZ-TOUCH
;

: SZ-INSERT-CRLF  ( -- )
   2 SZ-OPEN-HOLE 0= IF  EXIT  THEN
   SZ-CH-CR SZ-CUR @ C!
   SZ-CH-LF SZ-CUR @ 1+ C!
   2 SZ-CUR +!
   0 SZ-PREF-COL !
   0 SZ-HCOL !
   SZ-TOUCH
;

: SZ-BACKSPACE  ( -- )
   SZ-CUR @ SZ-TBUF = IF  EXIT  THEN
   -1 SZ-CUR +!
   SZ-TEND SZ-CUR @ - 1-
   DUP 0> IF
      SZ-CUR @ 1+  SZ-CUR @  ROT  MOVE
   ELSE
      DROP
   THEN
   -1 SZ-TLEN +!
   SZ-TLEN @ 0< IF  0 SZ-TLEN !  THEN
   SZ-TOUCH
;

\ Delete character(s) under cursor (forward). CRLF pair removed as one unit.
: SZ-DELETE-FWD  ( -- )
   SZ-CUR @ SZ-TEND = IF  EXIT  THEN
   \ CRLF under cursor?
   SZ-CUR @ C@ SZ-CH-CR =
   SZ-CUR @ 1+ SZ-TEND U< AND
   IF
      SZ-CUR @ 1+ C@ SZ-CH-LF = IF
         SZ-TEND SZ-CUR @ - 2 - DUP 0> IF
            SZ-CUR @ 2 +  SZ-CUR @  ROT  MOVE
         ELSE  DROP  THEN
         -2 SZ-TLEN +!
         SZ-TLEN @ 0< IF  0 SZ-TLEN !  THEN
         SZ-TOUCH EXIT
      THEN
   THEN
   \ single byte
   SZ-TEND SZ-CUR @ - 1- DUP 0> IF
      SZ-CUR @ 1+  SZ-CUR @  ROT  MOVE
   ELSE  DROP  THEN
   -1 SZ-TLEN +!
   SZ-TLEN @ 0< IF  0 SZ-TLEN !  THEN
   SZ-TOUCH
;

\ -----------------------------------------------------------------------------
\ Motion only (never mutate buffer)
\ -----------------------------------------------------------------------------

\ Remember preferred column after horizontal motion (not after Up/Down).
: SZ-REMEMBER-COL  ( -- )
   SZ-CUR-COL SZ-PREF-COL !
;

: SZ-GO-LEFT  ( -- )
   \ Use unsigned compare — heap buffer addresses must not use signed >
   SZ-CUR @ SZ-TBUF U> IF  -1 SZ-CUR +!  THEN
   SZ-REMEMBER-COL
;

: SZ-GO-RIGHT  ( -- )
   \ Do not walk past end-of-line into the next line with plain Right
   SZ-CUR @ SZ-CUR-LINE SZ-PARSE-LINE +  ( cur eol-addr )
   < IF  1 SZ-CUR +!  THEN
   SZ-REMEMBER-COL
;

\ Up/Down keep SZ-PREF-COL (sticky column). Do *not* overwrite it with CUR-COL —
\ after horizontal scroll CUR-COL can be huge and then MIN onto a short line is OK,
\ but overwriting PREF from a short line destroyed the goal for the next long line.
: SZ-GO-UP  ( -- )
   SZ-CUR-LINE DUP SZ-TBUF = IF  DROP EXIT  THEN
   SZ-PREV-LINE
   DUP SZ-PARSE-LINE NIP SZ-PREF-COL @ MIN +
   SZ-CUR !
;

: SZ-GO-DOWN  ( -- )
   SZ-CUR-LINE SZ-NEXT-LINE
   DUP SZ-TEND SZ-U>= IF  DROP EXIT  THEN
   DUP SZ-PARSE-LINE NIP SZ-PREF-COL @ MIN +
   SZ-CUR !
;

: SZ-GO-HOME-LINE  ( -- )
   SZ-CUR-LINE SZ-CUR !
   0 SZ-HCOL !
   0 SZ-PREF-COL !
;

\ Jump to true end of line and scroll horizontally so that end is visible.
: SZ-GO-END-LINE  ( -- )
   SZ-CUR-LINE SZ-PARSE-LINE + SZ-CUR !
   SZ-REMEMBER-COL
   SZ-ENSURE-HVISIBLE
;

: SZ-GO-HOME-FILE  ( -- )
   SZ-TBUF SZ-CUR !
   0 SZ-HCOL !
   0 SZ-PREF-COL !
;

\ End of file = end of last *content* line (not a phantom empty row after a final EOL).
: SZ-GO-END-FILE  ( -- )
   SZ-TLEN @ 0= IF  SZ-TBUF SZ-CUR !  0 SZ-HCOL !  0 SZ-PREF-COL !  EXIT  THEN
   SZ-TEND SZ-CUR !
   \ File ends with EOL → CUR-LINE is TEND (empty); sit on previous line's end instead.
   SZ-CUR-LINE SZ-TEND = IF
      SZ-TEND 1- SZ-LINE-START SZ-PARSE-LINE + SZ-CUR !
   THEN
   SZ-REMEMBER-COL
   SZ-ENSURE-HVISIBLE
;

\ Page without DO+R nesting (avoids return-stack clashes with motion).
VARIABLE SZ-PAGE-N
: SZ-PAGE-UP  ( -- )
   SZ-TEXT-ROWS SZ-PAGE-N !
   BEGIN  SZ-PAGE-N @  WHILE
      SZ-GO-UP  -1 SZ-PAGE-N +!
   REPEAT
;

: SZ-PAGE-DOWN  ( -- )
   SZ-TEXT-ROWS SZ-PAGE-N !
   BEGIN  SZ-PAGE-N @  WHILE
      SZ-GO-DOWN  -1 SZ-PAGE-N +!
   REPEAT
;

\ -----------------------------------------------------------------------------
\ Save / quit
\ -----------------------------------------------------------------------------

: SZ-MSG-LINE  ( -- )
   SZ-TEXT-BOT @ 2 + SZ-BLANK-ROW
   0 SZ-TEXT-BOT @ 2 + AT-XY
;

: SZ-DO-SAVE  ( -- )
   SZ-HAS-NAME? 0= IF
      SZ-MSG-LINE
      ." no filename — use SZ-SAVE-AS after quit"
      TERMINAL-REFRESH
      EXIT
   THEN
   SZ-SAVE IF
      SZ-MSG-LINE
      ." SAVE failed"
      TERMINAL-REFRESH
   ELSE
      SZ-MSG-LINE
      ." saved "
      SZ-GET-NAME TYPE
      ."  " SZ-TLEN @ 0 .R ." b"
      TERMINAL-REFRESH
   THEN
;

\ Returns true if the editor should close (Cmd-W / Ctrl-Q / File→Close).
\ Dirty buffer: S = save then close (if save ok); D = discard and close;
\ any other key keeps the editor open.
: SZ-CONFIRM-QUIT  ( -- flag )
   SZ-MODIFIED @ 0= IF  -1 EXIT  THEN
   SZ-MSG-LINE
   ." Modified! Save or Discard? S/D "
   TERMINAL-REFRESH
   KEY 255 AND                           ( c )
   DUP [CHAR] s = OVER [CHAR] S = OR IF
      DROP
      SZ-DO-SAVE
      SZ-MODIFIED @ 0=                   \ close only if save cleared dirty
      EXIT
   THEN
   DUP [CHAR] d = OVER [CHAR] D = OR IF
      DROP
      SZ-CLEAN                           \ discard edits — no "still modified" warning
      -1 EXIT
   THEN
   DROP 0                                \ cancel — stay in editor
;

: SZ-DO-QUIT  ( -- )
   SZ-CONFIRM-QUIT IF
      -1 SZ-DONE !
   ELSE
      \ User cancelled Save/Discard — do not quit the app either
      (SZ-CLR-APP-QUIT)
   THEN
;

\ Host menu / session flags (see TZForth host primitives SZ-HOST-EDITOR-ACTIVE!)
: SZ-EDITOR-ENTER  ( -- )  -1 SZ-HOST-EDITOR-ACTIVE! ;
: SZ-EDITOR-LEAVE  ( -- )   0 SZ-HOST-EDITOR-ACTIVE! ;

\ Menu-injected commands (host provideKey while KEY is waiting; path via SZ-HOST-TAKE-PATH)
: SZ-DO-MENU-OPEN  ( -- )
   SZ-HOST-TAKE-PATH
   DUP 0= IF  2DROP EXIT  THEN
   SZ-LOAD IF  ." SZ-EDITOR: open failed" CR EXIT  THEN
   SZ-VIEW-RESET
;

: SZ-DO-MENU-NEW  ( -- )
   SZ-CLEAR-BUF
   0 SZ-FNAME C!
   SZ-VIEW-RESET
;

\ -----------------------------------------------------------------------------
\ Goto line (must precede SZ-DO-MOUSE / VIEW helpers)
\ -----------------------------------------------------------------------------

\ Lines of context above the target when opening at a line (VIEW / goto).
5 CONSTANT SZ-VIEW-CONTEXT

\ Set SZ-TOP so the cursor line sits ~SZ-VIEW-CONTEXT rows below the top
\ of the text window (not jammed against the bottom).
: SZ-REVEAL-NEAR-TOP  ( -- )
   SZ-CUR @ SZ-LINE-START
   SZ-VIEW-CONTEXT
   BEGIN  DUP WHILE
      OVER SZ-TBUF = IF
         DROP 0
      ELSE
         SWAP SZ-PREV-LINE SWAP 1-
      THEN
   REPEAT
   DROP
   SZ-TOP !
   0 SZ-HCOL !
   0 SZ-PREF-COL !
;

\ Move cursor to 1-based line n (clamped). Start of that line; scroll so
\ the line is near the top of the view (SZ-VIEW-CONTEXT rows down).
\ Stop at EOF if n is past the last line (no DO — safer nested in KEY loop).
: SZ-GOTO-LINE  ( n -- )
   DUP 1 < IF  DROP 1  THEN
   >R                               \ R: target 1-based line
   SZ-TBUF 1                        \ addr cur-line#
   BEGIN
      DUP R@ <
   WHILE
      OVER SZ-TEND SZ-U>= IF
         DROP R> DROP
         SZ-CUR !  SZ-REVEAL-NEAR-TOP EXIT
      THEN
      SWAP SZ-NEXT-LINE SWAP 1+
   REPEAT
   DROP R> DROP
   SZ-CUR !
   SZ-REVEAL-NEAR-TOP
;

\ -----------------------------------------------------------------------------
\ Dispatch
\ -----------------------------------------------------------------------------

\ Facility mouse click → buffer cursor (Phase 4a).
\ Host delivers key 25 then (SZ-CLICK) yields facility col/row (0-based).
: SZ-DO-MOUSE  ( -- )
   (SZ-CLICK) 0= IF  2DROP EXIT  THEN          \ col row
   \ Ignore chrome (status / borders / help)
   DUP SZ-TEXT-TOP < IF  2DROP EXIT  THEN
   DUP SZ-TEXT-BOT @ > IF  2DROP EXIT  THEN
   SWAP                                        \ row col
   DUP SZ-TEXT-LEFT < IF  2DROP EXIT  THEN
   SZ-TEXT-LEFT -                              \ row text-col
   SZ-HCOL @ +                                 \ row buf-col
   SWAP                                        \ buf-col row
   SZ-TEXT-TOP -                               \ buf-col text-row (0-based)
   \ Target 1-based line = line# of SZ-TOP + text-row
   SZ-TOP @ SZ-HOST-LINE-NO +                  \ buf-col line#
   SZ-GOTO-LINE                                \ buf-col  (GOTO resets PREF/HCOL)
   \ Place caret on that line at buf-col (clamped to line length)
   SZ-CUR-LINE SZ-PARSE-LINE NIP               \ buf-col len
   MIN 0 MAX
   SZ-CUR-LINE + SZ-CUR !
   SZ-REMEMBER-COL
   SZ-ENSURE-HVISIBLE
;

\ Phase 5: load path + goto line for HYPER multi-hit ( a u line -- )
\ Do not reference Hyper words here (editor loads before Hyper).
: SZ-HYPER-GOTO  ( c-addr u line -- )
   >R                                 \ R: line  ( a u )
   2DUP SZ-LOAD IF
      R> DROP
      SZ-MSG-LINE
      ." hyper: cannot open "
      TYPE
      TERMINAL-REFRESH
      EXIT
   THEN
   2DROP
   R@ SZ-GOTO-LINE
   SZ-MSG-LINE
   ." hyper " SZ-GET-NAME TYPE ." :" R> 0 .R
   TERMINAL-REFRESH
;

\ Phase 5: Ctrl-PgUp/PgDn → HYPER-PREV / HYPER-NEXT (if Hyper module loaded).
\ ALSO FORTH so FIND sees Hyper words; PREVIOUS restores search order.
: SZ-RUN-FORTH  ( c-addr u -- )
   ALSO FORTH
   PAD PLACE  PAD FIND IF  EXECUTE  ELSE  DROP  THEN
   PREVIOUS ;

: SZ-DO-HYPER-PREV  ( -- )  S" HYPER-PREV" SZ-RUN-FORTH ;
: SZ-DO-HYPER-NEXT  ( -- )  S" HYPER-NEXT" SZ-RUN-FORTH ;

: SZ-HANDLE-KEY  ( c -- )
   255 AND
   DUP SZ-CTRL-Q = IF  DROP SZ-DO-QUIT EXIT  THEN   \ also File→Close / Cmd-W via host
   DUP SZ-CTRL-S = IF  DROP SZ-DO-SAVE EXIT  THEN   \ also File→Save / Cmd-S via host
   DUP SZ-MOUSE = IF  DROP SZ-DO-MOUSE EXIT  THEN
   DUP SZ-HYPER-PREV = IF  DROP SZ-DO-HYPER-PREV EXIT  THEN
   DUP SZ-HYPER-NEXT = IF  DROP SZ-DO-HYPER-NEXT EXIT  THEN
   DUP SZ-CMD-OPEN = IF  DROP SZ-DO-MENU-OPEN EXIT  THEN
   DUP SZ-CMD-NEW = IF  DROP SZ-DO-MENU-NEW EXIT  THEN
   DUP SZ-LEFT = IF  DROP SZ-GO-LEFT EXIT  THEN
   DUP SZ-RIGHT = IF  DROP SZ-GO-RIGHT EXIT  THEN
   DUP SZ-UP = IF  DROP SZ-GO-UP EXIT  THEN
   DUP SZ-DOWN = IF  DROP SZ-GO-DOWN EXIT  THEN
   DUP SZ-HOME-LINE = IF  DROP SZ-GO-HOME-LINE EXIT  THEN
   DUP SZ-END-LINE = IF  DROP SZ-GO-END-LINE EXIT  THEN
   DUP SZ-HOME-FILE = IF  DROP SZ-GO-HOME-FILE EXIT  THEN
   DUP SZ-END-FILE = IF  DROP SZ-GO-END-FILE EXIT  THEN
   DUP SZ-PGUP = IF  DROP SZ-PAGE-UP EXIT  THEN
   DUP SZ-PGDN = IF  DROP SZ-PAGE-DOWN EXIT  THEN
   DUP SZ-BS = IF  DROP SZ-BACKSPACE EXIT  THEN
   DUP SZ-DEL-FWD = IF  DROP SZ-DELETE-FWD EXIT  THEN
   DUP SZ-DEL = IF  DROP SZ-DELETE-FWD EXIT  THEN
   DUP SZ-ENTER = IF  DROP SZ-INSERT-CRLF EXIT  THEN
   DUP SZ-LF-KEY = IF  DROP SZ-INSERT-CRLF EXIT  THEN
   DUP BL < IF  DROP EXIT  THEN
   DUP 127 < IF  SZ-INSERT-CH EXIT  THEN
   DROP
;

\ Core interactive loop; does not reset cursor (caller sets SZ-CUR / view).
: (SZ-EDIT-LOOP)  ( -- )
   0 SZ-DONE !
   SZ-EDITOR-ENTER
   BEGIN
      SZ-DONE @ 0=
   WHILE
      SZ-REDRAW
      SZ-KEY SZ-HANDLE-KEY
   REPEAT
   SZ-EDITOR-LEAVE
   FACILITY-OFF
   CLS
   BEGIN DEPTH WHILE DROP REPEAT
   ." SZ-EDITOR: done" CR
   SZ-MODIFIED @ IF  ." warning: buffer still modified" CR  THEN
   SZ-.INFO
;

: SZ-EDIT-LOOP  ( -- )
   SZ-VIEW-RESET
   (SZ-EDIT-LOOP)
;

: SZ-EDIT-FILE  ( c-addr u -- )
   2DUP SZ-LOAD IF
      ." SZ-EDIT-FILE: load failed: " TYPE CR
      ."   try absolute path, or FROMLIB for Library-relative names" CR
      EXIT
   THEN
   2DROP
   SZ-EDIT-LOOP
;

\ Load path and open editor on 1-based line (for VIEW / hypertext).
: SZ-EDIT-FILE-AT  ( c-addr u line -- )
   >R
   2DUP SZ-LOAD IF
      R> DROP
      ." SZ-EDIT-FILE-AT: load failed: " TYPE CR
      EXIT
   THEN
   2DROP
   R> SZ-GOTO-LINE
   (SZ-EDIT-LOOP)
;

\ Empty untitled buffer and enter the editor (File → New / ⌘N).
: SZ-EDIT-NEW  ( -- )
   SZ-CLEAR-BUF
   0 SZ-FNAME C!
   SZ-EDIT-LOOP
;

\ Host set path, then: SZ-HOST-OPEN-EDIT (File → Open when not already editing).
: SZ-HOST-OPEN-EDIT  ( -- )
   SZ-HOST-TAKE-PATH
   DUP 0= IF  2DROP EXIT  THEN
   SZ-EDIT-FILE
;

\ Parse a path and edit. With FROMLIB on the same console line, relative
\ names resolve under Resources/Library (OPEN-FILE honors FROM-LIBRARY):
\   FROMLIB SZEDIT Editor/SZ-EDITOR-README.txt
\ : SZEDIT  ( -- )  BL WORD COUNT SZ-EDIT-FILE ;
