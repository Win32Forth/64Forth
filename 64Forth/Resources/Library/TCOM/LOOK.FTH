\ LOOK.SEQ      Target compilable string search across many files
ANEW LOOKMODULE
\ ***************************************************************************
\                       LOOK Description & Usage
\ ***************************************************************************
\ 
\   Here is a handy utility to search for a string in one or more files
\ on your disk. It is used as follows:
\ 
\                 LOOK <string> <file_specs> <enter>
\ 
\                 LOOK "<string with spaces>" <file_specs> <enter>
\ 
\   The string is space or quote delimited, and the file specs are space
\ delimited. Multiple file specs can be included on the same line.
\ 
\   You can also type in LOOK alone, and you will be prompted for the
\ search string and file specs.
\ 
\                 LOOK <enter>
\                 String to LOOK for     -><string with spaces> <enter>
\                 File spec(s) to search -><file_specs> <enter>
\ 
\   The search will proceed, processing progresses at about 40,000 bytes
\ per second on a 6 mhz PC-AT clone.
\ 
\   Each file processed will cause a partial rotation of the "spinner"
\ (see the spinner definition) to be displayed on the screen. When the
\ search string is found, the filename is displayed, followed by the line
\ number of the found line, and the lines contents up to 74 characters on
\ the line. The filename is only displayed the first time a string is
\ found.
\ 
\   The LOOKing process can be paused by pressing the space bar, and can
\ be terminated with ESC.
\ 
\   DOS I/O re-direction is allowed, so the following:
\ 
\                 LOOK ZIMMER *.SEQ >ZFOUND.LST <enter>
\ 
\                 LOOK "TOM ZIMMER" *.SEQ >ZFOUND.LST <enter>
\ 
\   This will build a file containing all occurances of "TOM ZIMMER"
\ found in the *.SEQ files of the current directory into a file called
\ ZFOUND.LST.
\ 
\   Only the first 700 files in a directory will be searched, although
\ you can change the constant MAXFILES and recompile LOOK to increase of
\ decrease this limit.
\ 
\   Users of Forth BLOCK file systems may find LOOK useful in scanning
\ their source files for text strings. LOOK will detect a file that
\ doesn't contain CRLF delimited lines, and automatically break the file
\ search into 64 character lines. This make reading the output of a scan
\ through .BLK or .SCR files much more readable.
\ 
\ ***************************************************************************
\                          Program Code Begins
\ ***************************************************************************
REQUIRE allspecs.fth

   700 constant maxfiles        \ only hold upto 700 filenames in list
                                \ from any given directory.
    40 constant lookmax         \ longest string we will search for

        2variable bytes_srch    \ accumulator for number of bytes searched
        2variable lines_srch    \ accumulator for total lines searched
          0 value files_srch    \ accumulator for number of files searched
          0 value dirs_srch     \ accumulator for number of directories
          0 value occur_srch    \ accumulator for occurances found
          0 value ?global       \ search ALL directories flag
          0 value ?count_only   \ only count files containing string
         variable fstime        \ first time found flag, used in each file
         variable do_prompt     \ flag, is a prompt needed
        128 array spec_buf      \ a place to hold the file specs

odd_align                       \ make sure SLOOK.BUF is odd aligned
 lookmax 1+ array slook.buf     \ a place to hold the search string

odd_align
outbuf drop                     \ make sure OUTBUF is ODD aligned

: .file-once    ( --- )         \ display filename first time text found
                fstime @ ?exit
                ?out_redirect 0=
                if      #line @ rows min #line !
                then
                cr space blue >bg yellow >fg space
                .seqhandle cols 1- sp>col
                black >bg ltgray >fg
                fstime on
                line_limit @ 64 =
                if      cr ."  BLK  HEX  DEC LINE"
                then    ;

: .outbuf       ( -- )          \ display the readline buffer
                outbuf count bounds
                do      i dup c@ bl max swap c!     \ filter out ctrl chars
                loop
                outbuf count 2- 72 min 0max type ;  \ display line

0 value spinval

: spinnero       ( -- )          \ video spinner, doesn't effect cursor
                                \ positon or I/O redirection. It is however
                                \ VERY HARDWARE SPECIFIC TO IBM'S & CLONES
                " |/-\" drop spinval 3 and + c@
                video-seg @ at? rows 1- min cols 2* * swap 2* + c!L
                incr> spinval ;

32 array spin$

: spinner       ( -- )
                spin$ 32 bounds
                do     bl i c! BLUE $10 * LTGREEN + i 1+ c!
             2 +loop
                seqhandle >pathend" 16 min dup>r 2* spin$ 2+
                12 r> - 0max 2* + swap bounds
                ?do     dup c@ i c! BLUE $10 * LTGREEN + i 1+ c! 1+
             2 +loop    drop
                ?ds: spin$ video-seg @ at? rows 1- min cols 2* * swap 2* + 2+
                28 cmovel ;

