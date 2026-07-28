\ To run Floating Point tests
\
\ Load only this file (do not FLOAD ttester.fs first — it is included below).

cr .( Running FP Tests) cr

0 WARNING !

s" [undefined]" pad c! pad char+ pad c@ move 
pad find nip 0=
[if]
   : [undefined]  ( "name" -- flag )
      bl word find nip 0=
   ; immediate
[then]

\ Hayes tester.fr defines T{ but not ERROR-XT / ERROR1 (fp tests need ttester.fs).
[undefined] ERROR-XT [if]
s" ttester.fs"         included
[then]

s" fatan2-test.fs"     included
s" ieee-arith-test.fs" included
s" ieee-fprox-test.fs" included
s" fpzero-test.4th"    included
s" fpio-test.4th"      included
s" to-float-test.4th"  included

\ Drain any floats left on the F stack before paranoia / ak-fp.
: zap-fpstack  begin fdepth while fdrop repeat ;
zap-fpstack

\ paranoia needs engine F= (IEEE equality); ak-fp-test.fth redefines F= as bitwise F~.
: try-paranoia  s" paranoia.4th" ['] included catch dup
  if  cr .( paranoia skipped, throw code ) . .error cr  else drop then ;
try-paranoia

zap-fpstack
s" ak-fp-test.fth"     included

-1 WARNING !

cr cr 
.( FP tests finished) cr cr