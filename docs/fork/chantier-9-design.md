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
- Coach : questions posées avec la maquette 6 (en attente).

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

- **3 · Sommeil (validée le 4 nov.)** : https://claude.ai/artifact/THF28w9AQZ2tAvyBEKkcKe — écran 1 la page (touchez une phase ; Anneau | Courbes), écran 2 la forme de l'anneau, écran 3 ce qui descend d'un niveau.
  - **Anneau en fer à cheval, ouvert en bas** (choix de Mohamed) : coucher en bas à gauche, la nuit monte par la gauche, passe en haut et redescend jusqu'au réveil en bas à droite (sens d'une montre) ; chaque heure collée à sa pastille.
  - **Un seul graphique** (idée de Mohamed) : une carte de la nuit avec un sélecteur **Anneau | Courbes**. Anneau par défaut ; Courbes = l'hypnogramme actuel avec les puces FC / VFC / Temp. peau / Mouvement et le plein écran. Les **4 durées des phases restent fixes en haut** de la carte, dans les deux vues (toucher une phase la montre seule) ; elles ne sont plus affichées deux fois. ⓘ remplace les 2 lignes d'aide grises. Coucher / Réveil / Endormi en bas de la carte.
  - **« Ce soir » quitte la page** (choix de Mohamed : information jugée peu pertinente, elle prenait trop de place ; une étape « petits boutons » a été essayée puis retirée) : « Ce soir, visez… » et « Pourquoi ce sommeil ? » vont dans « Personnaliser Sommeil », éteints par défaut, réactivables ; « Ajouter une sieste » devient une ligne d'action de cette feuille. Le coucher conseillé reste sur Aujourd'hui (Synthèse).
  - Sélecteur **Anneau | Courbes en haut de la carte** (ⓘ et plein écran à droite).
  - **« Vos nuits » en barres empilées** (idée de Mohamed, 4 nov.) : une barre par nuit, Profond en bas · Paradoxal · Léger, ligne de besoin (8 h), 14 nuits | 30 jours. **Éveillé hors de la barre** (hauteur = temps endormi, comparable au besoin et à la dette). En tête : **Moyenne endormi** en grand, **Dette** à droite. **Toucher une barre** : la nuit s'affiche en tête de carte (date, endormi, chaque phase, éveillé) avec « Voir cette nuit › » qui remonte l'anneau sur elle ; retoucher = retour à la moyenne. Une nuit sans phases (données partielles) : barre grise unie.
  - Ordre : carte de la nuit → Indicateurs (4 tuiles ; Régularité du coucher dès 3 nuits) → Vos nuits (dette, 14 nuits | 30 jours) → « Personnaliser Sommeil ».
  - **Horloge biologique et carte « Je me couche / Je me lève » rangées** dans « Personnaliser Sommeil », éteintes par défaut, réactivables (choix de Mohamed). Comparaison à la nuit habituelle : dans la vue Courbes, dès 5 nuits.

- **4 · Nutrition (validée le 4 nov., tout comme proposé)** : https://claude.ai/artifact/Q58frnJhvdY33LrWE9Qhug — écran 1 la page, écran 2 ce qui change.
  - Ordre proposé : en-tête (Nutrition · Objectifs · avatar), ‹ jour › ; carte anneaux (Mangé, Protéines, Glucides, Lipides) avec en bas **Reste / Dépensé / Bilan** (« Objectif » quitte la ligne : il est déjà écrit à côté de Mangé) ; **barre compacte** Saisir · Scanner · Photo · Dicter ; Repas ; carte **« Cette semaine »** (moyenne + 7 barres, tap → écran Historique avec les 3 graphiques et 7 j | 30 j) ; « Personnaliser Nutrition ».
  - Menu du Coach : repas normaux avec une étiquette « Coach » ; plus de section Prévu (décision du 4 nov.).
  - Carte « Bilan sanguin » : Plus → Santé → Carnet de labo, et réactivable dans Personnaliser (éteinte par défaut).

- **5 · Entraînement (validée le 4 nov., tout comme proposé)** : https://claude.ai/artifact/Y7mFfZxPcVt32RzjohHTxW — écran 1 la page, écran 2 ce qui change.
  - Ordre proposé : en-tête (Entraînement · avatar) ; Semaine | Mois, ‹ 2–8 nov. · 1 / 5 › ; bande des 7 jours (légende sur **une ligne** : muscu · cardio · ● fait ○ prévu) ; **une carte « Aujourd'hui »** (séance de muscu en grand : nom, durée, dernière fois, 2 lignes d'exercices, **charge à monter du jour**, Démarrer / Changer ; puis le cardio prévu en ligne avec son Démarrer) ; Progression compacte (4 compteurs, tap → écran Progression) ; Programmes (+ Planifier, Nouveau, Importer) ; Autres activités (Démarrer une activité, Intervalles, FC en direct, Tout l'historique, + **Démarrer la séance Bêta** venue d'Aujourd'hui = coaching silencieux du bracelet face à la Charge) ; Personnaliser.

## Code
- **Navigation (PR #61, fusionnée le 4 nov., `main` 9652643)** :
  - `StrandiOS/App/RootTabView.swift` : onglets `TabTag` 0 Aujourd'hui · 1 Entraînement (`LiftLogView`) · 2 Nutrition (`NutritionView`) · 3 Sommeil · 4 Coach (dernier, retiré si le Coach est désactivé). Plus n'est plus un onglet : **feuille** `moreSheet` (chemin `morePath`), ligne « Profil et réglages » (→ Paramètres) puis `MoreHubGroup.sheetGroups` (Santé et récupération, Analyses, Données, Réglages). **Tendances** = `MoreDestination.trends`, première ligne d'Analyses ; `router.openTrends()` ouvre la feuille dessus.
  - Une demande du routeur venue d'un écran **dans** la feuille : poussée dans la feuille si Plus a l'écran (`MoreDestination(routed:)`), sinon la feuille se ferme puis la demande est rejouée (une feuille ne peut pas en présenter une autre depuis le shell).
  - `Strand/App/TabShell.swift` : `\.showsMoreAvatar` (vrai seulement sur les racines d'onglet du shell iOS) + `MoreAvatarButton` (photo de profil → `router.openMore()`), et `TabRouteLink` + `\.tabRouteSwitch` : un lien d'Aujourd'hui vers `.liftLog`, `.nutrition` ou `.sleep` **change d'onglet** au lieu d'empiler une copie. Tout nouveau lien d'un écran racine vers un écran qui est un onglet passe par `TabRouteLink`. Hors shell (macOS, rendus) : rien ne change.
  - En-têtes : Aujourd'hui = batterie · + · avatar (« Personnaliser Aujourd'hui » en bas de l'écran) ; Entraînement = titre + avatar, puis Semaine | Mois avec ‹ ›, puis la période ; Nutrition = titre + Objectifs + avatar, puis ‹ jour › ; Sommeil et Coach = avatar après leurs boutons.
  - Widgets : tap Séance → onglet Entraînement, Nutrition → onglet Nutrition, Sommeil → onglet Sommeil (`openWidgetRoute`).
  - À tester sur le téléphone : les 5 onglets ; l'avatar sur chaque onglet ouvre Plus en feuille, OK la ferme ; Profil et réglages ; Tendances dans Analyses ; depuis Plus → Santé → Carnet de labo (ouverture dans la feuille) ; « Séance du jour » et la ligne Nutrition d'Aujourd'hui changent d'onglet ; Personnaliser Aujourd'hui en bas ; glisser entre onglets (pas sur Aujourd'hui) ; Coach désactivé → 4 onglets ; taps des widgets.
