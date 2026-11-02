# Entraînement (calendrier du Carnet + onglet Plus regroupé) — fiche du chantier (2 nov. 2026, ~05:30)

**État : chantier terminé côté code** (PR #25, #26, #27 fusionnées, `main` **6b8b423**). Reste la validation sur le téléphone avec la prochaine IPA groupée.

Maquette validée par Mohamed (« Oui, on code ça », 2 nov. ~02:45) : canvas « NOOP – Entraînement et Plus » — https://claude.ai/artifact/1nHYSvnk2EEpGYzgPjxdi4 (slug 0652aa04-df30-4641-adc9-6935b714e495). Valeurs d'exemple.
Artboards : 1 Plus regroupé (6 groupes) · 2 Entraînement · semaine (aujourd'hui) · 3 Entraînement · mois (un jour passé) · 4 Planifier la semaine.

## État du code
- **PR #25 — Plus en 6 groupes** (`feat/more-grouped`) : fusionnée le 2 nov. (~04:05), `main` b1e1825. Rendu `entrainement-1-plus` (release `render-render-more-grouped`) validé.
- **PR #26 — planning + calendrier semaine/mois** (`feat/training-calendar`) : fusionnée le 2 nov. (~05:20), `main` 46e1e14. Rendus `entrainement-2-semaine`, `entrainement-3-mois`, `entrainement-4-planifier` (release `render-render-training-calendar`) validés avec les écarts ci-dessous (widget, ~05:15). CI 7/7.
- **PR #27 — Synthèse d'Aujourd'hui + Coach suivent le planning** (`feat/training-today-coach`) : fusionnée le 2 nov. (~05:25), `main` **6b8b423**. CI 6/6.
- IPA : pas encore (quand Mohamed le dit).
- Branches de rendu : `render/more-grouped`, `render/training-calendar` (à supprimer seulement sur accord).

## Décisions de Mohamed (2 nov., widgets)
- **Planning = jours fixes** : un programme du Carnet par jour de la semaine (ex. lun. Full body A, mer. B, ven. C). Le calendrier montre le prévu et le fait.
- **Contenu du calendrier = muscu + cardio** : séances du Carnet (bleu Effort) et autres entraînements — course, intervalles, détectés (orange) — deux couleurs. Point creux = muscu prévue, point plein = muscu faite, point orange = cardio.
- **Vue = semaine + mois** : bande de 7 jours en haut, détail du jour dessous ; « Mois » (grille du mois, détail du jour dessous, compteurs du mois).
- **Plus = 6 groupes** : Entraînement, Nutrition, Santé et récupération, Analyses, Données, Réglages. Rien n'est supprimé.
- **Stockage du planning : sur l'iPhone** (UserDefaults, sans migration, hors `.noopbak`).
- **Écarts du rendu acceptés** (widget, ~05:15) : voir « Écarts avec la maquette ».

## Ce qui est codé
### Plus (PR #25)
- `Strand/Screens/MoreHub.swift` (partagé, rendu PNG) : `MoreHubGroup` (titre, résumé, icône, teinte : Entraînement bleu Effort, Nutrition doré activité, Santé rose cœur, Analyses accent, Données/Réglages gris), `MoreHubRowLabel`, `MoreHubCard`.
- `StrandiOS/App/RootTabView.swift` : `MoreDestination.hub(groupe)` ; **Entraînement** et **Nutrition** ouvrent directement leur écran ; les 4 autres ouvrent `MoreGroupScreen` (les anciennes lignes `MoreRow`, inchangées). Une seule `navigationDestination`. Groupes : Santé et récupération = Santé, Stress, Respirer, Rythme, Carnet de laboratoire ; Analyses = Ce qui vous fait bouger, Intelligence, Perspectives, Explorer, Comparer ; Données = Données fusionnées, Apple Santé, Mi Band, Sources, Sauvegarde, Export Raccourcis, Limites de NOOP ; Réglages = Alarmes, Automatisations, Centre de test, Siri et Raccourcis, Économie d'énergie, Paramètres. Entraînements, Intervalles et En direct sont dans l'écran Entraînement.
- iOS ne lit plus `MoreSectionPrefs` (plus de sections repliables) ; le type reste (jumeau Android). La note de bas de maquette (« Rien n'est supprimé… ») n'est pas reprise (note de revue).
### Planning + calendrier (PR #26)
- **Règles pures** `Strand/Data/TrainingPlan.swift` (tests `TrainingPlanTests`) :
  - `TrainingWeekPlan` : jour ISO (1 = lundi) → id de programme ; clé UserDefaults `training.weekPlan.v1` (JSON) ; `since` = jour du premier enregistrement : **les jours d'avant n'ont pas de prévu**, donc jamais « manqués » ; un programme supprimé libère son jour (`keepingPrograms`).
  - `TrainingCalendar` : jour ISO quel que soit le premier jour du calendrier, lundi de la semaine, 7 jours, cases du mois (lundi d'abord, blancs avant le 1er, ligne complétée).
  - `TrainingDays.buildTrainingDays` : par jour, programme prévu (`planDecision`), séances du Carnet faites (terminées avec ≥ 1 série de travail, règle de la rotation), autres activités. **Manquée** = prévue, rien soulevé, jour passé. `sessionTally` : toutes les séances faites de la période / jours prévus (une séance faite un autre jour compte). `periodTotals` : activités et minutes.
  - `splitLiftWorkouts` : la ligne `workout` d'une séance du Carnet (même début, ±60 s) n'est jamais recomptée en activité.
  - `programSummary` : supersets / exercices seuls, séries totales, durée habituelle (`LiftRotation.typicalMinutes`), dernière fois, 2 premiers blocs avec les étiquettes `LiftSuperset.tag` (« A1 Squat · A2 Tirage »).
- **Écran** (`LiftLogView` devient « Entraînement », même route `TabRoute.liftLog` depuis la Synthèse) : en-tête titre + « Semaine du 2 au 8 novembre » / « Novembre 2026 » + sélecteur **Semaine | Mois** ; barre « ‹ CETTE SEMAINE · 0 / 3 SÉANCES › » (ou « CE MOIS-CI ») ; bande de 7 jours ou grille du mois + légende ; compteurs du mois (séances muscu faites / prévues, cardio, au total) ; **jour choisi** : carte **Prévu** (ou **Manquée** en gris) avec forme, ≈ durée, la dernière fois, 2 blocs + « + n autres », **Démarrer** et **Changer** (aujourd'hui seulement) ; puis ce qui a été fait (Carnet · heure · durée · séries · Effort dans l'échelle choisie → fiche de la séance ; activité · source · heure · durée · kcal) ; sinon « Rien de fait aujourd'hui pour l'instant. » / « Rien d'enregistré ce jour-là. » / « Jour de repos. ».
  - **Carnet de force · programmes** : chaque programme (forme · séries, pastilles des jours prévus, → éditeur), Nouveau programme, Importer (Excel), lien **Planifier** (feuille `TrainingPlanSheet` / `TrainingPlanForm` : un menu par jour, Repos ou programme, encadré « Si tu rates un jour », Annuler / Enregistrer).
  - **Progression** compacte (4 compteurs, Voir → écran Progression).
  - **Autres activités** : Démarrer une activité (même parcours que Entraînements : choix du sport puis séance en direct), Intervalles, FC en direct ; **Tout l'historique** → écran Entraînements.
- Vues pures dans `Strand/Screens/TrainingCalendarViews.swift` (rendu `TrainingRenderTests`, ajouté à `fork-render-on-push.yml`). `TrainingMenu` : un `Menu` dessiné comme son seul libellé quand `\.trainingMenusAsLabels` est posé (le rendu PNG ne sait pas dessiner un `Menu` : rectangle jaune).
### Synthèse + Coach (PR #27)
- `TrainingWeekPlan.planDecision(for:calendar:)` = **seul résolveur** (programme, repos, ou rien avant le plan / sans plan), lu par le calendrier, la Synthèse et le Coach.
- Synthèse (`LiquidTodayView.loadTodaySession`) : séance en cours ou faite d'abord ; sinon le programme prévu aujourd'hui, ou **Repos** « jour de repos du planning » (`TodaySynthesisLogic.Session.State.rest`) ; sans plan, la rotation (repli).
- Coach : bloc **WEEK PLAN** après LIFT PROGRESSION (`CoachFiche.weekPlanText`, `AICoachEngine.trainingWeekPlanBlock`) : jours et programmes, séances faites / prévues cette semaine, jours manqués, aujourd'hui ; consigne de suivre le planning plutôt que la ligne de rotation. « Ce que lit le Coach » : « …, planning de la semaine ». Détail : `docs/fork/coach-instructions.md`.
- Feuille Planifier : « Un programme par jour. Le calendrier, la Synthèse d'Aujourd'hui et le Coach suivent ce planning. »

## Écarts avec la maquette (acceptés par Mohamed, 2 nov. ~05:15)
- Sélecteur **Semaine | Mois** dans les deux vues (la maquette semaine avait un bouton « Mois ») ; le titre reste « Entraînement », le mois est en sous-titre.
- **Changer** = menu des autres programmes qui **démarre** celui choisi aujourd'hui (ne modifie pas le planning).
- Démarrer / Changer seulement **aujourd'hui** ; un jour futur montre le prévu sans boutons.
- **Tout l'historique** ouvre l'écran Entraînements (toutes les séances, muscu comprise) ; la fiche d'une séance du Carnet s'ouvre depuis le jour du calendrier. La carte d'en-tête « Ton carnet » et la liste « Séances récentes » disparaissent.
- La carte Progression compacte ne montre plus « Charges à monter » ni « À prioriser » (toujours dans l'écran Progression).

## Reste à faire
- Validation sur le téléphone avec la prochaine IPA : Plus (6 groupes, chaque entrée atteignable) ; planifier la semaine ; Démarrer depuis le jour ; Changer ; jour manqué ; vue mois ; Synthèse un jour prévu et un jour de repos ; question au Coach « Je fais quoi aujourd'hui ? ».
- Ensuite : chantier 6 (bannières et widgets) — la bannière de séance et le widget Séance du jour lisent `planDecision`.
