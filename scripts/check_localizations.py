#!/usr/bin/env python3
"""Check native string coverage and format arguments without third-party dependencies."""
from pathlib import Path
import json
import re
root = Path(__file__).resolve().parents[1]
pattern = re.compile(r'("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*")\s*;')
tables = {}
for code in ('be', 'ru', 'en'):
    path = root / 'Stajanka/Resources' / (code + '.lproj') / 'Localizable.strings'
    pairs = [(json.loads(k), json.loads(v)) for k, v in pattern.findall(path.read_text())]
    assert len(dict(pairs)) == len(pairs), f'Duplicate keys in {code}'
    tables[code] = dict(pairs)
assert set(tables['be']) == set(tables['ru']) == set(tables['en']), 'Catalog key mismatch'
for key in tables['ru']:
    for code, table in tables.items():
        assert table[key], (code, key, 'empty value')
        assert table[key].count('%@') == key.count('%@'), (code, key, 'format mismatch')
for source in (root / 'Stajanka').rglob('*.swift'):
    for key in re.findall(r'\bL\(("(?:[^"\\]|\\.)*")', source.read_text()):
        assert json.loads(key) in tables['be'], (source, key, 'missing translation')
print(f"PASS: {len(tables['be'])} strings in all three languages; source keys and placeholders checked")
