\ sz-fl-test.fth — side-panel visit list + Hyper goto (automated)
\
\ Run (Editor + Hyper already loaded via AutoLoad):
\   FROMLIB FLOAD Editor/sz-fl-test.fth
\
\ Expected: console transcript only (markers, PASS count, ALL PASS).
\ No facility editor paint.
\
\ Host: SZFLTEST=1 after AutoLoad → /tmp/sz-fl-test-results.txt
\
\ CRITICAL: no IF/BEGIN while interpreting — only inside colon defs.

DECIMAL
\ EDITOR is CURRENT (top); HYPER-VOC still searchable for TO HYPER-LINE# / HYPER-HIT.
ONLY FORTH ALSO HYPER-VOC ALSO EDITOR DEFINITIONS

VARIABLE FL#PASS
VARIABLE FL#FAIL
0 FL#PASS !
0 FL#FAIL !

: FL.PASS  ( -- )  FL#PASS @ 1+ FL#PASS ! ;
: FL.FAIL  ( c-addr u -- )
   FL#FAIL @ 1+ FL#FAIL !
   ." FAIL: " TYPE CR
;
: FL.EXPECT  ( flag c-addr u -- )
   ROT IF  2DROP FL.PASS  ELSE  FL.FAIL  THEN
;

: FL.RESET  ( -- )
   0 SZ-FL-N !
   0 SZ-FL-CUR !
   0 SZ-FL-TOP !
;

: FL.DEPTH0?  ( -- flag )  DEPTH 0= ;
: FL.EMPTY  ( -- )  BEGIN DEPTH WHILE DROP REPEAT ;
: FL.PATH=  ( a1 u1 a2 u2 -- flag )  COMPARE 0= ;

: FL.MARK  ( c-addr u -- )  ." -- " TYPE ." --" CR ;

\ ---- leaf (stack-safe) ----

: T-FL-LEAF-UNIT  ( -- )
   FL.EMPTY
   S" Library/Sources/forth.s" SZ-FL-LEAF S" forth.s" FL.PATH=
      S" LEAF Library/Sources/forth.s" FL.EXPECT
   S" Kernel/forth.s" SZ-FL-LEAF S" forth.s" FL.PATH=
      S" LEAF Kernel/forth.s" FL.EXPECT
   FL.DEPTH0? S" LEAF stack clean" FL.EXPECT
;

\ ---- visit record / note / two lines same file ----

: T-FL-RECORD-ONE  ( -- )
   FL.EMPTY FL.RESET
   S" Library/Hyper/hyper.fth" 679 SZ-FL-RECORD
   SZ-FL-N @ 1 = S" RECORD one N=1" FL.EXPECT
   SZ-FL-CUR @ 0 = S" RECORD one CUR=0" FL.EXPECT
   0 SZ-FL-LINE@ 679 = S" RECORD one line 679" FL.EXPECT
   0 SZ-FL-ENT COUNT S" Library/Hyper/hyper.fth" FL.PATH=
      S" RECORD one path" FL.EXPECT
   FL.DEPTH0? S" RECORD one stack" FL.EXPECT
;

: T-FL-TWO-VISITS-SAME-FILE  ( -- )
   FL.EMPTY FL.RESET
   S" Library/Sources/forth.s" 100 SZ-FL-RECORD
   S" Library/Sources/forth.s" 1148 SZ-FL-RECORD
   SZ-FL-N @ 2 = S" two visits same file N=2" FL.EXPECT
   SZ-FL-CUR @ 1 = S" two visits CUR=1" FL.EXPECT
   0 SZ-FL-LINE@ 100 = S" visit0 line 100" FL.EXPECT
   1 SZ-FL-LINE@ 1148 = S" visit1 line 1148" FL.EXPECT
   FL.DEPTH0? S" two visits stack" FL.EXPECT
;

