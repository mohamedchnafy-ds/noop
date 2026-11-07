# Chantier 14 — Carte (position et métriques) — fiche (6 nov. 2026)

**État** : **étape 1 en code (7 nov.)**, PR #102, IPA `build/carte` à valider sur le téléphone. Le chantier de design « Instrument » (numéroté 13) a été abandonné le 6 nov. : pas de nouveau design à attendre, la Carte est codée en style F d'après la maquette v1 (choix de Mohamed, 7 nov.). Étape 2 (Lieux, suivi continu) : après la validation de l'étape 1.

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
