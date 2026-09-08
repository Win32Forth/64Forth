\ persist-save-gfx.fth — write unbound gfx image for emit-run.
\ Canonical: Xcode Resources/Library/Emitter (Documents/64Forth/Library is a symlink).
\ Prefer:  FROMLIB FLOAD Emitter/EmitterSmoke/persist-save-gfx.fth
\ Agent:   …/64Forth --agent -f $HOME/Documents/64Forth/Library/Emitter/EmitterSmoke/persist-save-gfx.fth

ONLY FORTH DEFINITIONS DECIMAL
FROMLIB FLOAD Emitter/emitter.fth

CREATE IMG-PATH 256 ALLOT
S" /Users/thomaszimmer/Documents/64Forth/Library/Emitter/EmitterSmoke/gfx.img" IMG-PATH PLACE

ALSO GRAPHICS
\ Stay open until a key (ESC/close also works). Headless: open fails → KEY → ESC.
: T-GFX  ( -- )
  S" Emitter GFX" APP-NAME
  WINDOW
  CLS
  2 1 AT ." persist-ok — press a key"
  KEY DROP
  WINDOW-OFF
  ;
ONLY FORTH ALSO SYSVOC ALSO EMITTER

/EMIT-STANDALONE
/EMIT-UNBOUND
' T-GFX TGT-BUILD
' T-GFX IMG-PATH COUNT SAVE-IMAGE
CR .( wrote ) IMG-PATH COUNT TYPE CR
