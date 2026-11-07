# Chantier 15 — Jeûne intermittent et eau (section de Nutrition) — fiche (7 nov. 2026)

**État** : demande reçue le 7 nov. (nuit). **Rien de codé.** Étape suivante : questions à Mohamed (outil à choix multiples), puis **maquette** (artefact Design, style F), validation, puis le code.

## La demande (7 nov., mots de Mohamed résumés)
- Une **nouvelle section dans Nutrition** : le **jeûne intermittent**. Mohamed ne sait pas encore où la placer : la maquette doit proposer l'emplacement.
- **Durée réglable** : 16 h, 17 h, 18 h, 19 h… « comme je veux ».
- **Heure de début** : « Commencer » à l'heure qu'il est (ex. 14:00) ; si le jeûne a commencé plus tôt et qu'il a oublié, **modifier l'heure de début** après coup.
- **Heure de fin prévue** affichée et modifiable ; s'il l'arrête plus tôt, **changer l'heure de fin** (réelle).
- **Affichage** : en **vert** la durée déjà faite, dans une autre couleur (ex. **rouge doux**) ce qui reste.
- **Eau, juste en dessous** : « est-ce que j'ai bu ». Un verre qui se remplit, plusieurs verres, ou plutôt **une bouteille qui se remplit**, avec des **graduations** 0 · 1 L · 2 L · 3 L (forme à trouver).
- Claude peut **proposer d'autres choses utiles** pour cette section.

