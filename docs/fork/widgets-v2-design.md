# Widgets v2 — fiche du chantier (5 nov. 2026)

**État** : maquette faite, à valider. Code après la validation ; l'IPA du chantier 9 partira de `main` avec ces widgets.

## Maquette
Canvas « NOOP – Widgets v2 » — https://claude.ai/artifact/675CLLFJ77Y4qPen5TmxMc. Taille moyenne (338 × 158 pt), valeurs d'exemple, style F (fond #1C1C1E, rayon 22, SF Pro, chiffres arrondis), couleurs des jetons de l'app (sombre).
Artboards : 1 Aujourd'hui · anneaux · 2 Fréquence cardiaque · 3 Stress · 4 Sommeil · 5 Séance du jour (muscu + cardio) · 5b cardio seul · 5c muscu faite · 5d jour de repos · 6 Nutrition (refait).

## Problème (Mohamed, 5 nov.)
On doit comprendre un widget au premier coup d'œil. Aujourd'hui : Séance du jour illisible (blocs A1/B1, points de la semaine) ; Sommeil = couleurs empilées sans légende ; FC sans les seuils de l'app ; anneaux = l'ancien trio Charge / Effort / Rest ; textes en anglais (FC, Stress, anneaux).

## Choix de Mohamed (5 nov.)
- Widgets utilisés (moyens) : anneaux, FC, Stress, Sommeil, Séance du jour. **Nutrition refait** dans le même style.
- **Brief du Coach retiré** de la galerie (libère une place : `NOOPWidgetBundle` était à 10, la limite).
- FC : **rouge** au-dessus du seuil haut (comme la carte FC d'Aujourd'hui), vert sous le seuil bas, seuils en pointillés.
- Séance du jour : le bouton **Démarrer lance la séance** (programme pour la muscu, séance en direct du sport pour le cardio).

## Propositions de la maquette
- **Anneaux** = la carte d'Aujourd'hui : 4 anneaux concentriques (Activité orange, Charge teinte selon le score, Effort bleu avec la bande cible, Repos violet) + 4 lignes (Activité 420 / 600 kcal, Charge 19 · basse, Effort 3,9 · cible 8–14, Repos 76 · nuit 5 h 11 min). FC / VFC / batterie retirées.
- **FC** : titre rose « Fréquence cardiaque », « 3 dernières heures », bpm + âge de la mesure, Min · Moy. · Max ; courbe rose, rouge au-dessus du seuil haut (habituel + 20, suit l'heure), verte sous le seuil bas (plus bas éveillé), étiquettes « haut 114 » / « bas 68 ». Seuils calculés par l'app à la publication (`TodayHRAlert.thresholds`, `HabitualHR`).
- **Stress** = la carte d'Aujourd'hui : niveau en mots (Calme / Modéré / Élevé) + « 2,9 sur 3 · cette heure », bandes colorées nommées, heures en mouvement grisées, 06:00–22:00, Élevé (durée) · Moy. · Pic.
- **Sommeil** : durée, coucher → réveil, dette, coucher conseillé ; **hypnogramme en 4 lignes** (Éveillé, Paradoxal, Léger, Profond) + légende avec la durée de chaque phase.
- **Séance du jour** : la séance (nom, « Muscu · 4 blocs · ≈ 55 min », Démarrer blanc) et le cardio (sport, « Cardio · 30 min », Démarrer rose) ; « Cette semaine · 0 / 2 séances faites » ; faite = coche bleue « Faite · 52 min » ; repos = « Jour de repos · Prochaine : … ». Plus de blocs A1/B1 ni de points de la semaine.
- **Nutrition** : anneau vert des kcal mangées / objectif, 3 barres Protéines (violet) / Glucides (jaune) / Lipides (cyan), Reste · Dépensé · Bilan.
- Tout en français (mise en mots côté app, comme les widgets du jour).
