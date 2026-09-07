#!/usr/bin/env python3
"""Does every switch still cover the enum it is switching over?

The trap this exists for is recorded in ANALYSIS: widen an enum — a new
`PlannedAction.Origin`, a new `Placement.Operation` — and every exhaustive
switch over it stops compiling, in files the change never touched.

It identifies the enum by the case names a switch matches rather than by the
type of the expression, which needs no type checking: a switch whose patterns
are all `.member` of exactly one project enum, with no `default`, must name
every case of it.
"""
import re, sys, pathlib, collections

root = pathlib.Path(sys.argv[1]).resolve()
files = sorted(list((root / "Sortomat").rglob("*.swift")) +
               list((root / "SortomatTests").rglob("*.swift")))

def strip(src):
    src = re.sub(r'"""(?:.|\n)*?"""', '"S"', src)
    src = re.sub(r'"(?:[^"\\\n]|\\.)*"', '"S"', src)
    src = re.sub(r'//[^\n]*', '', src)
    src = re.sub(r'/\*(?:.|\n)*?\*/', '', src)
    return src

def body_of(src, open_idx):
    depth, i = 0, open_idx
    while i < len(src):
        if src[i] == '{': depth += 1
        elif src[i] == '}':
            depth -= 1
            if depth == 0: return src[open_idx+1:i], i
        i += 1
    return "", len(src)

sources = {f: strip(f.read_text()) for f in files}
blob = "\n".join(sources.values())

# ---- project enums with simple cases --------------------------------------
enums = {}
for m in re.finditer(r'\b(?:public\s+|internal\s+|private\s+)?enum\s+(\w+)\s*'
                     r'(?::\s*[^{]+)?\{', blob):
    name = m.group(1)
    body, _ = body_of(blob, m.end() - 1)
    # Only the top level of the enum: a nested type's cases are not ours.
    body = re.sub(r'\{[^{}]*\}', ' ', body)
    cases = set()
    for c in re.finditer(r'^\s*case\s+([^\n]+)$', body, re.M):
        # Drop associated values first: the comma in
        # `case placeholder(token: String, filters: [Filter])` is inside the
        # payload, and splitting on it invents a case called `filters`.
        line = re.sub(r'\([^()]*\)', '', c.group(1))
        for part in line.split(','):
            cm = re.match(r'\s*(\w+)', part)
            if cm: cases.add(cm.group(1))
    if len(cases) >= 2:
        if name in enums: enums[name] = None          # ambiguous name
        else: enums[name] = cases
enums = {k: v for k, v in enums.items() if v}

by_case = collections.defaultdict(set)
for name, cases in enums.items():
    for c in cases: by_case[c].add(name)

problems = 0
switches = 0
for path, src in sources.items():
    for m in re.finditer(r'\bswitch\b[^\n{]*\{', src):
        body, end = body_of(src, m.end() - 1)
        inner = re.sub(r'\{[^{}]*\}', ' ', body)
        if re.search(r'^\s*default\s*:', inner, re.M): continue
        patterns = re.findall(r'^\s*case\s+([^\n:]+):', inner, re.M)
        if not patterns: continue
        names, dotted_only, optional = set(), True, False
        for p in patterns:
            for part in p.split(','):
                part = part.strip()
                # `case .text(let t)?:` — switching over an Optional, whose
                # own `.none`/`.some` are not the wrapped enum's cases and
                # would match some *other* enum that happens to have a `none`.
                if part.endswith("?"): optional = True
                dm = re.match(r'^\.(\w+)', part)
                if dm: names.add(dm.group(1))
                elif part: dotted_only = False
        if optional or "none" in names and "some" in names: continue
        if not dotted_only or len(names) < 2: continue
        candidates = [e for e in enums if names <= enums[e]]
        if len(candidates) != 1: continue        # can't identify it confidently
        enum = candidates[0]
        switches += 1
        missing = enums[enum] - names
        if missing:
            problems += 1
            line = src[:m.start()].count("\n") + 1
            print(f"{path.name}:{line}  switch over {enum} "
                  f"has no default and omits: {', '.join(sorted(missing))}")

print(f"{root.name}: {len(enums)} project enums, {switches} identified "
      f"exhaustive switches, {problems} incomplete")
