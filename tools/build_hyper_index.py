#!/usr/bin/env python3
"""
build_hyper_index.py — Phase 1 hypertext index builder for 64Forth.

Reads Resources/Config/HYPER.CFG (F-PC/NEWZ-inspired rules) and writes
Resources/Config/HYPER.NDX (word → file:line).

Usage (from repo root or anywhere):
  python3 tools/build_hyper_index.py
  python3 tools/build_hyper_index.py --src-root 64Forth --cfg 64Forth/Resources/Config/HYPER.CFG

Default --src-root is <repo>/64Forth (the app sources tree).
SPECS paths in the CFG are relative to --src-root.

NDX path rewriting (for VIEW / FROMLIB-style roots):
  Resources/Library/foo.fth  →  Library/foo.fth
  Kernel/foo.s               →  Kernel/foo.s  (unchanged)
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass, field
from glob import glob
from pathlib import Path
from typing import Iterable, List, Optional, Sequence, Tuple


# ---------------------------------------------------------------------------
# CFG
# ---------------------------------------------------------------------------

@dataclass
class TypeRule:
    kind: int
    pattern: str  # unescaped search string


@dataclass
class HyperConfig:
    specs: List[str] = field(default_factory=list)
    excludes: List[str] = field(default_factory=list)
    keeppath: bool = True
    after: int = 0
    before: int = 200
    linemax: int = 500
    stopat: Optional[str] = "\\"
    tabx: bool = True
    types: List[TypeRule] = field(default_factory=list)


def _strip_comment(line: str) -> str:
    # Full-line # comments only when # is first non-space (CFG style).
    s = line.strip()
    if not s or s.startswith("#"):
        return ""
    return line.rstrip("\n\r")


def _parse_quoted(s: str, start: int) -> Tuple[str, int]:
    """Parse "..." from s[start] where start points at opening quote. Returns (body, index_after)."""
    if start >= len(s) or s[start] != '"':
        raise ValueError("expected opening quote")
    i = start + 1
    out = []
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            out.append(s[i + 1])
            i += 2
            continue
        if c == '"':
            return "".join(out), i + 1
        out.append(c)
        i += 1
    raise ValueError("unterminated string")


def load_cfg(path: Path) -> HyperConfig:
    cfg = HyperConfig()
    text = path.read_text(encoding="utf-8", errors="replace")
    for raw in text.splitlines():
        line = _strip_comment(raw)
        if not line.strip():
            continue
        stripped = line.strip()
        if stripped == ";":
            break

        # *EXCLUDE name
        if stripped.upper().startswith("*EXCLUDE"):
            rest = stripped[8:].strip()
            if rest:
                cfg.excludes.append(rest)
            continue

        parts = stripped.split(None, 1)
        key = parts[0].upper()
        rest = parts[1] if len(parts) > 1 else ""

        if key == "SPECS":
            if rest:
                cfg.specs.append(rest.strip())
        elif key == "KEEPPATH":
            cfg.keeppath = rest.strip().upper() in ("ON", "1", "TRUE", "YES")
        elif key == "BLOCKFILE":
            pass  # ignored
        elif key == "AFTER":
            cfg.after = int(rest.strip().split()[0])
        elif key == "BEFORE":
            cfg.before = int(rest.strip().split()[0])
        elif key == "LINEMAX":
            cfg.linemax = int(rest.strip().split()[0])
        elif key == "STOPAT":
            # remainder of line after keyword (may be "\" alone)
            cfg.stopat = rest if rest != "" else None
            if cfg.stopat is not None:
                cfg.stopat = cfg.stopat.strip()
                if cfg.stopat == "":
                    cfg.stopat = None
        elif key == "TABX":
            cfg.tabx = rest.strip().upper() in ("ON", "1", "TRUE", "YES")
        elif key == "TYPE":
            # TYPE n "string"
            m = re.match(r'^(\d+)\s+"(.*)"\s*$', rest)
            if not m:
                # allow TYPE n "str with \" escapes"
                m2 = re.match(r"^(\d+)\s+", rest)
                if not m2:
                    print(f"warning: bad TYPE line: {stripped}", file=sys.stderr)
                    continue
                kind = int(m2.group(1))
                qstart = rest.find('"', m2.end() - 1)
                if qstart < 0:
                    print(f"warning: bad TYPE line: {stripped}", file=sys.stderr)
                    continue
                try:
                    pat, _ = _parse_quoted(rest, qstart)
                except ValueError as e:
                    print(f"warning: {e}: {stripped}", file=sys.stderr)
                    continue
                cfg.types.append(TypeRule(kind, pat))
            else:
                kind = int(m.group(1))
                # Decode simple escapes in pattern
                pat = (
                    m.group(2)
                    .replace("\\\"", '"')
                    .replace("\\\\", "\\")
                )
                cfg.types.append(TypeRule(kind, pat))
        else:
            # Ignore unknown for forward compatibility
            pass
    return cfg


# ---------------------------------------------------------------------------
# Path / file set
# ---------------------------------------------------------------------------

def expand_specs(src_root: Path, specs: Sequence[str], excludes: Sequence[str]) -> List[Path]:
    files: List[Path] = []
    seen = set()
    for spec in specs:
        # pathlib-style ** via glob
        pattern = str(src_root / spec)
        matched = sorted(glob(pattern, recursive=True))
        if not matched and not any(c in spec for c in "*?["):
            p = src_root / spec
            if p.is_file():
                matched = [str(p)]
        for m in matched:
            p = Path(m).resolve()
            if not p.is_file():
                continue
            if p.suffix.lower() not in (".s", ".inc", ".fth", ".fs", ".fr", ".4th", ".txt"):
                # allow .s .inc .fth primarily; skip random matches
                if p.suffix not in (".s", ".inc") and p.suffix.lower() not in (".fth", ".fs", ".fr", ".4th"):
                    continue
            rel = _rel_under(src_root, p)
            if _is_excluded(rel, excludes):
                continue
            key = str(p)
            if key in seen:
                continue
            seen.add(key)
            files.append(p)
    return files


def _rel_under(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def _is_excluded(rel_posix: str, excludes: Sequence[str]) -> bool:
    low = rel_posix.replace("\\", "/")
    for ex in excludes:
        if ex in low or ex in Path(low).name:
            return True
    return False


def ndx_path_for(src_root: Path, path: Path) -> str:
    """Stable path written into HYPER.NDX."""
    rel = _rel_under(src_root, path)
    if rel.startswith("Resources/Library/"):
        return "Library/" + rel[len("Resources/Library/") :]
    return rel


# ---------------------------------------------------------------------------
# Line prep + token extract
# ---------------------------------------------------------------------------

def prepare_line(line: str, cfg: HyperConfig) -> str:
    if len(line) > cfg.linemax:
        line = line[: cfg.linemax]
    if cfg.tabx:
        line = line.expandtabs(8)
    # Column window
    after = max(0, cfg.after)
    before = cfg.before if cfg.before > after else len(line)
    segment = line[after:before]
    if cfg.stopat:
        # Forth line comment: " \" " or start-of-segment "\"
        stop = cfg.stopat
        # Prefer space+stopat ( " \ " ) then bare stopat at index 0
        idx = -1
        sp = " " + stop
        j = segment.find(sp)
        if j >= 0:
            idx = j
        elif segment.startswith(stop):
            idx = 0
        else:
            # also "\t\" + stop
            j = segment.find("\t" + stop)
            if j >= 0:
                idx = j
        if idx >= 0:
            segment = segment[:idx]
    return segment


def is_name_char(c: str) -> bool:
    # Forth names: anything non-whitespace except we stop at obvious delimiters
    return not c.isspace()


def read_forth_name(s: str, i: int) -> Tuple[Optional[str], int]:
    """Read one Forth-ish name starting at i. Handles "quoted" names."""
    n = len(s)
    while i < n and s[i].isspace():
        i += 1
    if i >= n:
        return None, i
    if s[i] == '"':
        try:
            body, j = _parse_quoted(s, i)
            return (body if body else None), j
        except ValueError:
            return None, i + 1
    j = i
    while j < n and is_name_char(s[j]):
        j += 1
    name = s[i:j]
    # Trim trailing punctuation common after names in asm/macros
    while name and name[-1] in ",);":
        name = name[:-1]
    if not name or name in (":", ";", "(", ")", "\\"):
        return None, j
    # Skip pure numbers / empty
    if re.fullmatch(r"[-+]?[0-9]+", name):
        return None, j
    return name, j


def find_all(hay: str, needle: str) -> List[int]:
    if not needle:
        return []
    out = []
    start = 0
    while True:
        i = hay.find(needle, start)
        if i < 0:
            break
        out.append(i)
        start = i + max(1, len(needle))
    return out


# ---------------------------------------------------------------------------
# Scanners
# ---------------------------------------------------------------------------

LABEL_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):(?:\s|$)")


def parse_boot_word_line(raw: str) -> Optional[Tuple[str, str]]:
    """
    Parse a BOOT_WORD "name", "help", imm, CodeLabel line.
    Returns (name, code_label) or None. Handles escaped quotes in name/help.
    """
    s = raw.strip()
    if not s.startswith("BOOT_WORD"):
        return None
    i = len("BOOT_WORD")
    while i < len(s) and s[i].isspace():
        i += 1
    if i >= len(s) or s[i] != '"':
        return None
    try:
        name, i = _parse_quoted(s, i)
    except ValueError:
        return None
    while i < len(s) and s[i] in " \t,":
        i += 1
    if i >= len(s) or s[i] != '"':
        return None
    try:
        _help, i = _parse_quoted(s, i)
    except ValueError:
        return None
    while i < len(s) and s[i] in " \t,":
        i += 1
    # imm
    m = re.match(r"(\d+)", s[i:])
    if not m:
        return None
    i += m.end()
    while i < len(s) and s[i] in " \t,":
        i += 1
    m = re.match(r"([A-Za-z_][A-Za-z0-9_]*)", s[i:])
    if not m:
        return None
    code = m.group(1)
    if not name:
        return None
    return name, code


def is_plausible_name(name: str) -> bool:
    if not name or len(name) > 63:
        return False
    # Assembler directives like .quad / .ascii — not Forth "." or '."'
    if name.startswith(".") and len(name) > 2 and name[1:].replace("-", "").replace("_", "").isalnum():
        return False
    if name in ("//", "/*", "*/", "DOC\"", "DOC"):
        return False
    if re.fullmatch(r"\(\d+", name):  # (408 fragments
        return False
    if re.fullmatch(r"[-+]?[0-9]+", name):
        return False
    # Reject pure prose tokens that snuck out of comments (heuristic)
    if " " in name:
        return False
    return True


def collect_asm_labels(files: Sequence[Path], src_root: Path) -> dict:
    """label -> (ndx_path, line_no 1-based)"""
    labels = {}
    for path in files:
        if path.suffix.lower() not in (".s", ".inc", ".asm"):
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        ndx = ndx_path_for(src_root, path)
        for lineno, line in enumerate(text.splitlines(), 1):
            m = LABEL_RE.match(line.lstrip())
            if m:
                labels[m.group(1)] = (ndx, lineno)
    return labels


@dataclass
class Entry:
    name: str
    path: str  # ndx path
    line: int


# .ascii / .asciz "..." payloads (GAS) — bootstrap colon words live here
ASCII_STR_RE = re.compile(
    r'\.(?:ascii|asciz|string)\s+"((?:[^"\\]|\\.)*)"',
    re.IGNORECASE,
)


def _is_asm_noise_line(raw: str) -> bool:
    s = raw.lstrip()
    return (
        not s
        or s.startswith("//")
        or s.startswith("/*")
        or s.startswith("*")
        or s.startswith(";")
    )


def _is_forth_source(path: Path) -> bool:
    return path.suffix.lower() in (".fth", ".fs", ".fr", ".4th", ".f", ".seq")


def _is_asm_source(path: Path) -> bool:
    return path.suffix.lower() in (".s", ".inc", ".asm", ".S")


def scan_file(
    path: Path,
    src_root: Path,
    cfg: HyperConfig,
    labels: dict,
) -> List[Entry]:
    entries: List[Entry] = []
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as e:
        print(f"warning: cannot read {path}: {e}", file=sys.stderr)
        return entries

    ndx = ndx_path_for(src_root, path)
    lines = text.splitlines()
    asm = _is_asm_source(path)
    forth = _is_forth_source(path)

    for lineno, raw in enumerate(lines, 1):
        # --- BOOT_WORD catalog / co-located rows (real code lines only) ---
        if "BOOT_WORD" in raw and not _is_asm_noise_line(raw):
            if re.match(r"^\s*BOOT_WORD\b", raw):
                parsed = parse_boot_word_line(raw)
                if parsed:
                    name, code = parsed
                    if is_plausible_name(name):
                        if code in labels:
                            p, ln = labels[code]
                            entries.append(Entry(name, p, ln))
                        else:
                            entries.append(Entry(name, ndx, lineno))
                continue

        if asm:
            # Kernel assembly: do NOT run free TYPE 0 over comments/docs —
            # that floods the index with prose. Only:
            #   1) BOOT_WORD (above)
            #   2) Forth text inside .ascii / .asciz strings (forth_init_str)
            for m in ASCII_STR_RE.finditer(raw):
                payload = m.group(1)
                # Unescape minimal GAS escapes
                payload = (
                    payload.replace("\\n", "\n")
                    .replace("\\t", "\t")
                    .replace('\\"', '"')
                    .replace("\\\\", "\\")
                )
                for sub_lineno, sub in enumerate(payload.split("\n"), 0):
                    seg = prepare_line(sub, cfg)
                    if not seg.strip():
                        continue
                    for rule in cfg.types:
                        # Only defining-word prefixes in embedded Forth
                        if rule.kind == 0 and rule.pattern.startswith("BOOT_WORD"):
                            continue
                        if rule.kind == 0:
                            _scan_type0(seg, rule.pattern, ndx, lineno, entries)
                        elif rule.kind == 1:
                            _scan_type1(seg, rule.pattern, ndx, lineno, entries)
            continue

        if not forth:
            # Other text: light scan with comment strip only
            pass

        # --- Forth sources (.fth etc.) ---
        if _is_asm_noise_line(raw) and asm:
            continue

        seg = prepare_line(raw, cfg)
        if not seg.strip():
            continue

        for rule in cfg.types:
            if rule.kind == 0:
                if rule.pattern.startswith("BOOT_WORD"):
                    continue  # already handled
                _scan_type0(seg, rule.pattern, ndx, lineno, entries)
            elif rule.kind == 1:
                _scan_type1(seg, rule.pattern, ndx, lineno, entries)
            elif rule.kind == 2:
                _scan_type2(seg, rule.pattern, ndx, lineno, entries)
            elif rule.kind == 4:
                _scan_type4(seg, rule.pattern, ndx, lineno, entries)
    return entries


def _scan_type0(seg: str, prefix: str, ndx: str, lineno: int, entries: List[Entry]) -> None:
    for pos in find_all(seg, prefix):
        # Word boundary before prefix:
        #   - letter prefixes: don't match mid-token (FOOCREATE)
        #   - ": " must not match ALLOT: / NOTE: (alnum or _ before colon)
        if pos > 0:
            prev = seg[pos - 1]
            if prefix[:1].isalnum() or prefix[:1] == "_":
                if is_name_char(prev):
                    continue
            if prefix.startswith(":"):
                if prev.isalnum() or prev in "._":
                    continue
        name, _ = read_forth_name(seg, pos + len(prefix))
        if name and is_plausible_name(name):
            entries.append(Entry(name, ndx, lineno))


def _scan_type1(seg: str, ending: str, ndx: str, lineno: int, entries: List[Entry]) -> None:
    """Word immediately before ending marker (e.g. label:)."""
    s = seg.strip()
    if not s.endswith(ending):
        return
    # first token on line if entire word ends with ending
    body = s[: -len(ending)].strip()
    if not body or " " in body:
        # take last whitespace-separated token
        parts = body.split()
        if not parts:
            return
        name = parts[0] if len(parts) == 1 else parts[-1]
    else:
        name = body
    if name and is_plausible_name(name):
        entries.append(Entry(name, ndx, lineno))


def _scan_type2(seg: str, marker: str, ndx: str, lineno: int, entries: List[Entry]) -> None:
    """Word at start of line before marker string."""
    s = seg.lstrip()
    # first word
    name, j = read_forth_name(s, 0)
    if not name:
        return
    rest = s[j:].lstrip()
    if rest.startswith(marker.strip()) or marker in seg:
        # classic: name then spaces then marker
        after_name = s[j:]
        if marker in after_name or after_name.lstrip().startswith(marker.strip()):
            if is_plausible_name(name):
                entries.append(Entry(name, ndx, lineno))


def _scan_type4(seg: str, marker: str, ndx: str, lineno: int, entries: List[Entry]) -> None:
    s = seg.lstrip()
    if not s.startswith(marker.strip()):
        # allow marker after only leading spaces (already lstrip)
        if not s.startswith(marker):
            return
    # word after marker at line start
    if s.startswith(marker):
        name, _ = read_forth_name(s, len(marker))
        if name and is_plausible_name(name):
            entries.append(Entry(name, ndx, lineno))


# ---------------------------------------------------------------------------
# Emit NDX
# ---------------------------------------------------------------------------

def write_ndx(out_path: Path, entries: Sequence[Entry], src_root: Path, cfg_path: Path) -> None:
    # Group by path, preserve first-seen file order
    by_path: dict[str, List[Entry]] = {}
    path_order: List[str] = []
    for e in entries:
        if e.path not in by_path:
            by_path[e.path] = []
            path_order.append(e.path)
        by_path[e.path].append(e)

    lines: List[str] = [
        "# 64Forth hyper index — generated by tools/build_hyper_index.py",
        f"# src-root: {src_root.as_posix()}",
        f"# cfg: {cfg_path.as_posix()}",
        "# Format: @ path, then NAME linenumber  (case-insensitive lookup)",
        f"# entries: {len(entries)}",
        "",
    ]
    for p in path_order:
        lines.append(f"@ {p}")
        for e in by_path[p]:
            lines.append(f"{e.name} {e.line}")
        lines.append("")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def default_paths() -> Tuple[Path, Path, Path]:
    """Return (repo_root, src_root, cfg_path) guessing from script location."""
    script = Path(__file__).resolve()
    repo = script.parent.parent
    src = repo / "64Forth"
    cfg = src / "Resources" / "Config" / "HYPER.CFG"
    return repo, src, cfg


def main(argv: Optional[Sequence[str]] = None) -> int:
    repo, def_src, def_cfg = default_paths()
    ap = argparse.ArgumentParser(description="Build 64Forth HYPER.NDX from HYPER.CFG")
    ap.add_argument(
        "--src-root",
        type=Path,
        default=def_src,
        help="source root for SPECS (default: <repo>/64Forth)",
    )
    ap.add_argument(
        "--cfg",
        type=Path,
        default=def_cfg,
        help="path to HYPER.CFG",
    )
    ap.add_argument(
        "--out",
        type=Path,
        default=None,
        help="output HYPER.NDX (default: <src-root>/Resources/Config/HYPER.NDX)",
    )
    ap.add_argument(
        "-q",
        "--quiet",
        action="store_true",
        help="less progress output",
    )
    args = ap.parse_args(argv)

    src_root = args.src_root.resolve()
    cfg_path = args.cfg.resolve()
    out_path = (
        args.out.resolve()
        if args.out
        else (src_root / "Resources" / "Config" / "HYPER.NDX")
    )

    if not cfg_path.is_file():
        print(f"error: CFG not found: {cfg_path}", file=sys.stderr)
        return 1
    if not src_root.is_dir():
        print(f"error: src-root not a directory: {src_root}", file=sys.stderr)
        return 1

    cfg = load_cfg(cfg_path)
    if not cfg.specs:
        print("error: no SPECS in CFG", file=sys.stderr)
        return 1
    if not cfg.types:
        print("warning: no TYPE rules in CFG", file=sys.stderr)

    # SPECS in CFG may say Kernel/... or Resources/Library/... relative to src-root.
    # Also accept legacy SPECS Library/** by rewriting to Resources/Library/**
    fixed_specs = []
    for s in cfg.specs:
        if s.startswith("Library/") or s.startswith("Library\\"):
            fixed_specs.append("Resources/" + s.replace("\\", "/"))
        else:
            fixed_specs.append(s)

    files = expand_specs(src_root, fixed_specs, cfg.excludes)
    if not files:
        print("error: no files matched SPECS", file=sys.stderr)
        return 1

    if not args.quiet:
        print(f"src-root: {src_root}")
        print(f"cfg:      {cfg_path}")
        print(f"files:    {len(files)}")
        print(f"types:    {len(cfg.types)}")

    labels = collect_asm_labels(files, src_root)
    if not args.quiet:
        print(f"labels:   {len(labels)}")

    all_entries: List[Entry] = []
    for f in files:
        ent = scan_file(f, src_root, cfg, labels)
        all_entries.extend(ent)
        if not args.quiet and ent:
            print(f"  {ndx_path_for(src_root, f)}: {len(ent)} entries")

    # Dedupe identical (name, path, line); keep order
    seen = set()
    deduped: List[Entry] = []
    for e in all_entries:
        key = (e.name.upper(), e.path, e.line)
        if key in seen:
            continue
        seen.add(key)
        deduped.append(e)
    all_entries = deduped

    write_ndx(out_path, all_entries, src_root, cfg_path)
    if not args.quiet:
        print(f"wrote {len(all_entries)} entries → {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
