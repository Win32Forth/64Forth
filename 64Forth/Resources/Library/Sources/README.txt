Library/Sources — shipped kernel source for VIEW / Hyper
========================================================

These files are copies of 64Forth/Kernel/ for distribution inside the app
bundle (Resources/Library/Sources/). Hyper indexes them as:

  Library/Sources/forth.s
  Library/Sources/boot_words.inc
  Library/Sources/colon_words.inc
  …

so LOCATE/VIEW work in a release DMG without a developer checkout.

The Xcode “Copy Library” phase also refreshes this folder in the build
product from Kernel/ on every build. After editing Kernel sources, rebuild
(or re-copy) and run HYPER-REINDEX / tools/build_hyper_index.py so HYPER.NDX
line numbers stay accurate.

Do not treat this folder as the edit-source-of-truth for the kernel — edit
64Forth/Kernel/ then rebuild.

Swift host sources (App/, Host/) are not copied here: Hyper indexes Forth and
kernel assembly definitions only. Library/**/*.fth is already in the bundle.
