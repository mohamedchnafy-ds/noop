# Fork NOOP — règles de travail (mohamedchnafy-ds/noop)

Ce dépôt est le fork personnel de Mohamed. Ces règles s'ajoutent à `AGENTS.md` (importé par `CLAUDE.md`) ; quand elles diffèrent des habitudes d'upstream, elles l'emportent.

## Contexte
- NOOP = app iOS hors-ligne pour le bracelet WHOOP 4.0. Fork : `mohamedchnafy-ds/noop`.
- Mohamed n'a **ni Mac ni compte Apple Developer** (PC Windows). Il sideloade l'IPA sur iPhone (iOS 26.x) avec SideStore nightly (+ LocalDevVPN, pairing file Remote Pairing via idevice_pair) ou iloader.
- Déjà ajouté au fork (tout sur `main`) : Coach IA (Anthropic), écran Aujourd'hui, import de programme Excel, Carnet de force avec supersets « un tour = un tap », Progression, Nutrition, Entraînement (planning + calendrier), bannières et widgets. Détail : `docs/fork/`.

## Mémoire du projet : `docs/fork/`
- Les fiches de `docs/fork/` sont la **source de vérité** du fork (feuille de route, une fiche par chantier, instructions du Coach). Index : `docs/fork/README.md`.
- **Début** de chaque conversation qui code : la feuille de route (importée ci-dessous) puis la fiche du chantier concerné.
- **Pendant** : toute décision qui change le design ou les règles va dans la fiche du chantier.
- **Fin** (après la fusion dans `main`) : mettre à jour la feuille de route et la fiche, dans la PR du code ou dans une petite PR `docs/…`.
- Les maquettes sont des artefacts claude.ai (liens dans les fiches). Si la session ne peut pas les ouvrir, demander une capture à Mohamed.

