\ sz-fl-test.fth — automated tests for side-panel file list + Hyper goto
\
\ Run (Editor + Hyper already loaded via AutoLoad):
\   FROMLIB FLOAD Editor/sz-fl-test.fth
\
\ Expected interactive result: console transcript only (markers, PASS count,
\ final list dump, ALL PASS). No editor window / facility grid / blinking caret.
\
\ Host automation:
\   SZFLTEST=1  → KernelBridge runs this after AutoLoad, writes
\   Application Support/64Forth/sz-fl-test-results.txt (and /tmp if possible).
\
\ CRITICAL: no IF/BEGIN while interpreting — only inside colon defs.

DECIMAL
ONLY FORTH ALSO EDITOR DEFINITIONS

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

\ ---- unit: SZ-FL-ADD / FIND / leaf ----

: T-FL-ADD-ONE  ( -- )
   FL.EMPTY FL.RESET
   S" Library/Hyper/hyper.fth" SZ-FL-ADD
   SZ-FL-N @ 1 = S" ADD one entry N=1" FL.EXPECT
   SZ-FL-CUR @ 0 = S" ADD one entry CUR=0" FL.EXPECT
   FL.DEPTH0? S" ADD one entry stack clean" FL.EXPECT
;

: T-FL-ADD-TWO  ( -- )
   FL.EMPTY FL.RESET
   S" Library/Hyper/hyper.fth" SZ-FL-ADD
   S" Library/Sources/forth.s" SZ-FL-ADD
   SZ-FL-N @ 2 = S" ADD two entries N=2" FL.EXPECT
   SZ-FL-CUR @ 1 = S" ADD two entries CUR=1" FL.EXPECT
   0 SZ-FL-ENT COUNT S" Library/Hyper/hyper.fth" FL.PATH=
      S" entry0 full path hyper.fth" FL.EXPECT
   1 SZ-FL-ENT COUNT S" Library/Sources/forth.s" FL.PATH=
      S" entry1 full path forth.s" FL.EXPECT
   1 SZ-FL-ENT COUNT SZ-FL-LEAF S" forth.s" FL.PATH=
      S" entry1 leaf forth.s" FL.EXPECT
   FL.DEPTH0? S" ADD two stack clean" FL.EXPECT
;

: T-FL-ADD-DUP  ( -- )
   FL.EMPTY FL.RESET
   S" Library/Sources/forth.s" SZ-FL-ADD
   S" Library/Sources/forth.s" SZ-FL-ADD
   SZ-FL-N @ 1 = S" ADD same path twice N stays 1" FL.EXPECT
   SZ-FL-CUR @ 0 = S" ADD same path twice CUR=0" FL.EXPECT
   FL.DEPTH0? S" ADD dup stack clean" FL.EXPECT
;

: T-FL-LEAF-UNIT  ( -- )
   FL.EMPTY
   S" Library/Sources/forth.s" SZ-FL-LEAF S" forth.s" FL.PATH=
      S" LEAF of Library/Sources/forth.s" FL.EXPECT
   S" Kernel/forth.s" SZ-FL-LEAF S" forth.s" FL.PATH=
      S" LEAF of Kernel/forth.s" FL.EXPECT
   S" forth.s" SZ-FL-LEAF S" forth.s" FL.PATH=
      S" LEAF of bare forth.s" FL.EXPECT
   FL.DEPTH0? S" LEAF unit stack clean" FL.EXPECT
;

: T-FL-LEAF-MERGE  ( -- )
   FL.EMPTY FL.RESET
   S" Library/Sources/forth.s" SZ-FL-ADD
   S" Kernel/forth.s" 0 SZ-FL-LEAF-MATCH
   S" LEAF-MATCH Kernel vs entry0" FL.EXPECT
   S" Kernel/forth.s" SZ-FL-FIND-LEAF 0 = S" FIND-LEAF -> 0" FL.EXPECT
   FL.EMPTY
   S" Kernel/forth.s" SZ-FL-ADD
   SZ-FL-N @ 1 = S" leaf merge N=1" FL.EXPECT
   0 SZ-FL-ENT COUNT S" Kernel/forth.s" FL.PATH=
      S" leaf merge path updated" FL.EXPECT
   FL.DEPTH0? S" leaf merge stack clean" FL.EXPECT
