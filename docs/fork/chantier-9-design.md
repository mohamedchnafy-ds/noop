# Chantier 9 — lisibilité de l'app, section par section (4 nov. 2026)

But : que l'utilisateur ne soit pas perdu et voie l'information utile **au premier regard**. Moins de défilement pour trouver ce qui sert ; ce qui sert peu, ou dont on ne comprend pas le calcul, est rangé un niveau plus bas (accessible, mais pas sur l'écran principal).

Méthode (choix de Mohamed, revue le 4 nov.) : **d'abord la maquette complète de l'app**, section par section (artefact claude.ai par section → discussion → validation), **puis le code**, section par section, dans l'ordre ci-dessous. Exception : la navigation (section 1) est déjà codée (PR #61) ; elle sert de cadre aux autres maquettes. Au départ : une section à la fois, du design au code. État des lieux : captures du téléphone envoyées par Mohamed au fil des sections + rendus PNG de la CI (release `render-render-chantier-8`, 59 images ; ni Coach complet, ni écrans de Plus en détail, ni contrôles natifs).

## Décisions (4 nov.)
- **Barre d'onglets** : 5 onglets **Aujourd'hui · Entraînement · Nutrition · Sommeil · Coach**. **Plus** devient un bouton rond en verre **en haut à droite** de chaque écran (comme le profil de Santé / Fitness / App Store). iOS n'affiche que 5 onglets. L'onglet **Tendances** actuel (`TrendsView`, tag 1) quitte la barre : sa place (Plus → Analyses, ou Aujourd'hui) se décide dans la maquette de navigation.
- **Menu du Coach** (« fais-moi un programme nutrition ») : les repas sont ajoutés **comme des repas normaux** dans Nutrition (ils comptent tout de suite dans les anneaux et le bilan). **Plus de section « Prévu »** : Mohamed supprime ceux qu'il n'a pas mangés. À trancher au code : sort de la colonne `meal.planned` (#53) et des repas déjà prévus en base (aucune migration destructive ; les repas `planned` existants restent lisibles).
- **Aujourd'hui** (corrigé le 4 nov.) : la carte FC **reste comme aujourd'hui** (titre, En direct | Journée, courbe, Min / Moy. / Max) et le stress a **sa propre carte, juste sous la carte FC** (choix de Mohamed : une carte par mesure ; l'axe du temps du stress, 06:00–22:00, n'est pas celui de la FC). Titre « Stress › », niveau de l'heure en grand (« Modéré · 1,4 sur 3 »). Stress heure par heure 0–3 (`DaytimeStress`, points toutes les 30 min, 06:00–22:00), bandes Calme / Modéré / Élevé, heures « en mouvement » grisées, Élevé · Moy. · Pic, « Comment c'est calculé ».
- **Sommeil** : sur l'anneau, le coucher est aujourd'hui à droite et le réveil à gauche (sens horaire depuis le haut). À inverser (coucher à gauche, réveil à droite) ; la façon (sens de l'anneau ou ouverture en bas) se décide dans la maquette du Sommeil. Les deux libellés doivent rester attachés à leur vraie extrémité de la nuit.

- **Navigation, validée (4 nov.)** : bouton = **photo de profil** (l'avatar des Réglages) en haut à droite de chaque onglet ; Plus s'ouvre **en feuille** (OK ou glisser vers le bas, retour au même endroit) ; en-tête d'Aujourd'hui = **batterie · + · avatar** (« Personnaliser » descend en bas de l'écran, à côté des « Modifier ») ; **Tendances → Plus → Analyses** (première ligne).

## Réponses aux questions ouvertes (4 nov., matin)
- **PR #61 fusionnée** dans `main` (9652643). Pas d'IPA.
- **Ordre d'Aujourd'hui validé** : anneaux → Synthèse → carte FC (En direct | Journée) → carte Stress → Métriques (tuiles avec valeur) → Personnaliser.
- **Blocs qui quittent Aujourd'hui : déplacés ET réactivables**. Chacun vit à sa nouvelle place (Âge fitness, Vitalité → Plus → Santé et récupération ; Démarrer la séance Bêta → Entraînement → Autres activités ; Dernières séances → Entraînement ; Sources de données → Plus → Données ; tuiles sans valeur → Métriques → Toutes). « Personnaliser Aujourd'hui » a une section « Remettre sur la page » : un interrupteur par bloc, **éteint par défaut** ; allumé, le bloc s'affiche sous les Métriques (et reste à sa place habituelle). L'ancienne carte Stress « Calibration » est remplacée par la nouvelle carte Stress (pas d'interrupteur).
- Les 11 vieilles branches `build/*` / `feat/*` du 31 oct.–1er nov. (`sleep-redesign`, `superset-guided` 1 à 4, `superset-rounds`, `today-insights`) s'ignorent comme les autres (liste dans `.claude/rules/fork-noop.md`).

## Questions ouvertes
- Sommeil : voir la section 3 ci-dessous (en attente des réponses de Mohamed).

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

- **2 · Aujourd'hui (validée le 4 nov.)** : https://claude.ai/artifact/5Gtyju4onzwsH37moKvRZt — écran 1 la page (anneaux · Synthèse · carte FC En direct | Journée · carte Stress · Métriques avec valeur · Personnaliser), écran 2 ce qui quitte la page et où ça va, écran 3 la feuille « Personnaliser » (ordre glissable ; « Remettre sur la page » avec un interrupteur par bloc déplacé, éteints par défaut).

- **3 · Sommeil (proposition du 4 nov.)** : https://claude.ai/artifact/THF28w9AQZ2tAvyBEKkcKe — écran 1 la page proposée (touchez une phase), écran 2 les deux façons de mettre le coucher à gauche, écran 3 ce qui descend d'un niveau.
  - Ordre proposé : en-tête (Sommeil · alarmes · avatar), ‹ nuit › ; carte anneau (score Repos au centre, 4 phases en puces tactiles avec leur durée, Coucher / Réveil / Endormi, « Lire l'anneau » ⓘ) ; carte « Ce soir » (Visez ≈ besoin + dette, Coucher conseillé, Pourquoi ce sommeil ?, Ajouter une sieste) ; Phases de la nuit (puces FC / VFC / Temp. peau / Mouvement, hypnogramme, sans les 4 durées en double) ; Indicateurs (4 tuiles) ; Vos nuits (dette, 14 nuits | 30 jours) ; « Personnaliser Sommeil ».
  - Anneau proposé : **fer à cheval ouvert en bas** (coucher en bas à gauche, la nuit monte par la gauche, passe en haut, réveil en bas à droite ; sens d'une montre). Alternative : anneau complet en sens inverse (heures en haut).
  - Descend d'un niveau : les 2 lignes d'aide grises (→ ⓘ), les durées des phases en double (→ sous l'anneau seulement), Horloge biologique et la carte « Je me couche / Je me lève » (→ Personnaliser, éteintes par défaut) ; comparaison à la nuit habituelle (dès 5 nuits) et régularité du coucher (dès 3 nuits) restent conditionnelles.

## Code
- **Navigation (PR #61, fusionnée le 4 nov., `main` 9652643)** :
  - `StrandiOS/App/RootTabView.swift` : onglets `TabTag` 0 Aujourd'hui · 1 Entraînement (`LiftLogView`) · 2 Nutrition (`NutritionView`) · 3 Sommeil · 4 Coach (dernier, retiré si le Coach est désactivé). Plus n'est plus un onglet : **feuille** `moreSheet` (chemin `morePath`), ligne « Profil et réglages » (→ Paramètres) puis `MoreHubGroup.sheetGroups` (Santé et récupération, Analyses, Données, Réglages). **Tendances** = `MoreDestination.trends`, première ligne d'Analyses ; `router.openTrends()` ouvre la feuille dessus.
  - Une demande du routeur venue d'un écran **dans** la feuille : poussée dans la feuille si Plus a l'écran (`MoreDestination(routed:)`), sinon la feuille se ferme puis la demande est rejouée (une feuille ne peut pas en présenter une autre depuis le shell).
  - `Strand/App/TabShell.swift` : `\.showsMoreAvatar` (vrai seulement sur les racines d'onglet du shell iOS) + `MoreAvatarButton` (photo de profil → `router.openMore()`), et `TabRouteLink` + `\.tabRouteSwitch` : un lien d'Aujourd'hui vers `.liftLog`, `.nutrition` ou `.sleep` **change d'onglet** au lieu d'empiler une copie. Tout nouveau lien d'un écran racine vers un écran qui est un onglet passe par `TabRouteLink`. Hors shell (macOS, rendus) : rien ne change.
  - En-têtes : Aujourd'hui = batterie · + · avatar (« Personnaliser Aujourd'hui » en bas de l'écran) ; Entraînement = titre + avatar, puis Semaine | Mois avec ‹ ›, puis la période ; Nutrition = titre + Objectifs + avatar, puis ‹ jour › ; Sommeil et Coach = avatar après leurs boutons.
  - Widgets : tap Séance → onglet Entraînement, Nutrition → onglet Nutrition, Sommeil → onglet Sommeil (`openWidgetRoute`).
  - À tester sur le téléphone : les 5 onglets ; l'avatar sur chaque onglet ouvre Plus en feuille, OK la ferme ; Profil et réglages ; Tendances dans Analyses ; depuis Plus → Santé → Carnet de labo (ouverture dans la feuille) ; « Séance du jour » et la ligne Nutrition d'Aujourd'hui changent d'onglet ; Personnaliser Aujourd'hui en bas ; glisser entre onglets (pas sur Aujourd'hui) ; Coach désactivé → 4 onglets ; taps des widgets.