: T-FL-INSERT-AFTER-CURRENT  ( -- )
   \ hyper@679 → forth@1148 → back to hyper (CUR=0) → insert SZ-EDITOR after hyper
   FL.EMPTY FL.RESET
   S" Library/Hyper/hyper.fth" 679 SZ-FL-RECORD
   S" Library/Sources/forth.s" 1148 SZ-FL-RECORD
   0 SZ-FL-CUR !                              \ simulate Cmd-PgUp to hyper
   S" Library/Editor/SZ-EDITOR.fth" 22 SZ-FL-RECORD
   SZ-FL-N @ 3 = S" insert mid N=3" FL.EXPECT
   SZ-FL-CUR @ 1 = S" insert mid CUR=1 (new)" FL.EXPECT
   0 SZ-FL-ENT COUNT S" Library/Hyper/hyper.fth" FL.PATH=
      S" insert [0] hyper" FL.EXPECT
   1 SZ-FL-ENT COUNT S" Library/Editor/SZ-EDITOR.fth" FL.PATH=
      S" insert [1] SZ-EDITOR" FL.EXPECT
   2 SZ-FL-ENT COUNT S" Library/Sources/forth.s" FL.PATH=
      S" insert [2] forth (shifted)" FL.EXPECT
   1 SZ-FL-LINE@ 22 = S" insert SZ-EDITOR line 22" FL.EXPECT
   2 SZ-FL-LINE@ 1148 = S" insert forth still 1148" FL.EXPECT
   FL.DEPTH0? S" insert mid stack" FL.EXPECT
;

: T-FL-NOTE-HERE-OVERWRITE  ( -- )
   FL.EMPTY FL.RESET
   S" Library/Hyper/hyper.fth" 679 SZ-FL-RECORD
   S" Library/Hyper/hyper.fth" 691 SZ-FL-NOTE-HERE
   SZ-FL-N @ 1 = S" NOTE-HERE N stays 1" FL.EXPECT
   0 SZ-FL-LINE@ 691 = S" NOTE-HERE line becomes 691" FL.EXPECT
   FL.DEPTH0? S" NOTE-HERE stack" FL.EXPECT
;

: T-FL-REMOVE  ( -- )
   FL.EMPTY FL.RESET
   S" a.fth" 1 SZ-FL-RECORD
   S" b.fth" 2 SZ-FL-RECORD
   S" c.fth" 3 SZ-FL-RECORD
   1 SZ-FL-REMOVE                             \ drop b
   SZ-FL-N @ 2 = S" REMOVE mid N=2" FL.EXPECT
   0 SZ-FL-ENT COUNT S" a.fth" FL.PATH= S" REMOVE [0]=a" FL.EXPECT
   1 SZ-FL-ENT COUNT S" c.fth" FL.PATH= S" REMOVE [1]=c" FL.EXPECT
   0 SZ-FL-REMOVE
   SZ-FL-N @ 1 = S" REMOVE head N=1" FL.EXPECT
   0 SZ-FL-ENT COUNT S" c.fth" FL.PATH= S" REMOVE left c" FL.EXPECT
   0 SZ-FL-REMOVE
   SZ-FL-N @ 0 = S" REMOVE last N=0" FL.EXPECT
   FL.DEPTH0? S" REMOVE stack" FL.EXPECT
;

: T-FL-X-COL  ( -- )
   \ [X] occupies the last SZ-FL-XW columns of the side panel
   SZ-SIDE-LEFT SZ-SIDE-WIDTH + 1- SZ-FL-X-COL?
      S" X-COL last col is hit" FL.EXPECT
   SZ-SIDE-LEFT SZ-SIDE-WIDTH + SZ-FL-XW - SZ-FL-X-COL?
      S" X-COL first [ of [X] is hit" FL.EXPECT
   SZ-SIDE-LEFT SZ-SIDE-WIDTH + SZ-FL-XW - 1- SZ-FL-X-COL? 0=
      S" X-COL before [X] is not hit" FL.EXPECT
   SZ-SIDE-LEFT SZ-FL-X-COL? 0=
      S" X-COL not side left" FL.EXPECT
   SZ-FL-XW 3 = S" XW is 3 for [X]" FL.EXPECT
   FL.DEPTH0? S" X-COL stack" FL.EXPECT
