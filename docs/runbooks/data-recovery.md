# Recovering the catalog after a clobber

I want the shared catalog to be impossible to lose. It lives on a GitHub
Release asset rather than in git (the publishing pattern in Decision 016
and the `shared-data-plane-contract` skill), and release assets are
overwritten on each publish. So a bad publish leaves no version history
on the release itself.

This happened in Archive Watch on 2026-06-03: the catalog dropped from
about 30k items to about 1k in one publish. Both recovery paths below
were verified there.

The tool and workflow names in this runbook are placeholders for the
ones your data plane defines. You create them.

## The symptom

The catalog release asset (for example `catalog.json.gz`) is suddenly
small, or the app database built from it drops by an order of magnitude.
Confirm the count:

```sh
python tools/<your_catalog_release_tool>.py fetch      # you create this
python3 -c "import json; print(len(json.load(open('catalog.json'))['items']))"
```

## Path A: a dangling git commit (fullest)

This path applies when the catalog used to be committed in git and a
history rewrite (`git filter-repo` plus a force-push) removed it. GitHub
keeps the unreachable ("dangling") commits for about 90 days, and serves
them by full SHA.

```sh
# 1. Find the history rewrite. The force_push 'before' SHA is the old tip.
gh api "repos/<owner>/<repo>/activity?per_page=100" \
  | python3 -c "import json,sys; [print(a['before'],a['timestamp']) for a in json.load(sys.stdin) if a.get('activity_type')=='force_push']"

# 2. Fetch that dangling commit (GitHub serves it by full SHA even unreachable).
git fetch origin <OLD_TIP_SHA>

# 3. Walk its ancestry to the last commit that still had catalog.json
#    (the parent of the commit that removed it).
git log <OLD_TIP_SHA> -- catalog.json | head

# 4. Extract it.
git show <THAT_SHA>:catalog.json > catalog.json
```

In Archive Watch this yielded 30,645 items, more than had been lost.
After about 90 days the dangling objects may be garbage-collected, and
Path B is the fallback.

## Path B: a client's cached database (about a day stale)

Clients download the full database and cache it. Rebuild `catalog.json`
from the cached copy. The example assumes a SQLite cache with an
`item_json` table holding one JSON row per item; adjust the query to
your schema.

```sh
find ~/Library/Developer/CoreSimulator -name catalog.sqlite -size +50M
python3 - <<'PY'
import sqlite3, json, datetime
db = sqlite3.connect("<PATH>/catalog.sqlite")
items = [json.loads(r[0]) for r in db.execute("SELECT json FROM item_json")]
json.dump({"version":2,
           "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
           "generator":"recovery-from-cached-sqlite",
           "stats":{"totalItems":len(items)}, "items":items},
          open("catalog.json","w"), ensure_ascii=False)
print("recovered", len(items))
PY
```

## Finishing either path

```sh
python tools/<your_remediation_tool>.py            # re-apply deterministic data fixes (you create this)
python tools/<your_catalog_release_tool>.py publish # gzip + upload the release asset (you create this)
gh workflow run <your-publish-db>.yml              # rebuild the client database (you create this)
rm -f catalog.json
```

## Re-applying lost network enrichment

The recovered catalog predates whatever enrichment ran after its
snapshot. Enrichment workflows should be idempotent (fill only gaps), so
re-running them is safe. Dispatch them **one at a time**: a shared
concurrency group keeps only one pending run, so firing several at once
cancels the middle ones.

```sh
gh workflow run <enrichment-a>.yml && gh run watch <id> --exit-status
gh workflow run <enrichment-b>.yml && gh run watch <id> --exit-status
```

Enrichment behind a rate-limited API drains over days on its daily cron.
That is by design, not a failure.

## Prevention

A catalog-mutating build is additive and merge-guarded: it merges into
the accumulated artifact and can never replace it wholesale. See
Decision 016 (the merge-guard rule), Decision 037 (a generator's output
is not the shipped artifact), and `docs/CI-FLEET.md` (guarded
publishes).

Keep a cached copy somewhere you control, and test Path B once.