: .fline#       ( -- )
                cr line_limit @ 64 =
                if      loadline @ 0 16 um/mod dup 6 spaces
                        save> base hex
                        0 <# # # # #> type
                        restore> base
                        5 u.r 5 .r
                else    loadline @ 5 u.r
                then    space ;

0 value ?noslow

: searchfile    ( --- )         \ search current file for specified string
                IBRESET                 \ reset lineread operatons
                255 line_limit !        \ default to normal text file
                lineread c@ 250 >
                if       64 line_limit !
                then    0.0 seqhandle movepointer
                IBRESET         \ reset lineread operatons
                fstime off              \ mark file as nothing found yet
                spinner                 \ notify user we are searching 1 more
                begin   lineread c@
        [long]  while   slook.buf count outbuf crlf>bl's dup c@ dup>r 1+
                        bl outbuf c!                  \ count becomes a blank
                        search nip
                        r> outbuf c!                  \ restore the count
                        if      15 spaces .file-once space
                                incr> occur_srch
                                ?count_only ?exit     \ ***** EXITS HERE *****
                                .fline#
                                .outbuf
                                ?noslow 0= 1 and tenths \ delay a tenth second
                                ?keypause
                        then
                        lines_srch 2@ 1. d+ lines_srch 2!
                repeat  fstime @
                if cr ?noslow 0= 3 and tenths           \ delay a tenth second
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
                        seqhandle endfile bytes_srch D+!
                        incr> files_srch
                then
                seqhandle hclose drop           \ close the file
                seqhandle clr-hcb ;             \ clear the handle

: $do_1spec     ( a1 | -- )             \ do all files in a filespec
                incr> dirs_srch
                count spec_buf place    \ put in spec buffer
                spec_buf $getdir                \ read the directory files.
                #fls 0
                ?do     i do_1file
                        ?keypause
                loop    ;

: pad+\spec     ( -- )
                pad count + 1- c@ '\' <>
                if      " \" pad +place
                then    bl word count over c@ '\' =
                if      1 /string
                then    pad +place ;

: $do_1set      ( a1 -- )
                >in @ >r
                begin   >in @ #tib @ <
                while   dup count pad place pad+\spec
                        pad $do_1spec
                repeat  drop r> >in ! ;

: searchallof   ( | file_specs --- )    \ Do search all matching file_specs.
                0. bytes_srch 2!
                0. lines_srch 2!
                0 !> files_srch
                0 !> dirs_srch
                dirseg 0= if #tib @ >in ! exit then
                ?global
                if      getdirs
                        begin   nextdir
                                dup c@
                        while   $do_1set
                        repeat  drop
                else    begin   >in @ #tib @ <
                        while   bl word $do_1spec
                        repeat
                then    15 spaces cr ;

: ?in-empty     ( --- f1 )      \ is anything left in input stream?
                >in @ bl word c@ 0= swap >in ! ;

: ?esc_bye      ( -- )          \ leave if user pressed ESC
                esc_flg @
                if      ?out_redirect if cr then
                        ABORT
                then    ;

0 value conout

: set_console   ( -- )          \ save output and set to console
                conout ?exit
                ?CS: $19 c@L !> conout          \ save current output
                1 ?CS: $19 c!L ;                \ set to screen console

: restore_console ( -- )        \ restore output as specified by commandline
                conout 0= ?exit
                conout ?CS: $19 c!L             \ restore current output
                off> conout ;

: get-filespecs ( --- )         \ get one or more file specifications
                set_console
                ?in-empty       \ if nothing following command
                if      do_prompt @
                        if      ." File spec(s) to search  [*.*]  ->"
                                query cr
                                ?esc_bye
                        then
                        ?in-empty                   \ if nothing following
                        if      " *.*" ">$ $>tib    \ default to "*.*",
                        then                        \ ALL files
                then    ." in "
                tib #tib @ >in @ /string type space
                restore_console ;

: get-options   ( -- )
                >in @ bl word
                     1+ " -?" caps-comp 0=              \ ?=help
                if      drop .info .info2        bye    then
                here 1+ " -s" caps-comp 0=              \ case sensitive
                if      drop off> caps                  \ next word
                        >in @ bl word drop              then
                here 1+ " -c" caps-comp 0=              \ count only
                if      drop on> ?count_only     exit   then
                here 1+ " -f" caps-comp 0=              \ fast output
                if      drop on> ?noslow         exit   then
                >in ! ;

