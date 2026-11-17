# Chantier 24 — Habitudes

**État** (15 nov. 2026) : 4 choix faits, **maquette validée** par Mohamed : https://claude.ai/artifact/1xoQf4BcjsQ8xHjeYUe3x1 (source : `docs/fork/maquettes/chantier-24-habitudes.html`). **PR A #166 (données) verte 17/17 ; PR B #167 (écrans) et PR C (bannière, icône, Coach) ouvertes, empilées.** À fusionner dans l'ordre A → B → C après la validation de Mohamed, puis IPA `build/habitudes`. (Les n° 22 et 23 sont les micronutriments et le dossier médical, PR #164.)

## La demande (15 nov., mots de Mohamed résumés)
- Une section « Habitudes », ouverte depuis la photo de profil (feuille Plus).
- L'utilisateur crée ses propres habitudes (ex. lecture, méditation).
- Chaque habitude a un chronomètre : un appui démarre, un appui arrête ; le chrono continue si l'app est quittée ou le téléphone verrouillé.
- Ajouter une session après coup, à la main.
- Une note libre par session (ex. pourquoi elle s'est mal passée).
- Écran d'une habitude : liste des sessions, totaux semaine et mois, graphiques.
- Modifier ou supprimer une session ; modifier ou supprimer une habitude.
- Un raccourci sur l'écran d'accueil pour le chrono.
- **Aucune récurrence ni objectif quotidien** : enregistrement à la demande.
- Le Coach lit tout (notes comprises) et croise avec toutes les données (BPM, récupération, sommeil, nutrition, sport…), **seulement quand on le lui demande**, jamais de lui-même.

## Choix de Mohamed (15 nov., outil à choix multiples)
- **Raccourci = action de l'icône** (appui long) : « Lecture » (la dernière habitude chronométrée) démarre le chrono, ou « Arrêter · Lecture » si un chrono tourne. Remplace « Journal » (iOS n'affiche que 4 actions ; le Journal reste dans Démarrer). Pas de widget.
- **Bannière en direct** (Live Activity) sur l'écran verrouillé et dans la Dynamic Island : habitude, temps qui défile, bouton Arrêter.
- **Un seul chrono à la fois** : démarrer une autre habitude demande d'arrêter celle en cours.
- **Une session qui passe minuit compte pour le jour de son début** (comme une séance).

## Ce que montre la maquette
- **Feuille Plus** : ligne « Habitudes » dans Santé et récupération ; à droite le chrono en cours (« Lecture · 12:34 »), sinon le total de la semaine, sinon rien.
- **Habitudes** : carte du chrono en cours (habitude, « depuis 21:48 », temps, Arrêter) ; une ligne par habitude (icône de couleur, total de la semaine, dernière session, ▶ qui démarre tout de suite) ; « Nouvelle habitude ». État vide : « Crée une habitude, puis touche ▶ pour la chronométrer ».
- **À l'arrêt** : petite feuille avec la durée, une note facultative, Enregistrer, Reprendre, Ne pas garder. Fermer la feuille enregistre sans note.
- **Une habitude** : chrono / Démarrer en haut ; totaux Cette semaine · Ce mois · Depuis le début ; barres des minutes S (par jour) · M (par jour) · 3M (par semaine), toucher une barre → sa valeur, retoucher → le total ; « Quand » (heures des sessions sur 30 jours, frise 00:00–24:00) ; liste des sessions (date, heures, durée, note en italique, « à la main ») ; « + Session passée » ; « ••• » → modifier l'habitude.
- **Session passée / modifier une session** : habitude, date, début, fin, durée calculée, note ; « Supprimer la session ». Refus (bouton grisé + raison) : fin avant début, plus de 12 h, chevauchement d'une autre session de la même habitude.
- **Modifier l'habitude** : nom, couleur (jetons de la palette), icône (symboles SF), « Supprimer l'habitude » avec confirmation « Supprimer Lecture et ses 84 sessions ? ».
- **Écran verrouillé** : bannière + Dynamic Island ; « Arrêter » enregistre sans ouvrir l'app.
- **Coach** : exemple « Est-ce que lire le soir change mon sommeil ? » → ligne « ce qu'il a regardé » (Habitudes, Sommeil) et réponse qui cite les notes.

