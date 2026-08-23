\ sz-edit.fth — SZ-EDITOR interactive loop (Phase 5 navigation)
\
\ Keys:
\   printable       insert
\   Enter           CRLF
\   BS              backspace
\   Del / Ctrl-D    delete under cursor
\   arrows          move (host delivers codes 2/6/14/16)
\   Home / Ctrl-A   start of line
\   End  / Ctrl-E   end of line
\   Ctrl-Home / Cmd-Home   start of file
\   Ctrl-End  / Cmd-End    end of file
\   PgUp / PgDn     page up / down
\   mouse click     place caret; word under click in status (body)
\   mouse drag      byte-range selection (reverse-video); Cmd-C/X use it
\   double-click    select space-delimited word (reverse-video)
\   triple-click    select whole logical line (reverse-video)
\   Shift-click     extend selection from anchor to click (before or after)
\   Cmd-click       VIEW word under click (same as click + Cmd-E)
\   line# gutter    place caret only (reserved for later: e.g. breakpoints)
\   Cmd-X/C/V       cut / copy / paste
\   Cmd-E           VIEW word under cursor; Cmd-PgUp returns here
\   Cmd-PgUp/PgDn   previous/next Hyper hit
\   Cmd-Left/Right  prev/next occurrence of word under cursor (same file)
\                   assembly (.s/.inc/.asm): identifier bounds (labels / XROT:)
\   Cmd-F           type find string in status Select/Find type-in field
\   click find field  enter/stay find-edit (place caret; sync TOKEN/SEL-WORD); click document → edit
\   Return / ⇧Return  find next / previous (stay in field); Esc or click-out leave
\   Cmd-G / Cmd-→   find next; Cmd-⇧G / Cmd-← find previous
\   Cmd-S / Ctrl-S  save
\   Cmd-W / Ctrl-Q  quit
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
 11 CONSTANT SZ-CUT            \ Cmd-X
 13 CONSTANT SZ-ENTER
 14 CONSTANT SZ-DOWN           \ ↓ arrow (host)
 15 CONSTANT SZ-PASTE          \ Cmd-V
 16 CONSTANT SZ-UP             \ ↑ arrow (host)
 17 CONSTANT SZ-CTRL-Q
 19 CONSTANT SZ-CTRL-S
 22 CONSTANT SZ-COPY           \ Cmd-C
 23 CONSTANT SZ-PGUP
 24 CONSTANT SZ-PGDN
 28 CONSTANT SZ-HOME-FILE      \ Ctrl-Home / Cmd-Home
 29 CONSTANT SZ-END-FILE       \ Ctrl-End / Cmd-End
 18 CONSTANT SZ-VIEW-UNDER     \ Cmd-E — VIEW word under cursor (Hyper)
 20 CONSTANT SZ-FIND-PREV      \ Cmd-Left  — prev occurrence in this buffer
 21 CONSTANT SZ-FIND-NEXT      \ Cmd-Right — next occurrence in this buffer
\ Wheel keys must NOT collide with ASCII Tab (9) or Form Feed (12).
  3 CONSTANT SZ-VSCROLL-UP     \ mouse wheel / trackpad: view earlier lines
  7 CONSTANT SZ-VSCROLL-DN     \ mouse wheel / trackpad: view later lines
  9 CONSTANT SZ-TAB            \ Tab → expand to spaces (SZ-INSERT-TAB)
 12 CONSTANT SZ-HSCROLL-LEFT   \ drag-edge: pan left (SZ-HCOL only)
128 CONSTANT SZ-HSCROLL-RIGHT  \ drag-edge: pan right (SZ-HCOL only)
129 CONSTANT SZ-VIEW-UP        \ drag-edge: pan view up (TOP only, keep selection)
130 CONSTANT SZ-VIEW-DN        \ drag-edge: pan view down (TOP only)
 25 CONSTANT SZ-MOUSE          \ host mouse click in facility (Phase 4a)
 26 CONSTANT SZ-HYPER-PREV     \ Cmd-PgUp — previous HYPER hit
 27 CONSTANT SZ-HYPER-NEXT     \ Cmd-PgDn — next HYPER hit
 30 CONSTANT SZ-CMD-OPEN       \ host File→Open while KEY waiting
 31 CONSTANT SZ-CMD-NEW        \ host File→New while KEY waiting
 35 CONSTANT SZ-CMD-SAVE-AS    \ host Save As panel picked a path
131 CONSTANT SZ-FIND-EDIT-KEY  \ Cmd-F — type find string in status field
132 CONSTANT SZ-SHIFT-ENTER    \ ⇧Return — find previous (while find field open)
133 CONSTANT SZ-CMD-EVAL       \ host command-pane line ready (split console)
127 CONSTANT SZ-DEL            \ also delete-forward (legacy)

VARIABLE SZ-DONE

\ -----------------------------------------------------------------------------
\ Insert / delete at SZ-CUR
\ -----------------------------------------------------------------------------

\ Keep SZ-CUR inside [SZ-TBUF, SZ-TEND] (past-TEND corrupts on insert).
: SZ-CLAMP-CUR  ( -- )
   SZ-CUR @ SZ-TBUF U< IF  SZ-TBUF SZ-CUR !  THEN
   SZ-CUR @ SZ-TEND U> IF  SZ-TEND SZ-CUR !  THEN
;

\ Open a gap of u bytes at SZ-CUR (MOVE is src dest u).
: SZ-OPEN-HOLE  ( u -- flag )
   DUP 0= IF  DROP -1 EXIT  THEN
   SZ-CLAMP-CUR
   \ Grow capacity if needed (1 MB initial; doubles / expands for paste-sized inserts).
   DUP SZ-TLEN @ + SZ-ENSURE-CAP 0= IF  DROP 0 EXIT  THEN
   >R                                   \ R: gap size
   SZ-TEND SZ-CUR @ -                   \ n = bytes after cursor (never negative now)
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

\ Clear active multi-byte selection (motion / plain click / wheel). Paint uses
\ SZ-SEL-OK for reverse-video. Do NOT clear SZ-SEL-WORD — that is the Select/Find
\ type-in field (and stays in sync with SZ-TOKEN). Wheel scroll used to blank the
\ find box because SZ-SCROLL-* call SZ-GO-UP/DOWN → SZ-CLEAR-SEL.
: SZ-CLEAR-SEL  ( -- )
   0 SZ-SEL-OK !
;

: SZ-INSERT-CH  ( c -- )
   DUP BL < OVER 126 > OR IF  DROP EXIT  THEN
   1 SZ-OPEN-HOLE 0= IF  DROP EXIT  THEN
   SZ-CUR @ C!
   1 SZ-CUR +!
   SZ-CUR-COL SZ-PREF-COL !             \ SZ-PREF-COL lives in sz-screen
   SZ-TOUCH
;

\ Tab stop every 4 columns (0, 4, 8, …). Insert spaces up to the next stop.
: SZ-INSERT-TAB  ( -- )
   4  SZ-CUR-COL 4 MOD -                   \ n = 4 - (col mod 4)
   BEGIN  DUP WHILE
      BL SZ-INSERT-CH
      1-
   REPEAT  DROP
;

\ Insert a line break (LF). Cursor must be clamped so we never write past TEND.
\ After insert, CUR sits at the start of the new empty line.
: SZ-INSERT-CRLF  ( -- )
   SZ-CLAMP-CUR
   1 SZ-OPEN-HOLE 0= IF  EXIT  THEN
   SZ-CH-LF SZ-CUR @ C!
   1 SZ-CUR +!
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
   SZ-CLEAR-SEL
   \ Use unsigned compare — heap buffer addresses must not use signed >
   SZ-CUR @ SZ-TBUF U> IF  -1 SZ-CUR +!  THEN
   SZ-REMEMBER-COL
;

: SZ-GO-RIGHT  ( -- )
   SZ-CLEAR-SEL
   \ Advance within the line, including the append point at true EOL (TEND
   \ when the last line has no trailing newline). Do not wrap to next line.
   SZ-CUR @
   SZ-CUR-LINE SZ-PARSE-LINE +              ( cur eol )
   OVER U> IF  DROP 1 SZ-CUR +!  ELSE  2DROP  THEN
   SZ-CLAMP-CUR
   SZ-REMEMBER-COL
;

\ Up/Down keep SZ-PREF-COL (sticky column). Do *not* overwrite it with CUR-COL —
\ after horizontal scroll CUR-COL can be huge and then MIN onto a short line is OK,
\ but overwriting PREF from a short line destroyed the goal for the next long line.
: SZ-GO-UP  ( -- )
   SZ-CLEAR-SEL
   SZ-CUR-LINE DUP SZ-TBUF = IF  DROP EXIT  THEN
   SZ-PREV-LINE
   DUP SZ-PARSE-LINE NIP SZ-PREF-COL @ MIN +
   SZ-CUR !
;

\ True if buffer ends with an EOL byte (empty append line exists at TEND).
: SZ-FILE-ENDS-EOL  ( -- flag )
   SZ-TEND SZ-TBUF U> IF
      SZ-TEND 1- C@ SZ-CH-LF =
      SZ-TEND 1- C@ SZ-CH-CR = OR
   ELSE  0  THEN
;

\ Down one line. Never invents phantom lines past EOF.
: SZ-GO-DOWN  ( -- )
   SZ-CLEAR-SEL
   SZ-CUR @ SZ-TEND = IF  EXIT  THEN       \ already at absolute end
   SZ-CUR-LINE DUP SZ-NEXT-LINE            \ ls nx
   2DUP = IF                               \ cannot advance
      2DROP
      SZ-CUR-LINE SZ-PARSE-LINE + SZ-CUR !
      SZ-CLAMP-CUR SZ-REMEMBER-COL EXIT
   THEN
   NIP                                     \ nx
   DUP SZ-TEND = IF
      SZ-FILE-ENDS-EOL 0= IF
         \ nx is only the append point of this line, not a new line
         DROP
         SZ-CUR-LINE SZ-PARSE-LINE + SZ-CUR !
         SZ-CLAMP-CUR SZ-REMEMBER-COL EXIT
      THEN
      \ Real empty line after final EOL
      SZ-CUR !
      0 SZ-PREF-COL !
      SZ-CLAMP-CUR EXIT
   THEN
   DUP SZ-PARSE-LINE NIP SZ-PREF-COL @ MIN +
   SZ-CUR !
   SZ-CLAMP-CUR
;

\ True if caret can move to a later *line* (not merely EOL on the last line).
: SZ-CUR-CAN-DOWN?  ( -- flag )
   SZ-CUR @ SZ-TEND = IF  0 EXIT  THEN
   SZ-CUR-LINE DUP SZ-NEXT-LINE            \ ls nx
   2DUP = IF  2DROP 0 EXIT  THEN
   NIP
   DUP SZ-TEND = IF
      SZ-FILE-ENDS-EOL 0= IF  DROP 0 EXIT  THEN
   THEN
   DROP -1
;

\ Start of the last logical line (TEND if file ends with EOL → empty append line).
: SZ-LAST-LS  ( -- addr )
   SZ-TLEN @ 0= IF  SZ-TBUF EXIT  THEN
   SZ-FILE-ENDS-EOL IF  SZ-TEND EXIT  THEN
   SZ-TEND 1- SZ-LINE-START
;

\ Wheel only when the file is taller than the text window.
: SZ-WHEEL-SCROLLABLE?  ( -- flag )
   SZ-LINE-COUNT SZ-TEXT-ROWS >
;

\ True if advancing TOP still keeps the last line at/below the bottom row —
\ i.e. last line is still lower than the bottom, so one more line of scroll is OK.
\ When last line is already on the bottom row (or higher), do not scroll further:
\ keep the last line as low on screen as possible.
: SZ-TOP-CAN-DOWN?  ( -- flag )
   SZ-WHEEL-SCROLLABLE? 0= IF  0 EXIT  THEN
   SZ-TOP @ SZ-LAST-LS SZ-LINE-STEPS
   SZ-TEXT-ROWS 1- >
;

\ Wheel: move SZ-TOP and SZ-CUR together so the caret stays on the same screen
\ row while text scrolls under it. No scroll if the file fits in the window.
\ Stop at BOF; stop scroll-down when the last line sits on the bottom row.
: SZ-SCROLL-UP  ( -- )
   SZ-WHEEL-SCROLLABLE? 0= IF  EXIT  THEN
   SZ-CUR-LINE SZ-TBUF = IF  EXIT  THEN    \ caret already at first line
   SZ-TOP @ SZ-TBUF = IF  EXIT  THEN       \ view already at start
   SZ-TOP @ SZ-PREV-LINE SZ-TOP !
   SZ-GO-UP
;

: SZ-SCROLL-DOWN  ( -- )
   SZ-WHEEL-SCROLLABLE? 0= IF  EXIT  THEN
   SZ-TOP-CAN-DOWN? 0= IF  EXIT  THEN      \ last line already as low as possible
   SZ-CUR-CAN-DOWN? 0= IF  EXIT  THEN
   SZ-TOP @ SZ-NEXT-LINE SZ-TOP !
   SZ-GO-DOWN
;

