64Forth Library/Debugger
========================

High-level ITC DEBUG support that does not belong in the kernel cold blob
or under Hyper.

  debug-bp.fth   BREAK / UNBREAK / .BREAKS / BPGO
                 (kernel still owns BREAK-TABLE and (BP-GO))

AutoLoad loads Debugger/debug-bp.fth first, before the editor.

Future home for pause-UI Forth (DBG-PAUSE-XT), token maps (today Hyper/dbg-map.fth),
and other debugger policy moved out of forth.s.
