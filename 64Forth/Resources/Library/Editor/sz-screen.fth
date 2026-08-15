\ sz-screen.fth — SZ-EDITOR mono display / scroll (Phase 5 frame + cursor)
\
\ Uses Facility PAGE/AT-XY/EMIT, then TERMINAL-REFRESH once per frame so the
\ host paints the full screen (PAGE alone must not flush an empty buffer).
\
\ Layout (0-based rows; geometry from SET-EDIT-WINDOW / EDIT-WINDOW settings):
\   row 0              outer top     ╭──────────────── full width ────────────────╮
\   row 1              status        │ path L: C: … (full width after zoom)       │
\   row 2              col top       ├─────┬──────────────────────┬───────────────┤
\   rows 3..(2+H)      body          │ NNN │ text (W cols)        │ visit list    │
\   row (3+H)          col bottom    ├─────┴──────────────────────┴───────────────┤
\   row (4+H)          help 1        │ shortcuts…                                 │
\   row (5+H)          help 2        │ …                                          │
\   row (6+H)          outer bottom  ╰──────────────── full width ────────────────╯
\
\ Outline uses Unicode box-drawing (XEMIT); host stores one scalar per cell.
\ Column separators (gutter / side) align with ┬/┴ on the mid rules only.
\ Text body is SZ-TEXT-WIDTH columns. Gutter/frame extra; SZ-SIDE-WIDTH
\ columns on the right list leaf names of files opened / VIEW'd.
\ Facility cols = W + 8 + SZ-SIDE-WIDTH + 1 (outer │); rows = H + 7.
\ User:  width height SET-EDIT-WINDOW   (persists via settings)
\ Query: EDIT-WINDOW  ( -- width height )
\
\ Depends on: sz-host.fth, sz-buffer.fth

DECIMAL

\ Fixed chrome (not changed by SET-EDIT-WINDOW)
   0 CONSTANT SZ-OUTER-TOP      \ full-width top border row
   1 CONSTANT SZ-STAT-ROW       \ status content (boxed)
   2 CONSTANT SZ-FRAME-TOP      \ column tee bar above text
   3 CONSTANT SZ-TEXT-TOP       \ first text body row
   1 CONSTANT SZ-LN-COL         \ first column of line-number gutter
   5 CONSTANT SZ-LN-WIDTH       \ digits (right-justified; blank if past EOF)
   6 CONSTANT SZ-LN-SEP         \ column of │ between gutter and text
   7 CONSTANT SZ-TEXT-LEFT      \ first column of text body
  28 CONSTANT SZ-SIDE-WIDTH     \ visit list: leaf + line# + X
   7 CONSTANT SZ-CHROME-ROWS    \ facility rows = text height + this

\ Dynamic geometry (set by SZ-APPLY-EDIT-WINDOW)
VARIABLE SZ-TEXT-WIDTH          \ editable text columns
VARIABLE SZ-TEXT-BOT            \ last text row
VARIABLE SZ-FRAME-BOT           \ column tee bar below text
VARIABLE SZ-HELP1               \ help line 1 row
VARIABLE SZ-HELP2               \ help line 2 row
VARIABLE SZ-OUTER-BOT           \ full-width bottom border row
VARIABLE SZ-COLS                \ full facility width (editor + side panel)
VARIABLE SZ-EDIT-COLS           \ editor portion through its right '|'

\ SZ-CUR / SZ-TOP are defined in sz-buffer.fth (needed by SZ-ENSURE-CAP).

VARIABLE SZ-HCOL                   \ leftmost visible text column (horizontal scroll)
VARIABLE SZ-DRAW-LNO               \ running 1-based line # while painting (not on R stack)
VARIABLE SZ-SAVE-BASE              \ BASE save for gutter (avoid R stack inside DO)

\ Column of editor right border '|' (left edge of side panel is +1).
: SZ-EDIT-RIGHT  ( -- col )
   SZ-TEXT-LEFT SZ-TEXT-WIDTH @ +
;

\ First column of side panel content (after editor right border).
: SZ-SIDE-LEFT  ( -- col )
   SZ-EDIT-RIGHT 1+
;

\ ( width height -- )  apply text-body size to layout variables (host has clamped).
: SZ-APPLY-EDIT-WINDOW  ( width height -- )
   SWAP SZ-TEXT-WIDTH !
   SZ-TEXT-TOP + 1- SZ-TEXT-BOT !
   SZ-TEXT-BOT @ 1+ SZ-FRAME-BOT !
   SZ-FRAME-BOT @ 1+ SZ-HELP1 !
   SZ-HELP1 @ 1+ SZ-HELP2 !
   SZ-HELP2 @ 1+ SZ-OUTER-BOT !
   \ editor cols = TEXT-LEFT + width + 1 (right border) = width + 8
   SZ-TEXT-WIDTH @ SZ-TEXT-LEFT + 1+ DUP SZ-EDIT-COLS !
   \ full facility = editor + side content + outer right '|'
   SZ-SIDE-WIDTH + 1+ SZ-COLS !
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

\ Box-drawing outline (Unicode light arcs + tees; same family as Grok prompt box).
\ Facility host stores one Unicode scalar per cell (UTF-8 via XEMIT).
HEX
256D CONSTANT SZ-BOX-TL     \ ╭  arc down-right
256E CONSTANT SZ-BOX-TR     \ ╮  arc down-left
2570 CONSTANT SZ-BOX-BL     \ ╰  arc up-right
256F CONSTANT SZ-BOX-BR     \ ╯  arc up-left
2500 CONSTANT SZ-BOX-H      \ ─  horizontal
2502 CONSTANT SZ-BOX-V      \ │  vertical
252C CONSTANT SZ-BOX-TD     \ ┬  tee down (column top junctions)
2534 CONSTANT SZ-BOX-BU     \ ┴  tee up (column bottom junctions)
251C CONSTANT SZ-BOX-LT     \ ├  left tee (outer continues past mid bar)
2524 CONSTANT SZ-BOX-RT     \ ┤  right tee
DECIMAL

