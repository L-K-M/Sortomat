import re, sys, os, glob

root = os.path.abspath(sys.argv[1])
src = open(os.path.join(root, "Sortomat/Model/L10n.swift")).read()

def table(name):
    m = re.search(r"static let %s: \[String: String\] = \[" % name, src)
    body = src[m.end():src.index("\n    ]", m.end())]
    return dict(re.findall(r'^\s*"([^"]+)":\s*(.*?),?\s*$', body, re.M))

en = table("english")
spec = re.compile(r'%(?:(\d+)\$)?[-+ #0]*[\d*]*(?:\.\d+)?(?:hh|h|ll|l|q|L|z|j|t)?([@dioxXufFeEgGcsp%])')

def slots(fmt):
    """How many arguments the format string consumes."""
    positional, plain = 0, 0
    for index, conv in spec.findall(fmt):
        if conv == '%':
            continue
        if index:
            positional = max(positional, int(index))
        else:
            plain += 1
    return max(positional, plain)

def split_args(text):
    """Top-level commas only: skip nested (), [], "" and \\( ) interpolation."""
    depth, quote, parts, current = 0, False, [], ""
    i = 0
    while i < len(text):
        c = text[i]
        if quote:
            if c == "\\" and i + 1 < len(text):
                current += c + text[i + 1]; i += 2; continue
            if c == '"':
                quote = False
        else:
            if c == '"':
                quote = True
            elif c in "([{":
                depth += 1
            elif c in ")]}":
                depth -= 1
            elif c == "," and depth == 0:
                parts.append(current.strip()); current = ""; i += 1; continue
        current += c
        i += 1
    if current.strip():
        parts.append(current.strip())
    return parts

def call_args(text, start):
    """The argument text of a call whose '(' is at `start`."""
    depth, quote, i = 0, False, start
    while i < len(text):
        c = text[i]
        if quote:
            if c == "\\" and i + 1 < len(text):
                i += 2; continue
            if c == '"':
                quote = False
        else:
            if c == '"':
                quote = True
            elif c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    return text[start + 1:i]
        i += 1
    return None

problems = 0
checked = 0
for path in sorted(glob.glob(os.path.join(root, "Sortomat/**/*.swift"), recursive=True) +
                   glob.glob(os.path.join(root, "SortomatTests/**/*.swift"), recursive=True)):
    if path.endswith("L10n.swift"):
        continue
    text = open(path).read()
    for m in re.finditer(r'L10n\.(t|plural)\s*\(', text):
        kind = m.group(1)
        inner = call_args(text, m.end() - 1)
        if inner is None:
            continue
        args = split_args(inner)
        if not args or not args[0].startswith('"'):
            continue          # a computed key — nothing to check
        key = args[0].strip('"')
        extra = len(args) - 1
        if kind == "plural":
            # plural(key, count, args…): the count fills the first slot.
            for suffix in (".one", ".other"):
                fmt = en.get(key + suffix)
                if fmt is None:
                    continue
                checked += 1
                if slots(fmt) > extra:
                    print(f"{os.path.relpath(path, root)}: L10n.plural(\"{key}\") "
                          f"passes {extra} but «{key}{suffix}» wants {slots(fmt)}")
                    problems += 1
        else:
            fmt = en.get(key)
            if fmt is None:
                continue
            checked += 1
            if slots(fmt) != extra:
                print(f"{os.path.relpath(path, root)}: L10n.t(\"{key}\") "
                      f"passes {extra} but the string wants {slots(fmt)}")
                problems += 1

print(f"{os.path.basename(root)}: {checked} call sites checked, {problems} mismatched")
