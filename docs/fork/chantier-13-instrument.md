# Chantier 13 — Esthétique « Instrument » (fiche du chantier, 6 nov. 2026)

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
- Passe de cohérence (5 nov., FC avant Synthèse) : **la Synthèse repasse avant la FC** (choix de Mohamed, 6 nov.) — anneaux → Synthèse → FC → Stress → Métriques, déplacement unique (v5) comme v3 / v4.
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