;

: T-FL-FIND  ( -- )
   FL.EMPTY FL.RESET
   S" Library/Hyper/hyper.fth" SZ-FL-ADD
   S" Library/Sources/forth.s" SZ-FL-ADD
   S" Library/Sources/forth.s" SZ-FL-FIND 1 = S" FIND forth.s index 1" FL.EXPECT
   S" Library/Hyper/hyper.fth" SZ-FL-FIND 0 = S" FIND hyper.fth index 0" FL.EXPECT
   S" no/such/file.fth" SZ-FL-FIND 0< S" FIND miss negative" FL.EXPECT
   FL.DEPTH0? S" FIND stack clean" FL.EXPECT
;

: T-FL-NOTE-PATH  ( -- )
   FL.EMPTY FL.RESET
   S" Library/Sources/forth.s" SZ-FL-NOTE-PATH
   SZ-FL-N @ 1 = S" NOTE-PATH N=1" FL.EXPECT
   SZ-FL-CUR @ 0 = S" NOTE-PATH CUR=0" FL.EXPECT
   FL.DEPTH0? S" NOTE-PATH stack clean" FL.EXPECT
;

\ ---- load + note (no REDRAW / no KEY loop) ----

: T-LOAD-FORTH-S  ( -- )
   FL.EMPTY FL.RESET
   S" Library/Sources/forth.s" SZ-LOAD
   0= S" LOAD forth.s ior=0" FL.EXPECT
   SZ-HAS-NAME? S" LOAD forth.s has name" FL.EXPECT
   SZ-GET-NAME S" Library/Sources/forth.s" FL.PATH=
      S" LOAD forth.s FNAME" FL.EXPECT
   SZ-TLEN @ 0> S" LOAD forth.s non-empty buffer" FL.EXPECT
   FL.DEPTH0? S" LOAD forth.s stack clean" FL.EXPECT
;

: T-LOAD-AND-NOTE  ( -- )
   FL.EMPTY FL.RESET
   S" Library/Hyper/hyper.fth" SZ-LOAD
   0= S" load hyper ior=0" FL.EXPECT
   SZ-FL-NOTE-CURRENT
   SZ-FL-N @ 1 = S" NOTE after hyper load N=1" FL.EXPECT
   S" Library/Sources/forth.s" SZ-LOAD
   0= S" load forth.s ior=0" FL.EXPECT
   SZ-FL-NOTE-CURRENT
   SZ-FL-N @ 2 = S" NOTE after forth.s load N=2" FL.EXPECT
   SZ-FL-CUR @ 1 = S" NOTE after forth.s CUR=1" FL.EXPECT
   1 SZ-FL-ENT COUNT SZ-FL-LEAF S" forth.s" FL.PATH=
      S" NOTE entry1 leaf forth.s" FL.EXPECT
   FL.DEPTH0? S" LOAD+NOTE stack clean" FL.EXPECT
;

\ Body of SZ-HYPER-GOTO without SZ-REDRAW (facility paint not required).
: FL.HYPER-GOTO-CORE  ( c-addr u line -- )
   >R
   255 MIN SZ-PATH-TMP SZ-PLACE
   SZ-PATH-TMP COUNT
   2DUP SZ-LOAD IF
      R> DROP 2DROP EXIT
   THEN
   2DROP
   SZ-PATH-TMP COUNT SZ-FL-ADD
   SZ-FL-NOTE-CURRENT
   R> SZ-GOTO-LINE
;

: T-HYPER-GOTO-CORE  ( -- )
   FL.EMPTY FL.RESET
   S" Library/Hyper/hyper.fth" SZ-LOAD DROP
   SZ-FL-NOTE-CURRENT
   SZ-FL-N @ 1 = S" pre-goto-core N=1" FL.EXPECT
   S" Library/Sources/forth.s" 1148 FL.HYPER-GOTO-CORE
   SZ-FL-N @ 2 = S" after goto-core N=2" FL.EXPECT
   SZ-FL-CUR @ 1 = S" after goto-core CUR=1" FL.EXPECT
   1 SZ-FL-ENT COUNT S" Library/Sources/forth.s" FL.PATH=
      S" after goto-core entry1 path" FL.EXPECT
   1 SZ-FL-ENT COUNT SZ-FL-LEAF S" forth.s" FL.PATH=
      S" after goto-core entry1 leaf" FL.EXPECT
   SZ-CUR-LINE-NO 1148 = S" after goto-core line 1148" FL.EXPECT
   FL.DEPTH0? S" goto-core stack clean" FL.EXPECT
