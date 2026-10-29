"""File-name parsing against real archive.org names (docs/research/07).

Broken controls, 2026-10-19, each run against a mutated copy of otr_parse.py (RADIO_TOOLS=...):
    F12 keeps a year as the number           39/41
    F10b guesses M-D when both are <= 12      40/41
    F13 keeps the leading track number        40/41
    junk titles ("Audio file") kept          40/41
Broken controls, 2026-10-28:
    F4b without the digit boundary            the 43-11-21 row and the "48" control fail
    no F10c (YY-MM-DD last)                    both Jack Benny rows fail
"""
import os
import sys

sys.path.insert(0, os.environ.get("RADIO_TOOLS") or os.path.join(os.path.dirname(__file__), "..", "tools"))
import otr_parse as P

EXPECT = [
    ("Suspense 420617 001 The Burning Court (128-44) 28455 30m00s.mp3", "Suspense", "1942-06-17", 1, "The Burning Court"),
    ("Whistler_42-05-16_ep001_Retribution.mp3", "Whistler", "1942-05-16", 1, "Retribution"),
    ("Dragnet_49-06-10_ep002_Homicide.mp3", "Dragnet", "1949-06-10", 2, "Homicide"),
    ("Gunsmoke 52-04-26 (001) Billy the Kid.mp3", "Gunsmoke", "1952-04-26", 1, "Billy the Kid"),
    ("FMM 1931-06-01 (xx) Smackout.mp3", "FMM", "1931-06-01", None, "Smackout"),
    ("Father Knows Best (055) 1950-11-02 Too Many Problems.mp3", "Father Knows Best", "1950-11-02", 55, "Too Many Problems"),
    ("XMinusOne55-04-24001NoContact.mp3", "XMinusOne", "1955-04-24", 1, "NoContact"),
    ("Inner_Sanctum_-_450109_Desert_Death.mp3", "Inner Sanctum", "1945-01-09", None, "Desert Death"),
    ("42-06-17_Burning_Court.mp3", None, "1942-06-17", None, "Burning Court"),
    ("01 38-07-11 Dracula.mp3", None, "1938-07-11", None, "Dracula"),
    ("TSP420617.mp3", "TSP", "1942-06-17", None, None),
    ("04 Rex Stout's Nero Wolfe 04 82-02-06 The Cop Killer.mp3", "Rex Stout's Nero Wolfe", "1982-02-06", 4, "The Cop Killer"),
    # Families added 2026-10-19 (Track B), each from the unidentified or undated set:
    ("esca.53.04.12_Classified_Secret.MP3", "esca", "1953-04-12", None, "Classified Secret"),      # [Escape1953]
    ("Mindwebs-830326__AvailableOnTheWarpReaction.mp3", "Mindwebs", "1983-03-26", None, "AvailableOnTheWarpReaction"),
    ("521029 1030 The Microfilm of Death.mp3", None, "1952-10-29", 1030, "The Microfilm of Death"),  # [Green Hornet]
    ("SM400219 04 Kent Captured By The Wolfe.mp3", "SM", "1940-02-19", 4, "Kent Captured By The Wolfe"),
    ("179-GrandOleOpry05-10-58.mp3", "GrandOleOpry", "1958-05-10", None, None),                    # [GrandOleOpryOtr]
    ("481209TheSisters.mp3", None, "1948-12-09", None, "TheSisters"),                             # [Half-Hours_With_Rosalind]
    ("Taxi_-_Red_-_The_Writer_1969-06-01.mp3", "Taxi", "1969-06-01", None, "Red - The Writer"),
    ("The Queens Messenger 21 1984-07-16.mp3", "The Queens Messenger", "1984-07-16", 21, None),
    ("Friday Theatre - Deadly Marriages 19-07-1985.mp3", "Friday Theatre", "1985-07-19", None, "Deadly Marriages"),
    ("Inspector Steine - s02e06- End Game.mp3", "Inspector Steine", None, 6, "S02E06 End Game"),
    ("Grey_Goose_(Aust)_ep048.mp3", "Grey Goose (Aust)", None, 48, None),                          # [grey-goose-aust-ep-056]
    ("Dimx_e049_Requiem.mp3", "Dimx", None, 49, "Requiem"),                                        # [Dimension-X]
    ("Latin Rendezvous Ep#52=70.mp3", "Latin Rendezvous", None, 52, None),
    ("Upstate Radio Theatre 2310.mp3", "Upstate Radio Theatre", None, 2310, None),
    ("0252-Yes What Episode (252) Cow Noises.mp3", "Yes What Episode", None, 252, "Cow Noises"),
    ("Dr_Jekyll_and_Mr_Hyde.1932.xx.xx_Episode_33.mp3", "Dr Jekyll and Mr Hyde", None, 33, None),
    ("Springbok Library of the Air - Beware of Siks bearing Gifts 1985.mp3", "Springbok Library of the Air", None, None,
     "Beware of Siks bearing Gifts"),
    ("Guest Is Victor Moore.mp3", None, None, None, "Guest Is Victor Moore"),                     # [AA441110]
    ("Hydrolysis.mp3", None, None, None, "Hydrolysis"),                                           # [bbcmyword]
    # a leading track number is not the broadcast's number: the title identifies it
    ("003_Grave_Robber.mp3", None, None, None, "Grave Robber"),                                   # [Believe_It_Or_Not]
    # YY-MM-DD last with no title (2026-10-28): F4b once read the "3-11-21" inside it as 1921-03-11, number 4
    ("Jack Benny Show, The 43-11-21.mp3", "Jack Benny Show, The", "1943-11-21", None, None),     # [PDP_JackBenny]
    ("Jack Benny Show, The 40-01-14.mp3", "Jack Benny Show, The", "1940-01-14", None, None),
]
# Controls for the 2026-10-19 families: what must NOT be read.
CONTROLS = [
    ("Christmas 1950.mp3", "num", None),                       # a year, not episode 1950
    ("This is Wichita Boom Town 12-1-1940.mp3", "date", None),  # D-M or M-D: not guessed
    ("vvl_4005_Audio_file.mp3", "title", None),                # "Audio file" is not a title
    ("30.mp3", "title", None),                                 # a bare number is nothing
    ("Intro.mp3", "title", None),                              # a one-word junk title
    ("UIUC_Archives_1306005_0913_B.mp3", "title", None),       # an archive's shelf mark is not a title
    ("Jack Benny Show, The 48-11-21.mp3", "num", None),        # the "4" of "48" is not an episode number
    ("Some Show 12-10-45.mp3", "date", "1945-12-10"),          # M-D-YY last is still F4b
]
NO_DATE = ["UIUC_Archives_1306005_1470_B.mp3", "Dimension X 011 Zero Hour.mp3"]


def main():
    failed = 0
    for name, series, date, num, title in EXPECT:
        p = P.parse(name)
        got = (p["series"], p["date"], p["num"], p["title"])
        if got != (series, date, num, title):
            failed += 1
            print(f"FAIL {name}: {got}")
    for name in NO_DATE:
        if P.parse(name)["date"]:
            failed += 1
            print(f"FAIL (control) {name} got a date {P.parse(name)['date']}")
    for name, field, want in CONTROLS:
        if P.parse(name)[field] != want:
            failed += 1
            print(f"FAIL (control) {name}: {field}={P.parse(name)[field]!r}")
    tag = P.parse_album_tag("04/26/52, episode 1")
    if tag != {"date": "1952-04-26", "num": 1}:
        failed += 1
        print(f"FAIL album tag {tag}")
    n = len(EXPECT) + len(NO_DATE) + len(CONTROLS) + 1
    print(f"{n - failed}/{n} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
