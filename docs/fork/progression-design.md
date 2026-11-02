# Carnet de force · Progression — fusionnée dans `main` (1er nov. 2026)

Maquettes : canvas « NOOP – Progression (Carnet de force) » — https://claude.ai/artifact/Kb94kgSDB1C7mHynBHMmc9
Artboards : Carnet · carte Progression · Progression · Exercices · Détail exercice (Squat barre) · Progression · Muscles (silhouette) · Toucher un muscle · Forme du jour vs perf · Forme · moins de 20 séances.
Design validé par Mohamed le 1er nov. 2026 (11:45, « c'est magnifique »).

## État du code (1er nov. 2026, 14:00)
- **PR #9** (`feat/lift-progression` → `main`) **fusionnée le 1er nov. 2026 à 14:00** sur l'accord de Mohamed : commit de fusion **1a3e8ca** (`main`). 2 commits :
  - 7c66766 : la fonctionnalité.
  - 9474905 : « Voir la progression » ouvrable avant la première séance, état vide par onglet (Exercices, Muscles ; Forme compte déjà jusqu'à 20), aucun muscle « à prioriser » quand rien n'est enregistré.
- CI sur 9474905 : App build macOS (+ `StrandTests`) et iOS verts, i18n, doc-comments, Android et rendu verts. « Tools Python CI » rouge avec le même et unique échec que sur `main` (`test_checked_metadata_is_compact_v3_and_expands_losslessly`, vérifié en relançant la suite d'acceptation sur les deux branches).
- Rendu des états vides (release `render-render-lift-progression-empty`) envoyé à Mohamed : `progression-8-vide-carte`, `progression-9-vide-exercices`, `progression-10-vide-muscles`, `progression-7-forme-verrouillee`.
- **IPA sur le téléphone : 7c66766** (sans les états vides de 9474905). La prochaine IPA groupée remettra le téléphone au niveau de `main`.
- Un build `build/lift-progression` lancé par erreur sur 9474905 : release à ignorer.
- Validation sur le téléphone à faire après ses premières séances : compteurs, silhouette ; statuts après 3 séances d'un exercice ; Forme après 20 séances. Tout écart → petite PR de correction.
- Branches de travail restantes : `render/lift-progression`, `render/lift-progression-empty`, `build/lift-progression` (à supprimer seulement sur accord ; `prune-stale-branches.yml` peut supprimer seul `feat/lift-progression`, PR fusionnée).

## Choix de Mohamed (1er nov.)
- Placement : **carte dans le Carnet + écran dédié** (onglets Exercices | Muscles | Forme).
- Blocs v1 : **Exercices (statut + détail)**, **Muscles (séries + priorités)**, **Forme du jour vs perf**. Pas de bloc Régularité pour l'instant.
- Muscles affichés en **silhouette du corps** (face / dos).
- Ne note pas le RPE → aucun graphique basé sur le RPE.
- Écrans ouvrables dès maintenant, même sans séance.

## Principes
- Répondre à 3 questions : est-ce que je progresse ? où je stagne ? quels muscles prioriser ?
- Statuts calculés par des règles, pas de texte généré. Pas de score global, pas de tonnage total entre exercices, pas d'alerte de blessure (exclus par l'app d'origine, `LiftMetrics`).
- Rien de nouveau à stocker : tout se calcule à l'affichage depuis `liftSet` / `liftSession` ; pas de migration ; iPhone seulement (Android non touché, expliqué dans la PR).
- Style : tokens NOOP sombres, monde de couleur Effort (bleu) du Carnet ; aucun texte dans la zone d'un graphique.

## Règles (telles que codées dans `Strand/Data/LiftProgress.swift`)
- **Record** = charge plus lourde que toutes les précédentes, ou plus de réps à une charge déjà faite. La première séance d'un exercice sert de référence et n'est jamais un record. Échauffements et séries à 0 rép exclus.
- Statut par exercice (ordre de priorité) : moins de 3 séances = « pas assez de séances (n/3) » · **Prêt à monter** (`LiftProgression.suggest` sur la dernière séance et la ligne du programme, +2,5 kg ou 5 lb) · **En baisse** (aucun record sur les 2 dernières séances, et leurs deux 1RM estimés à plus de 5 % sous le meilleur d'avant) · **En progrès** (au moins un record sur les 3 dernières séances) · sinon **Stagne** (« n séances sans record », n = séances depuis le dernier record).
- Un exercice dans aucun programme peut progresser, stagner ou baisser, mais n'est jamais « prêt à monter ».
- Courbe d'un exercice = 1RM estimé (Epley) de la meilleure série de chaque séance (ou la charge au-delà de 12 réps) ; points pleins = record ; bandes = même charge. Échelle de double progression : séances consécutives à la charge de la dernière séance (4 au plus), total / (séries × haut de fourchette).
- Période (4 sem. / 12 sem. / Tout) : change la courbe, l'évolution en %, le nombre de records et de séances ; pas le statut.
- **Muscles** : séries par semaine (direct 1, indirect ½), moyenne sur 4 ou 12 semaines, divisée par les semaines d'historique seulement si l'historique est plus court. Valeurs lues par `WhoopStore.liftSetCounts` (même lecteur que l'ancienne carte hebdo, épinglé à `LiftMetrics.muscleCounts`). Échelle bleue 0 / < 2 / 2–4 / 4–8 / 8–12 / 12+ ; repère 4 séries.
- **À prioriser** = muscle principal d'au moins une ligne de programme ET (sous 4 séries/sem. OU tous ses exercices directs avec un statut stagnent ou baissent). Aucun sans séance enregistrée. Tri : les deux raisons d'abord, puis le moins de séries. Contour ambre. Les autres muscles sont listés en note (« jamais mis en priorité »).
- Équilibres : poussée (pectoraux, deltoïdes antérieurs et latéraux, triceps) / tirage (dorsaux, haut du dos, trapèzes, deltoïdes postérieurs, biceps), quadriceps / ischios, deltoïdes antérieurs / postérieurs ; affichés seulement si les deux côtés ont des séries.
- Toucher un muscle → feuille : séries par semaine sur 12 semaines (trait = repère 4) + exercices qui le travaillent (direct / indirect ½, séries par semaine, statut).
- **Forme** : affichée à partir de 20 séances mesurables (sinon « Encore n séances »). Perf d'une séance = médiane, sur ses exercices avec un 1RM estimé et 4 séances précédentes, de l'écart à la moyenne de ces 4 séances. Groupes par Charge du matin (67–100 / 34–66 / 0–33) et par nuit d'avant (≥ 7 h / 6–7 h / < 6 h, `totalSleepMin` du jour), points bornés à ±10 %, médiane à droite.
- Carte du Carnet : 4 compteurs, « Charges à monter » (exercice · programme, 40 → 42.5 kg), « À prioriser » avec mini-silhouettes, « Voir la progression » (toujours là). Elle remplace la section « Séries par muscle · 7 jours ».
- États vides (9474905) : carte du Carnet = une phrase d'explication + « Voir la progression » ; Exercices = compteurs à 0 + « Aucune séance pour l'instant… son statut arrive après 3 séances » ; Muscles = silhouette grise + « Après tes premières séances, les muscles sous le repère ou qui ne progressent plus apparaissent ici » ; Forme = « Encore n séances » (n/20).

## Écarts avec les maquettes (décidés en codant)
- Charges au format du Carnet (« 42.5 kg », point décimal, comme le reste du Carnet) ; nombres de séries et ratios au format français (« 2,8 », « 0,8 : 1 »).
- Libellés : « Bilan » (onglet Exercices), « Face » / « Dos », « Tendance » au lieu de « Gain », « Ensuite » dans l'échelle.
- Pluriels gérés (« 1 séance », « Encore 1 séance », « 1 muscle ») ; la clé existante « %lld sessions » a reçu ses formes au singulier.

## Fichiers
- `Strand/Data/LiftProgress.swift` (règles pures) · `Strand/Screens/LiftProgressData.swift` (lecture du store, libellés) · `LiftProgressView.swift` (carte, écran, onglets, feuille muscle) · `LiftExerciseProgressView.swift` (détail) · `LiftBodyMap.swift` (silhouette) · `LiftLogView.swift` (carte à la place de la section hebdo).
- Tests : `StrandTests/LiftProgressTests.swift` (règles), `StrandTests/LiftProgressRenderTests.swift` (12 semaines A/B/C générées + états vides, PNG) ; ajouté à `fork-render-on-push.yml`.

## Pistes pour plus tard
- Le Coach lit les statuts (ex. « développé militaire : stagne depuis 3 séances ») via `LiftProgress.exercises`.
- Bloc Régularité (séries par semaine sur 12 semaines, calendrier).
