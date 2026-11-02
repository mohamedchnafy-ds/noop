# Écran Aujourd'hui — design retenu (1er nov. 2026, version finale validée ; corrections du 2 nov.)

Maquettes : canvas « NOOP – Écran Aujourd'hui » — https://claude.ai/artifact/AS7gYuUQJkYbitFaXQjf3w
Le canvas ne contient que la version finale : « Premier écran », « Suite du défilement », « Fréquence cardiaque · onglet Journée », « FC · seuil franchi sans activité (exemple) », « Tuile Calories · matin · après séance · objectif dépassé ». Les pistes écartées (directions A, B, C, barres 7 jours, variantes de la tuile Calories, jauges horizontales, petits anneaux complets) restent dans l'historique des versions de l'artefact.

Principe : garder l'écran actuel (mot NOOP, 3 anneaux Charge/Effort/Repos, badge WHOOP, FC en direct, tuiles, Vos cartes, Sources, mêmes couleurs). Pas de phrase générée, pas de décor : on réutilise les composants existants. Graphiques légers : pas de lignes en pointillés ni de grille.

## Corrections du 2 nov. 2026 (validation sur le téléphone) — fusionnées dans `main`
- **Calories pendant une séance** (PR #20, fusion 45709de) : la journée ne compte en activité que la FC au-dessus de 50 % de la réserve (~125 bpm), donc la muscu partait en « repos ». Dans chaque séance enregistrée (Carnet, manuelle, détectée — `Repository.workoutRows`), l'activité = estimation de la séance (`Calories.estimateBoutCalories`, seuil 30 %, le chiffre de la fiche séance) − repos des mêmes échantillons. Repos inchangé. Un seul entonnoir : `NutritionDayReader.recordedSessions` + `TodayEnergy.dayEnergySplit` (Aujourd'hui, « dépensé » de Nutrition, fiche du Coach, objectif par défaut). Affichage seulement : le total enregistré (`activeKcalEst`, Tendances) ne change pas.
- **Minuit** (PR #21, fusion 38926b3) : le jour logique bascule à 00:00 quand le cycle du jour est « 00:00 » (04:00 sinon, comme upstream) — `Repository.logicalDayRolloverHour`. Le cycle passe à 00:00 **une fois** au lancement (`Repository.applyMidnightDayDefaultOnce`, clé `fork.dayCycleMidnightDefault.v1`) ; Réglages → Cycle du jour peut le remettre. L'écran se recharge seul au changement de jour (horloge 30 s, à l'apparition, au retour dans l'app). La durée de la nuit sous Repos reprend la dernière nuit tant que la nouvelle n'est pas enregistrée (même règle de fraîcheur que le score).
- **FC en direct : 2 seuils toujours visibles** (PR #22, fusion 486fd3d) : trait orange pâle en haut (habitude + 20), trait vert pâle en bas (plancher éveillé), plage claire entre les deux (remplace la bande repos → habituel). Pendant la calibration : **seuils provisoires** haut = FC repos + 30, bas = FC repos, « seuils provisoires » sur la ligne sous la courbe. Franchi au repos (règle inchangée : pas de séance, iPhone immobile, 3 min) : **orange au-dessus, vert en dessous** (courbe, chiffre, sous-titre, libellé du seuil). Ligne sous la courbe : « bas 58 · haut 91 » avec un trait de leur couleur. Rendu : release `render-render-today-hr-thresholds` (`4-fc-seuil`, `4b-fc-seuil-bas-et-provisoire`).

## Changements validés
1. **En-tête** : les 4 boutons actuels (photo/réglages, +, batterie, personnaliser) passent sur une ligne au-dessus du titre, avec la date à gauche ; « Aujourd'hui » n'est plus coupé.
2. **Anneaux** : sous le chiffre, dans l'anneau, une petite ligne — Charge « calibration » (anneau en 4 segments, n/4 rempli), Effort « cible 12–14 » (bande cible sur l'anneau), Repos « 3h 41m » (la nuit seule ; les siestes restent dans Sommeil). Sous l'anneau : le nom seul (CHARGE ›, EFFORT ›, REPOS ›). Mini-frise 7 jours retirée.
3. **Calories, FC au repos, VFC** : une rangée de 3 **demi-anneaux** (compteur 180°, chiffre dans l'arc) en bas de la carte des anneaux, visibles sans défiler.
   - Calories : chiffre = total du jour. **Deux couleurs nommées** sous l'arc : **doré = activité** (mouvement, exercices ; objectif réglable) et **cuivre = repos** (le reste de la dépense) — « activité 185/480 », « repos 760 ». L'arc va de gauche à droite (repos puis activité), échelle = repos du moment + objectif d'activité, donc **arc plein quand l'objectif d'activité est atteint** ; au-delà, l'échelle s'étend et un petit trait marque l'objectif.
   - FC au repos et VFC : **min à gauche, max à droite = min et max des 30 dernières nuits** ; zone claire = ta normale personnelle (absente tant que la calibration n'est pas finie) ; point = la nuit dernière.
4. **Fréquence cardiaque** : remontée juste sous la carte des anneaux, avant la Synthèse. **Même carte qu'aujourd'hui** (titre « BATTEMENTS PAR MINUTE › », chiffre en rose à droite, sous-titre, courbe lissée en dégradé rose, point final avec halo, pied **Min / Moy. / Max**), **sans grille ni pointillés**, avec :
   - sélecteur **En direct | Journée** dans l'en-tête de section, même style que « 14 nuits | 30 jours » de Sommeil ; « En direct » grisé pour un jour passé ou sans flux ;
   - En direct : plage claire entre les deux seuils (voir corrections du 2 nov.) ;
   - **Règle : aucun texte dans la zone de la courbe.** Les petits libellés (seuils, sommeil) vont sur une ligne sous le graphique, pour ne jamais être recouverts ;
   - Journée : **ta journée habituelle en aire grise très claire** (HabitualHR, 14 jours, toujours chargée, bouton « Journée habituelle » retiré) ; ligne sous la courbe « ta journée habituelle · sommeil · repos 62 » ; axe depuis minuit ;
   - **min et max marqués d'un simple point rose** sur la courbe ;
   - **zone dans le sous-titre** : « En direct · zone repos » (sous la zone 1), sinon « zone N » ;
   - mode Journée : sous-titre « Moyenne sur 5 min · depuis minuit », **sommeil en bande bleutée**, 4 heures sur l'axe.
   - **Courbe hors de ta plage, sans activité** :
     - seuil haut = **ton habitude à cette heure + 20 bpm** (provisoire : FC repos + 30) ;
     - seuil bas = **la plus basse de tes moyennes sur 5 min éveillées (hors sommeil) des 14 derniers jours** (provisoire : FC repos) ;
     - seulement si **aucune séance en cours** et **aucun mouvement de l'iPhone depuis 3 min** (capteur Mouvements et forme : le bracelet n'envoie pas le mouvement en direct, seulement à la synchro toutes les 7–15 min), et après **3 min** au-delà du seuil ;
     - au-dessus : orange, « Plus haute que d'habitude au repos · 4 min » ; en dessous : vert, « Plus basse que d'habitude, éveillé · 3 min ».
5. **Synthèse** : sous la carte FC, toujours ouverte, 3 lignes chiffrées — Dette de sommeil (calcul de Sommeil, « aucune » sous 10 min), Séance du jour (rotation du Carnet : programme fait le moins récemment, ou celui fait aujourd'hui marqué « faite » ; durée ≈ moyenne de tes séances de ce programme), Coucher conseillé. Pas d'heure au-dessus de la Synthèse.
6. **Démarrer une session (BETA)** : placé après la Synthèse.
7. **Doublons retirés** (filtrés à l'affichage et dans les éditeurs, choix enregistrés intacts) : tuiles Repos, Effort, Récupération (déjà dans les anneaux) ; tuiles Calories, FC repos, VFC (remontées) ; carte « Constantes de récupération » ; cartes VFC et FC au repos de « Vos cartes ». Restent en Métriques clés : Respiratoire, Oxygène, Pas (+ Poids / Temp. peau si choisis).
8. **Valeurs absentes** : « pas de donnée » au lieu de « – ».

Ordre final : en-tête → NOOP → carte anneaux (+ demi-anneaux Calories/FC repos/VFC) → Fréquence cardiaque → Synthèse → Démarrer une session → Métriques clés → Afficher toutes les métriques → Derniers entraînements → Vos cartes (Stress, Âge fitness, Vitalité) → Sources de données.
Ordres déjà enregistrés : à la première ouverture, FC puis Synthèse remontent juste sous les anneaux (une fois) ; la carte supprimée est filtrée à l'affichage ; le texte enregistré reste lisible par Android.

## Décisions d'alignement (1er nov. 2026, après la fusion de Sommeil — PR #7)
Quand la maquette contredit ce que Sommeil a codé, Sommeil fait foi.
- **Couleurs** : FC au repos en rouge (comme les bpm), VFC en vert menthe (comme la courbe VFC de Sommeil), sommeil en bleu. Durées au format de Sommeil (« 3h 41m », « 2h 23m »).
- **Orange / vert** : orange pour la courbe FC au-dessus du seuil haut, vert (`statusPositive`) sous le seuil bas. Calories : doré vif (activité) et cuivre foncé (repos), deux jetons de couleur dans le design system.
- **Coucher conseillé** = réveil habituel − besoin de sommeil (8h, même besoin que Sommeil) ; sous-titre « 8h avant ton réveil habituel de HH:MM » ; la dette reste sur sa propre ligne. **Réveil habituel** = médiane des heures de réveil des 14 dernières nuits (3 nuits minimum), sinon « pas de donnée ».
- **Calories** : objectif = calories d'**activité**, réglable dans Réglages (par défaut : moyenne des 14 dernières journées complètes). Repos et activité **recalculés à l'affichage** (voir corrections du 2 nov. pour les séances) : rien de stocké, pas de migration. Calories Apple Santé seulement s'il n'y a aucune FC du bracelet ce jour-là (alors seule la part activité).
- **Zone normale** FC au repos / VFC = la référence de la récupération (`chargeBaselines`), centre ± 1 écart-type, vide pendant la calibration.
- **iPhone seulement** : Android n'est pas touché (à expliquer dans la PR) ; aucune donnée stockée ne change.

## Statut
- Canvas final validé le 1er nov. 2026 (11:10).
- Code : PR #8 (`feat/today-redesign`), fusionnée le 1er nov. 2026 (94a113e). Corrections du 2 nov. : PR #20, #21, #22 fusionnées (`main` 486fd3d). À valider sur le téléphone avec la prochaine IPA groupée.
- Ajustement après rendu : demi-anneaux élargis (rayon 38, largeur 96) et chiffre resserré, pour qu'un total à 4 chiffres (« 2 000 kcal ») ne touche pas l'arc.
- Réglage : Réglages → section « Experimental · Liquid Today » → « Objectif de calories d'activité » (0 = moyenne automatique des 14 jours).
- Mouvements et forme : l'iPhone demande l'autorisation la première fois qu'un seuil est franchi ; refusée, la courbe ne change jamais de couleur.
