# Coach — fiche du chantier (mise à jour : 2 nov. 2026, ~02:00)

Maquettes : canvas « NOOP – Coach » — https://claude.ai/artifact/C6GpBDAKqyRfD7sprKeEmX
Artboards : 1 Nouvelle conversation · 2 Conversation · 3 Séance proposée (séance mixte) · 4 Historique · 5 Photo jointe · 6 Ce que le Coach doit savoir sur toi · 7 Ce que lit le Coach · 8 Menu ⋯. Cartes Repas / Produit : canvas « NOOP – Nutrition » (artboards 5, 6, 8).
Instructions : `docs/fork/coach-instructions.md` (**v1.6** : rôle intégré + Outils + nutrition + étiquettes).
Code (tout sur `main`) :
- **Correctif des plantages (2b)** — PR #10, fusion **3b2eb73** (1er nov., 14:29).
- **Étape historique** — PR #11, fusion **5b7c4d4** (15:50).
- **Étape 4 (rôle intégré + fiche + profil coach + Sonnet 5.5)** — PR #12, fusion **7fee747** (~16:55).
- **Étape 5 (écran + historique)** — PR #13, fusion **3c609e6** (~17:50).
- **Étape 6a (outils de lecture)** — PR #14, fusion **0e060cf** (~18:55).
- **Étape 6b (carte Séance)** — PR #15, fusion **92388be** (~19:05).
- **Photos + carte Repas + outils repas** — avec Nutrition 4c, PR #18, fusion **8dba15c** (2 nov. ~00:25).
- **Lecture d'étiquette (`read_label`)** — avec Nutrition 4d, PR #19, fusion **cb154b8** (2 nov. ~01:45).
- Code Coach plus ancien : PR #2 et #3 (31 oct.).

**IPA** : `build/coach-redesign` = 92388be (1er nov. ~19:30), puis **`build/nutrition` = `main` cb154b8** (2 nov., IPA de fin de Nutrition, contient tout le Coach). Installation et validation sur le téléphone : à faire (captures).

## Validé par Mohamed (1er nov.)
- Les 8 maquettes (1–5 : « on reste sur ça » ; 6–8 validées ~16:20).
- Conversations : historique + nouvelle conversation (titre auto, recherche, épingler, renommer, supprimer avec confirmation) ; plus rien ne s'efface à minuit.
- Brief du jour à la demande (carte + bouton Générer) ; plus de lancement automatique.
- Suggestions en français par thème + 2-3 relances sous la dernière réponse.
- Carte Séance avec **Ajouter au Carnet** et **Démarrer** ; rien n'est enregistré sans tap. Séances **tout en supersets ou mixtes** (`LiftSuperset`).
- Photo en entrée (Photothèque, Appareil photo) — codée en Nutrition 4c.
- Coach spécialisé sport, qui répond à la question posée sans digresser ; accès à **toutes** ses données.
- **Bouton Arrêter**, **Consignes en plus**, écrans 6–8, **Sonnet 5.5**.

## Technique — décisions de Mohamed (1er nov., 15:00)
- **Données : fiche + outils.** Fiche toujours envoyée ; outils à la demande.
- **Outils et photo : Anthropic seulement.** OpenAI, Gemini et Custom gardent le chat texte (avec rôle et fiche).
- **Refonte : iPhone (et Mac) seulement.** Android garde son Coach.
- Images (tranché le 1er nov. 20:35) : **stockées en local, réduites (JPEG 1568 px), supprimées avec la conversation, hors `.noopbak`**.
- Pris par défaut : cache de prompt Anthropic sur la partie fixe (rôle + fiche) — à faire ; titre auto = première question (48 caractères).
- À respecter : toute requête par `submit(_:photos:dictated:labelBarcode:)` / `beginBriefIfNeeded()` / `regenerateLastReply()`, tout flux par `CoachStreamRelay`, le contexte d'une question par `questionContext()`.

