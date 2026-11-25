"""The public log (R4-9 section 1.5). A job's log is in a public repository, so it can say only a fixed handful of
things: a count, the verdict's word, a service's name with ok or failed, the index date, an exception's class.
Never a title, phrase, id, work, number of words, or error body. Each line is built from a closed vocabulary or a
strict shape, and anything else raises with a message that names no data.
"""
import re
import sys

VERDICTS = ("clear", "asks", "held", "wait")
SERVICES = ("index", "archive_fts", "wikipedia", "wikidata", "openlibrary", "local_titles")
KNOWN_ERRORS = ("IndexRefused", "SelfTestFailed", "ServiceDown", "KeyError", "ValueError", "OSError", "TypeError",
                "JSONDecodeError", "MemoryError", "KeyboardInterrupt", "UnicodeDecodeError", "AssertionError",
                "FileNotFoundError", "IndexError", "AttributeError", "RuntimeError")


class LogRefused(Exception):
    pass


class PublicLog:
    def __init__(self, out=None):
        self.out = out or sys.stdout

    def _say(self, line):
        self.out.write(line + "\n")
        self.out.flush()

    def checked(self, n):
        if not isinstance(n, int) or not 0 <= n <= 1000:
            raise LogRefused("count")
        self._say(f"checked {n}")

    def verdict(self, word):
        if word not in VERDICTS:
            raise LogRefused("verdict")
        self._say(f"verdict {word}")

    def service(self, name, ok):
        if name not in SERVICES or not isinstance(ok, bool):
            raise LogRefused("service")
        self._say(f"service {name} {'ok' if ok else 'failed'}")

    def index(self, date):
        if not isinstance(date, str) or not re.fullmatch(r"\d{4}-\d\d-\d\d", date):
            raise LogRefused("date")
        self._say(f"index {date}")

    def selftest(self, passed):
        self._say("selftest " + ("passed" if passed else "failed"))

    def failed(self, exc):
        name = type(exc).__name__
        self._say("error " + (name if name in KNOWN_ERRORS else "other"))
