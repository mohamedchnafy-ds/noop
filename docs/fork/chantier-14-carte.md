# Chantier 14 — Carte (position et métriques) — fiche (6 nov. 2026)

**État** : **étape 1 fusionnée le 7 nov.** (#102, `main` 138c166 ; IPA `build/carte` validée par Mohamed). **Étape 2 en code (7 nov.)** : maquette v1 validée telle quelle ; **code fusionné** : A stockage (#106), B suivi (#107), C écrans Lieux · Un lieu · Points + Coach (#108), `main` 4be20b4 ; **IPA `build/carte-2`** = `main` 4be20b4, à valider sur le téléphone (liste « À tester » de l'étape 2 ci-dessous).

## La demande (6 nov.)
Une carte avec plusieurs calques : mes positions avec la FC, avec la VFC, avec d'autres métriques, pour voir si une métrique dépend du lieu.

## Ce que l'app sait déjà de la position (relevé du 6 nov., `main` 7ae38ad)
- Autorisation **« Pendant l'utilisation » seulement** (`NSLocationWhenInUseUsageDescription`, `project.yml`). Pas de « Toujours », pas de suivi en arrière-plan hors séance.
- GPS **seulement pendant une séance d'extérieur** lancée dans l'app (course, vélo, marche, rando) : `Strand/App/GpsWorkoutRecorder.swift` (`GpsWorkoutRecorder`, filtre `TrackFilter`).
- Stockage : `RouteStore` (UserDefaults, clé = début + sport de la séance) ; points `WorkoutRoutePoint` = lat, lon, précision, **heure en ms** → on peut joindre la FC de la même seconde. Sur l'appareil seulement.
- Trajets des séances **importées de Santé** lus aussi (`HKSeriesType.workoutRoute()`, #1205) ; réécriture vers Santé (#2340).
- Carte d'une séance : `WorkoutDetailView` (MapKit, trajet d'**une seule couleur**, départ vert / arrivée rouge).

## Choix de Mohamed (6 nov.) : les deux, en 2 étapes
### Étape 1 — Carte des séances (données déjà là)
- Toutes les séances GPS sur une seule carte ; **trajet coloré par zone FC** (couleurs des zones de l'app) au lieu d'une seule couleur, aussi dans la carte d'une séance.
- Aucune autorisation nouvelle, aucune donnée stockée nouvelle (iPhone seulement, comme les autres écrans du fork).
### Étape 2 — Lieux
- Détection des **lieux où l'on reste** (visites iOS, `CLVisit` : peu de batterie, précision de l'ordre d'un quartier ou d'un bâtiment) ; nom du lieu modifiable (Maison, Travail, Salle…).
- Par lieu, calques : **FC et Stress moyens** pendant les visites ; **VFC et Récupération des nuits** passées là ; peut-être Sommeil (durée, dette).
- Afficher l'**écart à ta normale**, pas la valeur brute, et seulement au-delà d'un nombre minimum de jours (à fixer dans la maquette).
- Demande l'autorisation **« Toujours »** (nouvelle clé `NSLocationAlwaysAndWhenInUseUsageDescription`) et un **interrupteur** pour arrêter le suivi et effacer les lieux.

### Suivi continu (choix de Mohamed, 6 nov.)
- **Relevé en continu** en plus des visites : autorisation « Toujours », mises à jour de position en arrière-plan (le mode `location` est déjà dans `UIBackgroundModes`, utilisé par `GpsWorkoutRecorder`), indicateur iOS de position visible ; **changements importants de position** en filet de sécurité pour relancer le suivi si iOS ferme l'app (après un balayage, reprise au prochain grand déplacement).
- iOS ne réveille pas une app « toutes les N minutes » : le mode par intervalle garde la position active en précision réduite et **ne garde qu'un point par intervalle**.
- **Réglage « Suivi de position »** : mode **Économe** (≈ 500 m, sans GPS) · **Équilibré** (un point toutes les 5 / 15 / 30 / 60 min, ≈ 100 m) · **Précis** (tous les 50 / 100 / 250 / 500 m, GPS) ; **défaut : Équilibré · 15 min** ; pause à l'arrêt (allumée) ; pas de relevé la nuit 23:00–07:00 (allumé, la nuit compte pour le lieu du coucher) ; autres plages sans relevé ; garder les points 1 an ; effacer. Pendant une séance GPS, le trajet reste à la seconde.
- **Un point stocké = heure, lat, lon, précision** ; FC, Stress, etc. retrouvés par l'heure dans les données du bracelet (rien de dupliqué).
- **Calque Points** (vue Séances | Lieux | Points) : FC comparée à ta FC habituelle de la même heure (±3 bpm = normale ; bleu clair plus basse, orange plus haute) ou Stress (couleurs Calme / Modéré / Élevé, gris foncé en mouvement) ; Jour · 7 J · 30 J ; toucher un point = heure, lieu, valeurs ; point creux sans FC.
- Maquette : écrans 6 « Suivi de position » et 7 « Carte · Points » du canvas.

### Pas (choix de Mohamed, 7 nov.)
- **Le WHOOP 4.0 n'envoie pas de pas** en Bluetooth, et son accéléromètre arrive environ une fois par minute : impossible de compter les foulées. Aujourd'hui NOOP montre une **estimation** du jour (`steps_est`, `StepsEstimateEngine`, calibrée sur les pas de l'iPhone) ; seul le WHOOP 5.0/MG a un compteur (`step_motion_counter`).
- La source des pas est donc **l'iPhone** (CoreMotion, `CMPedometer`), qui doit être sur soi. Déjà utilisé une fois en fin de séance (`Strand/Data/WorkoutPedometer.swift`, `NSMotionUsageDescription` présent) ; à ajouter : le relevé **en direct** (`startUpdates`).
- **Pendant une séance d'extérieur** (marche, course, rando) : un relevé **toutes les 5 s** (pas cumulés, cadence en pas/min, distance du podomètre), à côté des points GPS (même heure) :
  - tuiles **Pas** et **Cadence** sur l'écran de séance en cours ;
  - dans le détail : **courbe des pas/min** et **pas de chaque km** ;
  - sur la Carte : couleur du trajet **Zones FC | Cadence**.
- **Suivi continu** : chaque point (Équilibré · 15 min) garde aussi les **pas depuis le point précédent**, lus dans l'historique de l'iPhone (7 jours gardés par iOS) sans relevé en direct.
- iOS donne les mises à jour du podomètre à son rythme (quelques secondes) : on garde la dernière valeur toutes les 5 s. Stockage iPhone seulement, à côté du trajet (`RouteStore`) ; pas de donnée envoyée.
- Rangé dans ce chantier, avec l'étape 1 (même séance GPS) ; maquette refaite dans le nouveau design.

## Étape 1 — code (7 nov., PR #102)
Choix de Mohamed (7 nov.) : **l'étape 1 entière** dans une PR, puis une IPA. Ni autorisation « Toujours », ni migration, ni donnée de la base (stockage `UserDefaults` à côté du trajet, iPhone seulement, hors `.noopbak` comme `RouteStore`).
- **Pas de l'iPhone** : `Strand/App/WorkoutStepRecorder.swift` (`CMPedometer.startUpdates`, une lecture toutes les 5 s, pauses exclues, reprise après un arrêt forcé par `ActiveStepStore`) ; armé par `AppModel` pour une séance GPS **Course, Marche, Randonnée** (`WorkoutStepMath.recordsSteps`) ; enregistré à la fin sous la clé du trajet (`WorkoutStepStore`, `noop.workoutSteps.<début>|<sport>`). La colonne `steps` de la séance reste vide (donnée de la base partagée avec Android).
- **Calculs purs** : `Strand/Data/WorkoutSteps.swift` — `WorkoutStepMath` (cadence du moment sur 30 s, cadence minute par minute, pas de chaque km aux mêmes passages que les temps au km, rien à travers une pause > 15 s) et `RouteColoring` (zone FC de chaque point = échantillon FC le plus proche à 30 s près, sinon gris ; bandes de cadence < 90 · 90 · 110 · 130 · ≥ 160 pas/min ; segments qui partagent leur point de jonction). Tests : `StrandTests/WorkoutStepsTests.swift`.
- **Un seul calcul par fait** : la cadence de la tuile et de la courbe vient de `WorkoutStepMath`, jamais du champ cadence du podomètre ; la tuile Pas du détail lit d'abord les lectures enregistrées (même total que la carte Cadence).
- **Séance en cours** : tuiles **Pas** (« téléphone ») et **Cadence** (pas/min, « — » avant 15 s de lectures) sous les 4 tuiles, en mise en page cardio, seulement quand des pas sont relevés.
- **Détail d'une séance** : carte du trajet coloré par **zones FC** (`ColoredRouteMap`, un trait par segment, légende Z1…Z5) ; sélecteur **Zones FC | Cadence** quand les pas existent (légende Lent → Rapide, cyan du plus pâle au plus plein) ; carte **Cadence** (courbe des pas/min, Pas · Moy. · Pic) et **Pas par kilomètre** (ou par mille). Un trajet enregistré sans les heures de ses points reste d'une couleur (gris).
- **Écran Carte** : `Strand/Screens/RouteMapScreen.swift`, ligne **Carte** sous Tendances dans la feuille Plus (Analyses) ; 30 J · 90 J · Tout (60 séances au plus) ; toutes les séances GPS, toucher une séance = elle seule en couleur, les autres pâlies ; sélecteur Zones FC | Cadence quand une séance a des pas ; liste avec distance, durée, pas et barre des zones ; état vide expliqué. Pas de sélecteur Séances | Lieux tant que l'étape 2 n'existe pas, pas de valeur à droite de la ligne Carte (v1).
- **Traductions** : 19 clés dans les 10 langues (« Cadence » = « Cadence des pas » en français pour éviter l'écho de l'anglais).
- **À tester sur le téléphone** (la CI ne voit ni podomètre ni GPS) : une marche dehors lancée par le « + » d'Aujourd'hui, iPhone en poche : autorisation « Mouvements et forme » au premier lancement, tuiles Pas et Cadence qui avancent, Pause (les pas pendant la pause ne comptent pas) ; à la fin, détail de la séance : trajet coloré par zones, sélecteur Zones FC | Cadence, courbe Cadence, pas par km, tuile Pas = total de la carte Cadence ; Plus → Analyses → Carte : la séance sur la carte, 30 J · 90 J · Tout, toucher une séance, Zones | Cadence. Une course de plus de 1 km pour les pas par km. Une ancienne séance GPS (sans pas) : trajet par zones si ses points ont leur heure, sinon gris.

## Étape 2 — choix de Mohamed (7 nov.)
- IPA `build/carte` : **tout est bon**, #102 fusionnée.
- **Maquette v1 validée telle quelle** (écrans 3 à 7) : écart dès 3 nuits, bleu clair / gris / orange, FC des séances à part, défaut Équilibré · 15 min, nuit 23:00–07:00 sans relevé.
- **Stockage** : tables dans la base (migration iOS **v54-places** / Android **MIGRATION_45_46**, Room 46), tables créées aussi sur Android sans écran.
- **Découpage** : 3 PR + 1 IPA (A stockage, B suivi et réglages, C écrans Lieux / Un lieu / Points), fusion dès la CI verte, IPA `build/carte-2` à la fin.
- **« Dans la sauvegarde »** : interrupteur retiré ; lieux et points sont **toujours** dans le `.noopbak` (il copie la base entière), une ligne le dit.
- **« Le Coach peut le lire »** (éteint par défaut) : **dans cette étape** (PR C) : bloc lieux dans la fiche du Coach quand il est allumé.

## Étape 2 — code
### PR A — stockage
- GRDB `v54-places` / Room `MIGRATION_45_46` : `locationPoint` (clé = heure en **ms**, lat, lon, précision, **pas depuis le point précédent**, nul = inconnu), `place` (id, nom facultatif, centre, rayon en m, création), `placeVisit` (id, lieu, arrivée, départ nul tant qu'on y est, centre, précision ; index par lieu + arrivée et par arrivée). Pas de `deviceId` (comme les repas). Les deux `schema_oracle.json` (`both`), export Room `46.json` (branche temporaire `ci/room-schema-places`, release `room-schema-8d89546`).
- `WhoopStore` `PlaceStore.swift` (points, lieux, visites ; la purge des visites efface aussi un lieu **sans nom** resté vide) ; tests `PlaceStoreTests`, `PlacesMigrationTest` (Kotlin).
- Côté app, **un seul accès** : `Strand/Data/PlaceLog.swift` (`PlaceLog`, compteur `places.revision`) ; `PlaceVisitPlan.planVisit` = règle visite iOS → lieu + séjour : lieu le plus proche dont la zone (max(rayon, 150 m)) contient la visite, sinon nouveau lieu de 150 m ; une arrivée ouvre un séjour et ferme un séjour resté ouvert ; un départ ferme le séjour de même arrivée (± 2 min), sinon celui du même lieu ; tests `PlaceLogTests`.
- Aucune métrique copiée : FC, Stress, nuits sont relus par l'heure dans les données du bracelet.

### PR B — suivi et réglages
- **`Strand/App/PlaceTracker.swift`** (`PlaceTracker.shared`, attaché dans `StrandiOSApp.init` pour qu'un relancement par iOS — visite, grand déplacement — retrouve son délégué ; réappliqué au retour au premier plan) : visites iOS (`CLVisit` → `PlaceLog.recordVisit`), **changements importants** (≈ 500 m, filet de sécurité qui relance le suivi après un balayage ou une pause), et en Équilibré / Précis les mises à jour normales (`CLBackgroundActivitySession`, flèche de position visible) **amincies** par `PlaceTrackingRules.keepsFix` (Équilibré : un point par intervalle, 10 % de marge au plus 1 min ; Précis : tous les N m à 10 % près ; Économe : chaque grand déplacement). Pas de point la nuit (23:00–07:00, interrupteur) ni dans les autres plages : les mises à jour fines s'arrêtent, visites et grands déplacements continuent. « Pause à l'arrêt » = `pausesLocationUpdatesAutomatically`. Précision > 1 km écartée.
- **Pas depuis le point précédent** : `CMPedometer.queryPedometerData` entre les deux points (7 jours gardés par iOS), nul sinon.
- **Réglages** (`Strand/Data/PlaceTrackingSettings.swift`, UserDefaults `places.*`, hors `.noopbak`) : Lieux allumés (éteint par défaut), mode (défaut Équilibré), 5 / 15 / 30 / 60 min (défaut 15), 50 / 100 / 250 / 500 m (défaut 100), pause à l'arrêt (allumé), nuit (allumé), autres plages, garder points / visites (3 mois · 6 mois · **1 an** · 2 ans), « Le Coach peut le lire » (éteint). Lieu sans nom = « Lieu n » par ordre de création (`PlaceNaming`).
- **Écrans** : roue crantée en haut de l'écran Carte → **Lieux** (`PlacesSettingsView` : carte d'activation, état de l'autorisation avec « Ouvrir Réglages », Suivre mes lieux, Suivi de position, Le Coach peut le lire, Garder les visites, Lieux reconnus → renommer / oublier, Effacer tous les lieux ; ligne « dans la sauvegarde .noopbak ») → **Suivi de position** (`LocationTrackingSettingsView` : dernier relevé et points de la semaine, mode + batterie, fréquence, Quand, plages sans relevé, Garder les points, Effacer tous les points).
- `project.yml` : `NSLocationAlwaysAndWhenInUseUsageDescription` (iOS), `NSMotionUsageDescription` cite les pas entre deux positions.
- Tests : `PlaceTrackingTests` (plages à cheval sur minuit, intervalle, distance, défauts, noms). Traductions : 59 clés dans les 10 langues.

### PR C — écrans Lieux · Un lieu · Points + Coach
- **Règles pures** `Strand/Data/PlaceMetrics.swift` (tests `PlaceMetricsTests`) ; **lecture** `Strand/Data/PlaceMapReader.swift` (un seul lecteur pour la vue Lieux, l'écran d'un lieu et le Coach).
  - **Nuit → lieu** : le séjour en cours au début du sommeil (lieu du coucher), sinon le dernier séjour commencé dans les 12 h ; une nuit = le plus long bloc de sommeil (≥ 3 h) qui finit ce jour-là, avec la VFC / Récupération / durée de `dailyMetric`.
  - **VFC, Récupération, Sommeil** : moyenne des nuits du lieu contre la moyenne de **toutes** les nuits des 90 j ; écart affiché dès **3 nuits** (« trop peu » avant, pastille creuse). Bande « proche » : VFC ± 3 ms, Récupération ± 5 pts, Sommeil ± 20 min.
  - **FC** : moyenne des buckets 5 min **éveillés** des séjours (séances et sommeil retirés) contre la FC des **mêmes heures** dans les autres lieux, pondérée par heure ; ± 3 bpm = proche ; dès 3 visites avec FC.
  - **Stress** : part des heures notées en Élevé (niveau ≥ 2, heures en mouvement retirées) pendant les séjours contre la part sur toutes les heures notées ; ± 3 pts ; **14 derniers jours** seulement (le stress se calcule jour par jour).
  - Couleurs : mieux = `metricCyan` (bleu clair), proche = gris, moins bien = `statusWarning` (orange) ; FC et Stress : plus bas = mieux.
- **Écran Carte** : sélecteur **Séances | Lieux | Points** sous le titre (`RouteMapView`), la vue Séances inchangée.
  - **Lieux** (`PlacesLayerView`) : pastilles FC · Stress · VFC · Récup (défaut VFC), carte à disques (`PlaceDotsMap` : taille = visites, creux = trop peu, nom sous le disque), légende, explication du calque, liste triée (moins bien d'abord) → **Un lieu** (`PlaceDetailView` : visites · nuits · dernière, zone ≈ rayon, « Comparé à ta normale » VFC / Récupération / Sommeil / FC / Stress, « Nuits ici » (12 dernières, bleu clair / orange contre la normale), Renommer, Oublier ce lieu). Sans Lieux allumés : carte « Activer les Lieux » → réglages.
  - **Points** (`PointsLayerView`) : FC | Stress, Jour · 7 J · 30 J (défaut 7 J) ; un point = FC du bucket le plus proche contre la FC habituelle de la même heure (30 derniers jours) ; Stress = niveau de l'heure (Calme / Modéré / Élevé, gris foncé en mouvement), creux sans donnée ; toucher un point = heure, lieu, FC et écart, Stress ; tuiles Points / Plus haute / Plus basse (FC) ou Élevé / Pas (Stress).
- **Coach** : bloc **PLACES** (`CoachPlacesBlock.swift`) dans le contexte complet, seulement avec Lieux allumés **et** « Le Coach peut le lire » (et « Utiliser mes données ») : 8 lieux au plus, noms + visites, nuits, écarts VFC / Récupération / Sommeil / FC, jamais une coordonnée, stress omis (trop lent à chaque question). Ce que lit le Coach : carte **Lieux** avec le même réglage.
- Traductions : 57 clés.
- **Piège de parité vu sur #108** : `PlaceMetrics.verdict(delta:band:higherIsBetter:)` (3 arguments) comptait comme appel de `Whoop5EcgProbe.verdict` (3 arguments, appelée seulement par des tests) → `test-only-callsite|Packages/WhoopProtocol` en écart dans le test d'acceptation. Renommée `placeVerdict` (et `signedPlaceDelta`, `valueText`, `deltaText`, `reportDotTap`).

### À tester sur le téléphone (IPA `build/carte-2`)
- **Activer** : Plus → Analyses → Carte → roue crantée → « Activer les Lieux » → iOS demande la position (« Lorsque l'app est active » d'abord) ; l'avertissement orange et « Ouvrir Réglages » tant que ce n'est pas « Toujours » ; choisir « Toujours » dans Réglages → l'avertissement disparaît ; la flèche de position iOS apparaît.
- **Suivi** : Suivi de position → « Dernier relevé il y a … · n points cette semaine » avance (un point / 15 min en se déplaçant) ; Économe / Précis et les fréquences ; nuit 23:00–07:00 sans point ; une plage ajoutée (ex. 12:00–14:00) sans point ; app fermée d'un balayage → les points reprennent après un grand déplacement ; batterie sur une journée (Réglages → Batterie).
- **Lieux** : après quelques jours, Lieux reconnus → « Lieu 1 », « Lieu 2 »… ; renommer (Maison, Travail) ; vue Lieux de la Carte : disques et noms, calques, liste, un lieu → écarts, Nuits ici, Oublier ; « trop peu » avant 3 nuits.
- **Points** : FC | Stress, Jour · 7 J · 30 J, toucher un point (heure, lieu, FC, écart), points creux bracelet retiré.
- **Coach** : « Le Coach peut le lire » allumé → « Est-ce que je dors mieux chez mes parents ? » ; éteint → il ne sait rien des lieux.
- **Sauvegarde** : un `.noopbak` exporté puis restauré garde les lieux et les points.

## Carte v2 — retours sur l'IPA `build/carte-2` (7 nov., soir) et choix de Mohamed
Captures du 7 nov. (19:59) : vues Séances, Lieux (FC, VFC « aucune nuit »), Points (7 J, 18 points).
**Retours** : le design ne fait pas « sport / science » comme le reste de l'app ; l'affichage sur la carte est à optimiser ; vouloir une légende, choisir ce qu'on affiche et voir plusieurs valeurs à la fois ; **Lieux met du temps à s'afficher**.
**Constats** : fond Apple Plans chargé (commerces, cinéma, hôpital) qui écrase les données ; un lieu sans écart = grand cercle gris vide ; « Moins bien » sort en **jaune** (`statusWarning`) au lieu d'orange ; trois vues séparées (impossible de voir un trajet et ses points ensemble). Lenteur : à chaque ouverture, stress recalculé jour par jour sur 14 j (`StressDayCurve.day` × 14, le plus lourd) + 90 j de FC / sommeil / séances, et rechargé à chaque nouveau point (`places.revision`).
**Choix (7 nov.)** : les 4 propositions, **codées directement sans maquette** :
1. **Une carte à calques** : une seule carte ; bouton Calques pour afficher **en même temps** Trajets, Lieux et Points ; couleur au choix (FC, Stress, VFC, Récup, Cadence) ; **légende posée sur la carte** selon ce qui est allumé.
2. **Fond sobre, données en avant** : fond sombre atténué sans commerces ni lieux publics (`MKStandardMapConfiguration(emphasisStyle: .muted)`, `pointOfInterestFilter = .excludingAll`, sombre) ; lieux en disques pleins avec leur valeur en étiquette (« VFC +4 ms ») ; points reliés en trajet fin ; plein écran.
3. **Frise de la journée** : sous la carte, la courbe FC ou Stress du jour ; glisser le doigt dessus montre le point sur la carte, toucher un point montre son heure sur la courbe.
4. **« Ce qui ressort »** : les écarts nets classés (ex. « Chez mes parents : VFC −7 ms, 6 nuits ») avec le nombre de jours et une marge d'erreur ; signalé seulement s'il dépasse le bruit.
Toujours : **Lieux s'affiche tout de suite** (résultats gardés d'un jour à l'autre — un jour passé ne change plus —, affichage immédiat du dernier calcul, stress calculé seulement quand on touche Stress) ; « Moins bien » en **orange**.

### Carte v2 — code
- **PR 1 — rapidité, fond sobre, orange** :
  - **Jours passés gardés** (`Strand/Data/PlaceMapCache.swift`) : stress par heure et FC par 5 min, jour par jour, dans un fichier du dossier Caches (`noop-places-map-days.json`, 100 j au plus). Un jour est figé **24 h après sa fin** (`PlaceMapFreeze.frozenAfterSeconds`) : seuls aujourd'hui et hier sont relus à chaque ouverture. Le stress gardé est jeté si le réglage « ligne de base personnelle » change. Le fichier perdu = une ouverture lente, rien d'autre.
  - **Dernier calcul d'abord** : les chiffres des lieux sont gardés (`noop-places-map-summaries.json`) et dessinés tout de suite, puis remplacés par le calcul frais. Oublier un lieu le retire aussi de ce fichier ; tout effacer le supprime.
  - **Stress à la demande** : calculé seulement une fois la couche Stress touchée ; sinon le stress du dernier calcul est repris (`PlaceMapFreeze.carryPlaceStress`).
  - **Plus de rechargement à chaque point** : nouveau compteur `places.placeRevision` (lieu ou séjour modifié) pour Lieux ; `places.revision` (chaque point) reste pour Points et les réglages.
  - **Fond sobre** (`QuietMapLook.applyQuietMapLook`) : `MKStandardMapConfiguration(emphasisStyle: .muted)`, sans points d'intérêt, toujours sombre ; sur la carte des séances, Lieux, Points et le détail d'une séance.
  - **Orange** : jeton `StrandPalette.deviationOrange` (orange dans les deux styles de graphique ; `statusWarning` vire au jaune en style Classique, d'où le jaune vu sur l'IPA) pour « Moins bien », « Plus haute » et l'avertissement de position.

- **PR 1 fusionnée** : #111 (`main` 92e1180, 16/16).
- **PR 2 — carte à calques, frise, « Ce qui ressort »** :
  - **Un seul écran** (`RouteMapScreen`) : la carte (`LayeredPlaceMap`) dessine en même temps **Trajets** (zones FC, ou cadence), **Lieux** (disques pleins de 14 à 28 pt selon les séjours, nom + « VFC +4 ms » dessous ; pâle quand trop peu ou rien à comparer) et **Points** (petits disques reliés par un trajet fin, coupé quand deux points sont à plus de 3 h). Bouton **Calques** (menu à cases) et **Plein écran** en haut à droite ; **légende posée en bas à gauche**, une ligne par calque allumé. Calques et couleur gardés (`map.layers.*`, `map.tint`).
  - **Couleur au choix** (pastilles sous la carte) : FC · Stress · VFC · Récup · Cadence (Cadence seulement si une séance a les pas). Lieux suivent FC / Stress / VFC / Récup (Cadence → VFC) ; Points suivent Stress, sinon FC ; Trajets en zones FC, sinon cadence.
  - **Période** : Jour · 7J · 30J · 90J (défaut 7J) pour Trajets et Points ; Lieux toujours sur 90 jours.
  - **Frise de la journée** (`MapDayStrip`) : ‹ jour › + FC | Stress ; courbe FC du jour (5 min) ou barres de stress par heure ; un trait sous chaque point du jour. **Glisser** → curseur blanc sur la carte (sur la ligne entre les deux points qui encadrent l'instant, s'ils sont à moins de 3 h ; sinon au point le plus proche à 30 min près) + carte du point en haut à gauche ; **toucher un point** de la carte → la frise passe à son jour et montre son heure.
  - **« Ce qui ressort »** (`PlaceStandouts`) : pour chaque lieu et VFC, Récup, Sommeil, FC, Stress, l'écart est listé seulement s'il est un verdict (assez de nuits ou de visites, hors de la bande « proche ») **et** plus grand que sa **marge d'erreur** (intervalle à 95 % de la moyenne du lieu : 1,96 × écart-type / √n, sur les nuits, ou sur les visites pour FC et Stress). Classé par écart / marge ; 5 lignes au plus. Ex. « Chez mes parents · VFC de la nuit · 6 nuits : −7 ms, ± 4 ms ».
  - Le **Coach** reçoit la marge d'erreur dans le bloc PLACES (« margin of error ±4 ms ») et la consigne qu'un écart dans sa marge est du bruit.
  - Supprimés : les vues séparées Séances | Lieux | Points (`PlacesLayerView`, `PointsLayerView`). L'écran d'un lieu ne change pas.

### À tester sur le téléphone (IPA `build/carte-3`)
- **Rapidité** : Plus → Analyses → Carte : la 2e ouverture montre les lieux tout de suite (la 1re après l'installation reste lente, le temps de garder les jours passés) ; toucher Stress : premier calcul un peu plus long, ensuite immédiat.
- **Fond** : carte sombre atténuée, sans commerces ni lieux publics (aussi dans le détail d'une séance).
- **Calques** : bouton Calques → Trajets, Lieux, Points allumés ensemble ; la légende suit ; éteindre / rallumer ; l'état est gardé en revenant.
- **Couleur** : FC, Stress, VFC, Récup, (Cadence) : les disques, leurs étiquettes et les points changent ; « Moins bien » / « Plus haute » en **orange**.
- **Plein écran** : bouton ↗︎ → carte entière, pastilles en bas, ✕ pour fermer ; la légende ne passe pas sous les pastilles.
- **Frise** : glisser le doigt → curseur sur la carte et heure + FC (ou stress) au-dessus de la frise ; ‹ › change de jour ; toucher un point de la carte → son heure sur la frise.
- **Ce qui ressort** : lignes avec le nombre de nuits ou de visites et « ± » ; « Rien ne ressort encore au-delà du bruit » sinon.
- **Captures à envoyer** : la carte avec les trois calques, le plein écran, la frise pendant un glissé, « Ce qui ressort ».

## Prompt de démarrage (pour une nouvelle conversation)
> Chantier 14 — Carte (fork NOOP). Lis `docs/fork/feuille-de-route.md`, puis `docs/fork/chantier-14-carte.md` (fiche du chantier : choix de Mohamed, code de l'étape 1, liste « À tester »). L'étape 1 (pas de l'iPhone toutes les 5 s, trajet coloré par zones FC ou par cadence, écran Carte dans Plus → Analyses) est sur la PR #102 / `main` selon son état. Prochaine étape : les retours de Mohamed sur l'IPA `build/carte`, puis l'étape 2 (Lieux, suivi continu réglable, autorisation « Toujours », défaut Équilibré · 15 min, pas depuis le point précédent) : maquette v1 https://claude.ai/artifact/KAiT8uvq4iWVKHeX4TY7uJ (écrans 3 à 7) à faire valider avant de coder ; stockage des lieux à trancher (migration iOS v54 / Android 45→46 ou stockage à part). Règles : `.claude/rules/fork-noop.md` (questions par l'outil à choix multiples, vérifications avant de pousser, IPA par `build/<nom>`).

## Maquette v1 (6 nov.) — à valider
Canvas « NOOP – Carte » — https://claude.ai/artifact/KAiT8uvq4iWVKHeX4TY7uJ. Style F, valeurs d'exemple. 8 écrans :
0 Feuille Plus (ligne **Carte** sous Tendances, « 6 séances › ») · 1 Carte · Séances (interactif : 30 J · 90 J · Tout, toucher une séance = elle seule sur la carte, barre des zones par séance) · 2 Carte d'une séance (trajet par zone, pic de FC entouré, temps par zone) · 3 Carte · Lieux (interactif : calques FC · Stress · VFC · Récup, pastilles bleu clair = mieux que ta normale, gris = proche, orange = moins bien, taille = nombre de visites, creuses = pas assez de données) · 4 Un lieu (écarts VFC, Récupération, Sommeil, FC, Stress ; barres des nuits ; « Oublier ce lieu ») · 5 Activer les Lieux (ce qui est enregistré, « Toujours », interrupteurs Suivre / Le Coach peut le lire / Dans la sauvegarde, Garder 1 an, Effacer) · 6 Suivi de position (interactif : mode, fréquence, plages, pause à l'arrêt) · 7 Carte · Points (interactif : FC · Stress, Jour · 7 J · 30 J).
Propositions : sélecteur **Séances | Lieux** sous le titre (Lieux absent tant que l'étape 2 n'est pas codée) ; écart affiché à partir de **3 nuits** (VFC, Récupération) ; couleurs bleu clair / orange (pas vert / rouge) ; la FC des séances est comptée à part dans le calque FC des Lieux.

## Points à trancher dans la maquette
- **Pas de 6e onglet** : iOS n'en montre que 5 (au 6e il crée « Plus » tout seul). Proposition : **Plus → Analyses → Carte**, à côté de Tendances ; la carte des séances aussi depuis Entraînement → Historique.
- Sélecteur de calque (FC · Stress · VFC · Récupération) et période (30 j · 90 j · Tout).
- **La VFC n'a de sens que la nuit** (WHOOP 4.0, au repos) : jamais de VFC « par position » pendant une séance.
- **Corrélations trompeuses** : un lieu reflète surtout ce qu'on y fait (salle = FC haute). Le texte dit « écart », jamais « cause ».
- Stockage des lieux (étape 2) : table SQLite = migration (iOS **v54** / Android **MIGRATION_45_46**, à revérifier) et parité des données stockées, ou stockage à part hors base comme `RouteStore` (iPhone seulement, à justifier) ; dans la sauvegarde `.noopbak` ou non.
- Fonds de carte MapKit : téléchargés chez Apple (déjà le cas pour la carte d'une séance) ; aucune position n'est envoyée.
