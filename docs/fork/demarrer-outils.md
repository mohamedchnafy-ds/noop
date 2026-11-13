# Outils de Démarrer : FC en direct, Journal du bracelet, Respirer, Intervalles (12 nov. 2026)

Demande de Mohamed (12 nov., soir) : dans la feuille « Démarrer » (le « + »), les quatre outils du bas sont
peu clairs, surtout le **journal du bracelet** en bas de FC en direct (« du code et du charabia »). Il faut
que tout ce qui sort soit compréhensible.

Maquette validée (5 planches) : https://claude.ai/artifact/5eDS6cxaaXBT3FQ6UdQf4K
1. Journal du bracelet en clair · 2. FC en direct · 3. Respirer · 4. Intervalles · 5. Avant → après.

Ce lot prend de l'avance sur le chantier 17 : l'étape 5 (FC en direct) et une partie de l'étape 7 (Respirer,
Intervalles). Le bouton « Journal » de Démarrer (écran Perspectives) reste pour l'étape 4 du chantier 17.

## Choix de Mohamed (12 nov.)
- Le journal du bracelet devient un **écran à part** ; FC en direct garde une petite carte « Ce que fait le
  bracelet » (4 dernières phrases) avec « Tout voir › ».
- Les lignes brutes restent derrière un **interrupteur « Lignes techniques », éteint** par défaut.
  Copier / Enregistrer exportent toujours tout le journal brut, tel quel (rapport de bug).
- Les **4 écrans** sont refaits : Journal du bracelet, FC en direct, Respirer, Intervalles.
- Le bouton « Journal » (Perspectives) n'est pas touché : étape 4 du chantier 17.

## Règles du journal en clair (PR 1)
- `Strand/Data/StrapLogReader.swift` : **un seul lecteur**, `StrapLogReader.readStrapLog`, des règles fixes
  sur le texte de chaque ligne (`strapLogPhrase`). Une phrase n'affirme que ce que la ligne dit (règle
  « A diagnostic may only assert what it can attribute » d'`AGENTS.md`) : une **demande** de batterie se lit
  « Niveau de batterie demandé », jamais un pourcentage ; une déconnexion donne le texte d'erreur d'iOS, pas
  une cause devinée.
- Une ligne sans règle n'a pas de phrase : elle est comptée (« + n lignes techniques ») et visible avec
  l'interrupteur. Une ligne sans heure (« Command response: … ») prend l'heure de la ligne d'avant.
- Les lignes de routine (FC enregistrée toutes les 30 s, demandes de FC en direct et de batterie, réponse
  « en cours ») ont une clé de regroupement : elles se replient en une seule ligne « ×14 depuis 19:33 » tant
  que seules des lignes de routine ou techniques viennent entre elles ; une phrase sans clé (déconnexion,
  synchro…) arrête le regroupement.
- L'écran lit les 1 500 dernières lignes, la carte les 300 dernières, une fois par `logRevision`
  (`StrapLogReadingCache`) et rien en arrière-plan (#2521).
- L'état du lien en une ligne : **un seul résolveur**, `StrapLinkSummary.strapLinkSummary` (via
  `StrapLinkSummaryRow.currentSummary`), que FC en direct réutilisera (PR 2).
- Le lien « Centre de tests » quitte la carte de FC en direct : il est dans l'écran du journal (« Signaler
  un problème »). Le Centre de tests garde son propre journal brut.
- Android : inchangé (écrans iPhone, aucune donnée stockée nouvelle).

