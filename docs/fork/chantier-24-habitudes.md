# Chantier 24 — Habitudes

**État** (15 nov. 2026) : demande reçue, 4 choix faits, **maquette à valider** : https://claude.ai/artifact/1xoQf4BcjsQ8xHjeYUe3x1 (source : `docs/fork/maquettes/chantier-24-habitudes.html`). Pas de code avant la validation. (Les n° 22 et 23 sont les micronutriments et le dossier médical, PR #164.)

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

## Découpage proposé
1. **PR A — données** : migration, store, résolveur, tests.
2. **PR B — écrans** : feuille Plus, Habitudes, une habitude, feuilles d'arrêt / session / habitude, traductions dans les 10 langues.
3. **PR C — autour** : bannière en direct (bundle imbriqué), action de l'icône, outil du Coach.
4. **IPA `build/habitudes`** après la PR C (ou quand Mohamed le dit).

## Prompt de démarrage (pour une nouvelle conversation, après la validation de la maquette)
> Chantier 24 — Habitudes, fork NOOP. Lis `docs/fork/feuille-de-route.md` puis `docs/fork/chantier-24-habitudes.md` (choix de Mohamed et maquette validée https://claude.ai/artifact/1xoQf4BcjsQ8xHjeYUe3x1). Code la PR A (données) depuis `main` : revérifie le dernier numéro de migration, puis tables `habit` + `habit_session`, store GRDB sur le modèle de `FastStore`, résolveur pur des totaux, jumeau Room (schéma), tests, vérifications de la feuille de route avant de pousser.
