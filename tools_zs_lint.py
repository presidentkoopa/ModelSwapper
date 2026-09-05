"""A syntax check for the ZScript this repo actually writes.

WHY THIS EXISTS. Compile-testing meant launching the engine headless,
and that is no longer done -- it started the game on the user's machine,
stole focus and locked the pk3. build.ps1 only zips; nothing between an
edit and the user's next launch reads the ZScript at all. So a trailing
comma in an array initialiser shipped, and the first thing that noticed
was the game refusing to start:

    Script error, "zscript/rs_foreignanim.zs" line 306: Unexpected '}'

This is not a ZScript parser and does not try to be. It checks the small
set of things that are actually edited here by script -- clip tables,
shelf rows, the donor stubs -- where a mechanical edit can produce a
mechanical error:

  TRAILING COMMA   the last element of an array initialiser. ZScript
                   rejects it; C and Python both allow it, which is
                   exactly why it gets written.
  UNTERMINATED     a string or block comment left open, which swallows
                   everything after it and reports the error somewhere
                   far away from the cause.
  BRACE BALANCE    per file, counted outside strings and comments.

Run over every .zs before building:

    python tools_zs_lint.py zscript/*.zs
"""
import io, sys, glob, os


def lex(src):
    """Return the source as tokens with strings and comments removed --
    but with each string replaced by a single placeholder 'S'.

    THE PLACEHOLDER IS THE WHOLE POINT. A first version dropped strings
    outright, which turned Printf("a", "b") into Printf(,) and reported
    a trailing comma on twenty-two lines of code that compiles. A string
    IS an element; it has to count as one."""
    out, i, n, line = [], 0, len(src), 1
    state, opened = "code", 0
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
        if state == "code":
            if c == "/" and i + 1 < n and src[i + 1] == "/":
                state = "line"; i += 2; continue
            if c == "/" and i + 1 < n and src[i + 1] == "*":
                state, opened = "block", line; i += 2; continue
            if c == '"':
                state, opened = "str", line
                out.append((line, "S"))      # a string is one token
                i += 1; continue
            out.append((line, c))
        elif state == "line":
            if c == "\n":
                state = "code"
        elif state == "block":
            if c == "*" and i + 1 < n and src[i + 1] == "/":
                state = "code"; i += 2; continue
        elif state == "str":
            if c == "\\":
                i += 2; continue
            if c == '"':
                state = "code"
            elif c == "\n":
                return out, ("unterminated string opened on line %d" % opened)
        i += 1
    if state == "str":
        return out, "unterminated string opened on line %d" % opened
    if state == "block":
        return out, "unterminated block comment opened on line %d" % opened
    return out, None


def check(path):
    src = io.open(path, encoding="utf-8").read()
    toks, err = lex(src)
    problems = []
    if err:
        problems.append((0, err))
        return problems

    depth = 0
    for line, c in toks:
        if c in "{([":
            depth += 1
        elif c in "})]":
            depth -= 1
            if depth < 0:
                problems.append((line, "closing bracket with nothing open"))
                depth = 0
    if depth:
        problems.append((0, "%d bracket(s) never closed" % depth))

    # TRAILING COMMA: the last non-space token before a closer is a comma.
    prev = None
    for line, c in toks:
        if c.isspace():
            continue
        if c in "})]" and prev == ",":
            problems.append((line, "trailing comma before '%s' -- ZScript rejects it" % c))
        prev = c
    return problems


files = []
for a in sys.argv[1:]:
    files.extend(glob.glob(a))
if not files:
    files = glob.glob(os.path.join(os.path.dirname(os.path.abspath(__file__)), "zscript", "*.zs"))

bad = 0
for f in sorted(files):
    for line, msg in check(f):
        print("%s:%d  %s" % (f.replace("\\", "/"), line, msg))
        bad += 1
print("%d file(s) checked, %d problem(s)" % (len(files), bad))
sys.exit(1 if bad else 0)
