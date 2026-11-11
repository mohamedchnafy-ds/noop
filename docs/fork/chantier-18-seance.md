# Chantier 18 — La séance de musculation et l'écran Entraînement

Fiche ouverte le 11 nov. 2026. État : **changements listés avec Mohamed, maquettes à faire** (une par sujet + une maquette globale), puis code.

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

### Maquette 1 — saisie rapide et poids répété (11 nov.) : en attente de validation
- Lien : https://claude.ai/artifact/JkydKpfVF7QC1Np1isCFwG (source : `docs/fork/maquettes/chantier-18-1-saisie-rapide.html`).
- Choix de Mohamed : correction par **roulette sans clavier + boutons − / +** ; **palier par exercice avec valeur par défaut devinée** (barre 2,5 kg, haltère 1 kg, machine 5 kg), réglable d'un tap et retenu ; **repos lancé seul** à « Fait » (− 15 s, + 15 s, Passer) ; **série en cours en grand** avec les autres séries en liste compacte dessous.

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
