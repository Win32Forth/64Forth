# 64Forth

**Public domain.**

**64Forth's Heritage**: When I decided to make yet another Forth system, I went looking for a name for it. I thought of my earlier Forths, like F-PC, and Win32Forth, and thought possibly of Win64Forth. But this Forth is not designed for Windows, so that seemed wrong. I then thought of 64Forth, and went looking for Forth systems on the internet with that name. You will never guess what I found. Yes, you guessed it. 64Forth was the name of my earlier Forth system for the Commodore 64 Computer. In that case, the 64 represented the fact that the Commodore had I believe 64 MB of memory, which was quite a lot in that day. Anyway, I realized that I essentially already had dibs on the 64Forth name, so that is the name I chose for this MacOS M1-M5+ Forth system that is a hybrid of the two previous Forth systems I created this month. I hope you will find 64Forth interesting, at least enough to take a look. It is constructed mostly by Grok with an assembly language kernel, and a Swift code console and extensions, and like TZForth, it has some Libraries built right into the app. **As of v1.0.0** it includes File-Access, file-backed Blocks, Floating-point (`VOCABULARY FP`), Core/Core Ext, String Ext, Locals, **Facility + Facility Ext** (structures, `EKEY>FKEY`, `K-*`), **FacilityTerminal** full-screen `PAGE`/`AT-XY`, **SZ-EDITOR** (full-screen edit, find, clip, mouse/wheel, Tab indent, `EDIT` entry), **Hypertext** (LOCATE/VIEW, multi-hit ⌘PgUp/Dn, ⌘E, in-app `HYPER-REINDEX`), **Extended Character (UTF-8 XChar)**, **hashed multi-thread wordlists** (`DICT_THREADS`), a green Hayes subset (core through FP/paranoia Excellent), and modular Library **ANSValidate** (~383 passed / 0 failed). Optional later: App Sandbox for store builds, dual-buffer editor, richer reindex TYPE rules. The architecture is very interesting: CODE words are assembly labels; macros build traditional headers (NFA, LFA, FFA, CFA, BODY) plus an HFA (Help Field Address). Go Forth and prosper!


**Getting 64Forth to run on your Mac**: All of the latest security changes Apple has made to MacOS, have made it fairly difficult to run apps obtained from outside the Apple App Store, but it is not impossible. Here is how you to it;

1. **Download the .dmg** file from the '**releases**' folder in the 64Forth development folder.
2. **Open** and view the .jpg image called '**Getting 64Forth to run.jpg**'.
3. This image shows a collage of the dialogs you have to traverse to get the MacOS to allow you to open the app.
4. Don't despair, it's not that hard, just follow along;
5. **Mount the .dmg** file and you will see **64Forth.app**.
6. Drag the app onto your desktop.
7. Hold down the **Control key** and click the app and select **Open** from the menu that pops up.
8. You will get an error dialog that tells you that the app cannot be verified and will not be opened.
9. This last step is important because it sets up the MacOS so that you can now go into **Settings** and tell it to allow the app to open.
10. **Open Settings**, and scroll down to **Privacy & Security**. A list of apps and setting will be displayed.
11. Scroll down to the bottom of the **Privacy & Security** panel and you will see under the **Security** heading where it says '**64Forth.app**' **was blocked to protect your Mac**.
12. To the right of the above message you will see a button **"Open Anyway"**. Click the button.
13. After clicking Open Anyway, another dialog will pop up that says basically **Trash, Open Anyway and Done. Click Open Anyway.**
14. After you click **Open Anyway** in that dialog, **another dialog will pop up and ask you for your password.** This is the final system dialog that is keeping you from running 64Forth. Simply type in your "**Macs" password,** and 64Forth will open and display it's **Opening screen.**
15. You are done, you can now run 64Forth without having to go though this again.

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
    Host/          FileHost, FileAccess, BigIntHost, FloatHost, FacilityTerminal, KernelBridge
    Kernel/        forth.s, boot_words.inc, colon_words.inc, kernel_api.h
    Resources/     AutoLoad/, Library/, Docs/  → copied into app bundle
    Assets.xcassets/
