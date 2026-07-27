64Forth AutoLoad (product boot)
===============================

This folder is copied into the app as:

  64Forth.app/Contents/Resources/AutoLoad/

Boot (at launch)
----------------
1. If Resources/AutoLoad/autoload.fth is missing → silent; normal REPL.
2. If present → load/interpret it after the console attaches.
   During load, cwd is this AutoLoad folder. Nested FLOAD / INCLUDE of bare
   names (e.g. FLOAD ANEW.fth) reads siblings from Resources/AutoLoad.
3. If MAIN is defined → execute MAIN once.
4. Session cwd is restored; console stays open with ok> prompt.

Boot file name must be lowercase: autoload.fth

Files
-----
  autoload.fth          Product boot (edit freely)
  ANEW.fth              Classic ANEW reload marker
  AutoLoad-Sample.fth   Example patterns (not auto-loaded)
  README.txt            This note

Tools menu
----------
  Tools → Show AutoLoad Folder — open this directory in Finder.

Examples to add in autoload.fth
-------------------------------
  FROMLIB FLOAD smoke-load.fth
  FROMLIB FLOAD BigInteger/big-int.fth   (needs more kernel/host words)
