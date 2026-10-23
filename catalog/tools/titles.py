"""Episode titles as people read them, cleaned of the file names they came from.

Imported by every builder, never copied. Conservative on purpose: a title that
already reads as words is returned unchanged, and only these upload habits are
undone (MEASURED 2026-10-22 over 104,028 served titles: 2,883 with track digits
glued to a word, 2,048 run together with no spaces, 181 ending in a file
extension, 99 with underscores):

  "001 Frankenstein 1931.mp3"        -> "001 Frankenstein 1931"
  "Carolyn_Day_Detective_-_Audition_1" -> "Carolyn Day Detective - Audition 1"
  "01CbsNews-LinkletterHouseParty"    -> "Cbs News-Linkletter House Party"
  "EdnaWolfeWantsToGetNancyFowler"    -> "Edna Wolfe Wants To Get Nancy Fowler"

A spaced leading number stays ("77 Sunset Strip" is a title), "McGee" and
"MacArthur" stay whole, and capitals are never changed.
"""
import re

EXT = re.compile(r"\.(mp3|ogg|m4a|flac|wav)$", re.I)
GLUED_TRACK = re.compile(r"^\d{1,3}(?=[A-Z][a-z])")
HUMP = re.compile(r"(?<=[a-z])(?=[A-Z])")
MC = re.compile(r"\b(Ma?c) ([A-Z])")


def display_title(raw):
    if not raw:
        return raw
    t = EXT.sub("", raw.strip())
    if "_" in t:
        t = re.sub(r"_+", " ", t)
    t = GLUED_TRACK.sub("", t)
    if " " not in t and len(HUMP.findall(t)) >= 2:
        t = MC.sub(r"\1\2", HUMP.sub(" ", t))
    t = re.sub(r"\s{2,}", " ", t).strip()
    return t or raw.strip()
