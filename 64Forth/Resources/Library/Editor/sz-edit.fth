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
\   mouse click     word under click; gutter/col0 = whole line
\   Cmd-click       VIEW word under click (same as click + Cmd-E)
\   gutter after copy  paste-here (keeps prior clip); ⌘V pastes prior
\   Cmd-X/C/V       cut / copy / paste (before/after line if paste-here)
\   Cmd-E           VIEW word under cursor; Cmd-PgUp returns here
\   Cmd-PgUp/PgDn   previous/next Hyper hit
\   Cmd-Left/Right  prev/next occurrence of word under cursor (same file)
\                   assembly (.s/.inc/.asm): identifier bounds (labels / XROT:)
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
 25 CONSTANT SZ-MOUSE          \ host mouse click in facility (Phase 4a)
 26 CONSTANT SZ-HYPER-PREV     \ Cmd-PgUp — previous HYPER hit
 27 CONSTANT SZ-HYPER-NEXT     \ Cmd-PgDn — next HYPER hit
 30 CONSTANT SZ-CMD-OPEN       \ host File→Open while KEY waiting
 31 CONSTANT SZ-CMD-NEW        \ host File→New while KEY waiting
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
   \ Use unsigned compare — heap buffer addresses must not use signed >
   SZ-CUR @ SZ-TBUF U> IF  -1 SZ-CUR +!  THEN
   SZ-REMEMBER-COL
;

: SZ-GO-RIGHT  ( -- )
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

\ Temporary message on first help row (restored on next full redraw).
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
VARIABLE SZ-ANCHOR-BEG                 \ last plain-click range start
VARIABLE SZ-ANCHOR-END
VARIABLE SZ-SEL-BEG                    \ active selection
VARIABLE SZ-SEL-END
VARIABLE SZ-SEL-OK                     \ nonzero if SZ-SEL-* is a real range
VARIABLE SZ-CLICK-EXTEND               \ last click was ⌘-click range-extend (host flag)
VARIABLE SZ-CLICK-ZONE                 \ 0=body 1=gutter/before-line 2=after-eol
VARIABLE SZ-ANCHOR-LINE                \ nonzero if anchor is whole-line based
VARIABLE SZ-PASTE-WHERE                \ 0=normal 1=before-line 2=after-line
VARIABLE SZ-PASTE-LS                  \ line-start for before/after paste
VARIABLE SZ-PLACEHOLD                  \ nonzero: last click was paste placeholder only
VARIABLE SZ-CLIP-HOLD-U                \ previous solid clip (two-level stack)

\ Host click flag: bit0=valid, bit1=Command (range-extend).
\ Place caret without scrolling (line is already on-screen under the pointer).
\ zone: 0=body  1=gutter/line-start  2=after last char on line
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
   \ Gutter / line# / '|' → whole-line / paste-before
   DUP SZ-TEXT-LEFT < IF
      2DROP
      1 SZ-CLICK-ZONE !
      R@ SZ-GOTO-LINE-RAW                      \ no scroll — keep view still
      SZ-CUR-LINE SZ-CUR !
      SZ-CLAMP-CUR
      SZ-REMEMBER-COL SZ-ENSURE-HVISIBLE
      R> DROP EXIT
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
      OVER 0= IF  1 SZ-CLICK-ZONE !  THEN      \ col 0 → line mode
      MIN 0 MAX
      SZ-CUR-LINE + SZ-CUR !
   THEN
   SZ-CLAMP-CUR
   SZ-REMEMBER-COL SZ-ENSURE-HVISIBLE
   R> DROP
;

\ Facility mouse click → buffer cursor (Phase 4a).
\ Host key 25 then (SZ-CLICK) → col row flag (1=plain, 3=⌘-click VIEW).
: SZ-DO-MOUSE  ( -- )
   (SZ-CLICK) DUP 0= IF  DROP 2DROP EXIT  THEN
   2 AND SZ-CLICK-EXTEND !                     \ ⌘ bit
   SZ-MOUSE-PLACE
   SZ-MOUSE-XT @ ?DUP IF  EXECUTE  THEN
;

\ Phase 5: load path + goto line for HYPER multi-hit ( a u line -- )
\ Do not reference Hyper words here (editor loads before Hyper).
\ Copy path to SZ-PATH-TMP so a/u may safely alias HYPER-HIT across SZ-LOAD.
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
      EXIT
   THEN
   2DROP
   R@ SZ-GOTO-LINE
   SZ-MSG-LINE
   ." hyper " SZ-GET-NAME TYPE ." :" R> 0 .R
   TERMINAL-REFRESH
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

CREATE SZ-TOKEN  64 ALLOT
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
: SZ-ASM-NAME-CHAR?  ( c -- flag )
   DUP [CHAR] 0 [CHAR] 9 1+ WITHIN IF  DROP TRUE EXIT  THEN
   DUP [CHAR] A [CHAR] Z 1+ WITHIN IF  DROP TRUE EXIT  THEN
   DUP [CHAR] a [CHAR] z 1+ WITHIN IF  DROP TRUE EXIT  THEN
   DUP [CHAR] _ = IF  DROP TRUE EXIT  THEN
   DUP [CHAR] . = IF  DROP TRUE EXIT  THEN
   DUP [CHAR] $ = IF  DROP TRUE EXIT  THEN
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

\ Copy word under SZ-CUR into SZ-SEL-WORD (counted, max 16) for status bar.
: SZ-UPDATE-SEL-WORD  ( -- )
   SZ-FIND-CLEAR-STAT
   SZ-WORD-AT-CUR                              \ a u
   16 MIN
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

