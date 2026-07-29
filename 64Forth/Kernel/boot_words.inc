// ============================================================================
// Boot word catalog (CODE primitives)
// ============================================================================
// One line per word:
//   BOOT_WORD "NAME", "( stack ) description", imm, CodeLabel
//
// imm: 0 = normal, 1 = IMMEDIATE
// CodeLabel: assembly entry point (XDUP, XDROP, DOEXIT, ...)
// Helps sourced from TZForth primitiveHelpData (+ Pickle-specific notes).
// ============================================================================

// Dense table row: name*, help*, imm, code*.
// Strings live in __TEXT,__cstring so the table stays contiguous (4 quads/row).
.macro BOOT_WORD name, help, imm, code
    .quad .Lbw_n\@, .Lbw_h\@, \imm, \code
    .section __TEXT,__cstring,cstring_literals
.Lbw_n\@:
    .asciz "\name"
.Lbw_h\@:
    .asciz "\help"
    .previous
.endm

.align 8
boot_word_table:
    BOOT_WORD "EXIT", "EXIT ( -- ) return from colon definition", 0, DOEXIT
    BOOT_WORD ";", "; ( -- ) end colon definition (immediate)", 1, XSEMI
    BOOT_WORD "LIT", "LIT ( -- n ) internal: literal value", 0, XLit
    BOOT_WORD "DUP", "DUP ( n -- n n ) duplicate top", 0, XDUP
    BOOT_WORD "DROP", "DROP ( n -- ) discard top", 0, XDROP
    BOOT_WORD "SWAP", "SWAP ( a b -- b a ) swap top two", 0, XSWAP
    BOOT_WORD "OVER", "OVER ( a b -- a b a ) copy second", 0, XOVER
    BOOT_WORD "ROT", "ROT ( a b c -- b c a ) rotate top three", 0, XROT
    BOOT_WORD "NIP", "NIP ( a b -- b ) nip", 0, XNIP
    BOOT_WORD "TUCK", "TUCK ( a b -- b a b ) tuck", 0, XTUCK
    BOOT_WORD "PICK", "PICK ( n -- n ) pick", 0, XPICK
    BOOT_WORD ">R", ">R ( n -- ) ( R: -- n ) to return stack", 0, XTOR
    BOOT_WORD "R>", "R> ( -- n ) ( R: n -- ) from return stack", 0, XRTO
    BOOT_WORD "R@", "R@ ( -- n ) ( R: n -- n ) copy top of return stack", 0, XRFETCH
    BOOT_WORD "+", "+ ( n1 n2 -- n ) addition", 0, XPLUS
    BOOT_WORD "-", "- ( n1 n2 -- n ) subtraction", 0, XMINUS
    BOOT_WORD "*", "* ( n1 n2 -- n ) multiplication", 0, XSTAR
    BOOT_WORD "/", "/ ( n1 n2 -- quot ) division (quotient)", 0, XSLASH
    BOOT_WORD "MOD", "MOD ( n1 n2 -- rem ) modulo", 0, XMOD
    BOOT_WORD "/MOD", "/MOD ( n1 n2 -- rem quot ) remainder and quotient", 0, XSLMOD
    BOOT_WORD "=", "= ( n1 n2 -- flag ) equal", 0, XEQUAL
    BOOT_WORD "<", "< ( n1 n2 -- flag ) less than", 0, XLESS
    BOOT_WORD ">", "> ( n1 n2 -- flag ) greater than", 0, XGREATER
    BOOT_WORD "U<", "U< ( u1 u2 -- flag ) unsigned less", 0, XULESS
    BOOT_WORD "U>", "U> ( u1 u2 -- flag ) unsigned greater", 0, XUGREATER
    BOOT_WORD "AND", "AND ( n1 n2 -- n ) bitwise and", 0, XAND
    BOOT_WORD "OR", "OR ( n1 n2 -- n ) bitwise or", 0, XORR
    BOOT_WORD "XOR", "XOR ( n1 n2 -- n ) bitwise xor", 0, XXOR
    BOOT_WORD "INVERT", "INVERT ( n -- ~n ) bitwise invert", 0, XINVERT
    BOOT_WORD "0=", "0= ( n -- flag ) zero?", 0, XZEQUAL
    BOOT_WORD "0<", "0< ( n -- flag ) negative?", 0, XZLESS
    BOOT_WORD "0<>", "0<> ( x -- flag ) not zero?", 0, XZNOTEQUAL
    BOOT_WORD "0>", "0> ( n -- flag ) positive?", 0, XZGREATER
    BOOT_WORD "WITHIN", "WITHIN ( n1|u1 n2|u2 n3|u3 -- flag ) n2<=n1<n3 (unsigned wrap)", 0, XWITHIN
    BOOT_WORD "TRUE", "TRUE ( -- -1 ) true flag", 0, XTRUE
    BOOT_WORD "FALSE", "FALSE ( -- 0 ) false flag", 0, XFALSE
    BOOT_WORD "1+", "1+ ( n -- n+1 ) increment", 0, XONEPLUS
    BOOT_WORD "1-", "1- ( n -- n-1 ) decrement", 0, XONEMINUS
    BOOT_WORD "CELL", "CELL ( -- n ) address unit size in bytes (8)", 0, XCELL
    BOOT_WORD "CELLS", "CELLS ( n -- n ) cells to address units", 0, XCELLS
    BOOT_WORD "@", "@ ( addr -- n ) fetch cell", 0, XFETCH
    BOOT_WORD "!", "! ( n addr -- ) store cell", 0, XSTORE
    BOOT_WORD "C@", "C@ ( addr -- byte ) fetch byte", 0, XCFETCH
    BOOT_WORD "C!", "C! ( byte addr -- ) store byte", 0, XCSTORE
    BOOT_WORD "+!", "+! ( n addr -- ) add to memory", 0, XPLUSSTORE
    BOOT_WORD "EMIT", "EMIT ( c -- ) emit character", 0, XEMIT
    BOOT_WORD "KEY", "KEY ( -- c ) wait for and return next key code", 0, XKEY
    BOOT_WORD "KEY?", "KEY? ( -- flag ) true if a key is available (does not consume)", 0, XKEYQ
    BOOT_WORD "CR", "CR ( -- ) carriage return / newline", 0, XCR
    BOOT_WORD ".", ". ( n -- ) print number (with space)", 0, XDOT
    BOOT_WORD "U.", "U. ( u -- ) print unsigned", 0, XUDOT
    BOOT_WORD ".S", ".S ( -- ) print data stack contents", 0, XDOTS
    BOOT_WORD "TYPE", "TYPE ( addr len -- ) type string", 0, XTYPE
    BOOT_WORD ".(", ".( ( -- ) print text until ) immediately (immediate)", 1, XDOTPAREN
    BOOT_WORD "STATE", "STATE ( -- addr ) compilation state variable", 0, XSTATE
    BOOT_WORD "BASE", "BASE ( -- addr ) current numeric base variable", 0, XBASE
    BOOT_WORD "]", "] ( -- ) enter compile mode", 0, XRBRA
    BOOT_WORD "[", "[ ( -- ) enter interpret mode (immediate)", 1, XLBRA
    BOOT_WORD "DP", "DP ( -- addr ) dictionary pointer variable address (HERE is DP @)", 0, XDP
    BOOT_WORD "HERE", "HERE ( -- addr ) current dictionary pointer (value)", 0, XHERE
    BOOT_WORD "ALLOT", "ALLOT ( n -- ) allocate n bytes in dictionary", 0, XALLOT
    BOOT_WORD ",", ", ( n -- ) compile a cell", 0, XCOMMA
    BOOT_WORD "FIND", "FIND ( c-addr -- c-addr 0 | xt 1 | xt -1 ) find word from counted string (from WORD)", 0, XFIND
    BOOT_WORD "SEARCH-WORDLIST", "SEARCH-WORDLIST ( c-addr u wid -- 0 | xt 1 | xt -1 ) find in one wordlist", 0, XSEARCH_WORDLIST
    BOOT_WORD "'", "' ( \"<spaces>name\" -- xt ) find name, return xt", 0, XTICK
    BOOT_WORD "EXECUTE", "EXECUTE ( xt -- ) execute the word with the given xt", 0, XEXECUTE
    BOOT_WORD "LITERAL", "LITERAL ( x -- ) compile literal x (immediate)", 1, XLITERAL
    BOOT_WORD "IMMEDIATE", "IMMEDIATE ( -- ) mark latest word as immediate", 0, XIMMEDIATE
    BOOT_WORD ":", ": ( 'name' -- ) start colon definition", 0, XCOLON
    BOOT_WORD "CREATE", "CREATE ( 'name' -- ) create word that pushes its data field (for DOES>)", 0, XCREATE
    BOOT_WORD "0BRANCH", "0BRANCH ( -- ) internal: branch if zero", 0, X0Branch
    BOOT_WORD "BRANCH", "BRANCH ( -- ) internal: unconditional branch", 0, XBranch
    BOOT_WORD "BYE", "BYE ( -- ) exit Forth to the host", 0, XBYE
    BOOT_WORD "INCLUDE", "INCLUDE ( -- ) name|dialog load and interpret file", 0, XINCLUDE
    BOOT_WORD "INCLUDED", "INCLUDED ( c-addr u -- ) load and interpret named file (always)", 0, XINCLUDED
    BOOT_WORD "REQUIRED", "REQUIRED ( c-addr u -- ) INCLUDED if file-spec not yet loaded", 0, XREQUIRED
    BOOT_WORD ".INCLUDED", ".INCLUDED ( -- ) list files registered by INCLUDE/REQUIRED", 0, XDOT_INCLUDED
    BOOT_WORD "FORGET", "FORGET ( 'name' -- ) remove user name and all newer words; system words protected", 0, XFORGET
    BOOT_WORD "CHDIR", "CHDIR ( -- ) path|dialog change working directory", 0, XCHDIR
    BOOT_WORD "PWD", "PWD ( -- ) print logical current directory", 0, XPWD
    BOOT_WORD "DIR", "DIR ( -- ) path|filespec list directory (* ? wildcards; FROMLIB ok)", 0, XDIR
    BOOT_WORD "EDIT", "EDIT ( -- ) name|dialog open in system editor; updates cwd (FROMLIB ok)", 0, XEDIT
    BOOT_WORD "FROMLIB", "FROMLIB ( -- ) next FLOAD/INCLUDE/REQUIRE/EDIT/CHDIR/DIR uses Resources/Library", 0, XFROMLIB
    BOOT_WORD "FROM-LIBRARY", "FROM-LIBRARY ( -- ) synonym for FROMLIB", 0, XFROMLIB
    BOOT_WORD "LATEST", "LATEST ( -- addr ) FORTH wordlist head cell", 0, XLATEST
    BOOT_WORD "CURRENT", "CURRENT ( -- addr ) compilation wordlist variable", 0, XCURRENT
    BOOT_WORD "WORDLIST", "WORDLIST ( -- wid ) create empty word list", 0, XWORDLIST
    BOOT_WORD "FORTH-WORDLIST", "FORTH-WORDLIST ( -- wid ) main FORTH word list", 0, XFORTH_WORDLIST
    BOOT_WORD "GET-CURRENT", "GET-CURRENT ( -- wid )", 0, XGET_CURRENT
    BOOT_WORD "SET-CURRENT", "SET-CURRENT ( wid -- )", 0, XSET_CURRENT
    BOOT_WORD "GET-ORDER", "GET-ORDER ( -- widn ... wid1 n )", 0, XGET_ORDER
    BOOT_WORD "SET-ORDER", "SET-ORDER ( widn ... wid1 n -- )", 0, XSET_ORDER
    BOOT_WORD "PUSH-ORDER", "PUSH-ORDER ( wid -- ) prepend wid to search order", 0, XPUSH_ORDER
    BOOT_WORD "DEFINITIONS", "DEFINITIONS ( -- ) CURRENT = first in search order", 0, XDEFINITIONS
    BOOT_WORD "ONLY", "ONLY ( -- ) search order = FORTH only", 0, XONLY
    BOOT_WORD "ALSO", "ALSO ( -- ) duplicate first search-order entry", 0, XALSO
    BOOT_WORD "PREVIOUS", "PREVIOUS ( -- ) drop first search-order entry", 0, XPREVIOUS
    BOOT_WORD "FORTH", "FORTH ( -- ) set first search-order entry to FORTH", 0, XFORTH
    BOOT_WORD "ORDER", "ORDER ( -- ) print search order and CURRENT", 0, XORDER
    BOOT_WORD "ALLOCATE", "ALLOCATE ( u -- a-addr ior ) allocate u bytes", 0, XALLOCATE
    BOOT_WORD "FREE", "FREE ( a-addr -- ior ) free ALLOCATE block", 0, XFREE
    BOOT_WORD "RESIZE", "RESIZE ( a-addr1 u -- a-addr2 ior ) resize ALLOCATE block", 0, XRESIZE
    BOOT_WORD "GROWMEMORYMB", "GROWMEMORYMB ( n -- ) grow user dictionary to n MiB (once/session; no shrink; max 64)", 0, XGROWMEMORYMB
    BOOT_WORD "BI-MUL", "BI-MUL ( a b r -- ) BIG-INTEGER host multiply", 0, XBIMUL
    BOOT_WORD "BI-DIVMOD", "BI-DIVMOD ( num den quot rem work -- ) BIG-INTEGER host divmod", 0, XBIDIVMOD
    BOOT_WORD "BI-ISQRT", "BI-ISQRT ( a r quot rem work t1 t2 -- ) BIG-INTEGER host isqrt", 0, XBIISQRT
    BOOT_WORD "(LOCAL-INIT)", "(LOCAL-INIT) ( n nInit rev -- ) create locals frame", 0, XLOCAL_INIT
    BOOT_WORD "(LOCAL@)", "(LOCAL@) ( idx -- x ) fetch local", 0, XLOCAL_AT
    BOOT_WORD "(LOCAL!)", "(LOCAL!) ( x idx -- ) store local", 0, XLOCAL_STORE
    BOOT_WORD "{:", "{: ( -- ) declare locals {: args | vals -- outs :} (immediate)", 1, XLOCAL_BRACE
    BOOT_WORD "TO", "TO ( x 'name' -- ) store to VALUE or local (immediate)", 1, XTO_IMM
    BOOT_WORD "WORDS", "WORDS ( ['filter'] -- ) list first search-order wordlist, sorted", 0, XWORDS
    BOOT_WORD "?DUP", "?DUP ( n -- n n | 0 ) dup if non-zero", 0, XQDUP
    BOOT_WORD "[']", "['] ( -- xt ) compile xt of next name", 1, XBRACKET_TICK
    BOOT_WORD "LIT-ADDR", "LIT-ADDR ( -- xt ) address/xt of LIT (for SEE)", 0, XLIT_ADDR
    BOOT_WORD "0BRANCH-ADDR", "0BRANCH-ADDR ( -- xt ) xt of 0BRANCH (for SEE)", 0, X0BRANCH_ADDR
    BOOT_WORD "BRANCH-ADDR", "BRANCH-ADDR ( -- xt ) xt of BRANCH (for SEE)", 0, XBRANCH_ADDR
    BOOT_WORD "EXIT-ADDR", "EXIT-ADDR ( -- xt ) xt of EXIT (for SEE)", 0, XEXIT_ADDR
    BOOT_WORD "SLIT-ADDR", "SLIT-ADDR ( -- xt ) xt of (S\") runtime (for SEE)", 0, XSLIT_ADDR
    BOOT_WORD "NEGATE", "NEGATE ( n -- -n ) negate", 0, XNEGATE
    BOOT_WORD "ABS", "ABS ( n -- u ) absolute value", 0, XABS
    BOOT_WORD "MIN", "MIN ( n1 n2 -- min ) minimum", 0, XMIN
    BOOT_WORD "MAX", "MAX ( n1 n2 -- max ) maximum", 0, XMAX
    BOOT_WORD "LSHIFT", "LSHIFT ( n bits -- n ) logical left shift", 0, XLSHIFT
    BOOT_WORD "RSHIFT", "RSHIFT ( n bits -- n ) logical right shift", 0, XRSHIFT
    BOOT_WORD "<>", "<> ( n1 n2 -- flag ) not equal", 0, XNEQUAL
    BOOT_WORD "PARSE", "PARSE ( xchar -- c-addr u ) parse text delimited by xchar in SOURCE (UTF-8; updates >IN)", 0, XPARSE
    BOOT_WORD "WORD", "WORD ( char -- addr ) parse input up to delimiter char, return addr of counted string (trailing NUL)", 0, XWORD
    BOOT_WORD "\\", "\\ ( -- ) comment to end of line (immediate)", 1, XBACKSLASH
    BOOT_WORD "\\S", "\\S ( -- ) stop rest of FLOAD/INCLUDE file or multi-line console paste (immediate; also \\s)", 1, XBACKSLASH_S
    BOOT_WORD "(", "( -- ) comment until ) (immediate)", 1, XPAREN
    BOOT_WORD "DOCON-ADDR", "DOCON-ADDR ( -- addr ) address of DOCON code", 0, XDOCON_ADDR
    BOOT_WORD "DOCOL-ADDR", "DOCOL-ADDR ( -- addr ) address of DOCOL code (colon definitions)", 0, XDOCOL_ADDR
    BOOT_WORD "SOURCE", "SOURCE ( -- c-addr u ) current input source buffer and length", 0, XSOURCE
    BOOT_WORD ">IN", ">IN ( -- addr ) current input pointer variable ( >IN @ for offset)", 0, XTOIN
    BOOT_WORD "(S\")", "(S\") ( -- c-addr u ) runtime for S\" / .\"", 0, XSLIT
    BOOT_WORD "S\"", "S\" ( -- c-addr u ) compile/interpret \"-delimited string (leaves addr u)", 1, XSQUOTE
    BOOT_WORD ".\"", ".\" ( -- ) print text until \" (immediate)", 1, XDOTQ
    BOOT_WORD "(DO)", "(DO) ( limit start -- ) internal runtime for DO (setup rstack)", 0, XDO_RT
    BOOT_WORD "(?DO)", "(?DO) ( limit start -- ) internal runtime for ?DO", 0, XQDO_RT
    BOOT_WORD "(LOOP)", "(LOOP) ( -- ) internal runtime for LOOP", 0, XLOOP_RT
    BOOT_WORD "(+LOOP)", "(+LOOP) ( n -- ) internal runtime for +LOOP", 0, XPLUSLOOP_RT
    BOOT_WORD "I", "I ( -- n ) current DO loop index", 0, XI
    BOOT_WORD "J", "J ( -- n ) outer DO loop index (for nested loops)", 0, XJ
    BOOT_WORD "UNLOOP", "UNLOOP ( -- ) discard current DO loop params from rstack", 0, XUNLOOP
    BOOT_WORD "LEAVE", "LEAVE ( -- ) exit current DO loop (branch to after LOOP)", 0, XLEAVE
    BOOT_WORD "(DOES>)", "(DOES>) ( -- ) internal: patch latest CREATE word for DOES> and return from parent", 0, XDOES_RT
    BOOT_WORD "PAD", "PAD ( -- addr ) transient user scratch (1024 bytes); not used by system parsers", 0, XPAD
    BOOT_WORD "DOES>", "DOES> ( -- ) modify last CREATE'd word to execute the following code with data addr on stack (immediate)", 1, XDOES
    BOOT_WORD "EVALUATE", "EVALUATE ( i*x c-addr u -- j*x ) interpret the string as Forth source", 0, XEVALUATE
    BOOT_WORD "CATCH", "CATCH ( xt -- n ) execute xt; push 0 or throw code", 0, XCATCH
    BOOT_WORD "THROW", "THROW ( n -- ) raise exception n (0 is no-op)", 0, XTHROW
    BOOT_WORD "(CATCH-OK)", "(CATCH-OK) ( -- 0 ) CATCH success path", 0, XCATCH_OK
    BOOT_WORD "CONTAINS", "CONTAINS ( hay-a hay-u ned-a ned-u -- flag ) case-insensitive substring", 0, XCONTAINS
    BOOT_WORD "MS@", "MS@ ( -- u ) wall-clock milliseconds since epoch", 0, XMSFETCH
    BOOT_WORD "MS", "MS ( u -- ) wait at least u milliseconds (OS sleep; yields)", 0, XMS
    BOOT_WORD "TIME&DATE", "TIME&DATE ( -- sec min hour day month year ) local wall time", 0, XTIME_DATE
    BOOT_WORD "R/O", "R/O ( -- fam ) read-only file access method", 0, XR_O
    BOOT_WORD "W/O", "W/O ( -- fam ) write-only file access method", 0, XW_O
    BOOT_WORD "R/W", "R/W ( -- fam ) read/write file access method", 0, XR_W
    BOOT_WORD "BIN", "BIN ( fam1 -- fam2 ) add binary to file access method", 0, XBIN
    BOOT_WORD "OPEN-FILE", "OPEN-FILE ( c-addr u fam -- fileid ior )", 0, XOPEN_FILE
    BOOT_WORD "CREATE-FILE", "CREATE-FILE ( c-addr u fam -- fileid ior )", 0, XCREATE_FILE
    BOOT_WORD "CLOSE-FILE", "CLOSE-FILE ( fileid -- ior )", 0, XCLOSE_FILE
    BOOT_WORD "READ-FILE", "READ-FILE ( c-addr u1 fileid -- u2 ior )", 0, XREAD_FILE
    BOOT_WORD "WRITE-FILE", "WRITE-FILE ( c-addr u fileid -- ior )", 0, XWRITE_FILE
    BOOT_WORD "READ-LINE", "READ-LINE ( c-addr u1 fileid -- u2 flag ior )", 0, XREAD_LINE
    BOOT_WORD "WRITE-LINE", "WRITE-LINE ( c-addr u fileid -- ior )", 0, XWRITE_LINE
    BOOT_WORD "FILE-POSITION", "FILE-POSITION ( fileid -- ud ior )", 0, XFILE_POSITION
    BOOT_WORD "FILE-SIZE", "FILE-SIZE ( fileid -- ud ior )", 0, XFILE_SIZE
    BOOT_WORD "REPOSITION-FILE", "REPOSITION-FILE ( ud fileid -- ior )", 0, XREPOSITION_FILE
    BOOT_WORD "RESIZE-FILE", "RESIZE-FILE ( ud fileid -- ior )", 0, XRESIZE_FILE
    BOOT_WORD "DELETE-FILE", "DELETE-FILE ( c-addr u -- ior )", 0, XDELETE_FILE
    BOOT_WORD "RENAME-FILE", "RENAME-FILE ( c-addr1 u1 c-addr2 u2 -- ior )", 0, XRENAME_FILE
    BOOT_WORD "FILE-STATUS", "FILE-STATUS ( c-addr u -- x ior )", 0, XFILE_STATUS
    BOOT_WORD "FLUSH-FILE", "FLUSH-FILE ( fileid -- ior )", 0, XFLUSH_FILE
    BOOT_WORD "UNUSED", "UNUSED ( -- u ) bytes remaining in dictionary (HERE to dictionary limit)", 0, XUNUSED
    BOOT_WORD "REDEF-WARNING", "REDEF-WARNING ( -- addr ) variable; nonzero warns on redefine", 0, XREDEF_WARNING
    BOOT_WORD "USER-DICT", "USER-DICT ( -- addr ) base of user dictionary", 0, XUSER_DICT
    BOOT_WORD "SP0", "SP0 ( -- addr ) empty data-stack DSP", 0, XSP0
    BOOT_WORD "SP@", "SP@ ( -- addr ) current DSP under TOS", 0, XSPFETCH
    BOOT_WORD "SP!", "SP! ( n -- ) set data stack pointer (updates both cell and internal)", 0, XSPSTORE
    BOOT_WORD "SPACES", "SPACES ( n -- ) emit n spaces", 0, XSPACES
    BOOT_WORD "C,", "C, ( b -- ) compile a byte", 0, XCCOMMA
    BOOT_WORD "S>D", "S>D ( n -- d ) sign extend single to double", 0, XSTOD
    BOOT_WORD "2*", "2* ( x1 -- x2 ) shift left one bit (multiply by two)", 0, XTWOSTAR
    BOOT_WORD "2/", "2/ ( x1 -- x2 ) arithmetic shift right one bit (divide by two)", 0, XTWOSLASH
    BOOT_WORD "2@", "2@ ( addr -- n1 n2 ) fetch two cells", 0, XTWOFETCH
    BOOT_WORD "2!", "2! ( n1 n2 addr -- ) store two cells", 0, XTWOSTORE
    BOOT_WORD "UM*", "UM* ( u1 u2 -- ud ) unsigned double multiply", 0, XUMSTAR
    BOOT_WORD "M*", "M* ( n1 n2 -- d ) signed double multiply (low high)", 0, XMSTAR
    BOOT_WORD "UM/MOD", "UM/MOD ( ud u -- rem quot ) unsigned divmod", 0, XUMMOD
    BOOT_WORD "SM/REM", "SM/REM ( d n -- rem quot ) symmetric divmod", 0, XSMREM
    BOOT_WORD "FM/MOD", "FM/MOD ( d n -- rem quot ) floored divmod", 0, XFMMOD
    BOOT_WORD "D+", "D+ ( d1 d2 -- d3 ) double add", 0, XDPLUS
    BOOT_WORD "D-", "D- ( d1 d2 -- d3 ) double subtract", 0, XDMINUS
    BOOT_WORD "DNEGATE", "DNEGATE ( d1 -- d2 ) negate double", 0, XDNEGATE
    BOOT_WORD "DABS", "DABS ( d -- ud ) absolute value of double", 0, XDABS
    BOOT_WORD "D2*", "D2* ( xd1 -- xd2 ) shift double left 1", 0, XD2STAR
    BOOT_WORD "D2/", "D2/ ( xd1 -- xd2 ) arithmetic shift double right 1", 0, XD2SLASH
    BOOT_WORD "D0=", "D0= ( xd -- flag ) double equal zero?", 0, XD0EQUAL
    BOOT_WORD "D0<", "D0< ( d -- flag ) double negative?", 0, XD0LESS
    BOOT_WORD "D=", "D= ( xd1 xd2 -- flag ) double equal?", 0, XDEQUAL
    BOOT_WORD "D<", "D< ( d1 d2 -- flag ) signed double less", 0, XDLESS
    BOOT_WORD "DU<", "DU< ( ud1 ud2 -- flag ) unsigned double less", 0, XDULESS
    BOOT_WORD "DMIN", "DMIN ( d1 d2 -- d3 ) minimum of two doubles", 0, XDMIN
    BOOT_WORD "DMAX", "DMAX ( d1 d2 -- d3 ) maximum of two doubles", 0, XDMAX
    BOOT_WORD "D>S", "D>S ( d -- n ) double to single", 0, XDTOS
    BOOT_WORD "M+", "M+ ( d1|ud1 n -- d2|ud2 ) add single to double", 0, XMPLUS
    BOOT_WORD "2ROT", "2ROT ( x1 x2 x3 x4 x5 x6 -- x3 x4 x5 x6 x1 x2 ) rotate three pairs", 0, XTWOROT
    BOOT_WORD "COMPARE", "COMPARE ( c-addr1 u1 c-addr2 u2 -- n ) string compare -1/0/1", 0, XCOMPARE
    BOOT_WORD "SEARCH", "SEARCH ( c-addr1 u1 c-addr2 u2 -- c-addr3 u3 flag ) find substring", 0, XSEARCH
    BOOT_WORD "QUIT", "QUIT ( -- ) empty return stack, set interpret state, return to outer interpreter", 0, XQUIT
    BOOT_WORD "SOURCE-ID", "SOURCE-ID ( -- id ) input source id (-1 terminal, 0 evaluate, 1 file)", 0, XSOURCE_ID
    BOOT_WORD "REFILL", "REFILL ( -- flag ) attempt to refill the input buffer; flag true if successful", 0, XREFILL
    BOOT_WORD "ACCEPT", "ACCEPT ( c-addr +n1 -- +n2 ) read up to n1 chars from input into buffer", 0, XACCEPT
    BOOT_WORD ">NUMBER", ">NUMBER ( ud1 c-addr1 u1 -- ud2 c-addr2 u2 ) convert string digits to number accumulating in ud", 0, XTONUMBER
    BOOT_WORD "ENVIRONMENT?", "ENVIRONMENT? ( c-addr u -- false | i*x true ) query environment string", 0, XENVIRONMENT_Q
    BOOT_WORD "FILE-ECHO", "FILE-ECHO ( -- addr ) variable controlling loaded-source echo (FLOAD, INCLUDE, …; use with ON/OFF)", 0, XFILE_ECHO
    BOOT_WORD "PARSE-NAME", "PARSE-NAME ( -- c-addr u ) parse name from input (skip leading blanks, BL-delimited)", 0, XPARSE_NAME
    BOOT_WORD "2>R", "2>R ( n1 n2 -- ) (R: -- ) two to return stack", 0, X2TOR
    BOOT_WORD "2R>", "2R> ( -- n1 n2 ) (R: -- ) two from return stack", 0, X2RTO
    BOOT_WORD "2R@", "2R@ ( -- n1 n2 ) (R: -- ) copy two from return stack", 0, X2RFETCH
    BOOT_WORD "ROLL", "ROLL ( n -- ) roll", 0, XROLL
    BOOT_WORD ":NONAME", ":NONAME ( C: -- colon-sys ) ( -- xt ) start anonymous colon definition; ; leaves xt", 0, XNONAME
    BOOT_WORD "(C\")", "(C\") ( -- c-addr ) runtime for C\"", 0, XCSTR
    BOOT_WORD "C\"", "C\" ( -- c-addr ) compile \"-delimited counted string (run-time: addr of length byte)", 1, XCQUOTE
    BOOT_WORD "S\\\"", "S\\\" ( -- ) compile escaped \"-delimited string (leaves c-addr u at run-time)", 1, XSESCAPE
    BOOT_WORD "SAVE-INPUT", "SAVE-INPUT ( -- x1 ... xn n ) save current input source state for RESTORE-INPUT", 0, XSAVE_INPUT
    BOOT_WORD "RESTORE-INPUT", "RESTORE-INPUT ( x1 ... xn n -- flag ) restore input source; flag true if failed", 0, XRESTORE_INPUT
    BOOT_WORD "SETDOC", "SETDOC ( c-addr u -- ) pending help for next defining word", 0, XSETDOC
    .quad 0, 0, 0, 0

.equ BOOT_WORD_COUNT, 200

// Empty help used by : / CREATE / :NONAME
.align 8
boot_h_empty:
    .asciz ""

// C strings for _boot_cache_cfa
.align 8
boot_cmp_lit: .asciz "LIT"
boot_cmp_exit: .asciz "EXIT"
boot_cmp_slit: .asciz "(S\")"
boot_cmp_cstr: .asciz "(C\")"
boot_cmp_type: .asciz "TYPE"
boot_cmp_branch: .asciz "BRANCH"
boot_cmp_0branch: .asciz "0BRANCH"
boot_cmp_does_rt: .asciz "(DOES>)"
boot_cmp_catch_ok: .asciz "(CATCH-OK)"
boot_cmp_local_init: .asciz "(LOCAL-INIT)"
boot_cmp_local_at: .asciz "(LOCAL@)"
boot_cmp_local_store: .asciz "(LOCAL!)"
