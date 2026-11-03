# NOOP - Dossier de travail pour Claude Code
**Objet** : audit vérifié du code + pistes d'évolution (Coach, graphiques, nutrition, notifications, laboratoire de santé), préparé pour guider des chantiers sans redécouverte du code.
**Base vérifiée** : `main` @ **55a249b1** (2 nov. 2026, 21:07) - lecture seule, aucune modification. HEAD revérifié le 2 nov. ~22:11 : inchangé. Revérifier le HEAD avant de coder (règle 1 du fork) : une branche `build/*` ou `feat/*` peut être en avance.
**Révisions** : v4 (2 nov. ~22:15) - ajout §1.12 / §2.10 bis (Laboratoire de santé, import PDF, lien Nutrition) + passe de confirmation complète : chaque localisateur et constat a été relu dans le code à 55a249b1 ; corrections listées en §7. v4.1 (~22:20) - portée exacte de l'upsert `labMarker` précisée (dédoublonnage limité, remplacement à clé identique) et consentement PDF requalifié (spécifique requis, aucune couverture par les opt-in existants).
**Auteur de l'audit** : Instinct (agent), le 2 nov. 2026. Numéros de ligne ≈ indicatifs (ils dérivent) ; les chemins et noms de symboles sont la référence stable.

---

## 0. Mode d'emploi

**Ce que ce fichier est** : un dossier de préparation. Chaque piste indique où se trouve le code, ce qu'il fait aujourd'hui, ce qui manque, quoi réutiliser, quoi vérifier.
**Ce qu'il n'est pas** : ni une décision d'implémentation, ni une validation des choix listés en §5. Mohamed tranche avant chaque chantier ; un seul chantier de code à la fois (règle du fork).

**Étiquettes utilisées** :
- **[PREUVE]** : constat lu dans le code à 55a249b1 (fichier + symbole cités).
- **[PROPOSITION]** : suggestion de l'audit, à valider avant de coder.
- **[CHOIX]** : arbitrage ouvert, volontairement non tranché ici.
- **[À TESTER]** : non reproductible sans iPhone/bracelet ; le code seul ne le prouve pas.

**Avant de coder** : lire `.claude/rules/fork-noop.md` (règles du fork), `docs/fork/feuille-de-route.md` (état de `main`, décisions communes, pièges parité/i18n/CI), `AGENTS.md` (règles upstream : design tokens, migrations, parité Swift/Android), puis la fiche du chantier concernée dans `docs/fork/`. Les fiches `docs/fork/` consignent « validé par Mohamed » : c'est la mémoire du projet ; les choix **ouverts** de ce dossier (§5) ne sont pas tranchés par ces fiches.

**Statut des règles citées** : les règles du dépôt reprises ici (§0, §6 : branches, CI, PR, build, IPA) sont des consignes pour toute **future** session de code - elles n'autorisent rien aujourd'hui. Aucune branche, CI, PR, compilation ou IPA sans le feu vert de Mohamed au moment du chantier. De même, les fiches `docs/fork/` (mentions « validé par Mohamed » comprises) sont la documentation du projet : elles servent de contexte, et les choix ouverts de ce dossier restent à valider par Mohamed.

**Hors périmètre de ce dossier** :
- Fournisseurs IA autres qu'Anthropic (décision de Mohamed, 2 nov. : Anthropic seul). Ne rien proposer pour OpenAI/Gemini/Custom.
- Les arbitrages d'architecture non validés (ex. découpage en cinq onglets, déplacement de Sommeil, Coach global) : ne pas les traiter comme acquis.
- Aucune modification du dépôt n'est demandée à ce stade.

**Séquence convenue** : Mohamed refait d'abord le design (chantier 7) ; les chantiers fonctionnels de ce dossier viennent ensuite. Les localisateurs sont datés à 55a249b1 : après la refonte, une passe de réactualisation sera nécessaire avant de coder (la refonte déplacera des lignes, pas les concepts).

---

## 1. Cartographie vérifiée (anti-redécouverte)

### 1.1 Coach - chaîne d'envoi d'une question
| Élément | Fichier | Symbole (≈ ligne) |
|---|---|---|
| Moteur | `Strand/AI/AICoach.swift` | `AICoachEngine` (162) |
| Point d'entrée question | idem | `submit(_:photos:dictated:labelBarcode:)` (1072), `send(...)` (1112) |
| Contexte d'une question | idem | `questionContext()` (1471) → `buildFullContext()` (1479) → `ficheInputs()` (1526) |
| Rôle système | idem | `defaultSystemPrompt` (293), `toolsRole(readTools:)` (400), texte de référence : `docs/fork/coach-instructions.md` (v1.6) |
| Outils envoyés | idem | `provider == .anthropic ? CoachTools.definitions(...)` (1166) ; photos idem (1115) |
| Boucle outils | idem | `streamToolAnswer` (1188), `streamToolRound` (1328) |
| Exécution des outils | `Strand/AI/AICoachToolRunner.swift` | `runTool(_:input:)` (15) |
| SSE Anthropic | `Strand/AI/Providers/AnthropicTools.swift` | `AnthropicTurnAccumulator` (46) |
| Extras d'un message | `Strand/AI/CoachReplyMeta.swift` | bloc ```` ```noop-coach ```` (consulté / séance / repas / photos / code-barres) |
| Conversations | `Strand/AI/AICoach.swift` | `conversationDigests()` (836) - utilisé **seulement** par `CoachHistoryView` (liste) ; le modèle ne lit **pas** les autres conversations |

### 1.2 Coach - fiche (envoyée avec chaque question si « Utiliser mes données »)
Assemblage dans `Strand/AI/CoachFiche.swift` - `head(_:told:)` (105) : USER PROFILE (`bodyBlock`, âge/sexe/taille/poids/FC max, mention « app default » si non saisi) · WHAT THE USER TOLD THE COACH (`CoachProfile.contextBlock`) · TODAY (`todayBlock` : charge, effort, nuit, RHR, HRV, SpO2, respiration, temp. peau, pas, kcal repos/activité via `NutritionDayReader.spentFromSamples`, `Strand/Data/NutritionDay.swift` 60) · YOUR NORMALS (`normalsBlock`, bandes via `repo.chargeBaselines`) · SLEEP (`sleepBlock`, via `Repository.sleepSynthesisFigures` - extension dans `Strand/Data/LiveHRBannerFigures.swift` 69) · NUTRITION (`nutritionBlock` : jour vs objectifs + 7 j). Compléments assemblés dans `AICoach.swift` (`buildFullContext`/`buildContext`) : 14 derniers jours + moyennes 30 j · 6 dernières séances (`recentWorkoutsBlock`, 1974) · stress (`stressIndexLine()`, 1681, Baevsky) · LIFT LOG · LIFT PROGRESSION (`LiftProgressData.load`, 1604) · WEEK PLAN (`CoachFiche.weekPlanText` 283 + `trainingWeekPlanBlock`, 1628) · siestes 14 j (`napsBlock()`, 1613 + `CoachNapContext`) · signaux/Lab Book seulement avec le 2e opt-in (`includeOnDeviceSignals` → `onDeviceSignalsBlock()`, 1700 : patterns du Journal + roll-up LAB BOOK avec la dernière valeur de chaque marqueur, 8 max).

### 1.3 Coach - outils de lecture (Anthropic seulement)
`Strand/AI/CoachTools.swift` - `Name` (15) : `get_metric_history` (7–180 j, 1 métrique/jour, `dayRange` 100), `get_night` (≤ 400 j, garde dans `AICoachToolRunner` 38), `get_workouts` (≤ 60 lignes, runner 50 : sport, durée, effort, FC moy/max, kcal, distance), `get_exercise_history` (≤ 365 j), `get_programs`, `get_journal` (7–90 j, `journalDayRange` 101), `get_meals` (1–30 j, `mealDayRange` 105), `get_lab_book` (2e opt-in). **Limites** (97–99) : `maxRounds = 4`, `maxResultCharacters = 6000`. Métriques exposées (`Metric`, 28) : charge, effort, sleep, hrv, rhr, spo2, respiration, skin_temp, steps, calories. **Ni FC intrajournalière, ni poids, ni hydratation, ni objectifs, ni appareils.**

