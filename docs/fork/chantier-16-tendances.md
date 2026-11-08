# Chantier 16 — Tendances : une vision de forme, pas six graphiques (8 nov. 2026)

**État** (8 nov., nuit) : maquette v1 **validée** par Mohamed (les deux graphiques, anneaux pour le Bilan) ; code + animations dans la **PR #128**, 6/6 verte sur sa tête 2fe0b9f ; **IPA `build/tendances`** = 2fe0b9f (release `ipa-build-tendances`) essayée et **validée par Mohamed le 8 nov. (nuit)** ; **#128 mise à jour avec `main`** (merge 1e589d7 : catalogue en union, feuille de route et règles gardant les deux chantiers, allocation d'échos fr laissée à 17) puis **fusionnée** (`main` **ca8b307**, 6/6 sur 1e589d7) ; **IPA `build/elan-2`** = `main` ca8b307 (release `ipa-build-elan-2`) = Élan (chantier 10, PR A–C) + Tendances, à installer et valider (liste « À tester » ci-dessous).

## La demande (8 nov., mots de Mohamed résumés)
- « Trop de graphiques » dans la section Tendances (Plus → Analyses → Tendances).
- Une vision **plus globale, plus scientifique, plus sportive**.
- Méthode : maquette → PR → IPA.

## Diagnostic (captures du 8 nov., 9 jours de données)
- 8 cartes, **6 graphiques** de 8 points chacun (Charge, VFC, FC repos, Effort, charge d'entraînement vide, calendrier annuel à 8 cases).
- La semaine résumée **deux fois** (3 jauges puis « Résumé de la semaine » en barres) : la règle d'`AGENTS.md` « deux lectures d'un même fait ne doivent pas pouvoir diverger ».
- **Deux horloges** : le ‹ › de la semaine (digest) et le sélecteur S · M · 3M · 6M · 1A · Tout (courbes) ne parlaient pas de la même période.
- Une phrase du moteur en anglais (« Last week only had 2 days of data… »).

## Maquette validée (8 nov.)
https://claude.ai/artifact/4EJDD4QCZReyLLe2vQsysZ — 3 planches : la page à 7 jours (données réelles de Mohamed), la même à 3 mois (modèle de forme actif), « ce qui part, où ça va ».

Réponses de Mohamed (outil à choix multiples) : **on code** ; **les deux graphiques** (nuage + Forme) ; **anneaux** pour le Bilan.

## Ce que fait le nouvel écran
Une seule période pour toute la page : pastilles **S · M · 3M · 6M · 1A** (« Tout » retiré de l'écran, gardé dans l'enum pour les cartes hôtes d'Aujourd'hui) + un ‹ › qui recule d'une période entière. Semaine = lundi–dimanche (comme le digest) ; les autres = blocs glissants finissant aujourd'hui. Puis cinq cartes :

1. **Bilan** (`TrendsBilanCard`) : Charge · Effort · Repos une fois (jauges `BevelGauge`), écart en % vs la période précédente, une phrase déterministe (`TrendsOverview.bilanReading` : période précédente trop courte < 3 j, les deux montent, Effort monte / Charge baisse, etc.). Partage en PNG par l'icône en haut à droite (même rendu que l'ancien « Partager le récap »).
2. **Équilibre Charge / Effort** (`TrendsBalanceCard`) : un point par jour, axes 0–100 stockés, coupés à **50** ; quadrants Optimal / Surmenage / Récupération / Sous-exploité ; compte par quadrant ; phrase par règle (≥ la moitié en surmenage, ≥ 40 % sous-exploité, ≥ la moitié optimal, sinon « réparti ») ; dernier jour cerclé de blanc.
3. **Forme** (`TrendsFormeCard`) : Condition (CTL 42 j) · Fatigue (ATL 7 j) · Forme (TSB) de `TrainingLoadEngine` sur **tout** l'historique ; le seul graphique de courbes (CTL bleu, ATL ambre, aire verte / ambre entre les deux) cadré sur la période ; ratio aigu / chronique et monotonie de `ReadinessEngine` (zone 0,8–1,3). Avant 14 jours contigus : tuiles « — », « Se construit · n / 14 » en pastilles, phrase « Encore n jours ». En anglais la tuile s'appelle **Fitness** (« Condition » en français).
4. **Signaux vs ta normale** (`TrendsSignalsCard`) : VFC, FC repos, Respiration, Temp. peau, Sommeil ; valeur = moyenne de la période ; **bande = moyenne ± ½ écart-type** sur une fenêtre plus longue (S → 30 j, M → 90 j, 3M → 180 j, 6M / 1A → 365 j), au moins 7 lectures sinon pas de bande ; axe de la ligne = moyenne ± 2 écarts-types ; pastille = écart vs période précédente (Sommeil : écart au **besoin** de `sleepSynthesisFigures`). Chaque ligne ouvre `MetricDetailView` (`TabRoute.metric`).
5. **Jour par jour** (`TrendsGridCard`) : grille 5 lignes (Charge, Effort, VFC, FC repos, Sommeil) × colonnes : jours (S), semaines lundi-alignées (M, 3M), mois (6M, 1A). Charge = dégradé de récupération, Effort = bleu par intensité, signaux = vert (mieux) / gris (dedans) / ambre (moins bien) vs la bande. Toucher une colonne affiche ses valeurs au-dessus.

