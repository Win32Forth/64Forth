HayesTest/src/Harness — vendor drivers (not ANS/Hayes test cases)
================================================================

This folder holds 64Forth (and other vendor) *runners* / helpers that prepare
the environment or load the stock test sources. The tests themselves stay
untouched under:

  src/fp/          Floating-point suite (ieee-*, paranoia, ttester, …)
  src/*.fth        Core and other word-set tests (including blocktest.fth)

Files here
----------
  prepare-blocks.fth   Open/create writable hayes-blocks.blk under
                       Application Support before blocktest.fth
  runfptests.fth       Loads and runs all programs under ../fp/
                       (64Forth ERROR1, F-stack drain, error accumulation)

Do not put assertion/test sources in Harness. Keep Harness free of the
stock suite so diffs against forth2012-test-suite stay obvious.

Run (from the app):
  FROMLIB FLOAD HayesTest/HayesTest.fth
  → FLOAD src/Harness/prepare-blocks.fth  (if OPEN-BLOCK-FILE present)
  → … word-set tests …
  → FLOAD src/Harness/runfptests.fth      (after ALSO FP)
