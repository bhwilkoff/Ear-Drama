"""The public search services, behind one polite client with a recorded-fixture mode.

Every request carries a generic agent: no name, account, or production (R4-9 section 1.4). A service that does
not answer raises ServiceDown, whose message is a fixed word; the judge turns that into "wait", never "clear".
A call budget caps one script's requests.
"""
import json
import time
import urllib.error
import urllib.parse
import urllib.request

AGENT = "EarDrama-originality/1.0 (+https://eardrama.org)"
GAPS = {"archive_fts": 3.0, "wikipedia": 1.0, "wikidata": 1.0, "openlibrary": 1.0}
TIMEOUT = 45
MAX_CALLS = 12


class ServiceDown(Exception):
    pass


class Http:
    """fixtures: None for the network, else {"<service>\\t<query>": body or parsed JSON} and no request is made."""

    def __init__(self, fixtures=None, sleep=time.sleep, clock=time.monotonic, max_calls=MAX_CALLS):
        self.fixtures, self.sleep, self.clock, self.max_calls = fixtures, sleep, clock, max_calls
        self.calls, self.last, self.waited = 0, {}, 0.0

    def get(self, service, query, url):
        if self.calls >= self.max_calls:
            raise ServiceDown("budget")
        self.calls += 1
        if self.fixtures is not None:
            body = self.fixtures.get(service + "\t" + query)
            if body is None:
                raise ServiceDown("no_fixture")
            return body if isinstance(body, (dict, list)) else _parse(body)
        for attempt in (0, 1):
            gap = GAPS[service] - (self.clock() - self.last.get(service, -1e9))
            if gap > 0:
                self.waited += gap
                self.sleep(gap)
            self.last[service] = self.clock()
            try:
                req = urllib.request.Request(url, headers={"User-Agent": AGENT, "Accept": "application/json"})
                with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
                    return _parse(r.read())
            except ServiceDown:
                pass
            except (urllib.error.URLError, OSError, ValueError):
                pass
            if attempt == 0:
                self.sleep(GAPS[service])
        raise ServiceDown("no_answer")


def _parse(body):
    try:
        return json.loads(body)
    except (ValueError, TypeError):
        raise ServiceDown("not_json")


def q(s):
    return urllib.parse.quote(s, safe="")


def ia_search(http, phrase):
    """[(item id, title)] of the first 20 answers of archive.org's full-text search. Snippets are never read."""
    url = ("https://archive.org/services/search/beta/page_production/?service_backend=fts&hits_per_page=20&page=1"
           "&aggregations=false&user_query=" + q('"' + phrase + '"'))
    body = http.get("archive_fts", phrase, url)
    try:
        return [(h["fields"]["identifier"], str(h["fields"].get("title") or "")) for h in body["response"]["body"]["hits"]["hits"]]
    except (KeyError, TypeError):
        raise ServiceDown("shape")


def wikipedia(http, title):
    url = ("https://en.wikipedia.org/w/api.php?action=query&list=search&format=json&srlimit=8&srsearch="
           + q(f'intitle:"{title}" play'))
    body = http.get("wikipedia", title, url)
    try:
        return [(h["title"], h.get("snippet", "")) for h in body["query"]["search"]]
    except (KeyError, TypeError):
        raise ServiceDown("shape")


def wikidata(http, title):
    url = ("https://www.wikidata.org/w/api.php?action=wbsearchentities&language=en&format=json&limit=20&type=item&search="
           + q(title))
    body = http.get("wikidata", title, url)
    try:
        return [(h.get("label", ""), h.get("description", "")) for h in body["search"]]
    except (KeyError, TypeError):
        raise ServiceDown("shape")


def openlibrary(http, title):
    url = ("https://openlibrary.org/search.json?subject=drama&fields=title,author_name,first_publish_year&limit=5&title="
           + q(title))
    body = http.get("openlibrary", title, url)
    try:
        return [(d.get("title", ""), d.get("author_name") or []) for d in body["docs"]]
    except (KeyError, TypeError):
        raise ServiceDown("shape")
