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

## Journal
- **12 nov. (soir)** : audit des 4 écrans, maquette en 5 planches, 4 questions, réponses = les choix
  recommandés. PR 1 (journal du bracelet) codée : 96 clés dans les 10 langues, `StrapLogReaderTests`.

## À tester (prochaine IPA)
- **Journal du bracelet** : FC en direct → en bas, carte « Ce que fait le bracelet » (4 phrases, heure à
  droite) → « Tout voir » : ligne d'état (« Connecté au WHOOP 4.0 · la fréquence cardiaque arrive ·
  historique à jour il y a 2 min · batterie 73 % »), pastilles Tout · Connexion · Fréquence cardiaque ·
  Historique · Batterie · Problèmes, phrases avec icône (FC enregistrée « ×n depuis … », Niveau de batterie
  demandé, FC en direct demandée, Réponse du bracelet : en cours, Historique récupéré, Bracelet déconnecté en
  orange…) ; « Lignes techniques » montre la ligne brute sous chaque phrase et les blocs de lignes sans
  phrase ; Copier / Enregistrer donnent le même fichier qu'avant ; Centre de tests s'ouvre. **Captures à
  envoyer**, et le journal brut copié si une ligne fréquente reste sans phrase.