### 1.4 Coach - actions existantes (cartes à valider, rien sans tap)
| Action | Définition | Carte | Écriture |
|---|---|---|---|
| Créer un programme | `CoachSessionProposal.swift` (`create_program`, 30 ; bornes : 20 lignes, séries 1–10, réps 1–50, repos 0–600 s, 5–240 min, ≤ 500 kg) | `CoachSessionCard.swift` | « Ajouter au Carnet » (`addSessionToLiftLog`), « Démarrer » (iPhone) |
| Ajouter un repas | `CoachMealProposal.swift` (`log_meal`, 40) | `CoachMealCard.swift` | « Ajouter au journal » / « Modifier » (éditeur Nutrition pré-rempli) |
| Lire une étiquette | idem (`read_label`, `fromLabelInput`) | variante Produit | idem |
| Chercher un aliment | `search_foods` (Ciqual embarquée) | - | - |

**Borne temporelle du repas** [PREUVE] : `CoachMealProposal.mealTime` (158–180) = `min(max(when, earliest), now)` avec `maxDaysBack = 7` (47) → un repas proposé est **toujours daté au passé/présent**, jamais au futur. Pas de notion de « repas prévu » : `meal.origin` ∈ `manual | photo | voice | barcode` (`MealLogStore.swift` 112).

### 1.5 Fréquence cardiaque et graphiques
| Élément | Fichier | Détail vérifié |
|---|---|---|
| Carte FC d'Aujourd'hui (En direct / Journée) | `Strand/Liquid/TodayHeartRateCard.swift` | `TodayHeartRateSection` (558), teinte par défaut `StrandPalette.liquidHeart` (560) |
| Couleur de la courbe | idem | tracé teinté `tint` en tout état ; recoloration au-delà du seuil seulement si `model.threshold` + `alertSide` (≈144, ≈179) |
| Logique d'alerte | `Strand/Liquid/TodayVitals.swift` | `TodayHRAlert` (185) : seuil haut = habitude + 20 (`highMarginBpm`, 187), seuil bas = plancher éveillé (14 j, ≥ 3 j) ; provisoires : repos + 30 / repos ; franchi retenu si ≥ 180 s (`minDurationSec`, 189), trous ≤ 15 s ; `alert()` (255) = franchi **ET** aucune séance **ET** `phoneStill == true` (nil → jamais d'alerte) |
| Immobilité du téléphone | `TodayHeartRateCard.swift` | `PhoneStillness` (529), iOS seulement (`CMMotionActivityManager`) |
| Couleurs d'alerte | `Packages/StrandDesign/.../Palette.swift` | `statusWarning` / `statusPositive` (257–258) ; `liquidHeart` (141 : #D94C64 clair / #FF6B81 sombre, **identique dans les deux thèmes**) |
| Couleur `metricRose` | idem | **dépend du thème** (265) : Classic = #CB3A2F / #E5483B (rouge) ; Titanium (**thème par défaut** : `chartStyle = .titanium`, 150 ; `SettingsView` 135) = #C84E1E / #E0662F (**orange**) |
| Historique FC (exploration) | `Strand/Screens/FullDayChartView.swift` | tint `metricRose` (220, dégradé 490) - ouvert depuis `MetricExplorerView` |
| FC en direct (séance) | `Strand/Screens/LiveWorkoutView.swift` | `metricRose` (135–147), zones via `hrZoneColor` (Palette 399 ; usages 178–259) |
| Donnée 5 min | `Packages/WhoopStore/Sources/WhoopStore/Reads.swift` | `HRBucket` (9 : `ts`, `bpm` moyenne 5 min, `minBpm`, `maxBpm`) - utilisée par `dayChart`, `HabitualHR`, les graphiques de sommeil ; **jamais exposée au Coach** |
| Phases de sommeil | `Palette.swift` | `sleepStageColor` (405) : 4 teintes distinctes - pas de confusion avec la couleur FC |
| Rampes Charge/Effort | idem | `recoveryStops` (203), `strainStops` (224) - gradients dédiés |

### 1.6 Planning et calendrier d'entraînement
`Strand/Data/TrainingPlan.swift` - `TrainingWeekPlan` (13), `programs : [String: String]` (15) : **un seul id de programme du Carnet par jour ISO** ; `planDecision(for:calendar:)` (53) = seul résolveur (.program / .rest), lu par le calendrier, la Synthèse, le Coach (WEEK PLAN) et le widget (`TodaySessionResolver`, `Strand/Data/TodaySessionResolver.swift` 29). `TrainingDays.buildTrainingDays` (217) assemble prévu + fait ; les activités cardio **faites** s'affichent (orange), mais le planning ne sait **pas planifier** de cardio ni plusieurs séances le même jour. Édition : `Strand/Screens/TrainingPlanSheet.swift`.