VARIABLE SZ-BOX-T0
VARIABLE SZ-BOX-T1
VARIABLE SZ-BOX-T2

: SZ-XEMIT  ( xchar -- )  XEMIT ;

\ Emit n horizontal bar segments (─).
: SZ-BOX-H-N  ( n -- )
   BEGIN  DUP 0> WHILE  1- SZ-BOX-H SZ-XEMIT  REPEAT  DROP
;

\ Full-width rule with NO column tees (status top / help bottom).
\ ( row left right -- )  left/right are corner xchars (╭╮ or ╰╯).
: SZ-DRAW-HBAR-PLAIN  ( row left right -- )
   SZ-BOX-T2 !  SZ-BOX-T0 !                   \ right left
   0 SWAP AT-XY
   SZ-BOX-T0 @ SZ-XEMIT
   SZ-COLS @ 2 - 0 MAX SZ-BOX-H-N
   SZ-BOX-T2 @ SZ-XEMIT
;

\ Mid rule WITH tees at gutter and editor/side columns (aligned separators).
\ ( row left mid-tee right -- )  left/right typically ├ ┤ ; mid ┬ or ┴.
: SZ-DRAW-HBAR  ( row left mid right -- )
   SZ-BOX-T2 !  SZ-BOX-T1 !  SZ-BOX-T0 !     \ right mid left temps
   0 SWAP AT-XY
   SZ-BOX-T0 @ SZ-XEMIT                      \ left (├ or corner)
   \ ─ run to gutter sep (col 1 .. LN-SEP-1)
   SZ-LN-SEP 1 - 0 MAX SZ-BOX-H-N
   SZ-BOX-T1 @ SZ-XEMIT                      \ tee at LN-SEP
   \ ─ run across text (LN-SEP+1 .. EDIT-RIGHT-1)
   SZ-EDIT-RIGHT SZ-LN-SEP - 1- 0 MAX SZ-BOX-H-N
   SZ-BOX-T1 @ SZ-XEMIT                      \ tee at EDIT-RIGHT
   \ ─ run across side panel (EDIT-RIGHT+1 .. COLS-2)
   SZ-COLS @ 1- SZ-EDIT-RIGHT - 1- 0 MAX SZ-BOX-H-N
   SZ-BOX-T2 @ SZ-XEMIT                      \ right (┤ or corner)
;

\ Outer │ only (status / help rows — full-width panels, no column seps).
: SZ-DRAW-V-OUTER  ( row -- )
   0 OVER AT-XY  SZ-BOX-V SZ-XEMIT
   SZ-COLS @ 1- SWAP AT-XY  SZ-BOX-V SZ-XEMIT
;

\ Column verticals │ on a text-body row (gutter + side + outer).
: SZ-DRAW-V-COLS  ( row -- )
   0 OVER AT-XY  SZ-BOX-V SZ-XEMIT
   SZ-LN-SEP OVER AT-XY  SZ-BOX-V SZ-XEMIT
   SZ-EDIT-RIGHT OVER AT-XY  SZ-BOX-V SZ-XEMIT
   SZ-COLS @ 1- SWAP AT-XY  SZ-BOX-V SZ-XEMIT
;

