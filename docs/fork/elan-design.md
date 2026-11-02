# Élan (section motivation) — fiche du chantier (2 nov. 2026, ~12:50)

**État** : idées discutées, choix faits (2 nov., widget). **Maquette faite, à valider** (2 nov. ~12:50). Code : après la PR C des widgets (un seul chantier de code à la fois). À ajouter à la feuille de route quand le chantier démarre.

## Maquette
Canvas « NOOP – Élan » — https://claude.ai/artifact/TbB76NkVtT8wegLJmaH8oQ (slug d7531eec-7643-48ac-8d8e-04bc190f9a4f). Valeurs d'exemple. Styles repris des canvas Aujourd'hui (fond #1D1E23, cartes #2A2C34 / bord #373A44, rayon 22–26, police arrondie, titres de section 12 px espacés), Coach (carte Séance, bouton #3A7F6D, barre d'onglets) et Entraînement (titre 34 px, retour « ‹ Plus »).
Artboards : 1 Élan · écran · 2 Mon pourquoi · écrire · 3 Rappels d'Élan · 4 Notification · lendemain d'un raté · 5 Aujourd'hui · carte Élan (3 cas) · 6 Séance courte · préparée par le Coach · 7 Avant / maintenant · 8 Pesée du matin · première fois · 9 Poids · tendance · 10 Lectures (Du jour | Les essentiels, interactif) · 11 Lecture du jour.

