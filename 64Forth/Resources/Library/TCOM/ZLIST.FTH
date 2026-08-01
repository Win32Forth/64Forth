\\ ZLIST.SEQ             A file LISTer           written by Tom Zimmer
.options /opt /noinit           \ compiler directives for this program

  ZLIST is a simple file lister, it allows viewing and searching through
text files of any length.

  ZLIST IS PUBLIC DOMAIN, ALL RESPONSIBILITY FOR ITS USE IS ASSUMED BY
YOU THE USER.

  ZLIST was written in the Forth computer language, and compiled to pure
CALL threaded object code by TCOM.

  TCOM is a PUBLIC DOMAIN, optimizing (space & speed) Target COMpiler
that generates CALL threaded object code ".COM" files.

  This 18k source file compiles into a 12k .COM file in less than 10 seconds
on a 16mhz 80386 computer.

  TCOM was written by Tom Zimmer.

  If you would like to obtain a copy of TCOM, send a donation to $60 to:

                Tom Zimmer
                292 Falcato Drive
                Milpitas, Ca. 95035     Home: (408) 263-8859
                                        Work: (415) 327-8800

-------------------------------------------------------------------------

Compiling:      TCOM ZLIST <Enter>              \ you will need TCOM
                                                \ to do this.

Usage:          ZLIST <filename> <optional_word_to_find> <Enter>

        Press F1 while in ZLIST, for help if you need it.

Note:   Words that start with the "%" symbol in column one of the file
        being listed will not be displayed. This allows formatting your
        files with these special help section start words, which you
        will search for, but will not be displayed to the user.

        You can actually specify any word on the command line after the
        filename, and ZLIST will find it and place it on the second
        line of the display.

-------------------------------------------------------------------------

