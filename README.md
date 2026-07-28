# 64Forth

**Public domain.**

64Forth's Heritage: When I decided to make yet another Forth system, I went looking for a name for it. I thought of my earlier Forths, like F-PC, and Win32Forth, and thought possibly of Win64Forth. But this Forth is not designed for Windows, so that seemed wrong. I then thought of 64Forth, and went looking for Forth systems on the internet with that name. You will never guess what I found. Yes, you guessed it. 64Forth was the name of my earlier Forth system for the Commodore 64 Computer. In that case, the 64 represented the fact that the Commodore had I believe 64 MB of memory, which was quite a lot in that day. Anyway, I realized that I essentially already had dibs on the 64Forth name, so that is the name I chose for this MacOS M1-M5+ Forth system that is a hybrid of the two previous Forth systems I created this month. I hope you will find 64Forth interesting, at least enough to take a look. It is constructed mostly by Grok with an assembly language kernel, and a Swift code console and extensions, and like TZForth,it has some Libraries built right into the app. It is not as evolved as TZForth, no blocks, no Floating Point, limited File capability, and several other missing word sets, but it is still pretty functional, and it evolved well b beyond PickleForth, that provided the Assembly language kernel for it. The architecture is very interesting, the code words are constructed in assembly, with no headers, just assembly labels. Then the Assembler builds headers for all the CODE words using MACROS. The header structure is pretty traditional, with NFA (Name Field Address), LFA (Link Field Address), FFA (Flag Field Address), CFA (Code Field Address) followed by the BODY address. I have added an additional HFA (Help Field Address) that sits before the NFA, and is pointed to by an offset value in the FFA. The FFA hods the immediate flag, and also hold an offset value to the NFA, which makes traversal around the header pretty easy. Go Forth and prosper!

64Forth is a **macOS SwiftUI console app** whose **execution engine** is the **PickleForth ARM64 assembly kernel**, while the **host** (console, menus, Resources layout, FROMLIB-style library paths) follows **TZForth**.

| | Terminal kernel | Full Swift Forth | Hybrid (this project) |
|--|-----------------|------------------|------------------------|
| Project | PickleForth | TZForth | **64Forth** |
| UI | Terminal | SwiftUI console | SwiftUI console |
| Engine | `forth.s` ITC | Swift `TZForth` class | `forth.s` ITC (embed) |
| Libraries | cwd / absolute | `Resources/Library` + FROMLIB | same as TZForth (target) |

See **[DESIGN.md](DESIGN.md)** for the integration plan and phases.

---

## Layout

```text
64Forth/
  DESIGN.md
  README.md
  64Forth.xcodeproj/
  64Forth/
    App/           SwiftUI entry + content
    Host/          FileHost, KernelBridge (Swift ↔ kernel)
    Kernel/        forth.s, boot_words.inc, colon_words.inc
    Resources/     AutoLoad/, Library/, Docs/  → copied into app bundle
    Assets.xcassets/
```

---

## Status

- [x] Project folder and design doc  
- [x] Kernel sources copied from PickleForth (`_kernel_cold_start` entry, not `_main`)  
- [x] SwiftUI app shell + console  
- [x] Resource folders (AutoLoad sample, Library/BigInteger & PI samples)  
- [x] Embeddable `kernel_init` / `kernel_eval` / host EMIT·KEY (Phase 1)  
- [x] Console parity: protected region, Return commit, ↑/↓ history, Tools menus (Phase 2)  
- [x] FROMLIB + host-driven INCLUDE/FLOAD/REQUIRE (Phase 3)  
- [x] AutoLoad on launch (`Resources/AutoLoad/autoload.fth` → MAIN) (Phase 4)  
- [x] DIR + Phase 5 hardening (reentrancy, bookmarks, entitlements)  
- [x] Search-Order vocabularies + BIG-INTEGER + host BI-MUL/DIVMOD/ISQRT + ALLOCATE  
- [x] Locals (`{:` / `TO`) for full `big-int.fth`  
- [x] `REQUIRED` / absolute-path include registry / `.INCLUDED`  
- [x] Multi-wordlist `FORGET`, `RESIZE`, quoted `INCLUDE "…"` paths, console KEY  

Open `64Forth.xcodeproj` in **full Xcode** (Apple Silicon; not Command Line Tools alone). Build the **64Forth** app target.

### Phase 1 API (assembly ↔ Swift)

| Symbol | Role |
|--------|------|
| `kernel_init()` | Boot dict + `forth_init_str`; returns (no QUIT loop) |
| `kernel_eval(line, n)` | Interpret one line; `" ok\n"` via emit |
| `kernel_set_emit(fn)` | Host character output |
| `kernel_set_key(fn)` | Host KEY (−1 if none) |
| `kernel_set_fromlib(fn)` | Host arms FROMLIB resolve |
| `kernel_set_load_file(fn)` | Host reads file for INCLUDE/FLOAD |

**FROMLIB example** (after rebuild):

```text
FROMLIB FLOAD BigInteger/big-int.fth
```

(Resolves under `Resources/Library`. Full BigInteger stack needs TZForth words not yet in the Pickle kernel — use simple `.fth` files to smoke-test loads.)

See `64Forth/Kernel/kernel_api.h`. Do **not** call `_kernel_cold_start` from the UI.

---

## Chatting with Grok (important)

You are currently able to open Grok in **any project root**. Treat **one primary folder per chat**:

| Work on… | Start Grok / open project from… |
|----------|----------------------------------|
| **64Forth** (this hybrid app) | `~/Documents/XCodeProjects/64Forth` |
| **PickleForth** (terminal kernel only) | `~/Documents/XCodeProjects/PickleForth` |
| **TZForth** (Swift engine reference) | `~/Documents/XCodeProjects/TZForth` |

**Recommendations:**

1. **New chat when you switch products** — e.g. finish a PickleForth kernel chat, then open a **new** Grok session with cwd = `64Forth`. That keeps commits, paths, and context from mixing.  
2. **Point Grok at 64Forth** by opening that folder in the tool / starting the session from that directory (same as you did for PickleForth).  
3. You can still **read** PickleForth or TZForth from a 64Forth chat when integrating (`../PickleForth`, `../TZForth`); prefer **writing** only under `64Forth` unless you explicitly want a PickleForth fix.  
4. Kernel improvements: implement/test in PickleForth when pure assembly is easier, then **copy or cherry-pick** into `64Forth/64Forth/Kernel/`.

Use a **64Forth-rooted** Grok session for hybrid-app work; keep PickleForth sessions for pure terminal-kernel experiments.

---

## Origins

- Kernel lineage: PickleForth (ITC ARM64).  
- Host/UX lineage: TZForth (SwiftUI console, Resources, FROMLIB concepts).  
- Both public domain; 64Forth is public domain as well.
