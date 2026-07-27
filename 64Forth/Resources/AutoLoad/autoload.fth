\ autoload.fth — product boot (lowercase name required)

FLOAD ANEW.fth

\ Always load SZ-EDITOR so File menu / SZEDIT work without a manual FLOAD.
FROMLIB FLOAD Editor/SZ-EDITOR.fth

\ Required: define MAIN so the host can start the app after load.
: APP-RUN  ( -- )
\   .( AutoLoad APP-RUN finished.) CR
  ;

: MAIN  ( -- )
  ['] APP-RUN CATCH
  ?DUP IF
    .( AutoLoad MAIN: exception ) CR
    .ERROR CR
  THEN
  ;
