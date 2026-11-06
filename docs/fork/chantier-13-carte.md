# Chantier 13 — Carte (position et métriques) — fiche (6 nov. 2026)

**État** : idée retenue par Mohamed le 6 nov. ; **maquette v1 à valider** (6 nov.). Code : après Élan (chantier 10), un seul chantier de code à la fois.

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