;

: T-FL-NAMEW  ( -- )
   SZ-FL-NAMEW SZ-SIDE-WIDTH SZ-FL-LINEW - SZ-FL-XW - =
      S" NAMEW = SIDE-LINEW-XW" FL.EXPECT
   SZ-SIDE-WIDTH 20 > S" SIDE-WIDTH > 20 (room for line+X)" FL.EXPECT
   FL.DEPTH0? S" NAMEW stack" FL.EXPECT
;

: T-FL-PUT-REBUILD  ( -- )
   FL.EMPTY FL.RESET
   S" Library/Hyper/hyper.fth" 679 0 SZ-FL-PUT
   S" Library/Sources/forth.s" 1148 1 SZ-FL-PUT
   1 SZ-FL-SET-CUR
   SZ-FL-N @ 2 = S" PUT rebuild N=2" FL.EXPECT
   SZ-FL-CUR @ 1 = S" PUT rebuild CUR=1" FL.EXPECT
   0 SZ-FL-LINE@ 679 = S" PUT [0] line 679" FL.EXPECT
   1 SZ-FL-LINE@ 1148 = S" PUT [1] line 1148" FL.EXPECT
   1 SZ-FL-ENT COUNT S" Library/Sources/forth.s" FL.PATH=
      S" PUT [1] path forth.s" FL.EXPECT
   \ Order: index 0 is always first visit (hyper), not forth.
   0 SZ-FL-ENT COUNT SZ-FL-LEAF S" hyper.fth" FL.PATH=
      S" PUT order [0]=hyper.fth" FL.EXPECT
   FL.DEPTH0? S" PUT stack" FL.EXPECT
;

: T-FL-SHOW1-BAND  ( -- )
   \ Painting on separator (row < TEXT-TOP) must be a no-op / safe.
   FL.EMPTY FL.RESET
   S" Library/Hyper/hyper.fth" 679 SZ-FL-RECORD
   0 SZ-FRAME-TOP SZ-FL-SHOW1                 \ must not crash
   0 SZ-TEXT-TOP SZ-FL-SHOW1                  \ valid band
   FL.DEPTH0? S" SHOW1 band stack clean" FL.EXPECT
;

\ Simulate VIEW then Cmd-click EXIT: origin then dest must both be listed.
: T-FL-ENSURE-VISIT-DEST  ( -- )
   FL.EMPTY FL.RESET
   S" Library/Hyper/hyper.fth" 679 SZ-FL-RECORD
   S" Library/Sources/forth.s" 1148 SZ-FL-ENSURE-VISIT
   SZ-FL-N @ 2 = S" ENSURE dest N=2" FL.EXPECT
   SZ-FL-CUR @ 1 = S" ENSURE dest CUR=1" FL.EXPECT
   1 SZ-FL-ENT COUNT S" Library/Sources/forth.s" FL.PATH=
      S" ENSURE dest path forth.s" FL.EXPECT
   1 SZ-FL-LINE@ 1148 = S" ENSURE dest line 1148" FL.EXPECT
   \ second ENSURE same visit does not duplicate
   S" Library/Sources/forth.s" 1148 SZ-FL-ENSURE-VISIT
   SZ-FL-N @ 2 = S" ENSURE idempotent N=2" FL.EXPECT
   FL.DEPTH0? S" ENSURE stack" FL.EXPECT
;

\ ---- load + hyper-goto-core (no facility paint) ----

