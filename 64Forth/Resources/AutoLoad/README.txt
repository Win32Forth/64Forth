TZForth AutoLoad (product boot)
===============================

Full documentation: repository README.md section "AutoLoad (product boot)".

Build
-----
This folder is copied wholesale into the app at build time:

  YourApp.app/Contents/Resources/AutoLoad/

via the Xcode "Copy AutoLoad" Run Script phase (entire directory).

Boot (at launch)
----------------
1. If Resources/AutoLoad/autoload.fth is missing → silent; normal REPL.
2. If present → load/interpret it (no host path banners).
   During load, cwd is this AutoLoad folder. Nested FLOAD / INCLUDE of bare
   names (e.g. FLOAD ANEW.fth) reads siblings from Resources/AutoLoad without
   a security-scope dialog — the folder is inside the app bundle.
3. If MAIN is defined → execute MAIN once (silent if MAIN is absent).
4. Console stays open.

Boot file name must be lowercase: autoload.fth

Files in this project folder
----------------------------
  autoload.fth          Product boot (optional; omit for pure REPL)
  AutoLoad-Sample.fth   Example MAIN + CATCH pattern (not auto-loaded)
  ANEW.fth              Classic ANEW reload marker (loaded by default autoload)
  README.txt            This note
  (any other .fth)      Copied into the app; include from autoload.fth as needed

Default autoload.fth loads ANEW.fth and FROMLIB FLOAD Editor/SZ-EDITOR.fth
so the in-app editor is always available (File menu / SZEDIT).

Other Library modules (see TZForth/Library/ and Library/README.txt):

  FROMLIB FLOAD BigInteger/big-int.fth
  FROMLIB FLOAD PI/pi-test.fth

Tools menu
----------
  Tools → AUTOLOAD → VIEW AutoLoad Folder
    Opens Contents/Resources/AutoLoad/ in Finder so you can add/edit/remove
    files (zip-style customization after install). Use Finder to open/save
    files; there is no separate EDIT autoload.fth menu.

Ship a product
--------------
  1. Edit/add files under project TZForth/AutoLoad/ (especially autoload.fth).
  2. Define : MAIN ( -- ) ... ; if you want a startup entry (see sample).
  3. Archive or Release-build; distribute the .app.

Notes
-----
- CLS clears the whole console including the TZForth banner.
- Editing inside a signed .app can affect code signature; fine for personal
  zip use. App Store products should ship the intended AutoLoad at Archive time.
