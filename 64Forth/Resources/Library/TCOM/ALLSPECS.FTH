\ ALLSPECS.FTH      Return all directories one at a time

REQUIRE FPCTOOLS.fth

8000 constant dirlenmax
\       create dirlist dirlenmax 100 + allot
      0 value dirlist
      0 value dirlistlen
      0 value dirptr
  16 constant dirattribute
       handle dirshndl
       handle curhndl
       create startdir ," \" 64 allot
create dirpad 128 allot

: nullcmove     ( a1 a2 -- n1 )
                over 64 2dup 0 scan nip - dup>r nip cmove r> ;
                
: ?dirlist_alloc ( -- )         \ allocate space for dirlist if needed
                dirlist ?exit
                dirlenmax 100 + ds:alloc !> dirlist ;
                
: dir>list      ( a1 -- )       \ append a dir spec to list
                ?dirlist_alloc
                dirlistlen dirlenmax <
                if      dirlist dirlistlen + >r
                        curhndl count 3 - 0max r@ place
                        r@ count + nullcmove r@ c+!
                        r> c@ 1+ +!> dirlistlen
                else    drop
                then    ;
                
: nulltype      ( a1 -- )
                12 2dup 0 scan nip - type space ?cr ;
                
: $getdirs      ( a1 --- )
                dirshndl $>handle         \ get directory spec
                dirpad SET-DTA
                dirshndl >nam $10 find-first
                begin   255 and 0=
                while   dirpad 21 + c@ dirattribute =
                        dirpad 30 + c@ '.' <> and
                        if      dirpad 30 + dir>list
                        then    find-next
                repeat  ;
                
: getdirs       ( -- )
                ?dirlist_alloc
                dirlist dirlenmax 100 + erase
                startdir count dup 1+ =: dirlistlen dirlist place
                dirlist
                begin   dup c@
                        ?keypause
                while             curhndl clr-hcb
                        dup count curhndl place
                                  curhndl count + 1- c@ '\' <>
                        if  " \"  curhndl +place
                        then
                        " *.*"    curhndl +place
                                  curhndl count cr type space
                                  curhndl $getdirs
                        count +
                repeat  drop dirlist =: dirptr ;

: nextdir       ( -- a1 )
                dirptr dup count dup
                if      + =: dirptr
                else    2drop
                then    ;
\S

