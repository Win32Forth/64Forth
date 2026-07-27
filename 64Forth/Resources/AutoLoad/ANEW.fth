\ ANEW.fth — classic reload marker (TZForth / ANS-style)
\
\ Usage:
\   ANEW source_model
\   ... definitions that belong to this load unit ...
\
\ Behavior:
\   Parse the name following ANEW.
\   If that name is already in the dictionary, FORGET it (and every word
\   defined more recently than it), reclaiming dictionary space.
\   Then CREATE the name so it exists again as the unit marker.
\
\ Typical source file pattern:
\   ANEW MY-MODULE
\   : FOO ... ;
\   : BAR ... ;
\ Reloading the file runs ANEW MY-MODULE again, drops the previous FOO/BAR
\ (and MY-MODULE), and redefines from a clean point.
\
\ Load (AutoLoad boot, cwd = Resources/AutoLoad):
\   FLOAD ANEW.fth
\ Or from console after Tools → AUTOLOAD → VIEW / CHDIR there.
\
\ Uses only standard TZForth words: >IN @ R@ R> BL WORD FIND IF ELSE THEN
\ DROP FORGET CREATE

: ANEW  ( "<spaces>name" -- )
   >IN @ >R                    \ save parse position at start of name
   BL WORD FIND                \ ( c-addr 0 | xt 1 | xt -1 )
   IF                          \ name already defined
      DROP                     \ drop xt
      R@ >IN ! ." Reloading module: " BL WORD count type cr
      R@ >IN !                 \ re-parse same name for FORGET
      FORGET                   \ forget name and all words defined after it
   ELSE
      DROP                     \ drop c-addr (not found)
      R@ >IN ! ." Loading module: " BL WORD count type cr
   THEN
   R> >IN !                    \ re-parse name for CREATE
   CREATE                      \ define the marker word (empty body / DOES-ready)
;