: FL.HYPER-GOTO-CORE  ( c-addr u line -- )
   >R
   255 MIN SZ-PATH-TMP SZ-PLACE
   SZ-PATH-TMP COUNT
   2DUP SZ-LOAD IF  R> DROP 2DROP EXIT  THEN
   2DROP
   R> SZ-GOTO-LINE
;

: T-LOAD-FORTH-S  ( -- )
   FL.EMPTY FL.RESET
   S" Library/Sources/forth.s" SZ-LOAD
   0= S" LOAD forth.s ior=0" FL.EXPECT
   SZ-HAS-NAME? S" LOAD forth.s has name" FL.EXPECT
   SZ-TLEN @ 0> S" LOAD forth.s non-empty" FL.EXPECT
   FL.DEPTH0? S" LOAD stack" FL.EXPECT
;

: T-VISIT-GOTO-LINE  ( -- )
   FL.EMPTY FL.RESET
   S" Library/Sources/forth.s" 1148 SZ-FL-RECORD
   S" Library/Sources/forth.s" 1148 FL.HYPER-GOTO-CORE
   SZ-CUR-LINE-NO 1148 = S" goto-core line 1148" FL.EXPECT
   FL.DEPTH0? S" goto-core stack" FL.EXPECT
;

: T-FL-NOTE-CURRENT-AFTER-GOTO  ( -- )
   FL.EMPTY FL.RESET
   S" Library/Hyper/hyper.fth" SZ-LOAD DROP
   679 SZ-GOTO-LINE
   SZ-FL-NOTE-CURRENT
   SZ-FL-N @ 1 = S" NOTE-CURRENT N=1" FL.EXPECT
   0 SZ-FL-LINE@ 679 = S" NOTE-CURRENT line 679" FL.EXPECT
   FL.DEPTH0? S" NOTE-CURRENT stack" FL.EXPECT
;

\ ---- Hyper dual-write (if loaded) ----

\ Plant hit path+line (HYPER-VOC visible at compile of this file).
: FL.PLANT-HIT  ( c-addr u line -- )
   TO HYPER-LINE#
   HYPER-HIT PLACE
;

\ Hyper bind must see SZ-FL-RECORD / SZ-FL-NOTE-HERE after editor load.
: T-HYPER-FL-BIND  ( -- )
   FL.EMPTY FL.RESET
   ONLY FORTH ALSO HYPER-VOC
   S" HYPER-BIND-EDITOR" FIND IF  EXECUTE DROP  ELSE  DROP THEN
   S" HYPER-FL-REC-XT" FIND IF
      EXECUTE 0<> S" HYPER-FL-REC-XT bound" FL.EXPECT
   ELSE  DROP S" HYPER-FL-REC-XT missing" FL.FAIL  THEN
   S" HYPER-FL-NOTE-XT" FIND IF
      EXECUTE 0<> S" HYPER-FL-NOTE-XT bound" FL.EXPECT
   ELSE  DROP S" HYPER-FL-NOTE-XT missing" FL.FAIL  THEN
   ONLY FORTH ALSO EDITOR
   FL.EMPTY
;

: T-HYPER-V-REMOVE  ( -- )
   FL.EMPTY FL.RESET
   ONLY FORTH ALSO HYPER-VOC
   HYPER-HIST-CLEAR
   S" Library/Hyper/hyper.fth" 10 0 HYPER-V-STORE
   S" Library/Sources/forth.s" 20 1 HYPER-V-STORE
   2 TO HYPER-VN
   1 TO HYPER-VI
   0 HYPER-V-REMOVE
   HYPER-VN 1 = S" V-REMOVE VN=1" FL.EXPECT
   HYPER-VI 0 = S" V-REMOVE VI clamped" FL.EXPECT
   ONLY FORTH ALSO EDITOR
   FL.EMPTY
;

