\ tetra-smoke.fth — Emitter in-process tetra subset (+ MAIN build).
\ Lives under Library/Emitter/EmitterSmoke (shipped with Emitter).
\ Public domain.
\
\ Does NOT run GAME's KEY loop. Subset paints field/setup/one piece then
\ closes the window. MAIN is TGT-BUILD only (full reach proof).
\
\ Canonical: Xcode Resources/Library/Emitter (Documents/64Forth/Library is a symlink).
\ Prefer:  FROMLIB FLOAD Emitter/EmitterSmoke/tetra-smoke.fth
\ Agent:   …/64Forth --agent -f $HOME/Documents/64Forth/Library/Emitter/EmitterSmoke/tetra-smoke.fth

ONLY FORTH DEFINITIONS DECIMAL
FROMLIB FLOAD Emitter/emitter.fth
ALSO GRAPHICS

S" /Users/thomaszimmer/Documents/64TCOM/64TCOMARM64/tetra/tetra.fth" INCLUDED

\ Subset: open, draw playfield + chrome + one piece, close. No KEY.
: T-TETRA-SUB  ( -- )
  S" TETRA-sub" APP-NAME
  WINDOW
  fill-notes
  FIELD SETUP BORDER
  0 TO FIGURE.NO
  FILL.CURR DRAW.CURR
  WINDOW-OFF
  ;

: TRY-RUN  ( xt -- )
  DUP TGT-BUILD  TGT-RUN ;

CR .( === tetra subset: FIELD SETUP BORDER FILL.CURR DRAW.CURR === ) CR
['] T-TETRA-SUB TRY-RUN
CR .( T-TETRA-SUB returned ) CR

CR .( === MAIN TGT-BUILD only — full reach, no GAME KEY loop === ) CR
['] MAIN TGT-BUILD
CR .( MAIN build ok ) CR
CR .( MAIN reachable count ) REACH-N @ U. CR

CR .( DONE tetra-smoke ) CR
