# Chantier 18 — La séance de musculation et l'écran Entraînement

Fiche ouverte le 11 nov. 2026. État : **maquettes validées, code en cours** : lot A fusionné (A1 #142, A2 #143, `main` 42e56cc) ; lot B en cours (B1 #144, B2 #145 fusionnées, `main` b900d39 ; PR B3 : Régularité) ; voir « Chantier 18 — le code ».

## Méthode (choix de Mohamed, 11 nov.)
- Une maquette par sujet, puis **une maquette globale** ; validation, puis fin de chantier définie.
- Code en **lots** (une préoccupation par PR, fusion dès que la CI est verte) ; **une seule IPA** pour les lots A, B et C ; la détection de fin de série (lot D) en **IPA séparée**, après test sur le bracelet.
- Le tour des chantiers a été fait avant les maquettes (section « Repris d'autres chantiers »).

## Les changements, dans l'ordre prévu

### 1. Le poids se répète d'une série à l'autre (lot A)
- Le poids saisi sur la série 1 se répète sur les séries 2, 3, 4… tant que l'utilisateur n'en saisit pas un autre.
- Un poids changé à une série devient celui des séries suivantes ; les séries déjà faites ne bougent pas.
- **Règle propre à chaque exercice** : un nouvel exercice ne reprend rien du précédent ; le poids de sa série 1 se répète sur ses séries.

### 2. Saisie rapide en séance (lot A)
- Problème : toucher la case, taper la valeur, puis régler répétitions et repos prend trop de temps.
- Le cas courant = **un tap** : série préremplie (poids du 1, répétitions de la dernière séance ou de l'objectif, repos de l'exercice), on touche « fait ».
- Pour corriger : **roulette** sans clavier (poids par 0,5 kg, répétitions de 1 en 1) et boutons − / + pour un cran.
- Le repos se lance seul à la validation, avec la durée habituelle de l'exercice.
- Grandes zones de tap. **Palier réglable par exercice** (barre 2,5 kg, haltère 1 ou 2 kg) : à trancher dans la maquette.

### 3. Écran Entraînement épuré (lot B)
- Constat (capture du 11 nov.) : trop d'éléments empilés (Semaine | Mois, flèches, bande des 7 jours, légende, carte du jour, Progression, Programmes, Nouveau, Importer, Démarrer une activité) ; doublons (« 1 / 1 », « 1 prévue · 1 faite », légende) ; Progression occupe une carte pour quatre zéros.
- Base de la maquette : l'écran répond à « que fais-je aujourd'hui ? ». Bande de la semaine compacte, légende dans un « i » ; **séance du jour en grand** avec Démarrer ; **Progression en une ligne seulement quand elle a quelque chose à dire** ; Programmes / Nouveau / Importer derrière une ligne « Programmes › » ; « Démarrer une activité » fusionné avec la feuille « Démarrer » ; Historique en une ligne avec la dernière séance.
- Recoupe l'étape « Progression et fiches de séance » du chantier 17 : traitées ensemble (voir plus bas).

### 4. Courbe de FC et comparaison (lot A)
- Courbe de FC sur **tous les écrans de musculation** (feuille de séance, séance en cours, fiche d'une séance terminée), comme en cardio.
- Cardio et musculation : **2 ou 3 courbes des dernières séances du même type** (même programme / même sport), alignées sur le temps écoulé, discrètes, **masquables**. Moyenne et max à côté.

### 5. Ce qui influence mes séances (lot C)
- Vue « Ce qui influence mes séances » : sommeil, eau (avant et pendant), café, protéines, charge de la veille… comparés à des mesures de séance (FC moyenne à effort comparable, récupération de FC, charge soulevée, Effort, VFC de la nuit suivante).
- Chaque utilisateur est comparé à lui-même ; **seuil minimum de séances**, écart et nombre de séances affichés, « pas encore assez de données » avant ; jamais « X cause Y » : « chez toi, on observe… ».
- **Fonction expérimentale**, désactivable (règle d'AGENTS.md : pas de signal non validé comme acquis).
- Saisie nouvelle : **eau pendant la séance, d'un tap**. Le Coach peut expliquer les résultats.

### 6. (à venir : les prochains changements de Mohamed s'ajoutent ici)

### 7. Détection automatique de la fin de série (lot D, dernier, IPA séparée)
- Détection depuis le mouvement du bracelet (la FC réagit trop tard) ; marge de **5 à 6 s** sans mouvement (réglable dans 5–10 s).
- **Désactivée par défaut.** Option désactivée : l'app **propose** la fin de série mais **ne l'arrête pas** (le chrono continue) et note ce qu'elle aurait fait. Option activée : à la fin de la marge, la série s'arrête et le repos démarre ; annulable pendant la marge.
- **Repères de l'utilisateur** : il indique début et fin de chaque série ; ils servent de vérité de terrain pour régler la détection sur lui et corriger. Tout reste sur l'appareil. À trancher : repères à chaque série ou seulement pendant une phase d'apprentissage ; entrée ou non dans le `.noopbak`.
- Les données de mouvement du WHOOP 4.0 sont rares (#345) : d'abord enregistrer sans agir ; validation obligatoire sur le bracelet en séance réelle.

## Repris d'autres chantiers (choix de Mohamed, 11 nov.)
- **Progression** (chantier 17, étape « Progression et fiches de séance ») + bloc **Régularité** (séries par semaine sur 12 semaines, calendrier) : traités avec l'écran Entraînement.
- **Élan PR D** : lecture du jour (Coach + recherche web `web_search`, stockage des lectures, « Fais-moi le tour de… »). Détail dans `elan-design.md`.
- **Animations reportées** (chantier 12) : barre de séance réduite, éditeur par blocs, Progression, carte du corps et autres effets listés dans `chantier-12-animations.md`.
- **Restent dans leur fiche** : chantier 17 étapes 3 à 8 hors Progression, Coach (cache de prompt + 10 questions test), restes de la refonte, validations sur le téléphone des IPA `elan`, `elan-2`, `jeune-2`, `carte-3`, `animations-3`, `animations-4`.

## Maquettes et décisions

### Maquette 1 — saisie rapide et poids répété (11 nov.) : **validée**
- Lien : https://claude.ai/artifact/JkydKpfVF7QC1Np1isCFwG (source : `docs/fork/maquettes/chantier-18-1-saisie-rapide.html`).
- Choix de Mohamed : correction par **roulette sans clavier + boutons − / +** ; **palier par exercice avec valeur par défaut devinée** (barre 2,5 kg, haltère 1 kg, machine 5 kg), réglable d'un tap et retenu ; **repos lancé seul** à « Fait » (− 15 s, + 15 s, Passer) ; **série en cours en grand** avec les autres séries en liste compacte dessous.

### Maquette 2 — écran Entraînement épuré (11 nov.) : **validée**
- Lien : https://claude.ai/artifact/Tp2M6d8EEMATwo2MxKusD3 ; source `docs/fork/maquettes/chantier-18-2-entrainement.html`.
- Choix de Mohamed : **bande de 7 jours compacte**, légende dans un « i », **Mois** par un bouton calendrier ; **« Programmes › »** regroupe liste, Nouveau, Importer, Planifier ; **Progression** en une ligne seulement s'il y a une charge à monter, **Régularité** dans l'écran Progression ; **« Autre séance »** ouvre la feuille Démarrer.
- Rappel de Mohamed : **la fréquence cardiaque doit apparaître en musculation** (courbe sur la carte d'une séance faite et dans l'historique de cet écran ; feuille de séance, séance en cours et fiche terminée dans la maquette 3, avec la comparaison aux dernières séances).

### Maquette 3 — FC en musculation (11 nov.) : **validée**
- Remarque de Mohamed : la maquette 2 ne montrait la FC qu'après la séance ; elle doit être visible **pendant** l'entraînement.
- Lien : https://claude.ai/artifact/6FQ5eUz4vDz7RDeUUaVTxE ; source `docs/fork/maquettes/chantier-18-3-frequence-cardiaque.html`.
- Choix de Mohamed : **bandeau FC sous le nom de l'exercice** (FC en direct, zone, courbe des 10 dernières minutes avec repos ambrés et fin de série marquée) ; **comparaison** = 2 dernières séances du même programme (cardio : même sport) en pointillés, interrupteur « Comparer » ; **chiffres** : moyenne, max, zone de FC, **récupération entre séries** (baisse pendant le repos). Fiche terminée : courbe complète, temps par zone, FC moyenne par exercice.

### Maquette 4 — ce qui influence mes séances (11 nov.) : **validée**
- Lien : https://claude.ai/artifact/P75GuGrAZ228vR9kEqmotf ; source `docs/fork/maquettes/chantier-18-4-influences.html`.
- Choix de Mohamed : **bloc dédié dans l'écran Progression** (Expérimental, désactivable) ; **une carte par facteur** avec phrase déterministe « chez toi, on observe… », barres avec / sans, écart et nombre de séances ; **seuil 6 séances par groupe, 12 au total** (avant : « pas encore assez de données » + barre vers le seuil) ; **eau en séance** par un bouton « + verre » (25 cl) dans la barre de repos, total sur la fiche terminée.

### Maquette 5 — fin de série automatique, lot D (11 nov.) : **validée**
- Lien : https://claude.ai/artifact/Btt9NmKtquw9ZAgQc7YDRA ; source `docs/fork/maquettes/chantier-18-5-fin-de-serie.html`.
- Choix de Mohamed : réglage dans **Paramètres › Entraînement, section Expérimental** (éteint par défaut, marge 5–10 s, 6 s par défaut) ; pendant la marge, **compte à rebours + Annuler** ; option éteinte = l'app propose « Fin de série ? » et note ce qu'elle aurait fait ; **repères** : phase d'apprentissage de **10 séries** (boutons Début / Fin), puis la détection tourne seule, relançable ; sur l'appareil, hors `.noopbak`.

### Maquette globale — parcours de la séance (11 nov.) : en attente de validation
- Lien : https://claude.ai/artifact/5yrUL69fFHYHRSZomiMLus ; source `docs/fork/maquettes/chantier-18-6-parcours.html`. Réunit les maquettes 1 à 5 en 4 écrans : Entraînement, séance en cours, fiche terminée, Progression ; chaque écran indique le lot d'où vient chaque élément.

- **Ajout d'exercices depuis l'écran Entraînement (remarque de Mohamed, 11 nov.)** : on doit pouvoir ajouter ce qu'on veut à la séance du jour sans changer d'onglet. Choix : bouton **« + Exercice »** sur la carte du jour, à côté de Démarrer ; la carte a une **liste d'exercices dépliable** (nom, séries × reps, charge ; ↑ pour monter, − pour retirer ; étiquette « Aujourd'hui » sur un ajout) ; l'ajout vaut **pour aujourd'hui seulement**, le programme reste intact, et la question existante « mettre à jour le programme ? » de fin de séance propose de le garder ; l'ajout passe par une **feuille avec recherche, récents, filtre par muscle**, séries / reps / charge repris de la dernière séance, « Nouvel exercice » et « Superset… » en bas. Ajouté au lot B (code) ; à passer par les mêmes résolveurs que la séance courte d'Élan (items d'un jour).

## Sans maquette, dans le code (choix de Mohamed, 11 nov.)
Pas de maquette supplémentaire. Ces points se codent directement, en suivant le style des maquettes validées et les jetons du design system, et Mohamed valide sur captures :
- **Lot B** : refonte de l'écran Progression, bloc **Régularité** (séries par semaine sur 12 semaines, calendrier), fiches de séance (chantier 17, étape « Progression et fiches de séance »), **« + Exercice »** dans la séance en cours (même feuille que sur la carte du jour).
- **Après A, B, C** (quand on en a besoin, une PR chacune) : **Élan PR D** (lecture du jour, Coach + recherche web, détail dans `elan-design.md`) ; **animations reportées** du chantier 12 (barre de séance réduite, éditeur par blocs, Progression, carte du corps).

## Chantier 18 — le code

### Lot A, PR A1 : poids répété et saisie rapide (11 nov.)
Branche `claude/magical-franklin-hhb7rv`, partie de `main` e8ab909 (choix de Mohamed : coder depuis `main` sans attendre #141 « Mon graphique » ; la fiche entre dans `main` avec cette PR).
- **Poids répété** : `LiftSessionEngine.carry` a deux chaînes. Le **poids** d'une série = celui de la série de travail d'avant du même exercice (saisi une fois faite, saisi d'avance dans `pendingValues`, sinon son gris) ; la série 1 = le premier poids de travail de la dernière séance, sinon la cible du programme. Les **répétitions** gardent la chaîne d'avant (série faite d'avant, même série la dernière fois, cible). Un échauffement est sauté par la chaîne et garde le poids de sa série la dernière fois. Chaque exercice a sa chaîne.
- **« Les séries faites ne bougent pas »** : un poids donné à la série n ne remonte jamais aux séries d'avant. La règle « le gris reste gris » d'upstream est gardée : une série faite **sans poids saisi** suit encore une correction faite à une série **d'avant** (test existant `testCorrectingAnEarlierSetMovesTheGreyNumbersAfterIt`). La dernière séance en pyramide (60, 62,5, 65) donne donc 60 partout.
- **Carte de saisie rapide** (`LiftQuickEntryCard`, vue pure) dans la carte de l'exercice, au-dessus de la liste des séries : « Série n sur N », « La dernière fois : 60 × 8 », Poids et Réps en grand avec − / +, un tap sur le chiffre ouvre la **roulette** (`LiftNumberWheelSheet`, `Picker` en `.wheel` sur iOS), bouton **Palier**, bande de repos avec **−15 s / +15 s / Passer**, gros bouton **« Série terminée »** (la clé existante, comme la bannière ; « Démarrer la première série » pendant l'échauffement). La carte se tient sur `LiftSessionEngine.quickEntrySlot` : la série en cours, sinon celle qui suit pendant le repos. Pas de carte pour un superset (ses écrans guidés restent).
- **Un tap depuis le repos** : `completeQuickSet` enregistre la série suivante d'un coup ; elle est datée du **bout du repos** s'il est fini, sinon de **maintenant** (jamais avant la fin du repos) ; une seule étape d'annulation. Le repos suivant démarre seul, avec la durée de l'exercice.
- **Le gros bouton de la barre du bas** est caché quand la carte est là (une action par moment) ; Reprendre (pause) et Terminer restent. La bande de repos entre deux lignes est cachée aussi (le repos est dans la carte). Le défilement suit la série de la carte.
- **Palier par exercice** : `LiftWeightStep` (UserDefaults `lift.weightStep.v1`, nom d'exercice → kg ; 1, 2, 2,5, 5 kg en boucle), deviné par le nom (haltère / dumbbell → 1 kg, machine / poulie / câble / tirage / presse… → 5 kg, sinon barre 2,5 kg). Réglage de l'appareil, **hors `.noopbak`** (pas de jumeau Android). Le pas de la règle de progression (`LiftProgression`, « ↑ 62,5 kg ») **ne change pas**, pour que la séance, Entraînement et le Coach ne se contredisent pas. − / + retombent sur la grille du palier (61 → 62,5 → 65).
- Tests : `StrandTests/LiftQuickEntryTests.swift` ; `testLastSessionIsUsed…` attend 52,5 kg en série 3 (nouvelle règle).

### Lot A, PR A1 fusionnée (12 nov.)
- **#142** fusionnée (`main` 040ab3f), 6/6 sur sa tête (macOS + StrandTests, iOS, Android, Tools, doc, linux-capture). La branche `claude/magical-franklin-hhb7rv` repart de `main` pour A2 (choix de Mohamed : « fais le mieux »).

### Lot A, PR A2 : fréquence cardiaque en séance, sur la fiche et en cardio (12 nov.)
- **Calcul pur** `LiftHeartRateMath` : courbe par seaux (10 s en séance, comme la séance cardio), **récupération** d'une série = pic de FC du début de la série à 10 s après sa fin, moins le plus bas pendant son repos (repos ≥ 20 s ; le repos en cours se lit jusqu'à maintenant) ; **comparaison** = courbes des séances d'avant posées sur le **temps écoulé** depuis leur début (les pauses ne sont pas retirées : c'est un repère, pas une mesure) ; FC moyenne par exercice sur ses propres séries. Rien n'est stocké, rien ne nourrit un score.
- **Bandeau en séance** (`LiftLiveHeartRateBand`) au-dessus de la carte de saisie rapide (sous le nom de l'exercice) et sous les tuiles des écrans de superset : ♥ bpm, zone (`hrZoneSet`, la même que les tuiles), « en série » / « récup. », courbe des 10 dernières minutes avec les repos en ambre et un trait à la fin de chaque série, les **2 dernières séances du même programme** en pointillés gris, interrupteur « Comparer aux 2 dernières séances » **mémorisé** (`lift.hr.compare`, partagé avec le cardio), puis Moyenne · Max · Récup. (en cours, sinon la dernière). Relecture des échantillons toutes les 10 s ; séances d'avant lues une fois (programme identique, 120 jours). Séance libre : pas de comparaison. Sans FC : « En attente de la fréquence cardiaque du bracelet. » Sur les écrans de superset, la **moyenne n'est pas répétée** (déjà dans la tuile kcal : deux lectures du même fait, deux rafraîchissements).
- **Fiche terminée** (`LiftSessionHeartRateSection`, section « Fréquence cardiaque » sous les chiffres) : courbe de toute la séance (≈ 120 points), comparaison, Moyenne · Max · Récup. moyenne (sans en-tête : la moyenne n'est dite qu'une fois), temps par zone (5 segments + minutes), FC moyenne par exercice.
- **Cardio** : la courbe des 10 dernières minutes de la séance en direct dessine les **2 dernières séances du même sport** (même règle d'alignement), avec le même interrupteur.
- Tests : `StrandTests/LiftHeartRateMathTests.swift`.

### Lot A, PR A2 fusionnée (12 nov.)
- **#143** fusionnée (`main` 42e56cc), 6/6 sur sa tête (macOS + StrandTests, iOS, Android, Tools, doc, linux-capture).

### Lot B, PR B1 : écran Entraînement épuré (12 nov.)
- **En-tête** (`TrainingCompactHeader`) : « Entraînement », « Aujourd'hui » quand la semaine (ou le mois) montrée n'est pas la courante, **« i »** qui montre / cache la légende (sous la bande ou la grille du mois), **bouton calendrier** Semaine ↔ Mois ; en mois, ‹ mois › dessous. Plus de Semaine | Mois ni de compteur « 1 / 1 ».
- **Bande des 7 jours** sans flèches : un **balayage** horizontal change de semaine.
- **Lignes** (`TrainingLineLabel`) dans l'ordre de « Personnaliser Entraînement » (gardé) : **Progression** (« n charges à monter » + ↑ ; sinon « Par exercice et par muscle »). **Écart à la maquette, assumé** : la ligne reste visible sans charge à monter, sinon l'écran Progression (Régularité, et le bloc du lot C) n'aurait plus d'entrée depuis Entraînement. **Programmes ›** (« n programmes · Planifier la semaine ») ouvre un écran Programmes avec la carte existante (liste, Nouveau, Importer, Planifier) et ses feuilles. **Autre séance (cardio, autre sport)** ouvre la feuille **Démarrer** ; la feuille Démarrer gagne **Intervalles** (à côté de FC en direct). **Historique** en une ligne avec la dernière séance. La séance Bêta reste une ligne quand elle est activée.
- Retirés de l'écran : la carte Progression aux quatre zéros, la carte des programmes, la carte « Autres activités » (Démarrer une activité → feuille Démarrer, Intervalles et FC en direct → feuille Démarrer).

### Lot B, PR B1 fusionnée (12 nov.)
- **#144** fusionnée (`main` 4b6ff77), 6/6 sur sa tête.

### Lot B, PR B2 : « + Exercice » sur la carte du jour (12 nov.)
- **Ajouts du jour** (`LiftDayAdditions`, UserDefaults `lift.dayAdditions.v1`) : exercices ajoutés à **un programme pour un jour**, sur l'appareil, hors `.noopbak` ; un autre jour n'est jamais lu (effacé à l'écriture suivante). Le programme n'est pas touché.
- **Carte du jour** : bouton **« + Exercice »** à côté de Démarrer (pas pendant une séance en cours) ; les ajouts sous les blocs du programme, étiquette **« Aujourd'hui »**, **«−»** pour retirer.
- **Au démarrage** : tout Démarrer d'un programme passe par `beginProgramSession` (et la séance courte d'Élan par `beginElanShortSession`) qui ajoute les lignes du jour à la fin, en **lignes ajoutées pendant la séance** (`addedInSession`, id propre) avec le **nombre de séries de travail de la dernière fois** (3 pour un exercice jamais fait) ; poids et répétitions = les gris de la dernière séance. Les ajouts sont alors **pris par la séance** (effacés). En fin de séance, la question existante « mettre à jour le programme ? » propose de les garder.
- **Même feuille** que « Ajouter un exercice » de la séance en cours (`LiftSessionExerciseSheet`, `destination: .today`) : recherche, exercices déjà faits, **filtre par muscle** (pastilles des muscles principaux connus, aussi dans la séance), texte et bouton propres à « pour aujourd'hui ».
- **Pas fait** (à ajouter si Mohamed le veut) : « Superset… » dans la feuille, liste dépliable de **tous** les exercices du programme sur la carte (elle montre les premiers blocs puis « + n de plus »), retrait d'une ligne du programme pour aujourd'hui.

### Lot B, PR B2 fusionnée (12 nov.)
- **#145** fusionnée (`main` b900d39), 6/6 sur sa tête.

### Lot B, PR B3 : Régularité dans l'écran Progression (12 nov., sans maquette)
- **4e onglet « Régularité »** (Exercices · Muscles · Régularité · Forme) : `LiftRegularity` (pur) compte les **séries de travail par semaine** (lundi–dimanche, échauffements et séries à 0 rép. exclus, `LiftMetrics.isPerformed`) sur **12 semaines** et les **jours entraînés**.
- Trois chiffres : séances **cette semaine**, **semaines d'affilée** (la semaine en cours sans séance ne casse pas la série), **moyenne par semaine** (la semaine en cours exclue tant qu'elle n'est pas finie). Barres des séries (`LiftWeeklyBars`, trait = moyenne des semaines d'avant), puis le **calendrier** 12 × 7 (case bleue = séance ce jour-là).
- Les **fiches de séance** n'ont pas été refaites au-delà de la section « Fréquence cardiaque » (A2) : à revoir sur captures.
- Tests : `StrandTests/LiftRegularityTests.swift`.

## Définition de fin de chantier (proposée)
**Lots A, B, C (IPA 1) — le chantier est fini quand :**
1. Chaque lot est fusionné dans `main` (une PR par préoccupation), CI à 0 non-succès sur la tête de chaque PR (macOS + iOS + StrandTests + Tools Python + i18n + parité).
2. IPA `build/seance` = `main`, installée par-dessus l'app, validée par Mohamed sur le téléphone avec captures : ajout d'un exercice à la séance du jour depuis Entraînement (« + Exercice »), séance réelle avec poids répété, saisie en un tap, roulette, repos seul ; bandeau FC en séance et sur la fiche, comparaison masquable ; écran Entraînement épuré (bande, Mois, Programmes ›, Progression, Autre séance) ; Régularité ; bloc « Ce qui influence mes séances » (désactivable, « pas encore assez de données » avant 6 / 12 séances) ; « + verre ».
3. Données stockées nouvelles (eau en séance) : migration numérotée + jumeau Kotlin + deux `schema_oracle.json`, sauvegarde `.noopbak` vérifiée.
4. 10 langues pour toutes les nouvelles chaînes ; `i18n_audit`, `doc_comment_lint`, `Tools/` verts.
5. Fiche du chantier et feuille de route mises à jour (état, décisions prises au code, liste « À tester »).

**Lot D (IPA 2, à part) :** fusionné et construit seulement après un test sur le bracelet en séance réelle (enregistrement sans action d'abord, puis option allumée) ; résultats du test écrits dans la fiche ; option éteinte par défaut ; la détection n'est jamais présentée comme validée tant que le test n'a pas suivi des séries variées.

## Prompt de la conversation de code (proposé)
« Chantier 18 : la séance de musculation et l'écran Entraînement. Lis la feuille de route puis `docs/fork/chantier-18-seance.md` (maquettes validées, liens dans la fiche). Pars de `main`, vérifie qu'aucune branche `build/*` ou `feat/*` n'est en avance (règle 1). Code en lots, une PR par préoccupation, dans l'ordre : A (poids répété, saisie rapide à roulette et − / +, palier par exercice, repos lancé seul ; bandeau FC en séance et fiche, comparaison 2 séances), B (écran Entraînement épuré avec « + Exercice » sur la carte du jour ; Progression ; Régularité), C (Ce qui influence mes séances ; « + verre »). Passe par les résolveurs existants (durée, pause, planning, séance du jour, séance courte d'Élan, éditeur par blocs, bannière, widgets). Donnée stockée nouvelle (eau en séance) : migration + parité Kotlin + oracles. Avant chaque push : `i18n_audit`, `doc_comment_lint`, `Tools/`, parité. Fusionne chaque PR dès que la CI est verte ; une seule IPA `build/seance` après C avec les 3 rappels. Le lot D (fin de série) est une conversation à part, après un test sur le bracelet. Questions à Mohamed par choix multiples, réponses courtes en français. »

## Découpage du code
| Lot | Contenu | IPA |
|---|---|---|
| A | séance : poids répété (1), saisie rapide (2), courbe de FC + comparaison (4) | IPA 1 |
| B | écran Entraînement épuré (3) + Progression / Régularité | IPA 1 |
| C | ce qui influence mes séances (5) | IPA 1 |
| (Élan D, animations reportées) | à placer après la maquette globale | à décider |
| D | détection de fin de série (7) | IPA 2, après test sur le bracelet |

## Points de vigilance
- Partir de `main` à jour ; vérifier d'abord qu'aucune branche `build/*` ou `feat/*` n'est en avance (règle 1).
- Les lots A touchent `LiftSessionEngine` / la feuille de séance, aussi lus par la séance courte d'Élan, l'éditeur par blocs, la bannière et les widgets : passer par les résolveurs existants (durée, pause, planning).
- Parité Swift / Kotlin : seulement si une donnée stockée est ajoutée (repères du lot D, eau pendant la séance).
- Avant de pousser : `i18n_audit`, `doc_comment_lint`, tests `Tools/`.
