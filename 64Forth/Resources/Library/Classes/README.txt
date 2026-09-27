classes.fth
===========

A Forth-2012 rendering of the Win32Forth object extension in Class.f
(Andrew McKewan, later maintained by Tom Zimmer, public domain, the
April 2, 2002 Win32Forth tree).

Load it with:

    S" classes.fth" INCLUDED

Word sets it uses
-----------------

  Core
  Core Extensions     VALUE TO DEFER IS PARSE-NAME NIP TRUE/FALSE are
                      not all required; the file uses PARSE-NAME, VALUE,
                      TO, DEFER, IS, NIP, ?DUP, 2>R, 2R>, 2R@, ERASE,
                      COMPILE, CASE, and : the usual control-flow extensions
  Search-Order        WORDLIST SEARCH-WORDLIST GET-ORDER SET-ORDER
                      SET-CURRENT GET-CURRENT FORTH-WORDLIST
  Search-Order Ext    FIND's counted-string form (Core) is used too
  Exception           CATCH THROW ABORT
  Memory-Allocation   ALLOCATE FREE
  String              COMPARE /STRING SLITERAL
  Double-Number       2@ 2!   (DINT only)

No assembler, no code fields, no vocabulary internals, no Windows calls.

Language
--------

    :CLASS NAME <SUPER SUPERCLASS
        INT FIELD
        :M VERB: ( ... -- ... ) ... ;M
    ;CLASS

    NAME OBJ
    VERB: OBJ

Selectors are ordinary words whose names end in ":". The first :M that
uses a selector creates it. Inside a method, SELF is the current object
and SUPER starts the search in the superclass. Both are early-bound when
the method already exists, and late-bound when it does not.

    VERB: [ words-that-leave-an-object-address ]

evaluates the words between the brackets and sends VERB: to that address.
Brackets are how you force a late send.

    n NEW> CLASS          \ heap object, returned address
    addr DISPOSE          \ sends ~: then FREE
    ' OBJ CLONE NEWNAME
    :OBJECT NAME <SUPER CLASS ... ;OBJECT
    |CLASS NAME ... ;CLASS
    width <INDEXED        \ instances take a count:  n CLASS OBJ
    BYTE SHORT INT DINT BYTES BITS
    RECORD: ... ;RECORD
    ;RECORDSIZE: NAME
    .CLASSES

INT is one cell, not 16 or 32 bits. DINT is two cells. BYTE is an
unsigned byte. SHORT is an unsigned 16-bit little-endian field.
BITS packs into the cell opened by the previous INT. A named object,
executed directly, returns its data address. NEW> and DISPOSE use that
same address. The cell before it is the class pointer.

Ivar names and TO are visible while a method is being compiled. TO still
forwards to the host TO when the name is not an ivar. GET: is the default
when a field name is used. PUT: ADD: AND: OR: XOR: store or modify a
scalar field. A field that is itself an object receives the selector:

    SET: A
    GETX: OBJ.A

What is not portable, or not the same as Win32Forth
----------------------------------------------------

1. Names are folded with ASCII a-z to A-Z before they are stored or
   searched. 64Forth already stores dictionary names in uppercase, so
   this matches that host. On a case-sensitive Forth, write class,
   method, ivar, and selector names in uppercase. Mixed-case source
   will not find the words it just defined.

2. A selector exists only after some :M has created it. Win32Forth's
   interpreter hook treated every unknown word ending in ":" as a
   selector. Doing that requires replacing FIND, which is not a
   portable extension point. Define the method before you send it,
   or create the selector by mentioning it in any :M first.

3. A send compiled before the method exists stays late-bound. Win32Forth
   patched those references when the definition ended. Early binding
   happens only when the method is already in the class or a superclass
   at the send.

4. INT is a cell. On Win32Forth it was 32 bits because a cell was 32
   bits. SHORT is explicitly little-endian. Indexed objects store the
   element width and the count as cells after the fixed data. Win32Forth
   stored those two header fields as 16-bit words.

5. Early binding of a named object compiles that object's address.
   A system that relocates the dictionary when it saves an image must
   not save those compiled addresses, or must relocate them itself.
   Heap objects and `[ ... ]` sends do not embed a dictionary address.

6. Ivar names are on the search order only while :M ... ;M is compiling.
   Win32Forth also found them, at interpret time, through its FIND hook
   when an object was "exposed" to the debugger. Outside a method, use
   a selector (GETX: OBJ) or the object's address.

7. There is no Windows message selector (WM:), no MessageBox error
   dialog, and no link into SEE or DEBUG. A late send is an ordinary
   call to (LATE) or DOT-RUNTIME. ~: runs before DISPOSE; it is not a
   Windows destructor.

8. Not brought across, because each one is tied to the Win32Forth
   dictionary, debugger, or window classes: the doClass / doObj code
   field, ((findm)) and the method-hash table, chain-add debugger
   hooks, unresolved-method patchup, dot-notation through the class
   vocabulary, headerless objects that do not return an address
   (|CLASS here returns the data address), and the built-in String and
   Rectangle classes. Rectangle in classes-test.fth is only an example.

9. Search order deeper than 24 wordlists aborts. Nested :M aborts.
   Bit fields are allowed only in the cell just opened by INT.

10. HEAP-OBJ, DICT-OBJ, and ClassInit: are not re-entrant against the
    variables that hold the class currently being defined (^CLASS).
    A ClassInit: method may send messages and may NEW> other objects.
    It must not open a new :CLASS.

11. This file defines CELL- (Core, but missing from 64Forth). Double
    addition uses U< for the carry. UM+ is not required.

12. EVALUATE is the last action of the words that use it (the bracket
    send, and the body of an :OBJECT). 64Forth's EVALUATE does not
    return to the word that called it. A host whose EVALUATE does
    return still runs the send, because nothing follows it.

13. On 64Forth >BODY is CFA+16. For CREATE, VARIABLE, CONSTANT, VALUE,
    and DEFER that cell is the data, and CFA+8 is the DOES> fragment
    pointer. For a colon word the threaded body also starts at CFA+16,
    and CFA+8 is spare. XT>DATA is >BODY. Class
    and object words are created with ALIGN before CREATE. :M aligns
    before the system `:`. A header that starts unaligned makes the
    code field unaligned, and a cell fetch of it faults.

14. `n NEW>` is only for a class that has been `<INDEXED`. A class that
    is not indexed is created with `NEW> CLASS` and no count under it.
    Heap sends do not take the object from under the selector. Store
    the address (`NEW> POINT VALUE HP`) and write

        11 12 HP SET: [ ]

    The words in the brackets must leave the object on top. Arguments
    stay under it. Empty brackets send to the object already on top.
    Do not hold that address on the return stack across interpreted
    words.

15. CLONE copies the fixed instance data after ClassInit: has run. It
    does not copy the indexed tail. |CLASS returns the data address.

16. Dotted receivers (`GETX: OBJ.A`) are compiled with BEGIN/WHILE.
    classes-test.fth does not exercise them. On 64Forth, DO and ?DO
    inside a DOES> word (the selector runtime) memory-fault, so those
    loops are not used there.

17. Words such as Heap> for NEW>, and <Object or <Class for <SUPER, are
    not defined. SYNONYM is not in the word sets above. On 64Forth the
    dictionary folds case, so :Class and :CLASS are the same word.
