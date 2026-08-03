\ autoload.fth — 64Forth product boot (lowercase name required)
\ Loaded automatically after kernel_init when present in Resources/AutoLoad/.
\ During load, session cwd is this AutoLoad folder (nested FLOAD sees siblings).

FROMLIB REQUIRE EDITOR/SZ-EDITOR.fth
EDITOR 100 50 SET-EDIT-WINDOW FORTH
FROMLIB REQUIRE HYPER/HYPER.fth
HYPER-VOC MIN-HYPER-NOISE ON FORTH
HYPER-REINDEX

0 [IF]
    FILE-ECHO ON
    FROMLIB REQUIRE TCOM/FPCTOOLS.fth
    FROMLIB REQUIRE TCOM/LEDIT.fth
    FROMLIB REQUIRE TCOM/SZ.fth
[THEN]

: APP-RUN  ( -- )
\  S" 64Forth AutoLoad complete." TYPE CR
  ;

: MAIN  ( -- )
  APP-RUN
  ;
