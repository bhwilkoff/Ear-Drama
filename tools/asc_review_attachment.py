#!/usr/bin/env python3
"""Attach a file (an App Review screen recording) to a version's App Review Information.

    python3 tools/asc_review_attachment.py --platform IOS --file build/store-video/x.mp4 [--replace] [--dry-run]

Uses the editable version of that platform. --replace deletes the attachments already there
first. Needs ASC_KEY_ID and ASC_ISSUER_ID (see asc_release.py).
"""
import argparse
import hashlib
import pathlib
import sys
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import asc_release as r  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--platform", required=True, choices=sorted(r.PLATFORMS.values()))
    ap.add_argument("--file", required=True)
    ap.add_argument("--replace", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    path = pathlib.Path(a.file)
    data = path.read_bytes()

    aid = r.app_id()
    ver = next((v for v in r.versions(aid, a.platform) if v["attributes"]["appStoreState"] in r.EDITABLE), None)
    if not ver:
        print(f"FAIL no editable {a.platform} version")
        return 1
    det = r.call(f"v1/appStoreVersions/{ver['id']}/appStoreReviewDetail").get("data")
    if not det:
        print("FAIL the version has no App Review Information yet (run asc_listing.py first)")
        return 1
    have = r.call(f"v1/appStoreReviewDetails/{det['id']}/appStoreReviewAttachments")["data"]
    print(f"{a.platform} {ver['attributes']['versionString']}: {len(have)} attachment(s) now "
          f"{[h['attributes'].get('fileName') for h in have]}")
    if a.dry_run:
        print(f"would {'replace them with' if a.replace else 'add'} {path.name} ({len(data)} bytes)")
        return 0
    if a.replace:
        for h in have:
            r.call(f"v1/appStoreReviewAttachments/{h['id']}", "DELETE")
            print(f"    deleted {h['attributes'].get('fileName')}")

    made = r.call("v1/appStoreReviewAttachments", "POST", {"data": {
        "type": "appStoreReviewAttachments",
        "attributes": {"fileName": path.name, "fileSize": len(data)},
        "relationships": {"appStoreReviewDetail": {"data": {"type": "appStoreReviewDetails", "id": det["id"]}}}}})["data"]
    for op in made["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
        for h in op.get("requestHeaders", []):
            req.add_header(h["name"], h["value"])
        with urllib.request.urlopen(req, timeout=300) as resp:
            if resp.status >= 300:
                print(f"FAIL upload part at {op['offset']}: HTTP {resp.status}")
                return 1
    done = r.call(f"v1/appStoreReviewAttachments/{made['id']}", "PATCH", {"data": {
        "type": "appStoreReviewAttachments", "id": made["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})["data"]
    state = (done["attributes"].get("assetDeliveryState") or {}).get("state")
    print(f"    uploaded {path.name}: {state}")
    return 0 if state in ("UPLOAD_COMPLETE", "COMPLETE", None) else 1


if __name__ == "__main__":
    sys.exit(main())
