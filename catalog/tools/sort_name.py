"""The A-to-Z key of a name, computed once here and shipped as `sort_name`; no client re-derives it.

Accents are dropped, leading punctuation is skipped, then one leading English
article ("The ", "A ", "An "), and the rest is case-folded:

  '"Banjos In Action"'  -> 'banjos in action"'
  ': CARL SAGAN'        -> 'carl sagan'
  "The Shadow"          -> 'shadow'
  "A Date With Judy"    -> 'date with judy'

Digits stay and sort before letters on every client's plain comparison. A name
that is all punctuation falls back to itself, folded.
"""
import re
import unicodedata

ARTICLE = re.compile(r"^(the|a|an)\s+(?=\S)")


def _lead(s):
    i = 0
    while i < len(s) and not s[i].isalnum():
        i += 1
    return s[i:]


def sort_name(name):
    if not name:
        return ""
    folded = "".join(c for c in unicodedata.normalize("NFKD", name) if not unicodedata.combining(c)).casefold()
    t = _lead(folded)
    m = ARTICLE.match(t)
    if m and _lead(t[m.end():]):
        t = _lead(t[m.end():])
    return t or folded.strip()
