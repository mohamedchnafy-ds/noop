# Chantier 25 — Réveil adaptatif et alarme Fajr

**État** (16 nov. 2026) : spec validée par Mohamed, 4 choix faits (outil à choix multiples), **PR #170 fusionnée** (6/6 verte, `main` 090eb36 ; iPhone, sans migration). **IPA `build/reveil-adaptatif`** = `main` 090eb36 (release `ipa-build-reveil-adaptatif`), à valider (liste « À tester » ci-dessous). Pas de maquette : spec écrite validée, rendu à valider sur captures. Un premier passage de la CI avait un seul échec, `AlarmWakeTimeLabellingTests` : le contrôle « le bracelet sera armé » doit rester dans `nextStrapAlarm` ; remis dans l'entonnoir, sur les deux chemins.

## La demande (16 nov., spec de Mohamed résumée)
1. **Mode adaptatif par alarme** : réglage = heure la plus tôt + fenêtre (défaut 30 min). La nuit, l'app écoute la FC du WHOOP 4.0 en direct, repère une sortie de cycle (remontée de FC au-dessus du creux de la nuit) et fait vibrer le bracelet au meilleur moment de la fenêtre. **La fin de la fenêtre est garantie** : l'alarme du bracelet (firmware) y est armée, l'heure n'est jamais reculée.
2. Modèle : Android `com.noop.alarm` (`SleepWindowWatcher`, `SmartAlarmScheduler`, `SmartAlarmStore`). iOS en sideload : pas de sonnerie critique, le réveil = la vibration du bracelet.
3. **Question au réveil** en un tap « fatigué / en forme », qui ajuste la détection jour après jour.
4. **Coach** : l'heure du réveil et l'état des alarmes.
5. **Fajr** : horaires de la Masjid At-Tawba (Bagnols-sur-Cèze) via Mawaqit, récupérés chaque jour et gardés sur le téléphone ; une 2e alarme ancrée sur l'**adhan** (pas l'iqama), avance 10 / 20 / 30 / 40 min, même logique adaptative dans cette marge, **jamais après l'adhan**. Réglages par alarme.

## Ce qu'on a trouvé avant de coder
- **Mawaqit n'a pas de clé développeur gratuite.** Sa bibliothèque officielle (`mawaqit` sur PyPI, « The official Python library for the MAWAQIT API ») dit : *« Use of the MAWAQIT API is not authorized outside of the official MAWAQIT applications »*. L'accès se fait par un **jeton de compte** (`POST /api/2.0/me` en Basic → `apiAccessToken`), envoyé dans l'en-tête `Api-Access-Token`. Les horaires : `GET https://mawaqit.net/api/2.0/mosque/{uuid}/prayer-times` → `calendar` (12 mois, chaque jour = Fajr, Shuruq, Dhuhr, Asr, Maghrib, Isha ; 7 heures quand la mosquée affiche l'Imsak, Fajr = la 2e).
- **La mosquée** : `mawaqit.net/fr/m/masjid-tawba`, UUID public `0a9b8cab-baed-4cf6-8b23-af1d4e24e4c0`, 44,1607 N · 4,6188 E, Europe/Paris.
- **Le calcul sur le téléphone** à 15° (l'angle de Mawaqit pour la France) tombe **1,6 à 5,5 min avant** l'adhan de la mosquée sur **toute l'année 2026** (comparé jour par jour au calendrier publié). Il ne donne donc jamais une heure après l'adhan.
- Le BLE iOS en arrière-plan (`bluetooth-central`, déjà déclaré) garde l'app en vie tant que le bracelet envoie la FC (profil 0x2A37) : c'est ce qui fait tourner la détection la nuit. Pas de minuterie fiable en arrière-plan, donc tout est piloté par les arrivées de FC ; la fin de fenêtre, elle, ne dépend que du firmware du bracelet.

## Choix de Mohamed (16 nov.)
- **Source Fajr** : *jeton dans l'app + calcul*. Le jeton Mawaqit est collé dans l'écran Alarmes (trousseau, jamais dans le code ni dans le `.noopbak`). Sans jeton ou si l'API refuse : calcul à 15°.
- **Fin de fenêtre après un buzz adaptatif** : *gardée sauf réponse*. Elle reste armée ; elle n'est annulée **pour ce matin seulement** que si Mohamed répond « Fatigué / En forme » ou touche « Je suis réveillé » avant l'heure limite.
- **Écart Fajr / alarme principale** : **45 min**. Deux fenêtres d'alarmes différentes dont les heures limites sont à 45 min ou moins → une seule alarme, la plus tôt (donc jamais après l'adhan).
- **Apprentissage** : *le seuil seulement*. La fenêtre reste celle réglée.