## Plan technique (proposé, à confirmer au moment du code)
- **Données** : tables `habit` (id, nom, couleur, symbole, createdAt, updatedAt) et `habit_session` (id, habitId, startedAt, endedAt nil pendant le chrono, note, manual, createdAt, updatedAt), unix secondes, sans `deviceId` (comme `meal` et `fast`). **Le chrono = une session sans `endedAt`** : rien ne compte en arrière-plan, l'heure de début suffit et survit à un redémarrage. Au plus une session ouverte (vérifié à l'écriture). Migration **iOS v56-habits** / **Android MIGRATION_47_48** (Room 48, schéma seulement comme le jeûne), les deux `schema_oracle.json`, export Room par `ci/room-schema-habits`. Dans le `.noopbak` avec la base (vérifier au code).
- **Un seul résolveur** des chiffres d'une habitude (totaux, barres, « Quand », jour du début) lu par l'écran, la feuille Plus, la bannière et le Coach. Pur et testé.
- **Supprimer une habitude** supprime ses sessions (une transaction). Pas d'archives.
- **Bannière** : Live Activity sur le modèle de celle du jeûne (`LiveActivityIntent` dans `StrandiOSShared/`, relais enregistré dans `StrandiOSApp.init`). `NOOPWidgetBundle` est à **10 entrées (la limite)** : il faut un bundle imbriqué pour la 11e (prévu dans la feuille de route).
- **Action de l'icône** : `HomeScreenQuickAction` (dynamique : titre selon le chrono en cours), `.logJournal` retiré.
- **Coach** : **un outil** `get_habits` (habitudes, sessions avec notes, sur une période), **rien dans la fiche ni dans le brief** : c'est ce qui garantit qu'il n'en parle pas de lui-même. Une ligne dans le rôle des outils : l'appeler seulement quand la question porte sur une habitude, ne jamais en parler sinon ; croiser avec les autres outils (`get_series`, `get_night`, `get_day_heart_rate`, `get_meals`, `get_workouts`…). Une ligne « Habitudes et notes · seulement quand tu le demandes » dans Ce que lit le Coach. Derrière « Utiliser mes données », comme les autres outils de lecture.
- **Parité Android** : schéma seulement (pas d'écran Android).
- **Animations** : style sobre du chantier 12 (`NoopRollingNumber` pour le chrono, barres qui montent, pas de filtre au repos, Réduire les animations respecté).

## Code — PR A (données), 15 nov.
- **Migration iOS `v56-habits` / Android `MIGRATION_47_48`** (Room 48) : tables `habit` (id, name, colorKey, symbol, createdAt, updatedAt) et `habitSession` (id, habitId, startedAt, endedAt, note, manual, createdAt, updatedAt) ; index `idx_habitSession_habitId_startedAt` et `idx_habitSession_startedAt` ; pas de clé étrangère (supprimer une habitude supprime ses sessions dans la même transaction). Les deux `schema_oracle.json`, l'export Room `48.json` (branche temporaire `ci/room-schema-habits`, jamais fusionnée, à supprimer sur accord).
- `Packages/WhoopStore/Sources/WhoopStore/HabitStore.swift` : `upsertHabit`, `allHabits`, `deleteHabitAndSessions`, `upsertHabitSession`, `runningHabitSession`, `habitSessionsStarted` (par **début**, d'une habitude ou de toutes), `recentHabitSessions`, `habitSessionSummary` (nombre, total, première date, sessions terminées), `deleteHabitSession`. Android : `HabitEntities.kt` (schéma seulement, pas de DAO).
- `Strand/Data/HabitLog.swift` : **le seul résolveur** des chiffres d'une habitude (`resolveHabitFigures` → `HabitFigures` : semaine, mois, tout, barres S · M · 3M, plages « Quand » sur 30 jours) et toutes les écritures (`createHabit`, `editHabit`, `removeHabit`, `startHabitStopwatch`, `stopHabitStopwatch`, `addHabitSessionByHand`, `amendHabitSession`, `removeHabitSession`). Tout écran, la bannière, l'action de l'icône et l'outil du Coach passent par lui.
- **Règles écrites dans le code** : un chrono à la fois (démarrer ferme celui en cours à cet instant ; la question de confirmation est dans l'écran) ; jour d'une session = jour **logique** de son début (`Repository.logicalDayRolloverHour`) ; totaux et barres = sessions **terminées** seulement (le chrono en cours a son propre affichage) ; semaine = lundi → dimanche (`TrainingCalendar.mondayOf`) ; S = 7 jours de la semaine, M = 30 derniers jours, 3M = 12 dernières semaines ; une session passée qui passe minuit donne deux plages dans « Quand ».
- **Refus d'une session à la main ou modifiée** (`HabitSessionProblem`) : fin pas après le début, fin dans le futur, plus de 12 h, chevauchement d'une autre session de la **même** habitude (le chrono en cours compte jusqu'à maintenant). Une session en cours modifiée garde son chrono : seuls son début (dans le passé, sans chevauchement) et sa note changent.
- Note : espaces retirés, vide = pas de note. Nom vide refusé. `habits.revision` (UserDefaults) monte à chaque écriture ; `habits.lastStartedId` = la dernière habitude démarrée (pour l'action de l'icône) ; `HabitLog.onHabitChange` = crochet pour la bannière et l'icône (PR C).
- Tests : `HabitStoreTests` (paquet), `HabitsMigrationTest` (Kotlin), `HabitLogTests` (StrandTests : règles, barres, totaux, plages, écritures).

## Code — PR B (écrans), 15 nov. (#167, empilée sur #166)
- **Feuille Plus** : `MoreSheetEntry.habits` en tête de « Santé et récupération » (icône `timer`) ; à droite le chrono qui défile (`MoreHabitsRunning`, `TimelineView` 1 s) sinon « 5h 20m this week » (somme des `weekSeconds` de `resolveHabitFigures`), sinon rien. `MoreDestination.habits` → `HabitsView`.
- `HabitsView` : carte du chrono en cours, une ligne par habitude (icône, total de la semaine, dernière session ou « en cours », ▶ / ■ à part du lien), « Nouvelle habitude », état vide. Un autre ▶ pendant un chrono → `confirmationDialog` « Lecture tourne · Arrêter Lecture et démarrer Méditation ». La page d'une habitude est poussée par valeur (`HabitRoute`, `navigationDestination` dans `HabitsView`).
- `HabitDetailView` : Démarrer / chrono + Arrêter ; tuiles Cette semaine · Ce mois-ci · Depuis le <1re date> ; barres Semaine · Mois · 3 mois (`HabitBarsChart`, toucher / retoucher) ; « Quand » (`HabitDayStrip`) ; « Tes sessions » avec notes en italique et « ajoutée à la main » ; « + Ajouter une session » ; « ••• » → éditeur de l'habitude ; une habitude supprimée ferme la page.
- **Arrêter enregistre tout de suite** (le chrono s'arrête au toucher, la bannière suit) ; la feuille qui suit (`HabitStopSheet`) propose la note (Enregistrer), Reprendre (`HabitLog.resumeHabitStopwatch` : la même session repart de son début) et Ne pas garder (confirmation). La fermer garde la session sans note.
- `HabitSessionEditor` (ajout / correction : début, fin, durée, note ; le refus sous les champs ; une session en cours ne montre que son début) et `HabitEditor` (nom, 7 couleurs, 12 symboles SF, « Supprimer Lecture et ses 84 sessions ? »).
- **Couleurs** : `HabitPalette.tint` associe la clé stockée à un jeton existant (cyan = `macroFat`, violet = `macroProtein`, orange = `caloriesActivity`, vert = `fastingDone`, bleu = `accent`, rose = `liquidHeart`, jaune = `macroCarbs`). Jamais de couleur locale.
- Une note seule modifiée ne revérifie pas les heures (un chrono oublié plus de 12 h garde sa note).
- 37 clés dans les 10 langues (« Session », « Séance passée »… existaient pour l'entraînement : clés nouvelles « Habit session », « Add a session », « Your sessions », « End time » pour dire « session » et non « séance »).

## Code — PR C (autour), 15 nov. (empilée sur #167)
- **Coach** : outil `get_habits` (`Strand/AI/CoachHabitsTool.swift`, avec « Utiliser mes données » seulement) : par habitude, nombre et total des sessions terminées, puis chaque session (jour du début, heures, durée, « [added by hand] », la note entre guillemets, le chrono en cours) ; `habit` facultatif pour une seule habitude ; 7 à 365 jours. **Rien dans la fiche ni dans le brief.** Rôle des outils : l'appeler seulement quand la question porte sur une habitude ou ses notes, n'en parler jamais de soi-même, croiser avec `get_night`, `get_series`, `get_metric_history`, `get_day_heart_rate`, `get_meals`, `get_workouts` sur la même période. Ligne « Tes habitudes et leurs notes, seulement quand tu le demandes » dans Ce que lit le Coach. Libellé sous la réponse : « Habitudes depuis le 16 oct. ».
- **Bannière en direct** : `HabitActivityAttributes` + `HabitBannerStopIntent` + `HabitBannerRelay` (`StrandiOSShared/`), `HabitLiveActivity` (icône, nom, « depuis 21:48 », temps qui défile, Arrêter rouge ; Dynamic Island : icône + temps), `HabitLiveActivityController` (allumée par défaut, relancée au retour au premier plan après les 8 h d'iOS). **`NOOPWidgetBundle` imbrique un 2e lot** `NOOPWidgetBundleMore` (jeûne + habitudes) : la limite de 10 est levée pour la suite. Tap → `noop://habits` → `NavRouter.openHabits()` → feuille Plus sur Habitudes.
- **Action de l'icône** : `.habitTimer` remplace `.logJournal`. Titre dynamique écrit après chaque changement (`HabitLog.refreshHabitQuickAction`, clés `habits.quickActionTitle` / `habits.quickActionSubtitle`) puis menu réinstallé : « Arrêter · Lecture » / « Lecture » (« Démarrer le chrono ») / « Habitudes ». Toucher : `HabitLog.performHabitQuickAction` (arrête, sinon démarre la dernière habitude) puis la feuille Plus sur Habitudes.
- Tout passe par `HabitLog.onHabitChange` (enregistré dans `StrandiOSApp.init`) → `HabitLiveActivityController.refreshHabitSurroundings`.

## À tester (IPA `build/habitudes`, après la fusion de A, B, C)
- Plus → « Habitudes » (en tête de Santé et récupération) ; sans habitude : état vide ; « Nouvelle habitude » : nom, couleur, icône → la ligne apparaît.
- ▶ → le chrono défile sur la carte, dans la ligne de la feuille Plus et sur l'écran verrouillé / Dynamic Island ; quitter l'app, verrouiller, revenir : le temps a continué. Redémarrer le téléphone : la session est toujours là.
- ▶ d'une autre habitude pendant un chrono → la question, puis la première est arrêtée à cet instant.
- Arrêter (carte, ligne ■, bannière, appui long sur l'icône) → la feuille « Session terminée » (sauf depuis la bannière et l'icône) : note, Enregistrer ; Reprendre ; Ne pas garder.
- Page d'une habitude : totaux, barres S · M · 3M (toucher / retoucher), « Quand », sessions avec notes ; « + Ajouter une session » (refus : fin avant début, futur, plus de 12 h, chevauchement) ; toucher une session → modifier / supprimer ; « ••• » → renommer, couleur, icône, supprimer avec ses sessions.
- Appui long sur l'icône NOOP : « Lecture » (démarre) / « Arrêter · Lecture » ; « Journal » n'y est plus.
- Coach : « Est-ce que lire le soir change mon sommeil ? » → ligne « Habitudes depuis… » + réponse qui croise ; une autre question (« Je fais quoi aujourd'hui ? ») ne parle jamais des habitudes ; le brief non plus.
- **Captures à envoyer** (liste, page, feuille d'arrêt, éditeurs, bannière).

## Découpage proposé
1. **PR A — données** : migration, store, résolveur, tests.
2. **PR B — écrans** : feuille Plus, Habitudes, une habitude, feuilles d'arrêt / session / habitude, traductions dans les 10 langues.
3. **PR C — autour** : bannière en direct (bundle imbriqué), action de l'icône, outil du Coach.
4. **IPA `build/habitudes`** après la PR C (ou quand Mohamed le dit).

## Prompt de démarrage (pour une nouvelle conversation, après la validation de la maquette)
> Chantier 24 — Habitudes, fork NOOP. Lis `docs/fork/feuille-de-route.md` puis `docs/fork/chantier-24-habitudes.md` (choix de Mohamed et maquette validée https://claude.ai/artifact/1xoQf4BcjsQ8xHjeYUe3x1). Code la PR A (données) depuis `main` : revérifie le dernier numéro de migration, puis tables `habit` + `habit_session`, store GRDB sur le modèle de `FastStore`, résolveur pur des totaux, jumeau Room (schéma), tests, vérifications de la feuille de route avant de pousser.
