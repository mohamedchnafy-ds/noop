# Chantier 20 — Mode Essentiel

**Demande de Mohamed (13 nov. 2026)** : un mode activable depuis Aujourd'hui par un petit bouton discret, qui ne garde que l'essentiel sur Aujourd'hui, Sommeil, Nutrition, Entraînement (puis Coach) : les anneaux au centre, avec la bonne animation, un résumé très court, sans décoration ni options. Ensuite : « plus d'animation, un truc sportif, science et design en même temps, que l'utilisateur soit content de l'utiliser ».

**Maquette validée** (canevas, 6 écrans) : https://claude.ai/artifact/KfSKyyoxDCbJJD4rxMixBK
- v1 : 5 écrans (Aujourd'hui normal avec ◎, puis les 4 écrans Essentiel).
- v2 (« Aujourd'hui prend encore trop de place ») : la FC en tracé d'ECG autour des anneaux, plus de phrase, 4 petits chiffres ; plus d'animations partout.
- v3 (« testons ce que tu as dit ») : la respiration autour du Sommeil, l'Effort autour d'Entraînement.
- v4 (« Et Coach ? ») : l'étoile du Coach avec les 4 mesures en orbite, le brief, une seule barre.

## Choix (décisions prises pendant le chantier)
- **Bouton ◎** (`smallcircle.filled.circle`) à côté de l'avatar, **sur les 5 onglets** : verre gris = éteint, blanc = allumé. Un tap bascule, où qu'on soit. Seulement dans le shell iOS (`showsMoreAvatar`), rien sur macOS ni dans les rendus PNG.
- **Un seul réglage** : `noop.essentialMode` (UserDefaults, sur l'appareil, **hors `.noopbak`**, pas de parité Android : réglage d'affichage iPhone seul, aucune donnée stockée nouvelle, aucune migration).
- **Aucun calcul nouveau** : chaque écran Essentiel lit le modèle que son écran normal construit déjà. Pour que les deux ne puissent pas se contredire, les calculs des anneaux sont sortis des cartes dans un seul résolveur :
  - `TodayHeroModel.heroRings` / `chargeTint` / `ringText` / `activityText` (carte d'Aujourd'hui + Aujourd'hui Essentiel) ;
  - `NutritionBalanceModel.intakeRings` / `intakeFill` (carte de Nutrition + Nutrition Essentielle) ;
  - `SleepView.topSectionModel` (carte de la nuit + Sommeil Essentiel).
- **Une seule action par page**, pour que le mode ne soit pas un piège : « Ajouter un repas » (Nutrition), « Démarrer » (Entraînement, la séance ou le cardio prévus du jour, par les mêmes chemins que la carte du jour), « Brief du jour » (Coach, écran vide).
- **Animations** : `TimelineView` + `Canvas`, toutes immobiles avec Réduire les animations ou les animations de l'app coupées (`NoopMotionState.poseStill`).
  - Aujourd'hui : ECG en cercle (12 battements par tour), tête lumineuse qui passe **une pointe par battement** sur l'horloge commune (`NoopHeartbeat.beatPhase`), cœur au centre au même rythme, onde qui part des anneaux à chaque battement. Sans FC en direct : tracé pâle immobile, « — ». Un jour passé : ni tracé ni chiffre (la FC en direct n'appartient qu'à aujourd'hui).
  - Sommeil : le cadran existant (`SleepNightDial`, qui se trace du coucher au réveil avec son point blanc) + une onde turquoise autour qui gonfle et se relâche **au rythme respiratoire de la nuit** (`SleepModel.respiratory.latest`, la série des Indicateurs). Sans rythme mesuré : onde immobile, aucun chiffre (on n'affirme pas un rythme qu'on n'a pas).
  - Nutrition : le centre se remplit comme un verre (la part de l'objectif d'apport mangée), deux vagues.
  - Entraînement : anneau de 7 jours (muscu bleu, cardio rose, prévu non fait en pâle, aujourd'hui qui pulse), courbe d'Effort autour : une colline par jour, hauteur = Effort stocké (`DailyMetric.strain`, 0–100), point d'aujourd'hui qui bat. Séances faites / prévues = `TrainingDays.sessionTally`, minutes = `periodTotals` (mêmes résolveurs que l'en-tête et le mois).
  - Coach : étoile qui respire, 4 points aux couleurs des anneaux en orbite (arrivée en spirale) ; pendant une réponse, ils tournent plus vite et plus près. Sous l'étoile : la dernière réponse (Markdown) ou « Brief du jour ». Pas de pastilles de questions, pas d'historique ni de menu ⋯ (ils reviennent en coupant le mode).

## Fichiers
- `Strand/Screens/Essential/EssentialMode.swift` : clé, bouton ◎, en-tête, chiffre, bouton d'action.
- `Strand/Screens/Essential/EssentialTraces.swift` : géométrie (`EssentialTraceMath`) et tracés (cœur, respiration, Effort, verre).
- `Strand/Screens/Essential/CoachOrbitView.swift` : l'orbite du Coach.
- `Strand/Liquid/TodayEssentialView.swift`, `Strand/Screens/SleepEssentialSection.swift`, `Strand/Screens/NutritionEssentialSection.swift`, `Strand/Screens/TrainingEssentialSection.swift`.
- Branchements : `LiquidTodayView`, `SleepView` (+ `SleepTopSection` pour le bouton), `NutritionView`, `LiftLogView` (+ `TrainingCompactViews`), `CoachView`.
- 10 clés nouvelles dans les 10 langues (les autres textes réutilisent des clés existantes).

## À tester (IPA `build/essentiel`)
- ◎ présent sur les 5 onglets ; tap → la page passe en Essentiel (fondu), ◎ blanc ; retap → la page complète revient ; le choix reste après avoir quitté l'app.
- **Aujourd'hui** : anneaux au centre qui se dessinent, ECG rose autour, point lumineux qui passe une pointe à chaque battement, cœur au centre qui bat au même rythme et chiffre des bpm ; onde qui part des anneaux ; bracelet déconnecté → tracé pâle et « — » ; 4 chiffres = ceux de la carte normale ; toucher un chiffre → son anneau seul + valeur au centre, retoucher → retour ; balayer vers un jour passé → plus d'ECG.
- **Sommeil** : cadran qui se trace, onde turquoise qui respire autour et petit point qui la parcourt ; « 14,6 respirations/min » ; 4 phases = celles de la carte ; « Ce soir, visez ≈ … ».
- **Nutrition** : 4 anneaux, centre qui se remplit (vagues) avec « kcal restantes » (ou « en trop ») ; 3 macros « g à manger » ; « Ajouter un repas » ouvre la feuille d'ajout.
- **Entraînement** : anneau de la semaine (lettres dans l'anneau), séances faites qui apparaissent une à une, aujourd'hui qui pulse, courbe d'Effort autour avec le point d'aujourd'hui ; « 3 / 5 séances cette semaine », minutes ; séance du jour + « Démarrer » (muscu → séance, cardio → séance en direct).
- **Coach** : étoile et orbites, dernière réponse sous l'étoile (ou « Brief du jour »), poser une question → les orbites accélèrent pendant la réponse, puis la réponse remplace l'ancienne.
- Réduire les animations allumé : tout est immobile et lisible.
- **Captures à envoyer** (les 5 écrans).