```

---

## Agent channel (headless load / capture)

Automation (Grok, CI, scripts) can drive the kernel without the GUI:

```bash
/Applications/64Forth.app/Contents/MacOS/64Forth --agent -e '2 2 + .'
./tools/64forth-agent -c ~/proj -f smoke.fth -o /tmp/out.txt
```

See **[Resources/Docs/Agent-channel.md](64Forth/Resources/Docs/Agent-channel.md)** and `tools/64forth-agent`.  
Requires a build that includes `App/AgentChannel.swift` (rebuild in Xcode after pull).

---

## Status (v1.2.0)

- [x] **v1.2.0:** ITC DEBUG source-alias highlight (`LIT`/`0BRANCH`/`BRANCH`/`EXIT`); F8 step-out; Esc/`q` abort; ⌘Q while paused; DMG + GitHub release
- [x] **v1.1.9:** ITC DEBUG pause stack isolation + x28 NEXT mirror; locals drain; DOC"/help; DMG + GitHub release
- [x] **v1.1.8:** TCOM debugger host hooks (`TDBG-ARM-KEYS`, `SZ-SIDE-HOOK`); editor/`DEBUG` highlight (`SZ-HIGHLIGHT-NAME`, `DBG-HL-XT`); DMG + GitHub release
- [x] **v1.1.7:** ASMARM64 Library toolkit + `ASM-TESTS`; Open/New/Save As while editor KEY waits; docs `STATUSASM64.md`
- [x] **v1.1.6:** `DEBUG` Forth-level stepper (console + SZ-EDITOR Files-column stacks)
- [x] **v1.1.5:** console caret stays put after mid-line backspace (arrow then delete)
- [x] **v1.1.4:** GRAPHICS complete for tetra — coalesced EMIT, real `TONE` (Hz/tenths), `\ANS` dual-load helpers; see `Library/AppOutput/app-output.fth`
- [x] **v1.1.3:** separate **GRAPHICS** app-output window (Forth-first + thin Swift/`forth.s`)
- [x] **v1.1.2:** agent channel (`--agent` headless load/eval/transcript) — see `Agent-channel.md`
- [ ] **Later (optional):** DMG `/Volumes/…` open noise — see STATUS

**Console header** (GUI): `=== 64Forth 1.2.0 === Aug 31, 2026 7:10 PM ===`  
Stamp the date/time only when finishing a change set for a version, just before DMG + repo push (not every build). Edit `ConsoleView.swift` `banner`.

## Status (v1.1.1)

- [x] Project folder and design doc  
- [x] Kernel sources copied from PickleForth (`_kernel_cold_start` entry, not `_main`)  
- [x] SwiftUI app shell + console  
- [x] Resource folders (AutoLoad sample, Library/BigInteger & PI samples)  
- [x] Embeddable `kernel_init` / `kernel_eval` / host EMIT·KEY (Phase 1)  
- [x] Console parity: protected region, Return commit, ↑/↓ history, Tools menus (Phase 2)  
- [x] FROMLIB + host-driven INCLUDE/FLOAD/REQUIRE (Phase 3)  
- [x] AutoLoad on launch (`Resources/AutoLoad/autoload.fth` → MAIN) (Phase 4)  
- [x] DIR + Phase 5 hardening (reentrancy, bookmarks, entitlements; batched emit)  
- [x] Search-Order vocabularies + BIG-INTEGER + host BI-MUL/DIVMOD/ISQRT + ALLOCATE  
- [x] Locals (`{:` / `TO`) for full `big-int.fth`  
- [x] `REQUIRED` / absolute-path include registry / `.INCLUDED`  
- [x] Multi-wordlist `FORGET`, `RESIZE`, quoted `INCLUDE "…"` paths, console KEY  
- [x] File-Access word set (`FileAccess` host + CODE)  
- [x] Block word set with file volume; `LOAD` restores outer `BLK`  
- [x] Floating-point (`FloatHost` + `VOCABULARY FP`; `ALSO FP` to use)  
- [x] In-app Hayes subset green: core through FP (`FROMLIB FLOAD HayesTest/HayesTest.fth`)  
- [x] v0.6: FIND-before-number, Tools `?`, CODE `DEPTH`, include buffer 256 KiB, Hayes harness  
- [x] String Ext, Locals Ext, Facility structures, Extended Character (UTF-8 XChar)  
- [x] **v0.7.0:** Modular ANS-VALIDATE (~351/0); Facility Ext (`EKEY>FKEY`, `K-*`); `LOAD`/`BLK` restore; docs  
- [x] **v0.8.0:** `FacilityTerminal` cell grid for `PAGE`/`AT-XY`; **SZ-EDITOR** full-screen edit (FROMLIB, open panel, Cmd-S/W/Q, Ctrl-Home/End); `S"`/`."` keep leading spaces after the name blank  
- [x] **v0.8.1:** `ABORT"` compile path uses `-2 POSTPONE LITERAL` (fixes memory fault when compiling e.g. `BI-ENSURE`)  
- [x] **v0.8.2:** ANSValidate `host.fth` (TZForth FTEST high-ROI ports); `SLITERAL` cell-length fix  
- [x] **v0.9.0:** Multi-thread wordlists (`DICT_THREADS` = 16, hash in `_header_build`/FIND); `.THREADS` / `.VOCABULARIES`; `LAST` for `IMMEDIATE`/`ALIAS`/`RECURSE`/`MARKER`; prompt `ok(n)>` with data-stack depth; File-Access multi-result stack fix (`FILE_POP_UNDER`); Tools → Show Library/AutoLoad/Docs opens Finder via `NSWorkspace.open`; ANSValidate ~383/0 + stack hygiene; Hayes fail banners clearer  
- [x] **v0.9.6:** SZ-EDITOR same-file find (⌘←/→, ⌘G/⌘⇧G); status `Selected: "word"`; Hyper ⌘PgUp/Dn; reliable host key delivery (`ForthApplication`)
- [x] **v0.9.7:** SZ-EDITOR line select (gutter / line-start), multi-line ⌘-click ranges, two-level line clipboard + paste before/after line
- [x] **v0.9.8:** SZ-EDITOR two-line help (Cmd-E VIEW, etc.); mouse click no longer scrolls target to row 5
- [x] **v1.0.0:** Hypertext Phases 0–5 complete; SZ-EDITOR production features (find, clip, mouse/wheel, Tab→spaces, `.fth` default path, `EDIT`/`TextEdit`); stack-safe editor exit (`CLEARSTACK`); hardened `DEPTH`/`SP0`/`0BRANCH`
- [x] **v1.0.1:** Kernel assembly shipped as `Library/Sources/` so release VIEW/LOCATE works without a developer tree
- [x] **v1.0.2:** Hyper visit list (back/forward); Cmd-click VIEW; assembly-aware Cmd-←/→ find; Kernel→Library/Sources sync on build; kernel branding 64Forth
- [x] **v1.0.3:** Native code helpers for 64TCOM (`MPROTECT`, `ICACHE-INVAL`, `CALL-NATIVE`, `ALLOCATE-EXEC`)
- [x] **v1.0.4:** JIT entitlements (`com.apple.security.cs.allow-jit`, `allow-unsigned-executable-memory`); `JIT-WPROTECT` / `FREE-EXEC`; `CALL-NATIVE` toggles MAP_JIT exec mode; `kernel_eval` defaults MAP_JIT to write (avoids C! EXC_BAD_ACCESS); `ICACHE-INVAL` one-page-safe; verified with 64TCOM ARM64 `.RUN-ANS-N` / `SAVE-MACHO` (ANS exit 5).
- [x] **v1.0.5:** `SYSTEM ( c-addr u -- n )` — run a shell command via `/bin/sh -c` in the logical cwd (`CHDIR`/`PWD`); stdout/stderr to the console; `n` = exit status (`0` ok, `-1` launch fail). Enables 64TCOM `SAVE-MACHO` auto-`cc` without a separate Terminal window.
- [x] **v1.0.6:** Hyper/VIEW production polish — FORTH-visible `VIEW`/`LOCATE` (survive `ONLY FORTH`); multi-hit status `file(n/m)`; visit list vs multi-hit PgUp/PgDn fixed; path keys `AutoLoad/`/`Library/…`; case-insensitive hit dedup; editor status line trim; SZ-EDITOR/Hyper load path hardening; WORDLIST/REQUIRED fixes; ANS-VALIDATE green. Release: `64Forth/releases/64Forth-1.0.6-macOS.dmg`
- [x] **v1.0.7:** Release reindex path fix — symlink-safe `Library/…` SPECS keys (no bare filenames / mass `HX: skip` on DMG); exclude HayesTest/ANSValidate by full path; quieter `HX: skip` when `MIN-HYPER-NOISE` on. Release: `64Forth/releases/64Forth-1.0.7-macOS.dmg`
- [x] **v1.0.9:** box-drawing chrome, modal Cmd-F find; macOS DMG
- [x] **v1.1.0:** editor + scrollable command pane (Option A); staged evaluate while KEY waits; nested EVALUATE/CATCH safe for FLOAD/Hayes/ANS-VALIDATE; thick striped splitter; live command-pane scroll — see `Resources/Docs/STATUS.md`
- [x] **v1.1.1:** command-pane VIEW (⌘E / ⌘-click); seed/restore console under editor; splitter resize stable; CLS vs FACILITY-OFF; no duplicate Files visits — see `Resources/Docs/STATUS.md`

### Hypertext + SZ-EDITOR (v1.1.1)

| Area | Done |
|------|------|
| **Hyper Phases 0–5** | Index CFG/NDX, offline + in-app reindex, LOCATE/VIEW, multi-hit ⌘PgUp/Dn, ⌘E VIEW, SEE→VIEW, `HYPER-VOC`; kernel sources shipped as `Library/Sources/` for release VIEW |
| **SZ-EDITOR** | Full-screen Facility edit; save/close; find ⌘←/→ ⌘G; cut/copy/paste; mouse + wheel; Tab indent; `EDIT` opens SZ-EDITOR, `TextEdit` keeps system editor |
| **Split command pane** | Facility above + host `ok(n)>` console below; key 133 / `(SZ-CMD@)` / `(SZ-CMD-DONE)`; shared stack; long FLOAD output scrolls live |
| **Command-pane VIEW** | ⌘E / ⌘-click while KEY waits; seed lower pane from pre-editor transcript; no duplicate side-list visits on re-VIEW |
| **Autoload** | Loads editor + Hyper, reindexes on startup when configured |

**Docs:** `Resources/Docs/STATUS.md` (design + phase notes), `Resources/Library/Hyper/README.txt`, `Resources/Library/Editor/SZ-EDITOR-README.txt`, `Resources/Config/README.txt`, `Resources/Docs/README.txt`.

Optional later: persist split ratio, multi-line command paste polish, App Sandbox for store builds, editor dual-buffer.

Open `64Forth.xcodeproj` in **full Xcode** (Apple Silicon; not Command Line Tools alone). Build the **64Forth** app target for a DMG.

### Quick examples

```text
FROMLIB FLOAD BigInteger/big-int.fth
FROMLIB FLOAD HayesTest/HayesTest.fth
ALSO FP
1.5e0 2e0 F+ F.

FROMLIB FLOAD ANSValidate/ANS-VALIDATE.fth

\ Editor + Hyper (often already loaded via AutoLoad)
EDIT myfile              \ SZ-EDITOR; .fth added if no extension
FROMLIB EDIT TCOM/SZ
LOCATE DUP
VIEW SWAP                \ multi-hit: ⌘PgDn / ⌘PgUp
```

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

(Resolves under `Resources/Library`. BigInteger + PI libraries and the Hayes suite are supported on the current kernel/host.)

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