## Ce qui existe déjà dans l'app (relevé du 7 nov., `main` après #113)
- **Eau** : `Strand/Data/HydrationStore.swift` (total du jour dans `metricSeries`, source et clé `hydration`, **jumeau Android** `com.noop.analytics.HydrationStore` ; entrées du jour modifiables dans UserDefaults `noop.hydrationEntries.<jour>` ; taille de contenant perso `noop.hydrationCustomSizeML` ; import Santé `hydrationImported`), `Strand/Screens/HydrationView.swift` (récipient `LiquidVessel`, tube, Gorgée / Verre / Bouteille, barres 7 j), objectif **`HydrationGoal`** (`Packages/StrandAnalytics` : base selon le sexe 3,7 / 2,7 / 3,2 L + jusqu'à 0,7 L selon l'Effort, jumeau Kotlin). Réglage `noop.hydrationTracking` (éteint par défaut). Le Coach lit déjà l'eau. **À réutiliser : pas de nouveau stockage pour l'eau.**
- **Caféine** : `Strand/Data/CaffeineLog.swift` (café / thé : utile pendant un jeûne).
- **Repas** : tout passe par `MealJournal` (moment du repas, heure) ; la page Nutrition est organisée par moments (#70).
- **Jeûne** : **rien** (le mot « fasting » n'apparaît que dans les marqueurs de labo, `fasting_glucose`).

## Propositions de Claude (à faire trancher dans les questions)
1. **Anneau du jeûne** (cohérent avec les anneaux de l'app) : vert = fait, rouge doux = reste ; heure de début et heure de fin prévue sous l'anneau, chacune modifiable d'un tap ; au centre « 11 h 42 / 16 h ». Variante : une barre horizontale ou une frise de 24 h qui montre aussi la fenêtre de repas.
2. **Repères pendant le jeûne** (facultatifs, présentés comme indicatifs, jamais médicaux) : 12 h, 16 h, 18 h, 24 h marqués sur l'anneau.
3. **Lien avec les repas** : noter un repas pendant un jeûne propose « Terminer le jeûne à 12:30 ? » (heure du repas) ; la fenêtre de repas suit d'elle-même la fin du jeûne.
4. **Plan habituel** : horaires réguliers (ex. 20:00 → 12:00, 16:8) ; un rappel ou un démarrage automatique à l'heure prévue.
5. **Historique** : jeûnes des 7 / 30 derniers jours (barres, objectif atteint ou non), durée moyenne, série de jours tenus.
6. **Notifications** : fin prévue (« 16 h atteintes »), éventuellement mi-parcours.
7. **Écran verrouillé** : Live Activity du jeûne (temps fait / restant), sur le modèle de la bannière de séance. **Widget** : attention, `NOOPWidgetBundle` est à **10 widgets, la limite** (un 11e demande un bundle imbriqué).
8. **Bracelet** : comparer FC repos, VFC et sommeil des nuits de jeûne avec les autres, avec la même règle que « Ce qui ressort » de la Carte (écart affiché seulement au-delà de sa marge d'erreur).
9. **Coach** : bloc FASTING (jeûne en cours, historique court) dans sa fiche ; il peut proposer un repas de reprise.
10. **Eau** : une bouteille graduée 0 → 3 L (graduation finale = l'objectif `HydrationGoal`, arrondi), boutons + 250 ml / + 500 ml / perso, appui long pour corriger ; café / thé (caféine) en raccourci à côté.

## Choix par défaut (si Mohamed ne tranche pas)
- Place : **carte en haut de la page Nutrition** (au-dessus des moments de repas), qui ouvre une page « Jeûne » avec le détail et l'historique.
- Visuel : **anneau** (vert fait / rouge doux reste), durée par défaut **16 h**, choix rapide 12 · 14 · 16 · 17 · 18 · 19 · 20 h + « Autre ».
- Eau : **une bouteille graduée** sous le jeûne, branchée sur `HydrationStore` et `HydrationGoal`.
- Extras de la 1re version : lien avec les repas (3), historique (5), notification de fin (6), Coach (9). Le reste plus tard.
- Stockage des jeûnes : à trancher au moment du code (table avec migration iOS **v55** / Android **MIGRATION_46_47** et parité des données, ou stockage léger) ; vérifier le numéro juste avant.

## Méthode
- Questions d'abord (un lot, outil à choix multiples), puis **une maquette** (artefact Design, style F de l'app : fond noir, cartes #1C1C1E, chiffres arrondis), plusieurs écrans : carte dans Nutrition, page Jeûne (en cours, modifier le début / la fin, terminé), eau, historique ; puis validation par Mohamed (captures ou retours), puis le code en PR, une IPA à la fin.
- Règles habituelles : jetons de design uniquement, 10 langues sans `%` littéral dans une clé, noms de fonctions distinctifs côté app (parité), un seul résolveur pour l'état du jeûne (lu par la carte, la page, la notification, le Coach).

## Prompt de démarrage (pour une nouvelle conversation)
> Chantier 15 — Jeûne intermittent et eau, nouvelle section de Nutrition (fork NOOP). Lis `docs/fork/feuille-de-route.md`, puis `docs/fork/chantier-15-jeune.md` (la demande, ce qui existe déjà — l'eau avec `HydrationStore` / `HydrationGoal` —, tes propositions et les choix par défaut).
>
> **Commence par me poser tes questions avec l'outil à choix multiples (un seul lot)**, avant toute maquette : où placer la section dans Nutrition, la forme du jeûne (anneau, barre, frise), la forme de l'eau (bouteille graduée, verres), les durées proposées, et lesquelles de tes propositions garder pour la 1re version. Note mes réponses dans la fiche.
>
> Ensuite **fais la maquette** (artefact Design, style F de l'app) : carte dans Nutrition, page Jeûne (en cours : vert = fait, rouge doux = reste ; modifier l'heure de début après coup ; heure de fin prévue modifiable ; arrêter plus tôt et corriger l'heure de fin ; terminé), eau juste en dessous (bouteille qui se remplit, graduations 0 · 1 L · 2 L · 3 L), et ce que j'aurai retenu. Mets le lien de la maquette dans la fiche et attends ma validation avant de coder.
>
> Règles : `.claude/rules/fork-noop.md` (questions par l'outil à choix multiples, vérifications avant de pousser, IPA par `build/<nom>` quand je le dis).
