\ Full Hayes chain for UI console (runtests-tzforth.fth order after bootstrap).
\   FLOAD debug-bootstrap.fth
\   FLOAD debug-full-chain.fth

FILE-ECHO OFF
.( --- Hayes-order segment loads --- ) CR

VARIABLE cperrors
VARIABLE cerrors
VARIABLE derrors
VARIABLE eerrors
VARIABLE ferrors
VARIABLE lerrors
VARIABLE merrors
VARIABLE terrors
VARIABLE soerrors
VARIABLE serrors

0 #ERRORS !  fload coreplustest.fth    #ERRORS @ cperrors !
0 #ERRORS !  fload coreexttest.fth     #ERRORS @ cerrors !
0 #ERRORS !  fload doubletest.fth      #ERRORS @ derrors !
0 #ERRORS !  fload exceptiontest.fth   #ERRORS @ eerrors !
0 #ERRORS !  fload filetest.fth        #ERRORS @ ferrors !
0 #ERRORS !  fload localstest.fth      #ERRORS @ lerrors !
0 #ERRORS !  fload memorytest.fth      #ERRORS @ merrors !
0 #ERRORS !  fload toolstest.fth       #ERRORS @ terrors !
0 #ERRORS !  fload searchordertest.fth #ERRORS @ soerrors !
0 #ERRORS !  fload stringtest.fth      #ERRORS @ serrors !

.( coreplus= ) cperrors @ . CR
.( coreext= ) cerrors @ . CR
.( double= ) derrors @ . CR
.( except= ) eerrors @ . CR
.( file= ) ferrors @ . CR
.( locals= ) lerrors @ . CR
.( memory= ) merrors @ . CR
.( tools= ) terrors @ . CR
.( search= ) soerrors @ . CR
.( string= ) serrors @ . CR
.( total= )
cperrors @ cerrors @ + derrors @ + eerrors @ + ferrors @ +
lerrors @ + merrors @ + terrors @ + soerrors @ + serrors @ + . CR