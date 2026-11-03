# Noop - où part le temps entre une modification et l'IPA installable (v2, journaux inclus)

Audit des traces du fork mohamedchnafy-ds/noop, du 31 octobre (création du fork) au 2 novembre 2026 au soir. Aucune écriture sur le dépôt, aucun build relancé.

Heures de Paris (UTC+1) partout.

Cette version 2 intègre les journaux détaillés des exécutions, lus le 2 novembre au soir avec un accès authentifié en lecture seule (jeton temporaire, révocable). Les erreurs citées sont extraites des journaux ou des annotations GitHub, sauf mention contraire. Le journal des rectifications par rapport à la v1 est en fin de document.

## Méthode et périmètre des preuves

- Source principale : l'API GitHub Actions, 535 exécutions récupérées par pagination complète (6 pages de 100, dernière page de 35 ; aucune page manquante). Borne basse : première exécution le 31 oct. 15h06 (le fork vient d'être créé) ; borne haute : 2 nov. 21h08.
- Pour chaque exécution citée : horodatages et conclusion par job et par étape, journaux d'étapes et annotations GitHub (lues en v2). Les erreurs citées sont verbatim des journaux.
- Sources complémentaires : fichiers de workflows du dépôt, historique des commits, liste des releases et des pull requests (liens en fin de document).
- Le chiffre "~40 h" est la durée cumulée des exécutions (somme des durées fin - début des 535 exécutions, prises une par une) : il inclut le temps d'attente avant démarrage des jobs, pas seulement du calcul. Des exécutions tournent en parallèle, donc ce total n'est pas du temps calendaire. Il n'est pas non plus du temps facturable exact : la facturation GitHub se fait par job, et une exécution peut contenir 2 jobs parallèles (le total par jobs serait plus élevé). Une exécution inclut en outre une anomalie d'horodatage d'environ 60 min (voir plus bas). Aucun coût n'est déduit de ce total.
- Lecture des journaux limitée aux exécutions citées dans ce document ; les 535 exécutions n'ont pas été relues ligne à ligne.

## Vue d'ensemble

| Indicateur | Valeur | Base |
|---|---|---|
| Exécutions de workflows | 535 en ~54 h | API, pagination complète |
| Builds IPA | 18 : 15 réussis, 3 annulés | tableau détaillé plus bas |
| Durée d'un build IPA réussi | médiane 14,7 min (10,3 à 17,6) | horodatages d'étapes |
| Part de la compile xcodebuild dans un build IPA | ~95 % | durées par étape |
| Publication de l'IPA (GitHub Releases) | ~15 s | durées par étape |
| Attente avant démarrage d'un job | quelques secondes | création vs début de job |
| Vérifications PR "App build" | 66 : 43 vertes, 13 échecs, 10 annulées | API |
| Renders d'écrans | 40 : 32 verts, 6 échecs, 2 annulés | API |

Ces chiffres décrivent des métadonnées, pas le contenu des builds : je n'ai pas vérifié ligne à ligne que chaque compilation réussie s'est bien passée.

## Ce que les traces établissent

### 1. Chaque build recompile sans cache déclaré (établi, portée limitée)

- Aucun des 15 fichiers de workflows ne déclare d'étape de cache (vérifié par recherche textuelle : zéro occurrence de "cache").
- Chaque exécution part d'une machine virtuelle neuve : le dossier de compilation (DerivedData) est vide au départ. La compile d'un build IPA dure 10 à 17 min et représente ~95 % du build.
- Portée limitée : GitHub applique des caches d'outillage implicites sur ses runners. Le constat est : aucun cache de compilation n'est configuré, pas "rien n'est jamais mis en cache".

### 2. Le même code est compilé par deux chaînes distinctes (établi)

- La vérification PR "App build" compile en Debug sur deux runners (macOS universel + iOS) : 12 à 19 min.
- Le workflow IPA compile ensuite en Release non signé : 10 à 17 min.
- Si on attend la fin de la vérification avant de lancer l'IPA, cela fait 22 à 36 min de pipeline de compilation pour une modification (12-19 + 10-17), et 28 à 51 min si un render (6-15 min) s'ajoute. Les deux configurations étant différentes (Debug/Release), l'artefact de l'une n'est pas réutilisable par l'autre en l'état.
- Les traces montrent aussi des lancements d'IPA sans attendre la fusion (branches build/* poussées en parallèle des PR), donc les deux chaînes ne sont pas toujours en série.

