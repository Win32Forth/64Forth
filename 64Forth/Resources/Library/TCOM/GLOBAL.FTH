\\ GLOBAL.SEQ    Perform a global edit on a set of files    by Tom Zimmer

{

   700 constant maxfiles        \ only hold upto 700 filenames in list
                                \ from any given directory.
          0 value files_srch    \ accumulator for number of files searched
          0 value ?all
          0 value ?tonext
        128 array spec_buf      \ a place to hold the file specs
         64 array rwith-buf
           handle outhndl

odd_align                       \ make sure SLOOK.BUF is odd aligned
256 array slook.buf             \ a place to hold the search string

odd_align
outbuf drop                     \ make sure OUTBUF is ODD aligned

: searchfile    ( -- f1 )       \ search current file for specified string
                                \ return f1=true if string was found
                IBRESET                 \ reset lineread operatons
                false
                begin   lineread c@ dup 132 >
                        if      64 outbuf c! dup 64 -
                                dup negate instart +! inlength +!
                        then
                while   slook.buf count outbuf count search nip
                        if 0= exit
                        then
                        broken @ if bye then
                repeat  ;

: replacefile   ( -- )  \ replace strings in file
                cr cr ." FOUND IN FILE: " seqhandle count type
                outhndl clr-hcb
                seqhandle dup count rot >pathend" nip - outhndl place
                " TEMP.OUT" outhndl +place
                outhndl hcreate abort" Failed to create TEMP.OUT"
                off> ?tonext
                0.0 seqhandle movepointer
                IBRESET                 \ reset lineread operatons
                begin   lineread c@ dup 132 >
                        if      64 outbuf c! dup 64 -
                                dup negate instart +! inlength +!
                        then
        [long]  while   outbuf count
                        begin   slook.buf count 2over search
                                dup
        [long]                  if      cr outbuf count
                                        2dup 0Ah scan nip - 79 min type
                                        key?
                                        if      key drop
                                                off> ?all
                                        then
                                    ?all 0=
        [long]                      if
                cr ." Replace? [Y/N/Skipto_next_file/Replace_all/ESC_abort] {N}: "
                                        key
                                        case  27 of  ." ABORT!"
                                                     bye        endof
                                             upc
                                             'R' of  ." REPLACE ALL!"
                                                     on> ?all   endof
                                             'Y' of  ." Yes"    endof
                                             'S' of  ." Skip to next file!"
                                                     -1. seqhandle movepointer
                                                     ibreset
                                                     2drop dup false
                                                     on> ?tonext
                                                                endof
                                                     ." NO!" 2drop false
                                        endcase
                                    then
                                then
                        while   >r 2dup drop r@ outhndl hwrite drop
                                                        \ write first part
                                rwith-buf count outhndl hwrite drop
                                                        \ write replace string
                                r> slook.buf c@ + /string \ strip off text
                        repeat  drop dup>r outhndl hwrite r> -
                                abort" Write error to TEMP.OUT"
                        broken @ if bye then
                repeat
                outhndl hclose drop
                ?tonext 0=
                if      seqhandle hclose drop
                        seqhandle hdelete drop
                        outhndl seqhandle hrename drop
                else    outhndl   hdelete drop
                then    ;

: do_1file      ( n1 -- )       \ open search and close one file
                dup >fadr 1+ c@l '.' =
                if      drop exit
                then    >fadr dir>pad >r
                spec_buf seqhandle $>handle
                seqhandle >pathend
                dup seqhandle 1+ - r@ + seqhandle c! r> cmove
                seqhandle count + off
                seqhandle hopen 0=
                if      searchfile
                        if      replacefile
                        then
                        incr> files_srch
                then
                seqhandle hclose drop           \ close the file
                seqhandle clr-hcb ;             \ clear the handle

: $do_1spec     ( a1 -- )       \ do all files in a filespec
                count spec_buf place            \ put in spec buffer
                spec_buf count '.' scan nip 0=
                if      " .*" spec_buf +place   \ add .* to name given
                then
                spec_buf ?uppercase $getdir     \ read the directory files.
                #fls 0
                ?do     i do_1file              \ sum all file bytes
                        ?keypause
                loop    ;

: searchallof   ( | file_specs --- )    \ Do search all matching file_specs.
                begin   bl word dup c@
                while   $do_1spec
                repeat  drop ;

: ?in-empty     ( --- f1 )      \ is anything left in input stream?
                >in @ bl word c@ 0= swap >in ! ;

: ?esc_bye      ( -- )          \ leave if user pressed ESC
                esc_flg @ if ABORT then ;

: spec-needed   ( -- )
                ?in-empty
                abort"  At least one file specification is required" ;

: DOEXP1        ( A1 C1 N1 -- A2 N2 )   \ n2 = loop count
                OVER $C7 =      ( HOME )        \ if Home, then clear line
                IF      DUP>R AT? >R SWAP - R> 2DUP AT R@ SPACES AT R>
                        NEGATE >R DROP R@ + R>
                        EXIT
                THEN
                OVER $08 =      ( BACKSPACE )   \ if BS then backup one
                IF      0=
                        IF      DROP BEEP 0     \ or BEEP if at beginning
                        ELSE    (EMIT)         \ backup one char
                                BL (EMIT)
                                8 (EMIT)       \ erase chars space
                                -4 #OUT +!
                                1- -1
                        THEN    EXIT            \ leave if BACKSPACE
                THEN    DROP                    \ discard current index
                DUP $1B =       ( ESC )         \ char = ESC?, then cancel
                IF      DROP                    \ discard char
                        #EXSTRT @ ?DUP
                        IF      SPAN @ SWAP ABS SPAN !
                        ELSE    SPAN @ SPAN OFF \ skip to end
                        THEN
                        ESC_FLG ON              \ set escaped flag
                ELSE                            \ else emit, and bump to next
                        DUP EMIT OVER C! 1+ 1
                THEN    ;

: #EXSTRT_@+    ( a1 -- a2 n1 )         \ adj a1 by #exstrt
                #EXSTRT @ DUP>R + R> DUP NEGATE #EXSTRT ! ;

0 value ?g-char

: my#EXPECT     ( a1 n1 n1 -- )         \ EXPECT chars n1 into addr a1.
                                        \ starting at char n2 in string
                0MAX    DUP #EXSTRT ! ?DUP
                IF      2 PICK SWAP TYPE        \ display text sofar
                THEN
                ESC_FLG OFF
                DUP SPAN ! 0
        [long]  ?DO     #EXSTRT @ 0>
                        IF      #EXSTRT_@+
        [long]          ELSE    ?g-char
                                if      KEY DUP $20 =
                                        if      drop 158
                                        then    false
                                else    KEY DUP $0D =   \ if CR then leave, done
                                then
                                IF      DROP I SPAN ! LEAVE
                                ELSE    dup 158 =       \ Alt-A
                                        if      ?g-char 0= !> ?g-char
                                                drop 0 cr
                                        else    I DOEXP1
                                        then
                                THEN
                        THEN
                +LOOP   DROP ;

: myQUERY       ( -- )
                TIB 80 0 my#EXPECT  SPAN @ #TIB ! >IN OFF  ;

: .info         ( -- )
        ." Tom Zimmer's Global Edit utility V1.0 02/24/93"
                cr ." Usage: GLOBAL <-ALL> <search_text> <replace_text> <file_spec(s)> <Enter>"
                ?in-empty
        if      cr ."   Prompting for missing parameters, press ESC to cancel"
                cr
        then    ;

: ?/All         ( -- )          \ /ALL switch
                >in @ bl word 1+ " -ALL" comp 0=
                if      drop
                        on> ?all
                else    >in !
                then    ;

: main          ( -- )          \ prompts for search and replace strings
                                \ then file specs, and performs the edit
                CAPS ON                 \ ignore cAsE
                ?DS: SSEG !             \ init search segment
                DOSIO_INIT              \ init EMIT, TYPE & SPACES
                $FFF0 SET_MEMORY        \ default to 64k code space
                DOS_TO_TIB              \ move command tail to TIB
                COMSPEC_INIT            \ initialize shelling to DOS
                maxfiles =: maxdir      \ up to "maxfiles" directory entries
                dirinit                 \ initialize directory words
                diralloc                \ allocate directory name space
                dirseg                  \ if allocated properly, non-zero
                off> files_srch
 [long] if      20000 =: iblen          \ make read buffer larger
                lineread_init           \ initialize fast file reader
                off> ?all
                .info
                ?/All
                bl word c@ 0=
                if      cr ." Text to Search for: "
                        myquery 0 word
                else    here
                then    count  slook.buf place
                slook.buf c@ 0= abort" A search string is required"
                bl word c@ 0=
                if      cr ." Text to Replace with: "
                        myquery 0 word
                else    here
                then    count rwith-buf place
                ?in-empty
                if      cr ." File Specification(s) to Search: "
                        myquery
                then
                spec-needed             \ default file specification needed
                cr ." Replacing: " slook.buf count type
                   ."  with: "     rwith-buf count type
                   ."  in: "       tib #tib @ >in @ /string type
                searchallof             \ search everything
                                        \ then report summary of search
                cr ." Done!"
                dirrelease              \ release directory name space
        else    cr ." Couldn't allocate enough memory"
        then    ;