## Le code (une PR)
- `Strand/Data/WakePlan.swift` (pur) : `WakeWindow` (début, heure limite, adaptatif), `WakePlan.mainWindows` (heure limite = heure la plus tôt + fenêtre, tirée de `AppModel.nextSmartAlarmDate`, donc **identique à avant quand le mode adaptatif est éteint**), `fajrWindows` (adaptatif : [adhan − avance, adhan] ; classique : un buzz à adhan − avance), `merged` (45 min), `upcoming` (construit depuis 45 min **avant** maintenant, fusionne, puis coupe au futur : un Fajr passé il y a 20 min absorbe toujours l'alarme principale de dans 15 min ; « je suis réveillé » ne ressuscite pas l'alarme fusionnée).
- `Strand/Data/AdaptiveWake.swift` (pur) : `AdaptiveWakeDetector` (port de `SleepWindowWatcher` : creux = FC lissée la plus basse ≤ 90 bpm, 30 mesures minimum ; **en plus** : remontée tenue 3 mesures de suite, creux pris dès 3 h avant la fenêtre), `AdaptiveWakeSession` (une mesure / 10 s, buzz puis jusqu'à 3 buzz à 45 s d'écart, jamais à ou après l'heure limite), `WakeLearning` (rejeu : seuil 6 bpm, 3 « fatigué » sur les 5 dernières réponses à un réveil adaptatif → +1 bpm, 4 « en forme » → −1, bornes 4–12, chaque décision repart d'un compte vide ; par alarme).
- `Strand/Data/FajrTimes.swift` : `Mawaqit` (lecture de la réponse, Fajr du jour dans le fuseau de la mosquée, année vérifiée, actualisation après 20 h), `FajrCalculator` (soleil à 15°), `FajrTimes` (cache `Application Support/Fajr/mawaqit-timetable.json`, entonnoir `adhan(on:)` : mosquée sinon calcul), `MawaqitTokenStore` (trousseau `com.noop.mawaqit`), `MawaqitClient` (récupération quotidienne, nouvel essai 1 h après un échec, seul l'UUID de la mosquée part).
- `Strand/Data/WakeSchedule.swift` : clés UserDefaults (`alarm.adaptive.*`, `alarm.fajr.*`, `alarm.wakeJournal.v1`, `alarm.wakeDismissed.v1`, hors `.noopbak`), `WakeJournal`, et **`WakeSchedule.upcomingWindows`, le seul résolveur** lu par le bracelet, les notifications de secours, le guetteur de nuit, l'écran Alarmes, la ligne de la feuille Plus et le Coach.
- `Strand/App/AdaptiveWakeController.swift` : `AdaptiveWakeController` (nourri à chaque FC en direct par `AppModel`, buzz par `BLEManager.buzzStrapOnce`, journal du bracelet : écoute, buzz, fenêtre finie sans détection avec le nombre de mesures et le creux, ou « aucune FC n'est arrivée »), `WakeNotification` (secours à chaque heure limite en notifications uniques pour 8 matins, question adaptative ; catégories « Fatigué / En forme / Je suis réveillé » ajoutées à `ElanReminder.registerCategories`).
- `AppModel.applySmartAlarm` : quand le mode adaptatif ou Fajr est allumé, le bracelet est armé à **l'heure limite de la prochaine fenêtre** (le bracelet ne garde qu'une alarme) et réarmé sur la suivante dès qu'elle passe ; sinon l'ancien chemin (notification répétée) reste tel quel. `handleWakeResponse` / `answerWake` : réponse au journal, matin retiré du plan.
- Écran Alarmes : `WakeFeedbackCard` (en haut, tant qu'un réveil attend sa réponse, 12 h au plus), `AdaptiveModeSection` dans la carte du bracelet (« Au plus tôt » à la place de « Réveil à », fenêtre 10–60 min, « Garanti à 07:00, jamais plus tard », seuil appris), `FajrAlarmCard` (prochain adhan et sa source, avance 10/20/30/40, adaptatif dans la marge, note des 45 min, jeton Mawaqit). Sous le compte à rebours : « Adaptatif : dès 06:30, au plus tard 07:00 ». Texte d'honnêteté mis à jour (il renvoyait vers Android).
- Coach : bloc **ALARMS** de la fiche (`CoachFiche.alarmBlock`, depuis `WakeSchedule.facts`) + ligne « Alarmes » dans Ce que lit le Coach.
- Tests : `StrandTests/AdaptiveWakeTests.swift` (plan, fusion, détecteur, séance, apprentissage, Mawaqit, calcul contre 6 jours du calendrier de la mosquée, notifications, bloc du Coach).
- **Parité** : iPhone seulement, aucune donnée en base, pas de `.noopbak`, pas de migration ; Android garde son alarme téléphone.
- Piège rencontré : une `func clock(_:)` de plus comptait comme appel de `CircadianEngine.clock/1` (gouvernance de parité) → noms `wakeClock`, `fajrClock`, `alarmClock`.

## Action de Mohamed
- **Le jeton Mawaqit** : écrire à **support@mawaqit.net** pour demander un accès à l'API pour un usage personnel (rappeler qu'elle est réservée à leurs apps). S'ils donnent un jeton : NOOP → Plus → Alarmes → carte « Alarme Fajr » → « Colle ton jeton MAWAQIT » → « Enregistrer le jeton ». Sans réponse, l'alarme Fajr marche déjà avec le calcul (quelques minutes avant l'adhan).

## À tester (prochaine IPA)
- Alarmes → carte du bracelet → **Mode adaptatif** : « Au plus tôt », fenêtre 30 min, « Garanti à … », seuil « +6 bpm » ; sous le compte à rebours « Adaptatif : dès …, au plus tard … » ; le compte à rebours vise l'heure limite.
- **Une nuit** avec le bracelet, Bluetooth, NOOP en arrière-plan (pas fermé d'un glissement) : le bracelet vibre dans la fenêtre ou à l'heure limite ; notification « Réveil adaptatif » avec Fatigué / En forme / Je suis réveillé ; une réponse avant l'heure limite → pas de 2e vibration à l'heure limite. Journal du bracelet : « Adaptive wake: listening… », puis « strap buzzed at … » ou « window ended without a lighter phase (N samples…) ». **Si « no live heart rate reached the phone » apparaît, la FC ne parvient pas la nuit : le dire.**
- Carte « Comment te sens-tu ? » en haut d'Alarmes le matin ; elle disparaît après un tap.
- **Fajr** : allumer, prochain adhan affiché avec « Calculé sur le téléphone… » ; avance 10/20/30/40 ; « Prochaine fenêtre : … à …, l'adhan » ; avec l'alarme principale à moins de 45 min, une seule vibration ce matin-là.
- Jeton Mawaqit (si obtenu) : « Les horaires de la mosquée via MAWAQIT, mis à jour le … » ; jeton faux → message de refus, le calcul reste.
- Coach : « À quelle heure je me réveille demain ? », « Mon alarme Fajr est active ? ».
- **Captures à envoyer** : écran Alarmes (carte du bracelet en mode adaptatif, carte Fajr, carte du ressenti).

## Limites connues
- Le réveil adaptatif ne marche que si la FC arrive la nuit (bracelet porté, Bluetooth, app non fermée). Sinon c'est l'alarme du bracelet à l'heure limite qui réveille.
- Les notifications de secours sont planifiées 8 matins d'avance et refaites à chaque ouverture, reconnexion ou réglage : après plus d'une semaine sans ouvrir l'app ni connexion, elles s'arrêtent (le bracelet, lui, reste armé sur la prochaine heure limite).
- WHOOP 5/MG : l'alarme du bracelet demande les sondes du protocole (comme avant) ; non testé.
