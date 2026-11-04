# Chantier 9 — lisibilité de l'app, section par section (4 nov. 2026)

But : que l'utilisateur ne soit pas perdu et voie l'information utile **au premier regard**. Moins de défilement pour trouver ce qui sert ; ce qui sert peu, ou dont on ne comprend pas le calcul, est rangé un niveau plus bas (accessible, mais pas sur l'écran principal).

Méthode (choix de Mohamed, revue le 4 nov.) : **d'abord la maquette complète de l'app**, section par section (artefact claude.ai par section → discussion → validation), **puis le code**, section par section, dans l'ordre ci-dessous. Exception : la navigation (section 1) est déjà codée (PR #61) ; elle sert de cadre aux autres maquettes. Au départ : une section à la fois, du design au code. État des lieux : captures du téléphone envoyées par Mohamed au fil des sections + rendus PNG de la CI (release `render-render-chantier-8`, 59 images ; ni Coach complet, ni écrans de Plus en détail, ni contrôles natifs).

## Décisions (4 nov.)
- **Barre d'onglets** : 5 onglets **Aujourd'hui · Entraînement · Nutrition · Sommeil · Coach**. **Plus** devient un bouton rond en verre **en haut à droite** de chaque écran (comme le profil de Santé / Fitness / App Store). iOS n'affiche que 5 onglets. L'onglet **Tendances** actuel (`TrendsView`, tag 1) quitte la barre : sa place (Plus → Analyses, ou Aujourd'hui) se décide dans la maquette de navigation.
- **Menu du Coach** (« fais-moi un programme nutrition ») : les repas sont ajoutés **comme des repas normaux** dans Nutrition (ils comptent tout de suite dans les anneaux et le bilan). **Plus de section « Prévu »** : Mohamed supprime ceux qu'il n'a pas mangés. À trancher au code : sort de la colonne `meal.planned` (#53) et des repas déjà prévus en base (aucune migration destructive ; les repas `planned` existants restent lisibles).
- **Aujourd'hui** (corrigé le 4 nov.) : la carte FC **reste comme aujourd'hui** (titre, En direct | Journée, courbe, Min / Moy. / Max) et le stress a **sa propre carte, juste sous la carte FC** (choix de Mohamed : une carte par mesure ; l'axe du temps du stress, 06:00–22:00, n'est pas celui de la FC). Titre « Stress › », niveau de l'heure en grand (« Modéré · 1,4 sur 3 »). Stress heure par heure 0–3 (`DaytimeStress`, points toutes les 30 min, 06:00–22:00), bandes Calme / Modéré / Élevé, heures « en mouvement » grisées, Élevé · Moy. · Pic, « Comment c'est calculé ».
- **Sommeil** : sur l'anneau, le coucher est aujourd'hui à droite et le réveil à gauche (sens horaire depuis le haut). À inverser (coucher à gauche, réveil à droite) ; la façon (sens de l'anneau ou ouverture en bas) se décide dans la maquette du Sommeil. Les deux libellés doivent rester attachés à leur vraie extrémité de la nuit.

- **Navigation, validée (4 nov.)** : bouton = **photo de profil** (l'avatar des Réglages) en haut à droite de chaque onglet ; Plus s'ouvre **en feuille** (OK ou glisser vers le bas, retour au même endroit) ; en-tête d'Aujourd'hui = **batterie · + · avatar** (« Personnaliser » descend en bas de l'écran, à côté des « Modifier ») ; **Tendances → Plus → Analyses** (première ligne).

## Questions ouvertes (à poser au début de la prochaine conversation)
- Fusionner la PR #61 (navigation, verte) maintenant, ou la garder ouverte jusqu'au code d'Aujourd'hui ?
- Ordre d'Aujourd'hui : anneaux → Synthèse → carte FC → carte Stress → Métriques ?
- Les blocs de « Ce qui quitte la page » (maquette Aujourd'hui, écran 2) : déplacés, ou masqués et réactivables dans « Personnaliser » ?

## Ordre proposé des sections
1. Navigation (barre d'onglets, bouton Plus, place de Tendances)
2. Aujourd'hui
3. Sommeil
4. Nutrition (dont le menu du Coach)
5. Entraînement
6. Coach
7. Plus et ses écrans (Santé et récupération, Analyses, Données, Réglages)

## Maquettes
- **1 · Navigation** : https://claude.ai/artifact/Rj7SsNJL3SrLpJmw8rPJx5 (Aujourd'hui, feuille Plus, Entraînement, Nutrition, barre d'onglets ; valeurs d'exemple). Proposition : avatar en haut à droite de chaque onglet → feuille « Plus » (profil + bracelet, Santé et récupération, Analyses avec Tendances, Données, Réglages) ; en-tête d'Aujourd'hui réduit à batterie · + · avatar (« Personnaliser » descend en bas de l'écran, à côté des « Modifier ») ; Entraînement et Nutrition à la racine de leur onglet, sans « ‹ Plus » ; Semaine | Mois sous le titre.

- **2 · Aujourd'hui** : https://claude.ai/artifact/5Gtyju4onzwsH37moKvRZt (proposition interactive : En direct | Journée ; et la liste de ce qui quitte la page). Ordre proposé : anneaux · Synthèse · carte FC · carte Stress · Métriques (tuiles avec valeur seulement) · Personnaliser. **FC « En direct » reste dans la carte** (choix de Mohamed). Quittent la page : carte Stress « Calibration » (→ nouvelle carte Stress), Âge fitness et Vitalité (→ Plus → Santé), Démarrer la séance Bêta (→ Entraînement), Dernières séances, Sources de données (→ Plus → Données), tuiles « pas de donnée ». En attente de validation.

## Code
- **Navigation (PR à venir, branche `claude/chantier-9-navigation`)** :
  - `StrandiOS/App/RootTabView.swift` : onglets `TabTag` 0 Aujourd'hui · 1 Entraînement (`LiftLogView`) · 2 Nutrition (`NutritionView`) · 3 Sommeil · 4 Coach (dernier, retiré si le Coach est désactivé). Plus n'est plus un onglet : **feuille** `moreSheet` (chemin `morePath`), ligne « Profil et réglages » (→ Paramètres) puis `MoreHubGroup.sheetGroups` (Santé et récupération, Analyses, Données, Réglages). **Tendances** = `MoreDestination.trends`, première ligne d'Analyses ; `router.openTrends()` ouvre la feuille dessus.
  - Une demande du routeur venue d'un écran **dans** la feuille : poussée dans la feuille si Plus a l'écran (`MoreDestination(routed:)`), sinon la feuille se ferme puis la demande est rejouée (une feuille ne peut pas en présenter une autre depuis le shell).
  - `Strand/App/TabShell.swift` : `\.showsMoreAvatar` (vrai seulement sur les racines d'onglet du shell iOS) + `MoreAvatarButton` (photo de profil → `router.openMore()`), et `TabRouteLink` + `\.tabRouteSwitch` : un lien d'Aujourd'hui vers `.liftLog`, `.nutrition` ou `.sleep` **change d'onglet** au lieu d'empiler une copie. Tout nouveau lien d'un écran racine vers un écran qui est un onglet passe par `TabRouteLink`. Hors shell (macOS, rendus) : rien ne change.
  - En-têtes : Aujourd'hui = batterie · + · avatar (« Personnaliser Aujourd'hui » en bas de l'écran) ; Entraînement = titre + avatar, puis Semaine | Mois avec ‹ ›, puis la période ; Nutrition = titre + Objectifs + avatar, puis ‹ jour › ; Sommeil et Coach = avatar après leurs boutons.
  - Widgets : tap Séance → onglet Entraînement, Nutrition → onglet Nutrition, Sommeil → onglet Sommeil (`openWidgetRoute`).
  - À tester sur le téléphone : les 5 onglets ; l'avatar sur chaque onglet ouvre Plus en feuille, OK la ferme ; Profil et réglages ; Tendances dans Analyses ; depuis Plus → Santé → Carnet de labo (ouverture dans la feuille) ; « Séance du jour » et la ligne Nutrition d'Aujourd'hui changent d'onglet ; Personnaliser Aujourd'hui en bas ; glisser entre onglets (pas sur Aujourd'hui) ; Coach désactivé → 4 onglets ; taps des widgets.