### 3. Des jobs macOS meurent sans exécuter la moindre étape le 2 novembre (cause établie en v2)

Huit jobs ont pour conclusion "annulé" après ~15 min, avec zéro étape exécutée (métadonnées) :

- 6 jambes macOS (runner macos-15) de la vérification PR : 10h45→11h00, 11h01→11h16, 11h18→11h33, 11h38→11h53, 14h00→14h15, 14h15→14h30.
- 2 jobs de render (runner macos-15 également) : 10h45→11h00, 11h18→11h33.

Fenêtres calendaires réelles (enveloppes englobant les intervalles listés, avec des trous de 1 à 5 min entre eux ; ce n'est ni une somme ni une union exacte) : 10h45→11h53 et 14h00→14h30, pendant lesquelles les jambes macOS mouraient alors que les jambes iOS (macos-26) aboutissaient normalement. Un render sur macos-15 a réussi au milieu (11h01→11h15) et une jambe macOS a réussi à 12h00→12h13 : le problème était intermittent.

**Cause établie (v2).** L'annotation que GitHub attache à ces jobs dit textuellement : "The job was not acquired by Runner of type hosted even after multiple attempts", avec l'avis : "Due to capacity constraints, jobs targeting macOS arm64 runners may experience longer queue times." (lien en fin de document). Aucun journal n'existe pour ces jobs : aucun runner ne leur a jamais été attribué, rien n'a démarré. C'est une pénurie intermittente de capacité des runners macOS arm64 côté GitHub, pas un problème du dépôt. Le commentaire du workflow temporaire créé ce jour-là dans le dépôt ("while GitHub's macos-15 runners are not acquired") va dans le même sens.

### 4. L'étape "Test Strand" échoue sur 7 vérifications PR (établi ; causes extraites en v2)

31 oct. - 1er nov., 7 exécutions de la vérification PR échouent à l'étape "Test Strand" de la jambe macOS (vérifié une par une, journaux lus ; la jambe iOS est verte à chaque fois). Toutes les causes sont côté code, pas côté infrastructure. Quatre groupes :

- **31 oct. 15h06, 15h25 et 15h25** (runs 41208584506, 41210063479, 41210075369) : erreurs de compilation Swift 6 dans StrandTests/LiftSessionSupersetTests.swift - appels à des méthodes isolées sur l'acteur principal depuis un contexte non isolé ("call to main actor-isolated static method ... in a synchronous nonisolated context", lignes 121, 123, 124).
- **31 oct. 18h19** (run 41223991969) : échec d'assertion CoachNapContextTests.testBlocksOutsideTheMainNightAreNapsAndNewestComesFirst ("1" au lieu de "2") ET plantage de l'app pendant les tests : "Fatal error: Index out of range" (Swift/ContiguousArrayBuffer.swift).
- **31 oct. 20h30 et 20h51** (runs 41234541989, 41236160762) : régressions de logique superset/repos - LiftSessionSupersetTests.testNextPendingNeverLandsOnAMember (le prochain créneau tombe sur un membre du superset), testTheLastRestDoesNotStartAnything, LiftSessionTimingTests.testARestsEndIsPublishedOnceAndItsWarningBuzzes (fin de repos publiée deux fois au lieu d'une).
- **1er nov. 11h42** (run 41298647921) : le compilateur Swift abandonne, "unable to type-check this expression in reasonable time", à StrandTests/TodayScreenRenderTests.swift:67:16.

Chaque échec n'est découvert qu'après 10 à 15 min de compilation.

### 5. Une suite de tests reste rouge pendant ~23 h (cause établie en v2)

La suite "parity repository-acceptance" (Tools Python CI, ~3 min sur Linux) échoue sur 31 exécutions d'affilée : premier échec le 31 oct. 15h06 (création du fork), dernier le 1er nov. 14h29 ; retour au vert après le PR #11 (commit b53dc74d).

Cause établie (v2), identique sur les 31 exécutions (journaux relus une par une) : un test de gouvernance ("ratchet") compare l'inventaire des fichiers du dépôt à une base enregistrée. L'assertion échoue toujours de la même façon : 509 fichiers attendus contre 510 réels, empreinte différente. La suite échouait parce que la base enregistrée n'était pas à jour après l'ajout d'un fichier, pas à cause d'une régression du produit.

### 6. Des builds annulés par des pushes rapprochés (mécanisme établi, détails v2)

Les workflows utilisent `cancel-in-progress` : re-pousser la même branche tue le build en cours.

- 3 builds IPA annulés :
  - 1er nov. 1h04 (build/superset-guided) : l'annotation GitHub confirme le re-push ("Canceling since a higher priority waiting request for ipa-refs/heads/build/superset-guided exists").
  - 1er nov. 1h08 (build/superset-guided) : l'annotation dit "repository invocation blocked" ; le sens exact de ce message n'est pas établi, ce n'est pas l'annotation habituelle d'un re-push.
  - 1er nov. 10h23 (build/sleep-redesign) : annulé par un nouveau push à 10h29 après 6,5 min. En v2, lecture des journaux : la compilation était quasi terminée - mêmes 30 unités de compilation Swift que le build réussi de remplacement, 31 éditions de liens sur 32 ; il ne manquait que l'empaquetage final d'une cible puis l'étape de publication (~15 s). Le build de remplacement a duré 16,3 min. Le surcoût par rapport au scénario sans annulation n'est pas isolable : la durée qu'aurait prise le build initial est inconnue.
- 10 vérifications PR et 2 renders ont aussi été annulés par re-push.

### 7. Anomalie d'horodatage dans les traces (établi ; à connaître)

Trois exécutions du 1er nov. entre 8h47 et 10h46 affichent des horloges d'étapes décalées d'exactement 1 h par rapport aux horloges de job. Conséquence : le build lancé à 8h47 affiche 77 min sur la page GitHub, alors que ses étapes n'occupent que ~17 min. La vraie durée calendaire n'est pas tranchable avec certitude depuis l'API ; l'anomalie (et non un build réellement long) est l'explication la plus plausible, au vu de la cohérence des 14 autres builds (10 à 17 min).

## Le cas des widgets du 2 novembre : 4 h 03 entre premier commit et IPA finale

| Heure | Événement | Source |
|---|---|---|
| 10h45 | Premier commit + PR #30 | PR, commits |
| 10h45→11h53 | 5 poussées de code ; 4 vérifications PR voient leur jambe macOS mourir sans étape (fenêtre du point 3) ; 2 renders meurent pareil, 1 render passe | runs |
| 11h54 | Workflow temporaire de contournement créé sur macos-26 ; 1er essai en échec à l'étape de test : le compilateur abandonne sur une expression trop complexe ("unable to type-check this expression in reasonable time", StrandTests/LiftProgressTests.swift:110, journal lu en v2) ; 2e essai vert à 12h14 après une nouvelle poussée de code (commit différent, pas une simple relance) | runs, journaux, fichier workflow |
| 11h55→12h13 | La vérification PR finit par passer entièrement (jambe macOS attribuée) | run |
| 12h15 | PR #30 fusionné | PR |
| 12h18→12h35 | Build IPA (17,1 min), publiée | run, release |
| 12h35→13h59 | **Intervalle non attribué (84 min)** : aucune trace entre la publication de l'IPA et le commit du correctif. Le correctif (commit e5f7de84, "Widgets: read the App Group the signature grants under SideStore's main profile") indique qu'un problème d'App Group sous le profil SideStore a été corrigé ; l'hypothèse naturelle est une installation, un essai sur iPhone, un diagnostic puis l'écriture du fix, mais aucune trace ne le prouve | commits |
| 13h59 | PR #31 (correctif) ; ses 2 vérifications voient leur jambe macOS mourir (14h00→14h30) | runs |
| 14h36 | PR #31 fusionné alors que la jambe macOS de sa vérification est rouge (jambe iOS verte). L'acteur de la fusion n'apparaît pas dans les données récupérées | PR, runs |
| 14h36→14h48 | Build IPA (11,0 min), publiée | run, release |

Ce qui est répartissable avec preuve : ~1 h 51 entre le premier commit et la première IPA (itérations de code + vérifications, fenêtre de morts macOS incluse, sans qu'on puisse dire quelle part de ces 1 h 51 aurait existé sans l'incident, car le code changeait à chaque poussée) ; 84 min non attribuables ; 49 min entre le commit du correctif et l'IPA finale (dont ~30 min de vérifications mortes en chevauchement, puis 11 min de build).

## Ce que les traces ne mesurent pas

- Le temps de codage (y compris les allers-retours avec l'assistant de code) : les écarts entre commits ne prouvent pas une durée de travail.
- L'installation manuelle de l'IPA sur l'iPhone et les essais sur l'appareil : aucune trace.
- Tout ce qui précède la création du fork (31 oct.).

## Pistes d'accélération, avec leurs conditions

1. **Configurer un cache de compilation** (actions/cache sur DerivedData et les packages Swift) dans les workflows IPA, vérification et render. Sous conditions : validité d'un cache DerivedData entre machines éphémères, choix des clés, versions de Xcode, configuration Debug/Release. Gain réel à mesurer sur un essai, pas garanti ; c'est la piste au meilleur potentiel vu que la compile fait ~95 % du temps de build.
2. **Réduire la double compilation.** Un déclenchement de l'IPA à la fusion sur main ne supprime pas la seconde compile. Les vraies options : aligner Debug/Release pour réutiliser un artefact (change ce que la vérification garantit), ou faire produire l'IPA par le workflow de vérification (allonge la porte PR). Chaque option déplace une garantie, à choisir en connaissance.
3. **Ne pas re-pousser une branche de build pendant qu'un build tourne** (ou annuler explicitement). Un build a été tué alors que sa compilation était quasi terminée ; c'est le seul gaspillage directement évitable sans changer l'outillage.
4. **Réserver les renders aux modifications visuelles** : ~6 à 15 min et pas d'installation, mais sans intérêt pour un changement non visuel, et ils partagent la dépendance au runner macos-15 (2 morts le 2 nov.). Les 4 autres échecs de render ont des causes connues en v2, toutes des erreurs de compilation dans les fichiers de tests : "ambiguous use of init" (LiftSessionFinishTests.swift:220, 1er nov. 00h50), le même timeout de typage que la porte PR (TodayScreenRenderTests.swift:67, 1er nov. 11h41), et "reference to property 'calendar' in closure requires explicit use of 'self'" (TrainingRenderTests.swift:138 et 141, 2 nov. 03h27 et 04h50).
5. **Documenter un repli quand les runners macOS arm64 manquent** : le contournement macos-26 a fonctionné ce jour-là (build + tests en ~8 min), une fois, sur une branche temporaire. En faire une option durable change la cible des tests (version de macOS/SDK) : à qualifier avant d'en faire un défaut.
6. **Ne pas traiter une porte rouge comme un détail** : la fusion du PR #31 avec la jambe macOS rouge a perdu la couverture macOS pour ce changement. C'était peut-être acceptable ici (correctif de widget iOS), mais c'est une décision de couverture à prendre explicitement, pas une habitude.
7. **À plus long terme (arbitrage, pas recommandation)** : un Mac local ou un runner macOS loué permettrait la compile incrémentale et l'essai immédiat sans boucle cloud, au prix d'un coût et d'une maintenance. Le volume actuel (535 exécutions en 3 jours) est un argument dans les deux sens. Toute option payante est à évaluer séparément ; ce document ne mesure pas les coûts.
8. **Simplifier les expressions qui font abandonner le compilateur** : trois échecs distincts (porte PR du 1er nov. 11h42, render du 1er nov. 11h41, contournement du 2 nov. 11h54) viennent du même type d'erreur ("unable to type-check this expression in reasonable time") dans des fichiers de tests. Découper ces expressions évite des échecs découverts après 5 à 15 min de compile.

## Table des preuves

### Builds IPA (18 exécutions, durées mesurées sur les horodatages d'étapes)

| Début (Paris) | Branche | Issue | Durée | Lien |
|---|---|---|---|---|
| 31/10 15h56 | build/supersets-coach | réussi | 10,8 min | https://github.com/mohamedchnafy-ds/noop/actions/runs/41212335189 |
| 31/10 19h11 | build/today-insights | réussi | 10,3 min | https://github.com/mohamedchnafy-ds/noop/actions/runs/41228173566 |
| 31/10 21h45 | build/lift-superset-rounds | réussi | 14,4 min | https://github.com/mohamedchnafy-ds/noop/actions/runs/41240356227 |
| 31/10 23h30 | build/superset-rounds | réussi | 16,5 min | https://github.com/mohamedchnafy-ds/noop/actions/runs/41248490240 |
| 01/11 01h04 | build/superset-guided | annulé (re-push, confirmé par annotation) | 4,7 min | https://github.com/mohamedchnafy-ds/noop/actions/runs/41255108490 |
| 01/11 01h08 | build/superset-guided | annulé (annotation "repository invocation blocked", sens non établi) | 6,0 min | https://github.com/mohamedchnafy-ds/noop/actions/runs/41255428486 |
| 01/11 01h44 | build/superset-guided-4 | réussi | 15,8 min | https://github.com/mohamedchnafy-ds/noop/actions/runs/41258057897 |
| 01/11 07h45 | build/sleep-redesign | réussi | 12,1 min | https://github.com/mohamedchnafy-ds/noop/actions/runs/41282122087 |
| 01/11 08h47 | build/sleep-redesign | réussi (horloges incohérentes) | 17,6 min d'étapes | https://github.com/mohamedchnafy-ds/noop/actions/runs/41286162179 |
| 01/11 10h23 | build/sleep-redesign | annulé (re-push ; compilation quasi terminée, empaquetage final et publication non atteints) | 6,6 min | https://github.com/mohamedchnafy-ds/noop/actions/runs/41288655281 |
| 01/11 10h30 | build/sleep-redesign | réussi | 16,3 min | https://github.com/mohamedchnafy-ds/noop/actions/runs/41289094300 |
| 01/11 12h24 | build/today-redesign | réussi | 14,7 min | https://github.com/mohamedchnafy-ds/noop/actions/runs/41301755172 |
| 01/11 12h57 | build/lift-progression | réussi | 14,0 min | https://github.com/mohamedchnafy-ds/noop/actions/runs/41304193568 |
| 01/11 13h43 | build/lift-progression | réussi | 14,3 min | https://github.com/mohamedchnafy-ds/noop/actions/runs/41307871628 |
| 01/11 19h11 | build/coach-redesign | réussi | 14,8 min | https://github.com/mohamedchnafy-ds/noop/actions/runs/41335297956 |
| 02/11 01h15 | build/nutrition | réussi | 17,5 min | https://github.com/mohamedchnafy-ds/noop/actions/runs/41366199945 |
| 02/11 12h18 | build/day-widgets | réussi | 17,1 min | https://github.com/mohamedchnafy-ds/noop/actions/runs/41435835771 |
| 02/11 14h37 | build/widget-app-group | réussi | 11,0 min | https://github.com/mohamedchnafy-ds/noop/actions/runs/41454489055 |

### Jobs macOS morts sans étape le 2 novembre (conclusion "annulé", 0 étape exécutée)

| Fenêtre (Paris) | Workflow | Lien |
|---|---|---|
| 10h45→11h00 | App build (PR #30) | https://github.com/mohamedchnafy-ds/noop/actions/runs/41423290495 |
| 11h01→11h16 | App build (PR #30) | https://github.com/mohamedchnafy-ds/noop/actions/runs/41425391930 |
| 11h18→11h33 | App build (PR #30) | https://github.com/mohamedchnafy-ds/noop/actions/runs/41427692565 |
| 11h38→11h53 | App build (PR #30) | https://github.com/mohamedchnafy-ds/noop/actions/runs/41430425607 |
| 14h00→14h15 | App build (PR #31) | https://github.com/mohamedchnafy-ds/noop/actions/runs/41449218550 |
| 14h15→14h30 | App build (PR #31) | https://github.com/mohamedchnafy-ds/noop/actions/runs/41451443037 |
| 10h45→11h00 | Screens render | https://github.com/mohamedchnafy-ds/noop/actions/runs/41423256252 |
| 11h18→11h33 | Screens render | https://github.com/mohamedchnafy-ds/noop/actions/runs/41427688506 |

### Échecs "Test Strand" (7 exécutions, causes extraites des journaux)

| Début (Paris) | Cause extraite du journal | Lien |
|---|---|---|
| 31/10 15h06 | Compile : isolation d'acteur Swift 6 (LiftSessionSupersetTests.swift:121/123/124) | https://github.com/mohamedchnafy-ds/noop/actions/runs/41208584506 |
| 31/10 15h25 | Idem | https://github.com/mohamedchnafy-ds/noop/actions/runs/41210063479 |
| 31/10 15h25 | Idem | https://github.com/mohamedchnafy-ds/noop/actions/runs/41210075369 |
| 31/10 18h19 | Assertion CoachNapContextTests + crash "Index out of range" pendant les tests | https://github.com/mohamedchnafy-ds/noop/actions/runs/41223991969 |
| 31/10 20h30 | Assertions superset/repos (LiftSessionSupersetTests, LiftSessionTimingTests) | https://github.com/mohamedchnafy-ds/noop/actions/runs/41234541989 |
| 31/10 20h51 | Idem | https://github.com/mohamedchnafy-ds/noop/actions/runs/41236160762 |
| 01/11 11h42 | Compile : expression trop complexe à typer (TodayScreenRenderTests.swift:67) | https://github.com/mohamedchnafy-ds/noop/actions/runs/41298647921 |

### Autres références

- Annotation GitHub établissant la pénurie de runners (job 125203740592) : https://github.com/mohamedchnafy-ds/noop/actions/runs/41423290495
- PR #30 (day widgets) : https://github.com/mohamedchnafy-ds/noop/pull/30
- PR #31 (correctif App Group) : https://github.com/mohamedchnafy-ds/noop/pull/31
- Commit du correctif : https://github.com/mohamedchnafy-ds/noop/commit/e5f7de844c5c40ab6281d73ca8614743e2fca595
- PR #11 (retour au vert de la suite parity) : https://github.com/mohamedchnafy-ds/noop/pull/11 - commit https://github.com/mohamedchnafy-ds/noop/commit/b53dc74d0ae29ff9e72a514fdf7e59fbb3808de9
- Vérification PR qui finit par passer (PR #30) : https://github.com/mohamedchnafy-ds/noop/actions/runs/41432580168
- Contournement macos-26 : 1er essai en échec https://github.com/mohamedchnafy-ds/noop/actions/runs/41432553430 - 2e essai vert https://github.com/mohamedchnafy-ds/noop/actions/runs/41434027630
- Workflow IPA : https://github.com/mohamedchnafy-ds/noop/blob/main/.github/workflows/fork-ipa-on-push.yml
- Workflow de vérification : https://github.com/mohamedchnafy-ds/noop/blob/main/.github/workflows/app-build.yml
- Workflow de render : https://github.com/mohamedchnafy-ds/noop/blob/main/.github/workflows/fork-render-on-push.yml
- Workflow temporaire macos-26 (commentaire sur l'attribution des runners) : https://github.com/mohamedchnafy-ds/noop/blob/ci/day-widgets-macos/.github/workflows/tmp-day-widgets-macos-tests.yml
- Renders en échec (hors file d'attente) : runs 41254165648, 41298618970, 41377823748, 41385189849 sous https://github.com/mohamedchnafy-ds/noop/actions
- Suite parity : 31 échecs du run 41208584486 (31/10 15h06) au run 41311516820 (01/11 14h29), même assertion sur chacun.

## Journal des rectifications par rapport à la v1

1. Incident macOS du 2 nov. : la cause passe d'hypothèse à établie, par les annotations GitHub ("The job was not acquired by Runner of type hosted even after multiple attempts" + avis de capacité sur les runners macOS arm64).
2. "Test Strand" : la raison passe d'inconnue à quatre causes exactes extraites des journaux (voir table dédiée). Le comptage de 7 exécutions est confirmé ; un comptage intermédiaire à 4, communiqué pendant la vérification, était erroné (pagination incomplète) et est retiré.
3. Suite parity : la cause passe d'inconnue à établie (ratchet de gouvernance, base de 509 fichiers non mise à jour vers 510), identique sur les 31 exécutions vérifiées une par une.
4. IPA annulé le 1er nov. 10h23 : "compilation terminée, publication non atteinte" devient "compilation quasi terminée, empaquetage final et publication non atteints" (comparaison des étapes de build avec le build réussi).
5. IPA annulé le 1er nov. 1h08 : la cause passe de non établie à "repository invocation blocked" (annotation verbatim ; interprétation prudente).
6. Contournement macos-26, 1er essai : la raison de l'échec passe d'inconnue à "expression trop complexe à typer" (LiftProgressTests.swift:110) ; le 2e essai vert suit une nouvelle poussée de code.
7. Renders en échec : causes inconnues en v1, erreurs de compilation exactes en v2 (point 4 des pistes).
8. Ajout de la piste 8 (expressions trop complexes pour le compilateur).

## Limites rappelées

- Les journaux ont été lus pour les exécutions citées ; les 535 exécutions n'ont pas été relues ligne à ligne.
- Temps de codage et d'installation/essai sur iPhone : non mesurables, seulement bornés par les commits et les publications.
- 3 exécutions du 1er nov. ont des horloges incohérentes ; leurs durées calendaires exactes sont incertaines.
- Les durées de la colonne "Durée" des builds annulés correspondent au temps écoulé jusqu'à l'annulation.
- L'accès en lecture utilisé pour cette v2 est temporaire et révocable ; il n'a servi qu'à lire des journaux.
