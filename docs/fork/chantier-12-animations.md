# Chantier 12 — Animations (fiche du chantier, 5 nov. 2026)

**État** : maquettes **validées le 5 nov.** ; code à faire en **3 PR**, puis **une seule IPA** (qui contiendra aussi les widgets v2, #87, s'ils sont fusionnés avant). Rien n'est encore codé.
**Numéro** : 12 (le 11 est pris par les widgets v2, `widgets-v2-design.md`). Passe **avant Élan** (chantier 10).

## Maquette
Canvas « NOOP – Animations » — https://claude.ai/artifact/CdX9QpZHX9gBKtjKAZV4EF. Chaque écran se joue (bouton « Rejouer » / barre « Démo » en pointillés, qui n'existe pas dans l'app) ; panneau Tweaks : **Vitesse « Lente ×3 »** et **« Réduire les animations »**. L'étiquette « vibration … » marque seulement le moment d'une vibration.
- 1 Aujourd'hui · 2 Sommeil · 3 Nutrition · 4 Séance de muscu · 5 Coach · 6 Navigation (style sobre).
- 0 Catalogue de toute l'app (79 propositions, filtres Essentiel / Confort / Bonus / En maquette).
- 7 Effets sport (A à G).
Si la session ne peut pas ouvrir l'artefact : demander une vidéo d'écran ou des captures à Mohamed.

## Constat (5 nov.)
Les écrans refaits dans le fork (Aujourd'hui, Sommeil, Nutrition, Entraînement, séance en cours, Coach, Démarrer, Historique) n'ont presque aucune animation (0 appel dans `TodayHeroCard`, `NutritionView`, `NutritionPageParts`, `TrainingCalendarViews`, `CoachChartCard`, `CoachActionCard`, `CoachEmptyState`, `StartSheet`, `LiftProgressView`, `SleepNightDial`, `LiveWorkoutDashboard`, `LiftSessionBar`). Les écrans d'origine rangés dans Plus en ont déjà (cascade, comptage). La base existe dans `Packages/StrandDesign` : `NoopMotion` (ressorts `screen` / `card` / `value`, `CountUpText`, `.staggeredAppear(index:)`, `.softCardTransition()`, `gated`), `StrandMotion` (`drawIn`, `hero`, `breathe`), le seul interrupteur `NoopMotionState.shared.poseStill(reduceMotion)` (Réduire les animations + mode économie d'énergie + réglage de NOOP), `StrandPressableButtonStyle` / `StrandPressableModifier` (`StrandCard.swift`).

## Choix de Mohamed (5 nov.)
- **Style** : sobre, comme Fitness (ressorts doux sans rebond, vibrations légères, rien en boucle) **+ 4 effets sport** : A, B, C+E, D+F (ci-dessous). **G non retenu** : les gros chiffres restent en SF Rounded (« Actuel »).
- **Périmètre** : **Essentiel + Confort** du catalogue (~70 propositions) ; les Bonus sont écartés (liste en bas).
- **Méthode** : maquettes d'abord (faites), code ensuite, **3 PR**, **une seule IPA à la fin**.
- iPhone seulement : **aucune donnée stockée nouvelle**, Android n'a rien à suivre. Un seul réglage nouveau sur l'appareil (compte à rebours, hors `.noopbak`).
- Validation sur le téléphone **en vidéo d'écran** (les PNG ne montrent pas le mouvement).

## Règles du mouvement (à mettre en jetons dans `NoopMotion`, jamais de durée en dur dans un écran)
| Quoi | Réglage |
|---|---|
| Anneau à l'ouverture | 0,9 s, courbe « ease-out » forte sans rebond (≈ `timingCurve(0.25, 1, 0.5, 1)`), **0,09 s** de décalage par anneau, de l'extérieur vers le centre |
| Valeur qui change (jour, repas, série) | 0,65 s, même courbe |
| Chiffre qui change | `.contentTransition(.numericText(value:))` + `NoopMotion.value` |
| Comptage à l'ouverture | `CountUpText`, en même temps que l'anneau |
| Entrée en cascade | `.staggeredAppear(index:)` (montée de 8 pt), **une fois par lancement de l'app** (drapeau en mémoire), pas à chaque changement d'onglet |
| Carte touchée | `StrandPressableModifier` (≈ 97 %) |
| Vibrations | légère (`.selection` / `.impact(weight: .light)`) : choix dans un sélecteur, série cochée, repas ajouté, atterrissage d'un score (B) ; succès (`.success`) : objectif fermé, carte d'action validée, séance terminée ; forte (`.impact(weight: .heavy)`) : record, « Go » ; moyenne : fin du repos ; `.selection` : 3 · 2 · 1 |
| Réduire les animations / économie d'énergie | tout passe par `poseStill` : les valeurs arrivent directement, **les vibrations restent** |
| Boucles permises | seulement pendant qu'elles servent : cœur de la FC (séance cardio, FC en direct), 3 dernières secondes du repos, étincelle du Coach pendant l'attente, chrono en pause. Coupées par `poseStill` |

## Effets sport retenus
- **A · Anneaux en dégradé** : `AngularGradient` du ton foncé au ton vif de la couleur de l'anneau, bout lumineux (cercle de la couleur vive + ombre de 12 pt à 75 %), **halo radial derrière les anneaux d'Aujourd'hui** de la couleur de la Charge du jour (même teinte que l'anneau Charge), allumé une fois après le tracé puis à ~55 %. Où : Aujourd'hui, Nutrition, anneau Effort de l'Historique et de la fin de séance ; widgets en dégradé fixe (PR 3, après #87). Les tons foncés deviennent des **jetons** de `StrandPalette` (design system = loi).
- **B · Chiffres qui claquent** : le chiffre principal d'une carte monte en 0,85 s avec un flou de vitesse (max 6 pt, proportionnel à la vitesse), puis « atterrit » : échelle 1,14 → 1 en 0,42 s + éclat bref (ombre de sa couleur), vibration légère. Où : les 4 valeurs des anneaux d'Aujourd'hui, Endormi (Sommeil), Mangé (Nutrition), Effort de fin de séance, Vitalité (Santé). Première apparition après le lancement et changement de valeur seulement.
- **C · FC en direct** : le cœur bat au vrai rythme (période 60 / bpm), une onde part à chaque battement, la courbe défile en continu, barre **Z1–Z5** avec la zone active allumée (halo au battement), contour de la carte teinté de la zone. Couleurs : jetons existants `StrandPalette.zone1…zone5` (pas celles de la maquette). Où : séance cardio en direct, FC en direct, barre de séance réduite (cœur seul), Dynamic Island (couleur de zone, sans battement : une Live Activity ne s'anime pas en continu).
- **E · Compte à rebours 3 · 2 · 1 · Go** : avant une séance cardio en direct (sport de la feuille Démarrer, « Autre sport… », cardio du planning et de la carte du jour) ; Intervalles en a déjà un (`IntervalTimerView`, ticks `.selection`) : le mettre au même dessin. Chiffre 80 pt SF Rounded, échelle 1,55 → 1, anneau qui se vide en 1 s, « Go » en vert avec un éclat. Toucher l'écran = passer. **L'enregistrement démarre au « Go »** (la durée ne compte pas le compte à rebours). Pas de compte à rebours pour la muscu. Réglage **« Compte à rebours avant une séance »** dans Réglages, **activé par défaut**, UserDefaults `workout.countdown.enabled`, hors `.noopbak`.
- **D · Record** : reflet diagonal sur la carte (0,8 s), badge « Record » blanc avec un petit rebond (0,4 → 1,15 → 1), 8 traits courts qui partent (0,65 s), vibration forte. Rien d'autre ne bouge.
  - **Un seul résolveur** à créer côté app (`Strand/Data/LiftRecords.swift`, nom distinctif pour la gouvernance de parité) lu par la séance, la fin de séance et la fiche de séance. **Règle par défaut** : record si la charge dépasse la meilleure charge déjà faite sur cet exercice, ou même charge avec plus de répétitions que le meilleur à cette charge ; jamais à la première séance de l'exercice ; séries des séances terminées seulement.
- **F · Résumé de fin façon tableau de score** : en fin de séance (muscu et cardio), les chiffres entrent par la droite (60 pt, inclinés de −12° puis redressés), 0,22 s d'écart, en SF Rounded ; anneau Effort en dégradé (A) ; ligne Record (D) s'il y en a un ; vibration de succès.

## Plan de code (3 PR, une préoccupation chacune ; chaque PR part de `main` à jour)
### PR 1 — Fondations + anneaux et chiffres (Aujourd'hui, Sommeil, Nutrition)
- `Packages/StrandDesign` : jetons du tableau ci-dessus dans `NoopMotion` ; aides avec disponibilité (`.sensoryFeedback`, `.symbolEffect`, `.numericText(value:)` = iOS 17 / macOS 14, le paquet vise macOS 13 / iOS 16 → `if #available` dans l'aide, jamais dans l'écran) ; anneau en dégradé (A) ; modificateur « claque » (B) ; squelette de chargement qui scintille.
- **Aujourd'hui** : `Strand/Liquid/TodayHeroCard.swift` (anneaux tracés, A, B, objectif fermé = halo + coche + vibration de succès, une fois par jour et par anneau), `TodayVitals.swift` (3 cellules qui comptent, points « ta normale » qui glissent), `TodayHeartRateCard.swift` (`.numericText` déjà ligne ~279 ; courbe tracée), `TodayStressCard.swift` (courbe tracée), `TodaySynthesisCard.swift` (dette / coucher qui roulent), `TodayTiles.swift` (Toutes / Moins en cascade), `LiquidTodayView.swift` (cascade, changement de jour qui glisse).
- **Sommeil** : `SleepNightDial.swift` (fer à cheval tracé du coucher au réveil, point blanc qui suit, heure du réveil à l'arrivée), `SleepTopSection.swift`, `SleepPhasesCard.swift` / `StagesCard.swift` (phase touchée = les autres s'atténuent), `SleepView.swift` + `SleepDebtLedgerCard.swift` (Vos nuits : barres qui montent, nuit touchée, « Voir cette nuit » retrace l'anneau ; dette qui compte), `AsleepDurationCard.swift` (Endormi, B) ; Anneau ↔ Courbes en fondu ; heure corrigée qui se réajuste ; Indicateurs qui comptent.
- **Nutrition** : `NutritionPageParts.swift` / `NutritionView.swift` (anneaux A, Mangé B, « +620 kcal » qui monte, Reste / Bilan qui roulent, moments qui se déplient, ligne supprimée qui glisse, anneau dépassé = 2e tour plus foncé), `NutritionAddSheet.swift`, `NutritionBarcodeScanner.swift` / `NutritionBarcodePanels.swift` (cadre qui se resserre, coche + vibration), `NutritionMealEditor.swift` (portion qui roule), `NutritionMealCapture.swift` (onde de la dictée, reflet pendant l'estimation), `NutritionGoalsView.swift` (résultat qui roule), `NutritionHistoryCard.swift` (barres, 7 j ↔ 30 j).
### PR 2 — Séance de muscu + cardio + bannière
- **Muscu** : `LiftSessionView.swift` (série cochée : coche tracée + vibration ; le défilement existe ~l. 265 ; Changer l'ordre ~l. 323 ; fin de séance `finishAndDismiss` ~l. 1475 → résumé F), `LiftSupersetScreen.swift` (repos en anneau à la place de `.linear(duration: 1)` ~l. 727, 3 dernières secondes, +30 s, A1 → A2 qui glisse, tour terminé), `LiftSessionExerciseSheet.swift` et `LiftLiveReadouts.swift` (charge / répétitions qui roulent), `LiftSessionBar.swift` (chrono qui roule, anneau de repos), `LiftSessionDetailSheet.swift` (ligne Record), chrono en pause qui respire ; record D par `LiftRecords`.
- **Cardio** : `LiveWorkoutView.swift` / `LiveWorkoutDashboard.swift` (C, zone qui change en fondu + vibration légère en zone 4-5, km qui glisse, courbe qui défile, compte à rebours E, résumé F), `LiveView.swift` (FC en direct, C), `IntervalTimerView.swift` (anneau de phase, effort ↔ repos en fondu, 3-2-1 au dessin E), `StartSheet.swift` / `WorkoutStartControl.swift` (point d'entrée du compte à rebours), Réglages (interrupteur du compte à rebours).
- **Bannière** : `StrandiOSWidgets/LiftLiveActivity.swift` (le chrono `Text(timerInterval:)` existe ; ajouter `ProgressView(timerInterval:countsDown:)` pour le repos, `.contentTransition(.numericText())` sur FC / série / Effort), `NOOPLiveActivity.swift` (bannière FC : couleur de zone). Vue de l'extension : règle « vue pure dans `StrandiOSShared/` » de la feuille de route.
### PR 3 — Coach + navigation + le reste
- **Coach** : `CoachView.swift` (étincelle qui pulse tant que `coach.sending` n'a pas de premier mot ; mots en fondu au fil du flux, sans à-coups — voir `streaming` ~l. 697 et le défilement ~l. 1416), `CoachChartCard.swift` (courbe tracée, barres qui montent, bande normale en fondu, valeur touchée qui roule), `CoachActionCard.swift` (Valider : coche + vibration de succès + repli en « Fait · Annuler »), `CoachEmptyState.swift` (étincelles une fois, cascade), `StrandiOS/App/CoachVoiceInput.swift` (onde de la voix).
- **Navigation** : `StrandiOS/App/RootTabView.swift` (icône d'onglet qui rebondit), **zoom carte → écran** (`matchedTransitionSource` + `.navigationTransition(.zoom)`, iOS 18 : code partagé avec macOS 13 → `#if os(iOS)` dans une aide) pour la carte FC, Stress, les tuiles de Métriques, une nuit, une séance ; `MoreSheet.swift` (feuille Plus depuis l'avatar, Avancé en cascade).
- **Entraînement** : `TrainingCalendarViews.swift` (pastille du jour qui glisse `matchedGeometryEffect`, carte du jour en fondu, Semaine ↔ Mois, ‹ › qui glisse), `LiftProgressView.swift` (compteurs, courbes), `StartSheet.swift` (pastille de programme, libellé qui roule), `WorkoutsView.swift` (Historique : anneau Effort A, barres, chiffre de la barre touchée), `LiftProgramEditorSheet.swift` (blocs qui glissent, Lier / Détacher), `LiftBodyMap.swift` (muscle en fondu).
- **Plus et secondaires** : Santé / Stress / Tendances (mêmes jetons de durée), `SmartAlarmView.swift` (cloche qui sonne à l'armement, compte à rebours qui roule), `BackupSyncView.swift` (progression, coche + vibration), recherche du bracelet (ondes) dans `Strand/Onboarding/AddDeviceWizard.swift`.
- **Widgets** : seulement **après la fusion de #87** (widgets v2) : chiffre qui roule à chaque mise à jour, anneaux en dégradé fixe. Si #87 n'est pas fusionnée, reporter et le dire.

### Écartés (Bonus)
« + » qui tourne vers Démarrer, guide des scores en zoom, flèche de la charge à monter, vignette de photo qui vole vers la bulle, Carnet de labo qui compte, Respirer (déjà animé), indicateur de synchro (déjà animé), chiffres « sport » (G).

## Pièges propres au chantier
- **Code partagé macOS 13** : toute API iOS 17+ / macOS 14+ passe par une aide de `StrandDesign` avec `if #available` ; la jambe macOS d'`app-build.yml` le vérifie.
- **Rendu PNG et StrandTests** : `ImageRenderer` capture une seule image. Une valeur qui part de 0 à l'apparition (comme `CountUpText`, qui démarre à 0 dans `onAppear`) peut être dessinée à 0 : prévoir que les vues de rendu posent l'état final (par ex. une clé d'environnement « rendu immobile » posée par les tests de rendu, ou `poseStill`), et vérifier les PNG de la jambe `render`. Les tests qui comparent des textes ne doivent pas changer.
- **Gouvernance de parité** : `Packages/StrandDesign/Sources/**` est dans le périmètre de `parity_ledger.py` → chaque nouvelle déclaration publique reçoit une disposition `platform_specific` (procédure de la feuille de route), noms distinctifs côté app (ex. `slamIn`, `gradientRing`, `liftRecordCheck`).
- **i18n** : « Record », « Go », le réglage du compte à rebours et sa phrase d'aide, « Fait » si nouveau : 10 langues.
- **Un seul résolveur** : record (`LiftRecords`), zone FC (le résolveur de zone déjà utilisé par la séance en direct), réglage du compte à rebours (lu à un seul endroit).
- **BLE** : rien à toucher ; aucune animation ne doit retarder l'écriture d'une série ou le démarrage d'une séance (sauf le « Go » voulu).

## À tester sur le téléphone (vidéo d'écran)
- Aujourd'hui : anneaux tracés en dégradé + halo de la Charge, 4 valeurs qui claquent, cellules qui comptent, objectif fermé (halo, coche, vibration), courbes FC et Stress tracées, changement de jour, cascade une seule fois par lancement.
- Sommeil : fer à cheval tracé, Endormi qui claque, phase touchée, Vos nuits, « Voir cette nuit ».
- Nutrition : repas ajouté (+kcal, anneaux, vibration), moments, scanner, portion, anneau dépassé.
- Séance : série cochée, record (règle ci-dessus), repos en anneau (+30 s, 3 dernières secondes, vibration), A1 → A2, pause, fin de séance en tableau de score ; cardio : compte à rebours (et son réglage), cœur au rythme, zones, km ; bannière : barre de repos qui se vide écran verrouillé.
- Coach : étincelle, mots en fondu, graphique tracé, carte d'action validée.
- Navigation : zoom carte → écran et retour, feuille Plus depuis l'avatar, icône d'onglet.
- Réduire les animations (iPhone) et mode économie d'énergie : plus rien ne bouge, valeurs justes, vibrations présentes.

## Prompt de démarrage (nouvelle conversation)
> Chantier 12 — animations. Lis `docs/fork/feuille-de-route.md` puis `docs/fork/chantier-12-animations.md` (tout). Maquette : https://claude.ai/artifact/CdX9QpZHX9gBKtjKAZV4EF. Pars de `main` à jour (vérifier les branches en avance et les PR ouvertes, en particulier #87 widgets v2). Code les 3 PR dans l'ordre (1 Fondations + Aujourd'hui / Sommeil / Nutrition ; 2 Séance + cardio + bannière ; 3 Coach + navigation + reste), chacune depuis `main` à jour, avec les vérifications de la feuille de route (i18n, doc_comment_lint, unittest, gouvernance de parité). Fusionne chaque PR dès que la CI est verte (0 non-succès sur un total stable, build iOS compris) sans attendre l'IPA, comme pour le chantier 8. À la fin : une seule IPA `build/animations` depuis `main` avec les 3 rappels, et la liste « À tester » en vidéo. Une seule question par étape, via le widget ; pas de question si la fiche donne la réponse.
