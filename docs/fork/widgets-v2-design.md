# Widgets v2 — fiche du chantier (5 nov. 2026)

**État** : maquette **validée le 5 nov.** (« Go ») ; code en PR (`feat/widgets-v2`). L'IPA du chantier 9 partira de `main` avec ces widgets.

## Maquette
Canvas « NOOP – Widgets v2 » — https://claude.ai/artifact/675CLLFJ77Y4qPen5TmxMc. Taille moyenne (338 × 158 pt), valeurs d'exemple, style F (fond #1C1C1E, rayon 22, SF Pro, chiffres arrondis), couleurs des jetons de l'app (sombre).
Artboards : 1 Aujourd'hui · anneaux · 2 Fréquence cardiaque · 3 Stress · 4 Sommeil · 5 Séance du jour (muscu + cardio) · 5b cardio seul · 5c muscu faite · 5d jour de repos · 6 Nutrition (refait).

## Problème (Mohamed, 5 nov.)
On doit comprendre un widget au premier coup d'œil. Aujourd'hui : Séance du jour illisible (blocs A1/B1, points de la semaine) ; Sommeil = couleurs empilées sans légende ; FC sans les seuils de l'app ; anneaux = l'ancien trio Charge / Effort / Rest ; textes en anglais (FC, Stress, anneaux).

## Choix de Mohamed (5 nov.)
- Widgets utilisés (moyens) : anneaux, FC, Stress, Sommeil, Séance du jour. **Nutrition refait** dans le même style.
- **Brief du Coach retiré** de la galerie (libère une place : `NOOPWidgetBundle` était à 10, la limite).
- FC : **rouge** au-dessus du seuil haut (comme la carte FC d'Aujourd'hui), vert sous le seuil bas, seuils en pointillés.
- Séance du jour : le bouton **Démarrer lance la séance** (programme pour la muscu, séance en direct du sport pour le cardio).

