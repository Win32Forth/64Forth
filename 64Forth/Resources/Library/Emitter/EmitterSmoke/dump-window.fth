\ dump-window.fth
\ Canonical: Xcode Resources/Library/Emitter (Documents/64Forth/Library is a symlink).
\ Prefer:  FROMLIB FLOAD Emitter/EmitterSmoke/dump-window.fth
\ Agent:   …/64Forth --agent -f $HOME/Documents/64Forth/Library/Emitter/EmitterSmoke/dump-window.fth

ONLY FORTH ALSO GRAPHICS DECIMAL

: DUMP-WIN  ( -- )
  CR ." WINDOW xt= " ['] WINDOW HEX U. DECIMAL CR
  CR ." CFA@= " ['] WINDOW @ HEX U. DECIMAL CR
  CR ." body cells:" CR
  ['] WINDOW 8 +
  24 0 DO
    I . SPACE
    DUP I CELLS + @ HEX U. DECIMAL CR
  LOOP DROP ;

DUMP-WIN