\ View-only pan (do NOT move CUR / clear selection). Drag-edge scroll uses these
\ so the selection free end can re-map to the edge cell after the view moves.
\ Defined after TOP helpers; key dispatch is later (after SZ-DRAG-ACTIVE exists).
4 CONSTANT SZ-HSCROLL-STEP

: SZ-VIEW-LINE-UP  ( -- )
   SZ-TOP @ SZ-TBUF = IF  EXIT  THEN
   SZ-TOP @ SZ-PREV-LINE SZ-TOP !
;

: SZ-VIEW-LINE-DOWN  ( -- )
   SZ-TOP-CAN-DOWN? 0= IF  EXIT  THEN
   SZ-TOP @ SZ-NEXT-LINE SZ-TOP !
;

: SZ-VIEW-COL-LEFT  ( -- )
   SZ-HCOL @ 0= IF  EXIT  THEN
   SZ-HCOL @ SZ-HSCROLL-STEP - 0 MAX SZ-HCOL !
;

: SZ-VIEW-COL-RIGHT  ( -- )
   SZ-HCOL @ SZ-HSCROLL-STEP + 8192 MIN SZ-HCOL !
;

: SZ-GO-HOME-LINE  ( -- )
   SZ-CLEAR-SEL
   SZ-CUR-LINE SZ-CUR !
   0 SZ-HCOL !
   0 SZ-PREF-COL !
;

\ Jump to true end of line and scroll horizontally so that end is visible.
: SZ-GO-END-LINE  ( -- )
   SZ-CLEAR-SEL
   SZ-CUR-LINE SZ-PARSE-LINE + SZ-CUR !
   SZ-REMEMBER-COL
   SZ-ENSURE-HVISIBLE
;

: SZ-GO-HOME-FILE  ( -- )
   SZ-CLEAR-SEL
   SZ-TBUF SZ-CUR !
   0 SZ-HCOL !
   0 SZ-PREF-COL !
;

\ End of file = end of last *content* line (not a phantom empty row after a final EOL).
: SZ-GO-END-FILE  ( -- )
   SZ-CLEAR-SEL
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

\ Temporary message on first help row (restored on next full redraw).
: SZ-MSG-LINE  ( -- )
   SZ-TEXT-BOT @ 2 + SZ-BLANK-ROW
   0 SZ-TEXT-BOT @ 2 + AT-XY
;

: SZ-DO-SAVE  ( -- )
   SZ-HAS-NAME? 0= IF
      (SZ-SAVE-AS-REQ)
      EXIT
   THEN
   SZ-SAVE                       ( ior )
   IF
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

: SZ-DO-SAVE-AS  ( -- )
   SZ-HOST-TAKE-PATH
   DUP 0= IF  2DROP EXIT  THEN
   SZ-ENSURE-FTH
   255 MIN SZ-PATH-TMP SZ-PLACE
   SZ-PATH-TMP COUNT SZ-SAVE-AS     ( ior )
   IF
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

\ -----------------------------------------------------------------------------
\ Centered Save / Discard / Cancel dialog (keyboard + click)
\ -----------------------------------------------------------------------------
VARIABLE SZ-DLG-C0                    \ box left column
VARIABLE SZ-DLG-R0                    \ box top row
VARIABLE SZ-DLG-W
VARIABLE SZ-DLG-H
VARIABLE SZ-DLG-BTN-R                 \ row of clickable buttons
VARIABLE SZ-DLG-S0  VARIABLE SZ-DLG-S1   \ [S] Save  col range [s0,s1)
VARIABLE SZ-DLG-D0  VARIABLE SZ-DLG-D1   \ [D] Discard
VARIABLE SZ-DLG-X0  VARIABLE SZ-DLG-X1   \ [Esc] Cancel

48 CONSTANT SZ-DLG-WIDTH
 7 CONSTANT SZ-DLG-HEIGHT

VARIABLE SZ-DLG-T0
VARIABLE SZ-DLG-T1
VARIABLE SZ-DLG-T2

\ ( row cleft cmid cright -- )  xchars via XEMIT (box-drawing outline)
: SZ-DLG-BORDER-ROW  ( row cleft cmid cright -- )
   SZ-DLG-T2 !  SZ-DLG-T1 !  SZ-DLG-T0 !     \ right mid left
   SZ-DLG-C0 @ SWAP AT-XY
   SZ-DLG-T0 @ XEMIT
   SZ-DLG-W @ 2 - 0 MAX 0 DO  SZ-DLG-T1 @ XEMIT  LOOP
   SZ-DLG-T2 @ XEMIT
;

: SZ-DLG-CLEAR-ROW  ( row -- )
   SZ-DLG-C0 @ SWAP AT-XY
   SZ-BOX-V XEMIT
   SZ-DLG-W @ 2 - 0 MAX 0 DO  BL EMIT  LOOP
   SZ-BOX-V XEMIT
;

: SZ-DRAW-DIRTY-DIALOG  ( -- )
   SZ-DLG-WIDTH SZ-DLG-W !
   SZ-DLG-HEIGHT SZ-DLG-H !
   SZ-TEXT-WIDTH @ SZ-DLG-W @ - 2 / 0 MAX SZ-TEXT-LEFT + SZ-DLG-C0 !
   SZ-TEXT-ROWS SZ-DLG-H @ - 2 / 0 MAX SZ-TEXT-TOP + SZ-DLG-R0 !
   SZ-DLG-R0 @ SZ-BOX-TL SZ-BOX-H SZ-BOX-TR SZ-DLG-BORDER-ROW
   SZ-DLG-R0 @ 1+
   BEGIN  DUP SZ-DLG-R0 @ SZ-DLG-H @ + 1- < WHILE
      DUP SZ-DLG-CLEAR-ROW  1+
   REPEAT  DROP
   SZ-DLG-R0 @ SZ-DLG-H @ + 1- SZ-BOX-BL SZ-BOX-H SZ-BOX-BR SZ-DLG-BORDER-ROW
   SZ-DLG-C0 @ 2 +  SZ-DLG-R0 @ 2 +  AT-XY
   ." Unsaved changes in this file"
   SZ-DLG-R0 @ 4 + SZ-DLG-BTN-R !
   \ [S] Save   [D] Discard   [Esc] Cancel
   SZ-DLG-C0 @ 3 + DUP SZ-DLG-S0 !
   SZ-DLG-BTN-R @ AT-XY  S" [S] Save" TYPE
   SZ-DLG-S0 @ 8 + SZ-DLG-S1 !
   SZ-DLG-S1 @ 3 + DUP SZ-DLG-D0 !
   SZ-DLG-BTN-R @ AT-XY  S" [D] Discard" TYPE
   SZ-DLG-D0 @ 11 + SZ-DLG-D1 !
   SZ-DLG-D1 @ 3 + DUP SZ-DLG-X0 !
   SZ-DLG-BTN-R @ AT-XY  S" [Esc] Cancel" TYPE
   SZ-DLG-X0 @ 12 + SZ-DLG-X1 !
   TERMINAL-REFRESH
;

\ Map click to 0=none 1=save 2=discard 3=cancel
: SZ-DLG-HIT  ( col row -- action )
   SZ-DLG-BTN-R @ <> IF  2DROP 0 EXIT  THEN
   DROP                                       \ col
   DUP SZ-DLG-S0 @ >= OVER SZ-DLG-S1 @ < AND IF  DROP 1 EXIT  THEN
   DUP SZ-DLG-D0 @ >= OVER SZ-DLG-D1 @ < AND IF  DROP 2 EXIT  THEN
   DUP SZ-DLG-X0 @ >= OVER SZ-DLG-X1 @ < AND IF  DROP 3 EXIT  THEN
   DROP 0
;

\ KEY char → action (0=ignore)
: SZ-DLG-KEY  ( c -- action )
   DUP [CHAR] s = OVER [CHAR] S = OR IF  DROP 1 EXIT  THEN
   DUP [CHAR] d = OVER [CHAR] D = OR IF  DROP 2 EXIT  THEN
   DUP 27 = OVER [CHAR] x = OR OVER [CHAR] X = OR IF  DROP 3 EXIT  THEN
   DROP 0
;

\ Read next dialog action (1/2/3). Mouse key 25 uses (SZ-CLICK).
: SZ-DLG-READ  ( -- action )
   BEGIN
      KEY 255 AND
      DUP SZ-CMD-SAVE-AS = IF  EXIT  THEN
      DUP SZ-MOUSE = IF
         DROP
         (SZ-CLICK) 0= IF  DROP 2DROP 0
         ELSE
            \ col row flag — only mouse-down (phase 0)
            DUP 2 RSHIFT 3 AND IF  DROP 2DROP 0
            ELSE  DROP SZ-DLG-HIT  THEN
         THEN
      ELSE
         SZ-DLG-KEY
      THEN
      DUP IF  EXIT  THEN
      DROP
   AGAIN
;

\ True = proceed (buffer is clean: saved or discarded). False = cancel.
: SZ-CONFIRM-DIRTY  ( -- flag )
   SZ-MODIFIED @ 0= IF  -1 EXIT  THEN
   BEGIN
      SZ-DRAW-DIRTY-DIALOG
      SZ-DLG-READ
      DUP SZ-CMD-SAVE-AS = IF
         DROP SZ-DO-SAVE-AS
         SZ-MODIFIED @ 0= IF  -1 EXIT  THEN
      ELSE
      DUP 1 = IF                           \ Save
         DROP SZ-DO-SAVE
         SZ-MODIFIED @ 0= IF  -1 EXIT  THEN
      ELSE DUP 2 = IF                      \ Discard
         DROP SZ-CLEAN  -1 EXIT
      ELSE DUP 3 = IF                      \ Cancel
         DROP 0 EXIT
      ELSE
         DROP
      THEN THEN THEN THEN
   AGAIN
;

\ Returns true if the editor should close (Cmd-W / Ctrl-Q / File→Close).
: SZ-CONFIRM-QUIT  ( -- flag )
   SZ-CONFIRM-DIRTY
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
: SZ-EDITOR-LEAVE  ( -- )
   0 SZ-FIND-EDIT !
   0 SZ-HOST-EDITOR-ACTIVE!
;

\ Hyper multi-hit badge (values live in sz-screen). Defined early so menu open/new
\ can clear the (n/m) status without a forward reference.
: SZ-HYPER-HITS!  ( cur1based tot -- )
   TO SZ-HH-TOT  TO SZ-HH-CUR ;

: SZ-HYPER-HITS-OFF  ( -- )
   0 TO SZ-HH-CUR  0 TO SZ-HH-TOT ;

\ Split command pane: host stages a line and pushes key 133 while KEY waits.
\ EVALUATE runs on the editor Forth thread (not nested host kernel_eval).
\ (SZ-CONSOLE-EMIT) routes TYPE to the lower host pane so the facility grid is clean.
CREATE SZ-CMD-BUF  256 ALLOT

\ Pending xt for DBG: run stepper after the editor is on screen (untitled
\ or VIEW). 0 = none. Cleared before EXECUTE so a THROW cannot re-enter.
VARIABLE SZ-DBG-XT
0 SZ-DBG-XT !

: SZ-DBG-ARM  ( xt -- )  SZ-DBG-XT ! ;

\ Wheel while NEXT is paused (keys 3 / 7). Stay in the stepper.
: DBG-WHEEL  ( c -- )
   DUP 3 = IF  DROP SZ-SCROLL-UP  SZ-REDRAW EXIT  THEN
   DUP 7 = IF  DROP SZ-SCROLL-DOWN SZ-REDRAW EXIT  THEN
   DROP
;
' DBG-WHEEL DBG-WHEEL-XT !

: SZ-DBG-RUN  ( -- )
   SZ-DBG-XT @ DUP 0= IF  DROP EXIT  THEN
   0 SZ-DBG-XT !
   \ Idle-console DBG has no command-pane emit; keep >> lines off the grid.
   -1 (SZ-CONSOLE-EMIT)
   DBG-ON CATCH               ( ior )
   0 (SZ-CONSOLE-EMIT)
   DBG-OFF
   THROW
;

