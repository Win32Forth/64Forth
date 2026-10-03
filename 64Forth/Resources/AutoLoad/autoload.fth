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

\ Boot loads: debugger helpers, Emitter, Hyper. SZ-EDITOR is out of Autoload
\ (external 64Edit + XPC). Empty EDITOR vocab keeps Hyper's ALSO EDITOR safe.
\ FILE-ECHO ON
    \ ITC DEBUG (hub loads Debugger/*; leaves ALSO DEBUGGER on the order)
    FROMLIB REQUIRE Debugger/debugger.fth
    [UNDEFINED] EDITOR [IF] VOCABULARY EDITOR [THEN]
    FROMLIB REQUIRE Emitter/emitter.fth
    \ Load the hyper text code, and finally re-index so everything is up to date
    FROMLIB REQUIRE HYPER/HYPER.fth
    HYPER-VOC MIN-HYPER-NOISE ON FORTH
    HYPER-REINDEX
    \ Hyper clears DBG-HL-XT (console-only SZ-EDITOR era). Re-arm map→span
    \ for 64Edit so asm pause fallback still publishes off+len before paint.
    ALSO DEBUGGER
    DBG-MAP-BIND IF  DBG-ED-HL-XT DBG-SET-HL  THEN
    PREVIOUS

\ Boot: ONLY FORTH ALSO DEFINITIONS (FORTH FORTH, CURRENT=FORTH).
\ ALSO leaves a spare FORTH slot for vocabulary context; DEFINITIONS → FORTH.
\ BREAK/BPGO live in FORTH (debugger.fth rechains them). Type DEBUGGER to
\ PUSH-ORDER hub words when needed.
ONLY FORTH ALSO DEFINITIONS

\ --- Required boot word ------------------------------------------------------
\ Host executes MAIN once after autoload. Wrap the body in CATCH so faults
\ print cleanly and return to the REPL.
\ Note: use ." (not .() for the fault message — .( is IMMEDIATE and would
\ print while compiling MAIN. 64Forth has no .ERROR; print the code with .

: APP-RUN  ( -- )
  \ Default: nothing (debugger / hyper / emitter already loaded above).
  \ Put product startup here, or enable the template block below.
  ;

: MAIN  ( -- )
  ['] APP-RUN CATCH
  ?DUP IF
    ." AutoLoad MAIN: exception " . CR
  THEN
  ;
