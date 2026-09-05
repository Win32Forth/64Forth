\ emitter.fth — load the turnkey slicer
\ Public domain.

ONLY FORTH DEFINITIONS

FROMLIB FLOAD Emitter/reach.fth
FROMLIB FLOAD Emitter/target.fth
FROMLIB FLOAD Emitter/reloc.fth
FROMLIB FLOAD Emitter/run.fth

CR .( emitter loaded.) CR

