# Nutrition — design (mise à jour : 2 nov. 2026, ~03:10)

**État : chantier terminé côté code.** 4a (PR #16, 287a99f), 4b (PR #17, a8827d2), 4c (PR #18, 8dba15c), 4d (PR #19, cb154b8). **Corrections du 2 nov. (validation)** : PR #23 dictée/photo sans le Coach (fusion **90eaea8**), PR #24 Open Food Facts (fusion **e5650c9**, `main` e5650c9). IPA installée : `build/nutrition` = cb154b8 (sans #20–#24). **Ensuite** : validation sur le téléphone avec la prochaine IPA groupée (captures).
Décision de Mohamed (1er nov., 20:15) : **Nutrition maintenant**, en entier, avant la validation écran par écran de l'IPA 92388be. Une seule IPA à la fin de 4d.

## Maquettes
Canvas « NOOP – Nutrition » — https://claude.ai/artifact/7b5S7F8Q9zTwh7e5UXDVf2 (version 1793574244-a1d5)
Artboards : 1 Journal du jour (écran complet) · 2 Ajouter un repas · 3 Objectifs calculés (écran complet) · 4 Aujourd'hui · ligne sous Calories · 5 Coach · photo → carte Repas · 6 Coach · dictée → carte Repas ajoutée · 7 Code-barres · produit jamais vu · 8 Coach · étiquette lue → carte Produit · 9 Code-barres · produit déjà lu (sans réseau).
Valeurs inventées (profil d'exemple : homme, 30 ans, 178 cm, 80 kg).
- **Validées le 1er nov. (20:35)** : 1 à 6, avec 5 et 6 refaites le même jour sur la vraie `CoachSessionCard`.
- **7 redessiné en 7 · 8 · 9, validé le 2 nov. (~00:20, widget)** : tuile Code-barres de l'artboard 2 = « étiquette lue par le Coach ». Revu le 2 nov. (validation) : Open Food Facts d'abord (PR #24), l'étiquette reste le repli.

### Carte Repas (artboards 5 et 6) — gabarit de la carte Séance
- Même carte (`NoopPanelSurface`, rayon 24, marge 16) ; en-tête « REPAS PROPOSÉ » + heure ; nom ; résumé « 3 aliments · quantités estimées sur la photo · Ciqual » ou « … quantités dictées … ».
- Une ligne par aliment (puce des exercices seuls) : « ≈ 180 g · **230 kcal** » (≈ seulement pour une quantité estimée).
- Total dans un encadré (`MealTotalsRow`) : KCAL · PROT. · GLUC. · LIPIDES ; grammes avec une décimale sous 10 g (« 0,3 g »), entiers au-dessus.
- **Ajouter au journal** (prend la place restante) + **Modifier** (à sa largeur). Après le tap : « ✓ Dans ton journal », Modifier reste.

### Code-barres (artboards 7 · 8 · 9) — codé en 4d, Open Food Facts ajouté en PR #24
- **Produit inconnu du journal** : d'abord **Open Food Facts** (PR #24, voir plus bas). Trouvé → panneau 9 avec « Open Food Facts (ODbL) · vérifie les valeurs avant d'ajouter ». Absent ou sans réseau → panneau 7 avec une ligne qui dit pourquoi.
- **7 Produit jamais vu** : « Pas encore dans ton journal » + code ; explication ; encadré « Envoyé avec ta clé Anthropic… / Gardé sur ton iPhone… » ; **Photographier l'étiquette** + **Saisir à la main**. Sans Coach Anthropic configuré : texte d'explication et seulement « Saisir à la main ».
- **8 Coach** : photo + « Lis l'étiquette de ce produit (code-barres …) » dans une nouvelle conversation ; carte « PRODUIT LU SUR L'ÉTIQUETTE » (variante de la carte Repas : icône code-barres, « code-barres … · valeurs de l'étiquette », ligne POUR 100 G).
- **9 Produit déjà lu** : « déjà dans ton journal · sur ton iPhone » (PR #24 : il peut venir d'Open Food Facts ou de l'étiquette), « Relire l'étiquette », POUR 100 G, portion −/+ 10 g, puces (100 g, la dernière fois, 200 g), total, « = valeurs pour 100 g × 1,5 · aucune requête envoyée », Ajouter au journal.

## Corrections du 2 nov. 2026 (validation) — fusionnées dans `main`
### PR #23 — dictée et photo sans le Coach (`feat/nutrition-capture`, fusion 90eaea8)
- Les tuiles **Dicter** et **Photo** d'« Ajouter un repas » restent dans Nutrition : feuille de saisie `NutritionMealCaptureSheet` (dictée sur l'appareil `CoachVoiceInput`, texte modifiable une fois arrêtée ; photo = appareil ou Photothèque, 4 photos au plus, détail facultatif).
- **Trouver les aliments** = une requête avec la clé Anthropic, hors conversation (`AICoachEngine.estimateMeal`, `Strand/AI/AICoachMealEstimate.swift`) : `search_foods` sur Ciqual, puis `log_meal` (ou `read_label` pour un tableau nutritionnel). Le modèle ne donne aucune calorie ; l'app calcule.
- La proposition s'ouvre dans l'**éditeur de repas en brouillon** (`NutritionEditorTarget.draft`) : quantités modifiables, aliment retirable, ligne **Ajouter un aliment** (recherche Ciqual sur l'appareil, `NutritionFoodSearchSheet`, ajouté à 100 g). Rien n'est enregistré avant « Ajouter au journal ».
- Rien dans l'historique du Coach ; les photos sont supprimées à la fermeture de la feuille. Rendu `10-dicter` (release `render-render-nutrition-capture`). Tests `MealEstimateTests`.
### PR #24 — Open Food Facts (`feat/nutrition-open-food-facts`, fusion e5650c9)
- `Strand/Data/OpenFoodFacts.swift` : `lookupProduct` (GET `world.openfoodfacts.org/api/v2/product/<code>.json`, seul le code-barres part, User-Agent identifiant, 8 s), `parseProduct` (nom français sinon générique + 1re marque ; valeurs pour 100 g ; kcal, sinon kJ ÷ 4,184, sinon 4/4/9 ; mêmes refus que l'étiquette : macros > 102 g ou > 900 kcal pour 100 g).
- Une fois ajouté, la ligne du journal garde les valeurs (`foodRef = ean:<code>`) : le scan suivant se fait sur l'iPhone, sans requête.
- Réglage : Nutrition → Objectifs → **Codes-barres** « Chercher les nouveaux produits sur Open Food Facts » (activé par défaut, `nutrition.openFoodFactsEnabled`, UserDefaults, hors `.noopbak`). Écart assumé avec `docs/SCOPE.md` d'upstream (fork personnel). Données : contributeurs Open Food Facts, ODbL.
- Rendu `12-code-barres-open-food-facts` (release `render-render-nutrition-open-food-facts`). Tests `OpenFoodFactsTests`. Conflit `Localizable.xcstrings` / `NutritionRenderTests` résolu en gardant les deux blocs (commit d5ff2d2), CI 7/7.

## Décisions validées
### Avant le 1er nov. 20:15
- **Pas d'import CSV** : tout vient du journal.
- Saisie V1 : à la main, récents/favoris en un tap, photo via le Coach, dictée au Coach, code-barres. (2 nov. : dictée et photo aussi directement dans Nutrition, PR #23.)
- Stockage repas par repas (nouvelle table, migration GRDB + Room, parité).
- Aujourd'hui : ligne sous les demi-anneaux « Mangé · bilan · protéines x/y g », absente sans repas ; tap → Nutrition.
- Objectifs tous calculés par formule (aucun chiffre inventé par le modèle). Rien n'est enregistré sans un tap.

### 1er nov. 20:35 (widget)
- Protéines **2,0 g/kg**, lipides **1,0 g/kg**, objectif calories **−10 % / maintien / +10 %** par pas de 5 %.
- Import CSV Nutrition masqué. Libellés « **Objectif d'activité** » / « **Objectif d'apport** ».
- Détail par aliment stocké (`mealItem`) ; séries `calories_in`… non écrites ; `.noopbak` = toute la base (repas compris).
- Android : données seulement.
- **Ciqual 2025** embarquée (Anses, doi:10.57745/RDMHWY, Etalab 2.0, 3 323 aliments gardés sur 3 484, 346 Ko). Branche temporaire `ci/ciqual-2025` + release `ciqual-a651d39` (à supprimer seulement sur accord).
- Photos du Coach : locales, réduites (JPEG 1568 px), supprimées avec la conversation, hors `.noopbak`.
- **Code-barres** : au départ, `docs/SCOPE.md` n'autorisait pas Open Food Facts → étiquette lue par le Coach ; produit retrouvé localement par `foodRef = "ean:<code>"`, aucune table nouvelle. **Revu le 2 nov.** : Open Food Facts d'abord (PR #24), étiquette en repli.

## Formules (`Strand/Data/NutritionGoals.swift`)
- Métabolisme de base = Harris-Benedict révisée avec les coefficients de l'estimateur de calories ; défauts 70 kg, 170 cm, 30 ans.
- Dépense de référence = moyenne des totaux du bracelet des **14 jours complets avant aujourd'hui**, **3 jours minimum**.
- Objectif d'apport = dépense moyenne × (1 + %), arrondi à 10 kcal. Protéines / lipides = g/kg × poids ; glucides = le reste ÷ 4.
- Ligne tapée : kcal = 4/4/9 tant que l'utilisateur ne tape pas ses kcal. Ligne Ciqual, étiquette ou Open Food Facts : valeurs pour 100 g × quantité (`MealMath.portion`).
- Étiquette (4d) et Open Food Facts (PR #24) : kcal, sinon kJ ÷ 4,184, sinon 4/4/9 ; refus si protéines + glucides + lipides > 102 g ou énergie > 900 kcal pour 100 g.
- Réglages (UserDefaults, hors `.noopbak`) : `nutrition.proteinTenthsPerKg`, `nutrition.fatTenthsPerKg`, `nutrition.goalPercent`, `nutrition.openFoodFactsEnabled`.

## 4a — Stockage (PR #16, `main` 287a99f)
- Migrations iOS `v51-meal-log`, Android `MIGRATION_42_43` (Room 43).
- **`meal`** (`origin` : `manual` | `photo` | `voice` | `barcode`) et **`mealItem`** (`foodRef` `ciqual:<code>` / `ean:<code>`, valeurs pour 100 g, index `(foodRef)`).
- `MealMath` Swift/Kotlin (oracle commun) ; accès app **`Strand/Data/MealJournal.swift`** (toute lecture/écriture de repas).
- Leçons de parité : `test-only-callsite` bloquant ; jumeau Kotlin hors racines gouvernées ; dispositions `platform_specific` + `parity_ledger.py --refresh-derived`.

## 4b — Écrans (PR #17, `main` a8827d2)
- Nutrition (journal, bilan, repas, balayage → Supprimer), Ajouter / Modifier, Objectifs, ligne d'Aujourd'hui ; une seule source « dépensé » (`TodayEnergy.heartRateWindow` + `resolvedSplit`, `NutritionDaySummary`).

## 4c — Coach (PR #18, `main` 8dba15c)
- Ciqual embarquée (`CiqualTable`) ; outils `search_foods`, `log_meal` (toujours) et `get_meals` (avec « Utiliser mes données ») ; carte Repas (`CoachMealCard`, `CoachMealProposal`, `AICoachMeal`) ; photos (`CoachPhotoStore`, bouton « + », 4 par question, Anthropic seulement) ; dictée marquée ; bloc NUTRITION de la fiche ; « Analyse mon repas en photo ». Tuiles Photo / Dicter branchées sur le Coach (remplacées en PR #23 par la saisie dans Nutrition). Rendu `render-render-nutrition-coach`.

## 4d — Code-barres (PR #19, `feat/nutrition-barcode` e40bbc2, fusionnée le 2 nov. ~01:45, `main` cb154b8)
- **Scanner** (`Strand/Screens/NutritionBarcodeScanner.swift`, iPhone seulement) : AVFoundation (EAN-13, EAN-8, UPC-E), caméra arrière, lampe, accès caméra demandé/expliqué, vibration au code lu. Ouvert par la tuile Code-barres **après** la fermeture de la feuille Ajouter (`onDismiss`) ; « Saisir à la main » ferme le scanner puis ouvre l'éditeur ; une étiquette envoyée ferme le scanner puis ouvre le Coach.
- **Panneaux** (`NutritionBarcodePanels.swift`, purs, rendus en PNG) : `BarcodeLookingPanel`, `BarcodeUnknownPanel` (7), `BarcodeKnownPanel` (9).
- **Produits** (`Strand/Data/BarcodeCatalog.swift`) : code normalisé (8 à 14 chiffres ASCII), `productRef` = « ean:<code> », produit = dernière ligne du journal (3 ans) avec ce `foodRef` et des valeurs pour 100 g ; portion de départ = celle de la dernière fois (sinon 100 g), bornée 1–2 000 g.
- **Coach** : `coach.startNewConversation()` puis `coach.submit(…, photos:, labelBarcode:)` ; le code voyage dans les extras de la question (`CoachReplyMeta.barcode`) et **l'emporte sur celui du modèle**. Outil **`read_label`** (toujours avec Anthropic) → `CoachMealProposal.fromLabelInput` (bornes ci-dessus, origine `barcode`, ligne sans code Ciqual) ; carte = variante « Produit lu sur l'étiquette ». Ligne « Étiquette » ajoutée au rôle (v1.6).
- **Texte d'autorisation caméra** : couvre code-barres, repas et étiquettes.
- Tests : `BarcodeProductTests` ; `NutritionRenderTests` : `7-coach-etiquette`, `8-code-barres-inconnu`, `9-code-barres-connu` (release `render-render-nutrition-barcode`).

## Reste à faire
- Validation sur le téléphone avec la prochaine IPA groupée (impossible en CI) : dictée → éditeur pré-rempli → modifier ou ajouter un aliment → Ajouter ; même chose en photo ; scan d'un produit connu d'Open Food Facts ; produit inconnu → étiquette par le Coach ; second scan sans réseau ; lampe ; refus de la caméra.

## Liens avec les autres chantiers
- Aujourd'hui (PR #8) : ligne sous les demi-anneaux ; même dépense (`TodayEnergy`, séances : PR #20).
- Coach : `log_meal` / `read_label` sur le modèle de `create_program` ; toute requête par `submit` / `beginBriefIfNeeded` / `regenerateLastReply`, tout flux par `CoachStreamRelay` ; requête ponctuelle hors conversation : `estimateMeal` (PR #23).
- Plus regroupé (chantier Entraînement, PR #25) : Nutrition = un des 6 groupes, ouvre directement l'écran Nutrition.
- Fichiers partagés : `Localizable.xcstrings`, `TodayHeroCard.swift`, `TodayVitals.swift`, `LiquidTodayView.swift`, `AICoach.swift`, `AICoachMeal.swift`, `AICoachMealEstimate.swift`, `AICoachToolRunner.swift`, `CoachTools.swift`, `CoachReplyMeta.swift`, `CoachMealProposal.swift`, `CoachView.swift`, `CoachMealCard.swift`, `CoachPhotoViews.swift`, `Providers/AnthropicTools.swift`, `MealJournal.swift`, `BarcodeCatalog.swift`, `OpenFoodFacts.swift`, `NutritionDay.swift`, `NutritionGoals.swift`, `NutritionFormat.swift`, `NutritionView.swift`, `NutritionMealEditor.swift`, `NutritionMealCapture.swift`, `NutritionBarcodeScanner.swift`, `NutritionBarcodePanels.swift`, `CiqualTable.swift`, `MealLogStore.swift`, `RootTabView.swift`, `TabRoute.swift`.

## Couleurs
- Jetons : metricCyan (protéines), metricAmber (glucides), metricPurple (lipides) ; total kcal en gris clair. Style Titanium par défaut : glucides orange, lipides bleu.
