# Chantier 21 — Le bonhomme d'exécution

Demande de Mohamed (14 nov. 2026) : pendant la séance, juste sous l'exercice à faire, un bonhomme qui fait le mouvement avec une bonne exécution, « un peu comme dans Lift App ».

## Choix de Mohamed (14 nov.)
- **Bonhomme animé dessiné par l'app** (pas de photos, pas d'animations sous licence) : hors-ligne, presque rien en plus dans l'IPA, aux couleurs de NOOP, original (aucune reprise des visuels de Lift App).
- **Petite vignette sous le nom de l'exercice, toucher pour agrandir** : feuille avec le bonhomme en grand, la phase en cours, le tempo, « Ralenti », les muscles en bleu, 3 conseils.
- **Maquette d'abord** : validée le 14 nov. → https://claude.ai/artifact/FHAdxxU4x76FHD3vj6Bx6H

## Le code (PR du 14 nov.)
- `Strand/Data/LiftFigure.swift` : le modèle pur. Squelette vu de profil (une vue de face pour les élévations latérales), segments de longueur fixe, angles absolus (0 = haut, 90 = avant, 180 = bas). Une pose = des angles ; un mouvement = 2 poses (`start`, `end`) adoucies l'une vers l'autre puis retour, tempo fixe (pause 0,5 s au départ, 0,3 s en bas). Un bras ou la jambe arrière peut « atteindre » un point (résolution à 2 segments) : la barre suit une ligne, le pied arrière de la fente et les mains de la traction ne glissent pas. `LiftFigureDrawing.shapes` rend des formes avec un rôle (membre, membre éloigné, muscle, sol, banc, câble, disque, haltère) ; la vue ne choisit que les couleurs (jetons `StrandPalette`).
- `Strand/Data/LiftMovement.swift` : **21 mouvements** (squat, soulevé de terre, SDT roumain, développé couché, développé incliné, développé militaire, rowing, tirage vertical, traction, dips, pompe, curl biceps, extension triceps poulie, fente, hip thrust, élévation latérale, leg extension, leg curl, mollets, crunch, gainage), leurs muscles (`LiftMuscle`, affichés par `LiftMuscleSummary.line`), 3 conseils chacun, le tempo.
- **Un seul résolveur** du mouvement d'un exercice : `LiftMovementChoice.resolveMovement(exercise:choices:)` = le choix de l'utilisateur pour ce nom exact, sinon la reconnaissance sur les mots du nom (`LiftMovement.recognize`, français + anglais, accents ignorés, du plus précis au plus général : « Curl ischios » = leg curl avant curl, « Squat bulgare » = fente avant squat). Quelques noms sont exclus exprès (presse à cuisses, écarté, oiseau, face pull, shrug, lombaires…) : pas de bonhomme plutôt qu'un faux.
- Choix de l'utilisateur : UserDefaults `lift.movementChoice.v1` (JSON nom → mouvement), **hors `.noopbak`** (préférence d'affichage ; le perdre ramène la reconnaissance par le nom). Choisir le mouvement que le nom donne déjà efface l'entrée. Pas de migration, pas de donnée stockée nouvelle → **iPhone seulement**, Android inchangé.
- `Strand/Screens/LiftExecutionView.swift` : `LiftFigureView` (Canvas), `LiftExecutionTile` (vignette 96 × 76 sous le nom de l'exercice dans `LiftSessionView.exerciseCard`), `LiftExecutionSheet` (feuille). Un nom non reconnu : une ligne discrète « Choisir un mouvement pour voir l'exécution ».
- **Seul l'exercice en cours bouge** (`quickEntrySlot ?? currentSlot`) ; les autres cartes montrent une pose fixe (60 % du premier mouvement). Le bonhomme reste fixe quand la porte « mouvement calme » est fermée (`NoopMotionState.poseStill` : Réduire les animations du système, mode économie d'énergie, « Réduire les animations dans NOOP »).
- Ralenti : vitesse × 0,5, l'horloge de la figure est rebasée au changement (pas de saut).
- Poses réglées sur une planche de rendu (prototype JS identique, 3 images par mouvement) avant d'être écrites en Swift.
- Tests : `StrandTests/LiftMovementTests.swift` (reconnaissance FR / EN, choix, longueurs des segments à chaque image, pied et mains fixes, phases dans l'ordre, gainage immobile).
- Traductions : 105 clés dans les 10 langues. « Lifting » existait déjà (« Musculation ») : la phase de montée utilise « Rising » (« Montée »).

## Reporté
- Le bonhomme dans les écrans guidés d'un superset (`LiftSupersetScreen`) et dans la carte superset de la feuille.
- Un choix « aucun bonhomme » pour un exercice (la ligne discrète reste pour un nom non reconnu).
- Mouvements non dessinés : presse à cuisses, écartés, oiseau, face pull, shrug, extension lombaire, tirage horizontal assis (reconnu comme rowing).

## À tester (prochaine IPA)
- Séance avec « Squat barre », « Développé couché », « Rowing barre », « Curl haltères » : vignette sous chaque nom, **seule celle de l'exercice en cours bouge** ; passer à l'exercice suivant → sa vignette se met à bouger.
- Toucher la vignette → feuille : bonhomme en grand, pastille de phase (Prêt, Descente, Pause, Montée…), tempo, « Ralenti » (pas de saut au changement), muscles + « en bleu sur le bonhomme », 3 conseils numérotés.
- « Modifier » → liste des 21 mouvements, en choisir un autre → la vignette change, « Choisi par toi » ; revenir au mouvement d'origine → « Reconnu d'après le nom ».
- Un exercice au nom inconnu (ex. « Presse à cuisses ») → ligne « Choisir un mouvement pour voir l'exécution » → feuille ouverte sur la liste.
- Réduire les animations (système ou NOOP) → bonhomme fixe partout.
- Thème clair : bonhomme noir, muscles bleus, lisible.
- **Captures à envoyer** (vignette dans la carte, feuille, liste des mouvements).
