64Forth Library — sources under 64Forth/Resources/Library/

Build (TZForth-style Run Script "Copy Library") wipes and re-copies this
folder into the app bundle as Contents/Resources/Library/ on every build
so FROMLIB never sees a stale tree. Same for AutoLoad and Docs.

FROMLIB resolves relative paths under the bundle Library - no machine-specific
absolute paths.

Examples
--------
  FROMLIB FLOAD HayesTest/HayesTest.fth
  FROMLIB FLOAD ANSValidate/ANS-VALIDATE.fth
  FROMLIB FLOAD BigInteger/big-int.fth
  FROMLIB FLOAD PI/pi-test.fth
  FROMLIB FLOAD xchar-smoke.fth

After editing Library .fth files, rebuild/run so the bundle copy updates.

See ANSValidate/README.txt and Docs/README.txt.
