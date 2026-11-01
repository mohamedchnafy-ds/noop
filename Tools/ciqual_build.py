#!/usr/bin/env python3
"""Build the compact Ciqual table the app embeds (`Strand/Resources/Ciqual2025.tsv`, personal fork,
Nutrition) from the official ANSES files.

Source: "Anses. 2025. Ciqual French food composition table", Recherche Data Gouv,
https://doi.org/10.57745/RDMHWY, Licence Ouverte / Open Licence (Etalab 2.0). The two inputs are
`Table Ciqual 2025_FR_2025_11_03.xlsx` (the composition) and `alim_2025_11_03.xml` (the English names).

Usage: python3 -I Tools/ciqual_build.py <Table_Ciqual_2025_FR.xlsx> <alim_2025.xml> <out.tsv>
Needs openpyxl.

Columns kept (per 100 g): energy, Regulation (EU) 1169/2011 (kcal); proteins, N x 6.25; carbohydrates;
fat. "traces" and "< x" (below the quantification limit) count 0. A food missing any of the four
is left out. Values are written with a dot and at most one decimal (energy: whole kcal)."""
import sys, re, openpyxl, xml.etree.ElementTree as ET

xlsx, alim_xml, out = sys.argv[1:4]
names_en = {}
for alim in ET.parse(alim_xml).getroot().iter('ALIM'):
    code = (alim.findtext('alim_code') or '').strip()
    en = (alim.findtext('alim_nom_eng') or '').strip()
    if code: names_en[code] = en

def value(v):
    if v is None: return None
    s = str(v).strip()
    if s in ('', '-'): return None
    if s == 'traces' or s.startswith('<'): return 0.0
    return float(s.replace(',', '.'))

def clean(s):
    return re.sub(r'\s+', ' ', (s or '').replace('\t', ' ')).strip()

ws = openpyxl.load_workbook(xlsx, read_only=True).worksheets[0]
rows, skipped = [], []
for i, row in enumerate(ws.iter_rows(values_only=True)):
    if i == 0:
        assert 'kcal' in row[10] and 'Règlement' in row[10], row[10]
        assert 'N x 6.25' in row[15], row[15]
        assert row[16].startswith('Glucides') and row[17].startswith('Lipides'), (row[16], row[17])
        continue
    code = str(row[6]).strip()
    kcal, prot, carbs, fat = (value(row[c]) for c in (10, 15, 16, 17))
    name = clean(row[7])
    if None in (kcal, prot, carbs, fat):
        skipped.append((code, name)); continue
    rows.append((int(code), code, name, clean(names_en.get(code, '')), kcal, prot, carbs, fat))
rows.sort()

def g(x):
    t = f"{round(x + 1e-9, 1):.1f}"
    return t[:-2] if t.endswith('.0') else t

with open(out, 'w', encoding='utf-8', newline='\n') as f:
    f.write('# Anses. 2025. Ciqual French food composition table. https://doi.org/10.57745/RDMHWY\n')
    f.write('# Licence Ouverte / Open Licence (Etalab 2.0). Per 100 g: kcal (EU 1169/2011), protein (N x 6.25), carbohydrates, fat.\n')
    f.write('# code\tname_fr\tname_en\tkcal\tprotein_g\tcarbs_g\tfat_g\n')
    for _, code, fr, en, kcal, prot, carbs, fat in rows:
        f.write('\t'.join([code, fr, en, str(int(round(kcal + 1e-9))), g(prot), g(carbs), g(fat)]) + '\n')
print('kept', len(rows), 'skipped', len(skipped))
for s in skipped[:12]: print('  skip', s)