\ CLEAR must wipe table memory — otherwise a later PUT at index 1 leaves
\ stale path at index 0 (user: forth.s painted above HYPER.fth).
: T-FL-CLEAR-ERASES  ( -- )
   FL.EMPTY FL.RESET
   S" Library/Sources/forth.s" 2840 SZ-FL-RECORD
   S" Library/Hyper/hyper.fth" 806 SZ-FL-RECORD
   SZ-FL-CLEAR
   SZ-FL-N @ 0 = S" CLEAR N=0" FL.EXPECT
   0 SZ-FL-ENT C@ 0 = S" CLEAR [0] count erased" FL.EXPECT
   1 SZ-FL-ENT C@ 0 = S" CLEAR [1] count erased" FL.EXPECT
   \ PUT only index 1 (simulates skipped empty slot 0 after bad rebuild)
   S" Library/Hyper/hyper.fth" 806 1 SZ-FL-PUT
   0 SZ-FL-ENT C@ 0 = S" no stale path at [0] after PUT 1" FL.EXPECT
   1 SZ-FL-ENT COUNT SZ-FL-LEAF S" hyper.fth" FL.PATH=
      S" PUT 1 leaf hyper" FL.EXPECT
   FL.DEPTH0? S" CLEAR-ERASES stack" FL.EXPECT
;

\ Hyper VTAB insert-after + REBUILD must mirror order: hyper, forthA, forthB.
: T-HYPER-VTAB-MIRROR  ( -- )
   FL.EMPTY FL.RESET
   ONLY FORTH ALSO HYPER-VOC
   HYPER-BIND-EDITOR DROP
   HYPER-HIST-CLEAR
   S" Library/Hyper/hyper.fth" 679 0 HYPER-V-STORE
   1 TO HYPER-VN  0 TO HYPER-VI
   HYPER-FL-REBUILD
   \ Simulate RECORD-DEST: plant hit, insert after VI
   S" Library/Sources/forth.s" 1148 FL.PLANT-HIT
   HYPER-HIST-RECORD-DEST
   S" Library/Sources/forth.s" 2840 FL.PLANT-HIT
   HYPER-HIST-RECORD-DEST
   HYPER-VN 3 = S" VTAB mirror VN=3" FL.EXPECT
   HYPER-VI 2 = S" VTAB mirror VI=2 (latest)" FL.EXPECT
   ONLY FORTH ALSO EDITOR
   SZ-FL-N @ 3 = S" VTAB mirror FL-N=3" FL.EXPECT
   SZ-FL-CUR @ 2 = S" VTAB mirror FL-CUR=2" FL.EXPECT
   0 SZ-FL-ENT COUNT SZ-FL-LEAF S" hyper.fth" FL.PATH=
      S" VTAB mirror [0]=hyper" FL.EXPECT
   1 SZ-FL-ENT COUNT SZ-FL-LEAF S" forth.s" FL.PATH=
      S" VTAB mirror [1]=forth" FL.EXPECT
   2 SZ-FL-ENT COUNT SZ-FL-LEAF S" forth.s" FL.PATH=
      S" VTAB mirror [2]=forth" FL.EXPECT
   0 SZ-FL-LINE@ 679 = S" VTAB mirror [0] line" FL.EXPECT
   1 SZ-FL-LINE@ 1148 = S" VTAB mirror [1] line" FL.EXPECT
   2 SZ-FL-LINE@ 2840 = S" VTAB mirror [2] line" FL.EXPECT
   \ Newest must NOT sit above hyper
   0 SZ-FL-LINE@ 2840 = 0= S" newest not at [0]" FL.EXPECT
   FL.DEPTH0? S" VTAB mirror stack" FL.EXPECT
;

\ Empty-path PUT must not grow N / must not write.
: T-FL-PUT-EMPTY  ( -- )
   FL.EMPTY FL.RESET
   0 0 10 0 SZ-FL-PUT
   SZ-FL-N @ 0 = S" PUT empty N stays 0" FL.EXPECT
   FL.DEPTH0? S" PUT empty stack" FL.EXPECT
