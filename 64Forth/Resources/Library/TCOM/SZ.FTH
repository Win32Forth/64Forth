\\ SZ.FTH               Small Zimmer's Editor           by Tom Zimmer
  In this file I will develop the code for an editor. This is a fairly
simple editor, with a limited set of functions. It works with standard
text files where lines are terminated with a carraige return and a
linefeed. Only simple dump to the printer type printing from within the
program is supported. It is useful for manipulating up to two text files
at a time with each file limited to about 60000 characters.

{

FORTH DECIMAL
\ ***************************************************************************
\ Some additional words need to be added that are in the target library, but
\ are not in the normal F-PC Forth dictionary.
\ ***************************************************************************

VARIABLE HOSTING
ALSO HIDDEN ALSO

VARIABLE ESC_FLG

CREATE TMPBUF 128 ALLOT

: #EXPECT       ( A1 N1 N2 -- )
                PLUCK >R SWAP DUP>R SPAN ! TMPBUF PLACE
                AT? TMPBUF R> LINEEDITOR
                IF      TMPBUF COUNT DUP SPAN ! R> SWAP CMOVE
                ELSE    R>DROP ESC_FLG ON
                THEN    ;

: DS:ALLOC      ( n1 -- a1 )    \ allocate n1 bytes of DS: RAM at runtime,
                                \ returning a1 the address of the DS: RAM
                \ HERE SWAP DP +! ;
                HERE SWAP ALLOT ;

: DS:FREE?      ( -- n1 )       \ return the amount of free DS: RAM
                \ SP0 @ HERE - 300 - ;
                UNUSED 1000 - ;

: ?DS:          ?CS:    ;
: DS:!          DROP    ;
: DS:->SS:              ;
: INIT-CURSOR           ;
: dos_to_tib            ;
: SETUP_MEMORY          ;

    1 constant scrfline         \ first screen line
   22    value scrlline         \ last screen line
   79 constant maxcol           \ maximum right column position
   80 constant columns          \ columns on screen
  256 constant lbsiz            \ line buffer size
  $0A constant alf              \ a linefeed character
$2020 constant ablbl            \ two blanks
$0A0D constant acrlf            \ a carraige return Linefeed character
  $1E constant ylbl             \ green characters on a blue background
  $03 constant cybk             \ cyan characters on a black background
  $4F constant wtrd             \ white characters on a red background
 1024 constant msg_max          \ length of message buffer

: pglines       ( -- n1 )
                scrlline scrfline - 1- ;
: statline      ( -- n1 )
                scrlline 1+ ;

\ It may hard to believe that a simple editor needs all of these
\ variables, but it does.

$78 value stat_color            \ status and filename bar color
$07 value text_color            \ colors for text
$7F value end_color             \ color of end of file message
$4F value err_color             \ color of error messages
  0 value lbuf                  \ holds line buffer address
  0 value fhndl                 \ current file handle
  0 value ccphndl               \ cut copy paste handle
  0 value tbuf                  \ Text buffer array pointer
  0 value msg_buf               \ message buffer from compiler
  0 value msg_len               \ message buffer length
  0 value erroring
  0 value ?got_msg              \ did we find a message file
  0 value ?cmd                  \ do we leave in Command mode

variable totmem                 \ total memory used by editor
variable rbuf                   \ holds replace buffer address
variable sbuf                   \ holds search buffer address
variable dbuf                   \ dos command line buffer
variable scnt                   \ search count variable
variable tbuf_end               \ address of end of text buffer
variable read_len               \ bytes read from file
variable read_end               \ pointer to end of read text
variable curcol                 \ cursor column position
variable currow                 \ cursor row position
variable scrrow                 \ screen row position
variable curadr                 \ address of current line
variable scradr                 \ address of top of screen
variable insmode                \ insert mode flag
variable ?not_done              \ are we NOT done editing yet?
variable changed                \ line changed flag
variable modified               \ file modified flag
variable modifiable             \ will we allow the file to be changed?
variable totlines               \ total lines in file
variable fullflag               \ memory full flag
variable inserting              \ a disabling flag for ?FULL
variable seg#                   \ file segment number
variable didfind                \ we found the string
variable f$                     \ filename string pointer
variable file#                  \ current edit file
variable #files                 \ number of files open
variable ds_0                   \ first data segment
variable tsize                  \ current tab size
variable markflg                \ are we currently marking?
variable mark1                  \ line to cut or copy from
variable mark2                  \ the other line to cut or copy from
variable sm$                    \ status message string pointer
variable soff                   \ start displaying at column offset
variable ?got_dir               \ did we make a directory file properly

: >text_color   ( -- )          \ select the character colors for normal text
                text_color attrib ! ;

: >stat_color   ( -- )          \ set the status line character colors
                stat_color attrib ! ;

: >end_color    ( -- )          \ set the End of file message colors
                end_color attrib ! ;

: >err_color    ( -- )
                err_color attrib ! ;

: ?capslock     ( --- f1 ) 0 $417 c@l $40 and 0<> ;

: color_init    ( -- )          \ init for color or monochrome
                ?vmode 7 <>
                if      ylbl =: stat_color      \ yellow on blue
                        cybk =: end_color       \ cyan on black
                        $07  =: text_color      \ normal text
                        wtrd =: err_color       \ error messages
                        row/col_set
                        rows 3 - !> scrlline
                then    ;

: tbuf_size     ( -- n1 )       \ max edit filesize in bytes
                tbuf_end @ tbuf - ;

: ?full         ( -- f1 )       \ is memory full
                tbuf_end @ read_end @ 255 + u< dup fullflag !
                inserting @ and ;

: dos_prep      ( -- )          \ prepare a section of the screen in case
                                \ there is an error while performing a DOS
                                \ function. We will fill it in again after
                                \ the DOS function is performed.
                0 scrlline 4 - at
                4 for cr eeol next
                0 scrlline 3 - at ;

}

 ***************************************************************************
 exit command file creation. Allows passing a command back to the calling
 program.

 Builds a file called ZZ.CMD. The file contains the following information:

        Size       Contents
        --------------------------------------------------------
        byte       Ascii command to Mini Shell ( Q | 1-9 ).
        byte       Space filler.
        variable   Upto 64 bytes of filename.
        byte       Space filler.
        4bytes     Row number in ascii, four digits.
        byte       Space filler.
        4bytes     Column number in ascii, four digits.
        byte       Space filler.
        2bytes     CRLF line and file terminator.
        --------------------------------------------------------

 The command byte at offset zero is interpreted by the mini shell as
 follows:

        Q       Quitting, return to DOS.
        1-9     Perform the DOS commandline from the file ZZ.CFG using
                lines 2 through 10 respectively.

 ***************************************************************************

