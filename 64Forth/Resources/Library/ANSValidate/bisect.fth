\ bisect.fth — find first bad store (XSTORE / forth.s ~1555)
\
\   INCLUDE /Users/thomaszimmer/Documents/XCodeProjects/64Forth/64Forth/Resources/Library/ANSValidate/bisect.fth
\
\ IMPORTANT (Xcode): If the debugger stops at forth.s:1555 with NO console
\ text, that is LLDB catching EXC_BAD_ACCESS before Forth's soft handler and
\ before emit flush. Either:
\   1) Continue (Ctrl-Cmd-Y) so SIGSEGV is delivered — then look at the console
\   2) Disable Exception breakpoints; ensure scheme uses .lldbinit-64forth
\   3) Run 64Forth.app from Finder (no debugger)
\
\ Each step emits "Bn " via EMIT only (no .R). Last Bn before fault = culprit.

FILE-ECHO OFF
DECIMAL
ONLY FORTH DEFINITIONS

\ Print "B" then decimal n then space using only EMIT (always hits host emit)
: B  ( n -- )
  66 EMIT                       \ 'B'
  \ print n in decimal, at least one digit
  DUP 10 < IF 48 + EMIT ELSE
    DUP 10 / 48 + EMIT  10 MOD 48 + EMIT
  THEN
  32 EMIT ;                     \ space

1 B VARIABLE VP
2 B 0 VP !
3 B 1 VP !
4 B

5 B CREATE VB 64 ALLOT
6 B 65 VB C!
7 B

8 B 8364 VB XC!+ DROP
9 B

10 B : T.ENC  VB XC!+ VB - VP ! ;
11 B 8364 T.ENC
12 B

13 B VARIABLE #PASS
14 B 0 #PASS !
15 B
16 B : T.PASS  #PASS @ 1+ #PASS ! ;
17 B T.PASS
18 B

19 B : EXPECT  ROT IF 2DROP T.PASS ELSE 2DROP THEN ;
20 B TRUE S" x" EXPECT
21 B

22 B S" EXTENDED-CHARACTER" ENVIRONMENT? DROP DROP
23 B

24 B : XC-RT
       DUP >R R@ VB XC!+ VB -
       R@ XC-SIZE <> IF R> DROP FALSE EXIT THEN
       VB XC@+ NIP R> = ;
25 B 65 XC-RT DROP
26 B 8364 XC-RT DROP
27 B

28 B 65 VB XC!+ 66 SWAP XC!+ 67 SWAP XC!+ VB - DROP
29 B

30 B 8364 VB XC!+ DROP  VB 3 X-SIZE DROP
31 B

32 B 65 VB XC!+ 8364 SWAP XC!+ 66 SWAP XC!+ DROP
33 B VB XCHAR+ DROP
34 B

35 B 8364 VB 3 XC!+? DROP DROP DROP
36 B 8364 VB 2 XC!+? DROP DROP DROP
37 B

38 B 8364 VB XC!+ VB - VB SWAP -TRAILING-GARBAGE 2DROP
39 B

40 B 65 XC-WIDTH DROP
41 B 65 VB XC!+ 19968 SWAP XC!+ 66 SWAP XC!+ VB - VB SWAP X-WIDTH DROP
42 B

43 B : PH  <# 50 HOLD 8364 XHOLD 49 HOLD 0 0 #> ;
44 B PH 2DROP
45 B

46 B HERE 8364 XC, HERE SWAP - DROP
47 B

\ Force a visible end marker (many EMITs)
13 EMIT 66 EMIT 79 EMIT 78 EMIT 69 EMIT 13 EMIT
\ "DONE\n" via codes: already B47; print DONE
68 EMIT 79 EMIT 78 EMIT 69 EMIT 10 EMIT