;

: FL.DUMP  ( -- )
   ." FL-N=" SZ-FL-N @ 0 .R
   ."  FL-CUR=" SZ-FL-CUR @ 0 .R CR
   SZ-FL-N @ 0 DO
      ."   [" I 0 .R ." ] "
      I SZ-FL-ENT COUNT SZ-FL-LEAF TYPE
      ."  :" I SZ-FL-LINE@ 0 .R CR
   LOOP
;

: SZ-FL-TEST  ( -- )
   CR ." === SZ-FL-TEST (visit list + Hyper) ===" CR
   ONLY FORTH ALSO EDITOR
   S" LEAF" FL.MARK  T-FL-LEAF-UNIT
   S" RECORD-ONE" FL.MARK  T-FL-RECORD-ONE
   S" TWO-SAME-FILE" FL.MARK  T-FL-TWO-VISITS-SAME-FILE
   S" INSERT-AFTER" FL.MARK  T-FL-INSERT-AFTER-CURRENT
   S" NOTE-HERE" FL.MARK  T-FL-NOTE-HERE-OVERWRITE
   S" REMOVE" FL.MARK  T-FL-REMOVE
   S" X-COL" FL.MARK  T-FL-X-COL
   S" NAMEW" FL.MARK  T-FL-NAMEW
   S" PUT-REBUILD" FL.MARK  T-FL-PUT-REBUILD
   S" ENSURE-VISIT" FL.MARK  T-FL-ENSURE-VISIT-DEST
   S" LOAD-FORTH" FL.MARK  T-LOAD-FORTH-S
   S" GOTO-LINE" FL.MARK  T-VISIT-GOTO-LINE
   S" NOTE-CURRENT" FL.MARK  T-FL-NOTE-CURRENT-AFTER-GOTO
   S" HYPER-FL-SHOW" FL.MARK
   FL.EMPTY FL.RESET
   ONLY FORTH ALSO HYPER-VOC
   S" Library/Hyper/hyper.fth" 679 HYPER-FL-SHOW
   S" Library/Sources/forth.s" 1148 HYPER-FL-SHOW
   ONLY FORTH ALSO EDITOR
   SZ-FL-N @ 2 = S" HYPER-FL-SHOW N=2" FL.EXPECT
   1 SZ-FL-ENT COUNT SZ-FL-LEAF S" forth.s" FL.PATH=
      S" HYPER-FL-SHOW forth.s leaf" FL.EXPECT
   FL.EMPTY
   S" CLEAR-ERASES" FL.MARK  T-FL-CLEAR-ERASES
   S" PUT-EMPTY" FL.MARK  T-FL-PUT-EMPTY
   S" VTAB-MIRROR" FL.MARK  T-HYPER-VTAB-MIRROR
   S" V-REMOVE" FL.MARK  T-HYPER-V-REMOVE
   CR ." --- final list dump ---" CR
   \ Demo visit trail: hyper:679 → forth:1148 → insert SZ-EDITOR after hyper
   FL.RESET
   S" Library/Hyper/hyper.fth" 679 SZ-FL-RECORD
   S" Library/Sources/forth.s" 1148 SZ-FL-RECORD
   0 SZ-FL-CUR !
   S" Library/Editor/SZ-EDITOR.fth" 22 SZ-FL-RECORD
   FL.DUMP
   CR ." SZ-FL-TEST: " FL#PASS @ 0 .R ."  passed, " FL#FAIL @ 0 .R ."  failed." CR
   FL#FAIL @ IF
      ." *** SZ-FL-TEST FAILURES ***" CR
   ELSE
      ." ALL PASS" CR
   THEN
   ." === SZ-FL-TEST done ===" CR
   FACILITY-OFF
;

FORTH DEFINITIONS
ONLY FORTH ALSO EDITOR
SZ-FL-TEST
ONLY FORTH DEFINITIONS