{

handle cmdhndl

: cmdmake       ( -- f1 )       \ make the command file, return true if OK
                " ZZ.CMD" ">$ cmdhndl $>handle
                cmdhndl hcreate 0= ;

: #write        ( n1 handle -- )        \ write n1 as four digits to handle
                >r 0 <# # # # # #> r> hwrite drop ;

: cwrite        ( c1 handle -- )
                >r sp@ 1 r> hwrite 2drop  ;             \ add space

: %cmd          ( c1 -- )       \ put command c1 into command file
                ?cmd    0=      if drop exit then       \ leave if no command
                cmdmake 0=      if drop exit then       \ leave if no make
                                cmdhndl cwrite          \ send cmd
                bl              cmdhndl cwrite          \ add space
                fhndl count     cmdhndl hwrite drop     \ append filename
                bl              cmdhndl cwrite          \ add space
                currow @ 1+     cmdhndl #write
                bl              cmdhndl cwrite          \ add space
                curcol @ 1+     cmdhndl #write
                bl              cmdhndl cwrite          \ add space
                $0D             cmdhndl cwrite          \ terminate file
                $0A             cmdhndl cwrite          \ with CRLF chars
                                cmdhndl hclose drop ;   \ and close it

: Q_CMD         ( -- )  'Q' %cmd ;
: 1_CMD         ( -- )  '1' %cmd ;      \ control F1
: 2_CMD         ( -- )  '2' %cmd ;      \ control F2
: 3_CMD         ( -- )  '3' %cmd ;      \ control F3
: 4_CMD         ( -- )  '4' %cmd ;      \ control F4
: 5_CMD         ( -- )  '5' %cmd ;      \ F5
: 6_CMD         ( -- )  '6' %cmd ;
: 7_CMD         ( -- )  '7' %cmd ;      \ F7
: 8_CMD         ( -- )  '8' %cmd ;
: 9_CMD         ( -- )  '9' %cmd ;      \ F9
: 10_CMD        ( -- )  '0' %cmd ;
: 11_CMD        ( -- )  'A' %cmd ;      \ Shift-F1
: 12_CMD        ( -- )  'B' %cmd ;
: 13_CMD        ( -- )  'C' %cmd ;
: 14_CMD        ( -- )  'D' %cmd ;
: 15_CMD        ( -- )  'E' %cmd ;
: 16_CMD        ( -- )  'F' %cmd ;
: 17_CMD        ( -- )  'G' %cmd ;
: 18_CMD        ( -- )  'H' %cmd ;      \ Shift-F8



\ ***************************************************************************
\ get the message file from compiler

: get_MSG_file  ( -- )          \ get the message file to message buffer
                fhndl ccphndl $>handle
                " MSG" ">$  ccphndl $>ext
                ccphndl hopen dup 0= =: ?got_msg ?exit \ leave if no file
                msg_buf msg_max blank                   \ blank fill buffer
                msg_buf msg_max ccphndl hread =: msg_len \ read it into buffer
                $0A0D msg_buf msg_len + !               \ terminate with CRLF
                ;

40 array msg_lptrs
0 value msg_num

: "?msg_mark    ( a1 n1 -- )       \ does line start with our filename?
\                24 min 2dup $0A scan nip - '(' scan nip
                24 min '(' scan                 \ if we find a '(' in line
                if      dup msg_lptrs count 2* + !
                        msg_lptrs incr
                then    drop ;

: msg_type      ( a1 -- )
                begin   dup c@ $0D <>
                while   dup c@ emit 1+
                repeat  drop ;

: process_msgs  ( -- )          \ look for error messages in message buffer
                msg_lptrs off
                off> msg_num
                msg_buf msg_len
                begin   2dup $0A scan 2dup 2>r nip -
                        "?msg_mark
                        2r> 1 /string dup 0=
                until   2drop ;

\                 bounds
\                 ?do     i c@ $0A =
\                         if      i 1+ ?msg_mark
\                         then
\                 loop    ;

\ ***************************************************************************

: statline-at   ( n1 -- )       \ moves to column n1 of statline and
                                \ sets status color
                statline at >stat_color ;

: scrfline-at   ( n1 -- )       \ move to the first text line, erase it and
                                \ set the status line colors.
                scrfline 2dup at >stat_color eeol at ;

: end>rev       ( -- )          \ clear the status line, then select the
                                \ text colors.
                0 statline-at eeol >text_color ;

: .warning      ( a1 n1 -- )
                0 scrlline 2- at >stat_color
                2 for eeol cr next
                0 scrlline 2- at space type eeol
                cr ."  ** Press a key to return to the editor ** "
                cr >text_color
                beep key drop
                end>rev ;

: ?err          ( f1 a1 n1 -- f1 )      \ if f1 = true then display message
                rot
                if      .warning true
                else    2drop    false
                then    ;

: .by           ( -- )          \ my NON-COPYRIGHT message
                8 spaces
                ." Small Z editor was written by Tom Zimmer (public domain)" ;

: %szsave       ( -- f1 )       \ save changes, return true if failed
                fhndl hcreate dup ?exit drop
                tbuf read_len @ fhndl hwrite read_len @ -
                fhndl hclose or dup 0=
                if      modified off
                then    ;

: prevlf        ( a1 -- a2 )            \ a1 = address of char after LF
                                        \ a2 = address of previous LF
                2- dup tbuf 1- - 255 umin alf -scan drop ;

: nextlf        ( a1 -- a2 )            \ a1 = address of char after LF
                                        \ a2 = address of next LF
                read_end @ over - 1+ 255 umin alf scan drop ;

: parse_line    ( a1 -- a1 n1 )         \ given line a1, return length
                dup 255 alf scan drop 1+ read_end @ umin over - ;

: erase_below   ( -- )          \ erase the text line below the current line
                statline #line @ 1+ over min
                ?do     0 i at eeol
                loop    ;

: ?cursor-on    ( -- )          \ turn on cursor if in modifiable mode
                modifiable @
                if      cursor-on
                then    ;

create dashs ," ƒƒƒƒƒƒƒƒ"

: --s           ( n1 -- )       \ display n1 - symbols
                dup u8/ 0 ?do dashs 1+ 8 type loop 7 and dashs 1+ swap type ;

: showbottom    ( -- )          \ the after last text line message, shown
                                \ in "end-color".
                0 #line @ 1+ at >end_color
                30 --s ."  End of file " 36 --s >text_color
                erase_below ;

: revset        ( n1 -- )       \ test and set reverse video if we are
                                \ on a line marked for cut or copy.
                markflg @ 0<                    \ marking, set mark2
                if      currow @ mark2 !
                then
                scrrow @ - currow @ +           \ then test for between
                mark1 @ mark2 @ 2dup u>         \ mark1 and mark2
                if swap then between
                if      >rev                    \ if so then display reverse
                then    ;

: ?rev_set      ( n1 -- )       \ conditionally set the current line to
                                \ reverse video if we are marking.
                markflg @ 0=
                if      drop exit               \ not marking then leave
                then
                revset  ;

: get_tline     ( a1 -- a2 a1 n1 ) \ return the address and length of line a1
                dup nextlf 1+ tuck over -
                2dup + 2- @ acrlf = if 2- then
                soff @ /string columns min ;

: #scrshow      ( a1 -- )       \ show a screen full of text starting at
                                \ line address a1.
                cursor-off
                statline scrfline
                do      dup read_end @ u>= ?leave
                        get_tline
                        0 i at i ?rev_set type eeol >text_color
                loop    drop
                #line @ scrlline <
                if      showbottom
                then
                ?cmd 0= if ?cursor-on exit then         \ leave here!!
                0 statline 1+ at
                msg_lptrs count
                if      >err_color msg_num 2* + @ msg_type eeol
                        erroring
                        if      0 0 at >err_color
                                ."     Press ESC to EDIT   "
                        then
                else    ?got_msg
                        if      >end_color
                                ."   Program has no compile errors "
                                eeol
                        then
                then    drop >text_color
                ?cursor-on ;

: strip_bl's    ( -- )          \ strip blanks from the line buffer
                lbuf count tuck 1- + swap bl -skip nip lbuf c! ;

: adj_tbuf      ( a1 n1 -- a1 n1 )      \ adjust hole for edited line
                lbuf c@ 2dup - dup 0<   \ ?longer then make room
                if                                      \ dat olen nlen dif
                        abs >r drop
                        curadr @ dup r@ +               \ cur cur+dif
                        read_end @ curadr @ -           \ rem_len
                        2+ cmove>                       \ move the data
                        r>                              \ dat olen dif
                else                    \ else shorten space
                        >r drop
                        curadr @ dup r@ + swap          \ cur+dif cur
                        read_end @ curadr @ - r@ -
                                                        \ rem_len
                        2+ cmove
                        r> negate                       \ dat olen -dif
                then
                dup read_len +!                         \ adj file length
                    read_end +! ;                       \ & end address

: ltobuf        ( -- )          \ move the current line buffer to text buffer
                curadr @ parse_line dup lbuf c@ <>
                if      adj_tbuf                \ dat olen
                        drop lbuf c@            \ discard olen add nlen
                then    ( -- a1 n1 )
                lbuf 1+ -rot cmove ;    \ put line in text buffer

: add_crlf      ( -- )          \ append CRLF to line buffer
                acrlf lbuf count + !
                2 lbuf c+! ;

: ?del_crlf     ( -- )          \ delete CRLF if they are there
                lbuf count + 2- @ acrlf =
                if      -2 lbuf c+!
                        ablbl lbuf count + !
                then    ;

: putline       ( -- )          \ put the current line back in text body
                                \ if it has been changed.
                changed @ modifiable @ and      \ changes allowed?
                if      ?full ?exit
                        strip_bl's              \ remove trailing blanks
                        add_crlf
                        ltobuf                  \ move line to buffer
                        modified on             \ mark file as modified
                        changed off             \ clear line changed flag
                then    ;

: getline       ( -- )          \ get a line from text body
                lbuf count blank
                curadr @ parse_line lbuf place ?del_crlf ;

: szline        ( -- )          \ show the current line
                0 scrrow @ at
                scrrow @ ?rev_set
                lbuf count soff @ /string columns min type
                eeol >text_color ;

: szshow        ( -- )          \ show the text on screen
                scradr @ #scrshow ;

: dosave        ( -- )          \ save changes to current file if there
                                \ have been any
                putline
                getline
                modified @ modifiable @ and 0= ?exit
                dos_prep
                %szsave " Error while writing file!" ?err drop
                end>rev
                szshow ;

: szsave        ( -- f1 )       \ save changes from edit
                                \ f1 = true if error
                modifiable @ modified @ and
                if      %szsave " Save ERROR!" ?err
                else    false
                then    ;

: space>col     ( n1 -- )       \ display spaces upto column n1
                #out @ - spaces ;

: szstatus      ( -- )          \ show cursor position in file
                0 statline-at
                ."  Column " curcol @ 1+ .       12 space>col
                ." Line "   currow @ 1+ .       30 space>col
                modified @
                if      >end_color
                then    sm$ @ count type >stat_color
                seg# @ ?dup if 4 .r then
\                45 space>col ." Stk = " depth .
                56 space>col
                ." Lines "
                totlines @ 5 .r
                ."  Bytes "
                read_len @ 0 <# #s #> type eeol >text_color
                fullflag @
                if      62 0 at >stat_color ."  ** MEMORY FULL **"
                then
                ?cmd
                if      >stat_color
                        0 statline 2+ at
."   F5=Compile_prog  Ctrl-F5=Review_errs  =scrl_errs  F7=Debug_prog  F10=Quit "
                        eeol
                then    >text_color ;

: szcursor      ( -- )          \ position the cursor at the proper location
                                \ on the screen.
                curcol @ soff @ - scrrow @ at ;

: %fdel         ( -- )          \ delete char under cursor
                lbuf count curcol @ /string dup
                if      swap dup 1+ swap rot cmove
                        -1 lbuf c+!
                else    2drop
                then    changed on ;

: putachar       ( c1 -- )       \ put in one character to line buffer
                lbuf 1+ curcol @ + c!
                curcol @ lbuf c@ max lbuf c! ;

: linetotop     ( -- n1 )       \ lines to top of screen
                scrrow @ scrfline - ;

: <>near_end?   ( -- f1 )       \ true if closer to file end than PGLINES
                totlines @ 1- currow @ -        \ line from end
                pglines dup linetotop - + > ;   \ if more than pglines to end

: ?lastline     ( -- f1 )       \ is the current line the last line?
                currow @ totlines @ 1- >= ;

: %down1        ( a1 -- f1 )    \ a1 = addr we are adjusting
                                \ f1 = true if on last line
                dup>r @ nextlf 1+ dup read_end @ u<
                if      r> ! false
                else    drop
                        read_end @ prevlf 1+ tbuf umax r> !
                        true
                then    ;

: <down1>       ( -- f1 )       \ Move down one row in file
                scrrow @ scrlline >=    \ if at bottom of screen
                if      scradr %down1 drop
                else    scrrow incr
                then    curadr %down1 dup 0=
                if      currow incr
                then    ;

: %up1          ( a1 -- f1 )    \ move from line address in variable a1,
                                \ up one line and return a flag true if
                                \ we are at the beginning of the text buffer.
                dup>r @ prevlf 1+ tbuf umax dup r> ! tbuf u<= ;

: <up1>         ( -- )          \ backup one row in the text buffer, clipping
                                \ at the beginning of the text buffer.
                scrrow @ scrfline <=
                if      scradr %up1 drop
                else    scrrow decr
                then    curadr @ prevlf 1+ tbuf umax curadr !
                currow @ 1- 0max currow ! ;

: scrtop        ( -- )          \ move to top line on screen
                putline
                begin   scrrow @ scrfline >
                while   <up1>
                repeat
                getline ;

: scrbot        ( -- )          \ move to bottom line on screen
                putline true
                begin   ( -- f1 )
                        scrrow @ scrlline < and
                while   <down1> 0=      ( -- f1 )       \ true if not at end
                repeat
                getline ;

: scrlup        ( -- )          \ scroll the screen up
                putline
                scradr @ tbuf u<=     \ if already at top
                if      <up1>           \ then up a line
                else    scradr %up1 drop
                        curadr %up1 drop
                        currow decr
                then
                getline szshow ;

: scrldn        ( -- )          \ scroll the screen down
                ?lastline ?exit
                putline
                totlines @ 1- currow @ -        \ line from end
                linetotop + pglines >
                if      scradr %down1 drop
                        curadr %down1 drop
                        currow incr
                else    <down1> drop
                then
                getline szshow ;

: down1         ( -- )          \ move down one line in the text buffer.
                                \ redisplay the screen if needed.
                ?lastline ?exit
                modifiable @ 0= if scrldn exit then
                putline
                <down1> drop
                getline
                scrrow @ scrlline >= markflg @ or
                if      szshow
                then    ;

: up1           ( -- )          \ go up one line in file, redisplay the
                                \ screen if needed.
                modifiable @ 0= if scrlup exit then
                putline
                <up1>
                getline
                scrrow @ scrfline <= markflg @ or
                if      szshow
                then    ;

: ?soffL!       ( n1 -- )       \ starting column offset set, with
                                \ screen redisplay if needed.
                soff @ over >=
                if      dup soff !
                        szshow
                then    drop ;

: %left         ( -- )          \ move left one character column
                curcol @ 1- 0max dup curcol ! ?soffL! ;

: ?soff!        ( n1 -- )       \ set SOFF if n1 greater than columns
                maxcol - 0max ?dup
                if      soff @ max soff !
                        szshow
                then    ;

: right1        ( -- )          \ go right a character in this line
                curcol @ 1+ 255 min dup curcol ! ?soff! ;

: homeln        ( -- )          \ go to beginning of line
                curcol off
                soff @ soff off
                if      szshow
                then    ;

: endln         ( -- )          \ go to the end of the line
                strip_bl's lbuf c@ dup curcol ! ?soff! ;

: linechar      ( n1 -- c1 )    \ return the n1 char of lbuf at c1
                lbuf 1+ + c@ ;

: >space        ( --- )         \ move to next space in line
                lbuf c@ dup curcol @ over min
                ?do     i linechar dup bl =
                        swap 127 > or
                        if      drop i leave then
                loop    255 min dup curcol ! ?soff! ;

: space>        ( --- )         \ move to non blank in line
                lbuf c@ dup curcol @ over min
                ?do     i linechar dup bl <>
                        swap 127 > 0= and
                        if      drop i leave then
                loop    lbuf c@ min 255 min dup curcol ! ?soff! ;

: <<space>      ( ---  n1 )     \ n1 = offset from line strt to prev space
                0 dup curcol @
                ?do     i linechar dup bl =
                        swap 127 > or
                        if      drop i leave then
            -1 +loop    dup curcol ! dup ?soffL! ;

: <text         ( --- )      \ move to previous text in line.
                0 dup curcol @
                ?do     i linechar dup bl <>
                        swap 127 > 0= and
                        if      drop i leave then
            -1 +loop    dup curcol ! ?soffL! ;

: wleft         ( -- )          \ word left with wrap at line start
                curcol @ 0= curadr @ tbuf u> and
                if      up1 endln szshow exit
                then    curcol @ 1- 0max curcol !
                <text   curcol @ 0=
                if      szshow exit
                then    <<space>
                if      curcol incr
                then    curcol @ 255 min curcol ! szshow ;

: wright        ( -- )          \ word right with wrap at line end
                curcol @ lbuf c@ 255 min =
                ?lastline 0= and
                if      curcol off
                        soff off
                        down1 szshow exit
                then    >space
                curcol @ lbuf c@ >=
                if      szshow exit then
                space> szshow ;

: left          ( -- )          \ move left one character on line, with
                                \ wrap up to end of previous line if at
                                \ line start.
                curcol @ 0>
                if      %left
                else    currow @ 0>
                        if      up1
                                endln
                        then
                then    ;

: merge_prev    ( -- )          \ merge thie line with the previous line
                curadr @                        \ save cur lines addr
                lbuf c@ >r up1 endln
                lbuf c@ r> + 255 >              \ don't make lines longer
                if      drop beep exit          \ than 255 characters
                then
                curadr @ over u<                \ if not on first line
                if      ablbl over 2- !         \ change CRLF to BLBL
                        getline                 \ get line again
                        %fdel                   \ del one blank
                        curcol @ 0=             \ at line start?
                        if      %fdel           \ then del both blanks
                        else    right1          \ move right one
                        then
                        totlines decr
                then    drop ;

: %bdel         ( -- f1 )       \ backward delete, deletes char before cursor
                                \ return flag true if we need redisplay
                curcol @ 0=
                if      currow @ dup 0= ?exit drop
                        insmode @
                        if      modifiable @ 0= ?exit
                                merge_prev      true
                        else    left            false
                        then
                else    %left
                        modifiable @ 0= ?exit
                        insmode @
                        if      %fdel
                        else    bl putachar
                        then                    false
                then    changed on ;

: bdel          ( -- )          \ backwards delete
                %bdel
                if      szshow
                then    ;

: calc_lines    ( -- )          \ determine the total number of lines in
                                \ the file, set TOTLINES according
                totlines off
                tbuf
                begin   nextlf read_end @ over u>=
                while   1+ totlines incr
                repeat  drop
                read_end @ 1- c@ alf <>         \ last line has no CRLF
                if      totlines incr           \ need to bump total line
                then                            \ count by one more
                totlines @ 1 max totlines ! ;

: %goend        ( -- )          \ goto end of text buffer/file.
                read_end @ prevlf 1+ dup scradr ! curadr !
                scrlline 2- 0
                do      scradr %up1 ?leave
                loop
                totlines @ 1- currow !
                scrlline 1- totlines @ 1- scrfline + min scrrow ! ;

: downpg        ( -- )          \ go down page lines in file
                putline
                <>near_end?
                if      pglines 0
                        do      scradr %down1   ( -- f1 )
                                curadr %down1 drop
                                currow incr
                                ( -- f1 ) ?leave
                        loop
                else    %goend
                then
                getline szshow ;

: %gohome       ( -- )          \ goto start of text buffer/file
                tbuf scradr !
                tbuf curadr !
                scrfline scrrow !
                currow off ;

: uppage        ( -- )          \ go up page lines in file
                putline
                scradr @ tbuf u<=
                if      %gohome
                else    pglines 0
                        do      scradr %up1     ( -- f1 )
                                curadr %up1 drop
                                currow decr
                                ( -- f1 ) ?leave
                        loop
                then
                getline szshow ;

: gohome        ( -- )          \ goto beginning of file
                putline %gohome curcol off soff off getline szshow ;

: goend         ( -- )          \ goto end of file
                putline %goend getline szshow ;

: instgl        ( -- )          \ insert mode toggle
                insmode @ 0= dup insmode !
                if      big-cursor
                else    norm-cursor
                then    ;

: kerr          ( c1 -- )       \ discard garbage key
                ;

: dochar        ( c1 -- )       \ handle displayable characters
                modifiable @ 0=         \ if not modifiable, or
                lbuf c@ 254 >  or       \ if line is full
                if drop exit then       \ then discard and leave
                insmode @       \ if in insert mode, make a hole for char
                if      lbuf count curcol @ /string
                        swap dup 1+ rot cmove>
                        1 lbuf c+!
                then    putachar
                changed on              \ mark line as changed
                right1                  \ bump to next cursor position
                curcol @ lbuf c@ max 255 min lbuf c! ;

: inspage       ( -- )          \ insert a page break at cursor
                ^L dochar ;

: dotab_keys    ( c1 -- f1 )    \ adjust the tab size till Enter is pressed
                dup  13 = if drop     true exit then    \ enter
                dup 203 = if tsize decr 0= exit then    \ left arrow
                dup 205 = if tsize incr 0= exit then    \ right arrow
                dup  45 = if tsize decr 0= exit then    \ -
                dup  43 = if tsize incr 0= exit then    \ +
                0= ;                                    \ all others

: tabclip       ( -- )          \ clip tabsize to valid range
                tsize @ 2 max 60 min tsize ! ;

: settab        ( -- )          \ set tab size
                cursor-off
        begin   tabclip
                0 scrfline-at
                ."  TABs set every " tsize @ 2 .r
                ."  columns.  Press + and - to adjust; Enter when done"
                >text_color
                key dotab_keys
        until   ?cursor-on
                szshow ;

: doachar       ( -- )          \ enter any character into the text file
                0 scrfline-at
                ."  Press the key you want to enter ->"
                key dochar
                >text_color
                szshow ;

: dotab         ( -- )          \ up to next tab position
                curcol @ 1+ tsize @ mod tsize @ swap -
                ?dup 0= ?exit 1-                \ leave if none to do
                insmode @
                if      for bl dochar  next     \ insert one or more blanks
                else    for right1     next     \ move right one or more chars
                then    ;

: btab          ( -- )          \ tab backwards
                curcol @ 0= if left then
                curcol @ 1+ tsize @ mod ?dup 0=
                if      8 curcol @ min
                then    1-
                for     left next    ;

: merge_next    ( -- )          \ merge thie line with the next line
                insmode dup @ >r on
                lbuf c@ >r
                '.' dochar      \ put a dummy char at end of line
                down1 homeln    \ down and left
                lbuf c@ r> + 255 <
        if      bdel bdel bdel  \ delete to join, and del dummy char
        else    bdel bdel
        then    putline getline \ make sure trailing blanks removed
                                \ as occurs when joining an empty
                r> insmode ! ;  \ line to this line.

: fdel          ( -- )          \ forward delete a character
                modifiable @ 0= ?exit
                lbuf c@ curcol @ >
                if      %fdel                   \ and delete forward
                else    ?lastline 0=            \ if not on last line
                        if      merge_next
                                szshow
                        then
                then    ;

: %wdel         ( -- )          \ word delete low level
                begin   curcol @ linechar bl <>   \ till bl found
                        lbuf c@ curcol @ > and  \ or lineend reached
                while   fdel
                repeat
                begin   curcol @ linechar bl =    \ till bl<>found and
                        lbuf c@ curcol @ > and  \ or lineend reached
                while   fdel
                repeat  ;

: wdel          ( -- )          \ word delete
                modifiable @ 0= ?exit
                lbuf c@ curcol @ >      \ not at end of line
                if      %wdel           \ delete a word
                else    fdel            \ else just merge in next line
                then    ;

: %ldel         ( -- )          \ line delete without redisplay
                modifiable @ 0= ?exit
                homeln
                lbuf lbsiz blank
                0 lbuf c!
                changed on
                inserting off           \ disable inserting and ?FULL
                insmode dup @ >r on
                ?lastline
                if      putline                 getline
                else    putline <down1> drop    getline
                        %bdel drop
                then
                r> insmode !
                inserting on    ;       \ re-enable inserting text

: ldel          ( -- )          \ line delete
                %ldel szshow ;

: doenter       ( -- )          \ process the ENTER key
                insmode @ ?lastline or
                if      insmode dup @ >r on
                        acrlf split swap dochar dochar
                        r> insmode !
                        changed on
                        putline                         \ save changed line
                        getline                         \ and get it again
                        changed on                      \ make sure trailing
                        putline                         \ blanks are removed
                        getline
                        totlines incr
                then    down1 homeln
                szshow ;

: down_lines    ( n1 -- )       \ move down n1 lines in file
                scrrow @ 8 <
                if      dup 8 min 0 ?do <down1> drop loop
                        8 - 0max
                then
                0
                ?do     scradr %down1   ( -- f1 )
                        curadr %down1 drop
                        currow incr
                        ( -- f1 ) ?leave
                loop    ;

: toaline       ( n1 -- )
                putline %gohome down_lines
                curcol off soff off getline ;

\ ***************************************************************************
\ display error locations

: to_errline    ( -- )
                msg_lptrs 1+ msg_num 2* + @ 80 2dup $0A scan nip -
                '(' scan 1 /string 2dup ')' scan nip - here place
                bl here count + c!
                here number? 2drop totlines @ min 1- 0max
                dup mark1 ! dup mark2 ! markflg on
                toaline ;

: do_err        ( n1 -- )
                dup 200 = if    msg_num 1- 0max     =: msg_num  then
                dup 208 = if    msg_num 1+
                                msg_lptrs c@ 1- min =: msg_num  then
                drop    ;

: doerrs        ( -- )
                ?cmd 0= ?exit
                msg_lptrs c@ 0= ?exit
                on> erroring
                begin   to_errline
                        szshow szstatus szcursor
                        key                     \ get a key
                        dup $1B  <>             \ ESC
                        over $C4 <> and         \ F10
                        over $F1 <> and         \ Alt-F10
                while   do_err
                repeat  drop
                off> erroring
                markflg off
                -1 mark1 !
                -1 mark2 !
                szshow szstatus .current ;

\ ***************************************************************************

: ?.row         ( -- )
                scnt @ 31 and 0=
                if      at? scnt @ 4 .r at
                then    ;

: soffset       ( -- )          \ make sure found text is visible
                curcol @ dup sbuf @ c@ 4 + + ?soff! dup soff @ <
                if      dup soff !
                then    drop ;

: szfinda       ( -- )          \ find next occurance of same text
                sbuf @ c@ 0= if szshow exit then
                putline
                -1 didfind !    \ init to row -1
                cursor-off
                ?capslock 0= save!> caps
                59 scrfline-at ."  Scanning lines "
                curcol dup @ >r incr
                scnt off
                sbuf @ count curadr @
                begin   3dup parse_line dup>r curcol @ /string search 0=
                        r> 0> and
                while   drop nextlf 1+
                        scnt incr curcol off
                        ?.row
                repeat  nip >text_color
                scnt @ currow @ + totlines @ 1- <       \ before file end
                if      curcol +! r>drop
                        scnt @ down_lines
                        currow @ didfind !
                        soffset
                else    drop beep
                        r> curcol !
                then    2drop
                restore> caps
                ?cursor-on
                getline szshow ;

: .edit_info    ( -- )          \ display line edit options
                0 scrfline 1+ at >stat_color
        ."  Press: [ESC] = cancel, [Enter] = accept, [Home] = clear line"
                eeol >text_color ;

: szfind        ( -- )          \ search
                .edit_info
                0 scrfline-at ."  Enter text to search for ->"
                sbuf @ count 48 swap #expect span @ sbuf @ c! >text_color
                esc_flg @
                if      szshow
                else    szfinda
                then    ;

: szrepla       ( -- )          \ replace again with same string
                                \ and find next occurance to replace
                didfind @ dup 0< swap currow @ <> or ?exit
                insmode dup @ >r on
                curcol @ >r
                sbuf @ c@    0 ?do fdel              loop
                rbuf @ count 0 ?do dup i + c@ dochar loop drop
                r> curcol !
                r> insmode !
                didfind off
                szline
                szfinda ;

: szrepl        ( -- )          \ replace text just found
                didfind @ 0< ?exit
                .edit_info
                0 scrfline-at ."  Enter replacement text ->"
                rbuf @ count 48 swap #expect span @ rbuf @ c! >text_color
                esc_flg @
                if      szshow
                else    szrepla
                then    ;

: .current      ( -- )
                0 scrfline 1- at >stat_color ."  F1-Help  F10-Save/exit ≥ "
                f$ @ count type
                fhndl count 60 min type eeol >text_color ;

: szwrite       ( -- )          \ search
                .edit_info
                0 scrfline-at ."  Enter NEW name for this file ->"
                tib 1+ 30 expect span @ tib c! >text_color
                esc_flg @ 0=
                if      tib fhndl $>handle      \ change the name
                        .current
                        modified on
                        modifiable on
                then    szshow ;

: canceled?     ( -- f1 )
                esc_flg @ tib c@ 0= or ;

: ?get_dir      ( -- )          \ make and read a directory file if no file
                                \ was specified, and we didn't press ESC.
                tib c@ 0= esc_flg @ 0= and
                if      " DIR *.*>TEMP.DIR" ">$ $sys 0=
                        if      " TEMP.DIR" tib place
                                ?got_dir on
                        then
                then    ;

: ?dir_del      ( -- )          \ delete the temporary directory file
                ?got_dir @
                if      " DEL TEMP.DIR" ">$ $sys drop
                        ?got_dir off
                then    ;

: do_szprint    ( -- )          \ copy current file to printer
                " COPY "    tib  place
                fhndl count tib +place
                "  PRN>NUL" tib +place
                tib $sys drop
                ^L pemit  ;                     \ send a FORMFEED

: szprnt        ( -- )          \ print current file
                putline getline
                szsave 0=               \ saved ok
                cursor-off
                ?printer.ready and      \ and printer is online
                if      0 scrfline-at ."  Printing .... " >text_color
                        do_szprint
                else    0 scrfline-at ."  *** Printer is OFFLINE ***"
                        >text_color
                        beep
                then    ?cursor-on
                        szshow ;

: mark_CRLF's   ( -- )
                acrlf tbuf 2- 2dup ! 2- !     \ mark begin with 2*CRLF
                acrlf read_end @ ! ;            \ mark end of buf with CRLF

: %newfile      ( -- )
                acrlf tbuf !
                2 read_len !
                tbuf 2+ read_end !
                mark_CRLF's
                modifiable on ;

: tglset        ( f1 -- )       \ set the status line message, and turn
                                \ the cursor on or off according to edit
                                \ or browse mode.
                if      "  Edit MODE "    cursor-on
                else    "  Browse MODE "  cursor-off
                then    ">$ sm$ ! ;

: btgl          ( -- )          \ browse/edito mode toggle
                modifiable @ 0= dup modifiable !
                dup tglset
                0= if modified off then ;

: %szread       ( -- )          \ read the currently open file
                fhndl endfile or        \ if file has chars in it
                if      seg# @ tbuf_size um* fhndl movepointer
                        tbuf tbuf_size fhndl hread dup read_len !
                        tbuf + read_end !
                        mark_CRLF's
                else    %newfile        \ else just put in CRLF
                then    fhndl endfile tbuf_size 0 d> 0=
                dup tglset modifiable !
                fhndl hclose drop ;

: szread        ( -- )                  \ read the current file
                true modifiable !
                true tglset
                fhndl c@ 0=             \ default to untitled if no file
                                        \ was specified
                if      " UNTITLED" ">$ fhndl $>handle
                then    fhndl hopen     \ -- f1
                if      %newfile        " NEW File = "
                else    %szread         " Edit File = "
                then    ">$ f$ !        .current
                end>rev
                modified off
                changed off ;

: szopen        ( -- )          \ open another file to edit
                .edit_info
                0 scrfline 2+ at >stat_color 8 spaces
                ." [Enter] alone = see a list of files [*.*]" eeol
                0 scrfline-at ."  Enter NAME of file to edit ->"
                tib 1+ 30 expect span @ tib c! >text_color
                ?get_dir
                canceled? 0=
                if      dosave
                        tib fhndl $>handle
                        szread
                        calc_lines
                        ?dir_del
                        .current
                        gohome up1
                then    szshow ;

: %switch_files ( -- )          \ switch to the other files data space
                ds_0 @ ?ds: <>  \ copy stacks from current to other
                if      ?ds: rp0 @ $200 - ds_0 @       over $200 cmovel
                else    ?ds: rp0 @ $200 - over $1000 + over $200 cmovel
                then
                ds_0 @ file# @L 1+ 2 mod dup
                ds_0 @ file# !L         ( -- n1 )
                                        \ returns number of next file 0 or 1
                ds_0 @                  \ first 64k segment
                swap $1000 * + ds:! ds:->ss: ;

: bump_#files   ( -- )
                ds_0 @ #files @L 1+ ds_0 @ #files !L  ;

: seg_copy      ( -- )
                0 save!> seg#                           \ clear seg#
                save> sseg $1000 sseg +!                \ adj SSEG
                ds_0 @ 0 over $1000 + 0 $FFF0 cmovel    \ copy ALL
                restore> sseg                           \ restore SSEG
                restore> seg#  ;                        \ restore seg#

: seg_dup       ( -- f1 )       \ duplicate the current segment and return
                                \ a true flag if failed
                $1000 totmem +!                                 \ bump by 64k
                ?cs: totmem @ setblock 0=                       \ adj memory
                if      seg_copy
                        false                                   \ return false
                else    beep getline .current szshow
                        true                                    \ return true
                then    ;

: ofile         ( -- )          \ other file
                markflg off
                putline
                ds_0 @ #files @L        \ leave if more than zero=1 file
                if      %switch_files
                        getline
                        .current szshow exit
                then    $2000 totmem @ u>       \ already allocated?
                if      seg_dup ?exit           \ NO, then allocate and dup
                then
                %switch_files                   \ switch over
                szopen                          \ try to open
                canceled?                       \ canceled?
                if      %switch_files           \ switch back
                else    bump_#files             \ incr total
                then    getline .current szshow ;

: %dodone       ( -- )          \ we are done editing, save changes
                putline
                ds_0 @ #files @L 0=
                if      ?not_done off
                else    szsave 0=
                        if      ofile                   \ switch files
                                0 ds_0 @ #files !L      \ back to one file
                        else    beep
                        then
                then    ;

: dodone        ( -- )          \ we are done editing, save changes
                %dodone Q_CMD ;

: doquit        ( -- )          \ quit editing & discard changes
                ds_0 @ #files @L 0=
                if      ?not_done off
                        changed   off
                        modified  off
                else    changed   off
                        modified  off
                        ofile
                        0 ds_0 @ #files !L      \ discard one file
                then    Q_CMD ;

\ ***************************************************************************
\ exit with save, and pass commands to the calling program in file ZZ.CMD.

: mcmd          ( a1 -- )       \ define zz command functions
                create ' ,
                does>   ?cmd if %dodone dup perform then drop ;

mcmd  cmd1  1_cmd       mcmd  cmd2  2_cmd       mcmd  cmd3  3_cmd
mcmd  cmd4  4_cmd       mcmd  cmd5  5_cmd       mcmd  cmd6  6_cmd
mcmd  cmd7  7_cmd       mcmd  cmd8  8_cmd       mcmd  cmd9  9_cmd
mcmd cmd10 10_cmd       mcmd cmd11 11_cmd       mcmd cmd12 12_cmd
mcmd cmd13 13_cmd       mcmd cmd14 14_cmd       mcmd cmd15 15_cmd
mcmd cmd16 16_cmd       mcmd cmd17 17_cmd       mcmd cmd18 18_cmd

\ : cmd1          ( -- )  ?cmd if %dodone  1_cmd then ;
\ : cmd2          ( -- )  ?cmd if %dodone  2_cmd then ;
\ : cmd3          ( -- )  ?cmd if %dodone  3_cmd then ;
\ : cmd4          ( -- )  ?cmd if %dodone  4_cmd then ;
\ : cmd5          ( -- )  ?cmd if %dodone  5_cmd then ;
\ : cmd6          ( -- )  ?cmd if %dodone  6_cmd then ;
\ : cmd7          ( -- )  ?cmd if %dodone  7_cmd then ;
\ : cmd8          ( -- )  ?cmd if %dodone  8_cmd then ;
\ : cmd9          ( -- )  ?cmd if %dodone  9_cmd then ;
\ : cmd10         ( -- )  ?cmd if %dodone 10_cmd then ;
\ : cmd11         ( -- )  ?cmd if %dodone 11_cmd then ;
\ : cmd12         ( -- )  ?cmd if %dodone 12_cmd then ;
\ : cmd13         ( -- )  ?cmd if %dodone 13_cmd then ;
\ : cmd14         ( -- )  ?cmd if %dodone 14_cmd then ;
\ : cmd15         ( -- )  ?cmd if %dodone 15_cmd then ;
\ : cmd16         ( -- )  ?cmd if %dodone 16_cmd then ;
\ : cmd17         ( -- )  ?cmd if %dodone 17_cmd then ;
\ : cmd18         ( -- )  ?cmd if %dodone 18_cmd then ;


\ ***************************************************************************

: domark        ( -- )          \ start or end marking of text for
                                \ cut or copy.
                markflg @ 0=                            \ if not marking
                if      currow @ mark1 !                \ then start mark
                        -1 markflg !
                        "  Marking " ">$ sm$ !
                        exit
                then    markflg @ 0<                    \ if already started
                if      currow @ mark2 !                \ then end marking
                        1 markflg !
                        "  Mark is SET " ">$ sm$ !
                else    markflg off                     \ else clear mark
                        mark1 on
                        mark2 on
                        modifiable @ tglset
                then    szshow ;

: toline        ( n1 -- )       \ goto the line n1
                currow @ over =
                if      drop exit then
                currow @ over <
                if      currow @      ?do <down1> drop loop
                else    currow @ swap ?do <up1>        loop
                then    ;

: set_ccpfile   ( -- )
                " TEMP" ">$ ccphndl $>handle ;

: %copy_write   ( -- f1 )
                mark1 @ mark2 @ 2dup min toline max 1+
                curadr @ swap toline curadr @
                ?lastline                       \ if last line, use file-end
                if      drop read_end @         \ instead of curadr
                then
                over - dup>r
                ccphndl hwrite r> -
                ccphndl hclose or ;

: %docopy       ( -- f1 )       \ copy marked text while preserving our
                                \ current edit location
                set_ccpfile
                ccphndl hcreate dup ?exit
                scradr @ >r
                curadr @ >r
                scrrow @ >r
                currow @ >r             \ save current line
                %copy_write or          \ -- f1 = true if error
                r> currow !
                r> scrrow !
                r> curadr !
                r> scradr ! ;

: docopy        ( -- )          \ copy marked lines
                markflg @ 0= ?exit              \ leave if not marked
                markflg @ 0<
                if      domark                  \ finish marking first
                then
                %docopy 0=
                if      domark                  \ clear mark
                else    beep                    \ beep on error
                then    szshow ;

: %docut        ( -- )          \ cut the marked lines
                mark1 @ mark2 @ 2dup min toline - abs 1+ 0
                ?do     %ldel
                loop    ;


: docut         ( -- )          \ cut marked lines
                modifiable @ 0= if beep exit then
                markflg @ 0= ?exit              \ leave if not marked
                markflg @ 0<
                if      domark                  \ finish marking first
                then
                %docopy 0=
                if      %docut
                        domark
                then    szshow ;

: %read_paste   ( d1 -- )               \ d1 = len to read
                0 0 ccphndl movepointer \ move back to file beginning
                drop >r                 \ low part of length < 64k
                curadr @ dup r@ +               \ cur cur+dif
                read_end @ curadr @ -           \ rem_len
                cmove>                          \ move the data
                curadr @ r>                     \ dat olen dif
                ccphndl hread dup
                read_len +!                     \ adj file length
                read_end +! ;                   \ & end address

: dopaste       ( -- )          \ paste text into file
                modifiable @ 0= if beep exit then
                putline
                set_ccpfile
                ccphndl hopen
                if      getline
                        beep exit
                then
                currow @ >r
                ccphndl endfile 2dup            \ get file length
                tbuf_end @ read_end @ - 0 d<    \ compare against available
                if      %read_paste
                        calc_lines
                        %gohome
                        modified on             \ we have changed the file
                        r> down_lines
                else    2drop r>drop
                        beep
                then
                ccphndl hclose drop
                getline
                szshow ;

: nseg          ( -- )          \ display next segment in file ~64k segments
\                seg# @ 1+ seg# !
                seg# incr
                szread
                modifiable on btgl
                calc_lines
                gohome up1
                0 scrfline at showbottom szshow ;

: pseg          ( -- )          \ previous segment in file ~64k segments
                seg# @ 1- 0max seg# !
                szread
                modifiable on btgl
                calc_lines
                gohome szshow ;

: dodos         ( -- )          \ spawn a DOS shell after allowing the entry
                                \ of a command line.
                get-cursor >r cursor-on
                0 statline-at
                ."  Enter a command line->" at? eeol at
                dbuf @ count 80 swap #expect span @ dbuf @ c! >text_color
                r> set-cursor
                esc_flg @
                if      end>rev
                        szshow exit     \ leave if user canceled
                then
                dark dbuf @ $sys drop
                at? at                  \ re-init current cursor position
                dbuf @ c@               \ if command line was empty,
                                        \ return without prompting
                if      cr >end_color
                        ."  *** Press a key to continue editing ***"
                        >text_color cr
                        key drop
                then    dark
                instgl instgl
                .current end>rev szstatus szshow ;

: dohelp2       ( -- )          \ display second help screen

                0 scrfline 1- at erase_below
                0 scrfline 1- at
cr >end_color
   ."  SZ was written by Tom Zimmer as an example TCOM application (Public Domain)."
cr ."  TCOM is a Forth Target COMpiler written by Tom Zimmer. Call - (408) 263-8859"
cr
cr ."  The development environment used to create SZ is available for $60.00 from:"
cr
cr ."        Tom Zimmer
cr ."        292 Falcato Drive"
cr ."        Milpitas, Ca. 95035"
cr
>text_color
cr ."             Control Function Keys              ⁄ƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒø"
cr ."      ^F1≥View compile msgs ^F2≥Execute prog    ≥The operation of the Control≥"
cr ."      ^F3≥Compile optimized ^F4≥Edit ZZ.CFG     ≥function keys at left is    ≥"
cr ."      ^F5≥Review ERRORS     ^F6≥<not defined>   ≥set in the file ZZ.CFG. See ≥"
cr ."      ^F7≥Debug program     ^F8≥<not defined>   ≥the file ZZ.TXT for more    ≥"
cr ."      ^F9≥<not defined>    ^F10≥<not defined>   ≥information on these keys.  ≥"
cr 47 spaces                                      ." ¿ƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒŸ"
cr cr
>end_color
cr ."  …Õ Press a key to continue editing Õª  Maximum file size   ^ = Control"
cr ."  »ÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕº  ~60000 characters"
cr ."  Use /B on the DOS command line to start the editor in browse mode."
cr ."  Use the format: SZ <filename> <row> <column>  to specify a starting location."
cr ."  If EDIT MODE below is the same color as this line, then file has been changed."
                >text_color
                key drop ;

: dohelp        ( -- )          \ display a help screen
                putline getline
                cursor-off
                0 scrfline 1- at erase_below
                0 scrfline 1- at
cr >end_color
   ."  SZ was written by Tom Zimmer as an example TCOM application (Public Domain)."
cr ."  TCOM is a Forth Target COMpiler written by Tom Zimmer. Call - (408) 263-8859"
>text_color
cr ."   ESC/F1≥this HELP scrn     F2≥screen Top       alt-F2≥Browse prev 60k segment"
cr ."       F3≥Mark start/end     F4≥screen Bottom    alt-F4≥Browse next 60k segment"
cr ."       F5≥compile  <<ƒƒƒƒø   F6≥Search  new      alt-F6≥Find    again same"
cr ."       F7≥debug    <<ƒƒƒƒ¥   F8≥Replace new      alt-F8≥replace again same"
cr ."       F9≥ [ see ZZ.TXT ]Ÿ  F10≥Save & exit     alt-F10≥Discard current file"
cr ."     Home≥To line start    PgUp≥Page up           alt-O≥Open/switch 2nd file"
cr ."      End≥To line end      Pgdn≥Page down         alt-P≥Print current file"
cr ."      Ins≥Insert toggle     Del≥Delete char       alt-W≥Write as NEW filename"
cr ."      TAB≥spaces to TAB                           alt-X≥Cut   marked text (F3)"
cr ."    ^Home≥File strt       ^PgUp≥Scroll up         alt-C≥Copy  marked text (F3)"
cr ."     ^End≥File end        ^PgDn≥Scroll down       alt-V≥Paste cut/copied text"
cr ."       ^A≥Word left          ^F≥Word right        alt-T≥Adjust TAB increment"
cr ."       ^G≥Char delete        ^T≥word delete       alt-A≥Enter ANY character"
cr ."       ^Y≥Line delete        ^U≥Update disk   Shift-TAB≥back to previous TAB"
cr ."       ^L≥Ins page break-   ^O≥Open a file    Shift-F9≥Browse/Edit mode toggle"
cr ."   ^Enter≥DOS command        ^Q≥save & Quit   Shift-F10≥Save & exit"
>end_color
cr ."  …Õ   Press any key for MORE HELP   Õª  Maximum file size   ^ = Control"
cr ."  »ÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕÕº  ~60000 characters"
cr ."  Use /B on the DOS command line to start the editor in browse mode."
cr ."  Use the format: SZ <filename> <row> <column>  to specify a starting location."
cr ."  If EDIT MODE below is the same color as this line, then file has been changed."
                >text_color
                key drop
                dohelp2
                ?cursor-on
                szshow ;

: dofnc         ( c1 -- )       \ handle function characters
                255 min 126 - 0max exec:
\       err     CBS Control Backspace
        kerr    fdel
\       A-9     A-0     A -     A =     CPGUP   133     134     135
        cmd9    cmd10   kerr    kerr    scrlup  kerr    kerr    kerr
\       136     137     138     139     140     141     142     BACKTAB
        kerr    kerr    kerr    kerr    kerr    kerr    kerr    btab
\       A-Q     A-W     A-E     A-R     A-T     A-Y     A-U     A-I
        kerr    szwrite kerr    kerr    settab  kerr    kerr    kerr
\       A-O     A-P     154     155     156     157     A-A     A-S
        ofile   szprnt  kerr    kerr    kerr    kerr    doachar kerr
\       A-D     A-F     A-G     A-H     A-J     A-K     A-L     167
        kerr    kerr    kerr    kerr    kerr    kerr    kerr    kerr
\       168     169     170     171     A-Z     A-X     A-C     A-V
        kerr    kerr    kerr    kerr    kerr    docut   docopy  dopaste
\       A-B     A-N     A-M     179     180     181     182     183
        kerr    kerr    kerr    kerr    kerr    kerr    kerr    kerr
\       184     185     186     F1      F2      F3      F4      F5
        kerr    kerr    kerr    dohelp  scrtop  domark  scrbot  cmd5
\       F6      F7      F8      F9      F10     197     198     HOME
        szfind  cmd7    szrepl  cmd9    dodone  kerr    kerr    homeln
\       UP      PgUp    202     LEFT    204     RIGHT   206     END
        up1     uppage  kerr    left    kerr    right1  kerr    endln
\       DOWN    PgDn    INS     DEL     SF1     SF2     SF3     SF4
        down1   downpg  instgl  fdel    cmd11   cmd12   cmd13   cmd14
\       SF5     SF6     SF7     SF8     SF9     SF10    CF1     CF2
        cmd15   cmd16   cmd17   cmd18   btgl    dodone  cmd1    cmd2
\       CF3     CF4     CF5     CF6     CF7     CF8     CF9     CF10
        cmd3    cmd4    doerrs  cmd6    cmd7    cmd8    cmd9    cmd10
\       AF1     AF2     AF3     AF4     AF5     AF6     AF7     AF8
        ofile   pseg    kerr    nseg    doerrs  szfinda kerr    szrepla
\       AF9     AF10    242     CLEFT   CRIGHT  CEND    CPGDN   CHOME
        kerr    doquit  kerr    wleft   wright  goend   scrldn  gohome
\       A-1     A-2     A-3     A-4     A-5     A-6     A-7     A-8
        cmd1    cmd2    cmd3    cmd4    cmd5    cmd6    cmd7    cmd8 ;

: doctrl        ( c1 -- )       \ handle control characters
                exec:
\       0       1 A     2 B     3 C     4 D     5 E     6 F     7 G
        kerr    wleft   kerr    downpg  right1  up1     wright  fdel
\       8 H     9 TAB   10 J    11 K    12 L    13 M    14 N    15 O
        bdel    dotab   dodos   kerr    inspage doenter kerr    szopen
\       16 P    17 Q    18 R    19 S    20 T    21 U    22 V    23 W
        kerr    dodone  uppage  left    wdel    dosave  kerr    scrlup
\       24 X    25 Y    26 Z    27 ESC  28      29      30      31
        down1   ldel    scrldn  dohelp  kerr    kerr    kerr    kerr ;

: dokey         ( c1 -- )       \ process the key c1, and
                                \ display results
                dup 32 126 between if   dochar exit    then
                dup    126       > if   dofnc  exit    then
                                        doctrl ;

: szedit        ( -- )          \ Edit the current file in memory
                getline                 \ get line we are starting on
                szshow                  \ show the screen
                szline                  \ show current line
                szstatus                \ show status info
                szcursor                \ show edit cursor
                ?not_done on            \ flag as not done yet
                begin   key             \ get a key
                        dokey           \ process the key
                        ?not_done @     \ done yet?
                while   szline          \ show line
                        szstatus        \ show status info
                        szcursor        \ show cursor
                repeat  putline ;       \ save line changes

: fname>pad     ( -- a1 )               \ get string to a text pad
\ ***************************************************************************
\ If we are target compiling, start WORD at the beginning of the line.
\ ***************************************************************************
\U TARGET-INIT  >in off                 \ only if we are targeting
                bl word ;

: ?st_browse    ( -- )          \ do we want to start in browse mode?
                >in @ >r
                bl word 1+ @
                dup  $422F ( /B ) =
                swap $622F ( /b ) = or
                if      modifiable off
                        false tglset
                        r>drop exit
                then    r> >in ! ;

: ?ex_cmd       ( -- )          \ do we want to exit with a command byte?
                off> ?cmd
                >in @ >r
                bl word 1+ @
                dup  $432F ( /C ) =             \       /CMD or
                swap $632F ( /c ) = or          \       /cmd
                if      on> ?cmd
                        rows 4 - !> scrlline
                        get_MSG_file
                        process_msgs
                        doerrs
                        r>drop exit
                then    r> >in ! ;

: ?line/col     ( -- )          \ do we want to start at line/column
                >in @ >r
                bl word number? 0= if 2drop r> >in ! exit then drop
                1- 0max down_lines
                r>drop >in @ >r
                bl word number? 0= if 2drop r> >in ! exit then drop
                1- 0max dup curcol ! ?soff!
                r>drop ;

: szinit        ( -- )                  \ small Z editor initialization
                ?ds: ds_0 !                     \ init DSEG zero
                color_init                      \ init attrib vars for screen
                >text_color                     \ normal text color output
                inserting on                    \ default to Insert mode
                8 tsize !                       \ default tabs to 8 chars
                markflg off                     \ marking is off
                -1 mark1 !                      \ no valid mark start
                -1 mark2 !                      \ no valid mark end
                -1 didfind !                    \ mark as no text found
                seg# off                        \ current segment is zero
                curcol off                      \ first column of
                currow off                      \ first row
                soff off                        \ left edge offset is zero
                fullflag off                    \ memory is not full yet
                scrfline scrrow !               \ start displaying at scr top
             50 ds:alloc dup off sbuf !         \ search string buffer
             50 ds:alloc dup off rbuf !         \ replace string buffer
             64 ds:alloc dup off dbuf !         \ DOS command line buffer
        msg_max ds:alloc dup off =: msg_buf     \ message buffer
          lbsiz ds:alloc dup off =: lbuf        \ line buffer
          b/hcb ds:alloc dup off =: fhndl       \ main file handle
          b/hcb ds:alloc dup off =: ccphndl     \ cut copy paste handle
 ds:free? 300 - ds:alloc =: tbuf                \ initialize text buffer with
                                                \ all remaining ram
             10 ds:alloc tbuf_end !             \ initialize text buffer end
                tbuf curadr !                   \ init current line addr ptr
                tbuf scradr !                   \ and screen top line addr ptr
                lbuf lbsiz blank                \ init LBUF to all spaces
                insmode off instgl              \ start in insert mode
                ;

: sz            ( -- )          \ top level editor application
                szinit                                  \ init most variable
                fname>pad fhndl $>handle                \ get filename
                fhndl 1+ c@ '/' =                       \ if no filename
                if      fhndl off >in off               \ reset to beginning
                then                                    \ of line
                szread                                  \ read in the file
                calc_lines                              \ calculate # lines
                ?st_browse                              \ ? browse mode
                ?line/col                               \ starting line/col
                ?st_browse                              \ ?browse mode again
                ?ex_cmd                                 \ exit with command
                begin   szedit                          \ enter editor
                        dos_prep                        \ prepare for save
                        szsave 0= dup                   \ save if needed
                        if      ds_0 @ #files @L 0 <>   \ more than one file
                                if      drop            \ discard prev bool
                                        ofile           \ then switch files
                                        szsave 0=       \ save it to
                                then
                        then
                until                                   \ if we didn't cancel
                szshow                                  \ final show screen
                szstatus
                cursor-on                               \ turn cursor on
                norm-cursor                             \ rest cursor shape
                ?cmd
                if      0 statline 1+ 2dup    at >text_color eeol
                                      2dup 1+ at             eeol at
\                else    0 statline at >text_color .by eeol \ erase last line
                then    ;                                  \ and leave

FORTH DECIMAL
DEFINED TARGET-INIT NIP #IF     \ Test for whether we are target compiling

\ ***************************************************************************
\ If we are compiling with the TARGET compiler, then do these things.
\ ***************************************************************************

TARGET

: MAIN          ( -- )
                DECIMAL                         \ always select decimal
                INIT-CURSOR                     \ get intial cursor shape
                CAPS ON                         \ ignore cAsE
                ?DS: SSEG !                     \ init search segment
                $FFF0 SET_MEMORY                \ default to 64k code space
                ?ds: ?cs: - $1000 + totmem !    \ save segments used
                DOS_TO_TIB                      \ move command tail to TIB
                COMSPEC_INIT                    \ init command specification
                VMODE.SET                       \ initialize video display
                SZ ;            \ call the real start of the program

#THEN

}

