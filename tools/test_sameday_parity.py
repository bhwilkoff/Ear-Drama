#!/usr/bin/env python3
"""Parity guard for "That night on the radio" (contract 3.3b): the one query, in every language that runs it.

Apple and Android run the contract's SQL with the same order and the same cap; the web reads the year's
`search/dates` rows, which carry no network, so it orders by series then id (documented in the contract and in
api.js). Each is checked against its own text, and `check` is run on a broken copy to show it can fail.

    python3 tools/test_sameday_parity.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = {
    'contract': 'docs/CATALOG-CONTRACT.md',
    'apple': 'apple/Core/Catalog/CatalogDatabase.swift',
    'android': 'android/app/src/main/java/com/example/appname/data/CatalogDatabase.kt',
    'web': 'js/api.js',
}


def check(texts):
    bad = []
    flat = {k: re.sub(r'["\s+]+', ' ', v) for k, v in texts.items()}
    for k in ('contract', 'apple', 'android'):
        if 'network IS NULL, ' not in flat[k] or 'network, series_key, id' not in flat[k].replace('e.', ''):
            bad.append(f'{k}: the order is not network (unknown last), series, id')
    for k in ('apple', 'android'):
        if 'e.air_date = ? AND e.id != ?' not in flat[k]:
            bad.append(f'{k}: the day is not air_date = date and never the episode itself')
        if 'limit: Int = 12' not in texts[k]:
            bad.append(f'{k}: the cap is not 12')
    if 'limit = 12' not in texts['web'] or 'byText(a.series, b.series) || byText(a.id, b.id)' not in texts['web']:
        bad.append('web: the cap is not 12, or the order is not series then id')
    return bad


def main():
    texts = {k: open(os.path.join(ROOT, v), encoding='utf-8').read() for k, v in FILES.items()}
    bad = check(texts)
    broken = dict(texts, android=texts['android'].replace('network IS NULL, ', ''))
    if not check(broken):
        print('FAIL: the control did not fail (a broken Android order passed)')
        return 1
    for b in bad:
        print('FAIL ' + b)
    print('FAIL' if bad else 'PASS: the same-day query is the same on web, Apple, and Android')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