: get-global    ( -- )
                set_console
                ?in-empty               \ if nothing following command
                if      ." Global search? (-g\directory) ->" query cr
                        ?esc_bye
                        do_prompt on
                then
                >in @ bl word 1+ " -g" caps-comp
                if      >in !
                        restore_console         \ restore current output
                        EXIT                    \ ***** EXITS HERE *****
                then    drop
                on> ?global
                here count 2 /string dup
                if      2dup startdir place
                else    " \" startdir place
                then    2drop
        do_prompt @ 0=
        if      ." In " startdir count type ."  and lower directories, in "
                ?in-empty                       \ if nothing following
                if      " *.*" ">$ $>tib        \ default to "*.*",
                then                            \ ALL files
                >in @
                begin   bl word dup c@
                while   count type space
                repeat  drop >in !
        then    restore_console ;               \ restore current output

: get-1word     ( -- a1 )
                tib #tib @ >in @ /string tuck bl skip nip - >in +!
                                \ skip leading blanks before first word
                tib >in @ + c@  \ get delimiter character
                dup '0' '9' between over upc    \ numeric or
                'A' 'Z' between or              \ alphabetic, then
                if      drop            \ discard,
                        >in decr        \ backup and
                        $20 word        \ use blank for delimiter
                else                    \ if non alphabetic, then
                        >in incr        \ bump past the delimiter
                        word            \ get delimited string
                        >in incr
                then    ;

: get-string    ( | string -- )         \ get the search string
                set_console
                do_prompt off
                ?in-empty               \ if nothing following command
                if      ." String to LOOK for (no quotes) ->" query cr
                        ?esc_bye
                        do_prompt on
                        0  word
                else    get-1word
                then    count lookmax min slook.buf place
                ." Looking for " '"' emit slook.buf count type '"' emit
                space
                slook.buf c@ 0=
                if      ."  No search string specified"
                        ABORT
                then    restore_console ;       \ restore current output

: .info         ( -- )
           ."  Tom's LOOKup utility V1.4 03/11/94   ESC=cancel,  SPACE=pause search           "
        cr ."  Usage: LOOK [-? -s -c -f] " '"' emit
                          ." string" '"' emit ."  [-g<starting_dir>] [file_spec(s)..] <Enter> "
        cr ."   -?   : Display help information.                                              "
        cr ."   -s   : Sensitive to upper and lower case letters.                             "
        cr ."   -c   : Count and list only the names of files containing string.              "
        cr ."   -f   : Use FAST output, no pause for readability.                             "
        cr ."   -g   : Perform a global search of all directories at or below <starting_dir>. "
        cr ."   -g.  : Search starting at the the current directory and all below.            "
        cr ."   -g.. : Search starting at the directory above and all below.                  "
        cr at? black >bg ltgray >fg cols sp>col at ;

: .info2        ( -- )
        cr ."   The string being searched for can be either a single word without the quote   "
        cr ."   characters, or it can be any "
           '"' emit ." dos allowed string"
           '"' emit ." delimited by any two non-   "
        cr ."   alphabetic dos allowed characters.  Dos doesn't allow the use of the pipe     "
        cr ."   characters  >  or  |  in a dos commandline, as they have special meaning.     "
        cr ;

: flook         ( search_string file_specs --- ) \ Search files for string
                DECIMAL                 \ always select decimal
                CAPS ON                 \ ignore cAsE
                ?DS: SSEG !             \ init search segment
                DOSIO_INIT              \ init EMIT, TYPE & SPACES
                $FFF0 SET_MEMORY        \ default to 64k code space
                DOS_TO_TIB              \ move command tail to TIB
                ?in-empty               \ if nothing following command
                if      blue   >bg
                        yellow >fg
                        .info
                then
                maxfiles =: maxdir      \ up to "maxfiles" directory entries
                dirinit                 \ initialize directory words
                diralloc                \ allocate directory name space
                dirseg
[long]  if      32000 =: iblen          \ make read buffer larger
                lineread_init           \ initialize fast file reader
                off> occur_srch         \ reset the occurance counter
                ?vmode 7 =              \ setup for MONOCHROME or COLOR
                if      $B000           \ The SPINNER needs VIDEO-SEG
                else    $B800           \ to be set properly!
                then    video-seg !
                get-options             \ check for options
                get-string              \ get search text
                get-global              \ search all directories?
                ?global 0= do_prompt @ or
                if      get-filespecs   \ get the file specifications
                then
                set_console
                cr
                ." ** ESC = abort search ** SPACE = pause search ** "
                restore_console
                time-reset
                searchallof             \ search everything
                                        \ then report summary of search
                cr files_srch 1 u,.r     ."  Files searched; "
                   bytes_srch 2@ 1 ud,.r ."  Total bytes searched; "
                cr lines_srch 2@ 1 ud,.r ."  Total lines searched; "
                   occur_srch 1 u,.r     ."  Occurances found;"
                cr  dirs_srch 1 u,.r     ."  Directories searched; "
                   <.elapsed>            ."  Search time."
                dirrelease              \ release directory name space
        else    cr ." Not enough memory"
        then    ?out_redirect
                if      cr
                then    ;

}