Pied : deux lignes « Explorer une mesure › » (`TabRoute.metricExplorer`) et « Exporter le rapport › » (feuille PDF #436 inchangée).

## Animations (demande de Mohamed, 8 nov. après-midi : « il faut aussi ajouter des animations »)
Dans le langage du chantier 12 (jetons `NoopMotion`, briques `NoopFirstDraw` / `NoopRollingNumber`, rejeu à chaque affichage, rien au repos, tout coupé par Réduire les animations / `poseStill`) :
- **Page** : `noopEntranceRoot()` sur l'écran (les entrées rejouent à chaque arrivée sur Tendances et au retour d'une mesure) ; **chaque période est une nouvelle entrée** (`TrendsPeriodData.entranceKey` = plage + début de fenêtre) ; ‹ › fait glisser les cartes (`noopDaySlide(offset)`, 28 pt du côté d'où vient la période) avec une vibration `selection` ; le titre de la période fond ; un changement de plage anime les hauteurs (`NoopMotion.card`).
- **Bilan** : les trois arcs se tracent ensemble (`ringDraw`, 0,09 s d'écart) pendant que leurs chiffres comptent (`NoopRollingNumber` `.count` posé au centre du `BevelGauge`, label du gauge éteint) ; pastilles d'écart puis phrase en fondu.
- **Équilibre** : les points sont dessinés **au-dessus** du graphique (positions par `proxy.position(forX:)`), un par un du plus ancien au plus récent (50 ms d'écart, compressé pour qu'un trimestre tienne en ~1 s), échelle 0,2 → 1 ; le jour cerclé et son étiquette en dernier ; pastilles et phrase après le dernier point.
- **Forme** : Condition et Fatigue comptent, **Forme claque** (`.slam`, le chiffre principal de la carte) ; la courbe se trace de gauche à droite (`mask` sous `curveDraw`, 1,1 s) ; le point du ratio glisse du centre vers sa valeur ; en construction, les pastilles pleines s'allument en cascade.
- **Signaux** : le point de chaque ligne glisse du centre de la piste vers la lecture, ligne après ligne (0,06 s), la pastille d'écart fond derrière.
- **Jour par jour** : les cellules apparaissent colonne par colonne (35 ms, compressé pour 13 semaines), chaque ligne un souffle derrière ; la sélection (anneau blanc + ligne de lecture) suit `NoopMotion.value` avec une vibration `selection`.
- Rendu / tests : toutes les cartes dessinent l'état final quand `animated` est faux (par défaut) ; `TrendsView` passe `true`.

## Ce qui part
Digest hebdomadaire (jauges + ‹ › semaine), carte « Résumé de la semaine », courbe Charge, courbes VFC / FC repos / Effort, carte « Charge d'entraînement » (remplacée par Forme), calendrier annuel, grande carte Exporter. `WeeklyDigestView.swift`, `TrainingLoadCard.swift` et `TrainingLoadChart.swift` restent dans le dépôt (le digest sert ailleurs ; `TrainingLoadCard.modelKey` sert de clé de cache à Forme et a son test).

## Code
- `Strand/Data/TrendsOverview.swift` : la logique pure (fenêtres, période précédente, `maxOffset`, moyennes et écarts, quadrants et lecture, phrase du Bilan, bande personnelle, colonnes de grille, `civilDaysBetween`). Pas de jumeau Kotlin (iPhone seulement, aucune donnée stockée) ; le nom `civilDaysBetween` évite la collision lexicale avec `CyclePhaseEngine.daysBetween` du paquet (piège de parité de la feuille de route).
- `Strand/Screens/TrendsView.swift` (réécrit : période, `TrendsPeriodData`, `TrendsFormat`), `TrendsCardBits.swift` (ⓘ, en-tête, piste à bande, cellule), et les cinq cartes.
- `StrandTests/TrendsOverviewTests.swift` : 18 tests (semaine du 2–8 nov. des captures : 3 optimal / 4 surmenage, fenêtres, bande, colonnes, lecture du Bilan).
- 87 clés ajoutées au catalogue (10 langues) ; « Charge » / « Effort » traduits comme dans le reste du catalogue (Energie / Belastung, Carga / Esfuerzo…).
- Non compilé dans la session : `app-build.yml` sur la PR est la vérification.

## À tester (IPA `build/tendances`)
- Plus → Analyses → Tendances : S par défaut, « Cette semaine · 2–8 nov. · 7 / 7 jours » ; ‹ recule d'une semaine (« Semaine dernière »), › grisé sur la semaine en cours ; M / 3M / 6M / 1A : « 30 derniers jours », les dates après un ‹.
- Bilan : trois anneaux, pastilles « ↘ −15 % » colorées (Charge / Repos : vert si mieux, rose sinon ; Effort gris), phrase en français (période précédente à 2 jours → « les écarts sont indicatifs »). Icône partager en haut à droite → PNG du Bilan.
- Équilibre : 7 points, « aujourd'hui » cerclé, 4 pastilles de compte, phrase ; ⓘ en popover. Avec M / 3M les points sont plus petits.
- Forme : avec 9 jours → tuiles « — », 9 / 14 pastilles bleues, « Encore 5 jours… » ; **à partir du ~13 nov.** : tuiles chiffrées, courbe bleue / ambre, ratio avec sa zone verte, phrase monotonie.
- Signaux : 5 lignes, bande colorée, point gris si moins de 7 lectures (Respiration / Temp. peau selon la nuit), Sommeil « 7 h 10 · besoin 7 h 50 » avec pastille d'écart au besoin ; un tap ouvre la mesure.
- Jour par jour : L M M J V S D, D en blanc ; toucher une colonne → ligne « dim. 8 nov. · Charge 36 · Effort 53 · … » ; M → « Semaine par semaine » avec « nov. » au-dessus de la 1re semaine du mois ; 1A → « Mois par mois ».
- Pied : « Explorer une mesure » → Explorer ; « Exporter le rapport » → feuille PDF.
- Rien ne dépasse de l'écran en français (titres des cartes, pastilles).
- **Animations (en vidéo)** : à l'arrivée sur Tendances : les 3 arcs du Bilan se tracent et les chiffres comptent, les points du nuage tombent un à un (le cerclé en dernier), les pastilles 9 / 14 s'allument en cascade, les points des Signaux glissent ligne après ligne, la grille se remplit colonne par colonne. ‹ : les cartes glissent depuis la gauche et tout rejoue pour la nouvelle semaine ; › depuis la droite. Retour d'une mesure (tap sur une ligne des Signaux) : tout rejoue. Faire défiler et remonter : rien ne rejoue. Réduire les animations : tout est posé d'un coup, valeurs justes. Dès que la Forme est active : la courbe s'écrit de gauche à droite, le chiffre Forme claque, le point du ratio glisse.