\ Emit n spaces (no DO — safe inside REDRAW's DO/LOOP and SZ-DRAW-SIDE).
: SZ-SPACES1  ( n -- )
   BEGIN  DUP 0> WHILE  1- BL EMIT  REPEAT  DROP
;

\ Full chrome: outer box + status/help sides + column mid-bars with aligned tees.
: SZ-DRAW-FRAME  ( -- )
   \ Text-band column verticals first (mid bars overwrite tees afterward)
   SZ-TEXT-BOT @ 1+ SZ-TEXT-TOP DO
      I SZ-DRAW-V-COLS
   LOOP
   \ Status + help outer sides
   SZ-STAT-ROW SZ-DRAW-V-OUTER
   SZ-HELP1 @ SZ-DRAW-V-OUTER
   SZ-HELP2 @ SZ-DRAW-V-OUTER
   \ Files-column │ through the status row (between "Select/Find" and type-in)
   SZ-EDIT-RIGHT SZ-STAT-ROW AT-XY  SZ-BOX-V SZ-XEMIT
   \ Outer top (full width); help-grid bottom is SZ-DRAW-HELP-BOT (after help paint)
   SZ-OUTER-TOP SZ-BOX-TL SZ-BOX-TR SZ-DRAW-HBAR-PLAIN
   \ Column top: ├─────┬──────────┬─────────────┤  (tees align with body │)
   SZ-FRAME-TOP SZ-BOX-LT SZ-BOX-TD SZ-BOX-RT SZ-DRAW-HBAR
   \ Column bottom (editor): ├─────┴──────────┴─────────────┤
   SZ-FRAME-BOT @ SZ-BOX-LT SZ-BOX-BU SZ-BOX-RT SZ-DRAW-HBAR
;

\ -----------------------------------------------------------------------------
\ Side panel = visit list (one row per path+line, not unique file).
\ Layout per row (SIDE-WIDTH cols):  leaf name | spaces | line# | [X]
\   SZ-FL-NAMEW name chars, then SZ-FL-LINEW digits, then "[X]" to close.
\ Hyper visit history (Cmd-PgUp/PgDn) dual-writes here; list persists session.
\ Click row body → goto that visit; click any of the three [X] cols → remove.
\ -----------------------------------------------------------------------------
 32 CONSTANT SZ-FL-MAX
256 CONSTANT SZ-FL-ESZ                       \ path counted + line cell @HOFF
248 CONSTANT SZ-FL-HOFF                      \ line cell offset (aligned)
247 CONSTANT SZ-FL-PATHMAX                   \ max path chars in entry
  5 CONSTANT SZ-FL-LINEW                     \ line number field width
  3 CONSTANT SZ-FL-XW                        \ trailing "[X]" close (3 cols hit)
\ name field = SIDE - LINEW - XW  (e.g. 28-5-3 = 20)
: SZ-FL-NAMEW  ( -- n )  SZ-SIDE-WIDTH SZ-FL-LINEW - SZ-FL-XW - ;

CREATE SZ-FL-TAB  SZ-FL-MAX SZ-FL-ESZ * ALLOT
VARIABLE SZ-FL-N
VARIABLE SZ-FL-CUR
VARIABLE SZ-FL-TOP
VARIABLE SZ-FL-P
VARIABLE SZ-FL-Q
VARIABLE SZ-FL-K
VARIABLE SZ-FL-I
VARIABLE SZ-FL-L                             \ temp line while storing
VARIABLE SZ-FL-DI                            \ paint: visit index
VARIABLE SZ-FL-DR                            \ paint: facility row
0 SZ-FL-N !
0 SZ-FL-CUR !
0 SZ-FL-TOP !

: SZ-FL-ENT  ( i -- addr )
   SZ-FL-ESZ * SZ-FL-TAB +
;

: SZ-FL-LINE@  ( i -- n )
   SZ-FL-ENT SZ-FL-HOFF + @
;

: SZ-FL-LINE!  ( n i -- )
   SZ-FL-ENT SZ-FL-HOFF + !
;

\ Leaf after last / or \   ( a u -- a' u' )
\ Store base/len in P/K then 2DROP — must not leave full path under the leaf.
: SZ-FL-LEAF  ( c-addr u -- c-addr' u' )
   DUP 0= IF  EXIT  THEN
   OVER SZ-FL-P !
   DUP SZ-FL-K !
   2DROP
   SZ-FL-K @
   BEGIN  1- DUP 0< 0= WHILE
      SZ-FL-P @ OVER + C@
      DUP [CHAR] / = SWAP [CHAR] \ = OR IF
         1+
         DUP SZ-FL-P @ +
         SWAP SZ-FL-K @ SWAP -
         EXIT
      THEN
   REPEAT
   DROP
   SZ-FL-P @ SZ-FL-K @
;

\ Store path + line at ent. ( a u line ent -- )
: SZ-FL-STORE  ( c-addr u line ent -- )
   SZ-FL-Q !                                  \ Q = ent
   SZ-FL-L !                                  \ L = line
   SZ-FL-PATHMAX MIN
   SZ-FL-K !  SZ-FL-P !
   SZ-FL-K @ SZ-FL-Q @ C!
   0 SZ-FL-I !
   BEGIN  SZ-FL-I @ SZ-FL-K @ < WHILE
      SZ-FL-P @ SZ-FL-I @ + C@
      SZ-FL-Q @ 1+ SZ-FL-I @ + C!
      1 SZ-FL-I +!
   REPEAT
   SZ-FL-L @ SZ-FL-Q @ SZ-FL-HOFF + !
;

\ Drop oldest entry (index 0).
: SZ-FL-DROP0  ( -- )
   SZ-FL-N @ 1 < IF  EXIT  THEN
   SZ-FL-TAB SZ-FL-ESZ +  SZ-FL-TAB
   SZ-FL-N @ 1- SZ-FL-ESZ *  MOVE
   -1 SZ-FL-N +!
   SZ-FL-CUR @ 0> IF  -1 SZ-FL-CUR +!  THEN
   SZ-FL-CUR @ SZ-FL-N @ >= IF
      SZ-FL-N @ 1- 0 MAX SZ-FL-CUR !
   THEN
;

\ Open hole at ins: shift [ins, N) up one slot.
: SZ-FL-OPEN  ( ins -- )
   DUP SZ-FL-N @ > IF  DROP EXIT  THEN
   SZ-FL-I !                                  \ ins
   SZ-FL-N @ SZ-FL-I @ - DUP 0= IF  DROP EXIT  THEN
   SZ-FL-ESZ * >R
   SZ-FL-I @ SZ-FL-ENT
   SZ-FL-I @ 1+ SZ-FL-ENT
   R> MOVE
;

\ Remove entry i (shift down). Adjust CUR.
\ Uses K for i — SZ-FL-STORE clobbers I and L/P/Q.
: SZ-FL-REMOVE  ( i -- )
   DUP 0< IF  DROP EXIT  THEN
   DUP SZ-FL-N @ >= IF  DROP EXIT  THEN
   SZ-FL-K !                                  \ K = i
   SZ-FL-N @ 1 = IF
      0 SZ-FL-N !  0 SZ-FL-CUR !  EXIT
   THEN
   SZ-FL-N @ SZ-FL-K @ - 1- DUP 0> IF
      SZ-FL-ESZ * >R
      SZ-FL-K @ 1+ SZ-FL-ENT
      SZ-FL-K @ SZ-FL-ENT
      R> MOVE
   ELSE  DROP  THEN
   -1 SZ-FL-N +!
   SZ-FL-CUR @ SZ-FL-K @ > IF  -1 SZ-FL-CUR +!  THEN
   SZ-FL-CUR @ SZ-FL-N @ >= IF
      SZ-FL-N @ 1- 0 MAX SZ-FL-CUR !
   THEN
;

\ Overwrite current visit (or create slot 0). ( a u line -- )
: SZ-FL-NOTE-HERE  ( c-addr u line -- )
   DUP 1 < IF  DROP 1  THEN >R                \ R: line  ( a u )
   DUP 0= IF  R> DROP 2DROP EXIT  THEN
   SZ-FL-N @ 0= IF
      2DUP R@ 0 SZ-FL-ENT SZ-FL-STORE
      2DROP R> DROP
      1 SZ-FL-N !  0 SZ-FL-CUR !
      EXIT
   THEN
   2DUP R@ SZ-FL-CUR @ SZ-FL-ENT SZ-FL-STORE
   2DROP R> DROP
;

\ Insert visit after CUR (browser branch). ( a u line -- )
\ Note: SZ-FL-STORE clobbers SZ-FL-I — keep ins on the return stack.
: SZ-FL-RECORD  ( c-addr u line -- )
   DUP 1 < IF  DROP 1  THEN
   SZ-FL-L !                                  \ L = line
   DUP 0= IF  2DROP EXIT  THEN
   SZ-FL-PATHMAX MIN
   SZ-FL-N @ SZ-FL-MAX >= IF  SZ-FL-DROP0  THEN
   SZ-FL-N @ 0= IF
      2DUP SZ-FL-L @ 0 SZ-FL-ENT SZ-FL-STORE
      2DROP
      1 SZ-FL-N !  0 SZ-FL-CUR !
      EXIT
   THEN
   SZ-FL-CUR @ 1+ >R                          \ R: ins
   R@ SZ-FL-OPEN
   2DUP SZ-FL-L @ R@ SZ-FL-ENT SZ-FL-STORE
   2DROP
   R> SZ-FL-CUR !
   1 SZ-FL-N +!
;

\ Plain open (no line): record path at line 1, or update if only noting.
: SZ-FL-ADD  ( c-addr u -- )
   1 SZ-FL-RECORD
;

: SZ-FL-NOTE-PATH  ( c-addr u -- )
   1 SZ-FL-RECORD
;

\ After load: update current visit path+line, or record if list empty.
: SZ-FL-NOTE-CURRENT  ( -- )
   SZ-HAS-NAME? 0= IF  EXIT  THEN
   SZ-GET-NAME SZ-CUR-LINE-NO
   SZ-FL-N @ IF  SZ-FL-NOTE-HERE  ELSE  SZ-FL-RECORD  THEN
;

\ Clear visit panel (Hyper rebuilds from VTAB).
\ ERASE the table — without that, a skipped PUT leaves a stale path that still
\ paints (e.g. forth.s above hyper) while empty slots paint as blank rows.
: SZ-FL-CLEAR  ( -- )
   SZ-FL-TAB  SZ-FL-MAX SZ-FL-ESZ *  ERASE
   0 SZ-FL-N !
   0 SZ-FL-CUR !
   0 SZ-FL-TOP !
;

\ Store path+line at fixed index i; grow N to at least i+1.
\ Reject empty path so rebuild never creates holes.
: SZ-FL-PUT  ( c-addr u line i -- )
   >R                                         \ R: i  ( a u line )
   OVER 0= IF  R> DROP 2DROP DROP EXIT  THEN  \ empty path
   DUP 1 < IF  DROP 1  THEN
   R@ 0< IF  R> DROP 2DROP DROP EXIT  THEN
   R@ SZ-FL-MAX >= IF  R> DROP 2DROP DROP EXIT  THEN
   R@ SZ-FL-ENT SZ-FL-STORE                   \ ( a u line ent )
   R@ 1+ SZ-FL-N @ MAX SZ-FL-N !
   R> DROP
;

\ Set current highlight index (clamped).
: SZ-FL-SET-CUR  ( i -- )
   SZ-FL-N @ 0= IF  DROP 0 SZ-FL-CUR !  EXIT  THEN
   0 MAX
   SZ-FL-N @ 1- MIN
   SZ-FL-CUR !
;

\ True if entry i has this path and line. ( a u line i -- flag )
: SZ-FL-SAME?  ( c-addr u line i -- flag )
   >R                                         \ R: i  a u line
   R@ SZ-FL-LINE@ <> IF  R> DROP 2DROP FALSE EXIT  THEN
   R> SZ-FL-ENT COUNT                         \ a u ea eu
   COMPARE 0=
;

\ Find index of path+line or -1. ( a u line -- i )
: SZ-FL-FIND-VISIT  ( c-addr u line -- i )
   SZ-FL-L !                                  \ L = line
   SZ-FL-N @ 0= IF  2DROP -1 EXIT  THEN
   0
   BEGIN  DUP SZ-FL-N @ < WHILE
      >R 2DUP SZ-FL-L @ R@ SZ-FL-SAME? IF
         2DROP R> EXIT
      THEN
      R> 1+
   REPEAT
   DROP 2DROP -1
;

\ Ensure path+line is a visit and current. Insert after CUR if new.
\ Used by SZ-HYPER-GOTO so the side list always shows the destination
\ even when Hyper→panel rebuild is unavailable.
: SZ-FL-ENSURE-VISIT  ( c-addr u line -- )
   DUP 1 < IF  DROP 1  THEN
   >R 2DUP R@ SZ-FL-FIND-VISIT                \ a u i  R: line
   DUP 0< 0= IF
      SZ-FL-CUR !  2DROP R> DROP  EXIT        \ already present
   THEN  DROP
   R> SZ-FL-RECORD
;

: SZ-FL-ENSURE-VIS  ( -- )
   SZ-FL-N @ 0= IF  0 SZ-FL-CUR !  0 SZ-FL-TOP !  EXIT  THEN
   SZ-FL-CUR @ 0 MAX SZ-FL-CUR !
   SZ-FL-CUR @ SZ-FL-N @ 1- MIN SZ-FL-CUR !
   SZ-FL-TOP @ 0 MAX SZ-FL-TOP !
   \ Keep current row in the text band; never use TOP that paints above TEXT-TOP.
   SZ-FL-N @ SZ-TEXT-ROWS <= IF  0 SZ-FL-TOP !  EXIT  THEN
   SZ-FL-CUR @ SZ-FL-TOP @ < IF
      SZ-FL-CUR @ SZ-FL-TOP !
   THEN
   SZ-FL-CUR @ SZ-FL-TOP @ SZ-TEXT-ROWS + 1- > IF
      SZ-FL-CUR @ SZ-TEXT-ROWS - 1+ 0 MAX SZ-FL-TOP !
   THEN
;

\ Right-justify n in `width` columns (uses SZ-FL-I as digit count only).
CREATE SZ-FL-LDIG  8 ALLOT
: SZ-FL-EMIT-LINE  ( n width -- )
   SZ-FL-K !                                  \ K = width (not used by LEAF after)
   DUP 0> 0= IF  DROP SZ-FL-K @ SZ-SPACES1 EXIT  THEN
   0 SZ-FL-I !
   BEGIN  DUP WHILE
      10 /MOD
      SWAP [CHAR] 0 +
      SZ-FL-I @ 8 < IF
         SZ-FL-LDIG SZ-FL-I @ + C!
         1 SZ-FL-I +!
      ELSE  DROP  THEN
   REPEAT  DROP
   SZ-FL-K @ SZ-FL-I @ - 0 MAX SZ-SPACES1
   SZ-FL-I @
   BEGIN  DUP WHILE
      1-
      DUP SZ-FL-LDIG + C@ EMIT
   REPEAT  DROP
;

\ Draw visit i at facility row. Refuses rows outside the text band.
\ Empty path still paints "(?)" + line + [X] so a hole is visible (not a dead blank).
: SZ-FL-SHOW1  ( i row -- )
   DUP SZ-TEXT-TOP < IF  2DROP EXIT  THEN
   DUP SZ-TEXT-BOT @ > IF  2DROP EXIT  THEN
   OVER SZ-FL-N @ >= IF  2DROP EXIT  THEN
   OVER 0< IF  2DROP EXIT  THEN
   SZ-SIDE-LEFT SWAP AT-XY                    \ i  (row consumed)
   DUP SZ-FL-CUR @ = IF  -1  ELSE  0  THEN FACILITY-REV
   DUP SZ-FL-ENT C@ 0= IF
      S" (?)" SZ-FL-NAMEW MIN
      DUP >R TYPE
      SZ-FL-NAMEW R> - 0 MAX SZ-SPACES1
   ELSE
      DUP SZ-FL-ENT COUNT SZ-FL-LEAF
      SZ-FL-NAMEW MIN
      DUP >R TYPE
      SZ-FL-NAMEW R> - 0 MAX SZ-SPACES1
   THEN
   \ line# then [X] close control  (i still TOS)
   DUP SZ-FL-LINE@ SZ-FL-LINEW SZ-FL-EMIT-LINE
   DROP
   S" [X]" TYPE
   0 FACILITY-REV
;

\ Paint side panel using variables only (no fragile stack loops).
: SZ-DRAW-SIDE  ( -- )
   \ Clear only text-band side cells
   SZ-TEXT-TOP SZ-FL-DR !
   BEGIN  SZ-FL-DR @ SZ-TEXT-BOT @ > 0= WHILE
      SZ-SIDE-LEFT SZ-FL-DR @ AT-XY
      SZ-SIDE-WIDTH SZ-SPACES1
      1 SZ-FL-DR +!
   REPEAT
   SZ-FL-N @ IF
      SZ-FL-ENSURE-VIS
      SZ-FL-TOP @ 0 MAX SZ-FL-DI !
      SZ-TEXT-TOP SZ-FL-DR !
      BEGIN  SZ-FL-DR @ SZ-TEXT-BOT @ > 0= WHILE
         SZ-FL-DI @ SZ-FL-N @ < IF
            SZ-FL-DI @ SZ-FL-DR @ SZ-FL-SHOW1
         THEN
         1 SZ-FL-DI +!
         1 SZ-FL-DR +!
      REPEAT
   THEN
   \ Outer right │ on text rows only (leave top/bottom ╮╯ corners intact)
   SZ-TEXT-BOT @ 1+ SZ-TEXT-TOP DO
      SZ-COLS @ 1- I AT-XY  SZ-BOX-V SZ-XEMIT
   LOOP
;

\ True if facility col is inside the trailing "[X]" close (all three columns).
\ Hit range: [ SIDE-LEFT + SIDE-WIDTH - XW , SIDE-LEFT + SIDE-WIDTH )
: SZ-FL-X-COL?  ( col -- flag )
   DUP                                        \ col col
   SZ-SIDE-LEFT SZ-SIDE-WIDTH + SZ-FL-XW -    \ col col first
   < IF  DROP FALSE EXIT  THEN                \ col < first
   SZ-SIDE-LEFT SZ-SIDE-WIDTH +               \ col past-end
   <                                          \ col < past-end
;

\ SZ-FL-GOTO / SZ-SIDE-CLICK are defined after final SZ-REDRAW (need that CFA).

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

\ Clear text field + redraw editor right border for one row (not the side panel).
: SZ-CLEAR-TEXT-ROW  ( row -- )
   SZ-TEXT-LEFT OVER AT-XY
   SZ-TEXT-WIDTH @ 0 DO  BL EMIT  LOOP
   SZ-EDIT-RIGHT SWAP AT-XY  SZ-BOX-V SZ-XEMIT
;

\ Selection range for reverse-video paint (byte addresses; end exclusive).
\ Set by sz-edit (click / drag / cut). 0 SZ-SEL-OK = no highlight.
VARIABLE SZ-SEL-BEG
VARIABLE SZ-SEL-END
VARIABLE SZ-SEL-OK
0 SZ-SEL-OK !

\ True if buffer address `addr` lies in the active selection [beg,end).
: SZ-IN-SEL?  ( addr -- flag )
   SZ-SEL-OK @ 0= IF  DROP 0 EXIT  THEN
   DUP SZ-SEL-BEG @ U< IF  DROP 0 EXIT  THEN
   SZ-SEL-END @ U<
;

\ Paint one text row with horizontal scroll (SZ-HCOL = first visible column).
\ No >R here — REDRAW is inside DO and must not nest return-stack temps.
\ Selected bytes use FACILITY-REV so the host can reverse-video those cells.
VARIABLE SZ-SKIP
VARIABLE SZ-PAINTED
VARIABLE SZ-REV-ON
: SZ-SHOW-LINE  ( line-addr row -- )
   DUP SZ-CLEAR-TEXT-ROW
   SZ-TEXT-LEFT SWAP AT-XY
   SZ-PARSE-LINE                    ( a u )
   SZ-HCOL @ OVER MIN SZ-SKIP !     ( a u )
   SZ-SKIP @ - 0 MAX                ( a u' )
   SWAP SZ-SKIP @ + SWAP            ( a' u' )
   SZ-TEXT-WIDTH @ MIN
   DUP SZ-PAINTED !
   0 SZ-REV-ON !
   0 FACILITY-REV
   DUP 0= IF  2DROP EXIT  THEN
   0 DO
      DUP I +                       ( a addr )
      DUP SZ-IN-SEL?                ( a addr newrev )
      DUP SZ-REV-ON @ = 0= IF       \ state change?
         DUP SZ-REV-ON !            ( a addr newrev )
         FACILITY-REV               ( a addr )  \ consume newrev — do not @ again
      ELSE  DROP  THEN              ( a addr )
      C@ SZ-GLYPH EMIT
   LOOP
   DROP
   0 SZ-REV-ON !
   0 FACILITY-REV
   \ Pad to full TEXT-WIDTH so the border never rides on leftover content
   SZ-TEXT-WIDTH @ SZ-PAINTED @ - 0 MAX 0 ?DO  BL EMIT  LOOP
;

\ Selected / find query shown in status (counted; room for long typed find).
CREATE SZ-SEL-WORD  66 ALLOT
0 SZ-SEL-WORD C!
\ Find note shown after the query (e.g. no next / no prev / type).
CREATE SZ-FIND-STAT  18 ALLOT
0 SZ-FIND-STAT C!
\ Nonzero while Cmd-F status-field find edit is active (sz-edit).
VARIABLE SZ-FIND-EDIT
0 SZ-FIND-EDIT !
\ Insert index within the type-in field (0-based; used by caret + editing).
VARIABLE SZ-FIND-ICOL
0 SZ-FIND-ICOL !
\ Nonzero: query from type-in/selection → substring search (not whole-word).
VARIABLE SZ-FIND-TYPED
0 SZ-FIND-TYPED !
\ Hyper multi-hit: 1-based index and total (0 total = hide). Set by Hyper via
\ SZ-HYPER-HITS! so status can show (1/4) after the filename.
0 VALUE SZ-HH-CUR
0 VALUE SZ-HH-TOT

\ Status / help content must not wrap (would spill into the next chrome row).
\ Room for text inside the outer box = SZ-COLS - 2 (left/right │).
VARIABLE SZ-ROOM                          \ remaining printable cols on the row
VARIABLE SZ-ROOM-KEEP                     \ cols to leave unused (status: Sel: reserve)

: SZ-ROOM-SET  ( -- )
   SZ-COLS @ 2 - 0 MAX SZ-ROOM !
   0 SZ-ROOM-KEEP !
;

: SZ-ROOM-EMIT  ( c -- )
   \ Stop when only the reserved tail (e.g. Selected:) remains
   SZ-ROOM @ SZ-ROOM-KEEP @ <= IF  DROP EXIT  THEN
   EMIT  -1 SZ-ROOM +!
;

: SZ-ROOM-TYPE  ( c-addr u -- )
   BEGIN  DUP 0>  SZ-ROOM @ 0>  AND WHILE
      OVER C@ SZ-ROOM-EMIT
      1 /STRING
   REPEAT  2DROP
;

\ Type a decimal number without trailing space (0 .R style) into SZ-ROOM.
CREATE SZ-NUMBUF  16 ALLOT
VARIABLE SZ-NUMN
: SZ-ROOM-U.  ( u -- )
   0 SZ-NUMN !
   DUP 0= IF
      [CHAR] 0 SZ-ROOM-EMIT  DROP EXIT
   THEN
   BEGIN  DUP WHILE
      10 /MOD                               \ rem quot
      SWAP [CHAR] 0 +
      SZ-NUMN @ 16 < IF
         SZ-NUMBUF SZ-NUMN @ + C!
         1 SZ-NUMN +!
      ELSE  DROP  THEN
   REPEAT  DROP
   SZ-NUMN @
   BEGIN  DUP WHILE
      1-
      DUP SZ-NUMBUF + C@ SZ-ROOM-EMIT
   REPEAT  DROP
;

\ Path leaf shown in status: at most 30 chars (tail).
30 CONSTANT SZ-STAT-PATHMAX

\ Title left of the Files separator: "Select/Find" (ends at EDIT-RIGHT).
11 CONSTANT SZ-SEL-LABW

\ Type-in / highlight area: under visit list (SIDE-LEFT .. COLS-2).
: SZ-SEL-FIELD-W  ( -- n )
   SZ-COLS @ 1- SZ-SIDE-LEFT - 0 MAX
;

\ Max query chars in the type-in area (full side width).
: SZ-SEL-TEXT-MAX  ( -- n )  SZ-SEL-FIELD-W ;

\ First column of the "Select/Find" title (title ends at EDIT-RIGHT).
: SZ-SEL-TITLE-COL  ( -- col )
   SZ-EDIT-RIGHT SZ-SEL-LABW - 1 MAX
;

\ Status row:
\   cols 1 .. title-1     path + meta
\   title .. EDIT-RIGHT-1 "Select/Find"
\   EDIT-RIGHT            │  (Files separator extended up)
\   SIDE-LEFT .. COLS-2   type-in / highlighted find text
: SZ-SHOW-STATUS  ( -- )
   SZ-STAT-ROW SZ-BLANK-ROW
   \ --- path + meta (must not run into the Select/Find title) ---
   1 SZ-STAT-ROW AT-XY
   SZ-SEL-TITLE-COL 1 - 0 MAX SZ-ROOM !
   0 SZ-ROOM-KEEP !
   SZ-HAS-NAME? IF
      SZ-GET-NAME                             \ a u
      DUP SZ-STAT-PATHMAX > IF
         SZ-STAT-PATHMAX - +  SZ-STAT-PATHMAX
      THEN
      SZ-ROOM-TYPE
   ELSE
      S" untitled" SZ-ROOM-TYPE
   THEN
   SZ-HH-TOT 1 > IF
      [CHAR] ( SZ-ROOM-EMIT
      SZ-HH-CUR SZ-ROOM-U.
      [CHAR] / SZ-ROOM-EMIT
      SZ-HH-TOT SZ-ROOM-U.
      [CHAR] ) SZ-ROOM-EMIT
   THEN
   SZ-MODIFIED @ IF  [CHAR] * SZ-ROOM-EMIT  THEN
   S"  L:" SZ-ROOM-TYPE  SZ-CUR-LINE-NO SZ-ROOM-U.
   S"  C:" SZ-ROOM-TYPE  SZ-CUR-COL 1+ SZ-ROOM-U.
   S"  " SZ-ROOM-TYPE  SZ-TLEN @ SZ-ROOM-U.   \ file/buffer size only (no "b", no capacity)
   \ --- title ends at the Files-column vertical ---
   SZ-SEL-TITLE-COL SZ-STAT-ROW AT-XY
   S" Select/Find" TYPE
   \ --- type-in area right of the Files separator (query text only) ---
   \ Do not paint SZ-FIND-STAT here (e.g. "paste here", "selected") — those notes
   \ clutter the find box. Find-edit feedback ("no match") is shown while FIND-EDIT.
   SZ-SIDE-LEFT SZ-STAT-ROW AT-XY
   SZ-SEL-FIELD-W SZ-ROOM !
   0 SZ-ROOM-KEEP !
   SZ-SEL-WORD COUNT SZ-SEL-TEXT-MAX MIN SZ-ROOM-TYPE
   \ Find-edit notes (e.g. "(no next)") flush-right at end of field, not after query
   SZ-FIND-EDIT @ IF
      SZ-FIND-STAT C@ IF
         SZ-ROOM @ SZ-FIND-STAT C@ - 0 MAX
         BEGIN  DUP 0> WHILE  1- BL SZ-ROOM-EMIT  REPEAT  DROP
         SZ-FIND-STAT COUNT SZ-ROOM-TYPE
      THEN
   THEN
   \ Pad any leftover (plain spaces; I-beam shows insert point)
   BEGIN  SZ-ROOM @ 0> WHILE  BL SZ-ROOM-EMIT  REPEAT
;

\ -----------------------------------------------------------------------------
\ Help panel: 4 columns with graphic │ separators aligned on both rows.
\ Fixed field widths so row1/row2 separators line up; last col takes the rest.
\ Outer bottom bar uses matching ┴ tees so the help grid is fully boxed.
\ -----------------------------------------------------------------------------
 16 CONSTANT SZ-HELP-W1          \ "Cmd-E/click VIEW" / "drag/Shift-click" + pad
 18 CONSTANT SZ-HELP-W2          \ "Cmd-PgUp/Dn visits" / "dbl-word tri-line"
 15 CONSTANT SZ-HELP-W3          \ "side: line# [X]" / "Cmd-click VIEW"
\ W4 = remaining inner width after W1+W2+W3 + 3 separators

VARIABLE SZ-HELP-R
VARIABLE SZ-HELP-A1  VARIABLE SZ-HELP-U1
VARIABLE SZ-HELP-A2  VARIABLE SZ-HELP-U2
VARIABLE SZ-HELP-A3  VARIABLE SZ-HELP-U3
VARIABLE SZ-HELP-A4  VARIABLE SZ-HELP-U4

: SZ-HELP-INNER  ( -- n )  SZ-COLS @ 2 - 0 MAX ;

: SZ-HELP-W4  ( -- n )
   SZ-HELP-INNER SZ-HELP-W1 - SZ-HELP-W2 - SZ-HELP-W3 - 3 - 0 MAX
;

\ Absolute facility columns of the three help separators (for tees / verticals).
: SZ-HELP-SEP1  ( -- col )  1 SZ-HELP-W1 + ;
: SZ-HELP-SEP2  ( -- col )  SZ-HELP-SEP1 1+ SZ-HELP-W2 + ;
: SZ-HELP-SEP3  ( -- col )  SZ-HELP-SEP2 1+ SZ-HELP-W3 + ;

\ Type field left-justified in `width` cols (clipped + space pad). Uses SZ-ROOM.
: SZ-HELP-FIELD  ( c-addr u width -- )
   >R                                         \ a u  R:width
   R@ MIN                                     \ a u'
   DUP >R SZ-ROOM-TYPE                        \ R:width u'
   R> R> SWAP - 0 MAX                         \ pad
   BEGIN  DUP 0> WHILE  1- BL SZ-ROOM-EMIT  REPEAT  DROP
;

: SZ-HELP-V  ( -- )
   SZ-BOX-V SZ-XEMIT
   SZ-ROOM @ 0> IF  -1 SZ-ROOM +!  THEN
;

\ Paint four fixed-width help fields + │ seps on `row`.
: SZ-HELP-LINE  ( a1 u1 a2 u2 a3 u3 a4 u4 row -- )
   SZ-HELP-R !                                \ row
   SZ-HELP-U4 !  SZ-HELP-A4 !
   SZ-HELP-U3 !  SZ-HELP-A3 !
   SZ-HELP-U2 !  SZ-HELP-A2 !
   SZ-HELP-U1 !  SZ-HELP-A1 !
   SZ-HELP-R @ SZ-BLANK-ROW
   1 SZ-HELP-R @ AT-XY
   SZ-ROOM-SET
   SZ-HELP-A1 @ SZ-HELP-U1 @ SZ-HELP-W1 SZ-HELP-FIELD  SZ-HELP-V
   SZ-HELP-A2 @ SZ-HELP-U2 @ SZ-HELP-W2 SZ-HELP-FIELD  SZ-HELP-V
   SZ-HELP-A3 @ SZ-HELP-U3 @ SZ-HELP-W3 SZ-HELP-FIELD  SZ-HELP-V
   SZ-HELP-A4 @ SZ-HELP-U4 @ SZ-HELP-W4 SZ-HELP-FIELD
   \ Outer + column │ (blank wiped them)
   SZ-HELP-R @ SZ-DRAW-V-OUTER
   SZ-HELP-SEP1 SZ-HELP-R @ AT-XY  SZ-BOX-V SZ-XEMIT
   SZ-HELP-SEP2 SZ-HELP-R @ AT-XY  SZ-BOX-V SZ-XEMIT
   SZ-HELP-SEP3 SZ-HELP-R @ AT-XY  SZ-BOX-V SZ-XEMIT
;

\ Bottom outer bar with ┴ at help-column separators (aligned with help │).
: SZ-DRAW-HELP-BOT  ( -- )
   0 SZ-OUTER-BOT @ AT-XY
   SZ-BOX-BL SZ-XEMIT
   SZ-HELP-W1 0 MAX SZ-BOX-H-N
   SZ-BOX-BU SZ-XEMIT                         \ ┴ under sep1
   SZ-HELP-W2 0 MAX SZ-BOX-H-N
   SZ-BOX-BU SZ-XEMIT
   SZ-HELP-W3 0 MAX SZ-BOX-H-N
   SZ-BOX-BU SZ-XEMIT
   SZ-HELP-W4 SZ-BOX-H-N
   SZ-BOX-BR SZ-XEMIT
;

\ Two help rows with aligned │ columns + bottom tees.
: SZ-SHOW-HELP  ( -- )
   \ Row1 — W1 matches "Cmd-E/click VIEW" (16); row2 pads to same width
   S" Cmd-E/click VIEW" S" Cmd-PgUp/Dn visits"
   S" side: line# [X]" S" find Cmd-F/G"
   SZ-HELP1 @ SZ-HELP-LINE
   \ Row2 — "drag/Shift-click" (15) padded to W1=16 so │ lines up under row1
   S" drag/Shift-click" S" dbl-word tri-line"
   S" Cmd-click VIEW" S" Cmd-X/C/V/S/W"
   SZ-HELP2 @ SZ-HELP-LINE
   SZ-DRAW-HELP-BOT
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
   \ Cmd-F: caret stays in the type-in area until Esc/Enter (never in document)
   SZ-FIND-EDIT @ IF
      SZ-SIDE-LEFT SZ-FIND-ICOL @ +
      SZ-COLS @ 2 - MIN  SZ-SIDE-LEFT MAX
      SZ-STAT-ROW AT-XY
      EXIT
   THEN
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

\ Paint path without size-sync (SZ-REDRAW redefined after SET-EDIT-WINDOW).
: SZ-REDRAW-CORE  ( -- )
   SZ-ENSURE-VISIBLE
   0 SZ-HAVE-AT !
   0 SZ-DID-EMPTY-TEND !
   PAGE
   \ Content first (may blank whole rows), then chrome so outer │ / ─ win.
   SZ-SHOW-STATUS
   SZ-SHOW-HELP
   SZ-DRAW-FRAME
   SZ-DRAW-SIDE
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
   SZ-PLACE-CURSOR
   TERMINAL-REFRESH
;

: SZ-REDRAW  ( -- )  SZ-REDRAW-CORE ;

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
   \ Facility: editor (W+8) + side content + outer │ + height (H+7 chrome)
   SZ-WIN-W @ 8 + SZ-SIDE-WIDTH + 1+  SZ-WIN-H @ SZ-CHROME-ROWS +  (FACILITY-SIZE)
;

\ Match facility size to the graphic window (host monospaced metrics).
\ Defined after SET-EDIT-WINDOW so it calls the full version (layout + grid resize),
\ not the sz-host stub that only stores W/H.
\ (SZ-VIEW-CELLS) → full facility cols/rows (editor + side + outer │); 5 cmd lines below.
\ Text body: width = cols - 8 - SIDE - 1, height = rows - SZ-CHROME-ROWS.
: SZ-SYNC-SIZE  ( -- )
   (SZ-VIEW-CELLS)                            \ fcols frows
   SWAP 8 - SZ-SIDE-WIDTH - 1- 16 MAX         \ frows twidth
   SWAP SZ-CHROME-ROWS - 5 MAX                \ twidth theight
   OVER SZ-WIN-W @ =
   OVER SZ-WIN-H @ = AND IF  2DROP EXIT  THEN
   SET-EDIT-WINDOW
;

\ Final REDRAW: sync window size then paint (redefines earlier stub).
: SZ-REDRAW  ( -- )
   SZ-SYNC-SIZE
   SZ-REDRAW-CORE
;

\ Line apply — stub until sz-edit defines SZ-GOTO-LINE (load order).
: SZ-FL-APPLY-LINE  ( n -- )  DROP ;

\ Switch editor to visit i (path + stored line). No-op if already current.
\ Defined here so SZ-REDRAW is the final (sync+paint) version.
\ Full dirty-check version is redefined in sz-edit.fth.
: SZ-FL-GOTO  ( i -- )
   DUP 0< IF  DROP EXIT  THEN
   DUP SZ-FL-N @ >= IF  DROP EXIT  THEN
   DUP SZ-FL-CUR !
   DUP SZ-FL-ENT COUNT                        \ i a u
   2DUP SZ-LOAD IF
      ." cannot open " TYPE CR 2DROP DROP EXIT
   THEN
   2DROP                                      \ i
   DUP SZ-FL-LINE@ SZ-FL-APPLY-LINE
   DROP
   SZ-REDRAW
;

\ Click side panel: X column removes visit; else goto that visit.
: SZ-SIDE-CLICK  ( col row -- )
   OVER SZ-EDIT-RIGHT > 0= IF  2DROP EXIT  THEN
   OVER SZ-COLS @ 1- < 0= IF  2DROP EXIT  THEN
   DUP SZ-TEXT-TOP < IF  2DROP EXIT  THEN
   DUP SZ-TEXT-BOT @ > IF  2DROP EXIT  THEN
   SZ-TEXT-TOP - SZ-FL-TOP @ +                \ col i
   DUP 0< IF  2DROP EXIT  THEN
   DUP SZ-FL-N @ >= IF  2DROP EXIT  THEN
   SWAP SZ-FL-X-COL? IF
      SZ-FL-REMOVE
      SZ-REDRAW
   ELSE
      SZ-FL-GOTO
   THEN
;

\ Apply current window size to facility grid at load
SZ-WIN-W @ 8 + SZ-SIDE-WIDTH + 1+  SZ-WIN-H @ SZ-CHROME-ROWS +  (FACILITY-SIZE)
