#!/usr/bin/env python3
"""Set Ear Drama's App Store listing fields from the API (not the App Privacy label,
which the public API cannot set).

    python3 tools/asc_listing.py            # set everything, every platform
    python3 tools/asc_listing.py --dry-run

Words are docs/store/LISTING-DRAFT.md, verbatim (subtitle chosen by the owner 2026-11-16);
review notes are docs/store/APP-REVIEW-NOTES.md (APP-REVIEW-NOTES-TVOS.md for Apple TV).
Needs ASC_KEY_ID and ASC_ISSUER_ID in the environment (see asc_release.py).
"""
import argparse
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import asc_release as r  # noqa: E402

REPO = pathlib.Path(__file__).resolve().parent.parent
DRAFT = (REPO / "docs/store/LISTING-DRAFT.md").read_text()

PRIVACY_URL = "https://eardrama.org/privacy/"
SUPPORT_URL = "https://eardrama.org/credits/"
MARKETING_URL = "https://eardrama.org/"
COPYRIGHT = "2026 Learning is Change, Inc."
CONTACT = {"contactFirstName": "Ben", "contactLastName": "Wilkoff",
           "contactPhone": "+13034789812", "contactEmail": "ben@learningischange.com"}


def between(start, end):
    m = re.search(start + r"(.*?)" + end, DRAFT, re.S)
    return m.group(1)


def blockquote(after):
    i = DRAFT.index(after)
    lines = []
    for ln in DRAFT[i:].splitlines()[1:]:
        if ln.startswith(">"):
            lines.append(ln[1:].lstrip() if ln.strip() != ">" else "")
        elif lines:
            break
    return "\n".join(lines).strip()


def field(label):
    return re.search(r"\*\*" + re.escape(label) + r"\*\* \(\d+ max[^)]*\):\s*`([^`]+)`", DRAFT).group(1)


NAME = "Ear Drama"
SUBTITLE = field("Subtitle")
KEYWORDS = field("Keywords")
PROMO = blockquote("**Promotional text**")
DESCRIPTION = blockquote("**Description:**")
DESCRIPTION_TV = blockquote("**Description, tvOS**")
REVIEW_NOTES = (REPO / "docs/store/APP-REVIEW-NOTES.md").read_text().strip()
_tv_notes = REPO / "docs/store/APP-REVIEW-NOTES-TVOS.md"
REVIEW_NOTES_TV = _tv_notes.read_text().strip() if _tv_notes.exists() else REVIEW_NOTES
assert len(SUBTITLE) <= 30 and len(KEYWORDS) <= 100 and len(PROMO) <= 170 and len(DESCRIPTION) <= 4000 and len(DESCRIPTION_TV) <= 4000
assert len(REVIEW_NOTES) <= 4000 and len(REVIEW_NOTES_TV) <= 4000

AGE = {
    "alcoholTobaccoOrDrugUseOrReferences": "INFREQUENT_OR_MILD",
    "contests": "NONE", "gambling": False, "gamblingSimulated": "NONE",
    "horrorOrFearThemes": "INFREQUENT_OR_MILD",
    "matureOrSuggestiveThemes": "INFREQUENT_OR_MILD",
    "medicalOrTreatmentInformation": "NONE", "profanityOrCrudeHumor": "NONE",
    "sexualContentGraphicAndNudity": "NONE", "sexualContentOrNudity": "NONE",
    "violenceCartoonOrFantasy": "NONE", "violenceRealistic": "INFREQUENT_OR_MILD",
    "violenceRealisticProlongedGraphicOrSadistic": "NONE",
    "unrestrictedWebAccess": False, "userGeneratedContent": True,
    "messagingAndChat": False, "socialMedia": False, "gunsOrOtherWeapons": "NONE", "advertising": False, "lootBox": False,
    "healthOrWellnessTopics": False, "parentalControls": False, "ageAssurance": False,
}


def patch(path, type_, id_, attrs, dry):
    if dry:
        print(f"    would PATCH {type_} {sorted(attrs)}")
        return
    r.call(path, "PATCH", {"data": {"type": type_, "id": id_, "attributes": attrs}})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    dry = ap.parse_args().dry_run
    aid = r.app_id()

    print("app")
    patch(f"v1/apps/{aid}", "apps", aid, {"contentRightsDeclaration": "USES_THIRD_PARTY_CONTENT"}, dry)

    info = r.call(f"v1/apps/{aid}/appInfos")["data"]
    info = next(i for i in info if i["attributes"]["appStoreState"] in r.EDITABLE)
    iid = info["id"]
    print("appInfo", iid)
    for loc in r.call(f"v1/appInfos/{iid}/appInfoLocalizations")["data"]:
        patch(f"v1/appInfoLocalizations/{loc['id']}", "appInfoLocalizations", loc["id"],
              {"name": NAME, "subtitle": SUBTITLE, "privacyPolicyUrl": PRIVACY_URL}, dry)
    if not dry:
        r.call(f"v1/appInfos/{iid}", "PATCH", {"data": {
            "type": "appInfos", "id": iid, "relationships": {
                "primaryCategory": {"data": {"type": "appCategories", "id": "ENTERTAINMENT"}}}}})
    print("age rating")
    patch(f"v1/ageRatingDeclarations/{iid}", "ageRatingDeclarations", iid, AGE, dry)

    for name, platform in r.PLATFORMS.items():
        print(name)
        ver = next((v for v in r.versions(aid, platform)
                    if v["attributes"]["appStoreState"] in r.EDITABLE), None)
        if not ver:
            print("    no editable version")
            continue
        vid = ver["id"]
        patch(f"v1/appStoreVersions/{vid}", "appStoreVersions", vid, {"copyright": COPYRIGHT}, dry)
        for loc in r.call(f"v1/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]:
            patch(f"v1/appStoreVersionLocalizations/{loc['id']}", "appStoreVersionLocalizations",
                  loc["id"], {"description": DESCRIPTION_TV if platform == "TV_OS" else DESCRIPTION, "keywords": KEYWORDS,
                              "promotionalText": PROMO, "supportUrl": SUPPORT_URL,
                              "marketingUrl": MARKETING_URL}, dry)
        det = r.call(f"v1/appStoreVersions/{vid}/appStoreReviewDetail").get("data")
        attrs = dict(CONTACT, notes=REVIEW_NOTES_TV if platform == "TV_OS" else REVIEW_NOTES, demoAccountRequired=False)
        if det:
            patch(f"v1/appStoreReviewDetails/{det['id']}", "appStoreReviewDetails", det["id"], attrs, dry)
        elif not dry:
            r.call("v1/appStoreReviewDetails", "POST", {"data": {
                "type": "appStoreReviewDetails", "attributes": attrs,
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
        print("    set")
    return 0


if __name__ == "__main__":
    sys.exit(main())