### 1.7 Sommeil et siestes (réutilisable par le Coach)
`Strand/Data/Repository.swift` : `addManualNap(startTs:endTs:)` (1731 - borne anti-futur via `SleepEditGuard`, staging depuis le brut, session séparée jamais fusionnée à la nuit) ; `editSleepTimes(...)` (1557) ; `deleteSleepSession(...)` (1609, renvoie un snapshot d'**annulation**). UI existante : `SleepView` « Ajouter une sieste » (bouton ≈684, feuille ≈302) ; bannière d'annulation après suppression (≈130–174, snapshot ≈282).

### 1.8 Séances : ajout et correction (réutilisable)
- `Strand/Screens/ManualWorkoutSheet.swift` (24) : 6 champs - sport, début, fin (durée **dérivée**), distance, FC moyenne, calories ; validation `WorkoutSource.buildManualRowFromSpan` (`Strand/Data/WorkoutSource.swift` 384, appelée à 448 ; variante `buildManualRow` 413) ; persistance `Repository.saveManualWorkout`. Ouvert par `WorkoutsView.editWorkout(_:isCopy:)` (449) et le bouton d'ajout (≈609).
- `Strand/Screens/LiftSessionEditSheet.swift` (16) : corrige une séance du Carnet **terminée** (séries, charges, réps, RPE ; ajout/retrait de séries ; seule cette séance change, jamais le programme ; figures recalculées).

### 1.9 Nutrition
- Journal et accès : `Strand/Data/MealJournal.swift` (toute lecture/écriture de repas côté app) ; stockage `Packages/WhoopStore/Sources/WhoopStore/MealLogStore.swift` (`MealRow`, `MealOrigin` = manual/photo/voice/barcode, 112) ; tables `meal` / `mealItem` (migration « v51-meal-log », `Database.swift` 1233 ; jumelle Room dans `WhoopDatabase.kt`, base Android v43) ; `MealMath` (jumeau Kotlin).
- Objectifs : `Strand/Screens/NutritionGoalsView.swift` (11) - AppStorage `nutrition.proteinTenthsPerKg`, `nutrition.fatTenthsPerKg`, `nutrition.goalPercent` (clés dans `Strand/Data/NutritionGoals.swift` 19–23) ; formules `NutritionGoals`.
- Saisie : éditeur `NutritionMealEditor`, dictée/photo hors conversation (`AICoachEngine.estimateMeal` - extension dans `Strand/AI/AICoachMealEstimate.swift` 65), scanner code-barres (`NutritionBarcodeScanner` + `OpenFoodFacts.lookupProduct`, `Strand/Data/OpenFoodFacts.swift` 90, repli étiquette par le Coach).
- Trackers dédiés (opt-in) [PREUVE] : **eau** - `Strand/Data/HydrationStore.swift` (activation `noop.hydrationTracking` 29, OFF par défaut ; Sip 30 ml / Cup 237 ml / Bottle 500 ml ; total du jour dans `metricSeries` sous la source/clé « hydration » 22–25 ; import Apple Santé sous clé séparée, `setImported` 143 ; jumeau Android) + `Strand/Screens/HydrationView.swift` (jauge + objectif via le moteur `HydrationGoal`, historique 7 j, tuile Aujourd'hui). **Caféine** - `Strand/Data/CaffeineLog.swift` (saisie manuelle opt-in, estimation « encore actif » par demi-vie : `defaultHalfLifeHours = 5.5`, 25 ; affichée sur Today/Insights) + `Strand/Screens/CaffeineLogCard.swift`.
- Journal d'habitudes [PREUVE] : `Strand/Data/JournalCatalog.swift` - catalogue v2 typé et groupé (questions de départ style WHOOP, dont caféine et alcool ; fusionne les libellés importés d'un export WHOOP pour que `BehaviorInsights` joigne jours internes et importés). L'outil `get_journal` lit ces réponses.
- Historique [PREUVE] : `NutritionView.swift` = journal du **jour** seul (`NutritionBalanceCard` 345 + lignes de repas) - **aucun graphique semaine/mois nutrition n'existe** dans le code vérifié.
- Import CSV [PREUVE] : `Strand/Screens/DataSourcesView.swift` - un import CSV nutrition (Cronometer/MacroFactor → `metricSeries`, source « nutrition-csv », relu par Explorer/Insights) existe (`nutritionCard` 224) mais sa carte est **masquée dans le fork** (≈97 : « meals come from the journal » ; le code est conservé). Imports actifs sur cet écran : WHOOP, Apple Santé, Hevy/Liftosaur, fichiers d'activité (GPX/TCX/FIT).

### 1.10 Notifications (infrastructure existante)
`Strand/System/` - `BatteryNotifier` (6 identifiants : battery-low/full/runtime/stale/critical/bedtime, dédup par jour), `StrainTargetNotifier` (**policy pure testable + opt-in + dédup une fois/jour** - le modèle à copier), `WindDownNudge` (opt-in, OFF par défaut), `CoachBriefScheduler` (brief quotidien généré par le provider configuré, OFF par défaut, clés 33–34 ; iOS sideload : `BGAppRefreshTaskRequest` (432) = **best-effort**, rattrapage à l'ouverture), `IllnessNotifier`. Carte in-app : `JournalReminderCard` (rappel Journal, ON par défaut, clé `PuffinExperiment.journalReminderKey`). **Aucun rappel repas ni rappel lié au planning.** Contrainte sideload : une notification **locale** (`UNCalendarNotificationTrigger`) se déclenche sans réseau ni réveil de l'app ; une notification qui **génère du texte IA** est best-effort (même limite que le brief).

### 1.11 Profil, poids, appareils
- Profil : `ProfileStore` (`Strand/Data/Profile.swift` 9 : âge, sexe, taille, poids **courant**, FC max).
- `DailyMetric` (`Packages/WhoopStore/Sources/WhoopStore/MetricsCache.swift` 82) : champs vérifiés un par un - **aucun poids**. Homonymes à ne pas confondre : la colonne `weightKg` de `appleDaily` (`Database.swift` ≈194) est le poids Apple Santé ; celle de `liftSet` (≈1083) est la charge soulevée en muscu.
- Poids [PREUVE] : import Apple Santé en lecture seule (`StrandiOS/Health/HealthKitBridge.swift` 569–658, dernier relevé du jour ; la passe entière est **suspendue si une lecture agrégée a échoué**, ≈608) → stocké sous la source `apple-health` dans les lignes `AppleDaily` **et** aplati en `metricSeries` (≈638), relu par l'écran Apple Santé, les sparklines d'Aujourd'hui et Metric Explorer. Pas d'écran de suivi du poids dédié hors Apple Santé/Explorer ; absent de `CoachTools.Metric` (comme hydratation et caféine).
- Appareils/batterie : `Strand/Screens/DevicesView.swift`, `BatteryNotifier` - non exposés au Coach.

### 1.12 Laboratoire de santé (« Carnet de laboratoire »)
Le socle existe déjà :
| Élément | Fichier | Détail vérifié |
|---|---|---|
| Table | `Packages/WhoopStore/Sources/WhoopStore/Database.swift` | `labMarker` (migration v17) ; index unique `idx_labMarker_natural` (346) sur (deviceId, markerKey, takenAt, source) ; jumeau Room + test de migration Android (`LabMarkerMigrationTest.kt`) |
| Store | `.../WhoopStore/LabMarkerStore.swift` | `upsertLabMarkers` (112, `ON CONFLICT ... DO UPDATE`) : dédoublonnage **uniquement à clé naturelle identique** (deviceId, markerKey, takenAt, source) - même source + même instant = **remplacement** de la valeur (pas d'historique de la ligne écrasée) ; source ou horodatage différent = **nouvelle ligne** (doublon possible entre sources) ; projection `metricSeries` = dernier relevé du jour |
| Modèle | `Packages/StrandImport/.../LabMarker.swift` | `LabMarker` (markerKey, `category`, `value`/`valueText`, `unit`, `takenAt`, `source`, `note`, `referenceText`) ; catégories : bloodPanel, bloodPressure, bodyMeasurement, imaging, appointmentNote, other |
| Catalogue | `.../StrandImport/MarkerCatalog.swift` | ~30 marqueurs non-diagnostiques (lipides, glucose/HbA1c, fer/ferritine, vitamines D/B12/folates, thyroïde, CRP, rein, foie, tension, mesures corporelles) ; **aucune plage de référence embarquée** (`referenceTextHint` invite à recopier celle de son propre compte rendu ; `higherIsBetter` toujours nil) ; marqueur libre `custom_<slug>` toujours possible |
| Saisie manuelle | `Strand/Screens/MarkerEditorView.swift` | source « manual » (439) ; valeur, unité verbatim, date, note, plage recopiée |
| Import CSV | `.../StrandImport/LabMarkerCsvImport.swift` | CSV (date, marqueur, valeur, unité), alias vers le catalogue, « 120/80 » scindé systolique/diastolique, unités **jamais converties**, source « lab-csv » ; bouton d'import dans `LabBookView` (≈162) |
| Import WHOOP | `.../StrandImport/WhoopBiomarkerExportParser.swift` | export biomarqueurs WHOOP, source « whoop-biomarkers » |
| Projection | `Packages/StrandAnalytics/.../LabBookProjection.swift` | plie les relevés en points journaliers upsertés dans `metricSeries` sous la source **« lab-book »** (`LabMarkerStore` 96, ≈233) ; appariement avec les séries du bracelet (fenêtre glissante 14 j) + Pearson (`CorrelationEngine`), honnêteté sur n (plancher 4) |
| Écran | `Strand/Screens/LabBookView.swift` | entrée depuis `HealthView` (1575, `router.openLabBook()` - `NavRouter` 76) ; détail par marqueur avec tendance et corrélation ; avertissement non-médical affiché (`LabBookDisclaimerView`) |
| Lecture Coach | `Strand/AI/CoachTools.swift` + `AICoachToolRunner.swift` | outil `get_lab_book` (22 ; 5 dernières valeurs par marqueur, 429) **sous le 2e opt-in** « Tendances et Carnet de laboratoire » (`includeOnDeviceSignals`, garde runner 87–90) ; roll-up dans la fiche (§1.2) |

**Cadrage non-clinique existant** [PREUVE] : l'app ne livre ni plages de référence ni verdict ; `referenceText` est le texte du compte rendu de l'utilisateur, re-affiche verbatim ; l'en-tête de `get_lab_book` impose au modèle « not medical findings, do not diagnose » (`CoachTools.labBook`, ≈433). Le spec amont (`docs/superpowers/specs/2026-06-19-v5-health-records-design.md`) prévoit : phase 3 = dossiers cliniques Apple Santé/FHIR, **phase 4 = OCR PDF/photo strictement sur appareil (Vision/ML Kit), jamais de cloud, confirmation de chaque valeur** (§217) - ce cadrage entre en tension avec la demande PDF-via-Coach de Mohamed (§2.10 bis, [CHOIX]).

**Absents aujourd'hui** [PREUVE] : aucun import PDF/photo de bilan (les photos du Coach ne partent qu'en JPEG vers Anthropic - `AnthropicTools.swift` 132–136 ; le seul PDF du dépôt est l'**export** `TrendsReportRenderer`) ; les séries « lab-book » de `metricSeries` ne sont **pas** listées dans `MetricExplorerView` (aucune référence) ; aucun lien entre Lab Book et Nutrition.

---

## 2. Constats et propositions, par section

### 2.1 Cohérence des couleurs FC
**Constat** [PREUVE] : la courbe FC est **teintée par habillage** sur trois vues, sans lien avec un état, et la teinte n'est **pas la même** selon les vues : `liquidHeart` (rose-rouge constant, #D94C64/#FF6B81) sur la carte d'Aujourd'hui, `metricRose` sur l'exploration et la FC en direct séance - or `metricRose` **dépend du thème** : rouge en Classic (#CB3A2F/#E5483B), **orange en Titanium (#C84E1E/#E0662F), le thème par défaut**. L'alerte « franchi au repos » ne fait que recolorer la portion au-delà du seuil (orange haut / vert bas) quand **toutes** ses conditions sont remplies (≥ 3 min, aucune séance, iPhone immobile avec permission). Une capture seule ne dit pas si ces conditions étaient remplies.
**Écart** : la couleur ne porte aucun sens stable ; l'utilisateur ne peut pas distinguer « habillage » d'« état », et la même donnée change de teinte d'un écran à l'autre (rose-rouge Aujourd'hui, orange en thème par défaut ailleurs).
**Proposition** [PROPOSITION] : une couleur de courbe neutre et identique sur toutes les vues FC ; réserver orange/vert au seul dépassement de seuil **déjà implémenté**, avec son indicateur explicite (libellé + durée du dépassement, déjà partiellement en caption via `liveCaption`/`crossed`). Ne pas inventer d'alerte médicale. [CHOIX] : couleur cible à valider - **coordonner avec le chantier 7 (refonte)** qui refait déjà les couleurs des métriques (`docs/fork/refonte-design.md`, FC #FF375F) pour éviter deux changements.
**Réutiliser** : `TodayHRChartModel.sideColor`, `liveCaption`, les jetons `Palette`.
**Vérifications** : `StrandTests` existants (`TodayVitalsTests`) ; rendus PNG `render/*` ; [À TESTER] franchi réel sur iPhone (permission Mouvements).

### 2.2 FC intrajournalière pour le Coach
**Constat** [PREUVE] : le Coach ne reçoit ni la courbe du jour ni les temps par zone ; seulement RHR/VFC et moyennes/max des séances. La donnée existe : `HRBucket` (moyennes 5 min + min/max).
**Proposition** [PROPOSITION] : outil `get_day_heart_rate` (jour donné, buckets 5 min éventuellement ré-échantillonnés pour tenir sous `maxResultCharacters`) - lecture seule, même consentement « Utiliser mes données ». Réutiliser le lecteur qui alimente `dayChart` (même source = mêmes chiffres que l'écran, règle « deux lectures d'un fait ne doivent pas diverger » d'`AGENTS.md`). Borner : 1 jour par appel, défaut aujourd'hui.
**Vérifications** : tests `CoachToolsTests` ; volume (une journée ≈ 288 buckets → résumer par plages ou par heure).

### 2.3 Planning : plusieurs séances par jour + cardio planifiable
**Constat** [PREUVE] : `TrainingWeekPlan.programs` = jour → **un** programme du Carnet ; pas de cardio planifiable ; les séances **faites** multiples s'affichent déjà (`buildTrainingDays`).
**Proposition** [PROPOSITION] : faire évoluer le modèle jour → liste d'éléments typés (programme du Carnet | activité cardio avec sport + durée cible). [CHOIX] : forme du modèle (migration `training.weekPlan.v1` → v2 ou clé nouvelle), présentation dans `TrainingPlanSheet`, et contenu du bloc WEEK PLAN. Points de contact : `planDecision`, `buildTrainingDays`, `TrainingPlanSheet`, `CoachFiche.weekPlanText`, `TodaySessionResolver` (Synthèse + widget).
**Vérifications** : `TrainingPlanTests` ; rendus `TrainingRenderTests` ; [À TESTER] Synthèse et widget un jour multi-séances.

### 2.4 Corps cliquable dans la création de programme
**Constat** [PREUVE] : `LiftBodyMap` (face/dos, `highlighted`, `onTap` ; `Strand/Screens/LiftBodyMap.swift` 11) existe et sert dans `LiftProgressView` (79–80, 591). `LiftProgramEditorSheet` n'offre que l'ajout texte libre (≈110–135). Le mapping muscle ↔ exercices existe (`Packages/WhoopStore/.../LiftMuscle.swift`, `Strand/Data/LiftMuscleNames.swift`, et le mapping exercice→muscles déjà utilisé par Progression).
**Proposition** [PROPOSITION] : réutiliser `LiftBodyMap` dans l'éditeur de programme comme **filtre d'ajout** (toucher un muscle → exercices du Carnet qui le travaillent, puis ajout libre conservé). Ne pas créer une deuxième silhouette (principe de Mohamed : fonctions existantes au bon endroit, pas de doublon).
**Vérifications** : rendu PNG de l'éditeur ; parité de nommage (`knownExercise` - leçon déjà consignée) ; [À TESTER] parcours complet sur iPhone.

### 2.5 Actions du Coach : sieste, correction de séance, correction de séries
**Constat** [PREUVE] : toutes les briques d'écriture existent côté app (`addManualNap`, `editSleepTimes`, `deleteSleepSession` avec snapshot d'annulation, `ManualWorkoutSheet`/`saveManualWorkout`, `LiftSessionEditSheet`). Le Coach ne propose aujourd'hui que `create_program`, `log_meal`, `read_label`.
**Proposition** [PROPOSITION] : trois cartes d'action sur le gabarit existant (même règle : proposition → aperçu → validation → **annulation possible**) :
1. **Sieste** : `log_nap` (début/fin proposés par le modèle à partir de la déclaration) → `Repository.addManualNap`. Annulation = `deleteSleepSession` (snapshot existant).
2. **Correction de séance** : `correct_workout` (id de séance + champs à modifier) → mêmes règles que `ManualWorkoutSheet` (`buildManualRow`, jamais de fin future). Réutiliser `WorkoutsView.editWorkout`/le sheet comme écran de validation.
3. **Correction de séries** : `correct_lift_session` → réutiliser la logique de `LiftSessionEditSheet`.
[CHOIX] : mécanisme d'annulation uniforme (snapshot vs suppression directe), et si la carte s'affiche dans la conversation (comme Repas) ou ouvre directement la feuille native pré-remplie.
**Garde-fous à écrire dans le rôle** : distinguer données du bracelet et corrections déclarées ; ne jamais présenter une correction comme une mesure ; journaliser l'origine (champ `origin` existe déjà pour les repas - généraliser l'idée).
**Vérifications** : tests des bornes (modèle de `CoachMealProposal.fromToolInput`) ; [À TESTER] chaque carte de bout en bout.

### 2.6 Nutrition : repas prévu vs mangé (le « menu »)
**Constat** [PREUVE] : pas de statut « prévu » - un repas est daté au passé/présent (`mealTime` borné), `origin` ∈ manual/photo/voice/barcode.
**Proposition** [PROPOSITION] : ajouter un statut planifié permettant : « propose-moi un menu pour demain » → carte → validation → repas **prévus** visibles dans Nutrition, convertis en « mangé » d'un tap (ou via le Coach). Point technique : le statut « prévu » est **orthogonal** à `origin` (qui trace la provenance : manual/photo/voice/barcode) - un repas planifié puis mangé garde sa provenance ; il faut donc un **champ dédié** (ex. `meal.status = planned | logged`), pas une valeur d'`origin` qui confondrait les deux axes. Migration éventuelle (`meal` : vérifier la prochaine version - dernière v51 iOS / 43 Android), affichage dans le journal et le widget Nutrition, impact fiche (bloc NUTRITION : prévu ≠ mangé).
**Réutiliser** : `CoachMealCard` (gabarit), `MealJournal`, `NutritionDayReader`.
**Vérifications** : parité données (règle migrations Room/GRDB + `schema_oracle.json`) ; tests `MealMath`/`MealEstimateTests` ; [À TESTER] conversion prévu → mangé.

### 2.6 bis Nutrition : historique semaine/mois (absent - fiche de correction)
**Constat** [PREUVE] : aucun graphique semaine/mois nutrition (§1.9). De plus, Analyses (Explorer/Insights) **ne lit pas les repas internes** : `Repository.exploreSeries` (2458) ne sert que `metricSeries` (sources « my-whoop », « apple-health », « nutrition-csv », « noop-mood » - commentaire ≈2447–2456) et les repas internes vivent dans les tables `meal`/`mealItem` sans jamais alimenter `metricSeries` ; seule la source « nutrition-csv » (import masqué dans le fork) y écrirait des totaux nutritionnels. `BehaviorInsights` lit les habitudes du Journal, pas les repas. Conclusion : **aucune métrique nutritionnelle issue du journal interne n'apparaît aujourd'hui dans Analyses**.
**Proposition** [PROPOSITION] : une section historique dans `NutritionView` (bascule 7 j / 30 j) avec trois graphes : apports vs objectifs (kcal), macros (protéines/glucides/lipides vs objectifs), bilan estimé (apports − dépense). Points d'intégration exacts :
- Lecture par jour : boucler `NutritionDayReader.readDay(_:profile:day:)` (`Strand/Data/NutritionDay.swift` 96) sur la plage - il renvoie déjà `NutritionDaySummary` (eaten/spent/balanceKcal, 11) ; repas seuls : `MealJournal.mealJournalRange(fromDay:toDay:)` (89).
- Objectifs : `NutritionDayReader.currentPlan` (115) - **courants** (AppStorage) ; l'historique s'affiche donc contre les objectifs actuels, sauf si un snapshot d'objectifs daté est ajouté [CHOIX].
- Rendu : réutiliser le composant générique `TrendChart` (`Packages/StrandDesign/Sources/StrandDesign/TrendChart.swift`) plutôt qu'un nouveau graphique.
- Option d'élargissement [CHOIX] : écrire les totaux journaliers internes dans `metricSeries` sous une source dédiée (ex. « noop-nutrition ») pour qu'Explorer/Comparer/Insights les voient aussi - données nouvelles côté série, à traiter avec la règle parité.
**Règles métier à respecter** (tests à écrire, `StrandTests`) :
1. **Jour non saisi ≠ zéro** : un jour sans repas enregistré s'affiche « non saisi » (trou dans la courbe / hachuré), jamais 0 kcal - sinon le bilan estimé affiche un déficit faux.
2. **Objectifs historiques** : vérifier le comportement quand les objectifs changent en cours de période (affichage contre objectifs actuels, libellé explicite).
3. **Prévu exclu** : quand §2.6 existe, les repas `planned` ne comptent ni dans les apports ni dans le bilan (seuls les repas mangés).
4. Bilan estimé marqué comme estimation (dépense via `spentFromSamples`, déjà affichée comme telle).

### 2.7 Poids : série existante mais invisible au Coach
**Constat** [PREUVE] : une série de poids **existe déjà** quand l'utilisateur importe Apple Santé (stockée en `metricSeries` source `apple-health`, affichée par l'écran Apple Santé et Metric Explorer - §1.11). Mais : le profil ne garde que le poids courant, `DailyMetric` n'a pas de poids, et le Coach ne peut lire **aucune** de ces sources.
**Recommandation technique** (§5.1) : exposer la série existante au Coach (bloc fiche + `get_metric_history`) en réutilisant le même lecteur `metricSeries` que l'écran - lecture seule, aucune collecte nouvelle.
[CHOIX] produit (§5.2) : saisie manuelle du poids (donnée nouvelle → migration + parité Android) ou Apple Santé seulement ; et affichage d'un historique : écran dédié ou Metric Explorer existant. Aligné avec la cible « personne qui surveille sa ligne » (§3).

### 2.8 Hydratation et caféine : les trackers existent, le Coach ne les lit pas
**Constat** [PREUVE] : les trackers dédiés **existent** (§1.9) : eau (`HydrationStore`, opt-in OFF par défaut, totaux dans `metricSeries`), caféine (`CaffeineLog`, opt-in, estimation par demi-vie 5,5 h). Le Journal (habitudes oui/non + valeurs, questions caféine/alcool incluses) est lisible par `get_journal`. En revanche **le Coach ne lit ni le tracker eau ni le tracker caféine** : aucune métrique correspondante dans `CoachTools.Metric`, aucune lecture de `metricSeries` « hydration » ni de `CaffeineLog` dans la chaîne du Coach (seule mention de caféine : la ligne « compléments » du rôle système). Distinction nette : les **déclarations** d'habitudes du Journal (questions caféine/alcool, réponses oui/non + valeurs) restent lisibles via `get_journal` - ce sont des réponses déclaratives, pas les mesures des trackers dédiés.
**Recommandation technique** (§5.1) : ne créer **aucun** nouveau tracker - exposer l'existant au Coach : totaux d'eau (lecteur `metricSeries` « hydration ») et estimation de caféine active (`CaffeineLog`/`CaffeineDecay`) dans la fiche et/ou un outil, sous le même consentement « Utiliser mes données ». Garder la règle d'honnêteté : eau enregistrée ≠ eau bue.
[CHOIX] produit (§5.2) : activation par défaut ou mise en avant de ces trackers (aujourd'hui masqués derrière un opt-in), compteur d'eau plus visible (style Foodvisor), place dans le brief du jour.

### 2.9 Mémoire entre conversations
**Constat** [PREUVE] : le modèle ne lit que la conversation courante ; `conversationDigests()` ne sert qu'à la liste d'historique. La mémoire durable = `CoachProfile` (« Ce que le Coach doit savoir sur toi ») + Consignes.
**Proposition** [PROPOSITION] : résumé persistant par conversation clôturée injecté en tête de fiche (façon « My Memory » de WHOOP AI, §3) - ou plus simple : encourager la bascule des faits durables vers `CoachProfile` automatiquement avec validation. [CHOIX] : forme et consentement (contenu potentiellement sensible).

### 2.10 Notifications contextuelles entraînement × nutrition - piste à définir
**Demande (vocal du 2 nov.)** : rappels croisant séance prévue/réalisée et absence de repas dans le journal (ex. « séance bientôt et rien noté », « après la séance si rien mangé »). Mohamed demande un avis, pas une règle figée.
**Avis** [PROPOSITION] : utile **si** la formulation reste honnête - « aucun repas enregistré » ≠ « n'a pas mangé ». Exemples de formulation à valider : avant séance « Ta séance approche - pense à noter ce que tu as mangé » ; après séance « Séance terminée - tu as noté un repas depuis ? ». **Ne jamais affirmer** un déficit (protéines ou autre) depuis un journal incomplet. Avant tout message chiffré (fenêtre, quantités), vérifier les recommandations nutritionnelles auprès de sources fiables - ne pas inventer de fenêtre obligatoire.
**Conditions proposées à valider** [CHOIX] : déclencheurs, fréquence (au plus 1/jour, dédup comme `StrainTargetNotifier`), activation (opt-in, OFF par défaut, réglage dédié), plage horaire.
**Limites réelles à connaître avant de promettre quoi que ce soit** [PREUVE] :
1. **Pas d'heure de séance dans le modèle** : `TrainingWeekPlan` = jour → programme, **sans horaire**. « Séance bientôt » n'a donc pas d'heure de déclenchement ; il faut soit une heure par défaut configurable, soit un déclencheur « jour de séance » à heure fixe [CHOIX].
2. **Une notification locale planifiée ne re-vérifie pas ses conditions** : `UNCalendarNotificationTrigger` se déclenche à l'heure prévue même si un repas a été enregistré entre-temps (depuis n'importe quel écran) ou si le planning a changé. Il faut **annuler/replanifier** les notifications en attente à chaque événement pertinent (repas ajouté, séance terminée, planning modifié - un point de publication comparable existe côté widgets : `DayWidgetsSnapshot.publishDayWidgets`, `StrandiOS/Widgets/DayWidgetsPublish.swift` 17) et à chaque retour au premier plan, sinon le rappel arrive sur un état périmé.
3. **Permission** : flux d'autorisation `UNUserNotificationCenter` à prévoir (demande au moment de l'opt-in, état refusé géré dans Réglages).
4. Une notification **locale** fonctionne sans réseau ; une notification **à texte généré par IA** reste best-effort en sideload (même limite que `CoachBriefScheduler`).
**Implémentation pressentie** : policy pure testable (modèle `StrainTargetPolicy`) évaluée aux événements ci-dessus + notification locale planifiée/annulée en conséquence.
**Réutiliser** : `StrainTargetNotifier` (dédup), `WindDownNudge` (opt-in), `MealJournal`, `TrainingWeekPlan`.

### 2.10 bis Laboratoire de santé : import PDF d'un bilan par le Coach + lien Nutrition
**Demande (vocal du 2 nov.)** : pouvoir donner un PDF de bilan d'analyses au Coach ; il en extrait les résultats, les présente pour validation, puis remplit le Laboratoire de santé - nouvelles valeurs ajoutées, anciennes préservées, sans doublons. Et relier Laboratoire ↔ Nutrition.

**Ce qui existe déjà** [PREUVE] : tout le socle du Carnet de laboratoire (§1.12) : table `labMarker` + upsert à clé naturelle (dédoublonnage limité à la même source et au même horodatage - voir §1.12), catalogue non-diagnostique, saisie manuelle, imports CSV/WHOOP, projection `metricSeries` « lab-book », lecture Coach `get_lab_book` sous 2e opt-in. **Manquent** : l'entrée PDF (le Coach n'envoie que des JPEG à Anthropic - §1.12) et tout lien avec la Nutrition.

**Proposition A - import PDF via le Coach** [PROPOSITION], sur le gabarit des cartes existantes (§1.4 : proposition → aperçu → validation → écriture) :
1. **Entrée fichier** : étendre le composeur du Coach pour joindre un PDF à côté des photos (`CoachView.attachPicked`, ≈1074, aujourd'hui `PhotosPicker` images seules ; le sélecteur de documents existe déjà pour le CSV du Lab Book - `LabBookView` ≈96). Côté fournisseur : route candidate = blocs document PDF de l'API Anthropic - **capacité non vérifiée ici** : existence, bornes (taille, pages) et format exact à confirmer contre la documentation officielle avant tout codage ; point d'extension : `AnthropicTools` (≈132, blocs image aujourd'hui). Anthropic seul, conforme à la décision.
2. **Extraction bornée** : nouveau `CoachLabImportProposal` (gabarit `CoachMealProposal`) : le modèle renvoie une liste structurée (marqueur, valeur, unité, date du prélèvement, plage imprimée sur le compte rendu) ; rien n'est écrit par l'appel d'outil. Règles reprises de l'existant : unités **verbatim, jamais converties** ; marqueurs reconnus mappés sur `MarkerCatalog`, sinon `custom_<slug>` (même logique que `LabMarkerCsvImport`) ; « 120/80 » scindé systolique/diastolique ; la plage de référence va dans `referenceText` (recopiée, jamais inventée).
3. **Validation** : carte d'aperçu listant chaque valeur extraite (marqueur, valeur, unité, date) avec correction possible avant « Ajouter au Carnet de laboratoire » - **aucune écriture sans validation**, calqué sur `log_meal`.
4. **Écriture** : `LabMarkerStore.upsertLabMarkers` avec une provenance dédiée (ex. source « pdf-coach »). Portée exacte du store [PREUVE] : la clé naturelle (deviceId, markerKey, takenAt, source) ne dédoublonne **que** le même relevé réimporté depuis la même source avec le même horodatage - et dans ce cas la valeur existante est **remplacée** (`DO UPDATE`), pas conservée. Un même prélèvement saisi à la main puis extrait d'un PDF, ou extrait avec une heure différente, produit un **doublon**. Le chantier doit donc ajouter, sans rien écrire de silencieux : normalisation de la date du prélèvement (un bilan donne souvent un jour sans heure - politique à définir, ex. midi local comme l'import CSV via `LabBookFormat.noonEpoch`, `LabBookView` ≈263) ; **détection des doublons inter-sources** (même marqueur, même jour, valeur proche → fusion ou remplacement proposé dans l'aperçu, jamais automatique) ; **aperçu des remplacements** avant tout écrasement d'une valeur existante. Unités verbatim, **jamais de conversion implicite** (règle existante de `LabMarkerCsvImport`).
**Garde-fous à écrire dans le rôle** : extraction verbatim, jamais d'interprétation (« ces valeurs sont extraites de ton document, pas lues médicalement ») ; en cas de doute sur une ligne, la marquer « à vérifier » plutôt que deviner ; rappeler l'avertissement non-médical existant.
**Vérifications** : tests d'extraction sur PDF factices (tableaux multi-colonnes, unités variées, dates), tests de dédoublonnage (réimport du même bilan = même nombre de lignes), [À TESTER] parcours complet sur iPhone avec un vrai PDF.

**Proposition B - lien Laboratoire ↔ Nutrition** [PROPOSITION] : **lecture croisée prudente** - éclairer les conseils nutrition du Coach, jamais modifier automatiquement les objectifs ni diagnostiquer :
1. **Côté Coach** (léger, réutilise l'existant) : quand le 2e opt-in est actif, le Coach peut déjà lire le Lab Book (`get_lab_book`) pendant une conversation nutrition ; ajouter dans le rôle (`coach-instructions.md`) la consigne explicite : il peut tenir compte des valeurs déclarées du Lab Book dans ses réponses nutrition (ex. ferritine, vitamine D), sans jamais conclure à une carence ni changer les objectifs. Aucune donnée nouvelle, aucun nouvel envoi : le 2e opt-in couvre déjà cette lecture.
2. **Côté écran** (optionnel) : dans `NutritionView`, une ligne discrète « dernière valeur » pour 2–3 marqueurs choisis par l'utilisateur (ex. vitamine D), lien vers le détail du Lab Book. [CHOIX] : affichage et marqueurs concernés.
3. **Croisement dans Analyses** (ultérieur, dépend de §2.6 bis) : les séries « lab-book » sont dans `metricSeries` mais **pas listées par `MetricExplorerView`** [PREUVE] ; et les repas internes n'alimentent pas `metricSeries`. Les deux manques doivent être levés avant tout croisement labo × nutrition dans Explorer/Comparer.
**À ne pas faire** : modification automatique des objectifs nutritionnels depuis un bilan ; verdict « normal/anormal » ; corrélation présentée comme cause (le code actuel dit déjà « association, not cause »).

**Incohérence de consentement à corriger dans ce chantier** [PREUVE] : la ligne « Tendances et Carnet de laboratoire » de `CoachDataView` (≈142) promet « Un résumé seulement, jamais les mesures » - or le roll-up de la fiche (`onDeviceSignalsBlock`, ≈1736) envoie déjà la **dernière valeur** de chaque marqueur, et `get_lab_book` envoie jusqu'à 5 valeurs par marqueur. Le libellé de consentement doit être aligné sur ce qui part réellement **avant** d'ajouter l'envoi d'un PDF de bilan (donnée de santé complète, pas seulement des valeurs).

**[CHOIX] déterminant pour Mohamed** : le spec amont (phase 4, §217 du spec health-records) prévoit l'OCR de PDF **strictement sur appareil, jamais de cloud**. L'import via le Coach enverrait le **document complet** à Anthropic. Aucun consentement existant ne couvre ce flux : les opt-in actuels visent les métriques et des photos de repas, pas un bilan de santé entier (qui contient aussi identité, dates, laboratoire, médecin prescripteur). Il faut donc un **consentement spécifique** : libellé clair sur ce qui part (document entier, identifiants inclus), minimisation (n'envoyer que les pages utiles si possible), rappel de l'avertissement non-médical. La voie fidèle au spec - extraction sur appareil (Vision), sans envoi - reste une option distincte à part entière. À trancher.

### 2.11 Matrice de couverture de l'audit
| Zone | État de la revue | Détail vérifié |
|---|---|---|
| Nutrition - écran jour, objectifs, saisie (éditeur, dictée/photo, code-barres) | vérifié sans écart identifié | §1.9 ; manques listés en §2.6 (repas prévus) |
| Nutrition - graphiques semaine/mois | absence confirmée, fiche de correction ajoutée | `NutritionView.swift` = jour seul, aucune vue d'historique ; proposition complète en §2.6 bis |
| Nutrition - Analyses vs journal interne | écart identifié | Analyses (Explorer/Insights) ne lit que `metricSeries` ; les repas internes (tables `meal`/`mealItem`) n'y alimentent rien → aucune métrique nutritionnelle du journal interne dans Analyses ; seule la source « nutrition-csv » (import présent mais masqué dans le fork) écrirait ces clés. `BehaviorInsights` lit les habitudes du Journal (interne + WHOOP importé via `JournalCatalog`), pas les repas (§2.6 bis) |
| Laboratoire de santé (Carnet de laboratoire) | socle vérifié, manques identifiés | §1.12 (table, store, catalogue, imports CSV/WHOOP, projection, écran, outil Coach) ; manques : entrée PDF/photo, exposition dans Metric Explorer, lien Nutrition (§2.10 bis) ; incohérence de libellé de consentement signalée (§2.10 bis) |
| Hydratation / caféine | écart identifié | trackers opt-in existants mais non lus par le Coach (§2.8) |
| Sommeil (SleepView, SleepPhasesCard, SleepPhasesChart) | vérifié sans écart identifié | couleurs `sleepStageColor` (4 teintes distinctes, rampes Ribbon/Garmin au choix), courbe FC `liquidHeart`, mouvement `restColor` ; siestes/édition/suppression avec annulation (§1.7) |
| Jauges d'Aujourd'hui (TodayHeroCard) | vérifié sans écart identifié | `caloriesActivity`/`caloriesResting` sur les demi-jauges (200–228), anneaux charge/effort via jetons `Palette` |
| Stress (StressView) | vérifié sans écart identifié | gradient 3 ancres bleu→vert→ambre (`StressRamp`, 786–792), score Baevsky |
| Analyses (MetricExplorerView / CompareView / IntelligenceView / InsightsHubView) | vérifié sans écart identifié | `BehaviorInsights` (« Ce qui vous fait bouger ») lit le catalogue du journal (interne + importé) ; Explorer lit `metricSeries` |
| Navigation et réglages (RootTabView, MoreHub, SettingsView) | revue structurelle seulement | routage et groupes revus au niveau structurel ; pas d'écart identifié à ce niveau ; l'audit visuel complet relève du chantier 7 (refonte) |

---

## 3. Benchmark d'apps spécialisées (sources citées, consultées le 2 nov. 2026)

> Capacités rapportées par les sources officielles ci-dessous ; non re-testées sur appareil. Une case sans écart indiqué ne conclut **pas** à l'absence d'écart : ces pages marketing ne permettent pas une comparaison exhaustive. Tri « nécessaire / secondaire » = proposition d'audit au service de la cible de Mohamed (une app simple pour sportif attentif à son alimentation ou personne surveillant ligne/sport), à valider.

| App (source) | Ce qu'elle fait de marquant | Ce que NOOP a déjà | Écart utile |
|---|---|---|---|
| **Foodvisor** ([foodvisor.io](https://www.foodvisor.io/en/guides/article/best-calorie-counter-apps-why-foodvisor-stands-out/)) | Photo AI de repas, code-barres, plan nutrition personnalisé, chat avec diététiciens, recettes, suivi poids/**eau**/pas/activités, Apple Santé | Photo repas (Coach), dictée, code-barres (OFF + étiquette), journal, objectifs calculés, Apple Santé (calories) | Plan de repas/menu (§2.6), eau/caféine visibles pour le Coach (§2.8), historique poids exploité (§2.7) |
| **Cal AI** ([calai.app](https://www.calai.app/)) | Photo → calories (volume estimé, capteur de profondeur), code-barres, description texte ; revendique ~80 % de précision (sa propre FAQ) | Photo + dictée avec « quantités estimées » affichées | Recouvrement des fonctions listées, comparaison non exhaustive ; leçon : toujours marquer l'estimation (déjà fait) |
| **MyFitnessPal** ([support.myfitnesspal.com](https://support.myfitnesspal.com/hc/en-us/articles/360032622391-How-to-set-up-logging-reminders)) | Rappels de saisie par repas (« si je n'ai pas enregistré » à une heure choisie) | Carte rappel Journal (in-app) | Rappels repas - couvert par la piste §2.10 en version contextuelle |
| **Fitbod** ([help.fitbod.me](https://help.fitbod.me/hc/en-us/articles/360006269014-Muscle-Recovery)) | Carte de **récupération par muscle** (avatar face/dos, % fraîcheur), séances générées selon muscles frais, ajustement manuel | Silhouette (`LiftBodyMap`), statuts par exercice, « À prioriser », semaine planifiée | Fraîcheur par muscle → peut enrichir les statuts et la silhouette (secondaire) |
| **Hevy** ([hevyapp.com](https://www.hevyapp.com/features/)) | Journal de séance simple, minuteur de repos, types de séries, valeurs précédentes, graphiques par muscle, **mesures corporelles + photos**, streaks, social | Carnet + supersets, minuteur/bannière, Progression (graphiques par muscle), planification | Mesures corporelles/photos (secondaire) ; social (hors cible) |
| **Athlytic** ([athlyticapp.com](https://athlyticapp.com/)) | Score de récupération → zone d'effort cible du jour, suivi en direct au poignet | Charge/Effort, bande cible 12–14, `StrainTargetNotifier`, bannière FC live | Recouvrement partiel - non comparé en profondeur |
| **Bevel** ([help.bevel.health](https://help.bevel.health/en/articles/11583937)) | **Tout-en-un** : récupération, sommeil, strain, stress, nutrition, muscu, journal + « Bevel Intelligence » (check-ins quotidiens, nutrition & meal planning, plans d'entraînement) | Tous les domaines séparément ; Coach conversationnel | **Référence la plus proche de la cible** ; écart : planification repas + check-ins proactifs (§2.6, §2.10, brief du jour existant) |
| **WHOOP AI** ([whoop.com](https://www.whoop.com/us/en/thelocker/new-ai-guidance-from-whoop/)) | Coach conversationnel sur données 24/7 + **My Memory** ; **conversations proactives par notification** (« quand rien ne le justifie, WHOOP se tait ») ; Daily Outlook matinal | Coach (même données du bracelet), `CoachProfile`, `CoachBriefScheduler` (brief quotidien opt-in) | Mémoire inter-conversations (§2.9), proactivité prudente (§2.10) |
| **Oura Advisor** ([support.ouraring.com](https://support.ouraring.com/hc/en-us/articles/39512345699219-Oura-Advisor)) | Chat LLM sur les données, fils de conversation | Le Coach couvre le chat sur données ; les fils de conversation ne sont pas comparés en détail | - |
| **Sleep Cycle** ([support.sleepcycle.com](https://support.sleepcycle.com/hc/en-us/articles/7858323091356-What-is-the-Smart-Alarm-Clock)) | Réveil intelligent en phase légère (fenêtre 10–30 min) | Alarmes du bracelet (upstream) | Secondaire, hors demande |

**Tri proposé** [PROPOSITION] :
- **Nécessaires** (au cœur de la demande) : §2.2 (FC jour pour le Coach), §2.5 (cartes Sieste / Correction séance / Correction séries), §2.6 (repas prévus = le « menu » façon Foodvisor/Bevel), §2.6 bis (historique semaine/mois nutrition), §2.10 (rappels contextuels), §2.10 bis (import PDF du bilan + lien Nutrition), §2.1 (couleurs FC, avec le chantier 7).
- **Secondaires** : §2.7 (poids : exposer la série Apple Santé au Coach), §2.8 (eau/caféine : rendre les trackers existants lisibles par le Coach), fraîcheur par muscle (Fitbod), mesures/photos (Hevy).
- **À ne pas copier** : coaching humain 1:1 (Foodvisor), social (Hevy), vidéos d'entraînement - hors cible « une seule app simple » et hors périmètre offline du fork.

---

## 4. Ordre de chantiers proposé [PROPOSITION]
1. **Lecture d'abord** : §2.2 (FC jour), §2.7 (poids via Apple Santé si dispo) et §2.8 (eau/caféine) - exposer l'existant au Coach, sans écriture, risque faible.
2. **Actions du Coach** : §2.5 (Sieste, Correction séance, Correction séries) puis §2.10 bis A (import PDF du bilan) - cartes à validation + annulation ; le PDF suppose le [CHOIX] cloud/on-device tranché, un consentement spécifique et le libellé de l'opt-in corrigé.
3. **Nutrition** : §2.6 bis (historique semaine/mois), §2.6 (repas prévus) puis §2.10 (rappels contextuels) - le rappel dépend du journal et du planning, déjà en place.
4. **Planning** : §2.3 (multi-séances + cardio) - touche un modèle lu par 5 consommateurs ; à faire seul.
5. **Cohérence graphique** : §2.1 et §2.4 - à synchroniser avec le chantier 7 (refonte) pour ne pas refaire deux fois.

## 5. Recommandations techniques et choix produit

### 5.1 Recommandations techniques (pour Claude Code - re-validables au code)
1. **Repas prévus** : statut `planned` **orthogonal** à `origin` (provenance) - nouveau champ, pas une valeur d'`origin` (§2.6).
2. **Annulation des actions du Coach** : réutiliser le snapshot d'annulation de `Repository.deleteSleepSession` comme gabarit pour toute carte d'écriture (§2.5).
3. **Planning** : migration documentée de la clé `training.weekPlan.v1` vers un modèle v2 (liste typée), avec les 5 consommateurs listés (§2.3).
4. **Exposition de données existantes au Coach** : FC jour (`HRBucket` via le lecteur de `dayChart`), poids (`metricSeries` source `apple-health`), eau (`metricSeries` « hydration »), caféine (`CaffeineLog`) - réutiliser les lecteurs des écrans, aucune collecte nouvelle, même consentement (§2.2, §2.7, §2.8).
5. **Notifications contextuelles** : policy pure testable + annulation/replanification des notifications en attente à chaque événement (repas, séance, planning) et au premier plan ; permission demandée à l'opt-in (§2.10).
6. **Import PDF du bilan** : carte `CoachLabImportProposal` sur le gabarit `CoachMealProposal` ; écriture via `upsertLabMarkers` (dédoublonnage seulement à clé naturelle identique - ajouter normalisation de date, détection inter-sources et aperçu avant remplacement, §2.10 bis), source dédiée « pdf-coach », unités verbatim, mapping `MarkerCatalog`/`custom_<slug>` repris de `LabMarkerCsvImport` ; corriger le libellé du 2e opt-in (`CoachDataView` ≈142) pour refléter l'envoi réel des valeurs (§2.10 bis).

### 5.2 Choix produit à valider par Mohamed [CHOIX]
1. Formulations, déclencheurs, fréquence, plage et opt-in des rappels (§2.10) - **formulations à valider avant codage**.
2. Hydratation/caféine : activation par défaut ou mise en avant des trackers existants ; compteur d'eau plus visible ; place dans le brief (§2.8).
3. Poids : saisie manuelle (migration + parité) vs Apple Santé seulement ; écran d'historique dédié vs Metric Explorer (§2.7).
4. Mémoire entre conversations : résumé injecté vs bascule vers `CoachProfile` ; consentement pour un contenu potentiellement sensible (§2.9).
5. Couleur cible des courbes FC - via les maquettes du chantier 7 (§2.1).
6. Planning multi-séances/cardio : présentation dans `TrainingPlanSheet` et contenu du bloc WEEK PLAN de la fiche (§2.3 - les questions de modèle et de migration sont techniques, §5.1).
7. Annulation des actions du Coach : carte en conversation vs feuille native pré-remplie (§2.5).
8. Repas prévus : affichage dans le journal, le widget et la fiche (§2.6 - la migration `meal` est technique, §5.1).
9. **Import PDF du bilan : extraction par le Coach (PDF envoyé à Anthropic) vs extraction sur appareil (Vision), fidèle au spec amont** ; libellé du consentement associé (§2.10 bis).
10. **Lien Labo ↔ Nutrition** : forme de la lecture croisée (consigne Coach seule vs affichage dans NutritionView), marqueurs concernés (§2.10 bis).

## 6. Consignes pour une future session de code (à appliquer quand Mohamed lance un chantier - pas une autorisation actuelle)
- **Tests** : ajouter/étendre dans `StrandTests/` (modèles : `CoachToolsTests`, `TrainingPlanTests`, `TodayVitalsTests`) ; rendus PNG sur branche `render/<nom>` pour toute vue.
- **i18n** : 10 langues dans `Strand/Resources/Localizable.xcstrings` ; `python3 Tools/i18n_audit.py --ci origin/main` (pièges consignés dans la feuille de route).
- **Parité** : toute donnée stockée nouvelle → migration GRDB **et** Room + `schema_oracle.json` (2 copies) ; sinon disposition `platform_specific` + `parity_ledger.py --refresh-derived`.
- **Avant de pousser** : `i18n_audit`, `doc_comment_lint`, `python3 -m unittest discover -q` depuis `Tools/`, suite de parité si `Packages/` touché ; Swift non compilable en session → PR pour CI (`app-build.yml`).
- **IPA** : regrouper, `build/<nom>` depuis `main`, seulement quand Mohamed le dit.
- **[À TESTER] sur iPhone** : toute la chaîne de bout en bout (cartes, annulation, notifications, couleurs, import PDF) - non reproductible en CI.

## 7. Limites de cet audit
- Lecture statique du code à 55a249b1 ; **aucune exécution** sur appareil. Les comportements dynamiques (franchi de seuil réel, timing des notifications, précision photo, extraction PDF) restent à valider sur iPhone.
- Capacités concurrentes : rapportées depuis leurs sources officielles (liens §3), non re-testées ; les chiffres marketing (ex. « ~80 % » de Cal AI) sont ceux de l'éditeur.
- Les fiches `docs/fork/` reflètent la documentation du projet (contexte, pas validation des choix ouverts ici) ; ce dossier n'en modifie aucune.
- Matrice §2.11 : « vérifié sans écart identifié » = lecture ciblée du code sans anomalie trouvée, pas preuve d'absence de défaut ; « revue structurelle seulement » (navigation/réglages) = pas d'audit exhaustif à ce stade.
- La voie « blocs document PDF » de l'API Anthropic est une route candidate **non vérifiée** : capacité, bornes (taille, pages) et format exact à confirmer contre la documentation officielle avant tout codage (§2.10 bis).

### Passe de confirmation v4 (2 nov., ~22:15) - corrections apportées
Tous les constats et localisateurs du dossier ont été relus dans le code à 55a249b1 (HEAD revérifié inchangé). Confirmés sans changement : chaîne Coach (§1.1), fiche (§1.2), outils et bornes (§1.3), actions (§1.4, borne `mealTime`), alerte FC et conditions (§1.5), planning (§1.6), siestes/séances (§1.7–1.8), nutrition (§1.9, v51/43, clés AppStorage, carte CSV masquée), notifiers (§1.10), poids Apple Santé et absence dans `DailyMetric` (§1.11), conclusions §2.6 bis/§2.7/§2.8 (repas internes hors Analyses, poids et eau/caféine non lus par le Coach). Corrections :
1. `ficheInputs()` : 1526 (était 1528).
2. §1.2 : les blocs `recentWorkoutsBlock`/`stressIndexLine`/`trainingWeekPlanBlock`/`napsBlock` sont dans `AICoach.swift` (pas `CoachFiche.swift`) ; `sleepSynthesisFigures` = extension `Repository` dans `LiveHRBannerFigures.swift`.
3. §1.5/§2.1 : `metricRose` **dépend du thème** - rouge en Classic, **orange en Titanium (défaut)** ; « deux rouges coexistants » n'est exact qu'en Classic. Le constat d'incohérence est maintenu, formulation corrigée.
4. §1.7 : « Ajouter une sieste » = bouton ≈684 / feuille ≈302 (était #508) ; annulation ≈130–174 (était #160).
5. §1.8 : la feuille valide via `buildManualRowFromSpan` (384) ; `buildManualRow` (413) existe aussi.
6. §1.9 : `estimateMeal` vit dans `AICoachMealEstimate.swift` (65) ; caféine : `defaultHalfLifeHours = 5.5` (25) à la place d'un renvoi de ligne erroné.
7. §1.11 : `ProfileStore` localisé (`Profile.swift` 9) ; précision sur les homonymes `weightKg` (`appleDaily` vs `liftSet`).
8. §2.6 bis : `exploreSeries` = 2458 (commentaire sources ≈2447–2456).
9. §2.10 : `publishDayWidgets` localisé (`StrandiOS/Widgets/DayWidgetsPublish.swift` 17).
10. Ajouts : §1.12 (cartographie Lab Book) et §2.10 bis (PDF + lien Nutrition), dont l'incohérence du libellé de consentement du 2e opt-in.
11. v4.1 : suppression des garanties absolues sur l'upsert `labMarker` (« jamais de doublon », « historique intact ») - la clé naturelle inclut `source` et `takenAt` : dédoublonnage seulement à clé identique, avec **remplacement** de la valeur ; doublons inter-sources possibles ; ajout des garde-fous d'écriture (normalisation de date, détection inter-sources, aperçu avant remplacement, unités jamais converties). Consentement PDF requalifié : spécifique requis, les opt-in existants ne le couvrent pas ; capacité PDF de l'API Anthropic marquée route candidate non vérifiée.
