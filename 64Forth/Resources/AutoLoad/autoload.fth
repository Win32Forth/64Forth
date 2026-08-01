\ autoload.fth — 64Forth product boot (lowercase name required)
\ Loaded automatically after kernel_init when present in Resources/AutoLoad/.
\ During load, session cwd is this AutoLoad folder (nested FLOAD sees siblings).

\ FILE-ECHO ON
\ FROMLIB REQUIRE TCOM/FPCTOOLS.fth
\ FROMLIB REQUIRE TCOM/LEDIT.fth
\ FROMLIB REQUIRE TCOM/SZ.fth

: APP-RUN  ( -- )
\  S" 64Forth AutoLoad complete." TYPE CR
  ;

: MAIN  ( -- )
  APP-RUN
  ;