## Étape 6a — PR #14 : outils de lecture
- **Quand** : provider Anthropic **et** « Utiliser mes données ».
- **Outils** (`Strand/AI/CoachTools.swift`, exécution `AICoachToolRunner.swift`) : `get_metric_history`, `get_night`, `get_workouts`, `get_exercise_history`, `get_programs`, `get_journal`, `get_lab_book` (avec « Tendances et Carnet de laboratoire »), **`get_meals`** (4c).
- Résultats en anglais, 6 000 caractères au plus. Boucle `streamToolAnswer` (4 tours au plus, puis `tool_choice: none`).
- Rôle : section « ## Outils » seulement quand des outils partent. Sous la réponse : « Consulté : … ».
- **Stockage** : `CoachReplyMeta` = bloc ```` ```noop-coach ```` JSON à la fin du texte du message (pas de migration). Réponse : consulté, séance, repas. **Question (4c/4d)** : photos, dictée, code-barres.
- Tests : `CoachToolsTests`, `AnthropicToolStreamTests`, `CoachReplyMetaTests`, `CoachToolsRoleTests`.

## Étape 6b — PR #15 : carte Séance
- **`create_program`** (`CoachSessionProposal.swift`) envoyé avec tout appel Anthropic ; bornes séries/réps/repos/charge ; supersets normalisés.
- **Carte** (`CoachSessionCard.swift`) ; **Ajouter au Carnet** (`addSessionToLiftLog`) ; **Démarrer** (iPhone) ; le tour suivant relit la carte en texte (`CoachReplyMeta.forModel`).
- Relances Séance ; leçon parité `muscles(_:)` → `knownExercise`.

## Photos, carte Repas, étiquettes — PR #18 et #19 (avec Nutrition 4c et 4d)
- **Capsule** : bouton « + » (Photothèque ; Appareil photo sur iPhone), bande des photos jointes (retirables), 4 par question ; photo seule = « Analyse mon repas en photo ». Anthropic seulement. Photos : `CoachPhotoStore` (préparées dans le dossier temporaire, gardées à l'envoi dans `Application Support/CoachPhotos`, supprimées avec la conversation ou « Effacer »).
- **Envoi** : blocs image avec la question en cours ; une question plus ancienne avec photo est relue « [n photo(s) sent with this message earlier] ». Bulle de question : vignettes au-dessus du texte.
- **Dictée** : question dictée marquée ; son repas est enregistré « dicté ».
- **Outils toujours envoyés** (ne lisent rien) : `create_program`, `search_foods`, `log_meal`, **`read_label`**. Carte Repas / Produit : `CoachMealCard` (Ajouter au journal, Modifier → éditeur Nutrition pré-rempli) ; valeurs toujours calculées par l'app (Ciqual, ou valeurs pour 100 g lues sur l'étiquette et bornées).
- **Fiche** : bloc NUTRITION (même source « dépensé » qu'Aujourd'hui) ; « Ce que lit le Coach » : ligne Nutrition + « Tes repas sur plusieurs jours ».
- **Ouvrir le Coach depuis Nutrition** : `pendingComposerAction` (Photothèque, appareil, micro), consommé 0,6 s après l'apparition (feuille fermée) ; le scanner envoie une étiquette par `startNewConversation()` + `submit(…, labelBarcode:)` puis `router.openCoach()`.
- **Relances** : après une carte Repas/Produit : « Il me reste combien de protéines ? », « Que manger au prochain repas ? », « Explique pourquoi ».
- Tests : `CoachMealTests`, `BarcodeProductTests`, rendus `NutritionRenderTests` (cartes Repas et Produit).

**À valider sur le téléphone (IPA `build/nutrition`)** :
- Plantages (PR #10) : début de conversation, Arrêter, changement d'onglet pendant une réponse/le brief, dictée puis changement d'onglet.
- Écran (PR #13) : en-tête et menu ⋯, carte Brief, relances, Refaire, Historique, clavier et capsule (+ le bouton « + »).
- Outils (PR #14) : « Ma VFC sur 2 mois ? » → « Consulté : … ».
- Carte Séance (PR #15) : « Crée-moi une séance pour aujourd'hui » → carte ; Ajouter au Carnet ; Démarrer ; « Plus courte, 30 min ».
- Photos / Repas / Étiquette (PR #18, #19) : photo d'un repas → carte Repas → Ajouter / Modifier ; dictée d'un repas ; « Il me reste combien de protéines ? » ; scan d'un produit inconnu → photo d'étiquette → carte Produit → second scan hors ligne ; suppression d'une conversation avec photo.

## Étape 5 — PR #13
- `CoachHistory.swift`, `CoachPrompts.swift` (thèmes, relances), `CoachEmptyState`, `CoachHistoryView`, capsule. « Analyse mon repas en photo » remise en 4c.

## Étape 4 — PR #12
- Rôle intégré v1.3, fiche (`CoachFiche.swift` + `ficheInputs()`), profil coach (`CoachProfile.swift`), `CoachProfileView`, `CoachDataView`. Leçon : `clock(_:)` → `clockText`.

## Plantages — PR #10 · Historique — PR #11
- `CoachStreamRelay`, tour unique, `stopReply()`, micro durci. Migration `v50-coach-conversations`, `CoachConversationStore`.

## Reste à faire (dans l'ordre)
1. **Validation de l'IPA `build/nutrition` sur le téléphone** (liste ci-dessus) ; corrections en petites PR.
2. Cache de prompt Anthropic, 10 questions test.

## Liens avec les autres chantiers
- **Nutrition** : `docs/fork/nutrition-design.md` (4c, 4d).
- **Progression** : la fiche lit les statuts via `LiftProgressData.load`.
- **Fichiers partagés** : `Localizable.xcstrings`, `Strand/AI/AICoach.swift`, `AICoachMeal.swift`, `AICoachToolRunner.swift`, `AICoachSession.swift`, `CoachTools.swift`, `CoachSessionProposal.swift`, `CoachMealProposal.swift`, `CoachReplyMeta.swift`, `CoachPhotoStore.swift`, `CoachFiche.swift`, `CoachProfile.swift`, `CoachHistory.swift`, `CoachStreamRelay.swift`, `Providers/AnthropicTools.swift`, `Strand/Screens/CoachView.swift`, `CoachSessionCard.swift`, `CoachMealCard.swift`, `CoachPhotoViews.swift`, `CoachEmptyState.swift`, `CoachHistoryView.swift`, `CoachPrompts.swift`, `CoachLauncherSheet.swift`, `CoachSettingsView.swift`, `CoachDataView.swift`, `CoachProfileView.swift`, `RootTabView` / `TabRoute.swift`.
