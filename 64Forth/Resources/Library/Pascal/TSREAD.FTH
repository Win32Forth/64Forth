\\ TSREAD.SEQ    Target sequential LINEREAD support

  LINEREAD support for TCOM. Be sure to use LINEREAD_INIT before trying
to use the LINEREAD function. Some extra DOS memory must be allocated for
the line read buffer which currently defaults to 8000 bytes.

  LINEREAD reads a line into the buffer OUTBUF, and can be upto 255
characters in length. If you lineread a file that does not contain LF
characters, then LINEREAD will automatically break up the file into
255 character lines. Not wonderful perhaps, but better than crashing.

  The read lines will still contain the CRLF character pairs at the
end of the line buffer. You will thus need to remove them before using
the line.

{

FORTH DECIMAL TARGET >LIBRARY   \ A Library file

      0 VALUE IBLEN                \ current input buffer length
 $0A CONSTANT DELIMITER
 255 CONSTANT OBLEN             \ output buffer length
    VARIABLE INSTART
    VARIABLE INLENGTH
 IBMAX array INBUFFER            \ the input buffer
  VARIABLE LOADLINE
  VARIABLE FILEPOINTER          \ most recent read
  VARIABLE LINE_LIMIT           \ line read limit of no LF detected

   0 value handle

 oblen 1+ array outbuf

: .handle   ( --- )
                handle count type ;

: memchk        ( f1 -- )
                if      ." Insufficient Memory"
                        bye
                then ;

: IBRESET       ( --- )
                instart OFF
                inlength OFF
                loadline OFF ;

}

 Perform the following function, and then open a file on the handle
handle. LINEREAD will read lines from this handle into the buffer called
OUTBUF. The address of OUTBUF is also returned by LINEREAD.

{

: LINEREAD_INIT ( -- )          \ initialize the LINEREAD system.
                handle 0=
                if      hndls TO handle
                        handle clr-hcb
                        255 line_limit !
                then
                INBUFFER @ 0=
                if      IBMAX allocate memchk INBUFFER !
                then    ;

: CURPOINTER    ( handle --- currentFilePosition )
                FILE-POSITION drop ;

: savepointer   ( --- )
                handle curpointer inlength @ - filepointer ! ;

: get_aline     ( --- a1 )
                OUTBUF 1 + oblen READ-LINE DROP
                IF DUP OUTBUF C!
                THEN DROP OUTBUF ;


: fillbuff      ( --- )         \ Refill the input buffer.
\ ** if inlength is not adjusted for amount already taken out by instart, then it's wrong.
                INBUFFER instart @ + INBUFFER inlength @ CMOVE
                instart OFF
                
                
                inbseg @ instart @ over 0 inlength @ cmovel
                instart OFF
                inlength @ iblen inlength @ -
                handle INBUFFER exhread         \ perform the actual read
                inlength +!                     \ adjust buffer length
                savepointer ;

: ?fillbuff     ( --- f1 )                      \ f1 = true if refill needed
                oblen inlength @ >
                IF      filepointer @
                
                save_bx
                mov cx, line_limit              \ get longest allowed line
                cmp inlength cx
            u>= if      mov di, # filepointer   \ Set BX to point to FILEPOINTER
                        sub cx, cx              \ clear CX
                        mov cl, outbuf          \ read byte length of OUTBUF
                        add 2 [di], cx          \ Add to 32bit contents
                        adc 0 [di], # 0
                        mov bx, # 0
                        ret
                then                            \ If we got here, then
                mov bx, # -1                    \ go and re-fill the buffer
                ret     end-code

: LINEREAD      ( --- a1 )      \ read a line delimited by crlf
                ?fillbuff       \ re-fill buffer if needed.
                if      fillbuff
                then
                get_aline ;     \ returns line including CRLF

: SEQUP         ( --- )
                lineread_init
                true abort" No more handles available!" ;

: "HOPEN        ( a1 n1 --- f1 ) \ Returns a boolean FALSE for open successful
                lineread_init
                handle hclose drop
                handle ">handle
                handle hopen
                ibreset ;

: $HOPEN        ( a1 -- f1 )    \ Open a file for line reading
                count "hopen ;

: $FILE         ( A1 --- F1 )
                count "hopen
                0.0 handle movepointer       \ reset to beginning of file
                0.0 filepointer 2!
                loadline off                    \ reset file offset
                ibreset ;

: ?OPEN.ERROR   ( f1 --- )
                abort" Open Error!" ;

: SEQDOWN       ( --- )
                lineread_init
                handle hclose drop           \ close the file
                handle clr-hcb ;             \ clear the handle

: CLOSE         ( --- )
                seqdown ;

: ?FILEOPEN     ( --- )                 \ Verify a file is open.
                handle >hndle @ 0<
                abort" A file MUST be open to perform this operation." ;

FORTH TARGET >TARGET

}

