\\ ZIM.SEQ      A utility to squeeze text files         by Tom Zimmer

  This program compresses F-PC source and documentation files into a new
compressed format I call .ZIM.  I'm sure you can imagine where the name
came from, so we will move right along.

  .ZIM files use a token substitution scheme to reduce file size without
losing information.  Being inexperienced with compression technology,
allows me to use a compression scheme that others have probably already
tried and discarded. In an attempt to minimize complexity, I have chosen
to do all work on byte boundries (thus avoiding bit manipulation).  The
token assignments I use are taylored to my own style of programming, that
is I use a lot of white space in my files. If you use this compression
scheme on your own files, your compression ratios may not be as good.
Here then are the token assignments:

        0               escape sequence, see second table
        1-16            number of spaces
        17              substitute for CRLF
        18-127          110 token word substitutes as byte tokens
        128-255         not used, part of following word substitution
        32768-65000     word substitution as word tokens
        65001-65533     unassigned, not used
        65535           end of individual file marker
        65534           end of .ZIM file marker

        escape sequences following the zero (0) escape start code:

        1 n data        very long (>32) words
                        string "data" of count "n", not compressed.


{

\tcom   needs \tcom\tfileio.seq
\fpc    fload \tcom\fileio.seq          \ part of the tcom utilities
\fpc    ' ?cs: alias ?ds:

bhandle srchndl
bhandle sqzhndl
 handle tblhndl
 handle tmphndl
 handle z$$hndl

 128 constant #threads                  \ vocabulary hash threads
4096 constant sqzmax                    \ squeeze buffer max size
 sqzmax array sqzbuf                    \ the squeeze buffer
    256 array tokenbuf                  \ a place to hold the current word
    256 array namevoc1                  \ word list hash pointer tables
    256 array namevoc2
    256 array namevoc3
    256 array namevoc4
    256 array pathsave                  \ a place to save file spec path
      4 array datebuf                   \ a place to hold a binary file date
      4 array sizebuf                   \ a place to hold a file binary size
      4 array sqzlbuf
      0 value sqzoff
      0 value didword
      0 value sqzlen
      0 value nextoken
      0 value wordoff
      0 value wordoff1
      0 value wordoff2
      0 value wordoff3
      0 value wordoff4
      0 value tbank                     \ current vocabulary bank
      0 value linecnt                   \ lines processed count
      0 value wordtotal                 \ total wordds in table
      0 value sqzdone                   \ done squeezing a file
      0 value updated_words             \ words table has been updated

\tcom   0 value wordseg1                \ a place to save words found
\tcom   0 value wordseg2                \ a place to save words found
\tcom   0 value wordseg3                \ a place to save words found
\tcom   0 value wordseg4                \ a place to save words found
\tcom   0 value ptrseg
\fpc    65536. pointer wordseg1
\fpc    65536. pointer wordseg2
\fpc    65536. pointer wordseg3
\fpc    49152. pointer ptrseg

create cmpext ," ZIM"   \ compressed file .EXT
create tmpext ," Z$$"   \ temporary compressed file .EXT while deleting file

\fpc    false #if
\tcom   true  #if       \ **** load this segment if using TCOM ****

code hash       ( str-addr -- thread )
                mov ax, 1 [bx]          \ get first and second chars
                shl al, # 1             \ shift first char left one
                add al, ah              \ plus second char
                shl ax, # 1             \ the sum shifted left one again
                add al, 0 [bx]          \ plus count byte
                and ax, # #threads 1-
                shl ax, # 1
                mov bx, ax
                ret             end-code

code getfdt     ( handle# -- file-time file-date )
                                                \ handle# -> bx
                mov ah, # $057                  \ Function 57 -> ah
                mov al, # 0                     \ 0 -> al for "get"
                int $21                         \ gets the time & date
                dec si
                dec si
                mov 0 [si], cx                  \ the time to the stack
                mov bx, dx                      \ the date over it
                ret      end-code

code setfdt     ( file-time file-date handle# -- )
                                                \ handle# -> bx
                lodsw   mov dx, ax              \ get date to set
                lodsw   mov cx, ax              \ get time to set
                mov ah, # $057                  \ Function 57 -> ah
                mov al, # 1                     \ 0 -> al for "set"
                int $21                         \ sets the time & date
                load_bx                         \ reload BX with top of stack
                ret      end-code

: typel         ( seg off len -- )      \ a type long
                bounds
                ?do     dup i c@L emit
                loop    drop ;

: allocate      ( paragraphs -- segment )       \ allocate paragraphs of mem
                alloc 8 = abort" Out of memory!" nip ;

#else           \ ***** Load this segment if using F-PC *****

hidden also

' noop alias [long] immediate

code hash       ( str-addr -- thread )
                pop bx
                mov ax, 1 [bx]          \ get first and second chars
                shl al, # 1             \ shift first char left one
                add al, ah              \ plus second char
                shl ax, # 1             \ the sum shifted left one again
                add al, 0 [bx]          \ plus count byte
                and ax, # #threads 1-
                shl ax, # 1
                1push           end-code

code getfdt    ( handle# -- file-time file-date )
               pop bx                        \ handle# -> bx
               mov ah, # $057                \ Function 57 -> ah
               mov al, # 0                   \ 0 -> al for "get"
               int $21                       \ gets the time & date
               push cx                       \ the time to the stack
               push dx                       \ the date over it
               next     end-code

code setfdt     ( file-time file-date handle# -- )
                pop bx                          \ handle# -> bx
                pop dx                          \ get date to set
                pop cx                          \ get time to set
                mov ah, # $057                  \ Function 57 -> ah
                mov al, # 1                     \ 0 -> al for "set"
                int $21                         \ sets the time & date
                next     end-code

#then

: fgetdate      ( handle -- time date )         \ get the file data & time
                >hndle @ getfdt ;

: fsetdate      ( time date handle -- )         \ set the file date & time
                >hndle @ setfdt ;

: lplace        ( a1 len seg off -- )   \ place string from here to seg
                2>r ?ds: -rot 2r> rot >r 2dup r@ -rot c!L 1+ r> cmovel ;

: sqzemit       ( c1 -- )       \ write one char to squeezed output file
                pad c! pad 1 sqzhndl bwrite ;

: init_ptrlist  ( -- )          \ initialize the token pointer table
                off> nextoken
                wordoff1 4
                do      i ptrseg nextoken 2* !L         \ make a pointer
                        incr> nextoken                  \ bump token #
                        wordseg1 i c@L 5 +              \ cnt + pointer
               +loop    wordoff2 0= ?exit
                8192 !> nextoken
                wordoff2 4
                do      i ptrseg nextoken 2* !L         \ make a pointer
                        incr> nextoken                  \ bump token #
                        wordseg2 i c@L 5 +              \ cnt + pointer
               +loop    wordoff3 0= ?exit
                16384 !> nextoken
                wordoff3 4
                do      i ptrseg nextoken 2* !L         \ make a pointer
                        incr> nextoken                  \ bump token #
                        wordseg3 i c@L 5 +              \ cnt + pointer
               +loop
\tcom           24576 !> nextoken
\tcom           wordoff4 4
\tcom           do      i ptrseg nextoken 2* !L         \ make a pointer
\tcom                   incr> nextoken                  \ bump token #
\tcom                   wordseg4 i c@L 5 +              \ cnt + pointer
\tcom          +loop
                ;

}

  Token table file format:

        bytes           Contents
        ------------------------------------------------------------
        256     First vocabulary pointer list
          2     length of vocabulary word list
        ...     Data for first dictionary of vocabulary words

  ---------- optional additional word file contents -------------------

        256     Second vocabulary pointer list
          2     length of vocabulary word list
        ...     Data for second dictionary of vocabulary words
        256     Third vocabulary pointer list
          2     length of vocabulary word list
        ...     Data for third dictionary of vocabulary words


{

: %read_words   ( -- f1 )       \ f1=FALSE if read ok
                namevoc1 256 erase
                namevoc2 256 erase
                namevoc3 256 erase
                namevoc4 256 erase
                off> tbank                      \ reset token bank
                off> nextoken
                off> wordoff1
                off> wordoff2
                off> wordoff3
                off> wordoff4
                tblhndl hopen dup ?exit         \ try to open word table
        \
                namevoc1   256 tblhndl hread drop       \ read  voc pointers
                &> wordoff1  2 tblhndl hread drop       \ read  voc length
                0  wordoff1 tblhndl wordseg1 exhread    \ read  voc words
                wordoff1 - abort" Words read error"     \ check voc length
                wordoff1 !> wordoff
        \
                namevoc2   256 tblhndl hread 0= ?exit   \ read  voc pointers
                incr> tbank
                &> wordoff2  2 tblhndl hread drop       \ read  voc length
                0  wordoff2 tblhndl wordseg2 exhread    \ read  voc words
                wordoff2 - abort" Words read error"     \ check voc length
                wordoff2 !> wordoff
        \
                namevoc3   256 tblhndl hread 0= ?exit   \ read  voc pointers
                incr> tbank
                &> wordoff3  2 tblhndl hread drop       \ read  voc length
                0  wordoff3 tblhndl wordseg3 exhread    \ read  voc words
                wordoff3 - abort" Words read error"     \ check voc length
                wordoff3 !> wordoff
        \
\tcom           namevoc4   256 tblhndl hread 0= ?exit   \ read  voc pointers
\tcom           incr> tbank
\tcom           &> wordoff4  2 tblhndl hread drop       \ read  voc length
\tcom           0  wordoff4 tblhndl wordseg4 exhread    \ read  voc words
\tcom           wordoff4 - abort" Words read error"     \ check voc length
\tcom           wordoff4 !> wordoff
                ;

: read_words    ( -- f1 )       \ f1=FALSE if read ok
                %read_words dup ?exit
                init_ptrlist
                tblhndl hclose drop ;

: wordoff>wordoff ( -- )
                tbank 0=  if    wordoff !> wordoff1 then
                tbank 1 = if    wordoff !> wordoff2 then
                tbank 2 = if    wordoff !> wordoff3 then
                tbank 3 = if    wordoff !> wordoff4 then ;

: %write_words  ( -- )
                #out @
                if      cr
                then    ." Writing updated word table ."
                tblhndl hcreate abort" Failed to create ZIM.TBL file"
        \
                namevoc1    256 tblhndl hwrite drop
                &> wordoff1   2 tblhndl hwrite drop
                0 wordoff1 tblhndl wordseg1 exhwrite
                wordoff1 - abort" Error writting ZIM.TBL"
        \
                wordoff2 0= ?exit ." ."
                namevoc2    256 tblhndl hwrite drop
                &> wordoff2   2 tblhndl hwrite drop
                0 wordoff2 tblhndl wordseg2 exhwrite
                wordoff2 - abort" Error writting ZIM.TBL"
        \
                wordoff3 0= ?exit ." ."
                namevoc3    256 tblhndl hwrite drop
                &> wordoff3   2 tblhndl hwrite drop
                0 wordoff3 tblhndl wordseg3 exhwrite
                wordoff3 - abort" Error writting ZIM.TBL"
        \
\tcom           wordoff4 0= ?exit ." ."
\tcom           namevoc4    256 tblhndl hwrite drop
\tcom           &> wordoff4   2 tblhndl hwrite drop
\tcom           0 wordoff4 tblhndl wordseg4 exhwrite
\tcom           wordoff4 - abort" Error writting ZIM.TBL"
                ;

: write_words   ( -- )
                updated_words 0= ?exit
                wordoff>wordoff         \ update highest wordoffset value
                %write_words
                tblhndl hclose drop cr ;

: 1vocfind      ( hash voc seg -- <token> f1 )
                save!> sseg
                + @ ?dup
                if      begin   tokenbuf 2dup c@ 1+ comp
                                if      sseg @ swap 2- @L dup 0=
                                else    sseg @ swap 4 - @L
                                        true true
                                then
                        until
                else    false
                then    restore> sseg ;

: findtoken     ( -- <token> f1 )
                tokenbuf hash namevoc1 wordseg1 1vocfind ?dup ?exit
                tokenbuf hash namevoc2 wordseg2 1vocfind ?dup ?exit
                tokenbuf hash namevoc3 wordseg3 1vocfind
\tcom                                                    ?dup ?exit
\tcom           tokenbuf hash namevoc4 wordseg4 1vocfind
                ;

: sendtoken     ( n1 -- )
                dup 110 u<                      \ 128-(17+1) = 110
                if      18 + sqzemit            \      17+1  =  18
                else    $8000 or flip sp@ 2 sqzhndl bwrite drop
                then    ;

: addtoken1     ( -- )
                nextoken wordseg1 wordoff !L            \ install next token
                2 +!> wordoff                           \ bump over token num
                tokenbuf hash dup namevoc1 + @          \ old top name
                wordseg1 wordoff !L                     \ install in pointer
                2 +!> wordoff                           \ bump over pointer
                wordoff  swap namevoc1 + !              \ link to hash table
                tokenbuf count dup>r                    \ a1 n1
                wordseg1 wordoff  lplace                \ seg1
                r> 1+ +!> wordoff                       \ adjust buf offset
                nextoken                                \ next token
                incr> nextoken
                on> updated_words                       \ mark table modified
                sendtoken ;

: addtoken2     ( -- )
                nextoken wordseg2 wordoff  !L           \ install next token
                2 +!> wordoff                           \ bump over token num
                tokenbuf hash dup namevoc2 + @          \ old top name
                wordseg2 wordoff  !L                    \ install in pointer
                2 +!> wordoff                           \ bump over pointer
                wordoff  swap namevoc2 + !              \ link to hash table
                tokenbuf count dup>r                    \ a1 n1
                wordseg2 wordoff  lplace                \ seg1
                r> 1+ +!> wordoff                       \ adjust buf offset
                nextoken                                \ next token
                incr> nextoken
                on> updated_words                       \ mark table modified
                sendtoken ;

: addtoken3     ( -- )
                nextoken wordseg3 wordoff  !L           \ install next token
                2 +!> wordoff                           \ bump over token num
                tokenbuf hash dup namevoc3 + @          \ old top name
                wordseg3 wordoff  !L                    \ install in pointer
                2 +!> wordoff                           \ bump over pointer
                wordoff  swap namevoc3 + !              \ link to hash table
                tokenbuf count dup>r                    \ a1 n1
                wordseg3 wordoff  lplace                \ seg1
                r> 1+ +!> wordoff                       \ adjust buf offset
                nextoken                                \ next token
                incr> nextoken
                on> updated_words                       \ mark table modified
                sendtoken ;

: tokenover     ( -- )          \ send overflow like a too long word record
                0 sqzemit                       \ escape sequence start
                1 sqzemit                       \ escape message type1
                tokenbuf count                  \ the current word
                dup sqzemit                     \ send the string length
                sqzhndl sseg @ exbwrite ;       \ send strings data

: addtoken4     ( -- )
\fpc            tokenover       \
\tcom           nextoken wordseg4 wordoff  !L           \ install next token
\tcom           2 +!> wordoff                           \ bump over token num
\tcom           tokenbuf hash dup namevoc4 + @          \ old top name
\tcom           wordseg4 wordoff  !L                    \ install in pointer
\tcom           2 +!> wordoff                           \ bump over pointer
\tcom           wordoff  swap namevoc4 + !              \ link to hash table
\tcom           tokenbuf count dup>r                    \ a1 n1
\tcom           wordseg4 wordoff  lplace                \ seg1
\tcom           r> 1+ +!> wordoff                       \ adjust buf offset
\tcom           nextoken                                \ next token
\tcom           incr> nextoken
\tcom           on> updated_words                       \ mark table modified
\tcom           sendtoken
                ;

: ?nextbank     ( -- )          \ conditionally select the next token bank
                wordoff $FF00 u< ?exit          \ if current bank is full
                wordoff>wordoff
                nextoken 0 8192 um/mod nip 1+ 8192 * !> nextoken
                incr> tbank off> wordoff ;

: addtoken      ( -- )                  \ add symbol to current vocabulary
                ?nextbank
                tbank exec: addtoken1 addtoken2
                            addtoken3 addtoken4 tokenover ;

: "word>token   ( a1 n1 -- )    \ translate string to token and send it
                dup 32 >
                if      0 sqzemit               \ escape sequence start
                        1 sqzemit               \ escape message type1
                        dup sqzemit             \ send the string length
                        sqzhndl sseg @ exbwrite \ send strings data
                        exit
                then
                $20 tokenbuf 2+ c!
                sseg @ -rot tokenbuf placel
                findtoken 0=
                if      addtoken
                else    sendtoken
                then    ;

: scanword      ( a1 n1 -- a2 n2 )
                over sseg @ swap c@L bl =
                if      2dup bl skip 2dup 2>r nip - nip
                        begin   dup 16 - 0>
                        while   16 sqzemit 16 /string
                        repeat  ?dup if sqzemit then
                else    2dup bl scan 2dup 1 /string 2>r nip -
                        "word>token
                then    2r> ;

: scanline      ( seg off len -- )      \ scan contents of OUTBUF
                rot save!> sseg
                2dup + sseg @ swap 2- 0max @L   \ get line end chars
                $0A0D = dup>r                   \ if they are CRLF
                if      2-                      \ remove CRLF from line
                then
                begin   ?dup
                while   scanword
                repeat  drop
                r>
                if      17 sqzemit              \ 17 is a newline
                then
\fpc            ?keypause
                restore> sseg ;

: ?show.        ( -- )
                incr> linecnt
                linecnt 15 and ?exit
                " \|/-" drop linecnt 16 / 3 and + c@ (emit) 8 (emit) ;

: squeeze1      ( -- )
                ." Squeezing.. [" srchndl >bhandle count type ." ] "
                srchndl bopen if ." Failed to open!" cr exit then
                srchndl >bhandle fgetdate datebuf 2!    \ get the file date
                srchndl >bhandle endfile  sizebuf 2!    \ get file size
                0.0 srchndl bmovepointer
                tmphndl clr-hcb
                srchndl >bhandle >pathend" tmphndl place
                tmphndl 16 sqzhndl bwrite       \ start with name
                datebuf 4 sqzhndl bwrite        \ write data & time
                sizebuf 4 sqzhndl bwrite        \ write size in bytes
                sqzhndl bflush                  \ write buffer to disk
                sqzhndl >bhandle curpointer 2>r \ save ptr to next byte
                0.0 sqzlbuf 2!                  \ init to zero
                sqzlbuf 4 sqzhndl bwrite        \ place for compressed length
                off> linecnt
                begin   srchndl blineread dup
                while   ?show.
                        scanline
                repeat  2drop drop
                srchndl bclose drop
                $FFFF sizebuf !
                sizebuf 2 sqzhndl bwrite        \ end of file marker
                sqzhndl bflush
                sqzhndl >bhandle curpointer 2r@ d-      \ length of sqz'ed fil
                4 0 d- sqzlbuf 2!                       \ save in buf
                2r> sqzhndl >bhandle movepointer        \ back to length pt
                sqzlbuf 4 sqzhndl >bhandle hwrite drop  \ write sqz'ed length
                sqzhndl >bhandle endfile 2drop space cr ;

: squeeze_set   ( n1 -- )       \ setup filename for squeezing
                >r pathsave count here place
                r> >fadr countl here +placel
                here srchndl $>bhandle ;

create badexts  ," .COM" ," .ZIP" ," .ARC" ," .EXE"
                ," .OVL" ," .SYS" ," .BIN" ," .OBJ"
                ," .ZIM" ," .Z$$" ," .NDX" ," .SYM"
                ," .TBL" ," .FIL" ," .LIN"
                0 ,

: ?not_comexe   ( -- f1 )       \ verify file extention is not .COM or .EXE
                here handle>ext >r
                badexts 0
                begin   over count dup
                while   r@ swap caps-comp 0= or
                        swap count + swap
                repeat  2drop nip r>drop dup
                if      ." Skipped binary file [" here count type ." ]" cr
                then    0= ;

: squeeze       ( -- )
\tcom           dirinit
\tcom           diralloc
\fpc            dirseg drop                             \ force allocation
                srchndl >bhandle sqzhndl $>bhandle
                cmpext sqzhndl >bhandle $>ext
                bl word c@ 0=
                if      " *.SEQ" here place
                then
                sqzhndl read-write bopen
                if      sqzhndl bcreate
                        abort" Failed to create compressed file"
                else    sqzhndl >bhandle endfile        \ move to end of file
                        2 0 d- 0 0 dmax                 \ except two bytes
                        sqzhndl >bhandle movepointer    \ set position
                        sqzhndl dup>r >bsize @ 16 * r@ >bbytes !
                                                        \ set room to size
                        0 r> >boff !                    \ set offset to zero
                then
                begin   here c@
                        ?keypause
        [long]  while   here count here >pathend" nip - pathsave place
                        here $getdir
                        #fls 0
                        ?do     i squeeze_set
                                ?not_comexe
                                if      squeeze1
                                then    ?keypause
                        loop
                        bl word drop
                repeat
                $FFFE sizebuf !                 \ add $FFFE the end of
                sizebuf 2 sqzhndl bwrite        \ .ZIM file marker
                sqzhndl bflush
                sqzhndl bclose drop
                write_words
\tcom           dirrelease
\fpc            dirseg_release
                ;

: %showtable    ( -- )
                wordoff1 5 u< ?exit
                ." Word table 1" cr
                wordoff1 4
                do      cr wordseg1 i countl dup>r typel r> 5 +
                        ?keypause
               +loop
                wordoff2 5 u< ?exit
                cr cr ." Word table 2" cr
                wordoff2 4
                do      cr wordseg2 i countl dup>r typel r> 5 +
                        ?keypause
               +loop
                wordoff3 5 u< ?exit
                cr cr ." Word table 3" cr
                wordoff3 4
                do      cr wordseg3 i countl dup>r typel r> 5 +
                        ?keypause
               +loop
\tcom           wordoff4 5 u< ?exit
\tcom           cr cr ." Word table 4" cr
\tcom           wordoff4 4
\tcom           do      cr wordseg4 i countl dup>r typel r> 5 +
\tcom                   ?keypause
\tcom          +loop
                ;

: showtable     ( -- )
                %showtable
                cr cr ;

: .thread       ( seg vocabulary thread -- )
                cr ." Thread " dup 3 .r
                2* + @
                0 >r
                begin   ?dup
                while   r> 1+ >r
                        2dup 2- @L nip
                        ?keypause
                repeat  drop
                r> dup +!> wordtotal
                dup 4 u.r space 0
                ?do     ." ."
                loop    ;

: %showcnt      ( -- )
                wordoff1 5 u< ?exit
                off> wordtotal
                cr ." Vocabulary1" cr
                #threads 0
                do      wordseg1 namevoc1 i .thread
                loop    cr cr
                wordoff2 5 u< ?exit
                ." Vocabulary2" cr
                #threads 0
                do      wordseg2 namevoc2 i .thread
                loop    cr cr
                wordoff3 5 u< ?exit
                ." Vocabulary3" cr
                #threads 0
                do      wordseg3 namevoc3 i .thread
                loop    cr cr ;

: showcnt       ( -- )
                %showcnt
                ."  Total words " wordtotal u. cr cr ;

create sqzspcs
        $20 c, $20 c, $20 c, $20 c, $20 c, $20 c, $20 c, $20 c, $20 c,
        $20 c, $20 c, $20 c, $20 c, $20 c, $20 c, $20 c, $20 c, $20 c,
        $20 c, $20 c, $20 c, $20 c, $20 c, $20 c, $20 c, $20 c, $20 c,
        $20 c, $20 c, $20 c, $20 c, $20 c, $20 c, $20 c, $20 c, $20 c,
        $20 c,

create sqzcra
        $0D c, $0A c,

: sqztypel      ( seg off len -- )
                dup 0= abort" Attempt to write zero"
                rot sqzhndl swap exbwrite ;

: sqzspaces     ( n1 -- )
                17 min ?ds: sqzspcs rot sqztypel ;

: sqzcr         ( -- )
                ?ds: sqzcra 2 sqztypel ;

: un1word       ( -- )
                sqzbuf sqzoff + @ flip $7FFF and
                dup  8092 u<
                if      wordseg1 ptrseg rot 2* @L countl sqztypel
                        exit
                then
                dup 16384 u<
                if      wordseg2 ptrseg rot 2* @L countl sqztypel
                        exit
                then
                dup 24576 u<
                if      wordseg3 ptrseg rot 2* @L countl sqztypel
                        exit
                then    drop ;

: sqzfill       ( -- )          \ refill squeezed data buffer
                sqzbuf sqzlen sqzoff /string sqzbuf swap dup !> sqzlen cmove
                off> sqzoff
                sqzbuf sqzlen + sqzmax sqzlen -
                tblhndl hread +!> sqzlen ;

: unsqueezeword ( -- )          \ unsqueeze one word
                sqzbuf sqzoff + c@
                dup 0=                  \ esc char nothing for now
        [long]  if      didword
                        if      1 sqzspaces
                        then    drop
                        incr> sqzoff
                        sqzfill
                        sqzbuf sqzoff + dup c@ 1 =
                        if      1+ count dup>r ?ds: -rot sqztypel
                                r> 2+ +!> sqzoff
                                on> didword
                        else    incr> sqzoff
                                cr ." Illegal escape sequence " c@ .
                        then    exit
                then
                dup 17 <                \ 1 - 16 is a number of spaces
                if      didword
                        if      1+
                        then
                        sqzspaces
                        incr> sqzoff
                        off> didword
                        exit
                then
                dup 17 =                \ 17 is the CRLF token
                if      drop
                        sqzcr
                        incr> sqzoff
                        off> didword
                        ?show.
                        exit
                then
                dup 127 >               \ 8000 - FFFF is word tokens
                if      sqzbuf sqzoff + @ flip $FFFF =          \ end of file
                        if      on> sqzdone                     \ mark done
                                2 +!> sqzoff
                                exit
                        then
                        didword
                        if      1 sqzspaces
                        then    drop un1word
                        2 +!> sqzoff
                        on> didword
                        exit
                then
                dup 17 >                \ 18 - 127 is byte tokens
                if      18 -            \ mapped to tokens 0 - 110
                        didword
                        if      1 sqzspaces
                        then
                        wordseg1 ptrseg rot 2* @L countl sqztypel
                        incr> sqzoff
                        on> didword
                        exit
                then    drop
                incr> sqzoff ;

: ?sqzfill      ( -- )
                sqzoff sqzlen 10 - 0max u< ?exit
                sqzfill ;

: get_words     ( -- )
                read_words abort" Couldn't read word dictionary" ;

: sqzfile_set   ( -- )
                sqzhndl >bhandle clr-hcb                    \ clear handle
                pathsave count sqzhndl >bhandle place       \ install path
                tmphndl >pathend" sqzhndl >bhandle +place ; \ append filename

: ?fexists      ( -- f1 )       \ f1=true=go ahead
                sqzhndl >bhandle hopen dup 0=           \ already exists?
        [long]  if      drop
                        sqzhndl >bhandle fgetdate       \ -- time date
                        sqzhndl >bhandle hclose drop    \ close the file
                        datebuf 2@ d- 2dup d0=
                        if      2drop
                                ." Identical"
                        else    0.0 d<
                                if      ." Older"
                                else    ." Newer"
                                then
                        then
                        ."  file [" sqzhndl >bhandle count type
                        ." ] already exists, Overwrite [y/n] {n}?"
                        key upc 'Y' = cr
                then    ;

: unsqueeze1    ( -- )
                ." Un-squeezing.. [" sqzhndl >bhandle count type ." ] "
                sqzhndl bcreate abort" Failed to create UN-compressed file"
                sqzfill
                off> sqzdone
                begin   ?sqzfill
\fpc                    ?keypause
                        sqzlen          \ while not at end of .ZIM
                        sqzdone 0= and  \ and current file is not done
                while   unsqueezeword
                repeat
                sqzhndl bflush
                datebuf 2@ sqzhndl >bhandle fsetdate
                sqzhndl bclose drop space cr ;

: read_fileheader ( -- f1 )     \ f1=true for header read ok
                sqzfill
                sqzlen 28 u< if false exit then
                sqzbuf tmphndl dup clr-hcb 16 cmove     \ move in filename
                sqzbuf 16 + 2@ datebuf 2!
                sqzbuf 20 + 2@ sizebuf 2!
                sqzbuf 24 + 2@ sqzlbuf 2!
                tblhndl curpointer                      \ get file pointer
                sqzlen 28 - 0 d- tblhndl movepointer    \ backup to hdr end
                off> sqzoff                             \ reset buffer empty
                off> sqzlen
                true ;

: skiptonext    ( -- )  \ skip to the next file in .ZIM file
                sqzlbuf 2@                      \ get offset to next file
                tblhndl curpointer d+           \ add to current file offset
                tblhndl movepointer ;           \ reposition to that offset

: unsqueeze_view  ( -- )
                srchndl >bhandle tblhndl $>handle
                cmpext tblhndl $>ext
                tblhndl hopen abort" Couldn't open compressed file"
                cr
                begin   read_fileheader
                        ?keypause
                while   tmphndl count type tab ?cr
                        skiptonext
                repeat  ;

: unsqueeze_afile ( -- )
                true                                    \ not found true flag
                begin   read_fileheader dup
        [long]          if      drop
                                here tmphndl over c@ 1+ caps-comp 0=
                                if      sqzfile_set
                                        ?fexists
                                        if      unsqueeze1
                                        then
                                        drop false      \ replace found flag
                                        false           \ we are done
                                else    skiptonext true
                                then
                        then    0=
                until                                   \ was file found?
                if      ." Could not find [" here count type ." ]" cr
                then    ;

: unsqueeze_spec ( -- )
                begin   unsqueeze_afile
                        0.0 tblhndl movepointer
                        off> sqzoff                     \ reset buffer empty
                        off> sqzlen
                        bl word c@ 0=
                until   ;

: unsqueeze_all ( -- )
                begin   read_fileheader
                        ?keypause
                while   sqzfile_set
                        ?fexists
                        if      unsqueeze1
                        else    skiptonext
                        then
                repeat  ;

: unsqueeze     ( -- )
                srchndl >bhandle tblhndl $>handle
                cmpext tblhndl $>ext
                tblhndl hopen abort" Couldn't open compressed file"
                bl word >pathend" nip 0=
                if      here count pathsave place
                        bl word c@
                else    here count here >pathend" nip - pathsave place
                        here >pathend" here place       \ strip off path
                        here c@
                then
                if      unsqueeze_spec
                else    unsqueeze_all
                then    tblhndl hclose drop ;

: writetonext   ( -- )                  \ write this compressed file
                tblhndl curpointer 28 0 d- tblhndl movepointer
                                                \ backup to header start
                sqzlbuf 2@ 28 0 d+ 2* 0
                ?do     0 $8000 tblhndl wordseg1 exhread  $8000 - ?leave
                        0 $8000 z$$hndl wordseg1 exhwrite $8000 - ?leave
                loop    0 over  tblhndl wordseg1 exhread  over -
                abort" Failed during read of .ZIM"
                0 over  z$$hndl wordseg1 exhwrite swap -
                Abort" Failed during write to .Z$$" ;

: delete_1file  ( -- )
                true                                    \ not found true flag
                srchndl >bhandle tblhndl $>handle
                cmpext tblhndl $>ext
                tblhndl hopen abort" Couldn't open compressed file"
                srchndl >bhandle z$$hndl $>handle
                tmpext z$$hndl $>ext
                z$$hndl hcreate abort" Couldn't make temp file"
                begin   read_fileheader dup
        [long]          if      drop
                                here tmphndl over c@ 1+ caps-comp 0=
                                if      skiptonext
                                        drop false      \ replace found flag
                                else    writetonext
                                then    true            \ not done
                        then    0=
                until                                   \ was file found?
                z$$hndl hclose drop
                tblhndl hclose drop
                if      ." Could not find [" here count type ." ]" cr
                        z$$hndl hdelete drop
                else    tblhndl hdelete
                        abort" couldn't delete original .ZIM file"
                        z$$hndl tblhndl hrename
                        abort" failed to rename .Z$$ to .ZIM"
                then    ;

: delete_file   ( -- )          \ delete a file or files
                bl word c@ 0= ?exit
                begin   off> sqzoff                     \ reset buffer empty
                        off> sqzlen
                        delete_1file
                        bl word c@ 0=
                until   ;

: show1name     ( -- )          \ display the filename
                cr tmphndl count 15 over - spaces type
                ."  of " sizebuf 2@ 9 ud.r
                ."  bytes, compressed to " sqzlbuf 2@ 6 ud.r ."  bytes" ;

: shownames     ( -- )
                srchndl >bhandle tblhndl $>handle
                cmpext tblhndl $>ext
                ." View-names.. [" tblhndl count type ." ] "
                tblhndl hopen abort" Couldn't open compressed file"
                0
                begin   read_fileheader
                while   show1name
                        skiptonext
                        1+
                        ?keypause
                repeat  cr . ." Files"
                tblhndl hclose drop ;

: .sqoptions    ( -- )                  \ display help message
        cls
        ." Tom ZIMmer's text file squisher, written in Forth and compiled with TCOM."
        cr
        cr ." ZIM Help  --  ZIM                                alone, displays this help"
        cr 13 spaces    ."  ZIM filename{.ZIM}                 display .ZIM contents"
        cr 13 spaces    ."  ZIM -A filename{.ZIM} {files..}    add files to .ZIM file"
        cr 13 spaces    ."  ZIM -E filename{.ZIM} {pathname\}  extract file to pathname"
        cr 13 spaces    ."  ZIM -R filename{.ZIM} {files..}    delete files from .ZIM"
        cr 13 spaces    ."  ZIM -V filename{.ZIM}              display the files in .ZIM"
        cr 13 spaces    ."  ZIM -W                             display the word table"
        cr 13 spaces    ."  ZIM -#                             display hash thread depth"
        cr cr
        ." ZIM.COM will generate a file called ZIM.TBL it is a common symbol table"
        cr
        ." for all files compressed. This file IS NEEDED to uncompress a file again."
        cr
        ." If ZIM.TBL cannot be found you will not be able to perform an uncompress."
        cr cr 5 spaces
        ." TCOM is a public domain compiler available from:  Tom Zimmer"
        cr 55 sp>col ." 292 Falcato Drive"
        cr 5 spaces
        ." TCOM comes with source for the compiler,"
           55 sp>col ." Milpitas, Ca. 95035"
        cr 5 spaces
        ." library and example programs."
           55 sp>col ." Home: (408) 263-8859"
        cr 5 spaces
        ." A donation of $60.00 is requested."
           55 sp>col ." Work: (415) 327-8800"
        cr cr ." ***** WARRANTY = NONE *****"
        cr
        ." While every effort has been made to assure this software is bug free,"
        cr
        ." HOWEVER, *** NO WARRANTY OF ANY KIND IS STATED OR IMPLIED ***"
        ;

: zim           ( | name -- )           \ squeeze the file "name"
\fpc            unedit
\tcom           DECIMAL                         \ always select decimal
\tcom           INIT-CURSOR                     \ get intial cursor shape
\tcom           MARGIN_INIT                     \ initialize margins & TAB
\tcom           14 tabsize !
\tcom           ?DS: SSEG !                     \ init search segment
\tcom           DOSIO_INIT                      \ init EMIT, TYPE & SPACES
\tcom           $FFF0 SET_MEMORY                \ default to 64k code space
\tcom           DOS_TO_TIB                      \ move command tail to TIB
\tcom           caps on                         \ make not case sensitive
\tcom           $1000 allocate !> wordseg1
\tcom           $1000 allocate !> wordseg2
\tcom           $1000 allocate !> wordseg3
\tcom           $1000 allocate !> wordseg4
\tcom           $1000 allocate !> ptrseg
\fpc            wordseg1 0= abort" Out of memory!"
\fpc            wordseg2 0= abort" Out of memory!"
\fpc            wordseg3 0= abort" Out of memory!"
\fpc            ptrseg   0= abort" Out of memory!"
                wordseg1 0 $FFF0 0 lfill
                wordseg2 0 $FFF0 0 lfill
                wordseg3 0 $FFF0 0 lfill
\tcom           wordseg4 0 $FFF0 0 lfill        \ no seg 4 in F-PC
\tcom           ptrseg   0 $FFF0 0 lfill
\fpc            ptrseg   0 $BFF0 0 lfill        \ smaller ptr seg in F-PC
                off> sqzlen
                " ZIM.TBL" ">$ tblhndl $>handle
                bl word c@ 0=                   \ if not params, give help
                if      .sqoptions bye
                then
                here 1+ " -E" caps-comp 0=      \ -E=extract file
                if      get_words
                        bl word srchndl $>bhandle
                        unsqueeze bye
                then
                here 1+ " -V" caps-comp 0=      \ -V=view files
                if      bl word srchndl $>bhandle
                        unsqueeze_view bye
                then
                here 1+ " -W" caps-comp 0=      \ -W=display words
                if      get_words
                        showtable bye
                then
                here 1+ " -#" caps-comp 0=      \ -#=display dictionary
                if      get_words
                        showcnt bye
                then
                here 1+ " -A" caps-comp 0=      \ -A=Add files to .ZIM
                if      bl word srchndl $>bhandle
                        read_words drop
                        squeeze bye
                then
                here 1+ " -R" caps-comp 0=      \ -R=Remove file from .ZIM
                if      bl word srchndl $>bhandle
                        delete_file bye
                then
                here srchndl $>bhandle
                shownames ;

}

