\ autoload.fth — 64Forth product boot (lowercase name required)
\ Loaded automatically after kernel_init when present in Resources/AutoLoad/.
\ During load, session cwd is this AutoLoad folder (nested FLOAD sees siblings).

\ by default, we are loading the editor and the hyper text system as part of
\ what the user has available when they start using 64Forth
    FROMLIB REQUIRE EDITOR/SZ-EDITOR.fth
    \ Size follows the graphic window on each SZ-REDRAW (SZ-SYNC-SIZE).
    EDITOR 80 20 SET-EDIT-WINDOW FORTH
    FROMLIB REQUIRE HYPER/HYPER.fth
    HYPER-VOC MIN-HYPER-NOISE ON FORTH

ONLY FORTH DEFINITIONS

\ Automatically rstore all the default Library files when we run 64Forth
\ so that we will be orking wit all the latest code.
: RESTORE-SHIPPED  ( -- )
    S\" ditto --norsrc '/Users/thomaszimmer/Documents/XCodeProjects/64Forth/64Forth/Resources/Library' '/Users/thomaszimmer/Documents/64Forth/Library'"
    SYSTEM DROP
    CR ." Library restored from Xcode Resources" CR ;
\\
    RESTORE-SHIPPED
    HYPER-REINDEX
    FROMLIB FLOAD Emitter/emitter.fth
    .( About to load test.fth ) CR
    FROMLIB FLOAD Emitter/test.fth
{
    HYPER-REINDEX


\\
    FILE-ECHO ON
    FROMLIB REQUIRE TCOM/FPCTOOLS.fth
    FROMLIB REQUIRE TCOM/LEDIT.fth
    FROMLIB REQUIRE TCOM/SZ.fth
{