## Propositions de la maquette
- **Anneaux** = la carte d'Aujourd'hui : 4 anneaux concentriques (Activité orange, Charge teinte selon le score, Effort bleu avec la bande cible, Repos violet) + 4 lignes (Activité 420 / 600 kcal, Charge 19 · basse, Effort 3,9 · cible 8–14, Repos 76 · nuit 5 h 11 min). FC / VFC / batterie retirées.
- **FC** : titre rose « Fréquence cardiaque », « 3 dernières heures », bpm + âge de la mesure, Min · Moy. · Max ; courbe rose, rouge au-dessus du seuil haut (habituel + 20, suit l'heure), verte sous le seuil bas (plus bas éveillé), étiquettes « haut 114 » / « bas 68 ». Seuils calculés par l'app à la publication (`TodayHRAlert.thresholds`, `HabitualHR`).
- **Stress** = la carte d'Aujourd'hui : niveau en mots (Calme / Modéré / Élevé) + « 2,9 sur 3 · cette heure », bandes colorées nommées, heures en mouvement grisées, 06:00–22:00, Élevé (durée) · Moy. · Pic.
- **Sommeil** : durée, coucher → réveil, dette, coucher conseillé ; **hypnogramme en 4 lignes** (Éveillé, Paradoxal, Léger, Profond) + légende avec la durée de chaque phase.
- **Séance du jour** : la séance (nom, « Muscu · 4 blocs · ≈ 55 min », Démarrer blanc) et le cardio (sport, « Cardio · 30 min », Démarrer rose) ; « Cette semaine · 0 / 2 séances faites » ; faite = coche bleue « Faite · 52 min » ; repos = « Jour de repos · Prochaine : … ». Plus de blocs A1/B1 ni de points de la semaine.
- **Nutrition** : anneau vert des kcal mangées / objectif, 3 barres Protéines (violet) / Glucides (jaune) / Lipides (cyan), Reste · Dépensé · Bilan.
- Tout en français (mise en mots côté app, comme les widgets du jour).

## Écarts avec la maquette (code)
- Charge : pas de mot « basse » sous le chiffre (Today n'en affiche pas ; une seule lecture de la Charge).
- Sommeil : « dette 2 h 8 min » / « Coucher conseillé 00:03 » reprennent les phrases déjà traduites du widget.
- Séance cardio : « Objectif : 30 min » (le libellé de la feuille Démarrer) au lieu de « Cardio · 30 min » ; muscu : la ligne de la Synthèse (« 3 supersets + 1 exercice · ≈ 55 min »), sans « Muscu · ».
- Jour de repos : « Repos » + « Prochaine : Full body B · lundi » (sinon « jour de repos du planning »).
- Les petites tailles (Séance, Nutrition, Sommeil) et l'anneau/la ligne de l'écran verrouillé ne changent pas.

## Ce qui est codé (PR `feat/widgets-v2`)
- **Snapshot** `DayWidgetsSnapshot` (clé `noop.widget.day`) : + `rings`, `heart`, `stress`, `words` (mots par texte anglais, `word(_:)`) ; Séance + `rows` (`SessionRow` : lift | cardio | rest, nom, détail, fait, lien Démarrer), `dayLine`, `weekDone` ; Nutrition + `left` / `spent` / `net` ; Sommeil + `stages` (`StageTotal`). Tout optionnel (ancien JSON lisible). `changedWidgetKinds` recharge aussi `NOOPWidget`, `HeartRateWidget`, `StressWidget`.
- **Mise en mots** (`DayWidgetsContent`, extension « Widgets v2 ») : `widgetSessionRows` (les éléments du jour du planning par `buildTrainingDays`, au plus 2 ; sinon la séance du résolveur), `liftDetail`, `nextPlannedLine`, `weekDoneLine` (`sessionTally`), `nutritionFigures` (règles de `NutritionView.figuresLine`), `stageTotals`, `ringsSection`, `heartSection` (par tranche de 5 min, `TodayHRAlert.thresholds`), `stressSection` (`TodayStressLogic.model`), `widgetWords`, `widgetDayLine`.
- **Un seul calcul avec Aujourd'hui** : `TodayHeroFigures.heroEffortTarget` / `heroEffortCaption` (bande Effort, lus par `LiquidTodayView` et le widget) ; objectif d'activité par défaut mémorisé par Aujourd'hui (`rememberActivityGoalDefault`, par jour) ; sans lui, le widget montre « kcal » sans objectif (comme Aujourd'hui sans objectif). Activité = `NutritionDayReader.spentOnDay` (jour calendaire, comme Nutrition).
- **Publication** : seuils FC lus une fois par jour (`DayWidgetsHeartMemo` : profil habituel 14 j + plancher éveillé ; sommeil relu à chaque fois) ; stress par `StressDayCurve.today` (mémo, pas de relecture) ; `WidgetSnapshot.publish` force la publication du jour quand Charge / Effort / Repos / courbe de stress changent.
- **Vues** `StrandiOSShared/DayWidgetV2Views.swift` (ajoutée à la cible macOS dans `project.yml`) : `DayRingsWidgetFace`, `DayHeartWidgetFace` (courbe rose, rouge au-dessus du haut, verte sous le bas, pas de couleur pendant le sommeil, seuils en pointillés, « haut / bas » à droite), `DayStressWidgetFace`, `DaySessionWidgetFaceV2`, `DayNutritionWidgetFaceV2`, `DaySleepWidgetFaceV2` (hypnogramme 4 lignes), `DayWidgetTitle`.
- **Extension** : moyen → nouvelles vues ; FC et Stress lisent aussi le snapshot du jour (Stress : ancien dessin tant que l'app n'a pas publié) ; **Brief du Coach retiré** de `NOOPWidgetBundle` (9 widgets).
- **Démarrer** : `noop://widget/start?program=<id>&name=<nom>` / `?sport=<sport>` (`DayWidgetsSnapshot.Start`) → `NavRouter.widgetStart` → `RootTabView.startFromWidget` (onglet Entraînement, feuilles fermées, puis `beginProgramSession` ou `TrainingCardioLauncher`).
- 4 clés (10 langues) : « Last 3 hours », « this hour », « Next: %@ », « %lld / %lld sessions done ».
- Tests : `DayWidgetsTests` (+6), rendu `widgets-4-v2`, `widgets-5-v2-seance`.

## À tester sur le téléphone
- Les 6 widgets moyens : mêmes valeurs qu'Aujourd'hui (anneaux, bande Effort, objectif d'activité après avoir ouvert Aujourd'hui), carte FC (seuils, rouge / vert), carte Stress (niveau, « cette heure »), Nutrition (Reste / Dépensé / Bilan), Sommeil (durées des phases = Sommeil).
- Séance : Démarrer muscu → la séance du programme s'ouvre ; Démarrer cardio → la séance en direct du sport ; app fermée puis ouverte par le bouton.
- Brief du Coach absent de la galerie (un widget déjà posé disparaît).

## CI (5 nov.)
- 4c5b936 : macOS + StrandTests verts (rendus `widgets-4-v2`, `widgets-5-v2-seance` compris) ; build iOS annulé (runner arm64 non attribué) ; publication du rendu en conflit avec le run précédent (`ReleaseAsset.name already exists`), relancée par ce commit.
- Piège : `StrandDesign.SleepStage` ne compile pas (le module contient un `enum StrandDesign`) ; écrire `SleepStage`.
