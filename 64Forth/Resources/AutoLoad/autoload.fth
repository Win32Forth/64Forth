\ autoload.fth — 64Forth product boot (lowercase name required)
\ Loaded automatically after kernel_init when present in Resources/AutoLoad/.
\ During load, session cwd is this AutoLoad folder (nested FLOAD sees siblings).
\
\ Canonical sources live in the Xcode project:
\   SHIP = XCodeProjects/64Forth/64Forth/Resources/{Library,AutoLoad}
\ Documents/64Forth/{Library,AutoLoad} are symlinks to those folders, so the
\ project file and the running app always see the same bits. Edit either path.
\
\ If a menu/first-run restore replaces the symlinks with real folders again,
\ run:  XCodeProjects/64Forth/scripts/sync-shipped.sh link
\
\ After this file loads, the host runs MAIN once (if defined), then the REPL.

\ by default, we are loading the editor, the Emitter application builder and
\ the hyper text system as part of what the user has available when they
\ start using 64Forth

    FROMLIB REQUIRE EDITOR/SZ-EDITOR.fth
    \ Size follows the graphic window on each SZ-REDRAW (SZ-SYNC-SIZE).
    EDITOR 80 20 SET-EDIT-WINDOW FORTH
    FROMLIB REQUIRE Emitter/emitter.fth
    \ Load the hyper text code, and finally re-index so everything is up to date
    FROMLIB REQUIRE HYPER/HYPER.fth
    HYPER-VOC MIN-HYPER-NOISE ON FORTH
    HYPER-REINDEX

ONLY FORTH DEFINITIONS

\ --- Required boot word ------------------------------------------------------
\ Host executes MAIN once after autoload. Wrap the body in CATCH so faults
\ print cleanly and return to the REPL.
\ Note: use ." (not .() for the fault message — .( is IMMEDIATE and would
\ print while compiling MAIN. 64Forth has no .ERROR; print the code with .

: APP-RUN  ( -- )
  \ Default: nothing (editor / hyper / emitter already loaded above).
  \ Put product startup here, or enable the template block below.
  ;

: MAIN  ( -- )
  ['] APP-RUN CATCH
  ?DUP IF
    ." AutoLoad MAIN: exception " . CR
  THEN
  ;