: SZ-DO-CONSOLE-LINE  ( -- )
   SZ-CMD-BUF 255 (SZ-CMD@)                   \ u
   DUP 0= IF  DROP EXIT  THEN
   0 SZ-FIND-EDIT !                           \ leave find-edit if open
   -1 (SZ-CONSOLE-EMIT)                       \ host stream for this command
   SZ-CMD-BUF SWAP                            \ a u
   ['] EVALUATE CATCH DROP                    \ drop 0 or throw code; keep editor usable
   0 (SZ-CONSOLE-EMIT)                        \ flush + stop routing to command pane
   (SZ-CMD-DONE)                              \ host appends ok(n)> on main thread
   SZ-REDRAW                                  \ refresh facility after command I/O
;

\ Menu-injected commands (host provideKey while KEY is waiting; path via SZ-HOST-TAKE-PATH)
\ Cmd-O / File→Open: host shows panel, stages path with (SZ-PATH@), then key 30.
: SZ-DO-MENU-OPEN  ( -- )
   SZ-CONFIRM-DIRTY 0= IF
      \ Discard host-staged path so a cancelled dirty dialog does not leak.
      SZ-PENDING-PATH 511 (SZ-PATH@) DROP
      EXIT
   THEN
   SZ-HOST-TAKE-PATH
   DUP 0= IF  2DROP EXIT  THEN                \ cancelled / no path
   \ Copy off the host staging buffer immediately (stable for LOAD/RECORD).
   255 MIN SZ-PATH-TMP SZ-PLACE
   SZ-PATH-TMP COUNT
   2DUP SZ-LOAD IF
      ." SZ-EDITOR: open failed: " TYPE CR
      2DROP EXIT
   THEN
   2DROP
   SZ-VIEW-RESET
   SZ-HYPER-HITS-OFF
   \ Side list only. Hyper multi-hit ENSURE will re-attach visits when needed.
   SZ-HAS-NAME? IF
      SZ-PATH-TMP COUNT 1 SZ-FL-RECORD
   THEN
;

: SZ-DO-MENU-NEW  ( -- )
   SZ-CONFIRM-DIRTY 0= IF  EXIT  THEN
   SZ-HYPER-HITS-OFF
   SZ-CLEAR-BUF
   0 SZ-FNAME C!
   SZ-VIEW-RESET
;

\ -----------------------------------------------------------------------------
\ Goto line (must precede SZ-DO-MOUSE / VIEW helpers)
\ -----------------------------------------------------------------------------

\ Lines of context above the target when opening at a line (VIEW / Hyper only).
\ Not used for mouse clicks — scrolling under the pointer breaks selection.
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

\ Move cursor to start of 1-based line n (clamped). Does not scroll.
\ Stop at EOF if n is past the last line.
: SZ-GOTO-LINE-RAW  ( n -- )
   DUP 1 < IF  DROP 1  THEN
   >R                               \ R: target 1-based line
   SZ-TBUF 1                        \ addr cur-line#
   BEGIN
      DUP R@ <
   WHILE
      OVER SZ-TEND SZ-U>= IF
         DROP R> DROP
         SZ-CUR ! EXIT
      THEN
      SWAP SZ-NEXT-LINE SWAP 1+
   REPEAT
   DROP R> DROP
   SZ-CUR !
;

\ VIEW / Hyper: go to line and scroll it near the top of the window.
: SZ-GOTO-LINE  ( n -- )
   SZ-GOTO-LINE-RAW
   SZ-REVEAL-NEAR-TOP
;

\ -----------------------------------------------------------------------------
\ Dispatch
\ -----------------------------------------------------------------------------

\ Optional post-click hook (set after SZ-WORD-AT-CUR is defined).
VARIABLE SZ-MOUSE-XT
0 SZ-MOUSE-XT !

\ Selection / clipboard state (byte addresses into SZ-TBUF; end exclusive).
\ SZ-SEL-BEG / SZ-SEL-END / SZ-SEL-OK live in sz-screen (paint needs them).
VARIABLE SZ-ANCHOR-BEG                 \ last plain-click range start
VARIABLE SZ-ANCHOR-END
VARIABLE SZ-CLICK-EXTEND               \ last click was ⌘-click (VIEW)
VARIABLE SZ-CLICK-SHIFT                \ last event had Shift (extend selection)
VARIABLE SZ-CLICK-DBL                  \ last event was double-click
VARIABLE SZ-CLICK-TRI                  \ last event was triple-click (whole line)
VARIABLE SZ-CLICK-ZONE                 \ 0=body 1=line# gutter 2=after-eol
VARIABLE SZ-ANCHOR-LINE                \ nonzero if anchor is whole-line based
VARIABLE SZ-PASTE-WHERE                \ 0=normal 1=before-line 2=after-line
VARIABLE SZ-PASTE-LS                  \ line-start for before/after paste
VARIABLE SZ-PLACEHOLD                  \ nonzero: last click was paste placeholder only
VARIABLE SZ-CLIP-HOLD-U                \ previous solid clip (two-level stack)
VARIABLE SZ-DRAG-START                 \ buffer addr at mouse-down (free end moves from here)
VARIABLE SZ-EXT-ANCHOR                 \ fixed end for shift-extend / after double-click
VARIABLE SZ-DRAG-ACTIVE                \ nonzero while button held
VARIABLE SZ-DRAG-MOVED                 \ nonzero if drag left the start cell
VARIABLE SZ-SEL-DONE                   \ nonzero: selection finished on down (skip plain up)

\ Host click flag: bit0=valid bit1=⌘ bit2-3=phase bit4=⇧ bit5=double bit6=triple.
\ Place caret without scrolling (line is already on-screen under the pointer).
\ zone: 0=body  1=line# gutter (no select; reserved)  2=after last char on line
\
\ Critical: never set CUR to line-start + screen-col when past end-of-line —
\ that walked past SZ-TEND into heap and RETURN wrote garbage into the file.
: SZ-MOUSE-PLACE  ( col row -- )
   0 SZ-CLICK-ZONE !
   DUP SZ-TEXT-TOP < IF  2DROP EXIT  THEN
   DUP SZ-TEXT-BOT @ > IF  2DROP EXIT  THEN
   SWAP                                        \ row col
   DUP 0< IF  2DROP EXIT  THEN
   \ 1-based line# under SZ-TOP for this screen row
   OVER SZ-TEXT-TOP -                          \ row col text-row
   SZ-TOP @ SZ-HOST-LINE-NO +                  \ row col line#
   >R                                          \ row col  R: line
   \ Line-number gutter / '|' — place at line start only (no line-select).
   DUP SZ-TEXT-LEFT < IF
      2DROP
      1 SZ-CLICK-ZONE !
      R@ SZ-GOTO-LINE-RAW                      \ no scroll — keep view still
      SZ-CUR-LINE SZ-CUR !
      SZ-CLAMP-CUR
      SZ-REMEMBER-COL SZ-ENSURE-HVISIBLE
      R> DROP EXIT
   THEN
   \ Right file-list panel: ignore for caret (names later).
   DUP SZ-EDIT-RIGHT > IF
      2DROP R> DROP EXIT
   THEN
   \ Text body column
   SZ-TEXT-LEFT - SZ-HCOL @ +                  \ row buf-col
   NIP                                         \ buf-col
   R@ SZ-GOTO-LINE-RAW                         \ no scroll under mouse
   \ If click row is below last real line, GOTO left us at TEND — stay there.
   SZ-CUR @ SZ-TEND = IF
      DROP                                     \ buf-col
      2 SZ-CLICK-ZONE !
      SZ-CLAMP-CUR
      SZ-REMEMBER-COL SZ-ENSURE-HVISIBLE
      R> DROP EXIT
   THEN
   SZ-CUR-LINE SZ-PARSE-LINE NIP               \ buf-col llen
   2DUP < 0= IF                                \ buf-col >= llen → end of *content*
      NIP                                      \ llen only (never add screen col!)
      SZ-CUR-LINE + SZ-CUR !                   \ true EOL, not "far right on screen"
      2 SZ-CLICK-ZONE !
   ELSE
      MIN 0 MAX
      SZ-CUR-LINE + SZ-CUR !
   THEN
   SZ-CLAMP-CUR
   SZ-REMEMBER-COL SZ-ENSURE-HVISIBLE
   R> DROP
;

\ SZ-DO-MOUSE / drag phases are defined after SZ-DO-VIEW-UNDER (need clip helpers).
\ SZ-HYPER-HITS! / SZ-HYPER-HITS-OFF are defined earlier (before menu open).

\ Phase 5: load path + goto line for HYPER multi-hit ( a u line -- )
\ Do not reference Hyper words here (editor loads before Hyper).
\ Copy path to SZ-PATH-TMP so a/u may safely alias HYPER-HIT across SZ-LOAD.
\ Always register PATH-TMP in the side list after a successful open (not only
\ SZ-FNAME via NOTE-CURRENT) so assembly hits like Library/Sources/forth.s
\ appear and stay highlighted across Cmd-PgUp/PgDn visit navigation.
: SZ-HYPER-GOTO  ( c-addr u line -- )
   >R                                 \ R: line  ( a u )
   255 MIN SZ-PATH-TMP SZ-PLACE
   SZ-PATH-TMP COUNT
   2DUP SZ-LOAD IF
      R> DROP
      SZ-MSG-LINE
      ." hyper: cannot open "
      TYPE
      TERMINAL-REFRESH
      2DROP EXIT
   THEN
   2DROP
   \ Panel rows come from Hyper VTAB rebuild (HYPER-FL-REBUILD). Just go.
   R> SZ-GOTO-LINE
   SZ-REDRAW
;

\ ( -- a u line ) current file path + 1-based line (for Hyper jump stack)
: SZ-HYPER-ORIGIN  ( -- c-addr u line )
   SZ-HAS-NAME? 0= IF  0 0 1 EXIT  THEN
   SZ-GET-NAME
   SZ-CUR-LINE-NO
;

\ Phase 5: Cmd-PgUp/PgDn → HYPER-PREV / HYPER-NEXT (if Hyper module loaded).
\ Hyper words live in HYPER-VOC. Runtime FIND so Editor can load before Hyper.
CREATE SZ-RUN-NAME  64 ALLOT
: SZ-RUN-FORTH  ( c-addr u -- )
   63 MIN SZ-RUN-NAME SZ-PLACE
   S" HYPER-VOC" PAD SZ-PLACE
   PAD FIND 0= IF  DROP EXIT  THEN
   EXECUTE                              \ push HYPER-VOC
   SZ-RUN-NAME FIND IF  EXECUTE  ELSE  DROP  THEN
   PREVIOUS ;

: SZ-DO-HYPER-PREV  ( -- )  S" HYPER-PREV" SZ-RUN-FORTH ;
: SZ-DO-HYPER-NEXT  ( -- )  S" HYPER-NEXT" SZ-RUN-FORTH ;

\ SZ-TOKEN lives in sz-screen (with SZ-SEL-WORD / find status).
VARIABLE SZ-WORD-BEG                   \ inclusive start of word under cursor
VARIABLE SZ-WORD-END                   \ exclusive end of word under cursor

: SZ-BLANK?  ( c -- flag )
   DUP BL = OVER 10 = OR SWAP 13 = OR ;

\ Clamp address into [SZ-TBUF, SZ-TEND].
: SZ-CLIP-ADDR  ( addr -- addr' )
   DUP SZ-TBUF U< IF  DROP SZ-TBUF EXIT  THEN
   DUP SZ-TEND U> IF  DROP SZ-TEND  THEN ;

\ --- Word boundaries: Forth = whitespace; assembly = non-identifier ----------
\ Assembly (.s .S .inc .asm): labels like XROT: and uses like bl XROT / adrp x0,X@page
\ so ":" "@" "," are separators — Cmd-←/→ can find the next label occurrence.
\ "/" is part of the name (SM/REM); spaced "/" between words remains a separator
\ only when not adjacent to identifier chars on both sides (word expand is greedy).

: SZ-CH-UPC  ( c -- c' )
   DUP [CHAR] a [CHAR] z 1+ WITHIN IF  32 -  THEN ;

\ Current path ends with .s / .S / .inc / .INC / .asm / .ASM?
: SZ-ASM-FILE?  ( -- flag )
   SZ-HAS-NAME? 0= IF  FALSE EXIT  THEN
   SZ-GET-NAME 2>R                          \ R: a u (u = R-TOS)
   R@ 2 < IF  2R> 2DROP FALSE EXIT  THEN
   \ .s / .S  (any path whose last two chars are .s)
   2R@ + 2 - C@ [CHAR] . =
   2R@ + 1 - C@ SZ-CH-UPC [CHAR] S = AND IF
      2R> 2DROP TRUE EXIT
   THEN
   R@ 4 < IF  2R> 2DROP FALSE EXIT  THEN
   2R@ + 4 - C@ [CHAR] . <> IF  2R> 2DROP FALSE EXIT  THEN
   \ .inc
   2R@ + 3 - C@ SZ-CH-UPC [CHAR] I =
   2R@ + 2 - C@ SZ-CH-UPC [CHAR] N = AND
   2R@ + 1 - C@ SZ-CH-UPC [CHAR] C = AND IF
      2R> 2DROP TRUE EXIT
   THEN
   \ .asm
   2R@ + 3 - C@ SZ-CH-UPC [CHAR] A =
   2R@ + 2 - C@ SZ-CH-UPC [CHAR] S = AND
   2R@ + 1 - C@ SZ-CH-UPC [CHAR] M = AND IF
      2R> 2DROP TRUE EXIT
   THEN
   2R> 2DROP FALSE ;

\ Identifier char for assembly labels / symbols (not "@" — Mach-O @page suffix).
\ Include '/' so Forth kernel names like SM/REM stay one token (spaces still
\ separate "bl XROT / adrp" when '/' is spaced).
: SZ-ASM-NAME-CHAR?  ( c -- flag )
   DUP [CHAR] 0 [CHAR] 9 1+ WITHIN IF  DROP TRUE EXIT  THEN
   DUP [CHAR] A [CHAR] Z 1+ WITHIN IF  DROP TRUE EXIT  THEN
   DUP [CHAR] a [CHAR] z 1+ WITHIN IF  DROP TRUE EXIT  THEN
   DUP [CHAR] _ = IF  DROP TRUE EXIT  THEN
   DUP [CHAR] . = IF  DROP TRUE EXIT  THEN
   DUP [CHAR] $ = IF  DROP TRUE EXIT  THEN
   DUP [CHAR] / = IF  DROP TRUE EXIT  THEN
   DROP FALSE ;

\ True if c ends a "word" for expand/search (separator).
: SZ-WORD-SEP?  ( c -- flag )
   SZ-ASM-FILE? IF
      SZ-ASM-NAME-CHAR? 0=
   ELSE
      SZ-BLANK?
   THEN ;

\ Character to expand from when caret may be mid-word, on a sep, or at EOL:
\ prefer non-separator at SZ-CUR; else non-separator immediately before.
\ ( -- addr | 0 )
: SZ-WORD-ANCHOR  ( -- addr|0 )
   SZ-CUR @ SZ-CLIP-ADDR
   DUP SZ-TEND SZ-U>= IF
      DROP
      SZ-CUR @ SZ-TBUF U> IF
         SZ-CUR @ 1- DUP C@ SZ-WORD-SEP? IF  DROP 0  THEN
      ELSE  0  THEN
      EXIT
   THEN
   DUP C@ SZ-WORD-SEP? 0= IF  EXIT  THEN          \ mid/start of word
   \ On separator: use previous non-separator if any
   DUP SZ-TBUF = IF  DROP 0 EXIT  THEN
   1-
   DUP C@ SZ-WORD-SEP? IF  DROP 0 EXIT  THEN ;

\ Expand anchor to full word [beg,end) and copy into SZ-TOKEN.
\ Forth: whitespace-delimited.  Assembly: identifier run (so XROT: → XROT).
\ ( -- c-addr u )
: SZ-WORD-AT-CUR  ( -- c-addr u )
   0 SZ-TOKEN C!
   SZ-TBUF SZ-WORD-BEG !
   SZ-TBUF SZ-WORD-END !
   SZ-WORD-ANCHOR DUP 0= IF  DROP SZ-TOKEN COUNT EXIT  THEN
   \ walk left → inclusive start
   BEGIN
      DUP SZ-TBUF = IF  TRUE
      ELSE  DUP 1- C@ SZ-WORD-SEP? IF  TRUE
      ELSE  1- FALSE  THEN THEN
   UNTIL                                          \ beg
   DUP SZ-WORD-BEG !
   \ walk right → exclusive end
   BEGIN
      DUP SZ-TEND SZ-U>= IF  TRUE
      ELSE  DUP C@ SZ-WORD-SEP? IF  TRUE
      ELSE  1+ FALSE  THEN THEN
   UNTIL                                          \ end
   DUP SZ-WORD-END !
   SZ-WORD-BEG @ - 63 MIN                         \ len
   DUP 0= IF  DROP SZ-TOKEN COUNT EXIT  THEN
   DUP SZ-TOKEN C!
   SZ-WORD-BEG @  SZ-TOKEN 1+  ROT  CMOVE
   SZ-TOKEN COUNT ;

\ Status helpers (SZ-SEL-WORD / SZ-FIND-STAT live in sz-screen — defined first).
: SZ-FIND-CLEAR-STAT  ( -- )  0 SZ-FIND-STAT C! ;

: SZ-FIND-SET-STAT  ( c-addr u -- )
   16 MIN
   DUP SZ-FIND-STAT C!
   DUP 0= IF  2DROP EXIT  THEN
   >R SZ-FIND-STAT 1+ R> CMOVE
;

\ Copy word under SZ-CUR into SZ-SEL-WORD and SZ-TOKEN (find field source).
: SZ-UPDATE-SEL-WORD  ( -- )
   SZ-FIND-CLEAR-STAT
   SZ-WORD-AT-CUR                              \ fills TOKEN; a u
   63 MIN SZ-SEL-TEXT-MAX MIN
   DUP SZ-SEL-WORD C!
   DUP 0= IF  2DROP EXIT  THEN
   >R SZ-SEL-WORD 1+ R> CMOVE
;

\ Word or point range at current CUR → ( beg end ).  Point if no word.
: SZ-RANGE-AT-CUR  ( -- beg end )
   SZ-WORD-AT-CUR DUP IF
      2DROP SZ-WORD-BEG @ SZ-WORD-END @
   ELSE
      2DROP SZ-CUR @ DUP
   THEN
;

\ Show [beg,end) text in Select/Find field and seed SZ-TOKEN for find-edit.
: SZ-SHOW-RANGE-SEL  ( beg end -- )
   2DUP U> IF  SWAP  THEN                  \ beg end
   OVER - 0 MAX 63 MIN SZ-SEL-TEXT-MAX MIN \ beg u
   DUP SZ-SEL-WORD C!
   DUP SZ-TOKEN C!
   DUP 0= IF  2DROP EXIT  THEN
   >R                                       \ beg  R:u
   DUP SZ-SEL-WORD 1+ R@ CMOVE
   DUP SZ-TOKEN 1+ R@ CMOVE
   DROP R> DROP
;

\ Internal clip (also synced to host/system pasteboard via (SZ-CLIP!)).
\ Two-level: SZ-CLIP = current solid; SZ-CLIP-HOLD = previous solid.
65536 CONSTANT SZ-CLIP-MAX
CREATE SZ-CLIP  SZ-CLIP-MAX ALLOT
CREATE SZ-CLIP-HOLD  SZ-CLIP-MAX ALLOT
VARIABLE SZ-CLIP-U
VARIABLE SZ-CLIP-HOLD-U
0 SZ-CLIP-U !
0 SZ-CLIP-HOLD-U !

\ Whole line containing CUR: [line-start, next-line-start)
: SZ-LINE-RANGE-AT-CUR  ( -- beg end )
   SZ-CUR-LINE DUP SZ-NEXT-LINE
;

\ Push current solid clip down; store [beg,end) as new solid + host pasteboard.
: SZ-CLIP-STORE  ( beg end -- )
   \ demote current solid → hold
   SZ-CLIP-U @ IF
      SZ-CLIP SZ-CLIP-HOLD SZ-CLIP-U @ CMOVE
      SZ-CLIP-U @ SZ-CLIP-HOLD-U !
   THEN
   2DUP U> IF  SWAP  THEN                  \ beg end
   OVER - 0 MAX SZ-CLIP-MAX MIN            \ beg u
   DUP SZ-CLIP-U !
   DUP IF  >R SZ-CLIP R@ CMOVE R> DROP  ELSE  2DROP  THEN
   SZ-CLIP SZ-CLIP-U @ (SZ-CLIP!)
   0 SZ-PLACEHOLD !
   0 SZ-PASTE-WHERE !
;

: SZ-SET-SEL  ( beg end -- )
   2DUP U> IF  SWAP  THEN
   2DUP SZ-SEL-END ! SZ-SEL-BEG !
   -1 SZ-SEL-OK !
   2DUP SZ-CLIP-STORE
   SZ-SHOW-RANGE-SEL
;

: SZ-SET-ANCHOR-FROM-CUR  ( -- )
   SZ-RANGE-AT-CUR SZ-ANCHOR-END ! SZ-ANCHOR-BEG !
   0 SZ-ANCHOR-LINE !
;

: SZ-SET-LINE-ANCHOR  ( -- )
   SZ-LINE-RANGE-AT-CUR SZ-ANCHOR-END ! SZ-ANCHOR-BEG !
   -1 SZ-ANCHOR-LINE !
;

\ Placeholder click: keep solid clip; mark paste target only.
\ Never copy line/document text into the find type-in field (SZ-SEL-WORD).
: SZ-PLACEHOLDER-CLICK  ( -- )
   -1 SZ-PLACEHOLD !
   0 SZ-SEL-OK !
   0 SZ-SEL-WORD C!
   SZ-FIND-CLEAR-STAT
   SZ-LINE-RANGE-AT-CUR                    \ beg end (for paste locus)
   SZ-CLICK-ZONE @ 2 = IF
      2 SZ-PASTE-WHERE !                   \ after this line
      NIP SZ-PASTE-LS !                  \ end = next line start = after
   ELSE
      1 SZ-PASTE-WHERE !                   \ before this line
      DROP SZ-PASTE-LS !                  \ beg
   THEN
;

\ Whole-line select + copy (kept for future / programmatic use; not bound to gutter).
: SZ-LINE-SELECT  ( -- )
   SZ-LINE-RANGE-AT-CUR
   SZ-SET-SEL
   SZ-SET-LINE-ANCHOR
   S" line" SZ-FIND-SET-STAT
;

: SZ-PLAIN-CLICK  ( -- )
   \ Line# gutter: caret already placed; no select (reserved for breakpoints etc.)
   SZ-CLICK-ZONE @ 1 = IF
      0 SZ-SEL-OK !
      0 SZ-PLACEHOLD !
      0 SZ-PASTE-WHERE !
      0 SZ-SEL-WORD C!
      SZ-FIND-CLEAR-STAT
      EXIT
   THEN
   \ White space after EOL: place caret only — never fill find field from the line
   SZ-CLICK-ZONE @ 2 = IF
      0 SZ-SEL-OK !
      0 SZ-SEL-WORD C!
      SZ-FIND-CLEAR-STAT
      SZ-CLIP-U @ IF
         SZ-PLACEHOLDER-CLICK               \ paste-after locus if clip non-empty
      ELSE
         0 SZ-PLACEHOLD !
         0 SZ-PASTE-WHERE !
      THEN
      EXIT
   THEN
   \ Body: word under cursor in status (not a reverse-video range)
   0 SZ-SEL-OK !
   0 SZ-PLACEHOLD !
   0 SZ-PASTE-WHERE !
   SZ-SET-ANCHOR-FROM-CUR
   SZ-UPDATE-SEL-WORD
;

\ ⌘-click: extend prior anchor through this click (words or whole lines).
: SZ-RANGE-CLICK  ( -- )
   SZ-ANCHOR-LINE @ SZ-CLICK-ZONE @ 0= 0= OR IF
      \ line-based extend (anchor was line, or this click is line/after zone)
      SZ-LINE-RANGE-AT-CUR                  \ tb te
      SZ-ANCHOR-BEG @ SZ-TBUF U< IF
         2DUP
      ELSE
         SZ-ANCHOR-BEG @                    \ tb te ab
         ROT MIN                            \ te lo
         SWAP                               \ lo te
         SZ-ANCHOR-END @ MAX                \ lo hi
         2DUP
      THEN
      SZ-SET-SEL
      SZ-SET-LINE-ANCHOR
      S" lines" SZ-FIND-SET-STAT
   ELSE
      \ word-based extend
      SZ-RANGE-AT-CUR                       \ tb te
      SZ-ANCHOR-BEG @ SZ-TBUF U< IF
         2DUP
      ELSE
         SZ-ANCHOR-BEG @
         ROT MIN SWAP
         SZ-ANCHOR-END @ MAX
         2DUP
      THEN
      SZ-SET-SEL
      SZ-SET-ANCHOR-FROM-CUR
      S" copied" SZ-FIND-SET-STAT
   THEN
;

\ Stub; redefined after SZ-DO-VIEW-UNDER (⌘-click → VIEW).
: SZ-AFTER-MOUSE  ( -- )
   SZ-CLICK-EXTEND @ 0= IF  SZ-PLAIN-CLICK  THEN
;
' SZ-AFTER-MOUSE SZ-MOUSE-XT !

VARIABLE SZ-DR-BEG
VARIABLE SZ-DR-END
VARIABLE SZ-DR-N

\ Remove [beg,end); end exclusive. Adjust CUR and TOP.
: SZ-DELETE-RANGE  ( beg end -- )
   2DUP U> IF  SWAP  THEN
   2DUP = IF  2DROP EXIT  THEN
   OVER SZ-TBUF U< IF  NIP SZ-TBUF SWAP  THEN
   DUP SZ-TEND U> IF  DROP SZ-TEND  THEN
   DUP SZ-DR-END !
   OVER SZ-DR-BEG !
   SWAP - SZ-DR-N !                        \ n = end - beg
   SZ-TEND SZ-DR-END @ -                   \ tail
   DUP 0> IF
      SZ-DR-END @ SZ-DR-BEG @ ROT MOVE     \ src dest u
   ELSE  DROP  THEN
   SZ-DR-N @ NEGATE SZ-TLEN +!
   SZ-TLEN @ 0< IF  0 SZ-TLEN !  THEN
   SZ-CUR @ SZ-DR-END @ U< 0= IF
      SZ-CUR @ SZ-DR-N @ - SZ-CUR !
   ELSE
      SZ-CUR @ SZ-DR-BEG @ U< 0= IF  SZ-DR-BEG @ SZ-CUR !  THEN
   THEN
   SZ-TOP @ SZ-DR-END @ U< 0= IF
      SZ-TOP @ SZ-DR-N @ - SZ-TOP !
   ELSE
      SZ-TOP @ SZ-DR-BEG @ U< 0= IF  SZ-DR-BEG @ SZ-TOP !  THEN
   THEN
   SZ-TOP @ SZ-TBUF U< IF  SZ-TBUF SZ-TOP !  THEN
   SZ-TOUCH
;

\ If a real selection exists, delete [beg,end) and leave CUR at beg. flag=true if deleted.
: SZ-DELETE-SEL-IF  ( -- flag )
   SZ-SEL-OK @ 0= IF  0 EXIT  THEN
   SZ-SEL-BEG @ SZ-SEL-END @
   2DUP = IF  2DROP 0 SZ-SEL-OK ! 0 EXIT  THEN
   SZ-DELETE-RANGE
   0 SZ-SEL-OK !
   0 SZ-SEL-WORD C!
   -1
;

\ Redefine insert/delete so typing replaces the active drag/range selection.
: SZ-INSERT-CH  ( c -- )
   DUP BL < OVER 126 > OR IF  DROP EXIT  THEN
   SZ-DELETE-SEL-IF DROP
   1 SZ-OPEN-HOLE 0= IF  DROP EXIT  THEN
   SZ-CUR @ C!
   1 SZ-CUR +!
   SZ-CUR-COL SZ-PREF-COL !
   SZ-TOUCH
;

: SZ-INSERT-TAB  ( -- )
   SZ-DELETE-SEL-IF DROP
   4  SZ-CUR-COL 4 MOD -
   BEGIN  DUP WHILE
      BL SZ-INSERT-CH
      1-
   REPEAT  DROP
;

: SZ-INSERT-CRLF  ( -- )
   SZ-DELETE-SEL-IF DROP
   SZ-CLAMP-CUR
   1 SZ-OPEN-HOLE 0= IF  EXIT  THEN
   SZ-CH-LF SZ-CUR @ C!
   1 SZ-CUR +!
   0 SZ-PREF-COL !
   0 SZ-HCOL !
   SZ-TOUCH
;

: SZ-BACKSPACE  ( -- )
   SZ-SEL-OK @ IF  SZ-DELETE-SEL-IF DROP EXIT  THEN
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

: SZ-DELETE-FWD  ( -- )
   SZ-SEL-OK @ IF  SZ-DELETE-SEL-IF DROP EXIT  THEN
   SZ-CUR @ SZ-TEND = IF  EXIT  THEN
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
   SZ-TEND SZ-CUR @ - 1- DUP 0> IF
      SZ-CUR @ 1+  SZ-CUR @  ROT  MOVE
   ELSE  DROP  THEN
   -1 SZ-TLEN +!
   SZ-TLEN @ 0< IF  0 SZ-TLEN !  THEN
   SZ-TOUCH
;

\ If CUR is inside a word, move to end of that word (paste target).
: SZ-PASTE-POINT  ( -- )
   SZ-WORD-AT-CUR DUP IF
      2DROP SZ-WORD-END @ SZ-CUR !
   ELSE  2DROP  THEN
;

\ Insert u bytes from addr at SZ-CUR (raw, may include CRLF).
: SZ-INSERT-BYTES  ( addr u -- )
   DUP 0= IF  2DROP EXIT  THEN
   DUP SZ-OPEN-HOLE 0= IF  2DROP EXIT  THEN
   >R SZ-CUR @ R@ CMOVE
   R@ SZ-CUR +!
   R> DROP
   SZ-REMEMBER-COL
   SZ-TOUCH
;

: SZ-DO-COPY  ( -- )
   SZ-SEL-OK @ 0= IF
      \ no multi-select: copy word under cursor if any
      SZ-RANGE-AT-CUR 2DUP = IF  2DROP S" no sel" SZ-FIND-SET-STAT EXIT  THEN
      2DUP SZ-SEL-END ! SZ-SEL-BEG !  -1 SZ-SEL-OK !
   THEN
   SZ-SEL-BEG @ SZ-SEL-END @
   2DUP SZ-CLIP-STORE
   SZ-SHOW-RANGE-SEL
   S" copied" SZ-FIND-SET-STAT
;

: SZ-DO-CUT  ( -- )
   SZ-SEL-OK @ 0= IF
      SZ-RANGE-AT-CUR 2DUP = IF  2DROP S" no sel" SZ-FIND-SET-STAT EXIT  THEN
      2DUP SZ-SEL-END ! SZ-SEL-BEG !  -1 SZ-SEL-OK !
   THEN
   SZ-SEL-BEG @ SZ-SEL-END @
   2DUP SZ-CLIP-STORE
   2DUP SZ-SHOW-RANGE-SEL
   SZ-DELETE-RANGE
   0 SZ-SEL-OK !
   S" cut" SZ-FIND-SET-STAT
;

: SZ-DO-PASTE  ( -- )
   \ Prefer solid editor clip; host pasteboard fills SZ-CLIP if empty.
   SZ-CLIP-U @ 0= IF
      SZ-CLIP SZ-CLIP-MAX (SZ-CLIP@)
      DUP 0= IF  DROP S" empty" SZ-FIND-SET-STAT EXIT  THEN
      SZ-CLIP-MAX MIN SZ-CLIP-U !
   THEN
   SZ-CLIP-U @ 0= IF  S" empty" SZ-FIND-SET-STAT EXIT  THEN
   \ Replace active selection (drag/range) when not using paste-here placeholder.
   SZ-PLACEHOLD @ 0= IF  SZ-DELETE-SEL-IF DROP  THEN
   \ Placeholder click: discard ephemeral line selection; paste solid clip
   SZ-PLACEHOLD @ IF
      0 SZ-PLACEHOLD !
      SZ-PASTE-WHERE @ 1 = IF
         SZ-PASTE-LS @ SZ-CUR !
      ELSE SZ-PASTE-WHERE @ 2 = IF
         SZ-PASTE-LS @ SZ-CUR !
      ELSE
         SZ-PASTE-POINT
      THEN THEN
   ELSE
      SZ-PASTE-POINT
   THEN
   0 SZ-PASTE-WHERE !
   SZ-CLIP SZ-CLIP-U @
   SZ-INSERT-BYTES
   S" pasted" SZ-FIND-SET-STAT
;

\ Cmd-E / Cmd-click VIEW. Note visit origin at *current caret* first when the
\ caller has not already noted (Cmd-click notes before mouse-place so return
\ is the pre-click caret — e.g. VIEW line — not the click cell).
VARIABLE SZ-VIEW-NOTED                     \ nonzero: skip next HIST-NOTE
0 SZ-VIEW-NOTED !

: SZ-DO-VIEW-UNDER  ( -- )
   SZ-WORD-AT-CUR
   DUP 0= IF  2DROP 0 SZ-VIEW-NOTED ! EXIT  THEN
   \ Copy token — Hyper may clobber PAD / temps.
   63 MIN SZ-PATH-TMP SZ-PLACE
   S" HYPER-VOC" PAD SZ-PLACE
   PAD FIND 0= IF  DROP 0 SZ-VIEW-NOTED ! EXIT  THEN
   EXECUTE
   SZ-VIEW-NOTED @ IF
      0 SZ-VIEW-NOTED !
      S" HYPER-SKIP-NOTE" PAD SZ-PLACE
      PAD FIND IF  EXECUTE  ELSE  DROP  THEN
   THEN
   SZ-PATH-TMP COUNT
   S" HYPER-VIEW-NAME" PAD SZ-PLACE
   PAD FIND IF  EXECUTE  ELSE  DROP 2DROP  THEN
   PREVIOUS ;

\ Note Hyper origin at caret *before* moving the caret (for Cmd-click).
\ Only updates Hyper VTAB + side list via NOTE-HERE; must not throw or leave
\ the search order broken (BIND uses ONLY FORTH — avoid rebinding here).
: SZ-NOTE-ORIGIN-NOW  ( -- )
   S" HYPER-VOC" PAD SZ-PLACE
   PAD FIND 0= IF  DROP EXIT  THEN
   EXECUTE
   S" HYPER-HIST-NOTE-HERE" PAD SZ-PLACE
   PAD FIND IF  EXECUTE  ELSE  DROP  THEN
   PREVIOUS
   -1 SZ-VIEW-NOTED !
;

\ Plain click (no drag): word / line / placeholder. ⌘ is handled on mouse-down.
: SZ-AFTER-MOUSE  ( -- )
   SZ-PLAIN-CLICK
;
' SZ-AFTER-MOUSE SZ-MOUSE-XT !

\ --- Click-drag / shift-extend / double-click word selection ----------------

\ Apply [SZ-DRAG-START, SZ-CUR) as the live selection (order-independent).
: SZ-DRAG-SET-SEL  ( -- )
   SZ-DRAG-START @ SZ-CUR @
   2DUP U> IF  SWAP  THEN
   2DUP = IF  2DROP 0 SZ-SEL-OK ! EXIT  THEN
   2DUP SZ-SEL-END ! SZ-SEL-BEG !
   -1 SZ-SEL-OK !
   SZ-SHOW-RANGE-SEL
   S" select" SZ-FIND-SET-STAT
;

\ Space / blank separators only (double-click word — not assembly identifier rules).
: SZ-SPACE-SEP?  ( c -- flag )  SZ-BLANK? ;

\ Space-delimited word range at SZ-CUR → ( beg end ).  Point if none.
: SZ-SPACE-WORD-RANGE  ( -- beg end )
   SZ-CUR @ SZ-CLIP-ADDR
   DUP SZ-TEND SZ-U>= IF
      DROP
      SZ-CUR @ SZ-TBUF U> IF  SZ-CUR @ 1-  ELSE  SZ-CUR @ DUP EXIT  THEN
   THEN
   \ If on a blank, try char before (so click in trailing space still grabs word).
   DUP C@ SZ-SPACE-SEP? IF
      DUP SZ-TBUF = IF  DUP EXIT  THEN
      1-
      DUP C@ SZ-SPACE-SEP? IF  1+ DUP EXIT  THEN
   THEN
   \ walk left → inclusive start
   BEGIN
      DUP SZ-TBUF = IF  TRUE
      ELSE  DUP 1- C@ SZ-SPACE-SEP? IF  TRUE
      ELSE  1- FALSE  THEN THEN
   UNTIL                                          \ beg
   >R
   R@
   BEGIN
      DUP SZ-TEND SZ-U>= IF  TRUE
      ELSE  DUP C@ SZ-SPACE-SEP? IF  TRUE
      ELSE  1+ FALSE  THEN THEN
   UNTIL                                          \ end
   R> SWAP
;

\ Finalize [beg,end) as selection + clipboard; leave CUR at end; set extend anchor.
: SZ-COMMIT-RANGE  ( beg end -- )
   2DUP U> IF  SWAP  THEN
   2DUP = IF  2DROP 0 SZ-SEL-OK ! EXIT  THEN
   2DUP SZ-SEL-END ! SZ-SEL-BEG !
   -1 SZ-SEL-OK !
   2DUP SZ-SHOW-RANGE-SEL
   2DUP SZ-CLIP-STORE
   \ Fixed end for later Shift-click = start; free end = end (caret).
   OVER SZ-EXT-ANCHOR !
   OVER SZ-DRAG-START !
   NIP SZ-CUR !
;

\ Double-click: select space-delimited word under pointer.
: SZ-DBL-CLICK  ( col row -- )
   0 SZ-DRAG-ACTIVE !
   -1 SZ-SEL-DONE !
   SZ-MOUSE-PLACE
   0 SZ-PLACEHOLD !
   0 SZ-PASTE-WHERE !
   SZ-SPACE-WORD-RANGE                      \ beg end
   2DUP = IF  2DROP 0 SZ-SEL-OK ! EXIT  THEN
   SZ-COMMIT-RANGE
   S" word" SZ-FIND-SET-STAT
;

\ Triple-click: select whole logical line under pointer (incl. EOL if present).
: SZ-TRI-CLICK  ( col row -- )
   0 SZ-DRAG-ACTIVE !
   -1 SZ-SEL-DONE !
   SZ-MOUSE-PLACE
   0 SZ-PLACEHOLD !
   0 SZ-PASTE-WHERE !
   SZ-LINE-RANGE-AT-CUR                     \ beg end
   2DUP = IF  2DROP 0 SZ-SEL-OK ! EXIT  THEN
   SZ-COMMIT-RANGE
   \ Line-based shift-extend anchor for subsequent ⇧-clicks.
   SZ-SET-LINE-ANCHOR
   S" line" SZ-FIND-SET-STAT
;

\ Shift-click / shift-drag free end: selection is [EXT-ANCHOR, CUR].
: SZ-SHIFT-SET-SEL  ( -- )
   SZ-EXT-ANCHOR @ SZ-CUR @
   2DUP U> IF  SWAP  THEN
   2DUP = IF  2DROP 0 SZ-SEL-OK ! EXIT  THEN
   2DUP SZ-SEL-END ! SZ-SEL-BEG !
   -1 SZ-SEL-OK !
   SZ-SHOW-RANGE-SEL
   S" select" SZ-FIND-SET-STAT
;

\ Wire line apply now that SZ-GOTO-LINE exists.
: SZ-FL-APPLY-LINE  ( n -- )  SZ-GOTO-LINE ;

\ Redefine side-panel goto with dirty-buffer dialog (S/D/Esc or click).
\ Do NOT no-op when i = CUR: a mis-painted current row must still open its path
\ (user report: top forth.s dead-click while listed as current).
: SZ-FL-GOTO  ( i -- )
   DUP 0< IF  DROP EXIT  THEN
   DUP SZ-FL-N @ >= IF  DROP EXIT  THEN
   DUP SZ-FL-ENT C@ 0= IF  DROP EXIT  THEN   \ empty slot
   SZ-CONFIRM-DIRTY 0= IF  DROP SZ-REDRAW EXIT  THEN
   DUP SZ-FL-CUR !
   DUP SZ-FL-ENT COUNT                        \ i a u
   2DUP SZ-LOAD IF
      ." cannot open " TYPE CR 2DROP DROP EXIT
   THEN
   2DROP
   DUP SZ-FL-LINE@ SZ-GOTO-LINE
   DROP
   \ Keep Hyper visit index in sync when present.
   S" HYPER-VOC" PAD SZ-PLACE
   PAD FIND IF
      EXECUTE
      S" HYPER-SET-VI" PAD SZ-PLACE
      PAD FIND IF  SZ-FL-CUR @ SWAP EXECUTE  ELSE  DROP  THEN
      PREVIOUS
   ELSE  DROP  THEN
   SZ-REDRAW
;

\ Close visit i ([X]): if it is the current buffer, confirm dirty then switch
\ to the previous visit (or empty untitled if none left). Non-current rows
\ only drop the list entry (buffer is not that file).
: SZ-FL-GOTO-FORCE  ( i -- )
   \ Like SZ-FL-GOTO but no dirty dialog (caller already confirmed).
   DUP 0< IF  DROP EXIT  THEN
   DUP SZ-FL-N @ >= IF  DROP EXIT  THEN
   DUP SZ-FL-ENT C@ 0= IF  DROP EXIT  THEN
   DUP SZ-FL-CUR !
   DUP SZ-FL-ENT COUNT                        \ i a u
   2DUP SZ-LOAD IF
      ." cannot open " TYPE CR 2DROP DROP EXIT
   THEN
   2DROP
   DUP SZ-FL-LINE@ SZ-GOTO-LINE
   DROP
   S" HYPER-VOC" PAD SZ-PLACE
   PAD FIND IF
      EXECUTE
      S" HYPER-SET-VI" PAD SZ-PLACE
      PAD FIND IF  SZ-FL-CUR @ SWAP EXECUTE  ELSE  DROP  THEN
      PREVIOUS
   ELSE  DROP  THEN
   SZ-HYPER-HITS-OFF
   SZ-REDRAW
;

VARIABLE SZ-FL-CI                             \ close: index
VARIABLE SZ-FL-CW                             \ close: was current (flag)
VARIABLE SZ-FL-CN0                            \ close: N before remove

\ Empty editor after last visit closed (safe CUR/TOP, no Hyper FIND).
: SZ-EDIT-UNTITLED  ( -- )
   SZ-CLEAR-BUF
   0 SZ-FNAME C!
   SZ-TBUF-ADDR @ 0= IF  SZ-BUF-BOOT  THEN
   SZ-VIEW-RESET
   SZ-HYPER-HITS-OFF
   0 SZ-SEL-OK !
   0 SZ-PLACEHOLD !
   0 SZ-PASTE-WHERE !
;

\ Close visit i ([X]).
\ - Current row: dirty confirm, remove, show previous visit or untitled.
\ - Other row: remove from list only.
\ Hyper VTAB: try HYPER-V-REMOVE (rebuilds FL); if that no-ops (desync), FL-REMOVE.
: SZ-FL-CLOSE  ( i -- )
   DUP 0< IF  DROP EXIT  THEN
   DUP SZ-FL-N @ >= IF  DROP EXIT  THEN
   DUP SZ-FL-CI !
   SZ-FL-CUR @ = SZ-FL-CW !
   SZ-FL-CW @ IF
      SZ-CONFIRM-DIRTY 0= IF  SZ-REDRAW EXIT  THEN
   THEN
   SZ-FL-N @ SZ-FL-CN0 !
   \ Prefer Hyper remove when present (keeps VTAB/FL together via REBUILD).
   SZ-FL-CI @                                 \ i
   S" HYPER-VOC" PAD SZ-PLACE
   PAD FIND IF
      EXECUTE                                 \ PUSH-ORDER HYPER-VOC  ( i )
      S" HYPER-V-REMOVE" PAD SZ-PLACE
      PAD FIND IF
         EXECUTE                              \ ( i xt ) → V-REMOVE ( i )
      ELSE
         DROP SZ-FL-REMOVE                    \ ( i )
      THEN
      PREVIOUS
   ELSE
      DROP SZ-FL-REMOVE                       \ ( caddr ) was FIND miss under i?
   THEN
   \ If Hyper V-REMOVE no-op'd (i was past VN), FL still has the row — remove it.
   SZ-FL-N @ SZ-FL-CN0 @ = IF
      SZ-FL-CI @ SZ-FL-N @ < IF
         SZ-FL-CI @ SZ-FL-REMOVE
      THEN
   THEN
   SZ-FL-N @ 0= IF
      SZ-EDIT-UNTITLED
      SZ-REDRAW
      EXIT
   THEN
   SZ-FL-CW @ IF
      SZ-FL-CI @ 1- 0 MAX SZ-FL-N @ 1- MIN
      SZ-FL-GOTO-FORCE
   ELSE
      SZ-REDRAW
   THEN
;

: SZ-SIDE-CLICK  ( col row -- )
   OVER SZ-EDIT-RIGHT > 0= IF  2DROP EXIT  THEN
   OVER SZ-COLS @ 1- < 0= IF  2DROP EXIT  THEN
   DUP SZ-TEXT-TOP < IF  2DROP EXIT  THEN
   DUP SZ-TEXT-BOT @ > IF  2DROP EXIT  THEN
   SZ-TEXT-TOP - SZ-FL-TOP @ +                \ col i
   DUP 0< IF  2DROP EXIT  THEN
   DUP SZ-FL-N @ >= IF  2DROP EXIT  THEN
   SWAP SZ-FL-X-COL? IF
      SZ-FL-CLOSE
   ELSE
      SZ-FL-GOTO
   THEN
;

\ Leave find-edit mode (defined early: mouse-down uses it before find section).
: SZ-FIND-EDIT-OFF  ( -- )  0 SZ-FIND-EDIT ! ;

\ True if facility (col row) is the outer-top-border [X] close control.
: SZ-CLOSE-HIT?  ( col row -- flag )
   SZ-OUTER-TOP <> IF  DROP FALSE EXIT  THEN
   DUP SZ-CLOSE-COL < IF  DROP FALSE EXIT  THEN
   SZ-CLOSE-COL SZ-CLOSE-XW + <              \ col < first after [X]
;

\ True if facility (col row) is in the status type-in find field.
: SZ-FIND-FIELD-HIT?  ( col row -- flag )
   SZ-STAT-ROW <> IF  DROP FALSE EXIT  THEN
   DUP SZ-SIDE-LEFT < IF  DROP FALSE EXIT  THEN
   SZ-COLS @ 1- <                            \ col < outer border
;

\ Click in status type-in area: capture caret for find edit (stay modal).
\ TOKEN is the find query; SEL-WORD is what the status paints. Keep them aligned
\ so a field click never blanks a visible query to spaces.
: SZ-FIND-FIELD-CLICK  ( col -- )
   -1 SZ-FIND-EDIT !
   -1 SZ-FIND-TYPED !
   \ Seed TOKEN from visible field text when TOKEN empty (e.g. range-select path)
   SZ-TOKEN C@ 0= IF
      SZ-SEL-WORD C@ IF
         SZ-SEL-WORD COUNT 63 MIN
         DUP SZ-TOKEN C!
         >R SZ-SEL-WORD 1+ SZ-TOKEN 1+ R> CMOVE
      THEN
   THEN
   \ Always refresh SEL-WORD from TOKEN (fixes empty SEL + non-empty TOKEN)
   SZ-TOKEN C@ DUP SZ-SEL-WORD C!
   IF
      SZ-TOKEN 1+ SZ-SEL-WORD 1+ SZ-TOKEN C@ CMOVE
   THEN
   SZ-SIDE-LEFT - 0 MAX
   SZ-TOKEN C@ MIN
   SZ-FIND-ICOL !
   0 SZ-DRAG-ACTIVE !
   -1 SZ-SEL-DONE !                          \ ignore mouse-up word-select
;

\ mouse-down: status [X] close | find field | side-panel | ⌘ VIEW | …
: SZ-MOUSE-DOWN  ( col row -- )
   0 SZ-SEL-DONE !
   \ Status [X] → close editor (same as ⌘W / SZ-DO-QUIT)
   2DUP SZ-CLOSE-HIT? IF
      2DROP
      0 SZ-DRAG-ACTIVE !
      -1 SZ-SEL-DONE !
      SZ-FIND-EDIT @ IF  SZ-FIND-EDIT-OFF  THEN
      SZ-DO-QUIT
      EXIT
   THEN
   \ Status find type-in → enter/stay in find-edit; place field caret
   2DUP SZ-FIND-FIELD-HIT? IF
      DROP SZ-FIND-FIELD-CLICK
      EXIT
   THEN
   \ Any other click leaves find-edit and resumes document/side handling
   SZ-FIND-EDIT @ IF  SZ-FIND-EDIT-OFF  THEN
   \ Click in file list → switch file (no drag / selection).
   OVER SZ-EDIT-RIGHT > IF
      0 SZ-DRAG-ACTIVE !
      -1 SZ-SEL-DONE !
      SZ-SIDE-CLICK
      EXIT
   THEN
   SZ-CLICK-EXTEND @ IF
      0 SZ-DRAG-ACTIVE !
      \ Origin = caret *before* click (VIEW line if user never moved).
      SZ-NOTE-ORIGIN-NOW
      SZ-MOUSE-PLACE
      SZ-DO-VIEW-UNDER
      EXIT
   THEN
   SZ-CLICK-TRI @ IF
      SZ-TRI-CLICK EXIT
   THEN
   SZ-CLICK-DBL @ IF
      SZ-DBL-CLICK EXIT
   THEN
   SZ-CLICK-SHIFT @ IF
      \ Extend from fixed anchor (last plain down / selection start) to click.
      SZ-MOUSE-PLACE
      SZ-EXT-ANCHOR @ SZ-TBUF U< IF
         SZ-CUR @ SZ-EXT-ANCHOR !
      THEN
      SZ-EXT-ANCHOR @ SZ-DRAG-START !
      -1 SZ-DRAG-ACTIVE !
      -1 SZ-DRAG-MOVED !                    \ already a selection gesture
      0 SZ-PLACEHOLD !
      0 SZ-PASTE-WHERE !
      SZ-SHIFT-SET-SEL
      EXIT
   THEN
   \ Plain press: start potential drag; remember extend anchor.
   SZ-MOUSE-PLACE
   SZ-CUR @ SZ-DRAG-START !
   SZ-CUR @ SZ-EXT-ANCHOR !
   -1 SZ-DRAG-ACTIVE !
   0 SZ-DRAG-MOVED !
   0 SZ-SEL-OK !
   0 SZ-PLACEHOLD !
   0 SZ-PASTE-WHERE !
;

\ mouse-drag: extend free end (plain drag or shift-drag).
: SZ-MOUSE-DRAG  ( col row -- )
   SZ-DRAG-ACTIVE @ 0= IF  2DROP EXIT  THEN
   SZ-MOUSE-PLACE
   SZ-CUR @ SZ-DRAG-START @ = IF  EXIT  THEN
   -1 SZ-DRAG-MOVED !
   SZ-CLICK-SHIFT @ IF  SZ-SHIFT-SET-SEL  ELSE  SZ-DRAG-SET-SEL  THEN
;

\ mouse-up: if moved → finalize; else plain word/line click (unless done on down).
: SZ-MOUSE-UP  ( col row -- )
   SZ-SEL-DONE @ IF  2DROP 0 SZ-SEL-DONE ! EXIT  THEN
   SZ-DRAG-ACTIVE @ 0= IF  2DROP EXIT  THEN
   0 SZ-DRAG-ACTIVE !
   SZ-MOUSE-PLACE
   SZ-DRAG-MOVED @ IF
      SZ-CLICK-SHIFT @ IF  SZ-SHIFT-SET-SEL  ELSE  SZ-DRAG-SET-SEL  THEN
      SZ-SEL-OK @ IF
         SZ-SEL-BEG @ SZ-SEL-END @ SZ-CLIP-STORE
         \ Keep the original fixed end as shift-extend anchor.
         SZ-CLICK-SHIFT @ IF
            SZ-EXT-ANCHOR @ SZ-DRAG-START !
         ELSE
            SZ-DRAG-START @ SZ-EXT-ANCHOR !
         THEN
         S" selected" SZ-FIND-SET-STAT
      THEN
   ELSE
      SZ-MOUSE-XT @ ?DUP IF  EXECUTE  THEN
      \ After plain click, extend-anchor stays at this caret for Shift-click.
      SZ-CUR @ SZ-EXT-ANCHOR !
   THEN
;

\ Facility mouse → buffer (key 25).
\ (SZ-CLICK) → col row flag; bits: 0=valid 1=⌘ 2-3=phase 4=⇧ 5=double 6=triple.
: SZ-DO-MOUSE  ( -- )
   (SZ-CLICK) DUP 0= IF  DROP 2DROP EXIT  THEN
   DUP 2 AND SZ-CLICK-EXTEND !                 \ ⌘
   DUP 16 AND SZ-CLICK-SHIFT !                 \ ⇧
   DUP 32 AND SZ-CLICK-DBL !                   \ double
   DUP 64 AND SZ-CLICK-TRI !                   \ triple
   2 RSHIFT 3 AND                              \ col row phase
   DUP 0= IF  DROP SZ-MOUSE-DOWN EXIT  THEN
   DUP 1 = IF  DROP SZ-MOUSE-DRAG EXIT  THEN
   DUP 2 = IF  DROP SZ-MOUSE-UP EXIT  THEN
   DROP 2DROP
;

\ Case-insensitive char equal
: SZ-CH=  ( c1 c2 -- flag )
   DUP [CHAR] a [CHAR] z 1+ WITHIN IF  32 -  THEN
   SWAP
   DUP [CHAR] a [CHAR] z 1+ WITHIN IF  32 -  THEN
   = ;

\ Match SZ-TOKEN at ha (case-insensitive). ( ha -- flag )
: SZ-MATCH-AT  ( ha -- flag )
   SZ-TOKEN C@ 0= IF  DROP FALSE EXIT  THEN
   >R
   0
   BEGIN  DUP SZ-TOKEN C@ < WHILE
      DUP SZ-TOKEN 1+ + C@              \ i  token[i]
      OVER R@ + C@                      \ i  tc  hay[i]
      SZ-CH= 0= IF  DROP R> DROP FALSE EXIT  THEN
      1+
   REPEAT
   DROP R> DROP TRUE ;

\ Whole-word: separators (or buffer edges) on both sides of [addr, addr+u).
\ Forth: whitespace.  Assembly: non-identifier so XROT matches XROT: and "bl XROT".
: SZ-BOUND-OK  ( addr u -- flag )
   OVER SZ-TBUF = IF  TRUE
   ELSE  OVER 1- C@ SZ-WORD-SEP?  THEN
   0= IF  2DROP FALSE EXIT  THEN
   2DUP +                               \ addr u end
   DUP SZ-TEND SZ-U>= IF  DROP 2DROP TRUE EXIT  THEN
   C@ SZ-WORD-SEP? NIP NIP ;

\ True if SZ-TOKEN is a whole-word match at ha.
: SZ-WORD-HIT?  ( ha -- flag )
   DUP SZ-MATCH-AT 0= IF  DROP FALSE EXIT  THEN
   SZ-TOKEN C@ SZ-BOUND-OK ;

\ ( start -- addr|0 ) next whole-word match of SZ-TOKEN at/after start
\ NOTE: bound check must use (ha, token-len), NOT SZ-TOKEN COUNT (that is
\ the token buffer address in the dictionary — always failed whole-word).
: SZ-SEARCH-FWD  ( start -- addr|0 )
   SZ-TOKEN C@ 0= IF  DROP 0 EXIT  THEN
   BEGIN
      DUP SZ-TOKEN C@ + SZ-TEND U> IF  DROP 0 EXIT  THEN
      DUP SZ-WORD-HIT? IF  EXIT  THEN
      1+
   AGAIN ;

\ ( limit -- addr|0 ) previous match with start < limit
: SZ-SEARCH-BWD  ( limit -- addr|0 )
   SZ-TOKEN C@ 0= IF  DROP 0 EXIT  THEN
   BEGIN
      DUP SZ-TBUF = IF  DROP 0 EXIT  THEN
      1-
      DUP SZ-WORD-HIT? IF  EXIT  THEN
   AGAIN ;

\ Status: Sel:/Find: field (sz-screen) holds query + optional note.

\ SZ-FIND-TYPED lives in sz-screen (with SZ-FIND-EDIT / SZ-FIND-ICOL).

\ Put SZ-TOKEN into status Sel/Find text (up to field capacity), clear note.
: SZ-FIND-SHOW-TOKEN  ( -- )
   SZ-FIND-CLEAR-STAT
   SZ-TOKEN COUNT SZ-SEL-TEXT-MAX MIN 63 MIN
   DUP SZ-SEL-WORD C!
   DUP 0= IF  DROP EXIT  THEN
   >R SZ-TOKEN 1+ SZ-SEL-WORD 1+ R> CMOVE
;

\ Sync SEL-WORD from TOKEN without clearing find note (live typing).
: SZ-FIND-SYNC-SEL  ( -- )
   SZ-TOKEN COUNT SZ-SEL-TEXT-MAX MIN 63 MIN
   DUP SZ-SEL-WORD C!
   DUP 0= IF  DROP EXIT  THEN
   >R SZ-TOKEN 1+ SZ-SEL-WORD 1+ R> CMOVE
;

\ Substring search (typed / selection query) — no whole-word bounds.
: SZ-SEARCH-FWD-SUB  ( start -- addr|0 )
   SZ-TOKEN C@ 0= IF  DROP 0 EXIT  THEN
   BEGIN
      DUP SZ-TOKEN C@ + SZ-TEND U> IF  DROP 0 EXIT  THEN
      DUP SZ-MATCH-AT IF  EXIT  THEN
      1+
   AGAIN ;

: SZ-SEARCH-BWD-SUB  ( limit -- addr|0 )
   SZ-TOKEN C@ 0= IF  DROP 0 EXIT  THEN
   BEGIN
      DUP SZ-TBUF = IF  DROP 0 EXIT  THEN
      1-
      DUP SZ-MATCH-AT IF  EXIT  THEN
   AGAIN ;

: SZ-SEARCH-FWD-Q  ( start -- addr|0 )
   SZ-FIND-TYPED @ IF  SZ-SEARCH-FWD-SUB  ELSE  SZ-SEARCH-FWD  THEN
;
: SZ-SEARCH-BWD-Q  ( limit -- addr|0 )
   SZ-FIND-TYPED @ IF  SZ-SEARCH-BWD-SUB  ELSE  SZ-SEARCH-BWD  THEN
;

\ Load search token into SZ-TOKEN; set WORD-BEG/END. True if non-empty.
\ Prefer active multi-byte selection; else word at CUR.
: SZ-FIND-LOAD-TOKEN  ( -- flag )
   SZ-SEL-OK @ IF
      SZ-SEL-BEG @ SZ-SEL-END @
      2DUP U> IF  SWAP  THEN                  \ beg end
      2DUP = IF  2DROP FALSE EXIT  THEN
      OVER SZ-WORD-BEG !
      DUP SZ-WORD-END !
      OVER - 63 MIN                           \ beg u
      DUP 0= IF  DROP DROP FALSE EXIT  THEN
      DUP SZ-TOKEN C!
      >R SZ-WORD-BEG @ SZ-TOKEN 1+ R> CMOVE
      -1 SZ-FIND-TYPED !                      \ selection → substring
      TRUE EXIT
   THEN
   0 SZ-FIND-TYPED !
   SZ-WORD-AT-CUR NIP 0<>
;

: SZ-FIND-GOTO  ( addr -- )
   \ Place caret at match start; keep TOKEN as the query (do not re-expand —
   \ re-expand used to turn SM/REM into REM when '/' was a separator).
   \ Reverse-video the match so find hits are easy to see.
   DUP SZ-CUR !
   DUP SZ-WORD-BEG !
   DUP SZ-TOKEN C@ +                          \ beg end
   DUP SZ-WORD-END !
   2DUP SZ-SEL-END ! SZ-SEL-BEG !
   -1 SZ-SEL-OK !
   OVER SZ-EXT-ANCHOR !                       \ shift-extend from match start
   2DROP
   SZ-REMEMBER-COL
   SZ-ENSURE-VISIBLE
   SZ-FIND-SHOW-TOKEN
;

: SZ-FIND-NO-WORD  ( -- )
   0 SZ-SEL-WORD C!
   S" no word" SZ-FIND-SET-STAT
;

\ Keep status query from TOKEN; set note to its right (no next / no prev).
: SZ-FIND-KEEP-SEL  ( c-addr u -- )
   2>R
   SZ-FIND-SHOW-TOKEN
   2R>
   SZ-FIND-SET-STAT
;

\ Run next/prev using current SZ-TOKEN (no re-load from word).
\ Always search relative to SZ-CUR (latest caret), not a stale WORD-END/BEG from
\ an earlier hit — e.g. after scroll + click at top of file, Return must search
\ from there, not from the previous match.
: SZ-DO-FIND-NEXT-TOKEN  ( -- )
   SZ-TOKEN C@ 0= IF  SZ-FIND-NO-WORD EXIT  THEN
   SZ-CUR @
   \ If caret sits on a match start, skip it so Return advances to the next hit
   DUP SZ-MATCH-AT IF  SZ-TOKEN C@ +  THEN
   SZ-SEARCH-FWD-Q
   DUP 0= IF
      DROP S" (no next)" SZ-FIND-KEEP-SEL EXIT
   THEN
   SZ-FIND-GOTO
;

: SZ-DO-FIND-PREV-TOKEN  ( -- )
   SZ-TOKEN C@ 0= IF  SZ-FIND-NO-WORD EXIT  THEN
   SZ-CUR @                                    \ exclusive limit = current caret
   SZ-SEARCH-BWD-Q
   DUP 0= IF
      DROP S" (no prev)" SZ-FIND-KEEP-SEL EXIT
   THEN
   SZ-FIND-GOTO
;

\ Live preview while typing: first match from buffer start (or no match note).
: SZ-FIND-LIVE  ( -- )
   SZ-TOKEN C@ 0= IF
      0 SZ-SEL-OK !
      SZ-FIND-CLEAR-STAT
      EXIT
   THEN
   SZ-TBUF SZ-SEARCH-FWD-Q
   DUP 0= IF
      DROP
      SZ-FIND-SYNC-SEL
      S" no match" SZ-FIND-SET-STAT
      0 SZ-SEL-OK !
      EXIT
   THEN
   SZ-FIND-GOTO
;

\ --- Cmd-F: type query in status Find field (modal until Esc / Enter) --------
\ While open, keys never reach the document.  Arrows move the find caret only.
\ SZ-FIND-ICOL lives in sz-screen (status caret).
\ SZ-FIND-EDIT-OFF is defined earlier (before mouse-down).

: SZ-FIND-CLAMP-ICOL  ( -- )
   SZ-FIND-ICOL @ 0 MAX
   SZ-TOKEN C@ MIN
   SZ-FIND-ICOL !
;

\ Delete one char at index i (0-based); shrink length. Does not change ICOL.
: SZ-FIND-DEL-AT  ( i -- )
   DUP SZ-TOKEN C@ >= IF  DROP EXIT  THEN
   >R
   \ move body[i+1 .. len) → body[i ..)
   SZ-TOKEN 1+ R@ + 1+                      \ src
   SZ-TOKEN 1+ R@ +                         \ dst
   SZ-TOKEN C@ R> - 1- 0 MAX                \ n
   CMOVE
   SZ-TOKEN C@ 1- 0 MAX SZ-TOKEN C!
;

: SZ-FIND-EDIT-BS  ( -- )
   SZ-FIND-ICOL @ 0= IF  EXIT  THEN
   -1 SZ-FIND-ICOL +!
   SZ-FIND-ICOL @ SZ-FIND-DEL-AT
   SZ-FIND-SYNC-SEL
   SZ-FIND-LIVE
;

: SZ-FIND-EDIT-DEL  ( -- )
   SZ-FIND-ICOL @ SZ-TOKEN C@ >= IF  EXIT  THEN
   SZ-FIND-ICOL @ SZ-FIND-DEL-AT
   SZ-FIND-SYNC-SEL
   SZ-FIND-LIVE
;

\ Insert c at SZ-FIND-ICOL; advance caret.
: SZ-FIND-EDIT-INS  ( c -- )
   SZ-TOKEN C@ 63 >= IF  DROP EXIT  THEN
   SZ-TOKEN C@ SZ-SEL-TEXT-MAX >= IF  DROP EXIT  THEN
   SZ-FIND-CLAMP-ICOL
   >R
   \ open a hole at ICOL: move body[icol .. len) right by 1
   SZ-TOKEN 1+ SZ-FIND-ICOL @ +             \ src = dst-hole
   DUP 1+                                   \ src dst
   SZ-TOKEN C@ SZ-FIND-ICOL @ - 0 MAX       \ n
   CMOVE>
   R> SZ-TOKEN 1+ SZ-FIND-ICOL @ + C!
   SZ-TOKEN C@ 1+ SZ-TOKEN C!
   1 SZ-FIND-ICOL +!
   SZ-FIND-SYNC-SEL
   SZ-FIND-LIVE
;

: SZ-FIND-CARET-LEFT  ( -- )
   SZ-FIND-ICOL @ 1- 0 MAX SZ-FIND-ICOL !
;
: SZ-FIND-CARET-RIGHT  ( -- )
   SZ-FIND-ICOL @ 1+ SZ-TOKEN C@ MIN SZ-FIND-ICOL !
;
: SZ-FIND-CARET-HOME  ( -- )  0 SZ-FIND-ICOL ! ;
: SZ-FIND-CARET-END   ( -- )  SZ-TOKEN C@ SZ-FIND-ICOL ! ;

\ Cmd-F: open status type-in field right of Files separator.
\ If a selection is active, seed the query from it; otherwise start empty
\ (do not grab word-under-cursor or auto-highlight a match).
: SZ-DO-FIND-EDIT  ( -- )
   -1 SZ-FIND-EDIT !
   -1 SZ-FIND-TYPED !
   SZ-SEL-OK @ IF
      SZ-FIND-LOAD-TOKEN DROP
      SZ-FIND-SYNC-SEL
      SZ-FIND-CLEAR-STAT
      SZ-TOKEN C@ SZ-FIND-ICOL !
      SZ-TOKEN C@ IF  SZ-FIND-LIVE  THEN
   ELSE
      0 SZ-TOKEN C!
      0 SZ-SEL-WORD C!
      0 SZ-SEL-OK !
      0 SZ-FIND-ICOL !
      SZ-FIND-CLEAR-STAT
   THEN
;

\ Enter in find field: find next match, stay in the field (do not return to document).
: SZ-FIND-EDIT-COMMIT  ( -- )
   SZ-TOKEN C@ 0= IF  S" no word" SZ-FIND-SET-STAT EXIT  THEN
   -1 SZ-FIND-TYPED !
   SZ-DO-FIND-NEXT-TOKEN
;

\ ⇧Return in find field: find previous match, stay in the field.
: SZ-FIND-EDIT-COMMIT-PREV  ( -- )
   SZ-TOKEN C@ 0= IF  S" no word" SZ-FIND-SET-STAT EXIT  THEN
   -1 SZ-FIND-TYPED !
   SZ-DO-FIND-PREV-TOKEN
;

\ Cmd-Right / ⌘G: next occurrence.
\ Prefer active Cmd-F / last typed query; else selection or word under cursor.
: SZ-DO-FIND-NEXT  ( -- )
   SZ-FIND-EDIT @ IF  SZ-DO-FIND-NEXT-TOKEN EXIT  THEN
   SZ-FIND-TYPED @ SZ-TOKEN C@ 0<> AND IF
      SZ-DO-FIND-NEXT-TOKEN EXIT
   THEN
   SZ-FIND-LOAD-TOKEN 0= IF  SZ-FIND-NO-WORD EXIT  THEN
   SZ-WORD-END @                             \ search after current token range
   SZ-SEARCH-FWD-Q
   DUP 0= IF
      DROP S" (no next)" SZ-FIND-KEEP-SEL EXIT
   THEN
   SZ-FIND-GOTO ;

\ Cmd-Left / ⌘⇧G: previous occurrence
: SZ-DO-FIND-PREV  ( -- )
   SZ-FIND-EDIT @ IF  SZ-DO-FIND-PREV-TOKEN EXIT  THEN
   SZ-FIND-TYPED @ SZ-TOKEN C@ 0<> AND IF
      SZ-DO-FIND-PREV-TOKEN EXIT
   THEN
   SZ-FIND-LOAD-TOKEN 0= IF  SZ-FIND-NO-WORD EXIT  THEN
   SZ-WORD-BEG @
   SZ-SEARCH-BWD-Q
   DUP 0= IF
      DROP S" (no prev)" SZ-FIND-KEEP-SEL EXIT
   THEN
   SZ-FIND-GOTO ;

\ Normal key path (no Cmd-F field). Defined before DISPATCH so find-mode
\ can leave the field and reprocess a key without a forward reference.
: SZ-HANDLE-KEY-BODY  ( c -- )
   DUP SZ-FIND-EDIT-KEY = IF  DROP SZ-DO-FIND-EDIT EXIT  THEN
   DUP SZ-CMD-EVAL = IF  DROP SZ-DO-CONSOLE-LINE EXIT  THEN
   DUP SZ-CTRL-Q = IF  DROP SZ-DO-QUIT EXIT  THEN
   DUP SZ-CTRL-S = IF  DROP SZ-DO-SAVE EXIT  THEN
   DUP SZ-CUT = IF  DROP SZ-DO-CUT EXIT  THEN
   DUP SZ-COPY = IF  DROP SZ-DO-COPY EXIT  THEN
   DUP SZ-PASTE = IF  DROP SZ-DO-PASTE EXIT  THEN
   DUP SZ-VIEW-UNDER = IF  DROP SZ-DO-VIEW-UNDER EXIT  THEN
   DUP SZ-FIND-PREV = IF  DROP SZ-DO-FIND-PREV EXIT  THEN
   DUP SZ-FIND-NEXT = IF  DROP SZ-DO-FIND-NEXT EXIT  THEN
   DUP SZ-MOUSE = IF  DROP SZ-DO-MOUSE EXIT  THEN
   DUP SZ-VSCROLL-UP = IF  DROP SZ-SCROLL-UP EXIT  THEN
   DUP SZ-VSCROLL-DN = IF  DROP SZ-SCROLL-DOWN EXIT  THEN
   DUP SZ-VIEW-UP = IF  DROP SZ-VIEW-LINE-UP EXIT  THEN
   DUP SZ-VIEW-DN = IF  DROP SZ-VIEW-LINE-DOWN EXIT  THEN
   DUP SZ-HSCROLL-LEFT = IF  DROP SZ-VIEW-COL-LEFT EXIT  THEN
   DUP SZ-HSCROLL-RIGHT = IF  DROP SZ-VIEW-COL-RIGHT EXIT  THEN
   DUP SZ-HYPER-PREV = IF  DROP SZ-DO-HYPER-PREV EXIT  THEN
   DUP SZ-HYPER-NEXT = IF  DROP SZ-DO-HYPER-NEXT EXIT  THEN
   DUP SZ-CMD-OPEN = IF  DROP SZ-DO-MENU-OPEN EXIT  THEN
   DUP SZ-CMD-NEW = IF  DROP SZ-DO-MENU-NEW EXIT  THEN
   DUP SZ-CMD-SAVE-AS = IF  DROP SZ-DO-SAVE-AS EXIT  THEN
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
   DUP SZ-TAB = IF  DROP SZ-INSERT-TAB EXIT  THEN
   DUP BL < IF  DROP EXIT  THEN
   DUP 127 < IF  SZ-INSERT-CH EXIT  THEN
   DROP
;

\ Modal find-field keys.  Esc or click-out leave the field.
\ Enter → next; ⇧Return → previous.  ⌘W/⌘Q/⌘S and scroll are not trapped.
: SZ-FIND-EDIT-DISPATCH  ( c -- )
   DUP 27 = IF  DROP SZ-FIND-EDIT-OFF EXIT  THEN          \ Esc → document
   DUP SZ-SHIFT-ENTER = IF
      DROP SZ-FIND-EDIT-COMMIT-PREV EXIT                  \ ⇧Return → prev, stay
   THEN
   DUP SZ-ENTER = OVER SZ-LF-KEY = OR IF
      DROP SZ-FIND-EDIT-COMMIT EXIT                       \ Enter → next, stay
   THEN
   DUP SZ-MOUSE = IF  DROP SZ-DO-MOUSE EXIT  THEN         \ field vs document
   \ Close / quit / save must work while find-edit is open (else ⌘Q sets
   \ app-quit-pending, key is swallowed, later ⌘W closes the whole app).
   DUP SZ-CTRL-Q = IF  DROP SZ-FIND-EDIT-OFF SZ-DO-QUIT EXIT  THEN
   DUP SZ-CTRL-S = IF  DROP SZ-FIND-EDIT-OFF SZ-DO-SAVE EXIT  THEN
   DUP SZ-CMD-SAVE-AS = IF  DROP SZ-FIND-EDIT-OFF SZ-DO-SAVE-AS EXIT  THEN
   DUP SZ-CMD-NEW = IF  DROP SZ-FIND-EDIT-OFF SZ-DO-MENU-NEW EXIT  THEN
   DUP SZ-CMD-EVAL = IF  DROP SZ-DO-CONSOLE-LINE EXIT  THEN
   \ Scroll / jump in the document without leaving the find field
   DUP SZ-VSCROLL-UP = IF  DROP SZ-SCROLL-UP EXIT  THEN
   DUP SZ-VSCROLL-DN = IF  DROP SZ-SCROLL-DOWN EXIT  THEN
   DUP SZ-VIEW-UP = IF  DROP SZ-VIEW-LINE-UP EXIT  THEN
   DUP SZ-VIEW-DN = IF  DROP SZ-VIEW-LINE-DOWN EXIT  THEN
   DUP SZ-HSCROLL-LEFT = IF  DROP SZ-VIEW-COL-LEFT EXIT  THEN
   DUP SZ-HSCROLL-RIGHT = IF  DROP SZ-VIEW-COL-RIGHT EXIT  THEN
   DUP SZ-HOME-FILE = IF  DROP SZ-GO-HOME-FILE EXIT  THEN  \ ⌘Home
   DUP SZ-END-FILE = IF  DROP SZ-GO-END-FILE EXIT  THEN    \ ⌘End
   DUP SZ-BS = IF  DROP SZ-FIND-EDIT-BS EXIT  THEN
   DUP SZ-DEL-FWD = OVER SZ-DEL = OR IF
      DROP SZ-FIND-EDIT-DEL EXIT
   THEN
   \ Plain Home/End move the find-field caret (not document line)
   DUP SZ-LEFT = IF  DROP SZ-FIND-CARET-LEFT EXIT  THEN
   DUP SZ-RIGHT = IF  DROP SZ-FIND-CARET-RIGHT EXIT  THEN
   DUP SZ-HOME-LINE = IF  DROP SZ-FIND-CARET-HOME EXIT  THEN
   DUP SZ-END-LINE = IF  DROP SZ-FIND-CARET-END EXIT  THEN
   \ ⌘G / ⌘←→: next/prev match, stay in field (caret stays on status)
   DUP SZ-FIND-NEXT = IF  DROP SZ-DO-FIND-NEXT-TOKEN EXIT  THEN
   DUP SZ-FIND-PREV = IF  DROP SZ-DO-FIND-PREV-TOKEN EXIT  THEN
   DUP SZ-FIND-EDIT-KEY = IF  DROP EXIT  THEN             \ Cmd-F: stay
   DUP BL 1- > OVER 127 < AND IF                          \ printable → field
      SZ-FIND-EDIT-INS EXIT
   THEN
   DROP                                                   \ swallow all else
;

: SZ-HANDLE-KEY  ( c -- )
   255 AND
   SZ-FIND-EDIT @ IF  SZ-FIND-EDIT-DISPATCH EXIT  THEN
   SZ-HANDLE-KEY-BODY
;

\ Core interactive loop; does not reset cursor (caller sets SZ-CUR / view).
: (SZ-EDIT-LOOP)  ( -- )
   0 SZ-DONE !
   SZ-EDITOR-ENTER
   BEGIN
      SZ-DONE @ 0=
   WHILE
      SZ-REDRAW
      SZ-DBG-RUN
      SZ-KEY SZ-HANDLE-KEY
   REPEAT
   SZ-EDITOR-LEAVE
   FACILITY-OFF
   \ Do not CLS here — that clears the restored host transcript.
   \ Reset data stack without probing DSP. BEGIN DEPTH WHILE DROP can crash in
   \ DEPTH if a prior underflow left DSP past SP0 (SP0 is also return_stack[0]).
   CLEARSTACK
   \ Quiet exit: no "SZ-EDITOR: done" / SZ-.INFO path dump (user can SZ-.INFO).
   SZ-MODIFIED @ IF  ." warning: buffer still modified" CR  THEN
;

: SZ-EDIT-LOOP  ( -- )
   SZ-VIEW-RESET
   (SZ-EDIT-LOOP)
;

: SZ-EDIT-FILE  ( c-addr u -- )
   SZ-HYPER-HITS-OFF
   2DUP SZ-LOAD IF
      ." SZ-EDIT-FILE: load failed: " TYPE CR
      ."   try absolute path, or FROMLIB for Library-relative names" CR
      2DROP EXIT
   THEN
   2DROP
   SZ-FL-NOTE-CURRENT
   SZ-EDIT-LOOP
;

\ Load path and open editor on 1-based line (for VIEW / hypertext).
\ Hyper sets SZ-HYPER-HITS! before calling when multi-hit is active.
: SZ-EDIT-FILE-AT  ( c-addr u line -- )
   >R
   2DUP SZ-LOAD IF
      R> DROP
      ." SZ-EDIT-FILE-AT: load failed: " TYPE CR
      2DROP EXIT
   THEN
   2DROP
   R> SZ-GOTO-LINE
   \ After line is set so visit row stores the real line number.
   SZ-FL-NOTE-CURRENT
   (SZ-EDIT-LOOP)
;

\ Empty untitled buffer and enter the editor (File → New / ⌘N).
: SZ-EDIT-NEW  ( -- )
   SZ-HYPER-HITS-OFF
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
