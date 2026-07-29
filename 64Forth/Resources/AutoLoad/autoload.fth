\ autoload.fth — 64Forth product boot (lowercase name required)
\ Loaded automatically after kernel_init when present in Resources/AutoLoad/.
\ During load, session cwd is this AutoLoad folder (nested FLOAD sees siblings).
\
\ ANEW is a kernel word (classic FORGET-then-CREATE reload marker).

\ Tools that must work even if late forth_init aborted:
FLOAD see.fth

\ Optional: pull Library modules here, e.g.
\   FROMLIB FLOAD smoke-load.fth
\
\ TZForth ships FROMLIB FLOAD Editor/SZ-EDITOR.fth — not in the Pickle kernel stack yet.

: APP-RUN  ( -- )
  S" 64Forth AutoLoad complete." TYPE CR
  ;

: MAIN  ( -- )
  APP-RUN
  ;
