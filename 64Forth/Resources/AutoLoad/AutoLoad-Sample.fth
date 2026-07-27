\ =============================================================================
\ AutoLoad-Sample.fth — example product boot for TZForth
\ =============================================================================
\
\ How to use this as a real app boot file:
\   1. Copy or rename to  autoload.fth  in the same folder
\      (Contents/Resources/AutoLoad/autoload.fth inside the .app, or
\       TZForth/AutoLoad/autoload.fth in the Xcode project so it is copied
\       into the app bundle Resources).
\   2. Rebuild / reinstall the app.
\   3. On launch TZForth loads autoload.fth and executes MAIN once.
\   4. The console remains open (hybrid app + REPL). Hiding the console is
\      a future phase; there is no separate app window API yet.
\
\ Contract:
\   - Boot file name must be  autoload.fth  (case as on disk; typically lowercase).
\   - You must define  : MAIN ( -- ) ... ;
\   - Prefer CATCH around the real app body so faults do not dump raw into the REPL.
\   - Companion .fth files: INCLUDED with bare names (cwd is AutoLoad/ during load).
\
\ This sample is NOT auto-loaded unless you name it autoload.fth.
\ =============================================================================

DECIMAL

\ Optional: load helpers from the same AutoLoad folder
\ S" my-lib.fth" INCLUDED

\ --- Customer application entry (example) ------------------------------------

: APP-RUN  ( -- )
  \ Put the real application here (menus, demos, calculations, …).
  .( Hello from AutoLoad sample APP-RUN.) CR
  .( Replace APP-RUN with your product logic.) CR
  ;

\ --- Required boot word ------------------------------------------------------
\ Always wrap the app body in CATCH so uncaught faults print a clean message
\ and return to the REPL instead of leaving the system in a half-broken state.

: MAIN  ( -- )
  ['] APP-RUN CATCH
  ?DUP IF
    .( AutoLoad MAIN: exception ) CR
    .ERROR CR
  THEN
  ;

\ End of sample — MAIN is defined above (required for product boot).