## FC en direct (PR 2)
- Titre « FC en direct » (comme son entrée), sous-titre « Ton cœur en ce moment, battement par battement. »
- En-tête : la ligne d'état du résolveur `StrapLinkSummary` (titre seul, sans détail, pour ne pas dire deux
  fois batterie et historique), puis trois colonnes **Batterie · Au poignet · Historique** ; l'erreur de
  synchro (`lastSyncError`) dessous, en orange. Partis : la pastille « Associé · diffusion en cours », les
  badges FULL BOND / SYNCING n, la colonne Appareil (le nom est dans la ligne d'état).
- Cadran : plus de « HEART RATE » en capitales ; « Zone 1 » ; la phrase sous le cadran ne s'affiche que si
  elle apprend quelque chose (FC seule sans association complète, en attente, hors ligne).
- « VFC du moment » remplace « Physiologie en direct » et RMSSD : la valeur n'est montrée que si elle est
  crédible (**≤ 250 ms**, `LiveHRVReadout.ceilingMs`), sinon « — » et « Trop agitée pour un chiffre fiable ».
  La courbe des battements reste, « Temps entre les battements : … ms ». Les tuiles R-R / Trame / Événement
  partent (le journal du bracelet les garde).
- **La grille « Confiance du signal » (6 tuiles) part** : chacune répétait l'en-tête ou le cadran.
- Boutons : « Démarrer l'entraînement » en grand, puis « Mesurer ma VFC » et « Synchroniser maintenant »
  (`BLEManager.syncNow`, le même que Santé). « Rafraîchir » part (la batterie est relue à l'ouverture).
  Vibrer, Rechercher, Déconnecter restent dans la rangée du bas, inchangés.
- « Gérer les appareils » → « Appareils · Associer ou changer de bracelet ».
- Écart avec la maquette : pas de ligne Moyenne / Max sur 10 min / FC repos sous le cadran (aucune source
  sur 10 min à l'écran aujourd'hui ; à faire à part si Mohamed la veut).
## Respirer (PR 3)
- Sous-titre : « Le bracelet vibre pour te guider : une vibration pour inspirer, deux pour expirer. Tu peux
  fermer les yeux. » Onglets **Respirer · Mon rythme · Me calmer** (clé « My pace » ; « Calm me » en fr).
- Le rond affiche le mot de la phase pendant la séance (« Inspire… ») et la FC en petit dessous ; avant le
  départ, la pastille « Prêt » suffit (le rond ne le redit pas). Le grand « 96 BPM » part.
- Pastilles et chrono ne partagent plus une ligne qui se coupe (`ViewThatFits`) ; « 0:00 sur 10:00 ».
- Rythmes avec la virgule (« 5,5 resp/min ») ; « Sans fin » a sa clé (« No limit ») au lieu de « Open »
  (« Ouvrir ») ; « Carré 4-4-4-4 » ; « Vibrations activées » ; textes français de l'écran au tutoiement.
- Écart avec la maquette : les rythmes restent des pastilles (pas la liste expliquée), pas de compte à
  rebours « 5 s » sous le mot de la phase.

## Intervalles (PR 4)
- Titre « Intervalles », sous-titre « Le bracelet vibre à chaque changement : pas besoin de regarder
  l'écran. » Phases **Effort · Repos · Terminé** ; « Tour 1 sur 8 » (la clé « Round %lld of %lld » sert aussi
  à la ligne de superset de la séance : « Cycle » y devient « Tour », le mot du fork).
- « Prêt » tant que rien n'a commencé (au lieu de « En pause ») ; « Recommencer ».
- Durées « 30 s », « 10 min », « 1 min 30 s » (`IntervalTimerView.secondsText`, sans clé : « s » est le
  même partout) ; sous chaque réglage « De 5 s à 10 min, par pas de 5 s ».
- Écart avec la maquette : le chiffre central reste en secondes (« 30 », « Secondes »).

## Batterie sur Aujourd'hui (demande du 12 nov., soir)
- **13 nov. (après-midi), décision finale de Mohamed** (capture de l'IPA `build/demarrer`) : **pas de carte ni de
  ligne sous le titre**. La batterie va dans le **petit rond de l'en-tête** (celui qui affiche « 53 »), et elle y
  reste **en permanence** : pendant une synchro, le rond ne se transforme plus en « Synchronisation »
  (`LiquidBatteryButton` passe `syncing: false` à `ChargeSyncIndicator`). La synchro reste visible dans la carte
  Sources de données (`LiquidSyncStatusRow`) et dans le tirer-pour-rafraîchir. `TodayBatteryCard` et ses
  3 clés sont retirés. Les paragraphes ci-dessous sur la carte et la ligne sont l'historique.
- **13 nov. (soir), IPA `build/demarrer-2`** : le rond montrait « ··· » (aucun pourcentage). Cause : après
  une réinstallation l'app n'a pas encore de lecture, et le keep-alive ne demande jamais la batterie pendant
  une synchro (`guard !backfilling` dans `BLEManager.keepAliveFire`, on ne dérange pas le bracelet) ; le rond
  de synchro cachait ce vide. Correctif sans toucher au BLE : tant que ce lien n'a pas de lecture, le rond
  prend la **dernière lecture enregistrée** du bracelet (`LiveState.batterySamples`, série gardée en base,
  rechargée à la connexion) si elle a **3 h au plus**, bracelet connecté, et jamais pendant une charge
  (`StrapBatteryDisplay.headerBatteryPct`, test dans `LiquidBatteryDisplayTests`).
- **13 nov., retour sur l'IPA `build/demarrer`** : « tout est ok sauf la barre de la batterie, trop grosse,
  je voulais un truc discret ». La carte devient **une ligne discrète** sous le titre : petite icône,
  « 73 % » en petit gras puis « ~5 jours restants » en gris, sans fond ni chevron ; la couleur ne vient que
  pour faible / critique / en charge. Toucher → Appareils (inchangé). Le reste de la fiche ci-dessous
  (couleurs, résolveur) reste vrai.
- Carte « Batterie du bracelet » **juste sous le titre d'Aujourd'hui** (`TodayBatteryCard`, épinglée, hors de
  l'ordre personnalisable) : icône de batterie au quart près, **pourcentage en grand**, autonomie restante
  (« ~5 jours restants », même règle que la ligne de Sources de données) ou « En charge » ; vert au-dessus de
  30 %, orange de 15 à 30 %, rouge sous 15 % avec « À recharger bientôt ». Toucher → Appareils.
- **Un seul résolveur** avec la petite bague de l'en-tête : `LiquidTodayView.StrapBatteryDisplay.resolve`.
  Bracelet non connecté → « Bracelet non connecté », jamais un vieux pourcentage ; sous une bague Oura active,
  la charge de la bague (« Batterie de la bague »), sans autonomie du bracelet.
- Le pourcentage suit la langue (« 73 % ») ici, dans FC en direct et dans Sources de données.

## Journal
- **12 nov. (soir)** : audit des 4 écrans, maquette en 5 planches, 4 questions, réponses = les choix
  recommandés. PR 1 (journal du bracelet) codée : 97 clés dans les 10 langues, `StrapLogReaderTests` ;
  PR #156. PR 2 (FC en direct) codée, empilée sur la PR 1 : 13 clés, `LiveHRVReadoutTests`. PR 3
  (Respirer, 5 clés + 17 textes français) et PR 4 (Intervalles, 4 clés, `IntervalTimerTextTests`) codées
  depuis `main`.
- **12 nov. (soir, suite)** : choix de Mohamed, **tout dans la PR #156** (les 4 écrans) ; ajout demandé de la
  batterie bien visible sur Aujourd'hui (3 clés, `TodayBatteryLineTests`).

- **12 nov. (nuit)** : jobs macOS / iOS de #156 annulés deux fois sans runner arm64 ; choix de Mohamed :
  preuve Intel. Branche temporaire `ci/demarrer-intel` (tête de la PR + `tmp-demarrer-intel.yml`, jamais
  fusionnée, à supprimer sur accord) : build macOS vert, **build NOOPiOS simulateur vert**, **2 986
  StrandTests, 0 échec, 2 ignorés** (sans les 14 classes de rendu) sur `macos-15-intel`. Choix de Mohamed :
  fusionner, puis IPA `build/demarrer` depuis `main` (elle contient aussi la suite du chantier 18).

## À tester (IPA `build/demarrer`)
- **Batterie sur Aujourd'hui** (version du 13 nov.) : plus rien sous le titre ; le petit rond en haut à
  droite montre toujours la batterie (« 53 », éclair en charge), **même pendant une synchro** ; la synchro se
  voit dans Sources de données en bas d'Aujourd'hui. Ancienne version : sous le titre, carte « Batterie du bracelet · 73 % · ~5 jours restants »
  (vert), orange à 30 % ou moins, rouge à 15 % ou moins avec « À recharger bientôt », éclair « En charge » sur
  le chargeur, « Bracelet non connecté » sans pourcentage quand il est loin ; même valeur que la bague en haut
  à droite ; toucher → Appareils. **Capture à envoyer.**
- **Journal du bracelet** : FC en direct → en bas, carte « Ce que fait le bracelet » (4 phrases, heure à
  droite) → « Tout voir » : ligne d'état (« Connecté au WHOOP 4.0 · la fréquence cardiaque arrive ·
  historique à jour il y a 2 min · batterie 73 % »), pastilles Tout · Connexion · Fréquence cardiaque ·
  Historique · Batterie · Problèmes, phrases avec icône (FC enregistrée « ×n depuis … », Niveau de batterie
  demandé, FC en direct demandée, Réponse du bracelet : en cours, Historique récupéré, Bracelet déconnecté en
  orange…) ; « Lignes techniques » montre la ligne brute sous chaque phrase et les blocs de lignes sans
  phrase ; Copier / Enregistrer donnent le même fichier qu'avant ; Centre de tests s'ouvre. **Captures à
  envoyer**, et le journal brut copié si une ligne fréquente reste sans phrase.
- **FC en direct** : titre « FC en direct » ; en-tête = « Connecté au WHOOP 4.0 » + Batterie · Au poignet ·
  Historique en entier (rien de coupé) ; plus de grille de 6 tuiles ; « Zone 1 » sous le chiffre ; VFC du
  moment : un chiffre plausible, sinon « — » et « Trop agitée… » (fini les 454 ms) ; « Temps entre les
  battements » ; boutons Démarrer l'entraînement, Mesurer ma VFC, Synchroniser maintenant (la synchro se
  lance, le journal dit « Synchronisation demandée ») ; Vibrer / Rechercher / Déconnecter en bas ;
  « Appareils ». **Capture à envoyer.**
- **Respirer** : onglets Respirer · Mon rythme · Me calmer ; avant le départ, pastilles Prêt · Vibrations
  activées puis « 0:00 sur 10:00 · 0 respirations » sans coupure ; le rond montre la FC en petit, pendant la
  séance « Inspire… / Expire… » ; « 5,5 resp/min » ; « Sans fin · 5 min · 10 min · 15 min » ; « Carré » ;
  onglet Mon rythme et Me calmer au tutoiement. **Capture à envoyer.**
- **Intervalles** : titre « Intervalles » ; « Effort » et « Tour 1 sur 8 » ; « Prêt » avant de commencer,
  « En pause » après une pause ; « Recommencer » ; « 30 s · 15 s · 8 · 5:45 » ; « De 5 s à 10 min, par pas de
  5 s » ; une séance de muscu avec superset dit « Tour 2 sur 3 ». **Capture à envoyer.**