### Propositions de la maquette (à valider par Mohamed)
- **Accès** : écran ouvert depuis Plus (« ‹ Plus ») ; **carte ÉLAN dans Aujourd'hui**, après la Synthèse et avant « Démarrer une session », seulement quand il y a quelque chose : lendemain d'un raté (Séance courte / Pas aujourd'hui), pesée du matin pas encore notée, record.
- **Ordre de l'écran** : Aujourd'hui (alerte « Jamais deux fois de suite ») → Mon pourquoi → Avant / maintenant → Poids → Lecture du jour → Les essentiels → Victoires → Rappels.
- **Couleurs** : Élan = accent menthe #69DDB8 ; poids = violet #9B7BFF (celui de Vitalité, jeton à vérifier) ; Nutrition tenue = doré activité ; muscu = bleu Effort ; lectures par thème (Cœur rose, Sommeil bleu, Nutrition doré, Entraînement bleu clair).
- **Mon pourquoi** : texte + photo facultative (gardée sur l'iPhone), 4 aides (« Comment je veux me sentir dans 6 mois », « Ce que je veux pouvoir faire », « Ce que je ne veux plus vivre », « Pour qui je le fais ») ; affiché en haut d'Élan le lendemain d'un raté et après 3 jours sans séance. Vocal : non dessiné.
- **Rappels** : au plus **1 par jour** (choix 1 par jour / 4 par sem. / 2 par sem.) ; silence 21:30–07:00 ; lendemain d'un raté (18:00, séance courte) ; 1 h avant une séance prévue (**heure des séances réglée dans Planifier** : donnée nouvelle du planning) ; après 3 jours sans séance ; pesée du matin 07:30 (**compte à part** de la limite) ; repas non notés à 21:00 (désactivé par défaut) ; bilan du dimanche 19:00. Priorité le même jour : raté > séance prévue > 3 jours sans séance.
- **Notification** (écran verrouillé) : « Full body B est passée hier » + « 20 minutes ce soir suffisent pour garder le rythme » ; actions Séance courte · 20 min / Pas aujourd'hui. Pesée : « 30 secondes, avant de manger. Seule ta tendance compte. »
- **Séance courte** : les 2 premiers supersets du programme manqué, charges de la dernière fois, ≈ 20 min, carte Séance du Coach (Démarrer / Au Carnet), « Faite ce soir, elle compte dans ta semaine : 2 / 3 », lien « Ajuster avec le Coach ».
- **Avant / maintenant** : meilleure période de 4 semaines des 6 derniers mois (« lancé ») vs 3 dernières semaines : séances / sem., séries / sem., records, Nutrition tenue (j / 7), nuit moyenne ; barres des séances sur 12 semaines (bleu = lancé, gris = ces 3 semaines) ; « Ce que tu as construit » (1RM estimé et gain des exercices clés, comme Progression) ; « Ce qui revient vite » + lien vers la lecture mémoire musculaire + Séance courte.
- **Pesée** : saisie au clavier + −/+ 0,1 kg ; « Le matin, avant de manger » ; première pesée = « C'est ton point de départ », aucune comparaison, **tendance après 5 pesées** (1 / 5) ; encadré sur les variations d'eau ; Poids visé.
- **Poids** : message après une pesée plus haute (« Pesée notée. Une pesée seule bouge surtout avec l'eau… ») ; tendance (chiffre lissé + courbe, sans points de pesée), période 4 sem. / 12 sem. / Tout, rythme, reste, date estimée ; **Jours Nutrition tenus sur les 7 derniers jours** (point doré = tenu, rond creux = pas tenu, trait = aucun repas noté ; **tenu = à 10 % près de l'objectif d'apport**) ; Poids visé ; rappel de pesée.
- **Lectures** : onglets Du jour | Les essentiels ; filtres Tout / Sommeil / Cœur / Nutrition / Entraînement ; non lue (point menthe), lue, favori (étoile) ; champ « Fais-moi le tour de… » + « Le Coach cherche sur des sites de santé fiables et cite ses sources ». Essentiels groupés (Cœur : VFC, FC au repos, SpO2, respiration ; Sommeil et récupération : phases, dette, Charge et Effort ; Nutrition : déficit, protéines) avec le chiffre de l'utilisateur à droite.
- **Lecture** : thème + « lecture du jour », titre, « 4 min · préparée ce matin par le Coach · 3 sources », raison du choix, L'essentiel en 3 points, 3 sections avec renvois [1] [2] [3], **Pour toi** (ses chiffres), **À essayer**, **Sources** numérotées (liens), « Synthèse écrite par le Coach à partir de ces sources. Ce n'est pas un avis médical. », bouton « Poser une question au Coach ».

## Problème
Les coups de mou : plus envie d'aller à la salle ni de bien manger. Pour Mohamed, c'est la partie la plus importante et la plus négligée.
Constat : un jour sans motivation, on n'ouvre pas un écran « Motivation ». La section doit donc **venir à lui** (rappels, carte dans Aujourd'hui, widget) ; l'écran range tout.

## Choix de Mohamed (2 nov., ~12:15)
- Forme : **écran Élan + rappels** (notifications, carte dans Aujourd'hui, widget).
- Ton quand il décroche : **chiffres + porte de sortie** (« avant 3 séances/sem, là 1 » + séance courte proposée).
- Blocs v1 : **Avant / maintenant** (+ victoires), **Mon pourquoi**, **Objectif de poids**, **Lectures** (ex-« Fiches science »). **Séance courte après un raté** : incluse d'office.
- Maquette : « vraiment homogène avec l'application » (2 nov., ~12:35).

## Poids — la peur de la pesée (2 nov., ~12:30)
Mohamed ne se pèse pas régulièrement, par peur de ne pas avoir perdu entre deux pesées et de se démotiver (il est déjà resté un an sans se peser). Il sait que la pesée est importante pour suivre l'objectif.
Explication retenue : deux pesées isolées sont dominées par les variations d'un jour à l'autre (eau, sel, glucides, digestion, séance de la veille) ; plus on se pèse souvent, moins une pesée compte. Études de Steinberg et al. (2013, Obesity ; 2014, Am J Prev Med, NCT01369004) : pesée quotidienne + courbe = plus de perte de poids, sans effet psychologique négatif par rapport au groupe témoin ; les effets varient selon les personnes.
**Choix (widget)** :
- Affichage : **tendance seulement**. Jamais l'écart entre deux pesées ; la courbe apparaît après quelques pesées.
- Rythme : **chaque matin** (avant de manger), rappel discret.
- Repère en plus du poids : **jours Nutrition tenus**. Pas de tour de taille ni de photos pour l'instant.
- Balance : **classique** → saisie à la main dans l'app (il voit le chiffre sur la balance ; l'app ne le lui renvoie pas, ni de comparaison).
Principes : la première pesée = point de départ ; une pesée plus haute → message prêt d'avance, jamais « +x kg » ; la force rappelle que le corps change même quand la balance bouge peu.

## Lectures (2 nov., ~12:40)
Mohamed aime avoir des sujets à lire : sommeil et santé, régime, FC, VFC, SpO2… qui expliquent et montrent l'impact et les bienfaits, renouvelés chaque jour grâce au Coach qui va sur Internet.
**Deux étages** :
1. **Les essentiels** (embarqués, hors ligne) : écrits une fois, chaque source vérifiée par recherche web, aucune référence inventée ; chaque fiche affiche ses chiffres.
2. **La lecture du jour** (Coach + recherche web de l'API Anthropic) : synthèse en français rangée dans Élan, sources en liens cliquables.
**Choix (widget)** : sujet = **ses données d'abord**, sinon un de ses thèmes à tour de rôle ; préparée **à l'ouverture d'Élan** ; **sites fiables seulement** (`allowed_domains` : PubMed / PMC, Inserm, HAS, Anses, OMS… liste à arrêter) ; thèmes **Sommeil, Cœur, Nutrition et régime, Entraînement et récupération** ; aussi depuis une conversation (« Fais-moi le tour de la SpO2 » → carte Lecture « Ranger dans Élan »).
**Garde-fous** : tout chiffre sourcé (citations de l'API) ; synthèse, jamais de paragraphes recopiés ; pas de diagnostic ; Anthropic seulement (autres fournisseurs : essentiels seuls).
**Technique** : outil serveur `web_search` (`web_search_20250305` ou plus récent), `max_uses` ~5, `allowed_domains` (exclusif avec `blocked_domains`) ; citations toujours renvoyées (`web_search_result_location` : url, title, cited_text ≤ 150 car.), chaque citation affichée renvoie vers sa source ; 10 $ / 1 000 recherches + tokens (mesurer sur un premier article) ; désactivable par l'admin de l'org Anthropic (erreur 400 → message clair). Requête hors conversation sur le modèle d'`AICoachEngine.estimateMeal` (ex. `writeReading`) ; stockage local (table + migration v52 ou fichiers comme `CoachPhotoStore`) et `.noopbak` à décider ; consignes propres aux lectures (pas le rôle « sans digresser »).

## Principes (issus de la recherche)
- Un raté isolé ne casse pas une habitude ; ce sont les ratés à la suite (Lally et al., 2010) → « jamais deux fois de suite », pas de série de jours qui retombe à 0.
- Méga-étude sur des adhérents de salles de sport (Milkman et al., 2021, Nature) : l'intervention la plus efficace récompensait le retour après une séance manquée → le moment clé est le lendemain d'un raté.
- Intentions de mise en œuvre (Gollwitzer) : décider quand et où → une heure dans le planning, un rappel avant.
- La culpabilité nourrit le « foutu pour foutu » → toute comparaison négative vient avec une action facile.
- Raisons personnelles > citations génériques (théorie de l'autodétermination).

## Technique (à vérifier dans le code avant de coder)
- Notifications locales (UNUserNotificationCenter) ; pas de push serveur en sideload. Préparées quand l'app tourne (synchro du bracelet en arrière-plan).
- Messages par règles + modèles traduits (10 langues) ; le Coach seulement sur un tap ou à l'ouverture d'Élan (lecture du jour).
- Repérage du décrochage : `TrainingWeekPlan.planDecision`, `TrainingDays.buildTrainingDays`, `MealJournal`, `Repository.sleepSynthesisFigures`, `LiftProgress` ; séance courte via `create_program` (carte Séance).
- Poids : regarder ce qui existe (profil, métrique Poids, import Apple Santé par raccourci) avant toute nouvelle table (sinon migration iOS v52 / Android MIGRATION_43_44, parité). Le poids du profil (Coach, objectifs Nutrition) devrait suivre la tendance — à décider.
- « Jour Nutrition tenu » : `NutritionDayReader.currentPlan`, `NutritionDaySummary` ; un jour sans repas noté n'est ni tenu ni raté.
- Heure des séances dans le planning (`training.weekPlan.v1`) : extension du JSON, compatible avec les plannings déjà enregistrés.

## Reste à trancher
- Validation de la maquette (captures / retours de Mohamed) et des propositions ci-dessus.
- Liste des essentiels de la v1 et des domaines autorisés ; langue des textes générés.
- Place exacte de l'écran dans Plus (nouveau groupe ou dans Entraînement).
