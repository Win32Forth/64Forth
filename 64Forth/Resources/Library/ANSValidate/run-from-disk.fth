\ run-from-disk.fth — thin alias for the canonical FROMLIB entry
\
\ Prefer:
\   FROMLIB FLOAD ANSValidate/ANS-VALIDATE.fth
\
\ This file only exists so older docs that named run-from-disk still work.
\ It re-arms FROMLIB and loads the driver by Library-relative path.

FILE-ECHO OFF
DECIMAL
ONLY FORTH DEFINITIONS

FROMLIB FLOAD ANSValidate/ANS-VALIDATE.fth
