64Forth tools
=============

64forth-agent
  Headless agent channel wrapper. Passes --agent to the 64Forth binary
  and forwards remaining args (-e, -f, -c, -o, --repl, …).

  Requires a build that includes App/AgentChannel.swift (rebuild in Xcode).

  Examples:
    ./tools/64forth-agent --help
    ./tools/64forth-agent -e '2 2 + .'
    ./tools/64forth-agent -c ~/Documents/64TCOM/64TCOMARM64 -f IFDEMO.fth -o /tmp/out.txt

  Optional: FORTH64_APP=/path/to/64Forth.app

  Full docs: 64Forth/Resources/Docs/Agent-channel.md

build_hyper_index.py
  Hypertext index helper (existing).
