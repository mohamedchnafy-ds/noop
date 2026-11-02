# Refonte visuelle (chantier 7) — fiche du chantier (2 nov. 2026, ~16:20)

**État** : cadrage, audit, inventaire du code et **direction retenue** (2 nov., 16:15). Prochaine étape : **PR 1 — jetons + iOS 26**, dans une conversation dédiée (prompt de handover en bas).
**Maquette retenue** : canvas « NOOP – Refonte visuelle » — https://claude.ai/artifact/BM3c5Wt1e3cqLpbJMEeyCe (slug 53c7de04-b081-409a-8c5d-00c6fe49c8db). Un seul artboard, `Main.dc.html` : Aujourd'hui, **Fitness + Santé** (= ex-F). Les directions écartées (A Fitness pur, B Santé, C Épuré, D Instrument, E Néon nuit) restent dans l'historique des versions.
**Ordre** : la refonte passe **avant Élan** ; Élan sera codé dans le nouveau style. La validation de l'IPA `build/widget-app-group` continue en parallèle.

## Méthode de travail demandée par Mohamed (2 nov.)
- Maximiser le temps : lancer en parallèle ce qui peut l'être, regrouper les PR et les IPA. **Une IPA par lot** (2–3 écrans) ; PR → CI → IPA enchaînés sans attendre quand la validation sur le téléphone n'est pas bloquante.
- **Une conversation par PR ou par lot** ; fiche à jour à la fin ; prompt de handover dès que le contexte devient lourd. Un seul widget de questions par étape ; les choix par défaut sont notés ici. Ne pas surcharger la conversation.

## Direction retenue (Fitness + Santé) — ce que montre la maquette
- **Fond** noir pur #000000 ; **cartes** #1C1C1E, rayon 20, sans bordure ; séparateurs `rgba(255,255,255,0.09)` ; texte secondaire #8E8E93 ; blanc pour le texte principal.
- **Typo** : SF Pro (`.default`) pour tout le texte ; **SF Rounded bold** pour les chiffres (22 px dans les cartes, 36 px pour la FC en direct) ; titres d'écran 34 px bold (−0,6 pt) ; titres de section 20 px bold casse normale (« Métriques », « Synthèse ») ; date en 13 px semibold gris capitales (seule capitale conservée). **Plus de capitales espacées** (overline).
- **Hero Aujourd'hui** : carte unique = **4 anneaux concentriques plats** (extérieur → intérieur : Calories activité doré #FF9F0A, Charge vert #30D158, Effort bleu #0A84FF avec bande cible à 35 %, Repos bleu clair #64D2FF), trait 13, bouts ronds, piste à 18 %, centre vide ; à droite, 4 lignes **libellé coloré avec icône** + chiffre (Calories 18/480 kcal, Charge 2/4 calibration, Effort 4,6 cible 12–14, Repos 81 6h 8m) séparées par des filets ; en bas, 3 cellules sur une **grille à lignes fixes (libellé 16 / chiffre 26 / jauge 12 / légende 14)** : Dépense (barre activité doré + repos brun #A2845E), FC repos (barre « ta normale » rose à 28 % + point), VFC (idem turquoise #66D4CF).
- **Carte FC** : titre rose avec icône cœur + chevron, sélecteur En direct | Journée en pilule grise, chiffre 36 px, courbe rose 2,5 px avec point final, seuils = deux filets fins (haut orange, bas vert à 50 %), pied Min / Moy. / Max + « — 64 · — 90 ».
- **Synthèse** : carte liste, icône colorée seule (sans pastille), titre 16 px medium + sous-titre 13 px gris, valeur en SF Rounded 17 px, chevron ; « Démarrer » en texte bleu #0A84FF.
- **Métriques** : tuiles 2 colonnes #1C1C1E, libellé coloré avec icône 13 px, chiffre 24 px rounded, légende 11 px.
- **Navigation** : boutons ronds d'en-tête et barre d'onglets en **Liquid Glass natif iOS 26** (verre, onglet actif blanc, pas de menthe).
- **Couleurs des métriques** : Charge #30D158, Effort #0A84FF, Repos #64D2FF, Calories activité #FF9F0A / repos #A2845E, FC #FF375F, VFC #66D4CF, sommeil #5E5CE6 (dette), respiration #66D4CF, oxygène #0A84FF, temp. peau #FF9F0A. Liens / actions : bleu système #0A84FF ; bouton principal blanc sur noir ; **pas d'accent menthe**.

