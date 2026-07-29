\ string.fth — ANS String word set spot-checks from TZForth ANS-VALIDATE / FTEST
\
\ Requires: tester.fth already loaded
\ Loaded by ANS-VALIDATE.fth via relative FLOAD
\
\ Use CHAR (not [CHAR]) while interpreting.
\ NOT a formal ANS certificate. Prefer Hayes stringtest.fth.

DECIMAL
ONLY FORTH DEFINITIONS

CR .( === String ===) CR

CREATE ST-BUF 64 ALLOT

\ --- COMPARE ---
S" abc" S" abc" COMPARE 0= S" COMPARE=" EXPECT
S" ab" S" abc" COMPARE -1 = S" COMPARE<" EXPECT
S" abcd" S" abc" COMPARE 1 = S" COMPARE>" EXPECT

\ --- /STRING ---
S" abcdef" 2 /STRING NIP 4 = S" /STRING-u" EXPECT
S" abcdef" 2 /STRING DROP C@ CHAR c = S" /STRING-c" EXPECT

\ --- -TRAILING ---
S" abc   " -TRAILING NIP 3 = S" -TRAILING-u" EXPECT
S" abc   " -TRAILING DROP C@ CHAR a = S" -TRAILING-c" EXPECT
S" abc" -TRAILING NIP 3 = S" -TRAILING-none" EXPECT

\ --- BLANK ---
ST-BUF 8 BLANK
ST-BUF C@ BL =
ST-BUF 7 + C@ BL = AND S" BLANK" EXPECT

\ --- SEARCH ---
S" xyzabc" S" abc" SEARCH
NIP NIP S" SEARCH-found" EXPECT

S" xyz" S" abc" SEARCH
NIP NIP 0= S" SEARCH-miss" EXPECT

S" abc" S" " SEARCH
NIP NIP S" SEARCH-empty" EXPECT

S" xyzabc" S" abc" SEARCH
DROP DROP C@ CHAR a = S" SEARCH-at" EXPECT

\ --- CMOVE ---
S" HELLO" ST-BUF SWAP CMOVE
ST-BUF C@ CHAR H =
ST-BUF 4 + C@ CHAR O = AND S" CMOVE" EXPECT

\ --- CMOVE> ---
S" 12345" ST-BUF SWAP CMOVE
ST-BUF ST-BUF 2 + 3 CMOVE>
ST-BUF 2 + C@ CHAR 1 = S" CMOVE>" EXPECT

\ --- S" in colon ---
: ST-HELLO  S" hello" ;
ST-HELLO NIP 5 = S" Squote-u" EXPECT
ST-HELLO DROP C@ CHAR h = S" Squote-c" EXPECT

\ --- ENVIRONMENT? STRING ---
S" STRING" ENVIRONMENT? NIP S" ENV-STRING" EXPECT

\ --- FILL ---
ST-BUF 4 CHAR x FILL
ST-BUF C@ CHAR x =
ST-BUF 3 + C@ CHAR x = AND S" FILL-str" EXPECT

\ --- -TRAILING then COMPARE ---
S" ab  " -TRAILING S" ab" COMPARE 0= S" -TRAIL-CMP" EXPECT

\ --- SEARCH mid-string length remaining ---
\ stack: c-addr u flag  → drop flag, NIP leaves u
S" xyzabc" S" abc" SEARCH
DROP NIP 3 = S" SEARCH-u" EXPECT

CR .( --- String batch done ---) CR
