# Chantier 20 — Micronutriments dans Nutrition (préparé le 15 nov. 2026)

Demande de Mohamed (15 nov.) : « Dans Nutrition, est-ce possible d'avoir les micronutriments ? »
Réponse : oui. Chaque ligne de repas prise dans Ciqual garde son code (`mealItem.foodRef = "ciqual:<code>"`),
donc les micros se **recalculent depuis la table**, sans migration, et tout l'historique en profite.

## Choix de Mohamed (15 nov.)
- **Tout ce qui est possible** : fibres, sucres, sel, AG saturés ; minéraux ; vitamines ; oméga-3 (liste
  ci-dessous, tout ce que Ciqual 2025 fournit et qui sert).
- **Affichage** : une **carte du jour « Micronutriments »** dans Nutrition (% des repères ANSES), le
  **détail par repas et par aliment**, et le **Coach les lit** (ex. fer mangé face à la ferritine du Carnet
  de labo ; jamais de diagnostic).

## Ce qu'on suit (colonnes Ciqual 2025, pour 100 g)
- Glucides et graisses : fibres, sucres, AG saturés, AG mono-insaturés, AG polyinsaturés, cholestérol, sel.
- Oméga-3 / 6 : ALA (18:3 n-3), EPA, DHA, acide linoléique (18:2 n-6).
- Minéraux : calcium, fer, magnésium, potassium, sodium, zinc, phosphore, iode, sélénium, cuivre, manganèse.
- Vitamines : A (rétinol + bêta-carotène), D, E, K1, C, B1, B2, B3, B5, B6, B9, B12.

## Règles
- **Inconnu ≠ 0** : pour les micros, une case Ciqual vide (« - ») est **inconnue**, pas zéro (au contraire
  des macros, où `Tools/ciqual_build.py` compte les traces et « < x » à 0 et retire l'aliment incomplet).
  « traces » et « < x » restent 0. Un total du jour dit combien de lignes n'ont pas la valeur
  (« Fer : 9,8 mg · 2 aliments sans valeur »).
- **Sources** : Ciqual = tout ; Open Food Facts = ce que le produit donne (souvent fibres, sucres, sel,
  AG saturés seulement) ; ligne tapée à la main ou estimée sur photo / dictée sans code Ciqual = pas de
  micros, dit à l'écran. Les lignes OFF n'ont pas leurs valeurs pour 100 g stockées au-delà des macros : à
  trancher au code (relire le produit en cache, ou une colonne de plus, donc une migration).
- **Un seul résolveur** des micros d'une ligne, d'un repas et d'un jour (`MealJournal` ou un
  `MealMicros` à côté), lu par la carte, le détail, la fiche du Coach et l'outil du Coach.
- **Repères** : RNP / AS de l'ANSES (adulte), selon `profile.sex` ; le sel et les AG saturés sont des
  **plafonds** (barre qui se remplit vers une limite), les autres des **cibles**. Aucun message d'alerte
  automatique.
- **Table embarquée** : reconstruire `Strand/Resources/Ciqual2025.tsv` avec les colonnes en plus
  (`Tools/ciqual_build.py`, en-tête vérifiée par nom de colonne et non par position). Le fichier source
  n'est pas joignable depuis la session : branche `ci/ciqual-micros` + workflow temporaire (méthode de
  `ci/ciqual-2025`). Le lecteur `CiqualTable.parseCiqualLines` doit continuer à lire les 7 premières
  colonnes ; garder la taille raisonnable (≈ 3 300 aliments × ~40 colonnes).
- **Parité** : Android garde `MealMath` pour les macros ; les micros = iPhone seulement (aucune donnée
  stockée nouvelle si on reste sans migration).

## Étapes
1. Maquette (artefact Design) : carte du jour, détail d'un repas, fiche d'un aliment, réponse du Coach.
2. PR A : table Ciqual reconstruite + résolveur + tests.
3. PR B : écrans + fiche / outil du Coach.