{

\fpc    ' ?cs: alias ?ds:

\fpc    ONLY FORTH ALSO DEFINITIONS HIDDEN ALSO

\ **********************************************************************
\ define and reference these following color words NOW, to force them
\ to be allocated in memory now, and to be contiguous.
\ **********************************************************************

here    /nostack

blue    value hi1bg     hi1bg drop
ltgreen value hi1fg     hi1fg drop
yellow  value hi2bg     hi2bg drop
black   value hi2fg     hi2fg drop
dkgray  value txtbg     txtbg drop
white   value txtfg     txtfg drop
ltcyan  value hi4fg     hi4fg drop
black   value hi4bg     hi4bg drop

here swap - constant color_length

\ **********************************************************************

16384   constant listlimit      \ file buffer size limit
12288   constant listhi         \ hi water mark for buffer fill
 4096   constant listlo         \ lo water mark for buffer fill
   22   value    displaylines   \ number of lines to display on screen
   24   value    urows          \ user specified number of rows

handle listhndl                 \ current file handle
handle listhndl2                \ new file handle

\ -------------------------------------------------------------------------
\ Some values needed by program.
\ I like values as I think they are more readable than variables. T.Z.

0 value hif                     \ hilight colors have been modified
0 value listblk                 \ 4k block number of lowest block in memory
0 value listlen                 \ quantity of text in buffer
0 value listoff                 \ offset in buffer of top line of display
0 value listoffmax              \ highest allowable line in this file
0 value listblkmax              \ highest allowable block number
0 value listbuf                 \ pointer to 16k text buffer
0 value listscroll              \ horizontal scrolling offset
0 value lfindbuf                \ search text buffer
0 value lfindoff                \ column offset where text last found
0 value lfound                  \ was text found flag
0 value lfound1st
0 value lfcnt
0 value ?lst
0 value dest_line#              \ destination line number for /LINE
0 value doblock?

defer >hilight                  \ hilight defered words
defer >hilight2
defer >text
defer >hilight4

\ -------------------------------------------------------------------------

: >hi1          ( -- )          \ hilight one, for status lines
                hi1bg >bg hi1fg >fg ;

: >hi2          ( -- )          \ hilight two, for search found text
                hi2bg >bg hi2fg >fg ;

: >txt          ( -- )          \ normal text
                txtbg >bg txtfg >fg ;

: >hi4          ( -- )          \ hilight four, for comment lines
                hi4bg >bg hi4fg >fg ;

: ?save_colors  ( -- )
                hif 0= ?exit
                me@ me$ listhndl $>handle
                read-write listhndl hopen ?exit
                ?ds: ?cs: - $10 * $100 - &> hi1bg + 0   \ offset into file
                listhndl movepointer                    \ adj file pointer
                &> hi1bg color_length listhndl hwrite drop
                                                        \ write colors
                listhndl hclose drop ;

: .cmdhelp      ( -- )
                cr
." ZLIST is a file browser written by Tom Zimmer, updated 1994, public domain." cr cr
."   Options: ZLIST {/?} <filename> {/ROWS <#rows>} {[/LINE <line#>] or [word]}" cr
."                   /? = display this help information" cr
."             filename = name of the file to browse" cr
."                #rows = number of screen rows to use" cr
."                line# = number of file line to show on top display line" cr
."                word  = word to search for in filename"
                cr cr
."   Additional help on usage is available while in ZLIST by pressing F1."
                cr ;

: seeol         ( -- )          \ erase with spaces to end of line
                cols #out @ - 1- 0max spaces ;

: leeol         ( -- )          \ erase to end of line
                cols #out @ - 1- 0max 0 ?do  ." Ä"  loop    ;

: ?comment_color ( a1 n1 -- a1 n1 f1 )
                false
                ?lst 0= ?exit                   \ leave if /LST not enabled
                listscroll ?exit                \ leave if horizontal scrolled
                over 14 < ?exit                 \ leave if short line
                drop                            \ discard the false flag
                over dup  5 + c@   $20 =        \ blank in col 5
                over     13 +  @ $2020 = and    \ and blanks in col 13 & 14
                swap     15 +  @ $2020 = and ;  \ and blanks in col 15 & 16

0 value coltotal

: adj&clip      ( a1 n1 -- a1 n2 )      \ clip text to the window width
                coltotal
                if      coltotal over <
                        if      coltotal /string
                                off> coltotal
                        else    negate +!> coltotal 0
                        then
                then    #out @ + cols 1- min #out @ - ;

: .blk/line     ( a1 n1 -- a1 n1 )      \ show the block and line number
                dup                     \ if lines remaining, show count
                if      save> base hex
                        listlen over - 1024 /mod
                        listblk 4 * + 4 u.r 64 / 3 .r 2 spaces
                        restore> base
                else    9 spaces        \ else just show blanks
                then    ;

: grays         ( n1 -- )
                8 /mod 0
                ?do     " °°°°°°°°" type
                loop    " °°°°°°°°" rot min type ;

: .first_line   ( a1 n1 -- a2 n2 )      \ if search text found,
                                        \ bolden first line
                >hilight ." ³" >text
                2dup doblock?
                if      .blk/line >hilight ." ³" >text space
                        64 /string 2dup 2>r nip -
                else    $0A scan 2dup 1 /string 2>r nip - 1- 0max
                then
                over c@ '%' =
                if      2dup bl scan 2dup 2>r nip - spaces drop 2r>
                then
                ?comment_color >r
                lfound1st
        [long]  if      off> lfound1st
                        listscroll /string
                        listscroll lfindoff cols 1- > or
                        r@ lfindoff 24 < and or
                        if      >hilight2
                                cols 2- min
        [long]          else    r@
                                if      24 /string >hilight4
                                then    cols 2- min
                                over lfindoff r@ 24 and - 0max type
                                lfindoff r@ 24 and - 0max /string >hilight2
                                over lfindbuf c@ type
                                lfindbuf c@ /string
                                r@
                                if      >hilight4
                                else    >text
                                then
                        then    type
        [long]  else    r@
                        if      24 /string >hilight4
                        then    listscroll !> coltotal
                        begin   2dup 9 scan dup         \ look for tab
                        while   2dup 2>r                \ save remainder
                                nip - adj&clip type     \ output preceeding
                                #out @ 1- listscroll coltotal - +
                                8 mod 8 swap - 16 swap adj&clip SPACES drop
                                                        \ expand to tab pos
                                 \ -- This 16 is a dummy parameter needed by
                                  \   ADJ&CLIP, we discard it after expanding
                                   \  the TAB
                                2r> 1 /string           \ remove the TAB
                        repeat  2drop adj&clip type     \ type line remainder
                then    seeol cr r>drop
                2r> ;

: .one_line     ( a1 n1 -- a2 n2 )      \ display one line of screen
                >hilight ." ³" >text
                dup 0=
        if      doblock?
                if      9 grays >hilight ." ³" >text
                then    cols #out @ - 1- 0max grays
[long]  else    2dup doblock?
                if      .blk/line >hilight ." ³" >text space
                        64 /string 2dup 2>r nip -
                else    $0A scan 2dup 1 /string 2>r nip - 1- 0max
                then    over c@ '%' =
                if      2dup bl scan 2dup 2>r nip - spaces drop 2r>
                then
                ?comment_color
                if      24 /string >hilight4
                then
                listscroll !> coltotal
                begin   2dup 9 scan dup                 \ look for tab
                while   2dup 2>r                        \ save remainder
                        nip - adj&clip type             \ output preceeding
                        #out @ 1- listscroll coltotal - +
                        ( tabsize @ ) 8 mod ( tabsize @ ) 8 swap -
                        16 swap adj&clip SPACES drop    \ expand to tab pos
                         \ -- This 16 is a dummy parameter needed by ADJ&CLIP,
                           \  we discard it after expanding the TAB
                        2r> 1 /string                   \ remove the TAB
                repeat  2drop adj&clip type             \ type line remainder
                seeol 2r>
        then    cr ;

: dolist        ( -- )          \ list current displaylines of file
                0 1 at
                listbuf listlen listoff /string
                .first_line
                displaylines 1- 0               \ display rest of screen
                do      .one_line
                loop    2drop ;

: .emptyscr     ( -- )          \ list current displaylines of file
                0 1 at
                listbuf 0
                .first_line
                displaylines 1- 0               \ display rest of screen
                do      .one_line
                loop    2drop ;

: .rbar         ( -- )          \ display the right bar with file offset
                savecursor >hilight
                listhndl endfile nip
                if      listblk 4096 *d listoff 0 d+ 100 mu/mod rot drop
                        listhndl endfile 100 mu/mod rot drop
                        displaylines um/mod nip 1 max
                else    listblk 4096 *d listoff 0 d+
                        listhndl endfile displaylines um/mod nip 1 max
                then
                um/mod nip 1+ displaylines ( 1+ ) min dup 1
                ?do     cols 1-    i at ." ³"
                loop    cols 1- over at ." Û"
                1+ displaylines 1+ swap over min
                ?do     cols 1-    i at ." ³"
                loop    restcursor ;

: %+1line       ( -- n1 )               \ forward a line in the file
                                        \ with auto buffer refilling
                listoff listhi >                \ in last 4k block
                listlen listlimit = and         \ and buffer full
        [long]  if      listbuf dup listlo + swap listhi cmove
                                                \ move back low water mark
                        listblk 4 + listlo *d listhndl movepointer
                        listbuf listhi + listlo listhndl hread
                        listhi + !> listlen
                        incr> listblk
                        listlo negate +!> listoff
                then
                listbuf listlen listoff /string
                doblock?
                if      64 /string drop
                else    $0A scan drop 1+
                then    listbuf - ;

: +1line        ( -- )          \ forward a line in file, limit forward
                                \ movement to top of last screen full in file
                %+1line
                listblk listblkmax =            \ if at end of file
                if      listoffmax umin         \ then limit to last screen
                then    !> listoff ;

: f+1line       ( -- )          \ forward a line in file, no forward limit
                %+1line !> listoff ;

: -1line        ( -- )          \ back a line in file with auto buffer
                                \ refilling
                listoff listlo <
                listblk 0> and
        [long]  if      listbuf dup listlo + listlen listlo - cmove>
                        decr> listblk
                        listblk listlo *d listhndl movepointer
                        listbuf listlo listhndl hread drop
                        listlimit !> listlen
                        listlo +!> listoff
                then
                listoff 0=
                listoff 2- 0= or
                if      off> listoff
                else    doblock?
                        if      listoff 64 - 0max !> listoff
                        else    listoff 2- listbuf over + swap
                                $0A -scan drop
                                dup c@ $0A =    \ if we found a LINEFEED
                                if      1+      \ then bump to next char
                                then    listbuf - !> listoff
                        then
                then    ;

: lpgdn         ( -- )          \ forward "displaylines" into file
                doblock?
                if      16
                else    displaylines
                then    0   do  +1line  loop
                off> lfound .rbar ;

: %lpgup        ( -- )          \ backward "displaylines" into file
                doblock?
                if      16
                else    displaylines
                then    0   do  -1line  loop  ;

: lpgup         ( -- )
                %lpgup
                off> lfound .rbar ;

: lhome         ( -- )          \ to top of file
                0 !> listblk
                0.0 listhndl movepointer
                listbuf listlimit listhndl hread !> listlen
                off> listoff
                off> listscroll
                off> lfound
                .rbar ;

: doblock_set   ( -- )          \ check to see if this is a block file
                0 0 listhndl movepointer
                listbuf listlimit listhndl hread !> listlen
                listbuf listlen $0A scan nip 0= dup !> doblock?
                if      19
                else    urows
                then    dup 2- !> displaylines rows max !> rows
                .listing_file ;

: %lend         ( -- )          \ to bottom of file, actually limited
                                \ to bottom of file minus one page full
                listhndl endfile listlo um/mod nip 3 - 0max !> listblk
                listblk listlo *d listhndl movepointer
                listbuf listlimit listhndl hread !> listlen
                listlen !> listoff
                %lpgup ;

: lend          ( -- )
                %lend
                off> lfound .rbar ;

: lleft         ( -- )          \ scroll screen left
                listscroll 0=
                if      ?lst 0= !> ?lst                 \ listing format togl
                else    listscroll 2 - 0max !> listscroll
                then    ;

: lright        ( -- )          \ scroll screen right
                listscroll 2 + listlo min !> listscroll ;

: lefthome      ( -- )          \ move full left
                off> listscroll ;

: righthome     ( -- )          \ move right 40 columns
                listscroll 10 + listlo min !> listscroll ;

: lafind        ( -- )          \ search for already entered text again
                listblk listoff
                lfound
                if      f+1line
                then    2>r
                off> lfcnt
                off> lfound
                1 1 at >hilight ."   Searching ..." seeol
                begin   lfindbuf count
                        listbuf listlen listoff /string
                        2dup    doblock?
                        if      64 /string nip -
                        else    $0A scan nip - 1- 0max
                        then    search 0=
                        listoff listlen < and
                while   drop f+1line
                        incr> lfcnt
                        lfcnt 255 and 0=
                        if      .rbar
                        then
                repeat  !> lfindoff
                1 displaylines 1+ at
                listoff listlen >=
        [long]  if      ."  Text not found " leeol beep
                        2r> !> listoff !> listblk
                        listblk listlo *d listhndl movepointer
                        listbuf listlimit listhndl hread !> listlen
        [long]  else    2r> 2drop
                        on> lfound
                        on> lfound1st
                        ."  Text found at column " lfindoff . leeol
                then    >text .rbar ;

: lfind         ( -- )          \ enter text and search for it
                1 1 at >hilight ."  Text to find:" seeol
                >hilight2
                off> stripping_bl's
                on> autoclear
                savecursor cursor-on
                16 1 lfindbuf 48 lineeditor >text       \ get text from user
                if      lafind                          \ and go find it
                then    restcursor ;

: lhfind        ( -- )          \ find word at program startup
                0 word count lfindbuf place
                begin   lfindbuf count + 1- c@ bl <     \ strip trailing ctrl
                        lfindbuf c@ 0> and              \ till empty
                while   -1 lfindbuf c+!
                repeat lfindbuf c@ 0= ?exit    \ leave if no word specified
                lafind
                lfound
                if      -1line
                        dolist
                then    off> lfound
                lfindbuf off ;

: linefind      ( -- )
                off> lfcnt
                1 1 at >hilight ."   Moving to line ..." seeol
                begin   lfcnt dest_line# <
                        listoff listlen < and
                while   f+1line
                        incr> lfcnt
                repeat  listoff 200 + listlen u>
                if      lend
                then    >text  ;

: .listing_file ( -- )          \ display the current filename
                >hilight 0  0 at
                doblock?
                if      ." Ú BLK  Ln Â Listing: "
                else    ." Ú Listing: "
                then    listhndl count type space
                leeol ." ¿" >text ;

: .lastline     ( -- )          \ show the last line of display
                 0 displaylines 1+ at >hilight
." À ESC=Quit,   ^O=Open another file,    F6=Find,   P=file to Printer,   F1=Help"
                "  ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ"
                cols #out @ - 1- 0max min type ." Ù" >text ;

: lendset       ( -- )          \ set end of file markers
                %lend                   \ goto last displayable screen
                listoff !> listoffmax   \ set max pameters for use later
                listblk !> listblkmax
                lhome ;                 \ go back to top of file

: lopen         ( -- )          \ open a new file
                1 1 at >hilight ."  File to open:" seeol
                >hilight2
                on> autoclear
                16 1 listhndl2 63 lineeditor            \ get file from user
                >text 0= ?exit                          \ leave if canceled
                listhndl2 count + off                   \ null terminate
                listhndl2 hopen 0=                      \ try to open it
        [long]  if                                      \ if it worked,
                        listhndl hclose drop            \ then close old file
                        listhndl2 listhndl b/hcb cmove  \ move in new file
                        listbuf listlimit listhndl hread \ read new file
                        !> listlen                      \ set the read length
                        off> listblk                    \ block to zero
                        recoverscr                      \
                        doblock_set     \ setup for possible block file
                        lendset                         \ set end stuff
                        .lastline
                else    0 displaylines 1+ at >hilight
                        ."  Couldn't open file!" leeol beep >text
                then    ;

: eeol_cr_bar   ( -- )
                seeol >hilight ." ³" cr ." ³" >text ;

: do_zprint    ( -- )          \ copy current file to printer
                13 pemit
                " COPY "       tib  place
                listhndl count tib +place
                "  PRN>NUL"    tib +place
                tib $sys drop
                ^L pemit  ;                     \ send a FORMFEED

: zprint        ( -- )          \ print current file
                1 1 at
                ?printer.ready          \ and printer is online
                if      >hilight  ."  Printing .... " seeol
                        do_zprint
                else    >hilight2 ."  *** Printer is OFFLINE ***" seeol
                        beep    1 seconds
                then    >text ;

: %lhelp        ( -- )          \ show some help information
                0 1 at  >hilight ." ³" >text                    eeol_cr_bar
                35 sp>col >hilight2 ."  HELP! " >text           eeol_cr_bar
                                                                eeol_cr_bar
                ."      F1 = Display this help screen"       45 sp>col
                  ." ^Home = Top of file"                       eeol_cr_bar
                ."      F6 = Specify and find text in file"  45 sp>col
                  ."  ^End = End of file"                       eeol_cr_bar
                ."  Alt-F6 = Find next occurance of text"    45 sp>col
                  ."      = Up   one line"                     eeol_cr_bar
                ."     F10 = Leave ZLIST, save color changes" 45 sp>col
                  ."      = Down one line"                     eeol_cr_bar
                ."     ESC = Leave ZLIST"                    45 sp>col
                  ."  PgUp = Up   22 lines in file"             eeol_cr_bar
                ."      ^O = Specify and OPEN a new file"    45 sp>col
                  ."  PgDn = Down 22 lines in file"             eeol_cr_bar
                12 sp>col >hilight4
                ."  F3,5,7,9=FG & Alt-F3,5,7,9=BG adjust colors while in HELP"
                >text
                                                                eeol_cr_bar
                                                                eeol_cr_bar
                21 sp>col >hilight2
                ."  ZLIST is a PUBLIC DOMAIN PROGRAM " >text    eeol_cr_bar
                                                                eeol_cr_bar
."     ZLIST was written using TCOM, a Target COMpiler for the Forth computer"
                                                                eeol_cr_bar
."     language. TCOM is a PUBLIC DOMAIN PROGRAM written by Tom Zimmer."
                                                                eeol_cr_bar
."     TCOM is available for a $60 donation, from:  "
                          >hilight2 ."  Tom Zimmer           " >text
                                                                eeol_cr_bar
                50 sp>col >hilight2 ."  292 Falcato Drive    " >text
                                                                eeol_cr_bar
                50 sp>col >hilight2 ."  Milpitas, Ca. 95035  " >text
                                                                eeol_cr_bar
                                                                eeol_cr_bar
                50 sp>col >hilight2 ."  Home: (408) 263-8859 " >text
                                                                eeol_cr_bar
                50 sp>col >hilight2 ."  Work: (415) 327-8800 " >text
                                                                eeol_cr_bar
                                                                eeol_cr_bar
                0 23 at
                >hilight ." À Press " >hilight2 ."  ESC "
                >hilight ."  to continue file viewing "
                leeol ." Ù" >text ;

: dohelpkey     ( c1 -- )
                case
        ( F3 )          189 of  hi2fg 1+ $0F and !> hi2fg on> hif  endof
        ( F5 )          191 of  hi1fg 1+ $0F and !> hi1fg on> hif  endof
        ( F7 )          193 of  txtfg 1+ $0F and !> txtfg on> hif  endof
        ( F9 )          195 of  hi4fg 1+ $0F and !> hi4fg on> hif  endof
        ( Alt-F3 )      234 of  hi2bg 1+ $0F and !> hi2bg on> hif  endof
        ( Alt-F5 )      236 of  hi1bg 1+ $0F and !> hi1bg on> hif  endof
        ( Alt-F7 )      238 of  txtbg 1+ $0F and !> txtbg on> hif  endof
        ( Alt-F9 )      240 of  hi4bg 1+ $0F and !> hi4bg on> hif  endof
                                drop
                endcase ;

: lhelp         ( -- )
                savescr .listing_file
                begin   .listing_file
                        %lhelp
                        key dup 127 >
                while   dohelpkey
                repeat  drop restscr ;

: dolistkey     ( c1 -- )       \ handle keys entered by user
                case
        ( ^home )       247 of  lhome           endof   \ top of file
        ( ^end )        245 of  lend            endof   \ end of file
        ( home )        199 of  lefthome        endof   \ top of file
        ( end )         207 of  righthome       endof   \ end of file
        ( up arrow )    200 of  -1line          endof   \ up one line
        ( down arrow )  208 of  +1line          endof   \ down one line
        ( left arrow )  203 of  lleft           endof   \ scroll left
        ( right arrow ) 205 of  lright          endof   \ scroll right
        ( pgup )        201 of  lpgup           endof   \ up 22 lines
        ( pgdn )        209 of  lpgdn           endof   \ down 22 lines
                         ^W of  -1line          endof   \ up one line
                         ^Z of  +1line          endof   \ down one line
                         ^E of  -1line          endof   \ up one line
                         ^X of  +1line          endof   \ down one line
                         ^R of  lpgup           endof   \ up 22 lines
                         ^C of  lpgdn           endof   \ down 22 lines
        ( enter )        13 of  +1line          endof   \ down one line
        ( F6 )          192 of  lfind           endof   \ find text
        ( Alt-F6 )      237 of  lafind          endof   \ find text again
        ( F1 )          187 of  lhelp           endof   \ HELP
        ( Alt-L )       $A6 of  ?lst 0= !> ?lst endof   \ listing format togl
                        ^O  of  lopen           endof   \ open a new file
                        upc
                        'P' of  zprint          endof   \ print cur file
                                drop
                endcase ;

: listshow      ( -- )          \ process user input & test for done
                .lastline
                begin   dolist                  \ update the screen
                        key                     \ get a key from user
        ( ESC )         dup   27 <>             \ while not ESC
        ( F10 )         over 196 <> and         \ and not F10
                while   .lastline               \ update last screen line
                        dolistkey               \ process the users key
                repeat  27 =
                if      off> hif
                then    ;

: listread      ( | name -- )   \ read file into memory
                bl word c@ 0=                   \ get file from DOS cndline
                if      ." File to list: "      \ if enpty, prompt for file
                        query bl word drop
                then
                here listhndl $>handle          \ move file to LISTHNDL
                listhndl hopen                  \ try to open the file
                if      ."  Couldn't open file" \ and abort if we couldn't
                        .cmdhelp bye
                then
                listbuf listlimit listhndl hread \ then read the file
                !> listlen                      \ and set read length
                off> listblk ;                  \ and first block of file

: ?/?           ( -- )
                >in @ bl word count '?' scan nip \ if line has any ? on it
        [long]  if      drop .cmdhelp bye
                else    >in !
                then    ;

: ?/lst         ( -- )          \ /LST display option
                >in @ bl word 1+ " /LS"  caps-comp 0=
                if      drop    on>  ?lst
                else    >in !   off> ?lst
                then    ;

: ?/line        ( -- f1 )       \ /LINE display option
                >in @ bl word 1+ " /LI" caps-comp 0=
                if      drop
                        bl word number? 2drop !> dest_line#
                                true            \      return true if /LINE
                else    >in !   false           \ else return false
                then    ;

: ?/rows        ( -- )          \ /ROWS display option
                >in @ bl word 1+ " /RO" caps-comp 0=
                if      drop
                        bl word number? nip
                        if      dup 5 max 99 min dup 2- !> displaylines
                                dup !> rows !> urows
                        then    drop
                else    >in !
                then    ;

\ code row/col!   ( -- )
\                 push ds
\                 mov ax, # $40           \ absolute segment $40:00
\                 mov ds, ax              \ goes into ds
\                 mov bl, $4A             \ get the # of cols from    $40:$4A
\                 mov cl, $84             \ get the # of rows from    $40:$84
\                 pop ds
\                 mov &> cols bl
\                 cmp cl, # 24
\               < if      mov cl, # 25    \ at least 25 rows
\                 else    inc cl
\                 then
\                 mov &> rows cl
\                 ret     end-code

: ZLIST         ( | name -- )   \ this is the ZLIST program
                savescr
                savecursor
                ?/?
                blinkoff
                listread                        \ read first part of file
                lfindbuf off                    \ clear text find buffer
                listhndl2 clr-hcb               \ clear second file handle
                cursor-off           \ save cursor status
                ?vmode 7 =                      \ setup hilighting for vmode
                if      ['] >rev  is >hilight   \ for mono, use reverse
                        ['] >rev  is >hilight2
                        ['] >norm is >text
                        ['] >norm is >hilight4
                else    ['] >hi1  is >hilight   \ for color
                        ['] >hi2  is >hilight2
                        ['] >txt  is >text
                        ['] >hi4  is >hilight4
                        row/col_set
                        rows 3 - !> displaylines
                        rows 1-  !> urows
                then
                .listing_file                   \ show file we are listing
                >text                           \ select normal attributes
                doblock_set     \ test and setup for possible block file
                ?/rows
                ?/line 0=
        if      ?/lst                           \ hilight comment lines?
                lendset                         \ set the end of file stuff
                .emptyscr
                .lastline
                lhfind                          \ find word in first column
        else    lendset                         \ set the end of file stuff
                linefind                        \ move to line
                .lastline
        then    listshow                        \ go list the file to user
                restcursor
                0 displaylines 1+
                at? 1- nip max at               \ goto bottom of screen
                listhndl hclose drop            \ and close the file
                                                \ as we are leaving now
                discardscr                      \ throw away saved screen
                ?save_colors ;

\ Following lines add compatibility for both F-PC and TCOM

\fpc listlimit array fpcbuf   fpcbuf   !> listbuf  \ init buffer for F-PC
\fpc 49        array fpclfbuf fpclfbuf !> lfindbuf

\fpc \s         \ discard rest if using F-PC

: main          ( -- )          \ perform needed program setup for TCOM
                                \ I like "main", it sounds like "C".
                DECIMAL                         \ always select decimal
                listlimit ds:alloc !> listbuf   \ text buffer
                49        ds:alloc !> lfindbuf  \ search buffer
                INIT-CURSOR                     \ get intial cursor shape
                ?DS: SSEG !                     \ init search segment
                caps on                         \ case INSENSITIVE
                vmode.set                       \ video direct display
                $6000 SET_MEMORY                \ default to min code space
                DOS_TO_TIB                      \ move command tail to TIB
                COMSPEC_INIT                    \ init command specification
                ZLIST    ;




