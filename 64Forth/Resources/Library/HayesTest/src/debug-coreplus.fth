\ Isolate coreplustest.fth failures (expect cperrors=2 until fixed).
\ FLOAD debug-bootstrap.fth  then  FLOAD debug-coreplus.fth

TRUE VERBOSE !
0 #ERRORS !
fload coreplustest.fth
.( coreplustest errors= ) #ERRORS @ . CR