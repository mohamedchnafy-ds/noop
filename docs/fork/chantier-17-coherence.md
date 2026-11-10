# Chantier 17 — Réglages, « Avancé » et les écrans oubliés (10 nov. 2026)

**État** (10 nov.) : **plan validé par Mohamed** (fiche dans `main` par la PR #135) ; **étape 1 fusionnée : PR #136, `main` 6b3a80d** (Stress avant la Synthèse), à valider sur le téléphone avec la prochaine IPA. Prochaine étape, dans une nouvelle conversation : la maquette de l'étape 2 (Réglages et feuille Plus).

Numéro : Mohamed a dit « chantier 16 » ; le 16 est déjà pris par Tendances (fusionné le 8 nov.), ce chantier est donc le **17**.

## La demande (10 nov., mots de Mohamed résumés)
- **Aujourd'hui** : après les anneaux et la fréquence cardiaque, mettre le **Stress avant la dette de sommeil** (la première ligne de la Synthèse).
- **Profil et réglages** (avatar → feuille Plus → carte profil) : « immense, on s'y perd » ; impossible de distinguer ce qui fait quoi, ce qui est utile, ce qui sert au sommeil, au sport, etc. **À voir en premier.**
- **Plus → Avancé** (Rythme, Explorer, Comparer…) : d'anciens affichages jamais mis à jour ; à reprendre **page par page** pour les rendre cohérents avec ce qui a été fait récemment.
- Chercher **ce qu'il a oublié** dans l'application.
- **Graphique personnalisé** sous le Stress d'Aujourd'hui (message du 10 nov., en cours d'audit) : choisir les variables, plusieurs types de graphe, zoom, axes (choix, inversion), échelle, animé. « L'utilisateur a la main sur ses données. »
- Méthode : **un plan solide, des maquettes solides, puis le code**. **Une conversation par étape**, chacune avec son prompt, sa maquette et ses modifications.

## Choix de Mohamed (10 nov., outil à choix multiples)
1. **Ordre d'Aujourd'hui** : anneaux → Fréquence cardiaque → **Stress** → Synthèse → Métriques.
2. **Les 15 écrans « Avancé »** : **trier et fusionner**. Les simples réglages vont dans Réglages ; les écrans vides pour lui quittent la feuille (le code reste) ; Explorer + Comparer deviennent le graphique personnalisé ; les deux « Perspectives » deviennent un seul écran « Journal » ; la prévision d'Intelligence va dans Tendances. « Avancé » disparaît presque.
3. **Graphique personnalisé** : **une carte sur Aujourd'hui + un atelier en plein écran**. La carte montre le graphique enregistré (animée, touchable pour lire une valeur) ; un tap ouvre l'atelier (mesures, type, période, zoom, axes, échelle), où l'on enregistre plusieurs graphiques. Pas d'éditeur ni de zoom à deux doigts dans la page qui défile.
4. **Écrans oubliés** : les **quatre lots** entrent dans le chantier (Santé · Stress · FC en direct ; Progression et fiches de séance ; Alarmes · Respirer · Labo · Données ; passe de cohérence des textes).

## Ce que l'audit a trouvé (code de `main` ca8b307, 10 nov.)

Constat commun aux trois audits : **les vieux écrans ont déjà le fond noir, les cartes plates et la casse normale** (jetons aplatis au chantier 7, passe #41). Ce qui fait « ancien », c'est la **composition** : jauges « liquides » (`LiquidVessel`, `LiquidTube`), fond `ScenicHeroBackground`, grilles de `StatTile`, `ChartCard` + `TrendChart`, pastilles `StatePill`, sur-titres `SectionHeader(…, overline:)`, longs paragraphes dans les cartes, plusieurs sélecteurs de période par écran, vouvoiement, aucune entrée animée. Le nouveau style (Tendances, Jeûne, Élan, feuille Plus) : `noopEntranceRoot()`, `NoopRollingNumber` / `NoopFirstDraw`, ⓘ en popover (`TrendsCardHeader`), **une seule période par page**, Swift Charts direct et touchable, une phrase courte par règle.

### Réglages (`Strand/Screens/SettingsView.swift`, 3 187 lignes)
- **55 lignes** visibles « Avancé » replié, **69** déplié, **37 paragraphes** de plus de 120 caractères. Plus d'un tiers de l'écran est de l'explication.
- **Le rangement ne suit pas les domaines** : l'interrupteur du Coach est dans « Apparence » ; l'**objectif de calories d'activité** (le seul endroit où il se règle) est dans « Avancé → Experimental · Liquid Today » ; la carte « Série » n'est pas un réglage.
- **Deux lignes dangereuses** : « Liquid Today (prototype) » éteint ramène l'ancien écran Aujourd'hui (non refondu) ; « Couleurs des graphiques → Classique » recolore les phases de sommeil (contre « violets partout »).
- **Sans effet ou hors sujet pour un WHOOP 4.0 sur iPhone sideloadé** : Calibration des pas (compteur que le 4.0 n'envoie pas), Suivi de l'hydratation (l'eau se note déjà dans le Jeûne), « Graphiques de tendance » (lu par Explorer seulement, plus par Tendances), « Données Apple Watch », les mentions Apple Santé.
- **Trois lignes pointent vers upstream** (`ryanbr/noop`) : Rechercher les mises à jour, Vérifier automatiquement, Page du projet. Une « mise à jour disponible » proposerait un build sans les ajouts du fork.
- **Libellés qui prêtent à confusion** : deux « Diagnostics », « Calibration des pas » / « Estimation des pas », « Échelle d'effort » / « Effort : échelle exponentielle ».
- **Doublons** : journal du bracelet (Réglages, Centre de test, FC en direct), recalibrage de la Charge (Réglages, Centre de test), Re-scan / Déconnecter (Réglages, FC en direct), sauvegarde en fichier (Réglages) contre sauvegarde en dossier (Plus → Sauvegarde), Réglages atteignable par 5 entrées.
- **Les réglages vivent aussi ailleurs**, dans une vingtaine d'endroits : Personnaliser (Aujourd'hui, Sommeil, Entraînement, Nutrition), Objectifs de Nutrition, Rappels, rappels du Jeûne, Alarmes, Sauvegarde, Sources de données, Réglages du Coach (3 écrans), Lieux et suivi de position, Économie d'énergie, Automatisations, Centre de test, Export Raccourcis, Siri. **Quatre systèmes d'heures calmes** distincts (Rappels 21:30–07:00, alertes au poignet 22:00–07:00 non réglable sur iPhone, Lieux 23:00–07:00, rappel d'inactivité).

### Les 15 écrans « Avancé »
| Écran | Utile pour Mohamed | Ce qu'on en fait (choix 2) |
|---|---|---|
| Rythme | partiel (expérimental, nuage R-R) | quitte la feuille ; reste accessible par Automatisations → à trancher dans la maquette de l'étape 4 |
| Explorer | oui | devient l'**atelier** du graphique personnalisé (étape 3) ; sa fiche d'une mesure est refaite avec |
| Comparer | partiel (défaut « poids » vide : il lit `apple-health`, pas `noop-weight`) | fusionné dans l'atelier (étape 3) |
| Ce qui te fait bouger | partiel (s'intitule « Perspectives » à l'écran) | fusionné dans **Journal** (étape 4) |
| Intelligence | partiel | la **prévision de la Charge de demain** va dans Tendances ; la liste par jour (= grille « Jour par jour ») part (étape 4) |
| Perspectives | oui : **c'est l'écran du Journal**, cible de tous les accès « Journal » | refait et renommé **Journal** (étape 4) |
| Données fusionnées | non (une seule source) | quitte la feuille ; masquer aussi la ligne de Santé |
| Apple Santé | partiel (pas de HealthKit en sideload : deux paragraphes « ne peut pas se connecter ») | fusionné dans Sources de données (étape 7) |
| Mi Band | non | quitte la feuille |
| Export Raccourcis | partiel (un interrupteur) | dans Réglages (étape 2) |
| Limites de NOOP | partiel (tableau statique, une colonne sur deux pour le 5 / MG) | dans Réglages → Aide (étape 2) |
| Automatisations | oui (9 groupes de vrais réglages du bracelet) | dans Réglages → Bracelet, refait (étape 2) |
| Siri et Raccourcis | partiel (« Demander au Coach » manque : 3 actions montrées sur 4) | dans Réglages (étape 2) |
| Économie d'énergie | oui | dans Réglages → Bracelet (étape 2) |
| Centre de test | partiel (diagnostic) | un lien dans Réglages → Aide ; reste utilitaire |

« Quitte la feuille » = la ligne disparaît de `MoreSheetEntry`, **le code de l'écran reste** (aucune suppression de fichier sans accord).

### Les écrans oubliés (hors Réglages et « Avancé »)
- **Fiche d'une mesure** (`MetricDetailView`, dans `MetricExplorerView.swift`) : ouverte par chaque tuile d'Aujourd'hui, chaque ligne Signaux de Tendances et le lien « Analyses › » du Coach. Le plus vieil écran sur le chemin le plus fréquenté (jauge liquide, 8 périodes, vieux graphique).
- **Stress** (`StressView`) : fiole « sur 3 », 8 périodes, aujourd'hui seulement alors que la carte d'Aujourd'hui navigue dans les jours.
- **Santé** (`HealthView`) : titre « Moniteur de santé », 8 sections empilées, bloc Synchro en tête, FC en direct en double, liens vers Carnet de labo et Données fusionnées déjà dans Plus.
- **FC en direct** (`LiveView`) : « Console corporelle en direct », « Confiance du signal », fiole de bpm. **Courbe de la journée** (`FullDayChartView`) : « Chronologie détaillée », dates en anglais.
- **Progression** (`LiftProgressView`, `LiftExerciseProgressView`) : aucune entrée animée, période propre. **Fiche d'une séance** (`LiftSessionDetailSheet` : section RPE alors que Mohamed ne note pas le RPE) et **détail d'une séance cardio** (`WorkoutDetailView` : tuiles, fiole d'Effort, « of 21 »).
- **Alarmes** et **Respirer** (hero scénique, vouvoiement), **Carnet de labo** (sur-titres, fiole de corrélation), **Sources de données** (8 cartes à paragraphes dont Xiaomi, Oura, diffusion FC), **Sauvegarde** (titre « Backup & Sync » différent de la ligne Plus), **eau et caféine dans le Jeûne** (deux vieux écrans dans une page refaite).
- Petits : Intervalles (« ROUND »), `ManualWorkoutSheet` (durée écrite à la main), écrans du Coach (réglages, profil, données, historique), blocs remis du Sommeil (tube liquide), partage de Tendances (second choix de période), Guide des scores / Comment ça marche / Nouveautés (celles d'upstream).

### Incohérences qui traversent l'app
- **Cinq sélecteurs de période** : Tendances S · M · 3M · 6M · 1A ; Stress et fiche d'une mesure 8 options (`ExploreRange`) ; Historique 7J · 30J · 90J · 1A · Tout ; Progression 4 / 12 semaines ; Carnet de labo `LabWindow`.
- **Couleur de la VFC** : cyan dans Aujourd'hui et Santé, violet dans Tendances et la fiche d'une mesure.
- **Couleurs du stress** : vert / jaune / rouge sur la carte d'Aujourd'hui, bleu / vert / ambre dans l'écran Stress (« Calme » est vert d'un côté, bleu de l'autre).
- **Tu / vous** : 814 valeurs françaises du catalogue vouvoient, 242 tutoient.
- **Formats** : durées « 7h 12m » (Santé, Intelligence, séance passée), dates brutes « 2026-11-08 » (Intelligence), dates en anglais (courbe de la journée), point décimal forcé (eau, Respirer), « of 21 ».
- **Titres qui ne correspondent pas à leur entrée** : Santé → « Moniteur de santé », FC en direct → « Console corporelle en direct », Sauvegarde → « Backup & Sync », carte FC → « Chronologie détaillée », deux écrans « Perspectives ».
- **Anglais dans l'interface française** : phrases des effets, du coût d'activité et de la dose-réponse fabriquées en anglais dans `Packages/StrandAnalytics` (`BehaviorInsights`, `EffectRanker`, `DoseResponseEngine`) ; questions de départ du Journal (`JournalCatalog`) ; « Merge » / « Delete » de l'Historique ; carte Haptique d'Automatisations ; légende des Limites ; notification du brief. 190 littéraux signalés par `i18n_audit --full` (dont des libellés VoiceOver).
- **Code présent mais inatteignable sur iPhone** : l'ancien `TodayView` (5 980 lignes, sauf par l'interrupteur « Liquid Today »), `WeeklyDigestView`, `MoreGroupScreen` / `MoreRow`, `CoachBriefWidget`, `NotificationSettingsView` (macOS). À laisser, sauf accord pour supprimer.
- **Notifications hors budget** : batterie, maladie, objectif d'effort et inactivité (Automatisations) partent hors du `ReminderPlanner` du chantier 10. À trancher dans l'étape 2 (les y faire entrer ou les laisser comme alertes).

## Règles communes à toutes les étapes
- **Une seule période par page**, sur le modèle de Tendances : pastilles S · M · 3M · 6M · 1A + ‹ ›. Un écran qui a une bonne raison d'en avoir une autre (Historique, Progression) le dit dans sa maquette.
- **Une couleur par mesure, partout**. À trancher une fois, dans la maquette de l'étape 3 (l'atelier affiche toutes les mesures côte à côte) : VFC cyan ou violet ; stress = les couleurs de la carte d'Aujourd'hui (`StrandPalette.stressCalm` / `stressModerate` / `stressHigh`).
- **Plus de** `LiquidVessel`, `LiquidTube`, `ScenicHeroBackground`, grilles de `StatTile`, `ChartCard` + `TrendChart` dans un écran refait. Graphiques en Swift Charts direct, touchables, tracés par `NoopFirstDraw` ; chiffres par `NoopRollingNumber` ; racine `noopEntranceRoot()`. Règle « pas de filtre au repos » de la feuille de route.
- **Les explications passent en ⓘ** (popover, `TrendsCardHeader`) ; dans la page, une phrase courte au plus.
- **Tutoiement**, durées « 3 h 23 min », virgule décimale, dates localisées, titre de l'écran = libellé de son entrée.
- **Un réglage vit à un seul endroit** ; un autre écran qui en a besoin y met un lien, pas une copie (règle d'`AGENTS.md` « deux lectures d'un même fait »).
- **Phrases du moteur** : la mise en mots se fait côté app (comme `TrendsOverview.bilanReading`), pas dans `Packages/StrandAnalytics`, pour ne pas toucher à la parité Kotlin.
- **Rien n'est supprimé sans accord** : un écran qui quitte la feuille garde son fichier ; un réglage retiré de l'écran garde sa clé stockée.
- Aucune donnée stockée nouvelle n'est prévue, sauf les graphiques enregistrés de l'étape 3 (UserDefaults sur l'appareil, hors `.noopbak` par défaut ; à confirmer dans sa maquette). Android : inchangé (écrans iPhone seulement), sauf si une clé entre dans la liste blanche du `.noopbak`.

## Plan : une conversation par étape
Chaque étape : lire cette fiche → **maquette** (artefact claude.ai, planches « l'écran », « ce qui part, où ça va ») → questions en un lot (outil à choix multiples) → validation → **code** (une préoccupation par PR, depuis `main`) → CI verte → fusion → mise à jour de cette fiche et de la feuille de route. **IPA** : quand Mohamed le dit ; proposée après les étapes 2, 3 et 5.

| # | Étape | Maquette | Contenu | PR prévues |
|---|---|---|---|---|
| 1 | **Aujourd'hui : Stress avant la Synthèse** | non | `TodayLayoutPrefs.liquidV5Order` appliqué une fois (`today.liquidLayoutV5`), ne déplace que le Stress ; `liquidDefaultOrderRaw` suit ; test. Part de `main` ; la PR #134 (elle touche `LiquidTodayView.swift`) attend la validation de Mohamed, le conflit éventuel se règle à sa fusion. | 1 |
| 2 | **Réglages et feuille Plus** | oui | Réglages rangés **par domaine** (Profil et corps · Bracelet · Sommeil et récupération · Sport · Aujourd'hui · Coach · Notifications et rappels · Apparence et langue · Données · Aide et à propos), une ligne = un libellé clair + sa valeur, explication en ⓘ, recherche en tête ; lignes dangereuses, sans effet ou d'upstream retirées de l'écran ; absorbe Économie d'énergie, Automatisations, Siri, Export Raccourcis, Limites, Centre de test. Feuille Plus : « Avancé » réduit à ce qui reste, lignes vides retirées. | 2 à 3 (structure de Réglages ; écrans absorbés ; feuille Plus) |
| 3 | **Mon graphique** (atelier + carte d'Aujourd'hui) | oui | Atelier plein écran : mesures du catalogue (sans les sources vides, sans doublons anonymes), types courbe / barres / aires / nuage de points, période, zoom et déplacement, axe gauche / droite, échelle auto / fixe / inversée, normalisation, lecture au doigt ; graphiques enregistrés ; carte « Mon graphique » sous le Stress (nouvelle section d'Aujourd'hui). **Remplace Explorer et Comparer** ; la **fiche d'une mesure** est refaite sur le même moteur (elle reste la cible des tuiles, de Signaux et du Coach). Couleur par mesure tranchée ici. | 3 (moteur + atelier ; carte d'Aujourd'hui ; fiche d'une mesure) |
| 4 | **Journal, prévision, Rythme** | oui | Perspectives + Ce qui te fait bouger → un écran **Journal** (saisie, effets, dose-réponse ; phrases en français côté app) ; prévision de la Charge de demain dans Tendances ; sort de Rythme et d'Intelligence. | 2 |
| 5 | **Santé · Stress · FC en direct · courbe de la journée** | oui | Santé resserrée et renommée ; Stress aligné sur la carte d'Aujourd'hui (couleurs, jours passés, une période) ; FC en direct sans jargon ; courbe de la journée. | 2 à 3 |
| 6 | **Progression et fiches de séance** | oui | Progression, fiche d'un exercice, fiche d'une séance de muscu (sans RPE), détail d'une séance cardio. | 2 |
| 7 | **Alarmes · Respirer · Labo · Données** | oui | Alarmes, Respirer, Carnet de labo, Sources de données (+ Apple Santé fusionné, cartes Xiaomi / Oura retirées de l'écran), Sauvegarde (un seul écran pour fichier et dossier), eau et caféine du Jeûne, petits écrans (Intervalles, séance passée, Coach). | 3 |
| 8 | **Passe de cohérence des textes** | non | Tutoiement dans le catalogue français, phrases anglaises restantes, formats de durée et de date, capitales restantes. Une liste avant / après à valider avant la PR. | 1 à 2 |

Ordre : celui de la demande (Réglages d'abord, puis « Avancé » page par page), le graphique personnalisé en 3 parce qu'il règle le sort d'Explorer et de Comparer et fixe les couleurs des mesures que les étapes 4 à 7 réutilisent.

## Prompts de démarrage (un par conversation)

**Étape 1**
> Fork NOOP — chantier 17, étape 1. Lis `.claude/rules/fork-noop.md`, `docs/fork/feuille-de-route.md`, puis `docs/fork/chantier-17-coherence.md`. Code : sur Aujourd'hui, la carte Stress passe avant la Synthèse (anneaux → FC → Stress → Synthèse → Métriques) par une migration d'ordre v5 appliquée une fois, qui ne déplace que le Stress ; test ; PR vers `main`. Pas de maquette, pas d'IPA.

**Étape 2**
> Fork NOOP — chantier 17, étape 2 : Réglages et feuille Plus. Lis `.claude/rules/fork-noop.md`, `docs/fork/feuille-de-route.md`, puis `docs/fork/chantier-17-coherence.md` (audit des Réglages, tableau des 15 écrans « Avancé », règles communes). D'abord la **maquette** (artefact, 3 planches : Réglages rangés par domaine avec une section dépliée, la feuille Plus après le tri, « ce qui part, où ça va » ligne par ligne), puis tes questions en un seul lot. Le code seulement après ma validation.

**Étape 3**
> Fork NOOP — chantier 17, étape 3 : Mon graphique. Lis `.claude/rules/fork-noop.md`, `docs/fork/feuille-de-route.md`, puis `docs/fork/chantier-17-coherence.md` (choix 3, étape 3) et le code d'Explorer, de Comparer et de `CoachChartCard`. D'abord la **maquette animée** : la carte « Mon graphique » sous le Stress, l'atelier plein écran (mesures, type, période, zoom, axes, échelle, graphiques enregistrés), la fiche d'une mesure refaite, et la couleur de chaque mesure. Questions en un lot, code après validation.

**Étapes 4 à 8** : même forme — « chantier 17, étape N : <titre du tableau> », lire les trois fiches, la maquette d'abord (sauf l'étape 8 : la liste avant / après), questions en un lot, code après validation.

## Étape 2 : code de Réglages et de la feuille Plus (10 nov. 2026)
Maquette validée par Mohamed (« go », 10 nov.) : https://claude.ai/artifact/MKquxtH5nZ2mzzyhqDDbkX (planches 1, 1b, 1c, 2, 3 ; la planche 3 donne le sort de chaque ligne). Trois PR, une préoccupation chacune :
1. **Structure de Réglages** : `SettingsDomain` (10 domaines en accordéon, un seul déplié à la fois), recherche en tête, ⓘ en popover (`TrendsInfoButton`), `SettingsView(opening:)`, registre de lignes `settingsRows(_:)` (la recherche ne trouve que les lignes visibles avec le bracelet connecté). Lignes retirées de l'écran, clés stockées gardées : Couleurs des graphiques (l'app lit toujours « Par défaut »), Graphiques de tendance, Liquid Today (l'app lit toujours « allumé »), Hydratation, Données Apple Watch, Nouveautés, Rechercher les mises à jour, Vérifier automatiquement, Page du projet, carte Série (la ligne revient dans Tendances › Bilan, PR 3). Les écrans non refaits (Alarmes, Rappels, Coach ×3, Lieux, Sources, Sauvegarde, Stockage, Centre de test) s'ouvrent par des liens ; Économie d'énergie, Automatisations, Siri, Ce que NOOP lit, Export Raccourcis ouvrent encore leur ancien écran jusqu'à la PR 2.
2. **Écrans absorbés refaits** : Automatisations (groupes « Alerte »), Économie d'énergie, Siri et Raccourcis (+ « Demander au Coach »), Ce que NOOP lit (liste du bracelet actif), Export Raccourcis en ligne dans Données, lien Rythme dans Automatisations.
3. **Feuille Plus** (« Avancé » 15 → 6 écrans) + ligne Série dans Tendances › Bilan.
**État (10 nov.)** : PR 1 #137, PR 2 et PR 3 ouvertes (branches `claude/laughing-fermat-phluu0`, `-p2`, `-p3`, empilées ; fusionner dans l'ordre). Après la PR 3, la feuille Plus compte « Avancé · 6 écrans » (Explorer, Comparer, Ce qui te fait bouger, Intelligence, Perspectives, Apple Santé) ; les 9 autres (`MoreSheetEntry.leftTheSheet`) gardent leur fichier. La ligne Série est dans Tendances › Bilan (`TrendsBilanCard.streak`).
Écarts assumés de la PR 1 : la valeur « 06:04 » des Alarmes (en-tête Sommeil et ligne) n'est pas encore lue ; un résultat de recherche s'ouvre par un tap sur le nom de son domaine (pas de défilement jusqu'à la ligne) ; la phrase d'accroche de « À propos » est retirée.

## Journal
- **10 nov.** : demande de Mohamed, trois audits du code (Réglages ; les 15 écrans « Avancé » ; le reste de l'app), quatre choix, plan en 8 étapes. Trouvé en avance sur `main` : la PR #134 (`build/animations-4`, un commit d'animations), choix de Mohamed : elle attend sa validation de l'IPA `build/animations-4`, l'étape 1 part de `main`. Fiche mise dans `main` par une PR de documentation ; étape 1 codée dans la même conversation, les suivantes dans une conversation chacune.
- **10 nov., étape 1 (PR #136)** : `TodayLayoutPrefs.liquidV5Order` retire le Stress de l'ordre enregistré et le replace juste avant la Synthèse ; appliqué une fois (`today.liquidLayoutV5`, `LiquidTodayView.applyLayoutV5IfNeeded`, après v2, v3, v4) ; `liquidDefaultOrderRaw` (page neuve et « Réinitialiser » de Personnaliser) donne anneaux → FC → Stress → Synthèse → Métriques. Une carte Stress masquée reste masquée (la visibilité est stockée à part). Test `testLayoutV5PutsStressAboveSynthesisAndKeepsTheRest`. Aucune clé de traduction, aucune donnée stockée nouvelle ; Android inchangé (ordre du Liquid Today, iPhone seulement).

## À tester (prochaine IPA)
- **Étape 1** : Aujourd'hui dans l'ordre anneaux → Fréquence cardiaque → Stress → Synthèse → Métriques, sans rien toucher ; Personnaliser Aujourd'hui → l'ordre montre Stress au-dessus de Synthèse ; un ordre que tu as changé toi-même ailleurs est gardé ; si tu redescends le Stress à la main, il y reste aux lancements suivants.

## Journal (suite)
- **10 nov., fusion de l'étape 1** : sur la tête 870f26b de la PR #136, 4 vérifications sur 5 vertes (build iOS, i18n, lint, Tools Python) ; la jambe macOS + StrandTests annulée deux fois sans runner (`macos-15` saturé, `runner_id` 0, aucune étape). Choix de Mohamed : **preuve Intel**. Branche temporaire `ci/c17-step1-intel` (tête de la PR + `tmp-c17-step1-intel.yml`, jamais fusionnée, à supprimer sur accord) : build macOS vert, **2 926 StrandTests, 0 échec, 2 ignorés** (sans les 14 classes de rendu, sans `-testLanguage fr`) sur `macos-15-intel`. #136 fusionnée (`main` 6b3a80d).
