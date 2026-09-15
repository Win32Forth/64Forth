\\ PASCAL.SEQ       Tiny Pascal     Copyright 1987-91       Tom Zimmer

  Here is the latest version of my Tiny Pascal Implimentation in Forth.

  It doesn't do all that much, but it does translate the simple example
included with the compiler (PASX.PAS) from PASCAL to Forth.

  The PASCAL translator is Compiled as follows:

        TCOM PASCAL <enter>

  Once PASCAL has been compiled, you can use it to translate the pascal
example file PASX.PAS into Forth with the following command line:

        PASCAL PASX.PAS <enter>

The Pascal translator will output Forth source to the console. To direct
the translators output to a file use standard I/O redirection as in:

        PASCAL PASX.PAS >PASX.SEQ enter

A file PASX.SEQ will be created containing the Forth source for PASX.PAS.

  P.S. Don't redirect the output to the same file as the input, or you
will lose your original source.

{
64 value cols
variable #out 0 #out !
: cr        ( -- )
            0 #out !
            cr ;
cr
: sp>col    ( n -- )
            #out @ - 0 max spaces ;

: crout         ( --- )         cr ;
: crout+        ( --- )         cr  2 spaces ;
: crout++       ( --- )         6 sp>col #out @ 6 > if cr 6 spaces then ;

: ?nline        ( n1 --- )      #out @ + cols 10 - > if crout++ then ;
: "out          ( a1 n1 --- )   127 and dup ?nline type space ;
: $out          ( a1 --- )      count "out ;
: chrout        ( c1 --- )      emit space ;
: cout          ( c1 --- )      1 ?nline emit ;
: ##out         ( n1 --- )      6 ?nline 0 <# #s #> type space ;

: pasquery      ( -- )          \ get a line from the input file
                lineread count 2- 0max dup #tib ! tib swap cmove
                >in off                         \ reset >IN
\ ****
\ Add these lines to echo each the pascal source line to the output as
\ a Forth comment line.
                #out @ dup>r 39 >
                if      cr
                then
                40 sp>col ." \ " outbuf count 2- 0max type
                cr r> 6 >
                if      6 spaces
                then
\ ****
                ;

: charread      ( -- c1 )       \ get a character from the input file
                >in @ #tib @ >=                 \ if at line end,
                if      begin   pasquery        \ get a line of source
                                #tib @ 0=       \ if tib empty?
                        while   inlength @ 0=   \ and read buffer empty?
                                if abort then   \ then end of file, leave
                        repeat                  \ else repeat till we have
                                                \ more source to parse
                        ?keypause
                then
                tib >in @ + c@                  \ -- c1
                incr> >in
                ;

0 value no-const-or-vars        0 value chrpr
0 value typ                     0 value char-           0 value arraysize
0 value varcnt                  0 value ptyp
0 value parcnt                  0 value ptr

 80 array a$
160 array var$

defer limtyp

: clrbuf        ( a1 --- )              \ clear buffer
                dup 69 erase dup 65 blank 0 swap c! ;

: tokenpron     ( --- ) on> chrpr ;      \ token printing on

: tokenproff    ( --- ) off> chrpr ;     \ token printing off

\ : ?emit         ( c1 --- c1 )
\                 dup bl  <> chrpr and
\                 if      dup emit
\                 then   ;

: a-z           ( c1 --- f1 )
                bl or 'a' 'z' between ;

: a-f           ( c1 --- f1 )
                bl or 'a' 'f' between ;

: not0-f        ( c1 --- f1 )
                bl or dup  '0' 'f' between 0=           \ not 0 to f
                      swap '9' 'a' between or ;         \ or  9 to a

: nota-zor0-9   ( c1 --- f1 )
                bl or dup  '0' 'z' between 0=
                      swap '9' 'a' within  or ;

: typck        ( n1 --- f1 )
                CREATE C, DOES> C@ typ = ;

 0 typck keyword?        1 typck ident?
 2 typck ==?             3 typck char?
 4 typck #?              5 typck :=?
 6 typck :?              7 typck <?
 8 typck <=?             9 typck <>?
10 typck >=?            11 typck >?
12 typck string?        14 typck (?
15 typck )?

: keyck        ( n1 --- f1 )
                CREATE C, DOES> C@ ptr = keyword? and ;

 0 keyck and?            1 keyck array?
 2 keyck begin?          3 keyck newline?
 4 keyck case?           5 keyck const?
 6 keyck div?            7 keyck do???
 8 keyck downto?         9 keyck else?
10 keyck endd?          11 keyck for?
12 keyck func?          13 keyck if?
14 keyck integer?       15 keyck mem?
16 keyck mod?           17 keyck not?
18 keyck of?            19 keyck or?
20 keyck proc?          21 keyck read?
22 keyck repeat?        23 keyck shl?
24 keyck shr?           25 keyck then?
26 keyck to?            27 keyck type?
28 keyck until?         29 keyck var?
30 keyck while?         31 keyck write?
32 keyck in?

code inset      ( a1 n1 -- )
                pop cx
                push #tib                       mov #tib bx
                push >in                        mov >in  # 0 word
                push 'tib       lodsw           mov 'tib ax
                load_bx
                jmp cx          end-code

code insave     ( -- )
                pop cx
                push #tib
                push >in
                push 'tib
                jmp cx          end-code

code inrec      ( -- )
                pop cx
                pop 'tib
                pop >in
                pop #tib
                jmp cx          end-code

: crck         ( c1 -- f1 )
                CREATE C, DOES> C@ char- = char? and ;

';' crck ;?     '.' crck .?     '[' crck [?     ']' crck ]?
'*' crck *?     '-' crck -?     '+' crck +?     ',' crck ,?
'#' crck ##?

                \ compile a word which check match on its own first
                \ character.

: a$=a$+char    ( c1 --- )
                a$ count + c! 1 a$ c+! ;

: var$move      ( --- )
                a$ count var$ count + swap 1+ cmove
                a$ 1+
                begin   1+ dup c@ bl =
                until   incr> varcnt
                1+ a$ 1+ - var$ c+! ;

: "pabort       ( f1 a1 n1 -- )         \ pascal abort handler
                rot
                if      crout tib #tib @ "out
                        crout >in @ spaces "  - " "out
                        "out bye
                else    2drop
                then    ;

: to-or-downto?? to? downto? or 0= " To Expected !"             "pabort ;
: ident??    ident?   0=  " Identifier Expected !"              "pabort ;
: keyword??  keyword? 0=  " Keyword Expected !"                 "pabort ;
: :??        :?       0=  " ':' Expected !"                     "pabort ;
: (??        (?       0=  " '(' Expected !"                     "pabort ;
: )??        )?       0=  " ')' Expected !"                     "pabort ;
: :=??       :=?      0=  " ':=' Expected !"                    "pabort ;
: ==??       ==?      0=  " '=' Expected !"                     "pabort ;
: ;??        ;?       0=  " ';' Expected !"                     "pabort ;
: .??        .?       0=  " '.' Expected !"                     "pabort ;
: [??        [?       0=  " '[' Expected !"                     "pabort ;
: ]??        ]?       0=  " ']' Expected !"                     "pabort ;
: #??        #?       0=  " Number Expected !"                  "pabort ;
: #a??       #?       0=  " No Consts or Vars Allowed here !"   "pabort ;
: integer??  integer? 0=  " Integer Expected !"                 "pabort ;
: until??    until?   0=  " Until Expected !"                   "pabort ;
: mem??      mem?     0=  " Incorrect Keyword !"                "pabort ;
: do??       do???    0=  " Do Expected !"                      "pabort ;
: to??       to?      0=  " To Expected !"                      "pabort ;
: of??       of?      0=  " Of Expected !"                      "pabort ;
: end??      endd?    0=  " End Expected !"                     "pabort ;
: then??     then?    0=  " Then Expected !"                    "pabort ;
: string??   string?  0=  " Number Expected !"                  "pabort ;
: found??    0= " Error in variable create process"             "pabort ;
: no-const-or-vars??   no-const-or-vars
             " No Consts or Vars Allowed here !"                "pabort ;

: \=            ( c1 --- f1 ) ascii \ = ;

: '=            ( c1 --- f1 ) ascii ' = ;

: get$          ( c1/a1 --- c2 ) \ pass a1 the cfa of test rtn
                !> limtyp        \ and get string till tst pass
                a$ clrbuf
                begin   a$=a$+char charread dup limtyp
                        over 0= or
                until   ;

: bslsh         ( c1 --- )      \ dump text till '\'
                ['] \= get$ drop
                bl a$ 2+ c!     \ clear * to a blank
                a$ count 1- type crout ;

: a$>#          ( --- n1 )
                a$ number? 2drop ;

: skipblanks    ( --- c1 )
                bl
                begin   drop charread dup bl -
                until   ;

: string      ( c1 --- )
              drop bl ['] '= get$ drop 0 a$=a$+char 12 =: typ ;

: numbr       ( c1 --- n1 )
              ['] not0-f get$ drop 4 =: typ >in decr a$># ;

: coln          ( c1 --- )
                drop    6 =: typ charread '=' =
                if      5 =: typ
                else    decr> >in
                then   ;

: gthan         ( c1 --- )
                drop    charread '=' =
                if      10 =: typ
                else    11 =: typ
                        decr> >in
                then   ;

: lthan         ( c1 --- )
                drop    charread dup '>' =
                if      drop    9 =: typ
                else    '=' =
                        if      8 =: typ
                        else    7 =: typ
                                decr> >in
                        then
                then   ;

create kw-table
," and    "    ," array  "    ," begin  "    ," newline"
," case   "    ," const  "    ," div    "    ," do     "
," downto "    ," else   "    ," end    "    ," for    "
," func   "    ," if     "    ," integer"    ," mem    "
," mod    "    ," not    "    ," of     "    ," or     "
," proc   "    ," read   "    ," repeat "    ," shl    "
," shr    "    ," then   "    ," to     "    ," type   "
," until  "    ," var    "    ," while  "    ," write  "
," in     "
33 constant table-size

: a$srch        ( -- f1 )
                false
                table-size 0
                do      a$ 1+ i 8 * kw-table + count caps-comp 0=
                        if      0= i =: ptr leave
                        then
                loop    ;

: a-ident       ( c1 --- )
                dup a-z
                if      ['] nota-zor0-9 get$ drop
                        decr> >in
                        a$srch 0= 1 and =: typ
                        r>drop               \ pop out of def above
                then   ;

: a-#           ( c1 --- n1 )
                dup not0-f 0=
                if      numbr                   \ -- n1
                        r>drop               \ pop out of def above
                then   ;

: a-:           ( c1 --- )
                dup ':' =
                if      coln
                        r>drop
                then ;

: a-<           ( c1 --- )
                dup '<' =
                if      lthan
                        r>drop
                then ;

: a->           ( c1 --- )
                dup '>' =
                if      gthan
                        r>drop
                then ;

: a-$           ( c1 --- )
                dup ascii ' =
                if      string
                        r>drop
                then ;

: a-(           ( c1 --- )
                dup '(' =
                if      drop
                        14 =: typ
                        r>drop
                then ;

: a-)           ( c1 --- )
                dup ')' =
                if      drop
                        15 =: typ
                        r>drop
                then ;

: a-=           ( c1 --- )
                dup '=' =
                if      drop
                        2 =: typ
                        r>drop
                then ;

: token         ( --- c1 )
                begin
                        begin skipblanks ?dup
                        until dup '\' =                 \ ignore comments
                while   bslsh
                repeat  a-ident a-#     a-:
                        a-<     a->     a-$
                        a-(     a-)     a-=
                        3 =: typ                \ other characters
                          =: char- ;

256 constant maxcon     32 constant b/con       \ 8k
768 constant maxvar     32 constant b/var       \ 24k

0 value con#            0 value pcons
0 value var#            0 value pvars

: >c_name       ( n1 -- a1 )
                b/con * pcons + 2+ ;

: >v_name       ( n1 -- a1 )
                b/var * pvars + 2+ ;

: pconstant     ( n1 | <name> -- )
                con# b/con * pcons + swap over !        \ drop in the value
                bl word swap 2+ over c@ 1+ b/con 2- min cmove
                incr> con# ;

: pvariable     ( | <name> -- )
                var# b/var * pvars + dup off            \ drop in a zero
                bl word swap 2+ over c@ 1+ b/var 2- min cmove
                incr> var# ;

: $incon        ( a1 -- a2 f1 )
                false swap
                pcons con# b/con * bounds
                ?do     i 2+ over dup c@ 1+ caps-comp 0=
                        if      2drop true i 2+ leave
                        then
         b/con +loop    swap ;

: $invar        ( a1 -- a2 f1 )
                false swap
                pvars var# b/var * bounds
                ?do     i 2+ over dup c@ 1+ caps-comp 0=
                        if      2drop true i 2+ leave
                        then
         b/var +loop    swap ;

: pdefined      ( | <name> -- a1 f1 )   \ is following name defined in
                                        \ constant or variable table?
                bl word $incon ?dup ?exit $invar ;

: a$constant    ( --- a1 )      \ make a constant, return name
                a$ count inset -1 pconstant inrec
                con# 1- >c_name ;

: a$place       ( --- a1 )
                a$ count inset pdefined inrec 0=
                if      drop  a$constant
                then   ;

: a$variable    ( --- a1 )
                a$ count inset pdefined inrec 0=
                if      drop
                        a$ count inset pvariable inrec
                        var# 1- >v_name
                then    ;

: a$find??      ( --- a1 )
                a$ count inset pdefined inrec 0=
                if      cr ." ** Unspecified Identifier ->" count type
                        a$constant crout+
                then   ;

: create-constant       ( --- )
                begin   a$constant >r
                        token   ==??
                        token   ( --- n1 ) #??
                        dup     here 2- !
                        crout   ##out " CONSTANT" "out r> $out
                        token   ;??
                        token   ident? 0=
                until   ;

: const- ( --- )
         no-const-or-vars?? token ident?? create-constant ;

: makevars      ( --- f1 )
                integer??
                var$ count inset varcnt >r
                begin   pvariable crout " VARIABLE" "out
                        var# 1- >v_name $out
                        decr> varcnt
                        varcnt 1 <
                until   r> =: varcnt
                inrec   token ;? dup
                if      drop token ident? then   0=  ;

: makearrays    ( --- f1 )      \ var name array [23] of integer;
                token   [??  token
                #a??    2* =: arraysize
                token   ]??             token   of??
                token   integer??       token   ;??
                var$ count inset
                begin   pvariable crout
                        arraysize ##out " ARRAY" "out
                        var# 1- >v_name $out
                        decr> varcnt
                        varcnt 1 <
                until   inrec token   ident? 0=  ;

: var-          ( --- )         \ var name,name : integer;
                no-const-or-vars?? token
                begin   off> varcnt 0 var$ c!
                        begin   ident?? var$move token ,?
                        while   token
                        repeat  :??
                        token   array?
                        if      makearrays
                        else    makevars
                        then
                until   ;

: par-pass      ( a1 --- )
                >r var- crout " :" "out r> $out 16 sp>col
                var$ count inset varcnt =: parcnt
                begin   pdefined found??
                        decr> varcnt
                        varcnt 1 <
                until   inrec   parcnt =: varcnt
                begin   $out " !" "out
                        decr> varcnt varcnt 1 <
                until   )?? token ;

: proc-         ( --- )
                token   ident?? on> ptyp a$place ( --- a1 )
                token   (?
                if       off> ptyp par-pass
                         on> no-const-or-vars
                then     ;??     token   block- " ;" "out
                on> ptyp ;??     token   block- ;

: begin-        ( --- )
                begin   token   statment   ;? 0=
                until   end??   token ;

: par-to-stk    ( --- )
                begin   token   expr-      ,? 0=
                until   )??     token ;

: variable?     ( a1 --- f1 )   \ is name addr a1 in the array of variables?
                pvars dup b/var maxvar * + ubetween ;

: variable??    ( a1 --- )      \ error if not a variable
                dup variable? 0=
                if      crout " Assignment to NON-Variable->" "out
                        count "out crout
                else    drop
                then   ;

: varconout     ( a1 --- )
                dup $out variable?
                if      " @" "out
                then   ;       \ test if this is a variable

: constant-     ( --- )
                ident?
                if      a$find?? ( --- a1 ) token [?
                        if      $out  token expr-
                                " 2* + @" "out ]?? token
                        else    (?   if      par-to-stk  $out
                                     else    varconout
                                     then
                        then
                else    #?
                        if      ##out    token
                        else    " ascii" "out a$place $out token
                        then
                then   ;

                \ returns string for operator if true
: +-or?         ( --- <a1> <n1> f1 )
                -?  if  " -"  true exit then
                +?  if  " +"  true exit then
                or? if  " or" true exit then false ;

: term-oper?    ( --- <a1>/f1 )
                div? if " div" true exit then
                mod? if " mod" true exit then
                and? if " and" true exit then
                shl? if " shl" true exit then
                shr? if " shr" true exit then
                  *? if " *"   true exit then false ;

: factor-       ( --- )
                not?
                if      token   factor-         \ recurse here
                        " 0=" "out
                then   keyword?
                if      mem??   token [?? token expr- ]??
                        " @" "out token
                else    (?
                        if      token expr- )?? token
                        else    constant-
                        then
                then   ;


: term-         ( --- )
                factor-  term-oper?             \ -- <a1> f1
                if
                        begin   token factor-
                                $out           \ string is passed in
                                term-oper? 0=
                        until
                then   ;

: simp-expr     ( --- )
                -?
                if      token   term-   " negate" "out
                else    +?
                        if      token
                        then   term-
                then   +-or?
                if
                        begin   token simp-expr "out +-or? 0=
                        until
                then   ;

: in-           ( --- )
                [??  " dup" "out token simp-expr
                     " ="   "out ,?
                if
                        begin  token crout++ " over" "out
                                simp-expr    " = or" "out ,? 0=
                        until
                then   ]??          " nip" "out
                token   ;

: expr-         ( --- )
                simp-expr
                ==? if  token simp-expr " ="  "out then
                 <? if  token simp-expr " <"  "out then
                 >? if  token simp-expr " >"  "out then
                <>? if  token simp-expr " <>" "out then
                <=? if  token simp-expr " <=" "out then
                >=? if  token simp-expr " >=" "out then
                in? if  token in-                   then ;

: var-assign    ( --- )
                ident?? a$find?? token (?
                if      par-to-stk
                then   dup>r variable?
                if      [?
                        if      token expr-
                                " 2* " "out
                                ]??   token
                                :=??
                                token   expr- r> $out " ROT + !" "out
                        else    :=??
                                token   expr- r> $out " !" "out
                        then
                else    r> $out
                then   ;

: if-           ( --- )
                token   expr-   then??
                        crout+ " IF     " "out token statment else?
                if      crout+ " ELSE   " "out token statment
                then    crout+ " THEN   " "out ;

: cases-        ( -- )
                " dup" "out token constant- " ="    "out ,?
                if      begin token crout++ " over" "out
                                constant-   " = or" "out ,? 0=
                        until
                then    :??
                crout+  " IF     " "out token statment
                crout+  " ELSE   " "out ;

: case-         ( --- )
                token   expr-   of??
                crout+ " CASE    " "out
                begin   cases-
                        ;? 0=
                until   " drop" "out else?
                if      token   statment
                then    end??
                crout+ " ENDCASE" "out token ;

: while-        ( --- )
                        crout+ " BEGIN  " "out token expr- do???
                if      crout+ " WHILE  " "out token statment
                        crout+ " REPEAT " "out
                then   ;

: repeat-       ( --- )
                crout+  " BEGIN  " "out
                begin   token statment ;? 0=
                until   until?? token expr-
                crout+  " UNTIL  " "out ;

: for-          ( --- )
                token   ident?? a$find?? >r token :=??
                token   expr-   to-or-downto?? r> to?
                if       1 >r
                else    -1 >r
                then    >r
                token   expr-   do??    r>  r@ ##out >r
                        " + swap" "out crout+ " DO     " "out
                token   " I" "out r> $out " !" "out statment
                        r> ##out crout+ " +LOOP  " "out ;

: a$compile     ( --- )
                '.' cout '"' chrout
                a$ count 1 /string "out '"' chrout ;

: write-        ( --- )
                token   (??
                begin   crout++
                        token   string?
                        if      a$compile token
                        else    ##?
                                if      token expr-     " ."    "out
                                else    expr-           " emit" "out
                                then
                        then    ,? 0=
                until   )?? token ;

\ : #input        ( --- n1 )
\                 query bl word number? 0=
\                 " Must be a NUMBER" "pabort drop ;

: read-         ( --- )
                token   (??
                begin   crout++
                        token   ##?
                        if      " #input"       "out token
                        else    " key dup emit" "out
                        then
                        ident?? a$find??
                        dup variable?? $out
                        token   [?
                        if      token expr- ]?? " 2* + "  "out
                                token
                        then    " !" "out
                        ,? 0=
                until   )?? token ;

: mem-          ( --- )
                token   [??     token   expr-   ]??
                token   :=??    token   expr- " swap !" "out ;

: newlin-       ( -- )
                crout++
                " cr" "out token ;

: do-statment   ( --- )
                ptr 31 and exec:        \ statment interpretation table
        noop    noop    begin-  newlin- case-   noop    noop    noop
        noop    noop    noop    for-    noop    if-     noop    mem-
        noop    noop    noop    noop    noop    read-   repeat- noop
        noop    noop    noop    noop    noop    noop    while-  write- ;

: statment     ( --- )
                crout++
                keyword?
                if      do-statment
                else    var-assign
                then    ;

: begin-1       ( <a1> --- )    \ a1 exists if ptyp is on & is in HEAD SPACE.
                ptyp
                if      crout " :" "out ( a1 --- ) $out 16 sp>col
                then    begin- ;

0 value  ?stp

: stp   on> ?stp ;

: do-block      ( --- )
                ptr 31 and exec:    \ block interpretation table
        stp     stp     begin-1 stp     stp     const-  stp     stp
        stp     stp     stp     stp     proc-   stp     stp     stp
        stp     stp     stp     stp     proc-   stp     stp     stp
        stp     stp     stp     stp     stp     var-    stp     stp ;

: block-        ( <a1> --- )    \ a1 exists if ptyp is on
                keyword?
                if      off> ?stp
                        begin   do-block ?stp
                        until
                then   ;

: pas_init      ( -- )
                #tib off        >in off
                off> con#       off> var# ;

: program       ( --- )
                pas_init
                off> no-const-or-vars
                token                   \ pickup "Program" and discard
                token   ident?? a$place ( --- a1 )
                token   (?  on> ptyp
                if      par-pass on> no-const-or-vars
                        off> ptyp
                then   ;??
                token   block-
                crout+ " ; " "out .??
                crout crout ;

: init_arrays       ( -- )
                pcons ?exit
                maxcon b/con * dup ds:alloc =: pcons pcons swap erase
                maxvar b/var * dup ds:alloc =: pvars pvars swap erase
                var$ off a$ off ;

: main2         ( -- )
                init_arrays
                bl word $file abort" Couldn't open file."
                crout
                program ;

: main          ( -- )
                DECIMAL                         \ always select decimal
                CAPS ON                         \ ignore cAsE
                ?DS: SSEG !                     \ init search segment
                DOSIO_INIT                      \ init EMIT, TYPE & SPACES
                $FFF0 SET_MEMORY                \ default to 64k code space
                DOS_TO_TIB                      \ move command tail to TIB
                main2 ;

}

