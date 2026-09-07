"""Declarations that ended up outside the type they belong to.

A test method inserted after a class's closing brace still parses as a
file-scope function. It compiles as nothing, and calls to the class's private
helpers fail with "cannot find 'x' in scope" — a confusing error a long way
from the mistake. That cost two CI cycles in one afternoon, both times from
inserting a test by matching on a neighbouring function's name.

Brace counting, not Swift parsing. The blanking order is the whole trick:
raw strings, then multi-line literals, then plain strings, then line comments,
then block comments. Any other order gets it wrong — `"https://x"` looks like a
comment until strings are gone, and a comment mentioning `Invoices/*.pdf` looks
like a block comment until line comments are gone. Both are in this repo.
"""
import os
import re
import sys

root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")

RAW_STRING = re.compile(r'#{1,4}"(?:(?!"#).)*"#{1,4}')
PLAIN_STRING = re.compile(r'"(?:\\.|[^"\\])*"')
LINE_COMMENT = re.compile(r"//.*")
TEST_FUNC = re.compile(r"^\s*(?:public\s+|private\s+|internal\s+)?func\s+test\w*\s*\(")
TOP_TYPE = re.compile(r"^(?:public\s+|internal\s+)?(?:final\s+)?(?:class|struct|enum|actor|extension)\s")

problems = []
scanned = 0


def code(line, state):
    """The line with strings and comments removed. `state` carries the two
    things that span lines: a multi-line literal and a block comment."""
    if state["string"]:
        if '"""' not in line:
            return ""
        line = line.split('"""', 1)[1]
        state["string"] = False
    line = RAW_STRING.sub('""', line)
    while '"""' in line:
        before, _, after = line.partition('"""')
        if '"""' in after:
            line = before + after.split('"""', 1)[1]
        else:
            state["string"] = True
            line = before
            break
    line = LINE_COMMENT.sub("", PLAIN_STRING.sub('""', line))
    out = []
    while line:
        if state["comment"]:
            if "*/" not in line:
                break
            line = line.split("*/", 1)[1]
            state["comment"] = False
            continue
        if "/*" not in line:
            out.append(line)
            break
        before, _, line = line.partition("/*")
        out.append(before)
        state["comment"] = True
    return "".join(out)


for folder, _, names in os.walk(root):
    if "/." in folder or "/build" in folder:
        continue
    for name in sorted(names):
        if not name.endswith(".swift"):
            continue
        path = os.path.join(folder, name)
        scanned += 1
        depth = 0
        state = {"string": False, "comment": False}
        shown = os.path.relpath(path, root)
        for number, raw in enumerate(open(path, encoding="utf-8"), 1):
            clean = code(raw, state)
            if TEST_FUNC.match(raw) and depth != 1:
                problems.append(f"{shown}:{number}: test at depth {depth}, expected 1")
            if TOP_TYPE.match(raw) and depth != 0:
                problems.append(f"{shown}:{number}: type at depth {depth}, expected 0")
            depth += clean.count("{") - clean.count("}")
        if depth != 0:
            problems.append(f"{shown}: braces end at depth {depth}")

label = os.path.basename(root) or root
print(f"{label}: {scanned} files, {len(problems)} misplaced declarations")
for problem in problems:
    print("    " + problem)
sys.exit(1 if problems else 0)
