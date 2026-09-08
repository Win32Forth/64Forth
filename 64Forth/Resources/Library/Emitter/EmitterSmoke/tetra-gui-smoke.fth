\ tetra-gui-smoke.fth — interactive Emitter TGT-RUN of tetra MAIN/GAME.
\ Lives under Library/Emitter/EmitterSmoke (shipped with Emitter).
\ Public domain.
\
\ MAIN → GAME is a KEY loop (play until spawn blocked, then ESC).
\ Do NOT TGT-RUN under --agent: (APP-OPEN) is a no-op and KEY blocks forever.
\
\ Agent-safe (build + reach only):
\
\ Interactive (real GRAPHICS window + keys) — in the 64Forth console:
\   EMIT-TETRA
\ Arrow keys / Space / S / P as in SETUP chrome. ESC → WINDOW-OFF (ANS arm)
\ and returns to the console. After game-over banner, ESC also quits.
\ Canonical: Xcode Resources/Library/Emitter (Documents/64Forth/Library is a symlink).
\ Prefer:  FROMLIB FLOAD Emitter/EmitterSmoke/tetra-gui-smoke.fth
\ Agent:   …/64Forth --agent -f $HOME/Documents/64Forth/Library/Emitter/EmitterSmoke/tetra-gui-smoke.fth

ONLY FORTH DEFINITIONS DECIMAL
FROMLIB FLOAD Emitter/emitter.fth
ALSO GRAPHICS

S" /Users/thomaszimmer/Documents/64TCOM/64TCOMARM64/tetra/tetra.fth" INCLUDED

\ Build+run MAIN (WINDOW → GAME → KEY loop → ESC / WINDOW-OFF).
: EMIT-TETRA  ( -- )
  ['] MAIN DUP TGT-BUILD TGT-RUN ;

CR .( === MAIN TGT-BUILD — interactive KEY loop is EMIT-TETRA === ) CR
['] MAIN TGT-BUILD
CR .( MAIN build ok ) CR
CR .( MAIN reachable count ) REACH-N @ U. CR
CR .( GUI: type EMIT-TETRA   ESC quits via WINDOW-OFF ) CR

CR .( DONE tetra-gui-smoke ) CR
