\ HayesTest.fth — John Hayes forth2012-test-suite full driver (in-app)
\
\ Canonical run (bundled under Resources/Library):
\   FROMLIB FLOAD HayesTest/HayesTest.fth
\
\ Or after entering the HayesTest folder as cwd:
\   FROMLIB CHDIR HayesTest
\   FLOAD HayesTest.fth
\
\ Named FLOAD chdirs to this file's folder (HayesTest/), so nested loads
\ use bare subpaths under that folder (src/…, not HayesTest/src/…).
\
\ 1) src/prepare-blocks.fth — USE-BLOCK-FILE a *writable* .blk under
\    Application Support (bundle Resources/Library is read-only; FLUSH would
\    fail on src/blocks.blk).
\ 2) src/test.fth — full suite; nested FLOAD sets logical cwd to src/
\    so relative names (core*.fth, fp/runfptests.fth, …) resolve.
\
\ Pass criteria: src/test.fth and src/HAYES-RESULTS.txt.
\ Docs: README.md, doc/, prelimtest.md

FLOAD src/prepare-blocks.fth
FLOAD src/test.fth
