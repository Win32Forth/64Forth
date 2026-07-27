# 64Forth

**Public domain.**

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

## Status (scaffold)

- [x] Project folder and design doc  
- [x] Kernel sources copied from PickleForth (`_kernel_cold_start` entry, not `_main`)  
- [x] SwiftUI app shell + console placeholder  
- [x] Resource folders (AutoLoad sample, Library/BigInteger & PI samples)  
- [ ] Embeddable `kernel_init` / `kernel_eval` / host EMIT·KEY (Phase 1)  
- [ ] Full ConsoleView parity + FROMLIB (Phase 2–3)  

Open `64Forth.xcodeproj` in Xcode (Apple Silicon). Build the **64Forth** app target.

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

This chat was started under PickleForth; after scaffolding, continue 64Forth work in a **64Forth-rooted** session when convenient.

---

## Origins

- Kernel lineage: PickleForth (ITC ARM64).  
- Host/UX lineage: TZForth (SwiftUI console, Resources, FROMLIB concepts).  
- Both public domain; 64Forth is public domain as well.