;

\ NOTE: Do NOT call full SZ-HYPER-GOTO here — it SZ-REDRAWs the facility
\ editor (PAGE/AT-XY grid). FACILITY-OFF leaves that paint in the console,
\ so an interactive FLOAD looks like a stuck editor at DOEXIT. List logic is
\ covered by FL.HYPER-GOTO-CORE above; interactive VIEW covers full REDRAW.

\ ---- Hyper public path: (VIEW) pieces without KEY loop ----
\ Plant hit and call SZ-FL-NOTE-PATH the same way HYPER-NOTE-HIT does.

: T-NOTE-PATH-AS-HYPER  ( -- )
   FL.EMPTY FL.RESET
   S" Library/Hyper/hyper.fth" SZ-FL-ADD
   S" Library/Sources/forth.s" SZ-FL-NOTE-PATH
   SZ-FL-N @ 2 = S" NOTE-PATH as Hyper N=2" FL.EXPECT
   SZ-FL-CUR @ 1 = S" NOTE-PATH as Hyper CUR=1" FL.EXPECT
   1 SZ-FL-ENT COUNT SZ-FL-LEAF S" forth.s" FL.PATH=
      S" NOTE-PATH as Hyper leaf" FL.EXPECT
   FL.DEPTH0? S" NOTE-PATH as Hyper stack" FL.EXPECT
;

\ ---- dump for log ----

: FL.DUMP  ( -- )
   ." FL-N=" SZ-FL-N @ 0 .R
   ."  FL-CUR=" SZ-FL-CUR @ 0 .R CR
   SZ-FL-N @ 0 DO
      ."   [" I 0 .R ." ] "
      I SZ-FL-ENT COUNT TYPE CR
   LOOP
;

: FL.MARK  ( c-addr u -- )  ." -- " TYPE ." --" CR ;

: SZ-FL-TEST  ( -- )
   CR ." === SZ-FL-TEST (side file list + Hyper goto) ===" CR
   ONLY FORTH ALSO EDITOR
   S" ADD-ONE" FL.MARK  T-FL-ADD-ONE
   S" ADD-TWO" FL.MARK  T-FL-ADD-TWO
   S" ADD-DUP" FL.MARK  T-FL-ADD-DUP
   S" LEAF-UNIT" FL.MARK  T-FL-LEAF-UNIT
   S" LEAF-MERGE" FL.MARK  T-FL-LEAF-MERGE
   S" FIND" FL.MARK  T-FL-FIND
   S" NOTE-PATH" FL.MARK  T-FL-NOTE-PATH
   S" LOAD-FORTH" FL.MARK  T-LOAD-FORTH-S
   S" LOAD-NOTE" FL.MARK  T-LOAD-AND-NOTE
   S" GOTO-CORE" FL.MARK  T-HYPER-GOTO-CORE
   S" NOTE-AS-HYPER" FL.MARK  T-NOTE-PATH-AS-HYPER
   CR ." --- final list dump ---" CR
   FL.DUMP
   CR ." SZ-FL-TEST: " FL#PASS @ 0 .R ."  passed, " FL#FAIL @ 0 .R ."  failed." CR
   FL#FAIL @ IF
      ." *** SZ-FL-TEST FAILURES ***" CR
   ELSE
      ." ALL PASS" CR
   THEN
   ." === SZ-FL-TEST done ===" CR
   \ Ensure REPL is not left in facility mode if a future test paints.
   FACILITY-OFF
;

FORTH DEFINITIONS
ONLY FORTH ALSO EDITOR
SZ-FL-TEST
ONLY FORTH DEFINITIONS
