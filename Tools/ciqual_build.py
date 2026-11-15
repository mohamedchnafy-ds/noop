#!/usr/bin/env python3
"""Build the compact Ciqual table the app embeds (`Strand/Resources/Ciqual2025.tsv`, personal fork,
Nutrition) from the official ANSES files.

Source: "Anses. 2025. Ciqual French food composition table", Recherche Data Gouv,
https://doi.org/10.57745/RDMHWY, Licence Ouverte / Open Licence (Etalab 2.0). The two inputs are
`Table Ciqual 2025_FR_2025_11_03.xlsx` (the composition) and `alim_2025_11_03.xml` (the English names).

Usage: python3 -I Tools/ciqual_build.py <Table_Ciqual_2025_FR.xlsx> <alim_2025.xml> <out.tsv>
Needs openpyxl.

Columns kept (per 100 g), found by their header text, never by position:
- energy, Regulation (EU) 1169/2011 (kcal); proteins, N x 6.25; carbohydrates; fat. "traces" and
  "< x" (below the quantification limit) count 0. A food missing any of the four is left out.
  Written with a dot and at most one decimal (energy: whole kcal).
- the micronutrients of `MICROS` (fork chantier 22), in the unit Ciqual gives. For these an empty
  cell ("-") is UNKNOWN and written empty: it is never 0. "traces" and "< x" count 0. EPA + DHA is one
  column, unknown unless both are known. Written with a dot and at most three decimals.

The header line `# code\tname_fr\t...` names every column; the app maps columns by those names."""
import sys, re, openpyxl, xml.etree.ElementTree as ET

# (TSV column name, header prefix in the Ciqual sheet; a pair = the first column, else the second when the
# first is empty). The column names are the keys of
# `MicroNutrient` in `Strand/Data/MealMicros.swift`.
MICROS = [
    ('fiber_g', 'Fibres alimentaires (g'),
    ('sugars_g', 'Sucres (g'),
    ('sfa_g', 'AG saturés (g'),
    ('mufa_g', 'AG monoinsaturés (g'),
    ('pufa_g', 'AG polyinsaturés (g'),
    ('cholesterol_mg', 'Cholestérol (mg'),
    ('salt_g', 'Sel chlorure de sodium (g'),
    ('ala_g', 'AG 18:3 c9,c12,c15 (n-3)'),
    ('epa_dha_g', None),  # the sum of the two columns below
    ('la_g', 'AG 18:2 9c,12c (n-6)'),
    ('calcium_mg', 'Calcium (mg'),
    ('iron_mg', 'Fer (mg'),
    ('magnesium_mg', 'Magnésium (mg'),
    ('potassium_mg', 'Potassium (mg'),
    ('sodium_mg', 'Sodium (mg'),
    ('zinc_mg', 'Zinc (mg'),
    ('phosphorus_mg', 'Phosphore (mg'),
    ('iodine_ug', 'Iode (µg'),
    ('selenium_ug', 'Sélénium (µg'),
    ('copper_mg', 'Cuivre (mg'),
    ('manganese_mg', 'Manganèse (mg'),
    ('vitA_ug', 'Activité vitaminique A'),
    ('vitD_ug', 'Vitamine D (µg'),
    ('vitE_mg', ('Vitamine E (mg', 'Alpha-tocophérol (vitamine E)')),
    ('vitK1_ug', 'Vitamine K1 (µg'),
    ('vitC_mg', 'Vitamine C (mg'),
    ('vitB1_mg', 'Vitamine B1 ou Thiamine'),
    ('vitB2_mg', 'Vitamine B2 ou Riboflavine'),
    ('vitB3_mg', 'Vitamine B3 ou PP'),
    ('vitB5_mg', 'Vitamine B5 ou Acide'),
    ('vitB6_mg', 'Vitamine B6 (mg'),
    ('vitB9_ug', ('Vitamine B9 ou Folates totaux, équivalents folates alimentaires', 'Vitamine B9 ou Folates totaux (µg')),
    ('vitB12_ug', 'Vitamine B12 (µg'),
]
EPA, DHA = 'AG 20:5', 'AG 22:6'

