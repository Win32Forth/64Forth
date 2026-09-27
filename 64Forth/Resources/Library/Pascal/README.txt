64Forth Tiny Pascal translator (Library/Pascal)
===============================================

Port of Tom Zimmer’s Tiny Pascal → Forth translator (1987–91) to 64Forth
(Forth-2012, 64-bit cells). Public domain.

Load
----
  FROMLIB FLOAD Pascal/PASCAL.fth

Entry words
-----------
  PASCAL" ( c-addr u -- )
      Translate a .pas source to Forth on the console.

  PASCAL ( "name" -- )
      Same, taking the path from the input stream (BL WORD).

  PASCAL-TO-FILE ( c-addr u -- )
      Translate a .pas source to a sibling .fth file (same folder, same
      stem: Pascal/PASY.PAS → Pascal/PASY.fth). Prints "Wrote …" on success.

All three:
  • Honor FROMLIB at the entry word via PAS-RESOLVE (relative names are
    rewritten under LIBRARY-PATH, then the arm is cleared). Absolute and
    ~ paths are unchanged. Resolution is not done inside PAS-OPEN.
  • Require a .pas extension (any case). A .fth path is rejected so a
    generated sample is never mistaken for Pascal source.

Examples
--------
  FROMLIB FLOAD Pascal/PASCAL.fth

  \ Console translation
  FROMLIB S" Pascal/PASY.PAS" PASCAL"

  \ Write sibling .fth, then load and run
  FROMLIB S" Pascal/PASY.PAS" PASCAL-TO-FILE
  FROMLIB S" Pascal/PASY.fth" INCLUDED
  DEMO

Samples
-------
  PASX.PAS          Original stress-test program (reads KEY, mixed I/O).
  PASX-SAMPLE.fth   Checked-in translation of PASX.PAS (reference output).

  PASY.PAS          Clearer demo: no read/KEY; Write(#n) for numbers;
                    const/var/array/proc/for/while/repeat/if. Loop index
                    is "idx" (not "i") so it does not clash with Forth I.
                    Const NumberBase (not Base) avoids redefining Base.
  PASY-SAMPLE.fth   Checked-in translation of PASY.PAS (reference output).

  PASCAL-TO-FILE writes PASX.fth / PASY.fth next to the sources. Those
  generated names are intentionally free; keep *-SAMPLE.fth in the tree
  as stable references. Pascal.zip is not part of the library.

Array bounds
-------------
  array [n]              n cells (indexes 0 .. n-1)
  array [Limit]          the const's value, in cells
  array [Limit+1]        that value plus or minus a number

  A FOR from 0 to Limit includes both ends, so the array needs Limit+1
  cells. The bound must be a number or an already-defined const.

I/O codegen notes
-----------------
  read(x)       → KEY DUP EMIT x !     (character)
  read(#x)      → KEY x !              (no echo)
  write(x)      → x @ EMIT             (character)
  write(#x)     → x @ .                (number — prefer this)
  write('text') → ." text "

  PASY avoids read and uses # for numeric write so DEMO is useful without
  typing keys.

Tips
----
  Prefer PASY to try the translator; use PASX to stress older constructs.
  After editing Library files, rebuild or use Tools → Update User Data so
  Documents/64Forth/Library stays in sync with the bundle.