## Choix de Mohamed (2 nov., widgets)
- Périmètre : design system d'abord, puis écran par écran, Aujourd'hui en premier.
- Contenu Apple Santé / Fitness, navigation Liquid Glass iOS 26, sombre seulement, police Apple (SF), couleur Apple (pas de police ni d'accent de marque).
- 3 anneaux WHOOP gardés + **anneau Calories** demandé (16:12) ; jauges des métriques **au même niveau** (16:14).
- Code : **PR 1 = design system appliqué partout** (jetons), puis **une PR par écran**. **iOS 26 minimum**.
- Réglages d'apparence devenus inutiles (accent, opacité des cartes, ciel, image de fond, photo Sommeil) : pas tranché → **par défaut : retirer**.

## Audit des captures (2 nov., 15:02)
1. Fond gris-bleu (#1D1E23) + cartes grises à bordure 1 px partout → fond noir, cartes #1C1C1E sans bordure.
2. Police arrondie sur tout + titres de section en capitales espacées → SF Pro, titres 20 px bold, arrondi réservé aux chiffres.
3. Anneaux en relief (disque sombre, biseau, dégradé 5 tons) → anneaux plats concentriques.
4. Icônes dans des pastilles colorées → icône seule colorée.
5. Accent menthe partout → bleu système pour les liens ; la couleur n'est portée que par les métriques.
6. Sommeil : photo de lac nocturne, anneau horloge épais → fond noir, anneau fin, photo retirée.
7. Graphiques : pointillés, grille, courbes épaisses → traits 2–2,5 px, pas de grille.
8. Barre d'onglets : pastille menthe → Liquid Glass natif, sélection blanche.
9. Boutons pleins menthe → blanc sur noir (principal), #2C2C2E (secondaire), rayon 14.
10. Déjà bien : la liste Plus, les écrans Réglages / Données.

## Inventaire du code (2 nov., agent, HEAD 6b7bec3)
- **Jetons** : `Packages/StrandDesign/Sources/StrandDesign/` — `NoopVisualStyle.swift` (canvas #1D1E23, surface #2A2C34, surfaceTop #30323B, inset #23252C, border #373A44, divider #383A43, primaryText #F7F7FA, secondaryText #C3C4CA, tertiaryText #7D7F88, mint #69DDB8 ; cardRadius 22, compactRadius 16, pillRadius 999 ; pagePadding 16, cardPadding 16, itemGap 12, sectionGap 26), `Palette.swift` (`StrandPalette` : surfaceBase/Raised/Overlay/Inset, hairline, text*, heroFill/heroBorder, accent (selon `accentChoice`), liquidHeart, rampes recovery/strain, stages de sommeil, zones, metric*, caloriesActivity/Resting, chargeColor #03E095 / effortColor #4090E0 / restColor #83A0B8 / stressColor, titanium*, gold*), `Components.swift` (`NoopMetrics`, `NoopCard`, `SectionHeader`, `StatTile`, `ChartCard`, `SegmentedPillControl`, `SourceBadge`, `NoopPrimary/Secondary/GhostButtonStyle`, `ScoreStatePill`), `StrandCard.swift`, `NoopButton.swift`, `StatePill.swift`, `DomainTheme.swift`. Chaque couleur a une valeur light et dark.
- **Ombres** inline (`NoopPanelSurface` hors iOS, `NoopElevation`, `additiveBloom`).
- **Styles stockés** (`Appearance.swift`) : `chart.style`, `accent.color`, `theme.appearance`, `noop.showDayCycleBackground`, `noop.cardOpacityPercent`, `noop.skyBehindCards`, image de fond, `sleep.chart.style`. « Liquid Today » = écran Aujourd'hui (`noop.liquidTodayEnabled`), pas un thème.
- **Typo** : `Typography.swift` `enum StrandFont` — tout en `design: .rounded` ; `Text.strandOverline()` (uppercase + tracking 0.45). Pas de modificateur global. Contournements : `TodayTileLabel`, `SourceBadge`.
- **Surfaces** : `NoopPanelSurface` (iOS : fond `surface` + trait 0,8), `NoopChromeSurface`, `FrostedCardSurface`, `StrandCard`, `StrandPressableButtonStyle`.
- **Barre d'onglets** : `TabView` natif (`StrandiOS/App/RootTabView.swift:121-135`), `.tint(StrandPalette.accent)`, `tabBarMinimizeBehavior` derrière `#available(iOS 26)`. Glass déjà utilisé : `NoopLiquidGlassSearchField.swift:70-131`, `LiquidTodayView.swift:2590-2630`. En-tête Sommeil : `SleepTopSection.swift:95-120` ; en-tête générique : `ScreenScaffold.swift:120-126`.
- **Anneaux** : `HeroScoreCell` (`Strand/Liquid/TodayHeroCard.swift`) → `LiquidScoreGauge` (`LiquidPrimitives.swift:591-710`) + `LiquidVessel` / `LiquidRender.vessel` ; demi-anneaux `TodayHalfGauge`. Package : `RecoveryRing`, `StrainGauge`, `BevelGauge`, `GlowRing`.
- **Fond photo Sommeil** : `SleepPerformanceNightScene` (`SleepView.swift:1546`), `sleepNightHero.heic`, si `SceneBackgroundPrefs.enabledKey`. Aujourd'hui : `scene1…scene10` (`SceneHeroBackground.swift`, `LiquidSky.swift`).
- **Cibles** : `project.yml` macOS 13.0, NOOPiOS 17.0 (l. 216), widgets 17.0 (l. 388), watch 10.0. CI : `app-build.yml` macOS sur macos-15, iOS sur macos-26 ; `fork-ipa-on-push.yml` macos-26 ; **`fork-render-on-push.yml` macos-15 → le rendu PNG ne dessine pas le verre**.
- Pas de lint « jetons seulement ». 185 fichiers utilisent les jetons ; `.font(.system(` dans 103 fichiers (~343) ; couleurs littérales ~38 (LiquidSky, LiquidCore, LiquidPrimitives, LiquidTodayView, FusedRecordView, WorkoutDetailView, SettingsView, TodayView, SleepView) ; `.white/.black` ~63 ; `cornerRadius: 22` en dur dans `StrandCard.swift`.

## Plan de code
- **PR 1 — jetons + iOS 26** (`feat/design-tokens`) : `NoopVisualStyle` / `StrandPalette` dark → noir #000, surface #1C1C1E, surfaceTop #2C2C2E, hairline `white 9 %`, texte #FFFFFF / #8E8E93 ; couleurs des métriques ci-dessus (`chargeColor`, `effortColor`, `restColor`, `caloriesActivity/Resting`, `liquidHeart`, VFC) ; `accent` = bleu système (retrait de `accent.color`) ; `StrandFont` : textes en `.default`, chiffres (`display`, `rounded`, `number`, `bodyNumber`, `captionNumber`) en `.rounded` ; `strandOverline` → 13 px semibold gris casse normale (sans uppercase ni tracking) ; `NoopPanelSurface` iOS sans trait, `cardRadius` 20, `compactRadius` 14 ; boutons : principal blanc sur noir, secondaire #2C2C2E ; `project.yml` NOOPiOS + widgets → **26.0** ; retrait du fond photo / scènes / opacité des cartes / ciel / image de fond (réglages et code) ; `.font(.system(` les plus visibles repassés en jetons ; `.tint` de la `TabView` → blanc, boutons d'en-tête en `.glass`. Android non touché ; aucune donnée stockée nouvelle. Rendu PNG + IPA pour valider.
- **PR 2…** : une PR par écran (Aujourd'hui → Sommeil → Entraînement → Coach → Nutrition → Plus/Réglages), chacune depuis `main`, IPA par lot de 2–3.

## Prompt de handover (PR 1)
> Chantier 7 — refonte visuelle, PR 1. Lis `docs/fork/feuille-de-route.md` puis `docs/fork/refonte-design.md` (sections « Direction retenue », « Inventaire du code », « Plan de code »). Maquette : https://claude.ai/artifact/BM3c5Wt1e3cqLpbJMEeyCe. Pars de `main` (vérifier qu'aucune branche `build/*` / `feat/*` n'est en avance), branche `feat/design-tokens`, applique le plan de la PR 1, pousse un rendu `render/design-tokens` puis la PR ; dès que la CI est verte, lance l'IPA `build/design-tokens` sans attendre et envoie-la-moi avec les rappels (sauvegarde `.noopbak`, installer par-dessus, Keep App Extensions). Une seule question par étape, via le widget.