xlsx, alim_xml, out = sys.argv[1:4]
names_en = {}
for alim in ET.parse(alim_xml).getroot().iter('ALIM'):
    code = (alim.findtext('alim_code') or '').strip()
    en = (alim.findtext('alim_nom_eng') or '').strip()
    if code: names_en[code] = en

def value(v, missing):
    if v is None: return missing
    s = str(v).strip()
    if s in ('', '-'): return missing
    if s == 'traces' or s.startswith('<'): return 0.0
    return float(s.replace(',', '.'))

def clean(s):
    return re.sub(r'\s+', ' ', (s or '').replace('\t', ' ')).strip()

def column(headers, prefix):
    hits = [i for i, h in enumerate(headers) if h.startswith(prefix)]
    assert len(hits) == 1, (prefix, [headers[i] for i in hits])
    return hits[0]

ws = openpyxl.load_workbook(xlsx, read_only=True).worksheets[0]
rows, skipped = [], []
for i, row in enumerate(ws.iter_rows(values_only=True)):
    if i == 0:
        headers = [clean(str(h)) for h in row]
        c_code, c_name = headers.index('alim_code'), headers.index('alim_nom_fr')
        c_kcal = column(headers, 'Energie, Règlement UE N° 1169 2011 (kcal')
        c_prot = column(headers, 'Protéines, N x 6.25')
        c_carbs = column(headers, 'Glucides (g')
        c_fat = column(headers, 'Lipides (g')
        c_micro = [None if p is None else tuple(column(headers, q) for q in p) if isinstance(p, tuple)
                   else (column(headers, p),) for _, p in MICROS]
        c_epa, c_dha = column(headers, EPA), column(headers, DHA)
        continue
    code = str(row[c_code]).strip()
    kcal, prot, carbs, fat = (value(row[c], None) for c in (c_kcal, c_prot, c_carbs, c_fat))
    name = clean(row[c_name])
    if None in (kcal, prot, carbs, fat):
        skipped.append((code, name)); continue
    micros = []
    for (key, _), c in zip(MICROS, c_micro):
        if c is None:
            epa, dha = value(row[c_epa], None), value(row[c_dha], None)
            micros.append(None if epa is None or dha is None else epa + dha)
        else:
            found = [value(row[x], None) for x in c]
            micros.append(next((v for v in found if v is not None), None))
    rows.append((int(code), code, name, clean(names_en.get(code, '')), kcal, prot, carbs, fat, micros))
rows.sort()

def g(x):
    t = f"{round(x + 1e-9, 1):.1f}"
    return t[:-2] if t.endswith('.0') else t

def m(x):
    if x is None: return ''
    t = f"{round(x + 1e-12, 3):.3f}".rstrip('0').rstrip('.')
    return t if t else '0'

with open(out, 'w', encoding='utf-8', newline='\n') as f:
    f.write('# Anses. 2025. Ciqual French food composition table. https://doi.org/10.57745/RDMHWY\n')
    f.write('# Licence Ouverte / Open Licence (Etalab 2.0). Per 100 g: kcal (EU 1169/2011), protein (N x 6.25), carbohydrates, fat;\n')
    f.write('# then micronutrients in the unit their name ends with (empty = unknown, not 0).\n')
    f.write('# ' + '\t'.join(['code', 'name_fr', 'name_en', 'kcal', 'protein_g', 'carbs_g', 'fat_g']
                             + [k for k, _ in MICROS]) + '\n')
    for _, code, fr, en, kcal, prot, carbs, fat, micros in rows:
        f.write('\t'.join([code, fr, en, str(int(round(kcal + 1e-9))), g(prot), g(carbs), g(fat)]
                          + [m(x) for x in micros]) + '\n')
known = [sum(1 for r in rows if r[8][j] is not None) for j in range(len(MICROS))]
print('kept', len(rows), 'skipped', len(skipped))
for (k, _), n in zip(MICROS, known): print(f'  {k:16s} known for {n}')
