\\ VED.SEQ               A Virtual EDitor        written by Tom Zimmer

        .options /opt /noinit

  VED is a virtual file editor, it allows editing and searching through
text files upto about 40 megabytes. You should find VED to be very fast
for startup, editing and movement within a file. Saving even small
changes to very large files (multi-megabyte) however can take several
minutes since the entire file must be re-written to disk.

  Note:  VED can require disk FREE SPACE up to twice the number of bytes
         the file being edited currently consumes on disk. In all cases,
         VED requires AVAILABLE (unused) disk space slightly greater than
         equal to the space currently consumed by the file being edited.
         While this may seem like a lot, it is in fact typical of disk
         based file editors.

Example: If you are editing a 4 megabyte file, VED will need at least
         4.1 megabytes of free space, and MAY need upto 8 megabytes of
         FREE SPACE on disk over and above the 4 megabytes currently
         being used by the file on disk. That is a possible total of 12
         megabytes (free space plus original file size) to edit a 4
         megabyte file.

  VED IS PUBLIC DOMAIN, ALL RESPONSIBILITY FOR ITS USE IS ASSUMED BY
YOU THE USER.

  VED was written in the Forth computer language, and compiled to pure
CALL threaded object code by TCOM.

  TCOM is a PUBLIC DOMAIN, optimizing (space & speed) Target COMpiler
that generates CALL threaded object code ".COM" files.

  This 100k source file compiles into a 33k .COM file in about 30 seconds
on a 20mhz 80386 computer.

  VED the editor and TCOM the compiler were written by Tom Zimmer.

  If you would like to make a donation to the further development of TCOM
on the 8086 family, and other target processors, send a check for $60 to:

                Tom Zimmer
                292 Falcato Drive
                Milpitas, Ca. 95035     Home: (408) 263-8859
                                        Work: (415) 327-8800

  You will receive the latest version of F-PC, TCOM, NEWZ, VED on 5 1/4
high density disks via postpaid return mail.  Be sure to include your name,
address, and telephone number.


-------------------------------------------------------------------------

Compiling:      TCOM VED <Enter>   \ you will need TCOM to do this.

Usage:          VED <filename> <optional_word_to_find> <Enter>

        Press F1 while in VED, for help if you need it.

Note:   Words that start with the "%" symbol in column one of the file
        being listed will not be displayed. This allows formatting your
        files with these special marking words.  A marking word can be
        placed on the DOS command line after the filename.  The editor
        will search for a marking word and position the editor at the line
        starting with the word.

        You can actually specify any word on the command line after the
        filename, and VED will find it and place it on the second
        line of the display.

-------------------------------------------------------------------------