## Règles de travail (obligatoires)
1. **Toujours partir de `main`** et vérifier d'abord qu'aucune branche `build/*` ou `feat/*` n'est en avance sur `main` (`git log origin/main..origin/<branche>`, ou `gh api repos/mohamedchnafy-ds/noop/compare/main...<branche> -q .ahead_by`). Si c'en est une, le dire avant de coder. Exceptions connues, à ignorer : `feat/lift-superset-rounds`, `build/lift-superset-rounds`, `build/supersets-coach`, `feat/coach-lift-context`, `feat/lift-supersets`, et `build/` + `feat/` `sleep-redesign`, `superset-guided` (et `build/superset-guided-2` à `-4`), `superset-rounds`, `today-insights` (vieilles branches du 31 oct. et du 1er nov., ne rien y faire sans accord). La version installée sur le téléphone doit toujours correspondre à `main`.
2. Lire `AGENTS.md` avant toute modification (design tokens uniquement, traductions obligatoires dans les 10 langues de `Strand/Resources/Localizable.xcstrings`, migrations numérotées, parité Swift/Android pour les données stockées).
3. Avant de pousser : `python3 Tools/i18n_audit.py --ci origin/main`, `python3 Tools/doc_comment_lint.py`, puis depuis `Tools/` : `python3 -m unittest discover -q` (et la suite de parité quand on touche `Packages/`, voir la feuille de route). Sur le PC Windows, `python` ou `py -3` à la place de `python3`.
4. Le Swift ne se compile pas localement (ni dans le cloud, ni sur le PC) : ouvrir une PR vers `main` (déclenche `app-build.yml` = compilation macOS + iOS + tests). Si un test échoue et que le journal est illisible, ajouter temporairement une étape qui remonte les lignes `error:` / `Test Case ... failed` en annotations (`::error::`), puis la retirer.
5. IPA : pousser le commit sur `build/<nom>` (workflow `fork-ipa-on-push.yml`, ~20 min) ; télécharger l'asset de la release `ipa-build-<nom>` via l'API REST (`gh api -H "Accept: application/octet-stream" repos/mohamedchnafy-ds/noop/releases/assets/<id>`). Session cloud ou app : l'envoyer dans le chat. Session sur le PC : l'enregistrer dans le dossier du dépôt hors suivi git (ex. `..\ipa\`) et donner le chemin.
6. Une fois la PR verte et validée par Mohamed, **fusionner dans `main`** (`gh api -X PUT repos/mohamedchnafy-ds/noop/pulls/<n>/merge -f merge_method=merge`).
7. Regrouper plusieurs modifications par build : le coût fixe (build + réinstallation) est le même pour 1 ou 10 changements. Pas d'IPA à chaque commit : quand Mohamed le dit.
8. Ne jamais lancer une action irréversible (suppression de branche, force-push, reset de données) sans lui demander.

## Rappels à faire à chaque IPA
- Exporter un `.noopbak` vers **iCloud Drive** avant d'installer (NOOP → Plus → Sauvegarde).
- Installer **par-dessus** l'app existante (SideStore → My Apps → +), **ne jamais supprimer l'app** : supprimer efface le dossier Fichiers → NOOP, et le bracelet ne garde pas l'historique déjà synchronisé (safe-trim).
- À l'alerte « App Contains Extensions » : choisir *Keep App Extensions (Use Main Profile)*.

## Format des réponses
- Français, réponses courtes, résultat d'abord.
- Toute question à Mohamed passe par l'outil de questions à choix multiples (AskUserQuestion), jamais en texte libre. Un seul lot de questions par étape ; les choix par défaut sont notés dans la fiche.
- Il ne voit pas l'app depuis la session : lui demander des captures d'écran pour valider le rendu.

## Chantier en cours (mis à jour le 5 nov. 2026)
- **Chantier 9** : lisibilité de l'app, une section à la fois (maquette → validation → code). Fiche `docs/fork/chantier-9-design.md`. Méthode : toutes les maquettes d'abord (un artefact Design par section), le code après. Section 1 (navigation) fusionnée (#61), section 2 (Aujourd'hui) fusionnée (#64), section 3 (Sommeil) fusionnée (#66), section 4 (Nutrition) fusionnée (#68, #69, #70), section 5 (Entraînement) fusionnée (#71), section 6 (Coach) fusionnée (#73, #74, #75) ; **maquettes 2 à 7 validées le 4 nov.** (liens dans la fiche). Intercalé à la demande de Mohamed (4 nov. soir) : **Supersets et blocs** fusionné (#77, #78, `main` 07c13c4) ; **« Démarrer » fusionné (#80, `main` 21f486b)** ; **« Historique » fusionné (#81, `main` bae91f6)** ; maquette https://claude.ai/artifact/E3Q2mhqfXJVckeiGZskZE7, fiche `docs/fork/entrainement-design.md`. **Section 7 Plus fusionnée (#82, `main` 972520d)** : code du chantier 9 terminé. **Prochaine étape** : l'IPA depuis `main`, puis la validation sur le téléphone (liste « À tester »).

## Chantier précédent
- **Chantier 8** : code terminé, fiche `docs/fork/chantier-8-design.md` (choix de Mohamed et décisions prises pendant le chantier). Fusionnés : lots 1, 2a, 2b, 3 (#46 à #54), 4 (#55 planning, #57 écran de séance en cours), 5 (#58 corps cliquable), #59 virgule décimale. IPA unique construite : `build/chantier-8` = `main` ca02e9a. Reste : l'installer et valider sur le téléphone (liste « À tester » de la feuille de route).
- Méthode demandée : lots dans l'ordre ; fusion dès que la CI est verte ; **une seule IPA à la fin**.

## Chantier suivant (préparé le 5 nov.)
- **Chantier 12 — animations** : maquettes validées, fiche `docs/fork/chantier-12-animations.md` (choix, règles du mouvement, plan en 3 PR, prompt de démarrage). Se code dans une nouvelle conversation, avant Élan ; une seule IPA à la fin.

## Feuille de route (chargée à chaque session)
@../../docs/fork/feuille-de-route.md
