# Chantier 23 — Dossier médical : PDF dans le Coach (préparé le 15 nov. 2026)

Demande de Mohamed (15 nov.) : « Je veux pouvoir ajouter des PDF sur le Coach, des informations médicales,
et pouvoir les extraire et les ajouter. »

## Existant
- Carnet de labo → « Lire un bilan PDF avec le Coach » (chantier 8, PR #45) : `CoachLabReport`,
  `AICoachEngine.readLabReport` (bloc `document` PDF, 20 Mo / 100 pages), outil `record_lab_values`,
  feuille de vérification, source `lab-pdf`, consentement `ai.labReportConsent` (éteint par défaut).
- Manque : joindre un PDF **depuis le Coach** (le « + »), et les documents qui ne sont pas des bilans.

## Choix de Mohamed (15 nov.)
- **Les 4 types** de document :
  1. **Bilans sanguins** : joints dans le Coach, même extraction et même feuille de vérification que le
     Carnet (réutiliser `CoachLabReport`, pas de deuxième lecteur).
  2. **Traitements et allergies** (ordonnance) : médicaments, doses, allergies, rangés dans une fiche
     « Santé » que le Coach lit à chaque conversation.
  3. **Comptes rendus** (consultation, imagerie, kiné) : un résumé court gardé avec le document, que le
     Coach peut relire (outil, pas dans la fiche si trop long).
  4. **Mesures** (tension, poids, composition corporelle) : ajoutées aux séries existantes
     (`metricSeries`, source dédiée, ex. `doc-pdf`), une par jour et par clé.
- **Le PDF est gardé dans l'app** : réouvrable et supprimable, **hors du `.noopbak`** (comme
  `CoachPhotoStore`).

## Règles
- **Rien n'est écrit sans validation** : chaque extraction passe par une feuille de vérification (valeur
  par valeur, ligne par ligne), doublons signalés et décochés, jamais fusionnés en silence.
- **Consentement** : le PDF part entier chez Anthropic (identité, médecin, labo compris) ; réutiliser et
  élargir `ai.labReportConsent` (libellé à revoir) plutôt qu'en ajouter un second.
- **Un seul point d'entrée** d'extraction (type détecté par le modèle, puis confirmé par Mohamed) ; le
  Coach ne pose jamais de diagnostic et ne change aucun objectif tout seul.
- **Stockage** (à trancher à la maquette) : documents + fiche Santé en fichiers dans Application Support
  (sans migration, hors sauvegarde) **ou** table nouvelle (iOS v56 / Room `MIGRATION_47_48`, avec la
  parité et `schema_oracle.json`) si les traitements / allergies doivent passer dans le `.noopbak`.
- **Fiche du Coach** : traitements et allergies ajoutés à `CoachFiche` + `CoachDataView` (rubrique propre,
  désactivable).
- **Parité** : Coach = iPhone seulement. Les mesures écrites dans `metricSeries` utilisent des clés déjà
  connues des deux plateformes.

## Étapes
1. Maquette (artefact Design) : « + » du Coach → Joindre un PDF, feuilles de vérification des 4 types,
   écran « Dossier médical » (liste des documents, fiche Santé), réglage du consentement.
2. PR A : stockage + point d'entrée d'extraction + bilans depuis le Coach.
3. PR B : traitements / allergies + fiche du Coach.
4. PR C : comptes rendus + mesures.
