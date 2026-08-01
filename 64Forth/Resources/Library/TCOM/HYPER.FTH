\\ HYPER.FTH    Build an index of hyper text links      by Tom Zimmer

 03/03/94 13:59 tjz
        Updated to include new features for help, searching and
        displaying indexes.  You can also specify the name of the index
        file to search or build.

{

REQUIRE allspecs.fth      \ Load a needed utility
 36 array slook.buf
128 array joined$
142 array exclude$
  0 value exclude_len
  0 value ?blockon
  0 value ?quiet

defer donfile           \ A function to do on all specified files

0 value ?escval

: ?ESC          ( -- f1 )
                ?escval ?dup ?exit
                key?
                if      key 27 = dup !> ?escval
                else    false
                then    ;

handle indhndl

: search_1file  ( n1 -- )
                >fadr dir>pad
                2dup swap 1- c!                 \ lay in count
                over 1- over 1+ exclude$ exclude_len search nip
                if      2drop EXIT              \ leave if excluded file
                then    >r
                here indhndl $>handle
                indhndl >pathend
                dup indhndl 1+ - r@ + indhndl c!
                r> cmove
                indhndl count + off
                indhndl hopen 0=
                indhndl save!> seqhandle
                ibreset
                if      donfile
                then
                indhndl hclose drop
                restore> seqhandle ;

: $fallof        ( addr-offile_spec --- )
                                        \ Do something to all files
                                        \ matching file_specs.
                dirseg 0=
                if drop exit then
                dup count here c! here count cmove
                                        \ need spec at HERE also
                $getdir                 \ and read the directory files.
                #fls
                if      #fls 0
                        ?do     i >fadr 1+ c@l '.' <>
                                if      i search_1file
                                then    ?esc ?leave
                        loop
                then    ;

handle indexhndl
handle cfghndl
0 value ?exp_tabs
0 value after
0 value before
0 value stopper
0 value fstime
0 value ?global
0 value ?keeppath
2variable thisline
create crlf$ $0D c, $0A c,

: write.filename ( -- )
                fstime ?exit    \ put filename in index file
                " ù" indexhndl hwrite drop
                ?global ?keeppath or
                if      indhndl count     indexhndl hwrite drop
                else    indhndl >pathend" indexhndl hwrite drop
                then
                crlf$ 2 indexhndl hwrite drop
                on> fstime ;

: write.onename ( a1 n1 -- )
                write.filename
                indexhndl hwrite drop           \ write to file
                loadline @                      \ line where found,
                0 <# $0A hold $0D hold          \ end line with CRLF
                #S                              \ preceeded by the number
                bl hold #>                      \ preceeded by a blank
                indexhndl hwrite drop ;         \ write it too.

: skip_1word    ( a1 n1 -- a2 n2 )      \ skip one word through string
                begin   2dup bl scan    \ find a blank
                        bl skip         \ and skip it
                        dup             \ any text left
                while   2swap 2drop
                repeat  2drop  ;        \ if any text left, then

: ?word.ending  ( -- )  \ find a word ending with char in slook.buf
                thisline 2@ over c@ bl =        \ mustn't start with a blank
        if      2drop
        else    bl skip                         \ skip leading spaces
                2dup slook.buf 1+ c@ scan dup   \ did we find delimit char
                if      over 1+ c@ bl =         \ does a blank follow char?
                                                \ if so then ok, else not
                   if   nip -                   \ parse word before
                        skip_1word dup          \ if any text left, then
                        if      write.onename   \ write name to index
                        else    2drop
                        then
                   else 2drop 2drop
                   then
                else    2drop 2drop             \ discard if not found
                then

        then ;

: write.1cname  ( -- )
                thisline 2@ bl skip     \ skip leading blanks
                2dup '(' scan nip -     \ up to "("
                begin   2dup  bl scan dup       \ any blanks?
                while   2swap 2drop
                        bl skip         \ then skip them
                repeat  2drop
                write.onename   ;       \ and write one index name

: ?word.C       ( -- )  \ find a "C" function name
                thisline 2@ '(' scan dup        \ if we find a (
        if      2dup ';' scan nip >r            \ and
                     '{' scan nip r> >=         \ if { before ; or neither
                                                \ is found, then
                if      write.1cname
                then
        else    2drop
        then    ;

: ?word.prev    ( -- )  \ find occurances of slook.buf string and put word
                        \ previous to string in index file with line number.
                slook.buf count thisline 2@ search nip
                if      thisline 2@ bl skip     \ skip those blanks
                        2dup bl scan nip -      \ addr and len of name
                        write.onename           \ and write one index name
                then ;

: ?word.after   ( -- )  \ find occurances of slook.buf string and put word
                        \ following string in index file with line number.
                slook.buf count thisline 2@
                2dup stopper scan nip -         \ stop at stop char
                begin   4dup search             \ while found
        [long]  while   /string                 \ strip preceeding text
                        over 1- dup c@ bl =     \ preceed with BL
                        swap outbuf = or >r     \ or at line start
                        slook.buf c@ /string    \ skip search string + leadin
                        bl skip dup r> and      \ skip those blanks
                                                \ must have text left
                    if                          \ it anything left
                        2dup                    \ -- addr & len of string
                                                \ then get word following
                        2dup bl scan nip -      \ addr and len of name
                        write.onename           \ and write one index name
                    then
                repeat  drop 2drop 2drop ;

: ?word.stline  ( -- )  \ find occurance of slook.buf string at line start
                        \ put following string in index file.
                thisline 2@ 2dup bl scan nip - dup
        [long]  if      slook.buf count rot max compare 0=
                        if      thisline 2@ bl scan     \ find a blank
                                bl skip dup             \ skip those blanks
                                if                      \ if anything left
                                        2dup bl scan nip -  \ word following
                                        write.onename   \ write 1 index name
                                else    2drop
                                then
                        then
                else    2drop
                then ;

0 value pwlen           \ parse word length

: ?word.parse   ( -- )  \ parse out a word by "string ,," and two delimiters
                slook.buf count 2dup bl scan 2dup drop 1+ >r nip -
                dup !> pwlen
                thisline 2@
                2dup stopper scan nip -         \ stop at stop char
                begin   4dup search             \ while found
        [long]  while   /string                 \ strip preceeding text
                        over 1- dup c@ bl =     \ preceed with BL
                        swap outbuf = or >r     \ or at line start
                        pwlen /string           \ skip search string + leadin
                        dup r> and              \ must have text left
                    if                          \ it anything left
                        r@ c@ scan 1 /string bl skip
                        2dup r@ 1+ c@ scan nip - -trailing dup
                        if  2dup                \ -- addr & len of string
                                                \ then get word following
                            2dup bl scan nip -  \ addr and len of name
                            write.onename       \ and write one index name
                        then
                    then
                repeat  drop 2drop 2drop r>drop ;

: search.word   ( n1 -- )
                0max 5 min exec:
                ?word.after             \ 0
                ?word.ending            \ 1
                ?word.prev              \ 2
                ?word.C                 \ 3
                ?word.stline            \ 4
                ?word.parse             \ 5
                ;

                2variable curspec
 32             constant b/tbl
 64             constant maxtbl
  0             value    tblcnt
132             array fl$
b/tbl maxtbl *  array wtbl

: search.words  ( -- )
                wtbl b/tbl maxtbl * bounds
                do      i 1+ c@ 0= ?leave
                        i 1+ count slook.buf place
                        i c@ search.word
         b/tbl +loop    ;


: nfl$          ( -- a1 )
                curspec 2@ bl skip              \ skip blanks
                2dup bl scan                    \ find next blank
                2dup curspec 2!                 \ save for next try
                nip - pad place                 \ put it in pad
                pad ;                           \ ( -- pad )    return pad

: 0fl$          ( -- a1 )
                fl$ count curspec 2!            \ reset to spec's start
                nfl$ ;                          \ next spec

: ilineread     ( -- a1 )               \ index line read, with tab expand
                lineread                        \ read a line from file
                ?exp_tabs 0= ?exit              \ leave if not expanding tabs
                dup count                       \ through whole line
                begin   $09 scan dup            \ look for next tab char
                while   over bl swap c!         \ change tab to blank
                repeat  2drop ;

: next-cmd$     ( a1 n1 -- f1 )         \ find next matching string line
                                        \ f1 = true if match
                begin   2dup
                        ilineread crlf>bl's
                        count bl skip 2dup              \ skip leading spcs
                        bl scan nip -                   \ parse first word
                        rot max caps-comp 0=            \ compare strings =
                        outbuf c@ 0= or                 \ or empty lineread
                        outbuf c@ ';' =                 \ test for file stop
                        if      true or                 \ say we are done
                                outbuf off              \ clear buffer
                        then
                until   2drop outbuf c@ ;               \ true if matched

: find-cmd$     ( a1 n1 -- f1 )         \ find a line starting with string
                                        \ a1,n1. f1 = true if matched
                ibreset
                0.0 seqhandle movepointer
                next-cmd$ ;

: after-cmd     ( -- a1 n1 )            \ return a1,n1 string after command
                outbuf count
                bl skip bl scan         \ past first word
                bl skip ;               \ and past any following spcs

: read_stopper  ( -- )                  \ STOPAT \
                " STOPAT" find-cmd$
                if      after-cmd       \ -- a1 n1
                        if      c@ =: stopper
                        else    drop
                        then
                then    ;

: read_before   ( -- )                  \ BEFORE 64
                " BEFORE" find-cmd$
                if      after-cmd       \ -- a1 n1
                        "c$             \ -- a1         counted string
                        number?         \ -- d1 f1
                        if      over 250 min =: before
                        then    2drop
                then    ;

: read_after    ( -- )                  \ AFTER 35
                " AFTER" find-cmd$
                if      after-cmd       \ -- a1 n1
                        "c$             \ -- a1         counted string
                        number?         \ -- d1 f1
                        2drop 128 min =: after
                then    ;

: read_tabx     ( -- )                  \ TABX ON
                " TABX" find-cmd$
                if      after-cmd               \ -- a1 n1
                        "c$   1+ dup            \ -- a1         counted string
                        " ON"  caps-comp 0=     \ if "ON" then expand tabs
                        if      drop
                                on>  ?exp_tabs exit
                        then
                        " OFF" caps-comp 0=     \ if "OFF" then don't expand
                        if      off> ?exp_tabs exit
                        then
                then    ;

: 1word         ( a1 n1 -- a2 n2 a3 n3 )        \ parse out a word
                bl skip 2dup bl scan 2dup 2>r nip - 2r> 2swap ;

16 array c$

: "c$           ( a1 n1 -- a2 )         \ convert to a counted short string
                15 min c$ place c$ ;

\ : ""->$         ( a1 n1 -- a2 )         \ convert addr & len to counted $
\                 over 1- c! 1- ;

: nextword      ( a1 n1 -- a2 n2 )      \ skip from current word to next
                bl scan bl skip ;

: read_specs    ( -- )  \ SPECS *.SEQ;*.TXT;*.ASM
                " SPECS" find-cmd$
                if      after-cmd
                        2dup bl scan nip -      \ get line upto a blank
                        132 min fl$ place       \ move in file search string
                        fl$ count
                        begin   ';' scan dup            \ scan for ';'
                        while   over bl swap c!         \ change to blank
                        repeat  2drop
                        fl$ count curspec 2!            \ place to start
                then    ;

: read_exclude  ( -- )  \ EXCLUDE file1 file2 file3 file4 ; comment
                " EXCLUDE" find-cmd$
                exclude_len 128 < and           \ and not full
        [long]  if      after-cmd
                        2dup bl scan nip -      \ get line upto a blank
                        -trailing               \ remove trailing blanks
                        begin   2dup ';' scan 2dup 2>r nip - dup
                        while   12 min dup>r
                                exclude$ exclude_len + place
                                r> 1+ +!> exclude_len
                                2r> 1 /string
                        repeat  2r> 2drop 2drop
                then    ;

: read_global   ( -- )                  \ GLOBAL \
                " GLOBAL" find-cmd$
                if      after-cmd
                        2dup bl scan nip -      \ get line upto a blank
                        63 min startdir place   \ move in file search string
                        on> ?global             \ do a global edit
                then    ;

: get1cmd       ( -- )
                after-cmd                       \ -- a1 n1
                over c@ '0' - 0 max 9 min       \ type 0 to 9
                tblcnt b/tbl * wtbl + c!        \ set search type
                '"' scan 1 /string              \ skip to search $
                2dup 1 /string                  \ allow " to follow as legal
                '"' scan bl scan nip - 1- 0max  \ get " delim $
                b/tbl 2- min                    \ limit to avail
                tblcnt b/tbl * wtbl + 1+ place  \ move $ into buf
                incr> tblcnt ;

: read_cmds     ( -- )                  \ TYPE 0 "CONSTANT "
                " TYPE" find-cmd$
                if      get1cmd
                        begin   " TYPE" next-cmd$
                                tblcnt maxtbl < and
                        while   get1cmd
                        repeat
                then    ;

: read_blockfile ( -- )                  \ BLOCKFILE ON or BLOCKFILE OFF
                " BLOCKFILE" find-cmd$
                if      after-cmd
                        drop 1+ c@ upc 'N' =    \ second letter is N of "oN"
                        if      64 !> line_limit
                                on> ?blockon
                        then
                        after-cmd       \ -- a1 n1
                        "c$             \ -- a1         counted string
                        number? nip     \ -- n1 f1
                        if      dup 10 max 254 min !> line_limit
                                on> ?blockon
                        then    drop
                then    ;

: read_keeppath  ( -- )                  \ KEEPPATH ON  or  KEEPPATH OFF
                " KEEPPATH" find-cmd$
                if      after-cmd
                        drop 1+ c@ upc 'N' =    \ second letter is N of "oN"
                        !> ?keeppath
                then    ;

: cfg_open?     ( -- f1 )       \ open and return true, else couldn't
                " HYPER.CFG" ">$ cfghndl $>handle      \ init filename
                cfghndl hopen           \ could we open HYPER.CFG?
        [long]  if      " INDEX.CFG" ">$ cfghndl $>handle
                cfghndl hopen           \ else could we open INDEX.CFG?
                if      " NEWZ.CFG" ">$ cfghndl $>handle
                                        \ if that fails, try NEWZ.CFG
                cfghndl hopen
                if      " \NEWZ.CFG" ">$ cfghndl $>handle
                                        \ finally try root
                        cfghndl hopen 0=
                else    true
                then
                else    true
                then
                else    true
                then    ;

: cfg-init      ( -- )
                off> after                      \ start looking at 0
                250 =: before                   \ look up to char 250
                '\' =: stopper                  \ stop character=\
                off> tblcnt                     \ command count=0
                wtbl b/tbl maxtbl * erase       \ initialize table
                off> ?global                    \ no global searching
                off> exclude_len                \ clear exclude list
                " \" startdir place ;           \ default to whole disk

: read_cfg      ( -- )          \ read the hypertext word table for
                                \ building the index file.
                cfg-init
                cfg_open?
                if      cfghndl save!> seqhandle
                        read_specs              \ read file specifications
                        read_global             \ global hyperindex directory
                        read_after              \ read where to start in line
                        read_before             \ read before limit length
                        read_stopper            \ read stop char
                        read_tabx               \ file contains tabs
                        read_cmds               \ read compiler commands
                        read_blockfile          \ block file support
                        read_exclude            \ excluded file list
                        read_keeppath           \ should path be in index
                        restore> seqhandle
                        cfghndl hclose drop
                else    0 wtbl c!               \ type is zero
                        " ø" wtbl 1+ place      \ string is "ø"
                then    ;

: ind.1line     ( -- f1 )
                outbuf count
                before min after /string
                2dup stopper scan nip - tuck thisline 2!
                0>
                outbuf crlf>bl's 1+ c@ stopper <> and
                if      search.words
                then    ;

: index.file    ( --- )
                save> attrib
                blue >bg yellow >fg
                12 10 at seqhandle count type 70 #out @ - 0max spaces
                restore> attrib
                IBRESET
                0.0 seqhandle movepointer
                off> loadline
                off> fstime
                65530 1
                do      ilineread c@ 0= ?leave
                        ind.1line
                        i 63 and 0=
                        if      ?esc ?leave
                        then
                loop    ;

: joindir       ( dir spec -- filespec )        \ join dir & spec to make
                                                \ a complete filespec
                swap count joined$ place        \ lay in dir
                joined$ count + 1- c@ '\' <>
                if      " \" joined$ +place
                then
                count over c@ '\' =
                if      1 /string
                then    joined$ +place
                joined$ ;

: global_search ( -- )
                getdirs
                begin   nextdir dup c@
                while   dup 0fl$ joindir $fallof
                        begin   dup nfl$ dup c@
                                ?esc 0= and     \ leave if ESC pressed
                        while   joindir $fallof
                        repeat  2drop
                repeat  drop    ;

: bindex        ( --- )
                savecursor
                savescr cursor-off
                bl word c@
                if      here             indexhndl $>handle
                        indexhndl count '.' scan nip 0=     \ any extention?
                        if      " NDX" ">$ indexhndl $>ext  \ then add one
                        then
                else    " HYPER.NDX" ">$ indexhndl $>handle
                then
                save> attrib
                white >fg blue >bg
                10 6 70 16 box&fill bcr space
                white >fg cyan >bg
                ."  Building hypertext index file: "
                indexhndl ?UPPERCASE >pathend" type
                69 #out @ - 0max spaces
                bcr bcr bcr bcr
                blue >bg space   \ need a normal space here
                red  >bg
                ."  Press the ESCape key to cancel this index build "
                69 #out @ - 0max spaces bcr bcr
                blue   >bg
                ltgray >fg
                ."   HYPER was written by Tom Zimmer using the TCOM Compiler."
                bcr
                ."   This is version: 2.1,  dated: 03/25/94"
                yellow >fg cyan >bg
                12 6 at
                ."      HYPER the Hypertext Index Compiler and Scanner      "
                restore> attrib
                " *.TXT" fl$ place
                read_cfg
                indexhndl hcreate 0=
[long]  if      ['] index.file is donfile
                ?global
                if      global_search
                else    0fl$    $fallof
                        begin   nfl$ dup c@
                                ?esc 0= and     \ leave if ESC pressed
                        while   $fallof
                        repeat  drop
                then
                crlf$ 2 indexhndl hwrite drop
                indexhndl hclose drop
                ?esc 0= if 1 seconds then
        then    restscr restcursor
        ?esc abort" Index Build only partially completed before user abort!"
        ." Index compile: " indexhndl count type ."  complete." ;


0 value itcnt

: ?keypauser    ( -- )
                incr> itcnt
                itcnt 3 and 0=  \ only possible to pause every 4th time
                if      ?keypause
                then    ;

64 array bfword         \ search word
64 array curbfile       \ current index file name

                \ prepend the path in hndl to name at a1
: prepend.apath ( a1 hndl --- a1 )
                dup c@ >r                       \ save length of handle
                swap                            \ bring name to top
                dup  2+ c@ ':' =                \ do we already have a drive?
                over 1+ c@ '\' = or             \ or a path specified?
                r> 0= or 0=                     \ or handle is empty
                                                \ skip prepend if we do
             if dup c@ >r >r                    \ save name location & length
                r@ 1+ over c@ r@ + 1+ r@ c@ cmove> \ make room for path
                dup r@ over c@ 1+ cmove         \ move in path
                r> r> over c+!                  \ correct count
             then  nip ;

create "file_buf 64 allot
create "path_buf 64 allot

: path_only     ( a1 -- a2 )    \ remove a trailing filename from path
                dup count rot >pathend" nip - "path_buf place
                "path_buf ;

: path1         ( -- a1 )
                0fl$ path_only ;

: npath         ( -- a1 f1 )
                nfl$ path_only dup c@ 0= ;

: "file         ( a1 n1 -- f1 )   \ f1 = true if failed to open
                2dup 2>r "file_buf place
                "file_buf path1 prepend.apath
                $hopen  dup
                if      0=
                        begin   2r@ "file_buf place
                                npath   0=
                                if      "file_buf swap prepend.apath
                                        $hopen 0=
                                else    drop 0= true
                                then
                        until
                then    dup
                        \ if we can't open, then replace original file
                        \ in case we are going to be creating the file
                if      drop
                        2r@ "file_buf place
                        "file_buf path1 prepend.apath
                        $hopen
                then    2r> 2drop ibreset ;

: bfinit        ( -<<filename> word>- )
                " HYPER.NDX" ">$ indexhndl $>handle
                bl word c@ 0= abort" No search word specified"
                here count 63 min bfword place
                bl word c@
                if      bfword     indexhndl $>handle
                        indexhndl count '.' scan nip 0=     \ any extention?
                        if      " NDX" ">$ indexhndl $>ext  \ then add one
                        then    here count bfword place
                then
                read_cfg
                indexhndl count "hopen          \ if can't open, error
                abort" Couldn't open the hyper index file!"
                loadline off ;

: bshowinit     ( -- )
                " HYPER.NDX" ">$ indexhndl $>handle
                bl word c@
                if      here indexhndl $>handle
                then
                read_cfg
                indexhndl count "hopen
                abort" Couldn't open the hyper index file!" ;

0 value found_cnt
0 value total_cnt
0 value total_files

: .lineout      ( -- )          \ display a result line
                outbuf c@ 4 < ?exit
                cr
                outbuf crlf>bl's count -trailing
                2dup bl scan 2dup 2>r nip - 20 over - 1 max spaces type
                2r> bl skip
                ?blockon 0=
                if      7 over - 1 max spaces type
                else    pad 30 blank
                        pad place pad number? 2drop 16 /mod
                        hex     2dup 7 .r 3 .r
                        decimal      9 .r 3 .r
                then    2 spaces curbfile count 16 over - 0max spaces type
                incr> found_cnt ;

: .bheader      ( -- )
                ?quiet ?exit
                ?blockon
                if      cr
        ."          Word       HEX SCR Ln  DEC SCR Ln        File"
                        cr
        ."  ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ"
                else
        ."          Word           Line       File"
                        cr
        ."  ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ"
                then    ;

: .bfooter      ( -- )
                cr
                ?quiet ?exit
                ." Found: " found_cnt u. ." matching entries out of "
                total_cnt u. ." index entries in " total_files u. ." files."
                cr ;

M: +total_cnt?  ( -- )
                outbuf c@ 4 >
                if      incr> total_cnt
                then    ;

: _bfind        ( a1 -- )
                >r      \ save test and display routine on return stack
                .bheader
                begin   lineread c@
        [long]  while   outbuf 1+ c@ 'ù' =            \ 249 decimal
                        if      outbuf crlf>bl's count 1 /string -trailing
                                curbfile place
                                incr> total_files
                        else    r@ execute
                                +total_cnt?
                        then    ?keypauser
                repeat  seqhandle hclose drop
                .bfooter r>drop ;

: word_match?   ( -- )
                outbuf count 2dup bl scan nip -
                bfword count rot max caps-comp 0=
                if      .lineout
                then    ;

: start_match?  ( -- )
                outbuf 1+ bfword count caps-comp 0=
                if      .lineout
                then    ;

: in_match?     ( -- )
                bfword count
                outbuf count 2dup bl scan nip - search nip
                if      .lineout
                then    ;

: bfind     ( -<<filename> word>- )       bfinit    ['] word_match?  _bfind ;
: bfindst   ( -<<filename> word>- )       bfinit    ['] start_match? _bfind ;
: bfindin   ( -<<filename> substring>- )  bfinit    ['] in_match?    _bfind ;
: bshow     ( -<filename>- )              bshowinit ['] .lineout     _bfind ;
: bcount    ( -<filename>- )              bshowinit ['] noop         _bfind ;

-1 value curbline

: browse_file   ( -- )
                cr savescr
                " ZLIST "       pad  place      \ start with program name
                curbfile count  pad +place      \ append filename
                "  /LINE "      pad +place      \ append line command
                curbline 4 - 1 max
                0 <# #s #>      pad +place      \ finally line number
                pad $sys drop                   \ shell to program
                restscr ;

: _view_match?  ( f1 -- )
[long] if       pad 30 blank
                incr> found_cnt
                outbuf crlf>bl's count -trailing bl scan bl skip pad place
                pad number? 2drop !> curbline
                seqhandle curpointer inlength @ 0 d- 2>r
                indexhndl save!> seqhandle      \ save current file handle
                curbfile count "file
          if    cr ." Couldn't open source file: " seqhandle count type cr
[long]    else  cr ." File: " seqhandle count type cr
                ?blockon
    if ." ÄÄ BLK Line ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ" cr
    then    loadline off
                ?blockon
                if      curbline 16 / 16 * 0
                        ?do     lineread drop
                        loop    16
                else    curbline 4 - 0max 0
                        ?do     lineread drop
                        loop    10
                then    0
                do      ?blockon
                        if      loadline @ 0 16 um/mod
                                curbline 1- 16 mod i =
                                if ." Í" 4 else 6 then
                                hex u.r 2 .r decimal ."  ³ "
                        else    i 3 = if ." Í" 5 else 7 then
                                loadline @ 1+ swap u.r space
                        then
                        lineread crlf>bl's count -trailing type cr
                loop    cr seqhandle hclose drop
          then  ibreset
                restore> seqhandle              \ back to original file
                2r> seqhandle movepointer
        ."  Enter=Browse file, SPACE=Skip to Next occurance, ESC=Quit "
                key
                case    27 of seqhandle endfile ibreset endof
                        upc
                        13 of browse_file               endof
                              drop
                endcase cr
      then      ;

: view_match?   ( -- )
                outbuf count 2dup bl scan nip -
                bfword count rot max caps-comp 0=
                outbuf c@ 3 > and
                _view_match? ;

: viewin_match? ( -- )
                bfword count
                outbuf count 2dup bl scan nip - search nip
                outbuf c@ 3 > and
                _view_match? ;

: viewstart_match?  ( -- )
                outbuf 1+ bfword count caps-comp 0=
                outbuf c@ 3 > and
                _view_match? ;

: bview         ( -<word>- )
                on> ?quiet
                bfinit ['] view_match? _bfind
                found_cnt 0= abort" Word was not found!" ;

: bviewin       ( -<string>- )
                on> ?quiet
                bfinit ['] viewin_match? _bfind
                found_cnt 0= abort" Word was not found!" ;

: bviewst       ( -<string>- )
                on> ?quiet
                bfinit ['] viewstart_match? _bfind
                found_cnt 0= abort" Word was not found!" ;

: .ihelp        ( -- )          \ show INDEX help
   ."  HYPER V2.3   05/10/94   ESC=cancel, SPACE=pause"
cr ."  Usage: HYPER                   Display this help information."
cr ."         HYPER -B                Build HYPER.NDX using HYPER.CFG."
cr ."         HYPER -F  word          Find 'word' references in HYPER.NDX"
cr ."         HYPER -FI substring     Find 'substring' references in HYPER.NDX"
cr ."         HYPER -FS startstring   Find 'startstring' references in HYPER.NDX"
cr ."         HYPER -S                Show all entries in HYPER.NDX."
cr ."         HYPER -V  word          View the source files for word."
cr ."         HYPER -VI substring     View the source files for substring."
cr ."         HYPER -VS startstring   View the source files for startstring."
cr
cr ."   A filename can also follow any of the above commands (preceeding the word or"
cr ."  string) in the form:  `HYPER -F filename word'   to specify the name of the"
cr ."  hypertext index file to use or build."
cr
cr ."   HYPER is a utility for creating and searching hypertext index files."
cr ."  This program is particularly useful for maintaining various types of program"
cr ."  source files written in ASSEMBLER or FORTH.  Another utility program called"
cr ."  CTAGSP.EXE can be used to create index files from C language source files."
cr ."  HYPER is written in Forth by Tom Zimmer. CTAGSP is written in C by Jerry"
cr ."  Modrow and friends."
cr
rows 30 <
if      cr ."  Press SPACE for more, or ESC to quit"
        key 27 = ?exit
        cls
else    cr
then
cr ." HYPER.COM is a public domain example program by Tom Zimmer."
cr
cr ." HYPER was written in Forth and compiled with the TCOM Target Compiler."
cr
cr ." If you would like to have the source for HYPER and other TCOM example"
cr ." programs, send a check for US$60 to:"
cr
cr ." Address: Tom Zimmer            Phone: (408) 263-8859 evenings (7pm-9pm pst)"
cr ."          292 Falcato Drive            (415) 327-8800 days     (9am-5pm pst)"
cr ."          Milpitas, Ca. 95035   Outside US orders add 20 dollars."
cr
cr ." You will receive the TCOM compiler, its source, the source for HYPER and"
cr ." the source for a many other TCOM example programs on 3.5 inch 1.44 meg disks."
cr
cr ." Example programs include:
cr
cr ."   ZLIST  file viewer       SZ    small editor      GCLOCK Graphics clock"
cr ."   LOOK   file searcher     ZTREE disk space util   TIMEIT elapse timer"
cr ."   MANGEN Mandelbrot draw   TETRA a game            VMODE  video mode set"
cr
cr ." and several others, plus F-PC, the FULL Forth system on which TCOM is built."
cr ." This package totals almost five megabytes installed, with full source."
cr ;

: /-test        ( -<name>- )    \ define a word that tests commandline options
                ( -- f1 )       \ test string a1, n1 commandline option
                                \ and return boolean flag f1 true if found
                create
                does>   >in @ >r
                        here 33 blank           \ prefill with blanks
                        bl word 2+ swap count caps-comp 0=      \ check word
                        here 1+ c@ dup '/' = swap '-' = or and  \  '/' or '-'
                        if      true
                        else    r@ >in ! false
                        then    r>drop ;

/-test ?/blk    ," BLK"  ( -- f1 )  \ /Block file output for find
/-test ?/build  ," B"    ( -- f1 )  \ /Build the index file
/-test ?/find   ," F"    ( -- f1 )  \ /Find a word in the index file
/-test ?/findin ," FI"   ( -- f1 )  \ /Find a substring in the index file
/-test ?/findst ," FS"   ( -- f1 )  \ /Find a startstring in the index file
/-test ?/show   ," S"    ( -- f1 )  \ /Show words in index file
/-test ?/count  ," C"    ( -- f1 )  \ /Count words in index file
/-test ?/quiet  ," Q"    ( -- f1 )  \ /Quiet output, no header is displayed
/-test ?/view   ," V"    ( -- f1 )  \ /View sources for a word
/-test ?/viewin ," VI"   ( -- f1 )  \ /View sources for a substring
/-test ?/viewst ," VS"   ( -- f1 )  \ /View sources for a startstring

: main          ( -- )
                DECIMAL                         \ always select decimal
                INIT-CURSOR                     \ get intial cursor shape
                50 FUDGE !                      \ init MS timer, GUESS!!
                CAPS ON                         \ ignore cAsE
                ?DS: SSEG !                     \ init search segment
                VIDEOIO_INIT                    \ init EMIT, TYPE & SPACES
                FAST                            \ DIRECT video output
                $FFF0 SET_MEMORY                \ default to 64k code space
                DOS_TO_TIB                      \ move command tail to TIB
                COMSPEC_INIT                    \ init command specification
                LINEREAD_INIT           \ initialize the LINEREAD system.
                dirinit                 \ initialize directory words
                500 !> maxdir           \ 500 names per directory
                diralloc                \ allocate directory name space
                dirseg
[long]  if      off> ?escval            \ clear aborted flag
                ?/blk    if on> ?blockon then   \ for block files
                ?/quiet  if on> ?quiet   then   \ don't show header or footer
                ?/findin if bfindin exit then
                ?/findst if bfindst exit then
                ?/find   if bfind   exit then
                ?/show   if bshow   exit then
                ?/count  if bcount  exit then
                ?/build  if bindex  exit then
                ?/viewin if bviewin exit then
                ?/viewst if bviewst exit then
                ?/view   if bview   exit then
                >in @ bl word c@
                if      >in ! bview
                else    drop .ihelp
                then
        else    cr ." Not enough memory"
        then    ;