\ Show first 16 bytes of [beg,end) in Selected: status.
: SZ-SHOW-RANGE-SEL  ( beg end -- )
   2DUP U> IF  SWAP  THEN                  \ beg end
   OVER - 0 MAX 16 MIN                     \ beg u
   DUP SZ-SEL-WORD C!
   DUP IF  >R SZ-SEL-WORD 1+ R@ CMOVE R> DROP  ELSE  2DROP  THEN
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

\ Placeholder click: keep solid clip; only mark paste target + preview Selected.
: SZ-PLACEHOLDER-CLICK  ( -- )
   -1 SZ-PLACEHOLD !
   SZ-LINE-RANGE-AT-CUR                    \ beg end
   2DUP SZ-SHOW-RANGE-SEL
   SZ-CLICK-ZONE @ 2 = IF
      2 SZ-PASTE-WHERE !                   \ after this line
      NIP SZ-PASTE-LS !                  \ end = next line start = after
   ELSE
      1 SZ-PASTE-WHERE !                   \ before this line
      DROP SZ-PASTE-LS !                  \ beg
   THEN
   S" paste here" SZ-FIND-SET-STAT
;

\ Solid whole-line select + copy.
: SZ-LINE-SELECT  ( -- )
   SZ-LINE-RANGE-AT-CUR
   SZ-SET-SEL
   SZ-SET-LINE-ANCHOR
   S" line" SZ-FIND-SET-STAT
;

: SZ-PLAIN-CLICK  ( -- )
   \ Gutter / line-start: line select, or placeholder if solid clip already set
   SZ-CLICK-ZONE @ 1 = IF
      SZ-CLIP-U @ IF  SZ-PLACEHOLDER-CLICK  ELSE  SZ-LINE-SELECT  THEN
      EXIT
   THEN
   \ After EOL with existing solid clip → placeholder paste-after
   SZ-CLICK-ZONE @ 2 = SZ-CLIP-U @ AND IF
      SZ-PLACEHOLDER-CLICK EXIT
   THEN
   \ Body: word select
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

\ Cmd-E in editor: VIEW word under cursor (Hyper); stays in this edit session.
: SZ-DO-VIEW-UNDER  ( -- )
   SZ-WORD-AT-CUR
   DUP 0= IF  2DROP EXIT  THEN                 \ a u
   S" HYPER-VOC" PAD SZ-PLACE
   PAD FIND 0= IF  DROP 2DROP EXIT  THEN
   EXECUTE                                     \ push HYPER-VOC; a u remain
   S" HYPER-VIEW-NAME" PAD SZ-PLACE
   PAD FIND IF  EXECUTE  ELSE  DROP 2DROP  THEN
   PREVIOUS ;

\ ⌘-click: place caret (already done) then VIEW — same as click + Cmd-E.
\ (Replaces earlier stub; range-extend via ⌘-click is no longer used.)
: SZ-AFTER-MOUSE  ( -- )
   SZ-CLICK-EXTEND @ IF  SZ-DO-VIEW-UNDER  ELSE  SZ-PLAIN-CLICK  THEN
;
' SZ-AFTER-MOUSE SZ-MOUSE-XT !

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

\ Status: Selected: "word"  [optional note to the right — SZ-FIND-STAT in sz-screen]

: SZ-FIND-GOTO  ( addr -- )
   SZ-CUR !
   SZ-REMEMBER-COL
   SZ-ENSURE-VISIBLE
   SZ-UPDATE-SEL-WORD                       \ also clears find note
;

: SZ-FIND-NO-WORD  ( -- )
   0 SZ-SEL-WORD C!
   S" no word" SZ-FIND-SET-STAT
;

\ Keep Selected: word; set note to its right (no next / no prev).
\ ( note-addr note-u -- )
: SZ-FIND-KEEP-SEL  ( c-addr u -- )
   2>R
   SZ-WORD-AT-CUR 16 MIN
   DUP SZ-SEL-WORD C!
   DUP IF  >R SZ-SEL-WORD 1+ R> CMOVE  ELSE  2DROP  THEN
   2R>
   SZ-FIND-SET-STAT
;

\ Cmd-Right / ⌘G: next occurrence of full word under cursor (same buffer)
: SZ-DO-FIND-NEXT  ( -- )
   SZ-WORD-AT-CUR DUP 0= IF  2DROP SZ-FIND-NO-WORD EXIT  THEN
   2DROP
   SZ-WORD-END @                             \ search after current word range
   SZ-SEARCH-FWD
   DUP 0= IF
      DROP S" no next" SZ-FIND-KEEP-SEL EXIT
   THEN
   SZ-FIND-GOTO ;

\ Cmd-Left / ⌘⇧G: previous occurrence of full word under cursor (same buffer)
: SZ-DO-FIND-PREV  ( -- )
   SZ-WORD-AT-CUR DUP 0= IF  2DROP SZ-FIND-NO-WORD EXIT  THEN
   2DROP
   SZ-WORD-BEG @                             \ search before current word range
   SZ-SEARCH-BWD
   DUP 0= IF
      DROP S" no prev" SZ-FIND-KEEP-SEL EXIT
   THEN
   SZ-FIND-GOTO ;

: SZ-HANDLE-KEY  ( c -- )
   255 AND
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
   DUP SZ-TAB = IF  DROP SZ-INSERT-TAB EXIT  THEN
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
   \ Reset data stack without probing DSP. BEGIN DEPTH WHILE DROP can crash in
   \ DEPTH if a prior underflow left DSP past SP0 (SP0 is also return_stack[0]).
   CLEARSTACK
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
