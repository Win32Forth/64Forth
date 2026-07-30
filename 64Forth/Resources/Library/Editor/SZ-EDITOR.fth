\ SZ-EDITOR.fth — Small Zimmer Editor for TZForth (port driver)
\
\ Phases 1-4: host, buffer, mono screen, minimal interactive edit.
\ Reference (read-only): Legacy/SmallZimmerEditor.fth
\
\ Load (from Resources/Library):
\   FROMLIB FLOAD Editor/SZ-EDITOR.fth
\
\ Try:
\   SZ-HOST-SMOKE
\   SZ-BUFFER-SMOKE
\   SZ-SCREEN-SMOKE
\   S" my.txt" SZ-EDIT-FILE
\   SZEDIT my.txt <return>
\
\ Keys in editor: ^S save  ^Q quit  ^B^F left/right  ^P^N up/down
\                 type to insert  Enter newline  BS delete
\
\ Nested modules: named FLOAD chdirs to this file's folder (Editor/), so
\ sibling names need no Editor/ prefix.

ANEW SZ-EDITOR

\ Body words go in the standard EDITOR vocabulary (boot-time VOCABULARY EDITOR).
\ ANEW rewinds FORTH/DP but does not clear EDITOR's head, so empty it first on
\ every load — otherwise reload leaves dangling links into forgotten headers.
ONLY FORTH ALSO EDITOR DEFINITIONS
0 GET-CURRENT !

FLOAD sz-host.fth
FLOAD sz-buffer.fth
FLOAD sz-screen.fth
FLOAD sz-edit.fth

: SZ-BANNER  ( -- )
   CR
   ." === SZ-EDITOR TZForth port ===" CR
   ." Phases 1-5: edit + navigation + framed screen" CR
   ." File menu: Cmd-S Save  Cmd-W Close editor  or  SZEDIT file" CR
   ." Keys: arrows  Home/End  PgUp/Dn  BS Del  type  Ctrl-Q close" CR
   ." Dirty close/quit: Modified! Save or Discard? S/D  (other=cancel)" CR
   ." Size: width height SET-EDIT-WINDOW  - default 80 20" CR
   ." Cmd-W closes editor   Cmd-Q quits app after editor close" CR
   CR
;

SZ-BANNER

FORTH DEFINITIONS
ONLY FORTH ALSO EDITOR
\ Parse a path and edit. No path → usage / open panel when host supports it.
\   SZEDIT my.txt
\   S" /path/to/file" SZ-EDIT-FILE
\   FROMLIB SZEDIT Editor/SZ-EDITOR-README.txt
: SZEDIT  ( -- )
   BL WORD COUNT
   DUP 0= IF  2DROP SZ-HOST-REQUEST-OPEN EXIT  THEN
   SZ-EDIT-FILE
;

ONLY FORTH DEFINITIONS

