# Chantier 13 — Esthétique « Instrument » (fiche du chantier, 6 nov. 2026)

**ABANDONNÉ (6 nov., ~21:05 UTC)** : après l'IPA `build/today-hud`, Mohamed est revenu à l'IPA précédente et **ne veut plus ce design**. Le code du HUD (#103) est **retiré de `main`** par un commit d'annulation (pas de réécriture d'historique) : `main` a de nouveau le code de 7ae38ad (Aujourd'hui « Fitness + Santé » d'avant). Cette fiche reste comme historique : diagnostic, maquettes (https://claude.ai/artifact/BxtF7aKChTqp1kGGvKpaEr), choix et journal du code. Pour le reprendre un jour : annuler le commit d'annulation (revert du revert) sur une branche depuis `main`.

**État (6 nov., soir)** : B jugée trop sage par Mohamed → 3 pistes futuristes → **piste 1 « HUD holographique » retenue**, maquette complète à valider ; maquette : https://claude.ai/artifact/BxtF7aKChTqp1kGGvKpaEr (6 planches : sombre, clair, petit iPhone 375 pt, interaction, calibration, sans données). Le code ne commence qu'après la validation de la maquette. Les autres écrans ne prennent le style qu'après la validation du pilote sur le téléphone.

## Retour sur la maquette B (6 nov., soir)
- Mohamed : « pas du tout ce que j'attendais » ; il veut **quelque chose de futuriste comme dans les films, high tech**. La proposition B (sobre) est mise de côté, gardée sur la page « Proposition B (v1) » du canevas.
- Trois pistes v2 sur la page « Futuriste (v2) » du même canevas : **1 · HUD holographique** (4 anneaux concentriques numérotés 01–04 dans un réticule gradué, panneaux à coins coupés, chrome cyan, libellés SF Mono capitales), **2 · Cockpit** (cadran segmenté de la Charge + 3 petits cadrans, télémétrie en barres segmentées, histogramme FC par quart d'heure, accent ambre), **3 · Projection holographique** (anneaux couchés en perspective au-dessus d'un socle lumineux, valeurs flottantes reliées par des traits). Communs : couleurs des mesures inchangées, lueurs dessinées (traits doublés, dégradés) sans flou, mêmes données qu'aujourd'hui.

## Choix de Mohamed (6 nov., nuit)
- **Piste 1 · HUD holographique** retenue (Cockpit et Projection écartées, gardées sur la page « Pistes v2 écartées »).
- **Séquence de démarrage courte (≈ 1 s) à chaque affichage d'Aujourd'hui** : graduations qui pivotent, anneaux qui balaient de l'extérieur vers le centre, panneaux qui montent, courbe FC qui se trace. Coupée par Réduire les animations (`poseStill`), suit la règle « une fois par affichage » du chantier 12 (`noopEntranceGeneration`).
- **Typographie** : SF Pro (textes), SF Mono capitales espacées (libellés techniques, heures, unités), SF Rounded (chiffres). Pas de police embarquée.
- **Mode clair « plan »** : fond blanc bleuté, chrome bleu ardoise #0B5E86, mêmes couleurs de mesures (variantes claires de `StrandPalette`) ; rose FC des libellés assombri (#C7002F) pour le contraste.
- Maquette de la piste 1 complétée (page « HUD holographique (retenu) ») : sombre avec démarrage rejouable, clair « plan », petit iPhone 375 pt, calibration, sans données (clair et sombre). **À valider avant le code.**

## Demande de Mohamed (6 nov.)
- Évolution vers une esthétique scientifique / science-fiction haut de gamme, qui reste une app de santé lisible et crédible : instrument de recherche personnel, fond sombre profond, surfaces sobres, contours fins ponctuels, espace généreux. Touche holographique seulement sur une sélection ou une interaction. Pas de grille hexagonale, de scanlines, de décor spatial ni de halos partout.
- SF Pro pour la lecture, SF Rounded à chiffres tabulaires pour les mesures, monospacé seulement pour les heures, unités et annotations techniques.
- **Écran pilote : Aujourd'hui sur iPhone.** Android et Mac hors périmètre (les fichiers partagés feront hériter le Mac sans travail dédié).
- Garde-fous : aucune formule, BLE, stockage ni donnée du Coach modifiés ; aucun score inventé ni affirmation médicale ; mode clair, Dynamic Type, VoiceOver, traductions, cibles de 44 pt, Réduire les animations, pas de flou sur les surfaces qui défilent.

## Écarts assumés avec les décisions antérieures
- Chantier 7 (« Fitness + Santé ») : cartes **sans bordure** → la carte des anneaux seule reçoit un contour fin (0,5 pt). Troisième voix typographique (monospacé) pour les annotations. Effet irisé à la sélection.
- Direction « Instrument » (écartée le 2 nov.) : on reprend sa précision (axes, unités, annotations), pas son décor.
- « Néon nuit » (écartée) : seule une lumière limitée à la sélection est reprise.
- Chantier 12 : le **halo permanent** derrière les anneaux (renforcé le 6 nov.) **ne s'allume plus qu'à la fermeture d'un objectif** (choix de Mohamed, 6 nov.).
- Passe de cohérence (5 nov., FC avant Synthèse) : la Synthèse devait repasser avant la FC (choix du 6 nov.), **puis Mohamed est revenu dessus le 6 nov. (nuit) : la FC reste avant la Synthèse**, l'ordre enregistré ne change pas.
- Inchangés : couleurs sémantiques des mesures (`StrandPalette`), fond noir, SF Pro / SF Rounded, Liquid Glass natif, 5 onglets.

## Diagnostic (code de `main` 7ae38ad)
- `TodayHeroCard.swift` : pas de « % » pour Charge et Repos (`ringValue`), Repos accompagné de la durée de la nuit (« 81 · 6 h 08 »), Effort sans « / 21 » ; correspondance anneau ↔ ligne par la couleur seule ; icône « checkmark » pour la Charge ; grille à hauteurs fixes (16 / 26 / 12 / 14) et tailles en dur avec `minimumScaleFactor` 0,6 → Dynamic Type rétrécit au lieu de grandir ; 8 chiffres dans une carte ; `heroSourceLabel` calculé mais jamais affiché.
- `TodayHeartRateCard.swift` : aucun axe des bpm ; en direct l'abscisse est l'index de l'échantillon, pas l'heure (`liveChart`) ; curseur à l'appui long qui n'affiche pas l'heure ; Min / Moy. / Max sans unité ni heure ; `extremes` calculé mais non dessiné.
- Fraîcheur : `LiveState.lastSyncedAt` n'est lu que dans « Sources de données », sorti de la page.
- Hiérarchie : toutes les sections ont la même surface et le même titre 20 bold.
- Jetons : `StrandFont.mono` en 13 pt fixe (sans Dynamic Type) ; pas de jeton d'annotation, de contour fin ni de reflet de sélection.

## Proposition B retenue — ce que montre la maquette
- **Niveau 1 · état** : carte des anneaux, seule avec contour fin. Unités : « 185 / 480 kcal », « 72 % », « 4,6 / 21 » + « cible 12–14 », « 81 % » + « nuit 6 h 08 ». Devant chaque ligne, un **repère** : petit cadran de 4 cercles où le cercle de l'anneau lu est coloré. Cellules Dépensé / FC repos / VFC avec une annotation monospacée de provenance (« estimé », « mesuré · nuit »), « ta normale 55–61 ».
- **Niveau 2 · explication** : la Synthèse en liste posée sur le fond (sans carte), filets entre les lignes.
- **Niveau 3 · détails** : FC, Stress, Métriques en cartes sans contour.
- **Fraîcheur** : « Bracelet synchronisé · il y a 4 min » sous le titre (un seul relevé du fait, pas d'heure en double).
- **Courbe FC** : graduations 60 / 90 / 120 bpm à droite, heures en bas, min et max annotés avec leur heure, point « maintenant », bande Sommeil, journée habituelle, seuils en pointillés ; pied « Min 52 bpm · 04:12 · Moy. 71 bpm · Max 131 bpm · 07:48 » ; chiffre « 72 bpm · mesuré à 14:35 ». En direct : abscisse en temps réel (les trous restent visibles).
- **Interaction** : trait irisé (rose FC → bleu Effort → violet Repos) sur le curseur de la FC et son étiquette « 11:20 · 96 bpm », et en bordure de la ligne d'anneau touchée. Pas de flou, statique sous Réduire les animations.
- **Métriques** : « estimation non vérifiée » (SpO₂), « estimé » (pas), « mesuré · nuit » (respiration).
- **États** : calibration (« 2 / 4 nuits · calibration », pas de bande cible, « seuils provisoires ») ; sans données (« pas de donnée », phrases d'attente, « Pas encore de synchronisation du bracelet »).
- Pas de halo au repos.

## Plan de code (après validation de la maquette)
- **Jetons** (`Packages/StrandDesign`) : `StrandFont.annotation` (monospacé, `relativeTo:` pour Dynamic Type), `NoopVisualStyle.instrumentStroke` (contour 0,5 pt, clair / sombre), `NoopVisualStyle.selectionSheen` (dégradé des couleurs de mesures), jetons d'axe. Dispositions `platform_specific` pour la gouvernance de parité.
- **Aujourd'hui** : `TodayHeroCard.swift` (unités, repère, provenance, grille qui grandit, halo seulement à l'objectif), `TodayHeartRateCard.swift` (axes, curseur heure + bpm, min / max, abscisse temporelle en direct), `TodaySynthesisCard.swift` (liste sans carte), `LiquidTodayView.swift` (ligne de fraîcheur, ordre v5, niveaux). Clés nouvelles dans les 10 langues.
- **Vérification** : PNG `render/*` en 320 et 375 pt, sombre et clair, avec et sans données, calibration ; `app-build.yml` (macOS + iOS + StrandTests) ; vidéo sur le téléphone pour l'interaction et le verre.

## Journal du code — pilote HUD d'Aujourd'hui (6 nov., nuit)
- **Choix de Mohamed** : développement sur une branche (celle de la session, `claude/optimistic-heisenberg-mj5oq2`) **+ un interrupteur** dans Réglages → Apparence, « Style HUD d'Aujourd'hui », **éteint par défaut** ; la PR peut donc être fusionnée dès que la CI est verte : le téléphone reste identique tant que l'interrupteur est éteint.
- **Interrupteur** : `TodayHUDPrefs.enabledKey` = `today.hudStyle` (UserDefaults, appareil seulement, hors `.noopbak`), lu par `LiquidTodayView` (iPhone seulement : `#if os(iOS)`, le Mac reste sur l'écran actuel) et par `SettingsView` (ligne iOS seulement).
- **Écran actuel inchangé** : le HUD vit dans `Strand/Liquid/TodayHUD.swift`. Les résolveurs de la carte des anneaux sont déplacés dans une extension de `TodayHeroModel` (`activityFraction`, `fraction(of:)`, `effortBandFraction`, `chargeRingTint`, `valueText(of:)`, `activityGoalReached`…), lus par `TodayHeroCard` **et** `TodayHUDHero` : les deux dessins ne peuvent pas afficher un chiffre différent.
- **Jetons** : `Packages/StrandDesign/Sources/StrandDesign/NoopHUDStyle.swift` (chrome, bords, lavis, textes, fond, panneaux, `glowOpacity`, coupe des coins, crochets), `StrandFont.hudLabel` / `hudCaption` / `hudValue` / `hudValueSmall` / `hudCenter`, `noopHUDLabel()` (capitales + espacement), `noopHUDPanel()`, `NoopChamferShape`, `NoopHUDBrackets`. Lueurs dessinées (trait doublé translucide, dégradé radial), aucun flou ni ombre.
- **Aujourd'hui en HUD** : réticule gradué (72 graduations, cercle pointillé, 4 repères) + 4 anneaux numérotés 01–04, Charge au centre ; 4 cellules (valeur + unité « / 480 kcal », « % », « / 21 », « % », barre de 20 segments, note : légende de calibration ou de reprise, cible de l'Effort, « nuit 6 h 08 ») ; 3 panneaux de la nuit (Dépensé « estimation », FC repos et VFC « mesuré · nuit », « ta normale … ») ; ligne de synchro sous le titre (`TodayHUDStatusLine` : « Synchronisation… », « Synchronisé il y a … », « Pas encore synchronisé ») ; fond en dégradé statique.
- **Démarrage** : `NoopFirstDraw(key: "today.hud")`, une fois par affichage de l'écran : graduations qui pivotent de −24°, anneaux qui balaient (décalage `NoopMotion.ringStagger`), centre puis cellules et panneaux qui montent de 8 pt. Sous Réduire les animations (`poseStill`), tout arrive posé.
- **Carte FC en HUD** (`\.todayHUDStyle`) : panneau HUD bordé de rose ; le graphique reçoit une échelle des bpm à droite (pas ronds, 3–4 valeurs), la valeur du point le plus bas et du plus haut, une lueur dessinée sous la courbe (`TodayHRChartModel.yAxis`, éteint ailleurs).
- **Ordre** : d'abord prévu Synthèse avant FC en HUD ; **annulé le 6 nov. (nuit) par Mohamed : la FC reste avant la Synthèse**. Le HUD suit l'ordre enregistré (anneaux → FC → Synthèse → Stress → Métriques), comme l'écran actuel.
- **Complété le 6 nov. (nuit, « code tout » de Mohamed)**, toujours derrière l'interrupteur :
  - **Synthèse** : libellé technique « SYNTHÈSE » et liste posée sur la page (filets HUD, pas de carte), « DÉMARRER » en chrome.
  - **Stress** : panneau HUD (coins coupés, crochets chrome) à la place de la carte.
  - **Métriques** : titre de section en libellé HUD, tuiles en petits panneaux à coins coupés, libellés en capitales techniques (même règle pour les autres titres de section d'Aujourd'hui).
  - **Curseur de la FC** : l'heure du point touché (« 11:20 · 96 bpm ») ; `TodayHRChartModel.timeSpan` (secondes couvertes par le tracé) posé par la courbe de la journée et par la courbe en direct du HUD.
  - **En direct** : en HUD, chaque échantillon est placé à son heure et la courbe se coupe après une pause de plus de 15 s (`liveChart(…, onClock:)`, `liveGapSec`) ; hors HUD, rien ne change (échantillons espacés régulièrement).
  - **Objectif fermé** : vibration de succès, coche qui rebondit, lueur dessinée de l'anneau qui s'allume un instant ; une fois par jour et par anneau, **avec les mêmes clés que l'écran actuel** (`TodayHeroMotion.goalStoreKey`) : changer de style ne célèbre jamais deux fois.
- **Reste pour après la validation du pilote** : les autres onglets (Sommeil, Nutrition, Entraînement, Coach), selon la demande de Mohamed (« n'étends le style qu'après validation »).
- **Clés nouvelles (10 langues)** : « Today HUD style », la phrase d'aide de l'interrupteur, « Today's status », « night %@ », « measured · night », « nights » (« estimate » existait déjà).
- **Vérification** : rendu `TodayHUDRenderTests` (sombre, clair, 375 pt, calibration, vide clair et sombre, + tests de l'ordre et des résolveurs), ajouté à `fork-render-on-push.yml`.

## Fusion et IPA (6 nov., soir)
- **#103 fusionnée** (`main` **c2fdd14**) sur 18/18 vérifications vertes sur sa tête 582ccd8 (build macOS + StrandTests, build iOS simulateur, rendu, paquets, Android, Python). Une erreur de compilation trouvée par le rendu (« unable to type-check this expression in reasonable time », `TodayHUD.swift:133`, dessin des graduations) a été corrigée en découpant le dessin en fonctions typées (`TodayHUDReticle.ticks` / `dottedCircle` / `crossMarks`). Le rendu a aussi montré la valeur du maximum de la FC coupée en haut : elle se place à côté du point quand il n'y a pas 16 pt.
- PNG du rendu envoyés à Mohamed (release `render-render-today-hud`).
- **IPA** `build/today-hud` = `main` c2fdd14, release `ipa-build-today-hud`.
- Branches temporaires à supprimer sur accord : `ci/hud-intel` (vérification de secours sur Intel), `render/today-hud`.