{

\ define and reference these following color words NOW, to force them
\ to be allocated in memory now, and to be contiguous.

here    /nostack

blue   value hi1bg      hi1bg drop
ltgray value hi1fg      hi1fg drop
yellow value hi2bg      hi2bg drop
black  value hi2fg      hi2fg drop
dkgray value txtbg      txtbg drop
ltgray value txtfg      txtfg drop
black  value endbg      endbg drop
cyan   value endfg      endfg drop

here swap - constant color_length       \ area to save

             21    value displaylines   \ number of lines on screen
             48 constant lflen          \ list find buffer length
            512 constant pagebytes      \ bytes in each page, 4 pages

              0 value    maxpages       \ maximum edit pages, 6 bytes/page

              7 constant mempages       \ number of memory pages
              6 constant lowpages       \ fill to at least these pages

pagebytes mempages *    /nostack1
        512 +   value    pagesbytes     \ total bytes in all memory pages

pagebytes mempages *    /nostack1
                constant highwater

pagebytes lowpages *    /nostack1
                constant lowwater

              0 value     pageslen      \ length of all pages in memory
              0 value     page1len      \ length of page one
              0 value     pages&        \ pointer to pages buffer
              0 value     calc&

: field@        ( n1 n2 -<name>- n3 )   \ define a new field for record
                ( n1 -- a1 )            \ move from record n1 to the field
                create over , +         \ address of this field in the rec
                does> dofield@ ;

: field!        ( n1 n2 -<name>- n3 )   \ define a new field for record
                ( n1 -- a1 )            \ move from record n1 to the field
                create over , +         \ address of this field in the rec
                does> dofield! ;

\ ----------------------------------------------------------------------
\ The following two sets of defining words must match in size and
\ position of the defined fields!
\ ----------------------------------------------------------------------

0       /nostack1               \ don't give a stack depth error here
        2 field@ >page#@        \ physical block number         2 bytes
        2 field@ >bytes@        \ length of text in page        2 bytes
        2 field@ >lines@        \ Lines in this page            2 byte
constant b/rec                  \ bytes in a page record

32767 b/rec / 2* 256 - constant limitpages      \ maximum number of pages
                                                \ we can support in 64k
                                                \ of page record memory

0       /nostack1               \ don't give a stack depth error here
        2 field! >page#!        \ physical block number         2 bytes
        2 field! >bytes!        \ length of text in page        2 bytes
        2 field! >lines!        \ Lines in this page            2 byte
constant b/rec2                 \ bytes in a page record

\ ----------------------------------------------------------------------

        0 value totpages        \ pages in the current file
        0 value updateflg       \ has memory changes for these pages?
        0 value recseg&         \ edit pages records segment

: recsbytes     ( -- n1 )       \ total bytes in page records
                maxpages b/rec * ;

\ : dofield@    ( n1 a1 -- n2 )
\               @ swap b/rec * + recseg& swap @L ;

                                \ a1 = pointer to the field offset word value
code dofield@   ( n1 a1 -- n2 ) \ return field value n2 of record n1
                mov cx, 0 [bx]          \ get the field offset word
                load_bx
                mov ax, # b/rec         \ multiply n1 by "b/rec"
                mul bx
                mov bx, ax              \ result to BX
                add bx, cx              \ then add field offset
                mov cx, &> recseg&      \ base segment of records array
                mov dx, ds              \ save the data segment
                mov ds, cx              \ set to the records segment
                mov bx, 0 [bx]          \ fetch a word from segment
                mov ds, dx              \ restore the data segment
                ret             end-code

\ : dofield!    ( n1 n1 a1 -- )
\               @ swap b/rec * + recseg& swap !L ;

                                \ a1 = pointer to the field offset word value
code dofield!   ( n1 n2 a1 -- ) \ store n1 to field a1 @ of record n2
                mov cx, 0 [bx]          \ get the field offset word
                load_bx
                mov ax, # b/rec         \ multiply n1 by "b/rec"
                mul bx
                mov bx, ax              \ result to BX
                add bx, cx              \ then add field offset
                lodsw                   \ get value to store
                mov cx, &> recseg&      \ base segment of records array
                mov dx, ds              \ save the data segment
                mov ds, cx              \ set to the records segment
                mov 0 [bx], ax          \ store a word to segment
                mov ds, dx              \ restore the data segment
                load_bx
                ret             end-code

: set-page-records ( n1 -- )    \ adjust the number of page records for file
                maxpages 4 - 0max totpages > ?exit  \ only if we need space
                                                    \ ***** EXITS HERE *****
                totpages 128 +                      \ allocate 128 at a time
                recseg& 0=
                if      dup b/rec um* 16 um/mod nip 2+ alloc 8 =
                        abort" Failed to allocate page record buffer"
                        !> recseg& drop
                else    recseg& over b/rec um* 16 um/mod nip 2+ setblock
                        if      drop maxpages   \ if couldn't adjust, leave
                        then                    \ maxpages the same as before
                then    !> maxpages ;

: insert-pagerec ( n1 -- )      \ insert a page record at page n1
                set-page-records    \ adjust max pages if needed
                maxpages 2- umin >r             \ limit the page #
                recseg& r@ b/rec *              \ segment/offset of record
                maxpages b/rec * over - >r      \ calculate the remaining len
                2dup 2dup b/rec + r> cmoveL>    \ move the remaining recs out
                b/rec 0 LFILL                   \ clear the inserted rec
                -1 r> >page#!                   \ clear the records page#
                incr> totpages ;                \ increase total pages by one

0 value lastmem                 \ number of last page in memory

: delete-pagerec ( n1 -- )      \ delete a page record at page n1
                maxpages 2- umin >r             \ limit the page #
                recseg& r@ b/rec *              \ segment/offset of record
                maxpages b/rec * over - >r      \ calculate the remaining len
                2dup 2dup b/rec + swap r@ cmoveL \ pull in remaining recs
                r> + b/rec 0 LFILL              \ clear the last record
                -1 r> >page#!                   \ clear its page#
                totpages 1- 0max !> totpages    \ reduce total pages by one
                lastmem 1- 0max !> lastmem ;    \ reduce last mem page by one

: #delete-pagerecs ( n1 n2 -- )
                0
                ?do     dup delete-pagerec
                loop    drop ;

\ -------------------------------------------------------------------------

                handle orighndl         \ the edit file handle
                handle swaphndl         \ the swap file handle
                handle temphndl         \ a temporary file handle
                handle savehndl         \ a handle for saving

\ -------------------------------------------------------------------------
\ Some values needed by program.
\ -------------------------------------------------------------------------

0 value linebuffer              \ current line being edited buffer address
0 value page1#                  \ page number of first buffers page
0 value lineupdate              \ line has been changed flag
0 value pageoff                 \ offset into current page to top of screen
0 value anypages?               \ were any pages changed?
0 value curcol                  \ screen column
0 value slineoff                \ screen line offset
0 value slinerem                \ screen line remainder
0 value srow                    \ screen row
0 value goflg                   \ we are searching flag
0 value ?full                   \ is one of the page buffers full?
0 value ?browse                 \ are we in browse mode
0 value onlycur                 \ only display current edit line
0 value ?newfile                \ true if making a new file
0 value endpage                 \ next available page in swap file
0 value calccnt
0 value calcpage
0 value calculating?
2variable curline               \ current file line
2variable totines               \ total file lines

2variable dtotbytes             \ total characters in the current file

0 value marking                 \ are we in the process of marking text
0 value marked                  \ has a block of text been marked

0 value pagest                  \ selected text markers
0 value offsetst
0 value offsetrow
0 value pageed
0 value offseted

2variable offsetline

-1 value extabs                 \ expand tabs flag
-1 value insflag                \ insert flag

0 value hif                     \ hilight colors have been modified
0 value listscroll              \ horizontal scrolling offset
0 value lfindbuf                \ search text buffer
0 value lfindoff                \ column offset where text last found
0 value lfound                  \ was text found flag
0 value lfound1st
0 value lfcnt
0 value lreplbuf                \ replace text buffer

defer >hilight                  \ hilight defered words
defer >hilight2
defer >text

create veddate  [forth] getdate [target] , ,
create vedtime  [forth] gettime [target] , ,

: .pages        ( -- )
                savescr savecursor
                cls
                ."    #   abs bytes lines -- pages: " totpages u. cr 3 tenths
                totpages 0
                do      ." {"   i 3 u.r
                        ."  p:" i >page#@ 5 u.r
                        ."  b:" i >bytes@ 4 u.r
                        ."  l:" i >lines@ 3 u.r ." } "
                        i 1+ 3 mod 0= if cr then
                        ?keypause
                loop    cr
                ." maxpages: " maxpages u.
                ." page1#: " page1# u.
                5 tenths
                begin key? while key drop repeat        \ clean out keyboard
                key drop                                \ wait for next key
                restcursor restscr ;


: ,#s           ( d -- 0 0 )
                0 -rot
                begin   # 2dup or
                while   rot 1+ dup 3 =
                        if      ',' hold
                                drop 0
                        then    -rot
                repeat  rot drop ;

: big.          ( d1 -- )       \ display a double with ","'s
                <# ,#s #> type space ;

: >hi1          ( -- )          \ hilight one, for status lines
                hi1bg >bg hi1fg >fg ;

: >hi2          ( -- )          \ hilight two, for search found text
                hi2bg >bg hi2fg >fg ;

: >txt          ( -- )          \ normal text
                txtbg >bg txtfg >fg ;

: >end          ( -- )          \ end color
                endbg >bg endfg >fg ;

: ?save_colors  ( -- )          \ write VED back to disk after color changes
                hif 0= ?exit                    \ ***** EXITS HERE *****
                me@ me$ temphndl $>handle
                read-write temphndl hopen ?exit \ ***** EXITS HERE *****
                ?ds: ?cs: - $10 * $100 - &> hi1bg + 0   \ offset into file
                temphndl movepointer                    \ adj file pointer
                &> hi1bg color_length temphndl hwrite drop  \ write colors
                temphndl hclose drop ;

: veeol         ( -- )          \ erase to end of line
                cols #out @ - 1- 0max spaces ;

: leeol         ( -- )          \ erase to end of line
                cols #out @ - 1- 0max 0 ?do  ." Ä"  loop    ;

\ some shift type key sensing words, only the SHIFT key is needed

\ : ?capslock     ( --- f1 ) 0 $417 c@l $40 and 0<> ;
\ : ?altkey       ( --- f1 ) 0 $417 c@l $08 and 0<> ;
: ?ctrlkey      ( --- f1 ) 0 $417 c@l $04 and 0<> ;
: ?shiftkey     ( --- f1 ) 0 $417 c@l $03 and 0<> ;

: curcol!       ( n1 -- )       \ set the cursor to a new column n1
                listscroll >r
                0max dup !> curcol
                listscroll - cols 3 - >
                if      curcol cols 3 - - !> listscroll
                then    curcol listscroll min !> listscroll
                listscroll r> <>
                if      off> onlycur
                        dopage
                then    ;

: pagecursor    ( -- )          \ display the cursor
                curcol listscroll - 1+ srow 1+ at ;

: page#set@     ( n1 -- n1 )    \ make sure page has a number assigned to it
                                \ and return the page number
                dup >page#@ 0<
                if      endpage over >page#!
                        incr> endpage
                then    >page#@  ;

: -pageslen!    ( n1 -- )       \ subtract bytes n1 from PAGESLEN
                pageslen swap - 0max !> pageslen ;

M: +pageslen!   ( n1 -- )       \ add bytes n1 to PAGESLEN
                +!> pageslen ;

: swapposition  ( n1 -- )       \ position to record n1 in SWAP file
                page#set@ pagebytes um* swaphndl movepointer ;

: origposition  ( n1 -- )       \ position to record n1 in ORIG file
                >page#@ $7FFF and pagebytes um* orighndl movepointer ;

: add-page      ( a1 n1 -- a2 n2 )      \ add a page after LASTMEM
                incr> lastmem                   \ bump last page in memory
                lastmem insert-pagerec          \ insert a new page record
                lastmem swapposition            \ write page n1
                2dup pagebytes umin             \ dup and limit to a page
                2dup lastmem setlines           \ set the page lines
                swaphndl hwrite                 \ write upto a page of bytes
                dup lastmem >bytes!             \ set page size
                /string                         \ strip off bytes written
                off> updateflg                  \ clear update flags
                on> anypages?   ;

: pagessave     ( -- )          \ save all updated pages to the swap file
                updateflg 0= ?exit              \ ***** EXITS HERE *****
                pageslen pagebytes min !> page1len      \ page1 full length
                pages& pageslen dup
        [long]  if      lastmem 1+ page1#
                [long]  ?do     dup             \ if there are bytes to write
                                if              \ then write a page
                                        i swapposition          \ set positn
                                        2dup pagebytes umin     \ clip to pg
                                        2dup i setlines         \ set da lines
                                        swaphndl hwrite         \ write page
                                        i >bytes!               \ set page len
                                else    i lastmem 1+ i -
                                        #delete-pagerecs
                                        leave
                                then    pagebytes /string
                        loop    dup             \ if any bytes left
                        if      add-page        \ then insert a new page
                        then
                else    page1# !> lastmem
                        page1# swapposition     \ mark as in swapfile
                        0 page1# >lines!        \ clear the line counter
                then    2drop
                off> updateflg                  \ clear update flag
                on> anypages? ;

: pagesup       ( -- )  \ remove first page from memory, moving others up
                pages& pagesbytes               \ addr & length of buffer
                page1len /string                \ buffer after page one
                pages& swap cmove               \ move tail of buffer up
                page1# 1+ totpages 1- umin !> page1#    \ next page
                page1len -pageslen!             \ subtract length of page1#
                page1# >bytes@ !> page1len ;    \ reset page one length

: recalc-lines  ( -- )                  \ correct total lines and bytes
                0.0 dtotbytes 2!
                0.0  totines 2!
                totpages 0
                do      dtotbytes 2@ i >bytes@ 0 d+ dtotbytes 2!
                         totines 2@ i >lines@ 0 d+ totines 2!
                loop    ;

: setlines      ( a1 n1 n2 -- )         \ for text a1,n1 of page n2, set lines
                >r 0 -rot
                begin   $0A scan dup                    \ calculate lines
                while   1 /string                       \ in page
                        2>r 1+ 2r>                      \ bump line count
                repeat  2drop r> >lines! ;

: 1pageread     ( a1 n1 -- )    \ read in page n1 to address
                0 over >lines!
                over >r                                 \ save read address
                dup>r >page#@ 0<                        \ in ORIG or SWAP
                if      r@ origposition
                        pagebytes    orighndl hread     \ read ORIG file
                else    r@ swapposition
                        r@ >bytes@ swaphndl hread       \ read SWAP file
                then    dup +pageslen!                  \ adj mem byte count
                        r> 2dup >bytes!                 \ set page length
                r> -rot setlines ;

: page1fill     ( -- )          \ read first page into memory
                pages& page1# 1pageread
                page1# >bytes@ !> page1len ;    \ set length of page1

: pagesfill     ( -- )          \ fill memory buffer till full
        begin   pageslen lowwater u<            \ if remaining memory space
                lastmem totpages 1- u< and      \ and not past last page
        while   incr> lastmem                   \ bump last memory page
                pages& pageslen +               \ address of the page in mem
                lastmem 1pageread               \ read the page
        repeat  ;

: #page-refill  ( n1 -- )       \ refill memory starting at page n1.
                dup !> page1#
                    !> lastmem
                page1fill               \ refill first page
                page1len !> pageslen    \ also set total length
                pagesfill               \ and remaining pages
                off> updateflg ;        \ mark not modified

: zeromem       ( -- )          \ clear all pages out of memory
                page1# 0 totpages 1- between 0= ?exit   \ only if valid page
                                                \ ***** EXITS HERE *****
                lastmem page1# umax !> lastmem ;

\ ----------------------------------------------------------------------
\ *************************** WARNING **********************************
\ This function DOES NOT correct the addresses of the pages in memory.
\ It MUST be immediately followed by END>UP which will correct the
\ addresses of the pages in memory.
\ ----------------------------------------------------------------------

0 value pageendsave

: pages>end     ( -- )          \ move inmemory pages to end of buffer space
                begin   pageslen lowwater u>
                while   lastmem >bytes@         \ get the pages length
                        -pageslen!              \ reduce length of memory
                        decr> lastmem           \ reduce pages in memory
                                                \ repeat till enough memory
                repeat                          \ is available to read a page
                pages&                          \ addr of first page in mem
                dup pagesbytes pageslen - +     \ addr of destination
                dup !> pageendsave              \ set new first page addr
                pageslen                        \ length of text to move
                cmove>                          \ move text down in memory
                page1# 1- 0max !> page1# ;      \ backup a page

: end>up        ( -- )          \ move page1 from end of buf to page2
                pageendsave                     \ from addr
                pages& page1len +               \ to   addr is end of page one
                pageslen page1len -             \ length minus first page
                cmove   ;                       \ move pages up in memory

: minus1page    ( -- )          \ backup one page if not on first page
                pagessave
                pages>end
                page1fill
                end>up ;

: plus1page     ( -- )          \ move forward one page in file
                pagessave
                pagesup
                pagesfill ;

\ ----------------------------------------------------------------------
\ ----------------------------------------------------------------------
\ ----------------------------------------------------------------------

: .lineend      ( -- )
                veeol >hilight ." ³" cr ;

: onlycursor    ( -- )
                on> onlycur ;

\ **********************************************************************
\ Expand tabs on the fly while displaying each line of the file
\ **********************************************************************

create dots ,"         "        \ fill character for blank lines

0 value coltotal

: adj&clip      ( a1 n1 -- a1 n2 )      \ clip text to the window width
                coltotal
                if      coltotal over <
                        if      coltotal /string
                                off> coltotal
                        else    negate +!> coltotal 0
                        then
                then    #out @ + cols 1- min #out @ - ;

: .one_line     ( a1 n1 -- a2 n2 )      \ display one line of screen
                attrib @ >r
                over pages& page1len + <
                if      >hilight
                else    red >bg white >fg
                then    ." ³"
                r> attrib !
                dup 0=
        [long]  if      >end
                        cols #out @ - 1- 0max 8 /mod 0
                        ?do  dots count type loop
                        dots 1+ swap type .lineend
                        exit                    \ ***** EXITS HERE *****
                then
                listscroll !> coltotal
                2dup $0D scan 2dup 2>r nip -            \ parse line - CRLF
                extabs                                  \ expanding tabs??
 [long] if      begin   2dup 9 scan dup                 \ look for tab
                while   2dup 2>r                        \ save remainder
                        nip - adj&clip type             \ output preceeding
                        #out @ 1- listscroll coltotal - +
                        tabsize @ mod tabsize @ swap -
                        16 swap adj&clip SPACES drop    \ expand to tab pos
                         \ -- This 16 is a dummy parameter needed by ADJ&CLIP,
                           \  we discard it after expanding the TAB
                        2r> 1 /string                   \ remove the TAB
                repeat  2drop
        then    adj&clip type                           \ type line remainder
                cols 1- #out @ - spaces .lineend
                2r> 2 /string ;

: .editline     ( -- )                  \ display the current edit line
                attrib @ >hilight ." ³" attrib !
                linebuffer count
                listscroll /string cols 2- min type .lineend ;

\ nifty word to scale the current file position to a number less than n1,
\ returns d2 the scaled limit value, and d1 the scaled current position.

: pos/scaleto   ( n1 -- n2 n3 ) \ n1=scale to integer
                                \ n2=current file position scaled to $FFFF
                                \ n3=limit scaled to less than $FFFF
                >r dtotbytes 2@ dup>r dup 1+ um/mod nip 0
                page1# pagebytes um*
                slineoff 0 d+ r> 1+ um/mod nip 0
                2swap r@ um/mod nip 1 max um/mod nip r> min ;

: 0rbar         ( -- )
                savecursor >hilight
                cols 1- displaylines pos/scaleto 1 max at ." ³"
                restcursor ;

: .rbar         ( -- )          \ display the right bar with file offset
                savecursor
                cols 1- displaylines pos/scaleto 1 max at
                goflg
                if      >hilight2
                else    >hilight
                then    ." Û"
                restcursor ;

: ?markhilight  ( a1 n1 -- a1 n1 )  \ select hilighting for the current line
                >text                   \ default to normal text attributes
                marking marked or 0= ?exit      \ ***** EXITS HERE *****
                over pages& -
                page1# pagebytes um* rot    0 d+ 2>r
                                        \ calculate actual file position
                pagest pagebytes um* offsetst 0 d+ 2r@ 1. d+ d<
                                        \ compare to mark start
                pageed pagebytes um* offseted 0 d+ 2r>       d> and
                                        \ and to mark end
                if      >hilight2       \ and hilight if in range
                then    ;

: dostatus      ( -- )
                25 0 at                         \ also show some status info
                pageslen highwater u>                   \ if full, an error!
                ?full or
                if      ?browse
                        if      >hilight
                                ."   BROWSE  "
                        else    >hilight2
                                ."  **FULL** "        \ notify user
                        then    on> ?full
                else    anypages?
                        if      >hilight2 ."  changed "
                        else    >hilight  ." ÄÄÄÄÄÄÄÄÄ"
                        then
                then    >hilight
                ."  Column: "   curcol .
                ." Position: " 100 pos/scaleto .
                ." % Size: " dtotbytes 2@ big. leeol
                 0 displaylines 2+ at >hilight
                ."   Line: " curline 2@ 1. d+ big. ." of "
                calculating?                    \ are we still counting lines
                if                              \ then tell the user
                        ." counting lines"      \ we are counting lines
                        totines 3 + C@ 32 and  \ show flashing to user
                        if      ."  "
                        else    ."  "
                        then
                else    totines 2@ big. ." lines"      \ no, show lines
                then
\                46 sp>col ." Depth: " depth  1 .r
\                60 sp>col ." Pages: " page1# 1 .r ." -" lastmem 1 .r
                veeol 1 spaces ;

: dopage        ( -- )          \ list current displaylines of file
                savecursor cursor-off
                onlycur                         \ is the update cursor line
                                                \ only flag on?
                if      0 srow 1+ at .editline  \ then update the cursor line
                        off> onlycur            \ only, and clear the flag
                        dostatus
                        restcursor
                        exit                    \ ***** EXITS HERE *****
                then
                0 1 at
                pages& pageslen                 \ addr & total length
                pageoff /string                 \ addr&len of page text
                displaylines 0                  \ display rest of screen
                do      ?markhilight
                        i srow =                \ if cursor row,
                        if      $0A scan 1 /string      \ skip a line
                                .editline       \ display line buffer
                        else    .one_line       \ else display page buffer
                        then
                loop    2drop \ nip 0= !> atend?
                dostatus
                .rbar restcursor ;

: .emptyscr     ( -- )          \ display an empty screen
                0 1 at
                displaylines 0
                do      >hilight ." ³" >text veeol cr
                loop    ;

: nextline      ( n1 -- n2 )    \ given offset n1, find offset of next line
                pages& pageslen rot /string $0A scan 1 /string drop
                pages& - ;

: prevline      ( n1 -- n2 )    \ given offset n1, find offset of prev line
                1- pages& over + 1- swap $0A -scan 1 /string drop
                pages& - 0max ;

: +1line        ( -- )          \ forward a line in file
                pageoff pagebytes u>
                if      pageslen pagebytes umin >r      \ save page length
                        plus1page
                        pageoff  r@ - 0max !> pageoff   \ sub from PAGEOFF
                        slineoff r> - 0max !> slineoff  \ and from SLINEOFF
                then    pageoff nextline !> pageoff ;

: -1line        ( -- )          \ back a line in file
                pages& pageoff 2- 0max $0A scan nip 0=
                if      page1# 0=
                        if      off> pageoff
                                exit            \ ***** EXITS HERE *****
                        then
                        minus1page
                        page1len +!> pageoff    \ just after end of buffer
                        page1len +!> slineoff   \ correct screen line offset
                then
                pageoff 2 =
                if      off> pageoff            \ don't bother to scan, just
                        exit                    \ ***** EXITS HERE *****
                then    pageoff prevline !> pageoff ;

: %endchar      ( -- n1 )       \ offset to last char on line
                255 linebuffer over + swap      \ strip trailing blanks
                $20 -skip nip ;

: ?expand_tabs  ( -- )                  \ conditionally expand tabs
                extabs 0= ?exit         \ only if expand tabs flag is on
                                        \ ***** EXITS HERE *****
                linebuffer count
                begin   9 scan dup
        [long]  while   over bl swap c!         \ change to a blank
                        1 /string 2dup          \ step past tab
                        linebuffer c@ over -    \ calculate text position
                        tabsize @ mod tabsize @ swap -
                        tabsize @ mod >r        \ distance to move
                        over r@ + swap cmove>   \ expand the text
                        over r@ blank           \ fill expanded area with bl's
                        swap r@ + swap          \ adjust remaining text
                        r> linebuffer c+!       \ adjust line length
                repeat  2drop ;

: getline       ( -- )          \ get the current line from page
                pages& pageslen slineoff /string 2dup $0A scan nip -
                1- 0max 255 umin linebuffer place
                ?expand_tabs                            \ conditional expand
                linebuffer count 255 swap /string blank \ trail with blanks
                255 linebuffer c!                       \ count to full buffr
                off> lineupdate ;                       \ clear update flag

: placeline     ( -- )          \ place linebuffer into page
                pages& pageslen slineoff /string 2dup $0A scan 1 /string
                dup !> slinerem nip -
                linebuffer c@ over - dup>r 0<>
                if      2dup + dup r@ + slinerem        \ from to count
                        r@ 0<
                        if      cmove                   \ compress
                        else    cmove>                  \ expand
                        then
                then    drop
                ?dup
                if      linebuffer count rot swap cmove \ place text
                then
                r@ +pageslen!                           \ shorter/longer
                slineoff page1len u<=
                if      r@ +!> page1len                 \ adj page len in mem
                then    r> s>d                          \ double difference
                dtotbytes 2@ d+ 0. dmax dtotbytes 2!    \ adjust length
                off> lineupdate                         \ clear line update
                on> updateflg                           \ set   page update
                on> anypages? ;                         \ set   file update

: putline       ( -- )          \ put line back into page
                lineupdate 0= ?exit             \ ***** EXITS HERE *****
                totpages maxpages 3 - >=        \ if page buffers are full
                if      on> ?full               \ then notify user
                        exit                    \ and don't save changes
                                                \ ***** EXITS HERE *****
                then
                %endchar linebuffer c!          \ and adjust buffer count
                $0A0D linebuffer count + !      \ append CRLF
                2 linebuffer c+!                \ correct line count
                placeline
                pageslen lowwater u<            \ if memory is not full
                lastmem totpages 1- u< and      \ and not at last page
                if      pagesfill               \ then fill remaining space
                then
                pageslen highwater u>           \ memory is full
                if                              \ and curline before last page
                        slineoff pageslen dup pagebytes mod - u<
                        if      pagessave
                                lastmem >bytes@ -pageslen!
                                lastmem 1- 0max !> lastmem
                        else    plus1page       \ else move forward a page
                                                \ to make more room in mem
                        then
                then    ;

: ?lastline     ( -- f1 )       \ are we on last line?
                lastmem  totpages 1- u>=                \ on last page
                slineoff pageslen    u>= and ;          \ and at end of file

: ?firstline   ( -- f1 )       \ are we on first line?
                page1# 0= slineoff 0= and ;

: delline       ( -- )          \ delete current line of file
                ?full ?exit                     \ ***** EXITS HERE *****
                ?lastline ?exit                 \ ***** EXITS HERE *****
                pages& pageslen slineoff /string $0A scan 1 /string nip 0=
                if      noop
                then
                linebuffer off
                placeline
                pageslen lowwater u<            \ if memory is not full
                lastmem totpages 1- u< and      \ and not at last page
                if      pagesfill               \ then fill remaining space
                then
                totines 2@ 1. d- 0. dmax totines 2!
                getline ;

: %-sline       ( -- )          \ up one screen line
                ?firstline ?exit                \ ***** EXITS HERE *****
                srow 0=
                if      -1line
                else    srow 1- 0max !> srow
                then
                slineoff prevline !> slineoff
                slineoff pageoff umin !> pageoff        \ topline above or at
                curline 2@ 1. d- 0. dmax curline 2! ;   \ screen line

: -sline        ( -- )          \ move up a line on screen and in file
                putline %-sline getline ;

: %+sline       ( -- )          \ down one screen line
                ?lastline ?exit                 \ ***** EXITS HERE *****
                srow displaylines 1- >=
                if      +1line
                else    incr> srow
                then
                slineoff nextline !> slineoff
                curline 2@ 1. d+ curline 2! ;

: +sline        ( -- )          \ move down one line on screen and in file
                putline %+sline getline ;

: %-scrlline    ( -- )          \ scroll up one line
                ?firstline ?exit                \ ***** EXITS HERE *****
                page1# 0= pageoff 0= and
                if      %-sline exit            \ ***** EXITS HERE *****
                then
                -1line
                slineoff prevline !> slineoff
                curline 2@ 1. d- 0. dmax curline 2! ;

: -scrlline     ( -- )          \ scroll screen up one line in file
                putline %-scrlline getline ;

: markoff       ( -- )          \ clear any marked lines that may be
                                \ currently marked
                off> marking
                off> marked
                off> pagest off> offsetst
                off> pageed off> offseted ;

: fhome         ( -- )          \ to top of file
                savecursor cursor-off
                putline
                pagessave                       \ preserve current contents
                zeromem                         \ clear all pages from mem
                page1# 0<>                      \ if not already on page zero
                if      0 #page-refill          \ select first page
                then
                off> pageoff                    \ top of buffer to screen
                off> slineoff                   \ top of buffer for line
                0 curcol!                       \ first column
                off> srow                       \ first screen row
                off> lfound                     \ no text found
                0. curline 2!                   \ 0 current line number
                getline                         \ get the line
                restcursor ;

: lpgup         ( -- )          \ backward "displaylines" into file
                putline
                displaylines 0   do  %-scrlline  loop
                getline
                off> lfound ;

: updown        ( -- )
                displaylines 0
                do      %-scrlline      \ slineoff drop
                loop
                off> srow
                displaylines 0
                do      %+sline         \ slineoff drop
                loop
                ;

: lhome         ( -- )          \ goto start of line
                0 curcol! ;

: lend          ( -- )          \ goto end of line
                %endchar curcol! ;

: %+scrlline    ( -- )          \ scroll line down one
                ?lastline ?exit                 \ ***** EXITS HERE *****
                +1line
                slineoff nextline !> slineoff
                curline 2@ 1. d+ totines 2@ dmin curline 2! ;

: +scrlline     ( -- )          \ scroll screen one line down in file
                putline %+scrlline getline ;

: lleft         ( -- )          \ scroll screen left
                listscroll 8 - 0max !> listscroll
                curcol 8 - curcol! ;

: lright        ( -- )          \ scroll screen right
                listscroll 8 + 132 min !> listscroll
                curcol 8 + 132 min curcol! ;

: +scol         ( -- )          \ move right on screen
                curcol 1+ 132 min curcol! onlycursor ;

: pageins       ( c1 -- )       \ insert char c1 into the current line
                ?full                           \ unless file is full
                if      drop exit               \ then discard & exit
                                                \ ***** EXITS HERE *****
                then
                insflag                         \ insert/overtype flag
                if      linebuffer count curcol /string
                        >r dup dup 1+ r> 252 min cmove> c! \ insert the char
                else    linebuffer 1+ curcol + c!          \ overtype char
                then    +scol                              \ next column
                on> lineupdate                  \ mark as changed
                on> anypages?                   \ mark file modified
                onlycursor ;          \ tell redisplay to show this line only

: pagecr        ( -- )          \ insert a CR & LF in file
                ?full ?exit                     \ ***** EXITS HERE *****
                %endchar curcol min curcol!
                $0D pageins
                $0A pageins
                lhome +sline
                off> onlycur ;

: lsplit        ( -- )          \ split line at cursor
                ?full ?exit                     \ ***** EXITS HERE *****
                %endchar curcol min curcol!
                $0D pageins
                $0A pageins
                curcol 2- curcol!               \ backup to previous position
                putline getline
                off> onlycur ;

: %delchar      ( -- )          \ delete char under cursor in cur line
                linebuffer count curcol /string >r
                dup 1+ swap r> 252 min cmove
                bl linebuffer count + 1- c!
                on> lineupdate
                on> anypages? ;

\ ----------------------------------------------------------------------
\ WARNING!!  This function doesn't check to see if the joined total line
\            length will be too long after the join!!!
\ ----------------------------------------------------------------------

: joinline      ( -- )          \ join this line and next
                ?full ?exit                     \ ***** EXITS HERE *****
                ?lastline ?exit                 \ ***** EXITS HERE *****
                %endchar 131 > ?exit            \ only lines less than 131
                                                \ ***** EXITS HERE *****
                %endchar
                if      %endchar 1+ curcol max 131 min  \ at least curcol
                else    0
                then
                dup linebuffer c!               \ set linebuffer length
                    curcol!                     \ move to end of line
                placeline                       \ line back into buffer
                                                \ but without CRLF chars
                getline                         \ get the new line again
                                                \ auto append next line to it
                off> onlycur ;

: delchar       ( -- )          \ delete the char under the cursor
                ?full ?exit                     \ ***** EXITS HERE *****
                curcol %endchar <               \ if not yet at line end
                if      %delchar                \ then delete a character
                        onlycursor
                else    insflag                 \ else if in insert mode
                        if      joinline        \ then join with next line
                                on> lineupdate  \ mark as changed
                                on> anypages?
                        then
                then    ;

: lchar@        ( -- c1 )       \ get the current line character
                linebuffer 1+ curcol + c@ ;

: lwdel         ( -- )          \ delete word at cursor
                ?full ?exit                     \ ***** EXITS HERE *****
                %endchar curcol <=
                if      joinline                \ join this line and next
                        0 curcol!
                        %delchar
                else    lchar@ bl <>
                        if      begin lchar@ bl <> while %delchar repeat
                        then
                        begin   lchar@ bl  =
                                curcol %endchar < and
                        while   %delchar
                        repeat  onlycursor
                then    ;

: -scol         ( -- )          \ left a column on screen, wrap to prev line
                curcol 0=
                if      ?firstline 0=
                        if      -sline lend
                        then
                else    curcol 1- curcol! onlycursor
                then    ;

: fend          ( -- )          \ to bottom of file, actually limited
                                \ to bottom of file minus one page full
                savecursor cursor-off
                putline
                pagessave                       \ preserve current contents
                zeromem                         \ clear pages from memory
                totpages lowpages - 0max        \ select the last few pages
                #page-refill                    \ and refill the page buffer
                pageslen !> pageoff             \ first   line to last byte
                pageslen !> slineoff            \ current line to last byte
                off> listscroll                 \ no horizontal scrolling
                off> lfound                     \ no text found
                updown                          \ re-center screen on line
                getline                         \ get line beyond end of file
                -sline lend                     \ up to last real line in file
                totines 2@ 1. d- 0. dmax curline 2!     \ set last line
                restcursor ;

: ltab          ( -- )          \ tab to next column
                8 curcol 8 mod -
                insflag                         \ if in insert mode
                if      0 ?do bl pageins loop
                        curcol
                else    curcol +
                then    131 min curcol! ;

: lbtab         ( -- )          \ tab to previous column
                curcol 0=                       \ if at column zero
                if      -scol                   \ goto end of previous line
                        curcol 8 mod            \ and if not on tab stop
                        if      ltab            \ goto next tab stop
                        then
                else    curcol dup 1- 0max 8 mod 1+ - curcol!
                        onlycursor             \ else backup to tab stop
                then    ;

: lwrd          ( -- )          \ left word on screen
                ?shiftkey
                if      lleft           \ if shift key held, scroll left
                        exit                    \ ***** EXITS HERE *****
                then    curcol 0=               \ if at line start
                if      -scol                   \ then up and to the right
                        exit                    \ ***** EXITS HERE *****
                then    -scol                   \ backup one char
                curcol 0= ?exit                 \ stop if at line start
                                                \ ***** EXITS HERE *****
                lchar@ bl =                     \ if cur char is a blank
                if      curcol 0                \ then skip blanks
                        ?do     -scol lchar@ bl <> ?leave
                        loop
                then    curcol 0                \ and skip to a blank
                        ?do     -scol lchar@ bl = ?leave
                        loop
                lchar@ bl =                             \ current is blank &
                linebuffer 2+ curcol + c@ bl <> and     \ next is not blank
                if +scol then onlycursor ;              \ then forward 1 char

: rwrd          ( -- )          \ right word on screen
                ?shiftkey
                if      lright          \ if shift key held, scroll right
                        exit                    \ ***** EXITS HERE *****
                then    %endchar curcol <=      \ at line end?
                if      +sline                  \ then down and to the left
                        0 curcol!
                        exit                    \ ***** EXITS HERE *****
                then    lchar@ bl <>            \ if cur char is blank
                if      %endchar curcol         \ then skip to a blank
                        ?do     +scol lchar@ bl = ?leave
                        loop
                then    %endchar curcol         \ and finally skip blanks
                ?do     +scol lchar@ bl <> ?leave
                loop    onlycursor ;

: backdel       ( -- )          \ delete char before cursor
                ?full ?exit                     \ ***** EXITS HERE *****
                curcol 0>
                if      curcol 1- curcol!
                        %delchar
                        onlycursor
                        exit                    \ ***** EXITS HERE *****
                then    ?firstline 0=
                if      -scol delchar
                then    ;

: instgl        ( -- )          \ insert/overwrite toggle
                insflag 0= dup !> insflag
                if      big-cursor
                else    norm-cursor
                then    onlycursor ;

: lpgdn         ( -- )          \ forward "displaylines" into file
                putline
                displaylines 0   do  %+scrlline  loop
                ?lastline
                if      fend
                then
                getline
                off> lfound ;

: scrtop        ( -- )          \ move to top of screen
                srow 0
                ?do     -sline
                loop    ;

: scrbot        ( -- )          \ move to bottom of screen
                displaylines 1- srow over min
                ?do     +sline
                loop    ;

: linefind      ( -- n1 f1 )    \ search one line for text
                lfindbuf count
                pages& pageslen pageoff /string
                2dup $0A scan 1 /string nip - search ;

: ?stop         ( -- )          \ poll keyboard for stop now
                key?
                if      key 27 <> !> goflg
                then    ;

: rest_page     ( n1 -- )       \ restore the previous page n1
                page1# over <>                  \ if not on same page
                if      pagessave               \ save current pages
                        zeromem                 \ clear all pages from mem
                        dup #page-refill        \ reset to current page
                then    drop ;

: lafind        ( -- )          \ search for already entered text again
                lfindbuf count
                linebuffer count curcol 1+ /string search
                if      on> lfound
                        curcol 1+ + curcol!
                        exit                    \ ***** EXITS HERE *****
                then    drop
                cursor-off
                putline
                linebuffer off
                curline 2@       2>r
                page1#   pageoff 2>r
                slineoff srow    2>r
                srow dup 0 ?do  -sline     loop
                         0 ?do  +scrlline  loop
                lfound
                if      +scrlline
                then
                off> lfcnt
                off> lfound
                on> goflg
                1 displaylines 1+ at >hilight ."   Searching for " '"' emit
                >hilight2 lfindbuf count type >hilight
                '"' emit ."  press ESC to cancel" veeol
                begin   linefind dup 0= dup
                        if      pageoff +1line pageoff <> and
                                curline 2@ 1. d+ curline 2!
                        then    goflg and
                while   2drop
                        incr> lfcnt
                        lfcnt 1023 and 0=
                        if      dostatus ?stop
                        then
                repeat  !> lfound !> lfindoff
                cursor-on off> goflg
                0rbar
                1 displaylines 1+ at
                lfound 0=
                if      ."  Text not found " leeol beep
                        2r> !> srow    !> slineoff
                        2r> !> pageoff rest_page
                        2r> curline 2!
                        >text
                        0 curcol!
                        getline
                        exit                    \ ***** EXITS HERE *****
                then    2r> 2drop 2r> 2drop 2r> 2drop
                on> lfound1st
                ."  Text found at column " lfindoff . leeol
                off> srow
                pageoff  !> slineoff
                lfindoff curcol!
                slineoff
                5 0
                do      %-sline
                loop
                5 0
                do      slineoff over = ?leave
                        %+sline
                loop    drop
                >text getline
                lfindbuf count linebuffer count search drop curcol! ;

: lbfind        ( -- )          \ search backwards for already entered text
                cursor-off
                putline
                linebuffer off
                curline 2@       2>r
                page1#   pageoff 2>r
                slineoff srow    2>r
                srow dup 0 ?do  -sline     loop
                         0 ?do  +scrlline  loop
                -scrlline
                off> lfcnt
                off> lfound
                on> goflg
                1 displaylines 1+ at >hilight
                ."   Searching backwards for " '"' emit
                >hilight2 lfindbuf count type >hilight
                '"' emit ."  press ESC to cancel" veeol
                begin   linefind dup 0= dup
                        if      pageoff -1line pageoff <> and
                                curline 2@ 1. d- 0. dmax curline 2!
                        then    goflg and
                while   2drop
                        incr> lfcnt
                        lfcnt 511 and 0=
                        if      dostatus ?stop
                        then
                repeat  !> lfound !> lfindoff
                cursor-on off> goflg
                0rbar
                1 displaylines 1+ at
                lfound 0=
                if      ."  Text not found " leeol beep
                        2r> !> srow    !> slineoff
                        2r> !> pageoff rest_page
                        2r> curline 2!
                        >text
                        0 curcol!
                        getline
                        exit                    \ ***** EXITS HERE *****
                then    2r> 2drop 2r> 2drop 2r> 2drop
                on> lfound1st
                ."  Text found at column " lfindoff . leeol
                off> srow
                pageoff  !> slineoff
                lfindoff curcol!
                slineoff
                5 0
                do      %-sline
                loop
                5 0
                do      slineoff over = ?leave
                        %+sline
                loop    drop
                >text getline
                lfindbuf count linebuffer count search drop curcol! ;

: lfind         ( -- )          \ enter text and search for it
                1 1 at >hilight ."  Text to find:" veeol
                >hilight2
                on> autoclear
                off> stripping_bl's
                16 1 lfindbuf lflen lineeditor >text    \ get text from user
                if      lafind                          \ and go find it
                then    ;

: lhfind        ( -- )          \ find word at program startup
                bl word count lflen min lfindbuf place
                lfindbuf c@ 0= ?exit            \ leave if no word specified
                                                \ ***** EXITS HERE *****
                lafind  ;

: larepl        ( -- )          \ replace just found text with text already
                                \ entered
                lfound 0= ?exit                 \ ***** EXITS HERE *****
                lfindbuf c@ 0
                ?do     %delchar
                loop    lreplbuf count bounds
                ?do     i c@ pageins
                loop
                putline getline         \ save changes to line
                dopage                  \ show results momentarily
                lafind ;                \ find next occurance

: lrepall       ( -- )          \ replace all occurances
                begin   lfound
                while   larepl
                repeat  ;

: lrepl         ( -- )          \ replace just found text with text entered
                1 1 at >hilight ."  Replace with:" veeol
                >hilight2
                on> autoclear
                off> stripping_bl's
                16 1 lreplbuf lflen lineeditor >text    \ get text from user
                if      larepl
                then    ;

: gotoline      ( line page -- )
                savecursor cursor-off
                putline
                pagessave                       \ preserve current contents
                zeromem                         \ clear pages from memory
                0max #page-refill               \ select last page
                off> pageoff                    \ first   line to last byte
                off> slineoff                   \ current line to last byte
                off> listscroll
                0 curcol!
                off> srow
                off> lfound
                dup 3 min dup 0
                ?do      %+sline
                loop    - 0
                ?do     %+scrlline
                loop    getline
                restcursor ;

: past_gotoline ( d1 -- d1 )
                calculating?
        [long]  if      24 1 at >hilight2
                        ."  One moment counting lines..  Press: ESC to stop "
                        >hilight veeol
                        begin   -1 !> calccnt
                                calclines
                                2dup totines 2@ d<
                                calculating? 0= or
                                key? or
                        until   key? if key drop then
                then    ;

create gotobuf ," 0" 14 allot

: %goto         ( -- )          \ goto line in gotobuf
                $2020 gotobuf count 2dup upper + !
                gotobuf number?
        [long]  if      1. d- 0. dmax           \ 0ne lower than entered
                        past_gotoline
                        totines 2@ 1. d- dmin 2dup
                        totines 2@ 1. d- d=    \ limited to last line
                        if      2drop
                                fend
                                exit            \ just goto end of file
                                                \ ***** EXITS HERE *****
                        then
                        0.0
                        totpages 0
        [long]          ?do     i >lines@ 0 d+ 2over 2over 1. d+ d<
                                if      i >lines@ 0 d-     \ remove lines
                                        2dup curline 2!    \ set cur line
                                        d- drop i gotoline \ go there
                                        0.0 0.0            \ dummy values
                                        leave
                                then
                        loop    2drop
                then    2drop ;

: lgoto         ( -- )          \ goto a percent position in file
                1 1 at >hilight ."  Goto Line:" veeol
                >hilight2
                on> autoclear
                off> stripping_bl's
                13 1 gotobuf 7 lineeditor >text    \ get line # from user
                if      %goto
                then    ;

: .listing_file ( -- )          \ display the current filename
                >hilight 0  0 at
                ?newfile
                if      ." Ú" >hilight2 ."  New: " >hilight space
                else    ." Ú Editing: "
                then    orighndl >pathend" type space leeol ." ¿" >text ;

: .lastline     ( -- )          \ show the last line of display
                 0 displaylines 1+ at >hilight
." À F10=Save&Exit,   ^O=Open file,   F6=Find,   Alt-P=file to Printer,   F1=Help"
                "  ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ"
                cols #out @ - 1- 0max min type ." Ù" >text ;

: setuppages    ( -- )          \ prepare a file for editing
                recseg& ?dup if dealloc drop then       \ release pages buffer
                off> recseg&                            \ clear pages segment
                off> maxpages                           \ clear max pages
                off> totpages                           \ clear total pages
                orighndl endfile 2dup dtotbytes 2!      \ set total bytes
                pagebytes um/mod                        \ file size in pages
                dup limitpages u>       \ 64k limit on page records buffer
                abort" Can't edit file larger than about 40 megabytes!"
                swap if 1+ then 1 max !> totpages       \ set total pages
                set-page-records                        \ set maximum pages
                0.0 orighndl movepointer                \ position to start
                recseg& 0 recsbytes 0 LFILL             \ clear page records
                totpages 0
                do      i $8000 + i >page#!
                        pagebytes i >bytes!
                        -1        i >lines!
                loop
                orighndl >nam c@ bl or 96 -
                getdiskfree * um*                       \ avail disk space
                off> ?browse
                dtotbytes 2@ mempages pagebytes * 0 d+  \ needed space
                d< !> ?full                             \ if too big, flag on
                off> calcpage
                0.0 totines 2!
                on> calculating? ;

: delswapfile   ( -- )
                swaphndl hclose  drop           \ close  swap file
                swaphndl hdelete drop ;         \ delete swap file

: saveapage     ( f1 n1 -- f2 )         \ save page n1
                !> page1#
                9 6 at ." Saving page " page1# 1+ u.
                ." of " totpages . ." pages, "
                pagebytes u. ." bytes each "
                page1fill
                pages& page1len savehndl hwrite page1len <>
                if      0=                      \ change false to true
                        5 8 75 10 box&fill >hilight
                        9 9 at ." Disk FULL!! "
                then    ;

                                \ f1=true if failed to save properly
: pagesaveall   ( -- f1 )       \ save all of the current file
                putline
                pagessave                       \ save updated memory pages
                getline
                anypages? 0=
                if      orighndl hclose drop
                        exit                    \ ***** EXITS HERE *****
                then
                savecursor savescr >hilight cursor-off
                5 4 75 7 box&fill
                ."  Saving changes"
                7 6 at >text 73 sp>col
                7 6 at
                " _TEMP.$$1" ">$ savehndl $>handle
                savehndl hcreate
                if      orighndl hclose drop    \ then close old file
                        5 8 75 10 box&fill >hilight
                        9 9 at ."  Couldn't create file, press a key"
                        beep key drop
                        restscr
                        restcursor
                        true                    \ failed flag
                        EXIT                    \ ***** EXITS HERE *****
                then
                zeromem                         \ clear all pages from mem
                false   totpages 0
                do      i saveapage dup ?leave
                loop
                dup if ."  Failed, press a key" beep key drop then
                orighndl hclose drop            \ then close old file
                savehndl hclose drop            \ and  close new file
                if      restscr
                        restcursor
                        true                    \ failed flag
                        EXIT                    \ leave if save failed
                then                            \ ***** EXITS HERE *****
                delswapfile
                orighndl savehndl $>handle              \ copy of file
                " BAK" ">$ savehndl $>ext               \ make fl BAK
                savehndl hdelete drop                   \ del old BAK
                orighndl savehndl hrename drop          \ make it BAK
                " _TEMP.$$1" ">$ savehndl $>handle      \ temp nameset
                savehndl orighndl hrename               \ temp to name
        [long]  if      >hilight
                        16 10 64 15 box&fill
                        ."  The filename specified could not be created!"
                        bcr
                        ."   The edit was saved to the file  _TEMP.$$1  "
                        bcr bcr >hilight2
                        ."  Press the ESC key to acknowledge" 63 sp>col
                        33 10 at
                        ."    WARNING!   "
                        begin beep key 27 = until
                        >text           true
                else    5 tenths        false
                then
                restscr
                restcursor
                off> anypages? off> ?full ;

: ?.full        ( -- )
                ?full
        [long]  if      dopage
                        savecursor cursor-off
                        >hilight
                        19 4 61 11 box&fill
                        ."  There is not enough disk space to save"
                        bcr
                        ."  any changes made to this file."
                        bcr bcr
                        ."  ****** Switching to BROWSE mode ******"
                        bcr bcr >hilight2
                        ."  Press the ESC key to acknowledge" 60 sp>col
                        33 4 at
                        ."    NOTICE!   "
                        begin beep key 27 = until
                        >text
                        on> ?browse
                        restcursor
                then    ;

: svfile        ( -- )          \ save any changes from file to disk
                pagesaveall drop                \ save current file
                orighndl hopen                  \ try to open the file
                !> ?newfile                     \ don't care though, will make
                                                \ the file later if needed
                setuppages
                -1 !> page1#                    \ a garbage page, forces read
                fhome
                markoff
                ?.full ;

: lopen         ( -- )          \ open a new file
                orighndl temphndl $>handle
                1 1 at >hilight ."  File to open:" veeol
                >hilight2
                on> autoclear
                16 1 temphndl 61 lineeditor     \ get file from user
                >text
                0= temphndl c@ 0= or ?exit      \ leave if canceled
                                                \ or null length
                                                \ ***** EXITS HERE *****
                temphndl count + off            \ null terminate
                orighndl temphndl over c@ 1+ caps-comp 0= ?exit
                                                \ if same file, exit
                                                \ ***** EXITS HERE *****
                temphndl count 2dup bl skip nip - nip   \ -- number of blanks
                temphndl count rot /string temphndl place \ remove blanks
                temphndl hopen                          \ try to open it
                !> ?newfile                     \ don't care though, will make
                                                \ the file later if needed
                pagesaveall                     \ save current file
        if      orighndl hopen                  \ try to open the file
                !> ?newfile                     \ don't care though, will make
                                                \ the file later if needed
        else    temphndl orighndl b/hcb cmove   \ move in new file
        then    setuppages                      \ figure page pointers
                -1 !> page1#                    \ a garbage page, forces read
                fhome                           \ goto top of file
                markoff
                .listing_file                   \ show file listing
                ?.full ;

: lwrite        ( -- )          \ Write current file to new filename
                ?full ?exit                     \ ***** EXITS HERE *****
                orighndl temphndl $>handle
                1 1 at >hilight ."  Write file to:" veeol
                >hilight2
                on> autoclear
                16 1 temphndl 61 lineeditor     \ get file from user
                >text
                0= temphndl c@ 0= or ?exit      \ leave if canceled
                                                \ or null length
                                                \ ***** EXITS HERE *****
                temphndl count 2dup bl skip nip - nip   \ -- number of blanks
                temphndl count rot /string temphndl place \ remove blanks
                temphndl count + off                    \ null terminate
                temphndl pathset drop
                orighndl temphndl over c@ 1+ caps-comp 0= ?exit
                                                \ if same file, exit
                                                \ ***** EXITS HERE *****
                temphndl hopen 0=               \ if opened, warn user
        [long]  if      temphndl hclose drop    \ close the file
                        1 1 at >hilight2
                        ."  File already exists, overwrite it? [y/N] " veeol
                        key upc 'Y' <> ?exit    \ ***** EXITS HERE *****
                        temphndl hdelete drop   \ OK, delete it
                then
                temphndl count orighndl place   \ just change name
                orighndl count + off
                on> anypages?                   \ mark as changed
                pagesaveall                     \ save current file
                orighndl hopen                  \ try to open the file
                !> ?newfile                     \ don't care though, will make
                                                \ the file later if needed
                setuppages                      \ figure page pointers
                -1 !> page1#                    \ a garbage page, forces read
                fhome                           \ goto top of file
                markoff
                .listing_file  ;                \ show file listing

: veeol_cr_bar   ( -- )
                veeol >hilight ." ³" cr ." ³" >text ;

: do_zprint    ( -- )          \ copy current file to printer
                " COPY "     tib  place
                orighndl count tib +place
                "  PRN>NUL"  tib +place
                tib $sys drop
                ^L pemit  ;                     \ send a FORMFEED

: zprint        ( -- )          \ print current file
                1 1 at
                ?printer.ready          \ and printer is online
                if      >hilight  ."  Printing .... " veeol
                        do_zprint
                else    >hilight2 ."  *** Printer is OFFLINE ***" veeol
                        beep    1 seconds
                then    >text ;

: dodos         ( -- )          \ shell out to DOS
                savecursor savescr cls
                cr ." Type EXIT to continue editing" cr
                tib off tib $sys drop
                restscr restcursor ;

: markstart     ( -- )          \ set mark start
                slineoff pagebytes /mod page1# + !> pagest !> offsetst
                slineoff nextline
                         pagebytes /mod page1# + !> pageed !> offseted
                srow    !> offsetrow
                curline 2@ offsetline 2!
                on> marking ;

: %markend      ( -- )          \ set the end of a marked area
                page1# pagebytes um* slineoff 0 d+
                pagest pagebytes um* offsetst 0 d+ 1. d+ d<
                if      slineoff          pagebytes
                        /mod page1# + !> pagest !> offsetst
                        srow    !> offsetrow
                        curline 2@ offsetline 2!
                else    slineoff nextline pagebytes
                        /mod page1# + !> pageed !> offseted
                then    ;

: markend       ( -- )          \ set the end of a marked area
                %markend
                off> marking
                on> marked ;                    \ we have marked text

: ?markend      ( -- )          \ finish marking text
                marking
                if      %markend
                then    ;

: marktgl       ( -- )          \ marked text toggle function
                marking marked or
                if      marked
                        if      markoff
                                1 1 at >hilight
                                ."   *** Mark cleared ***" veeol
                                3 tenths
                        else    markend
                        then
                else    markstart
                then    ;

: make_temp     ( -- f1 )       \ open the temp cut file return true if error
                ?shiftkey
                if      1 1 at >hilight ."  Copy to:" veeol
                        >hilight2
                        on> autoclear
                        10 1 savehndl 61 lineeditor     \ get file from user
                        >text
                        0= savehndl c@ 0= or    \ leave if canceled
                        if      true exit       \ or null length
                                                \ ***** EXITS HERE *****
                        then
                else    " TEMP.TMP" ">$ savehndl $>handle
                then    savehndl hcreate ;

: open_temp     ( -- f1 )       \ open the temp cut file return true if error
                ?shiftkey
                if      1 1 at >hilight ."  Paste from:" veeol
                        >hilight2
                        on> autoclear
                        13 1 savehndl 61 lineeditor     \ get file from user
                        >text
                        0= savehndl c@ 0= or    \ leave if canceled
                        if      true exit       \ or null length
                                                \ ***** EXITS HERE *****
                        then
                else    " TEMP.TMP" ">$ savehndl $>handle
                then    savehndl hopen ;

: copypage      ( n1 -- )       \ copy one page to TEMP
                !> page1#                               \ set page to copy
                9 6 at ." Copying text pages " page1# u.
                page1fill                               \ read the first page
                pageed  page1# =                        \ if on last page
                if      pages& offseted                 \ write end page
                else    pagest  page1# =                \ if on first page
                        if      pages& offsetst +
                                page1len offsetst -     \ write first page
                        else    pages& page1len         \ write middle page
                        then
                then    savehndl hwrite drop ;          \ actually write page

: %fcopy        ( -- )          \ copy marked text
                putline                         \ save current line
                pagessave                       \ save pages
                getline                         \ reget line incase
                marking                         \ were we marking?
                if      markend                 \ finish marking
                then
                marked 0= ?exit                 \ leave if no mark
                                                \ ***** EXITS HERE *****
                make_temp ?exit                 \ open temp file
                                                \ ***** EXITS HERE *****
                page1#   pageoff 2>r            \ save where we were
                slineoff srow    2>r
                zeromem
                >hilight 5 4 75 7 box&fill
                ."  Copy marked text to: " savehndl count type
                7 6 at >text 73 sp>col
                pageed pagest <>
                if      pageed 1+ pagest        \ copy text
                        ?do     i copypage
                        loop                    \ loop for all pages
                else    pagest !> page1#
                        page1fill
                        pages& offsetst +       \ start
                        offseted offsetst - 0max \ for length
                        savehndl hwrite drop
                then
                savehndl hclose drop             \ close temp file
                2r> !> srow    !> slineoff
                2r> !> pageoff #page-refill
                >text
                getline ;

: fcopy         ( -- )          \ copy marked block of test lines
                %fcopy
                markoff ;                       \ clear marking

: adjust-pages  ( -- )          \ adjust the number of line in this page
                                \ and the number of lines in document
\               0 pages& page1len
\               page1# >lines@ >r
\               begin   $0A scan dup                    \ calculate lines
\               while   1 /string                       \ in page
\                       2>r 1+ 2r>                      \ bump lines count
\               repeat  2drop page1# >lines!            \ set new line count
\               totines 2@ page1# >lines@ r> - s>d d+ totines 2!
                page1# >bytes@ 0=
                if      totpages 1- 1 max !> totpages
                then    ;

: cutpage       ( n1 -- )       \ cut one page out of file
                dup !> page1#                           \ set page to cut
                    !> lastmem
                9 6 at ." Cutting text pages " page1# u.
                pageed  page1# =                        \ if on last page
        [long]  if      page1fill                       \ read the first page
                        pages& offseted +               \ write end page
                        pages&
                        page1len offseted - 0max dup>r cmove
                        r@ page1# >bytes!
                        r@ !> page1len
                        r> !> pageslen
                        on> updateflg                   \ set page update flg
                        pagessave
                        dtotbytes 2@ offseted 0 d- dtotbytes 2!
                        adjust-pages
        [long]  else    pagest  page1# =                \ if on first page
        [long]          if      page1fill               \ read the first page
                                dtotbytes 2@ page1len offsetst - 0 d-
                                dtotbytes 2!
                                offsetst page1# >bytes!
                                offsetst !> page1len
                                offsetst !> pageslen
                                on> updateflg           \ set page update flg
                                pagessave
                                adjust-pages
        [long]          else    dtotbytes 2@ page1# >bytes@ 0 d- dtotbytes 2!
                                0 page1# >bytes!        \ cut a middle page
                                totines  2@ page1# >lines@ 0 d- totines 2!
                                0 page1# >lines!
                                page1# swapposition     \ mark as in swapfile
                                totpages 1- 1 max !> totpages
                        then
                then    ;

: %fcut         ( -- )          \ cut marked text
                marking                         \ were we marking?
                if      markend                 \ finish marking
                then
                marked 0= ?exit                 \ leave if no mark
                                                \ ***** EXITS HERE *****
                zeromem
                >hilight 5 4 75 7 box&fill
                ."  Cut marked text"
                7 6 at >text 73 sp>col
                pageed pagest <>
                if      pageed 1+ pagest        \ copy text
                        ?do     i cutpage
                        loop                    \ loop for all pages
        [long]  else    pagest !> page1#
                        pagest !> lastmem
                        page1fill
                        pages& offseted +               \ start
                        pages& offsetst +
                        page1len offseted - 0max dup>r  \ for length
                        cmove
                        r@ page1# >bytes!
                        r@ !> page1len
                        r> !> pageslen
                        on> updateflg           \ set   page update
                        pagessave
                        adjust-pages
                        dtotbytes 2@ offseted offsetst - 0 d- dtotbytes 2!
                then
                maxpages 3 - totpages <
                if      off> ?full
                then
                offsetst dup !> slineoff !> pageoff
                pagest #page-refill
                on> updateflg
                pagessave
                off> srow
                offsetrow 0
                ?do     %+sline
                        %-scrlline
                loop    offsetline 2@  curline 2!       \ back to start line
                recalc-lines
                >text   getline ;

: fcut          ( -- )          \ cut a marked block of text lines
                ?full ?exit                     \ ***** EXITS HERE *****
                ?ctrlkey 0=             \ bypass copy if CTRL held down
        if      %fcopy
        then    %fcut
                markoff ;

: fpaste        ( -- )          \ paste text from TEMP
                ?full ?exit                     \ ***** EXITS HERE *****
                open_temp ?exit                 \ ***** EXITS HERE *****
                putline
                >hilight 5 4 75 7 box&fill
                ."  Pasting from: " savehndl count type
                7 6 at >text 73 sp>col
                pagessave
                savehndl endfile pagebytes um/mod nip
                0 over
                do      9 6 at ." Pasting text pages " dup i - u.
                        pageslen lowwater u>
                        if      lastmem >bytes@  \ get the pages length
                                -pageslen!       \ reduce length of memory
                                decr> lastmem    \ reduce # of pages in mem
                        then
                        i pagebytes um* savehndl movepointer
                        calc& pagebytes savehndl hread >r
                        pages& slineoff + dup r@ +              \ from to
                        pageslen slineoff - cmove>              \ move down
                        calc& pages& slineoff + r@ cmove        \ move new in
                        r> +pageslen!                           \ adj length
                        on> updateflg                           \ mark changed
                        pagessave
                        totpages maxpages 3 - >=  \ if page buffers are full
                        if      on> ?full       \ then notify user
                                leave           \ and don't save changes
                        then
            -1 +loop    drop
                savehndl hclose drop
                recalc-lines
                getline ;

: %help        ( -- )          \ show some help information
                35 0 at   >hilight2 ."   HELP!  "
                0 1 at  >hilight ." ³" >text                    veeol_cr_bar
        ."      F1 = Display this help screen"        45 sp>col ." ^Home = Top of file"               veeol_cr_bar
        ."      F6 = Specify and find text in file"   45 sp>col ."  ^End = End of file"               veeol_cr_bar
        ."  Alt-F6 = Find next occurance of text"     45 sp>col ."    F2 = Top of screen"             veeol_cr_bar
        ."      F8 = Specify replace text after find" 45 sp>col ."    F4 = Bottom of screen"          veeol_cr_bar
        ."  Alt-F8 = Replace next occurance of text"  45 sp>col ."      = Up   one line"             veeol_cr_bar
        ."     F10 = Save changes and leave VED"      45 sp>col ."      = Down one line"             veeol_cr_bar
        ."     ESC = Discard changes and leave VED"   45 sp>col ."  PgUp = Up   22 lines in file"     veeol_cr_bar
        ."      ^O = Specify and OPEN a new file"     45 sp>col ."  PgDn = Down 22 lines in file"     veeol_cr_bar
                                                                                                      veeol_cr_bar
                4 sp>col >hilight
        ."  Set&save fg/bg screen colors for text=F3/F4 border=F5/F6 hilight=F7/F8 "
                >text                                           veeol_cr_bar
                                                                veeol_cr_bar
                23 sp>col >hilight2
                ."  VED is a PUBLIC DOMAIN PROGRAM " >text      veeol_cr_bar
                                                                veeol_cr_bar
."     VED was written using TCOM, a Target COMpiler for the Forth computer"
                                                                veeol_cr_bar
."     language. TCOM is a PUBLIC DOMAIN PROGRAM written by Tom Zimmer."
                                                                veeol_cr_bar
."     TCOM is available for a $60 donation, from:  "
                          >hilight2 ."  Tom Zimmer           " >text
                                                                veeol_cr_bar
                50 sp>col >hilight2 ."  292 Falcato Drive    " >text
                                                                veeol_cr_bar
                50 sp>col >hilight2 ."  Milpitas, Ca. 95035  " >text
                                                                veeol_cr_bar
                50 sp>col >hilight2 ."  Home: (408) 263-8859 " >text
                                                                veeol_cr_bar
                50 sp>col >hilight2 ."  Work: (415) 327-8800 " >text
                                                                veeol_cr_bar
                                                                veeol_cr_bar
                4 19 at >hilight2 ."  Compiled: "
                veddate 2@ form-date count type ."  at "
                vedtime 2@ swap split dup 11 > dup>r if 12 - then join swap
                           form-time count drop 5 type
                r> if ."  PM " else ."  AM " then
                4 20 at ."  VED can edit files upto: "
                pagebytes limitpages um* big. ." Bytes."
                4 21 at ."  Available disk space   : "
                orighndl >nam c@ bl or 96 -
                getdiskfree * um* big. ." Bytes."
                >text
                0 23 at
                >hilight ." À Press " >hilight2 ."  F1 "
                >hilight ."  to return to editing "
                leeol ." Ù" >text ;

: dohelpkey     ( c1 -- )       \ help keys while on help screen
                case
        ( F3 )          189 of  txtfg 1+ 15 and !> txtfg on> hif  endof
        ( F4 )          190 of  txtbg 1+ 15 and !> txtbg on> hif  endof
        ( F5 )          191 of  hi1fg 1+ 15 and !> hi1fg on> hif  endof
        ( F6 )          192 of  hi1bg 1+ 15 and !> hi1bg on> hif  endof
        ( F7 )          193 of  hi2fg 1+ 15 and !> hi2fg on> hif  endof
        ( F8 )          194 of  hi2bg 1+ 15 and !> hi2bg on> hif  endof
                                drop
                endcase ;

: lhelp         ( -- )
                savecursor cursor-off
                begin   .listing_file
                        %help
                        key dup 187 <>          \ 187 = F1
                while   dohelpkey
                repeat  drop
                restcursor .lastline ;

: lerr  ;       \ do nothing keys

: lctrl         ( n1 --- )              \ control key table
                exec:
\ @      A        B          C        D        E        F        G
lerr     lwrd     lerr       lpgdn    +scol    -sline   rwrd     delchar
\ H      I        J          K        L        M        N        O
backdel  ltab     dodos      lerr     lerr     pagecr   lsplit   lopen
\ P      Q        R          S        T        U        V        W
lerr     lerr     lpgup      -scol    lwdel    svfile   instgl   -scrlline
\ X      Y        Z          ESC
+sline   delline  +scrlline  lerr     lerr     lerr     lerr     lerr  ;

: lfunc         ( n1 --- )              \ function key table
                126 - 0max exec:
\ junk    CBS Control Backspace (127)
  lerr    delchar
\ A-9     A-0       A -       A =       CPGUP     133       134       135
  lerr    lerr      lerr      lerr      -scrlline lerr      lerr      lerr
\ 136     137       138       139       140       141       142       BACKTAB
  lerr    lerr      lerr      lerr      lerr      lerr      lerr      lbtab
\ A-Q     A-W       A-E       A-R       A-T       A-Y       A-U       A-I
  fhome   lwrite    lerr      lerr      lerr      lerr      lerr      lerr
\ A-O     A-P       154       155       156       157       A-A       A-S
  lerr    zprint    lerr      lerr      lerr      lerr      lerr      lerr
\ A-D     A-F       A-G       A-H       A-J       A-K       A-L       167
  lerr    lerr      lgoto     lerr      joinline  lerr      lerr      lerr
\ 168     169       170       171       A-Z       A-X       A-C       A-V
  lerr    lerr      lerr      lerr      fend      fcut      fcopy     fpaste
\ A-B     A-N       A-M       179       180       181       182       183
  lerr    lerr      lerr      lerr      lerr      lerr      lerr      lerr
\ 184     185       186       F1        F2        F3        F4        F5
  lerr    lerr      lerr      lhelp     scrtop    marktgl   scrbot    lerr
\ F6      F7        F8        F9        F10       197       198       HOME
  lfind   lerr      lrepl     lerr      lerr      lerr      lerr      lhome
\ UP      PDUP      202       LEFT      204       RIGHT     206       END
  -sline  lpgup     lerr      -scol     lerr      +scol     lerr      lend
\ DOWN    PGDN      INS       DEL       SF1       SF2       SF3       SF4
  +sline  lpgdn     instgl    delchar   lerr      lerr      lerr      lerr
\ SF5     SF6       SF7       SF8       SF9       SF10      CF1       CF2
  lerr    lbfind    lerr      lrepall   lerr      lerr      lerr      lerr
\ CF3     CF4       CF5       CF6       CF7       CF8       CF9       CF10
  lerr    lerr      lerr      lerr      lerr      lerr      lerr      lerr
\ AF1     AF2       AF3       AF4       AF5       AF6       AF7       AF8
  lerr    lerr      lerr      lerr      lerr      lafind    lerr      larepl
\ AF9     AF10      242       CLEFT     CRIGHT    CEND      CPGDN     CHOME
  lerr    lerr      lerr      lwrd      rwrd      fend      +scrlline fhome
\ A-1     A-2       A-3       A-4       A-5       A-6       A-7       A-8
  lerr    lerr      lerr      lerr      lerr      lerr      lerr      .pages  ;

: dolistkey     ( c1 -- )       \ handle keys entered by user
                dup bl  '~' between if  pageins exit then       \ ascii
                dup bl  <           if  lctrl   exit then       \ control
                dup 127 255 between if  lfunc   exit then       \ function
                drop lerr ;                                     \ garbage

: emptykbd      ( --- )         \ empty any keyboard typeahead
                begin   0 $41A @L
                        0 $41C @L - abs 2 >     \ keyboard depth > 1 key
                while   bioskey drop
                repeat  ;

: ?savechanges  ( -- <c1> f1 ) \ prompt for saving changes if any made
                anypages?
        [long]  if      begin   key?
                        while   key drop
                        repeat
                        savecursor cursor-off >hilight
                        10 4 70 10 box&fill
                        bcr
                        ."      Do you want to save the changes made to this file?"
                        bcr bcr
                        ."        Press:   Y=YES,   N=NO,   ESC=continue editing"
                        begin   key upc
                                case    'Y' of  196  true  true endof
                                        'N' of  241  true  true endof
                                         27 of       false true endof
                                                drop false beep
                                endcase
                        until
                        restcursor
                        dopage
                else    0 true
                then    ;

: pageshow      ( -- f1 )       \ process user input & test for done
                                \ return trye if exited with F10
                .lastline
        begin
                begin   dopage                  \ update the screen
                        pagecursor              \ show the cursor
                        emptykbd                \ discard all but one key
                        pagekey                 \ get a key from user
( ESC )                 dup   27 <>             \ while not ESC
( F10 )                 over 196 <> and         \ and not F10
( Alt-F10 )             over 241 <> and         \ and not Alt-F10
                while   .lastline               \ update last screen line
                        0rbar                   \ clear right bar character
                        dolistkey               \ process the users key
                        ?markend
                repeat  dup 27 =
                if      drop
                        ?savechanges
                else    true
                then
        until   196 =
                putline ;               \ save changes to line

: pageopen      ( | name -- )   \ read the first page into buffer PAGE1BUF
                bl word c@ 0=                   \ get file from DOS cndline
                if      " UNTITLED" ">$         \ if no name given, "UNTITLED"
                else    here                    \ else use given name
                then    orighndl $>handle       \ move file to orighndl
                orighndl hopen                  \ try to open the file
                !> ?newfile                     \ don't care though, will make
                                                \ the file later if needed
                orighndl handle>ext 1+ " BAK" caps-comp 0=
                orighndl handle>ext 1+ " $$1" caps-comp 0= or
                orighndl handle>ext 1+ " $$2" caps-comp 0= or
                abort" Sorry, CANNOT edit a .BAK, .$$1 or .$$2 file!"
                orighndl swaphndl $>handle      \ copy to save handle
                " BAK" ">$ swaphndl $>ext       \ make extention .BAK
                swaphndl hdelete drop           \ delete the .BAK file
                " $$2" ">$ swaphndl $>ext       \ make extention .$$$
                swaphndl hcreate drop ;         \ create the SWAP file

: calclines     ( -- )          \ calculate the number of lines in file
                calculating? 0= ?exit           \ ***** EXITS HERE *****
                incr> calccnt
                calccnt 1023 and ?exit          \ ***** EXITS HERE *****
                pageslen
                save> page1#
                totpages calcpage 40 + min calcpage
        [long]  ?do     calc& i 1pageread
                        i >lines@ 0 totines 2@ d+ totines 2!
                        i !> calcpage
                        i 127 and 0=
                        if      dup !> pageslen
                                dostatus
                                pagecursor
                        then
                        key?  ?leave
                loop    incr> calcpage
                restore> page1#
                !> pageslen
                totpages 1- calcpage <=
                if      off> calculating?
                then    dostatus pagecursor ;

: pagekey       ( -- c1 )       \ get a key from user
                begin   key? 0=
                while   calclines
                repeat
                bioskey dup 127 and 0=
                if      flip dup 3 =
                        if      drop 0          \ allow a null
                        else    127 and 128 or
                        then
                else    255 and
                then    ;

code row/col!   ( -- )
                push ds
                mov ax, # $40           \ absolute segment $40:00
                mov ds, ax              \ goes into ds
                mov bl, $4A             \ get the # of cols from    $40:$4A
                mov cl, $84             \ get the # of rows from    $40:$84
                pop ds
                mov &> cols bl
                cmp cl, # 24
              < if      mov cl, # 25    /NOSTACK1 \ at least 25 rows
                else    inc cl
                then
                mov &> rows cl
                ret     end-code

: VED           ( | name -- )   \ this is the VIRTUAL EDITOR
                blinkoff
                ?vmode 7 =                      \ setup hilighting for vmode
                if      ['] >rev  is >hilight   \ for mono, use reverse
                        ['] >rev  is >hilight2
                        ['] >norm is >text
                else    ['] >hi1  is >hilight   \ for color
                        ['] >hi2  is >hilight2
                        ['] >txt  is >text
                        row/col!
                        rows 4 - !> displaylines
                then    >norm
                pageopen                        \ open the file
                setuppages                      \ count the pages
                savecursor cursor-on            \ save cursor status
                big-cursor
                -1 !> page1#                    \ a garbage page, forces read
                fhome                           \ goto first page
                markoff                         \ clear marked lines
                lfindbuf off                    \ clear text find buffer
                lreplbuf off                    \ clear text replace buffer
                temphndl clr-hcb                \ clear the temp file handle
                savehndl clr-hcb                \ and the save file handle
                .listing_file                   \ show file we are listing
                >text                           \ select normal attributes
                .emptyscr
                .lastline
                lhfind                          \ find word in first column
                ?.full
     begin      pageshow                        \ go list the file to user
[long]  if      anypages?
           if   pagesaveall                     \ save current file
                0= dup>r                        \ pass/fail flag
             if 25 0 at >hilight2 ." Ä SAVED Ä" \ clear changed message
             else
                orighndl hopen                  \ try to open the file
                !> ?newfile                     \ don't care though, will make
                                                \ the file later if needed
                setuppages                      \ figure page pointers
                -1 !> page1#                    \ a garbage page, forces read
                fhome                           \ goto top of file
                markoff
                .listing_file
             then
           else delswapfile                     \ delete the swap file
                true >r                         \ flag as done
           then
        else
                delswapfile                     \ delete the swap file
                anypages?                       \ only if there were changes
            if  25 0 at >hilight2 ." DISCARDED" \ clear changed message
            then true >r                        \ flag as done
        then    r>                              \ recover the flag
     until      restcursor 0 rows 2- at         \ goto bottom of screen
                orighndl hclose drop            \ and close the file
                                                \ as we are leaving now
                ?save_colors cursor-on ;

: main          ( -- )          \ perform needed program setup for TCOM
                DECIMAL                         \ always select decimal
              lflen 2+ ds:alloc !> lfindbuf     \ search buffer
              lflen 2+ ds:alloc !> lreplbuf     \ replace buffer
                 260   ds:alloc !> linebuffer   \ line editing buffer
          pagesbytes   ds:alloc !> pages&       \ allocate the page buffers
           pagebytes   ds:alloc !> calc&        \ line calculation buffer
                INIT-CURSOR                     \ get intial cursor shape
                MARGIN_INIT                     \ initialize margins & TAB
                ?DS: SSEG !                     \ init search segment
                caps on                         \ case INSENSITIVE
                vmode.set                       \ video direct display
                $0000 SET_MEMORY                \ default to min code space
                DOS_TO_TIB                      \ move command tail to TIB
                COMSPEC_INIT                    \ init command specification
                VED      ;

