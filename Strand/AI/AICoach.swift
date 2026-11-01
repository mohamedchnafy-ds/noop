import Foundation
import Combine
import Security
import WhoopStore
import StrandAnalytics
import StrandImport

// MARK: - AI Coach (the one networked feature, strictly opt-in, bring-your-own-key)
//
// NOOP is offline by design. This file is the single exception: when the user pastes their OWN
// API key for a provider they choose, NOOP can send a compact text summary of their metrics plus
// their question to that provider and surface coaching advice. Nothing leaves the device until a
// key is set AND a question is asked. We never embed our own key, never auto-send, and only ever
// transmit the small text context built in `buildContext()` + the running chat, no raw streams.
//
// Pure macOS: Foundation + URLSession + Security (Keychain). Compiles on macOS 13, Swift 5.
// Provider wire formats live in Providers/: OpenAI.swift, Anthropic.swift, Gemini.swift.

// MARK: - Chat model

/// One turn in the coaching conversation.
struct ChatMessage: Identifiable, Equatable {
    enum Role: String { case user, assistant }
    let id: UUID
    let role: Role
    let text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

// MARK: - Secure key storage (Keychain)

/// Keychain Services wrapper for the user's API key. Uses a generic-password item under a fixed
/// service so the key never lands in UserDefaults, a plist, or on disk in the clear.
enum AIKeyStore {
    private static let service = "com.noop.aicoach"
    private static let account = "api-key"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// UserDefaults key recording which provider the stored API key belongs to, so one provider's key
    /// is never sent to another provider's endpoint (above all the arbitrary user-typed Custom URL).
    private static let ownerKey = "ai.keyProvider"

    /// The provider the stored key was saved for, or nil for a legacy key saved before this tracking.
    static var ownerProvider: String? { UserDefaults.standard.string(forKey: ownerKey) }

    /// Store (or replace) the API key for `owner`. Empty/whitespace input is treated as a clear.
    /// Returns true once the key is in the Keychain (or was cleared); false if the Keychain write
    /// failed, in which case the owner marker is left untouched so it never points at a key that
    /// isn't actually stored (#872). The live `read()`/`hasKey` gating already reads the real
    /// Keychain, so this is defensive tidying of the discarded write result, not a behaviour change.
    @discardableResult
    static func save(_ key: String, owner: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { clear(); return true }
        guard let data = trimmed.data(using: .utf8) else { return false }

        // Delete any existing item first so we always insert a single, fresh value.
        SecItemDelete(baseQuery as CFDictionary)

        var attrs = baseQuery
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { return false }
        UserDefaults.standard.set(owner, forKey: ownerKey)
        return true
    }

    /// Read the stored API key, or nil if none is set.
    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8),
              !str.isEmpty else { return nil }
        return str
    }

    /// Remove any stored API key.
    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
        UserDefaults.standard.removeObject(forKey: ownerKey)
    }
}

// MARK: - Errors

/// User-facing failure reasons mapped to clear, non-crashing messages.
enum AICoachError: LocalizedError {

    /// Whether an HTTP status means the stored key itself was turned away, as opposed to the provider
    /// being busy, broken, or asked for something it does not have.
    ///
    /// Named rather than left as two literals in two switches because it is the hinge the key-repair
    /// affordance hangs on, and it decides what the wearer is told to go and do. Widen it and a rate
    /// limit starts demanding a new key; narrow it and the trap this exists to remove comes straight
    /// back. Byte-identical twin of the Kotlin `AiCoach.isKeyRejection`.
    static func isKeyRejection(_ status: Int) -> Bool { status == 401 || status == 403 }

    case noKey
    case emptyQuestion
    case badKey
    case rateLimited(String)
    case server(Int, String)
    case network(String)
    case decode
    case emptyReply(String)   // #1074: verbatim provider-error / empty-reply text (byte-parity with Android emptyReplyMessage)
    case keySaveFailed
    case badCustomURL(String)

    var errorDescription: String? {
        switch self {
        case .badCustomURL(let message):
            return message
        case .noKey:
            return "Add your own API key first to use the coach."
        case .keySaveFailed:
            return "Couldn't save the key to the Keychain. The key was not stored, so try again."
        case .emptyQuestion:
            return "Type a question for the coach."
        case .badKey:
            return "That API key was rejected. Check the key and the provider you selected."
        case .rateLimited(let detail):
            let extra = detail.isEmpty ? "" : " (\(detail))"
            return "The provider is rate-limiting requests right now. Wait a moment and try again.\(extra)"
        case .server(let code, let detail):
            let extra = detail.isEmpty ? "" : " - \(detail)"
            return "The provider returned an error (\(code))\(extra)."
        case .network(let detail):
            return "Network problem: \(detail). The coach is the only feature that needs the internet."
        case .decode:
            return "Couldn't read the provider's reply. Try again."
        case .emptyReply(let message):
            return message
        }
    }
}

// MARK: - Engine

/// Drives the AI Coach: holds the chat, the chosen provider/model, the secure key, and performs the
/// networked request. `@MainActor` so all `@Published` mutations are main-thread; the actual HTTP
/// call hops off-main via `URLSession`'s async API and results are applied back on the main actor.
@MainActor
final class AICoachEngine: ObservableObject {

    // Published state the UI binds to.
    @Published var messages: [ChatMessage] = []

    /// Local day the current transcript was last written on; nil while it is empty. Drives the day
    /// boundary in `send` — see `isStaleConversation`. Kotlin twin: `CoachViewModel.conversationDay`.
    private var conversationDay: Int?
    @Published var sending = false
    @Published var errorText: String?

    /// Whether the last failure was the provider turning the stored key away, as opposed to a rate
    /// limit, a server fault or the network.
    ///
    /// It exists because the rejection message tells the wearer to check their key while the screen
    /// offers no way to reach it: the coach shows the chat as soon as ANY key is stored, and a wrong
    /// key is still a stored key, so the only route back was a Disconnect that also throws the
    /// conversation away. This lets the error carry the field with it.
    ///
    /// It QUALIFIES `errorText` rather than standing on its own, and the view reads it only inside the
    /// branch that renders one, so it cannot leave a key editor open under no error. Assigned on every
    /// failure, so a rejection followed by a rate limit stops claiming to be a rejection. Twin of the
    /// Kotlin `CoachViewModel.keyRejected`.
    @Published var keyRejected = false

    /// #1862: a question handed over by the Today Coach launcher sheet, for `CoachView` to send on appear.
    ///
    /// The launcher owns no send, stream, error or consent surface of its own — duplicating those is how a
    /// second chat UI drifts from the first. It collects a question and hands it here; the Coach screen,
    /// which already has all of that, consumes it exactly once and clears it. Nil is the normal state, and
    /// setting it performs NO network work by itself.
    @Published var pendingPrompt: String?
    @Published var provider: AIProvider {
        didSet {
            guard provider != oldValue else { return }
            UserDefaults.standard.set(provider.rawValue, forKey: Self.providerKey)
            // Reset the model list to the new provider's built-in options.
            availableModels = provider.modelOptions
            // Keep the model valid for the newly-selected provider.
            if !provider.modelOptions.contains(model) {
                model = provider.defaultModel
            }
            // The message names a provider ("That API key was rejected", after a request only THIS
            // provider saw), so it cannot survive switching to a different one. Harmless while only the
            // chat rendered it; wrong now that the setup card does too, which is where switching
            // happens. Twin of the Kotlin `selectProvider`.
            errorText = nil
            keyRejected = false
        }
    }
    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Self.modelKey) }
    }
    /// The model ids offered in the picker. Seeded from `provider.modelOptions`, reset when the
    /// provider changes, and optionally extended by `refreshModels()` with the provider's live list.
    @Published var availableModels: [String] = []
    /// Explicit permission for the coach to read & transmit the user's biometric data. OFF by
    /// default, until this is true, NO metrics are included in any request (only the question).
    @Published var dataConsent: Bool {
        didSet { UserDefaults.standard.set(dataConsent, forKey: Self.consentKey) }
    }
    /// Base URL for the Custom (OpenAI-compatible) provider, e.g. `http://localhost:11434/v1` for a
    /// local LLM server. Only used when `provider == .custom`. Persisted so it survives relaunch.
    @Published var customBaseURL: String {
        didSet { UserDefaults.standard.set(customBaseURL, forKey: AIProvider.customBaseURLKey) }
    }
    @Published var customAuthHeader: CustomAIAuthHeader {
        didSet { UserDefaults.standard.set(customAuthHeader.rawValue, forKey: AIProvider.customAuthHeaderKey) }
    }
    /// Whether the user has committed the Custom provider (tapped Connect with a base URL). Lets the
    /// keyless local path reach the chat without a stored key, while avoiding a flip mid-typing.
    @Published var customConnected: Bool {
        didSet { UserDefaults.standard.set(customConnected, forKey: Self.customConnectedKey) }
    }
    /// SECOND opt-in (v5): also fold a SUMMARY of the new on-device signals, your strongest n-of-1
    /// correlations and your Lab Book markers, into the coach context. OFF by default and gated behind
    /// `dataConsent` too, so it never adds anything without both consents. Summary-only: a few one-line
    /// sentences, NEVER raw readings, the anonymity / no-raw-egress posture is preserved.
    @Published var includeOnDeviceSignals: Bool {
        didSet { UserDefaults.standard.set(includeOnDeviceSignals, forKey: Self.onDeviceSignalsKey) }
    }

    /// K11: THIRD opt-in — send a chart image alongside the text when using Gemini's multimodal
    /// API. OFF by default and gated behind `dataConsent` too. Only active when the provider is
    /// Gemini (the only provider with multimodal support in the app). When on, the Coach composer
    /// shows an "Attach chart" toggle; the rendered chart is sent as inline_data to Gemini.
    @Published var multimodalChartEnabled: Bool {
        didSet { UserDefaults.standard.set(multimodalChartEnabled, forKey: Self.multimodalChartKey) }
    }

    /// What the user told the coach (personal fork), persisted on every change and sent with every
    /// question. See `CoachProfile`.
    @Published var coachProfile: CoachProfile = CoachProfile.load() {
        didSet { if coachProfile != oldValue { coachProfile.save() } }
    }

    private let repo: Repository
    /// The body profile behind the context's USER PROFILE block and today's calorie and effort figures.
    /// Nil only where a test builds an engine without one.
    private let profile: ProfileStore?
    private let session: URLSession

    private static let providerKey = "ai.provider"
    private static let modelKey = "ai.model"
    private static let consentKey = "ai.dataConsent"
    private static let customConnectedKey = "ai.customConnected"
    private static let onDeviceSignalsKey = "ai.includeOnDeviceSignals"
    private static let multimodalChartKey = "ai.multimodalChartEnabled"
    /// UserDefaults key holding the user's extra instructions (personal fork): text ADDED to the built-in
    /// role, never a replacement for it, so the answer format and the rules the coach's later tools rely
    /// on always hold. Absent or blank means none. Read FRESH per request (see `systemPrompt`) so an edit
    /// takes effect on the very next message.
    ///
    /// It replaces the upstream `ai.systemPrompt` override, which swapped the whole prompt out. That key
    /// is no longer read and is left as it is on disk.
    static let extraInstructionsKey = "ai.coachExtraInstructions"

    /// The built-in role that frames every request (personal fork: the coach instructions v1.3, the
    /// validated v1.2 text adapted to the context the app now sends). French on purpose: it is the text
    /// that was written and validated for this fork, and it tells the coach to answer in French.
    ///
    /// The user's extra instructions are appended to it (`extraInstructionsKey`), never swapped in for it.
    static let defaultSystemPrompt = """
    Tu es le coach sportif personnel de l'utilisateur, dans l'app NOOP. Tu t'occupes uniquement de :
    - l'entraînement (musculation, cardio, mobilité), sa programmation et sa progression ;
    - la récupération et le sommeil ;
    - la nutrition du sportif (énergie, protéines, hydratation, repas autour des séances) ;
    - la prévention des blessures et l'adaptation de l'entraînement à une douleur.
    Si on te demande autre chose, dis en une phrase que ce n'est pas ton rôle, puis propose un angle sport s'il y en a un.

    ## Comment répondre
    1. Réponds à la question posée dès la première phrase. Pas d'introduction, pas de récapitulatif de la journée.
    2. Utilise seulement les données qui concernent la question. Ne parle d'une autre donnée que si elle change ta réponse (par exemple une VFC très basse quand on te demande s'il faut faire une séance lourde) ; une phrase suffit alors.
    3. Longueur : question simple → 2 à 4 phrases. Analyse → un court paragraphe et 5 puces au plus. Plan ou séance → seulement si on te le demande.
    4. Termine sans résumé ni conseils en plus. Une seule question de suivi au maximum, et seulement s'il te manque une information pour bien répondre.
    5. Tutoie, en français, ton direct et encourageant, sans emphase. Pas d'emoji.
    6. Markdown léger : **gras** pour les chiffres clés, listes courtes. Pas de titre pour une réponse courte, pas de tableau sauf pour un plan sur plusieurs jours.

    ## Lire les données
    Avec chaque question, tu reçois une fiche de ses données, en anglais :
    - USER PROFILE : âge, sexe, taille, poids, FC max. Une valeur marquée « app default » n'a pas été saisie : ne t'appuie pas dessus, demande-la si elle compte.
    - WHAT THE USER TOLD THE COACH : son objectif, son rythme, son matériel, ses douleurs et le reste. Respecte-les. Si un point manque et qu'il compte pour ta réponse, demande-le.
    - TODAY : les chiffres de l'écran Aujourd'hui. YOUR NORMALS : ses normales personnelles. SLEEP : besoin, dette, réveil habituel, coucher conseillé.
    - Ensuite : les 14 derniers jours, les moyennes sur 30 jours, les entraînements récents, le stress du jour, le Carnet de force (LIFT LOG), le statut de chaque exercice (LIFT PROGRESSION) et les siestes.
    - charge = récupération du jour (0-100) ; effort = charge cardio de la journée (0-100) ; rest = durée de la nuit ; deep / REM / light = phases de sommeil ; eff = efficacité du sommeil ; HRV = VFC (ms) ; RHR = FC au repos (bpm) ; SpO2, respiration, skin-temp deviation (température cutanée), steps (pas), calories.
    - Un tiret « — » ou « not measured » veut dire NON MESURÉ, jamais zéro. Dis-le si une donnée utile manque.
    - Compare toujours à SES normales (YOUR NORMALS, sinon les moyennes sur 30 jours), pas aux normes générales. Un écart compte quand il est net : VFC sous sa zone normale (ou sous 85 % de sa moyenne), FC au repos au-dessus de sa zone (ou 5 bpm au-dessus de sa moyenne), nuit de moins de 6 h.
    - Relie les signaux entre eux au lieu de les citer un par un :
      - VFC en baisse + FC au repos en hausse + nuit courte → fatigue accumulée : alléger.
      - Charge basse le lendemain d'une grosse séance → attendu, pas inquiétant.
      - Température cutanée et respiration en hausse ensemble, avec VFC basse → possible début de maladie : repos, pas d'intensité.
      - Bonne charge mais plusieurs nuits courtes → s'entraîner en gardant des répétitions en réserve, et se coucher plus tôt.
    - N'invente jamais un chiffre. Quand tu estimes (calories d'un repas, charge à viser), dis que c'est une estimation.

    ## Autorégulation
    - Charge 67-100 : feu vert, on peut pousser (charges en hausse, 0 à 1 répétition en réserve sur les dernières séries).
    - Charge 34-66 : séance prévue, qualité plutôt que volume (1 à 2 répétitions en réserve).
    - Charge 0-33 : récupération active (marche, zone 2 légère, mobilité) et sommeil.

    ## Musculation (Carnet de force)
    - Quand un bloc LIFT LOG est présent, appuie chaque réponse muscu dessus : séries faites (charge × réps), e1RM, volume hebdomadaire par muscle, programmes.
    - Pour dire si un exercice progresse, stagne, baisse ou peut monter, reprends son statut dans LIFT PROGRESSION : c'est la règle que l'app affiche, ne la recalcule pas. « ready to go up » donne la charge à viser.
    - L'utilisateur ne note pas le RPE : ne t'appuie jamais dessus, même si une colonne ou une consigne RPE apparaît. Pour l'intensité, parle en répétitions en réserve.
    - Double progression : si toutes les séries de travail atteignent le haut de la fourchette de répétitions, propose +2,5 kg (haut du corps) ou +5 kg (bas du corps) ; sinon, garde la charge.
    - Les lignes A1, A2… sont des supersets : une série de chaque, repos après la dernière.
    - Repère de volume : 10 à 20 séries par muscle et par semaine selon le niveau et la récupération.

    ## Créer une séance
    Quand on te demande une séance :
    - Pars des exercices de son Carnet et de leurs dernières charges. N'ajoute un nouvel exercice que si c'est nécessaire, et dis-le.
    - Respecte la durée, le matériel et les douleurs qu'il t'a indiqués (WHAT THE USER TOLD THE COACH) ; adapte l'intensité à la charge du jour.
    - Choisis la structure selon le but, et mélange si c'est utile :
      - exercice seul pour les mouvements lourds (squat, développé couché, soulevé de terre…), repos 2 à 3 min ;
      - superset (2 exercices) pour les accessoires, de préférence sur des muscles opposés ou des zones différentes ;
      - triset (3 exercices ou plus) seulement pour gagner du temps ou en finisher.
      Si l'utilisateur impose une structure (« tout en supersets », « sans superset »), respecte-la.
    - Présente-la exactement ainsi, avec une seule phrase avant et rien après :
      **Nom de la séance** · durée estimée
      Exercice — séries × réps · charge
      repos 2:30
      A1 Exercice — séries × réps · charge
      A2 Exercice — séries × réps · charge
      repos 2:00 après A2
      (un superset = une même lettre avec des numéros qui se suivent : A1, A2, A3… ; un exercice seul n'a pas de lettre ; garde l'ordre d'exécution)
    - Pour une modification, donne seulement les lignes qui changent, sauf si on te redemande la séance complète.

    ## Nutrition
    - Protéines : environ 1,6 à 2,2 g par kg de poids de corps et par jour, en 3 à 5 repas.
    - Utilise son poids (USER PROFILE) et son objectif (WHAT THE USER TOLD THE COACH). S'ils manquent ou sont marqués « app default », demande-les avant de donner des quantités.
    - Les calories sont une estimation du bracelet.
    - Pas de régime extrême ni de jeûne prolongé. Compléments : seulement les classiques (créatine, protéine en poudre, caféine, vitamine D), toujours présentés comme facultatifs.

    ## Sécurité
    Tu n'es pas médecin : ne pose jamais de diagnostic. Douleur vive ou qui s'aggrave, douleur thoracique, malaise, essoufflement anormal → arrêter et consulter. Pour une douleur légère, propose d'adapter l'exercice (amplitude, charge, variante) plutôt que de forcer.

    ## Exemples (chiffres fictifs : ils montrent le ton et la longueur)
    Question : « Je fais combien de séries de biceps par semaine ? »
    Réponse : « **9 séries** sur les 7 derniers jours (curl incliné, 3 × 3 séances). C'est le bas de la fourchette : tu peux monter à 12 en ajoutant une série par séance si tes bras récupèrent bien. »

    Question : « J'ai mal dormi, je fais ma séance ? »
    Réponse : « Oui, mais allégée : **5 h 10** de sommeil et VFC à **38 ms** (ta normale : 41 à 51). Fais Full body B en gardant 2 répétitions en réserve et saute le finisher. Couche-toi tôt ce soir. »
    """

    /// The role, then the user's extra instructions under their own heading when there are any. Pure, so
    /// the composition is tested without UserDefaults.
    nonisolated static func composeSystemPrompt(role: String, extra: String?) -> String {
        let trimmed = extra?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return role }
        let heading = "## Consignes de l'utilisateur\n"
            + "Elles complètent ce qui précède et l'emportent en cas de conflit, sauf sur la sécurité."
        return role + "\n\n" + heading + "\n" + trimmed
    }

    /// The system prompt actually sent, read FRESH from UserDefaults on every request so an edit in the
    /// settings takes effect on the next message, with no engine rebuild.
    var systemPrompt: String {
        Self.composeSystemPrompt(role: Self.defaultSystemPrompt,
                                 extra: UserDefaults.standard.string(forKey: Self.extraInstructionsKey))
    }

    /// The user's extra instructions, "" when none. The settings editor binds to this: writing persists
    /// the text, and a blank one clears the key.
    var extraInstructions: String {
        get { UserDefaults.standard.string(forKey: Self.extraInstructionsKey) ?? "" }
        set {
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                UserDefaults.standard.removeObject(forKey: Self.extraInstructionsKey)
            } else {
                UserDefaults.standard.set(newValue, forKey: Self.extraInstructionsKey)
            }
            objectWillChange.send()
        }
    }

    /// True when extra instructions are stored; gates the "Clear" control in the settings.
    var hasExtraInstructions: Bool { !extraInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Remove the extra instructions.
    func clearExtraInstructions() {
        UserDefaults.standard.removeObject(forKey: Self.extraInstructionsKey)
        objectWillChange.send()
    }

    /// Contextual suggestion chips for the composer, derived from today's bands via `CoachSuggestions`.
    /// Reads only on-device `repo.days`; pure, byte-identical to the Android twin. Returns the stable
    /// generic fallback when there is no usable data for today.
    var suggestions: [String] { CoachSuggestions.suggestions(for: repo.days.last, recent: repo.days) }

    /// K7: Follow-up suggestion chips shown after each assistant reply. These are generic
    /// conversational follow-ups (not data-derived) so the user can dig deeper without typing.
    /// Byte-identical to the Android twin's `followUpSuggestions`.
    /// Strength-training prompts (personal fork), shown first among the composer's chips. Localized,
    /// because the chip's text IS the question sent: a French user asks in French.
    static var liftSuggestions: [String] {
        [
            String(localized: "How did my last strength session go?"),
            String(localized: "What should I aim for in my next session?"),
            String(localized: "Am I making progress on my lifts?"),
            String(localized: "Is my weekly volume per muscle balanced?"),
            String(localized: "Should I train hard today given my recovery?"),
        ]
    }

    static let followUpSuggestions: [String] = [
        "Tell me more about that",
        "What should I do next?",
        "How does today compare to this week?",
        "Give me a specific action plan",
    ]

    /// K12: Rough token estimate for the next send, based on the current draft + context size.
    /// Uses the standard ~4 chars/token heuristic. This is an estimate only — actual token counts
    /// vary by tokenizer. Returns nil when the engine isn't configured (no context to estimate).
    func estimatedTokens(forDraft draft: String) -> Int? {
        guard isConfigured else { return nil }
        // Estimate the context size: system prompt + data context (rough — we don't build the
        // full context here to avoid a DB read on every keystroke). Use the last known context
        // size or a reasonable default.
        let systemPromptTokens = systemPrompt.count / 4
        // The data context is typically ~2000-4000 chars depending on the user's data.
        // Use a conservative estimate of 3000 chars (750 tokens) when consent is on.
        // Higher since the Lift Log joined the context (sessions, progression and programs), and again
        // since the profile, today's figures, the normals, the sleep block and the Lift Log statuses did.
        let contextTokens = dataConsent ? 2_300 : 150
        // History tokens: sum of all message texts in the windowed history.
        let historyTokens = windowedMessages().reduce(0) { $0 + $1.text.count / 4 }
        let draftTokens = draft.count / 4
        return systemPromptTokens + contextTokens + historyTokens + draftTokens
    }

    /// Set once the one-time default-model upgrade has been considered, so a model picked by hand
    /// afterwards, the old default included, is never changed again.
    static let modelUpgradeKey = "ai.modelUpgradedToSonnet55"

    /// The model to switch a stored choice to, once: an Anthropic connection still on the previous
    /// built-in default moves to the current one (`AIProvider.anthropic.defaultModel`). Any other model,
    /// provider or an install already considered keeps its choice (nil).
    nonisolated static func upgradedModel(provider: AIProvider, stored: String?, alreadyUpgraded: Bool) -> String? {
        // "claude-sonnet-4-6" is the Anthropic default before Claude Sonnet 5.5.
        guard !alreadyUpgraded, provider == .anthropic, stored == "claude-sonnet-4-6" else { return nil }
        return AIProvider.anthropic.defaultModel
    }

    /// Used in place of the metrics context when the user has NOT granted data access.
    private let noConsentNote = """
    NOTE: The user has not granted access to their biometric data. Coach generally and encourage \
    them to turn on "Use my data" (Coach menu, "What the coach reads") for guidance tailored to their \
    real numbers.
    """

    init(repo: Repository, profile: ProfileStore? = nil, session: URLSession = .shared) {
        self.repo = repo
        self.profile = profile
        self.session = session

        // Restore persisted provider / model (falling back to sane defaults).
        let storedProvider = UserDefaults.standard.string(forKey: Self.providerKey)
            .flatMap(AIProvider.init(rawValue:)) ?? .openAI
        self.provider = storedProvider

        var storedModel = UserDefaults.standard.string(forKey: Self.modelKey)
        // Once per install: a model still on the previous built-in default moves to the new one.
        if let upgraded = Self.upgradedModel(provider: storedProvider, stored: storedModel,
                                             alreadyUpgraded: UserDefaults.standard.bool(forKey: Self.modelUpgradeKey)) {
            storedModel = upgraded
            UserDefaults.standard.set(upgraded, forKey: Self.modelKey)
        }
        UserDefaults.standard.set(true, forKey: Self.modelUpgradeKey)
        // A persisted custom id is honoured even if it's not in the built-in list.
        if let storedModel, !storedModel.isEmpty {
            self.model = storedModel
        } else {
            self.model = storedProvider.defaultModel
        }

        // Seed the picker with the provider's built-in options; include any persisted custom id.
        var seeded = storedProvider.modelOptions
        if let storedModel, !storedModel.isEmpty, !seeded.contains(storedModel) {
            seeded.insert(storedModel, at: 0)
        }
        self.availableModels = seeded

        self.dataConsent = UserDefaults.standard.bool(forKey: Self.consentKey)
        self.customBaseURL = UserDefaults.standard.string(forKey: AIProvider.customBaseURLKey) ?? ""
        self.customAuthHeader = AIProvider.customAuthHeader
        self.customConnected = UserDefaults.standard.bool(forKey: Self.customConnectedKey)
        self.includeOnDeviceSignals = UserDefaults.standard.bool(forKey: Self.onDeviceSignalsKey)
        self.multimodalChartEnabled = UserDefaults.standard.bool(forKey: Self.multimodalChartKey)
    }

    // MARK: Key management

    /// True when a key is present in the Keychain.
    var hasKey: Bool { AIKeyStore.read() != nil }

    /// True once the coach can actually send: a stored key for the cloud providers, or, for the
    /// Custom (local) provider, a committed base URL (a key is optional there, as local servers
    /// usually need none). Gates the setup card vs. the live chat.
    var isConfigured: Bool { provider == .custom ? customConnected : hasKey }

    /// The key to send with a request: the stored key, or an empty string for the keyless Custom
    /// provider. `nil` means "not configured", the caller surfaces `.noKey`.
    private var resolvedKey: String? {
        if let k = AIKeyStore.read() {
            // Only send the stored key to the provider it was SAVED for, never Bearer one provider's
            // key (e.g. a cloud OpenAI/Anthropic secret) to another provider's endpoint, above all the
            // arbitrary user-typed Custom URL. A legacy key with no recorded owner is assumed to belong
            // to a cloud provider, so it is never auto-sent to Custom.
            let owner = AIKeyStore.ownerProvider
            if owner == provider.rawValue { return k }
            if owner == nil && provider != .custom { return k }
        }
        return provider == .custom ? "" : nil
    }

    /// Commit the Custom (local) provider once the user has entered a server URL. Optionally stores a
    /// key first if they pasted one. Pulls the server's live model list so the picker isn't empty.
    func connectCustom() {
        let url = customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        errorText = nil
        customConnected = true
        // Pull the server's model list; if the user hasn't picked one yet, default to the first.
        Task {
            await refreshModels()
            if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let first = availableModels.first {
                model = first
            }
        }
    }

    /// Disconnect entirely: forget any stored key and un-commit the Custom provider. The base URL is
    /// kept so reconnecting pre-fills it.
    func disconnect() {
        AIKeyStore.clear()
        customConnected = false
        // Retire the transcript with the connection. Kotlin has done this since the method existed
        // (CoachViewModel.disconnect) and this side never did, so returning to the setup screen on Apple
        // left the whole conversation sitting behind it — including whatever the user had told a coach
        // they were in the middle of disconnecting from. The conversation itself stays in the history.
        stopReply()
        resetTranscript()
        // The error belongs to the connection being retired, so it goes with it. Kotlin has cleared it
        // here since the method existed and this side never did: harmless while only the chat rendered
        // an error, and a visible defect the moment the setup card does too, because the card this
        // returns to would open carrying "That API key was rejected" above an empty key field, reading
        // as a verdict on the key about to be typed.
        errorText = nil
        keyRejected = false
        objectWillChange.send()
    }

    /// Store the user's pasted key securely. Clears any prior error. If the Keychain write fails the
    /// key is NOT saved, so surface that to the UI instead of silently proceeding (#872).
    func setKey(_ key: String) {
        guard AIKeyStore.save(key, owner: provider.rawValue) else {
            errorText = AICoachError.keySaveFailed.errorDescription
            objectWillChange.send()
            return
        }
        errorText = nil
        // A stored key is no longer the rejected one. Deliberately leaves the transcript alone:
        // correcting a mistyped key is not a reason to lose the conversation, which is what routing
        // this through `disconnect` used to cost. Twin of the Kotlin `saveKey`.
        keyRejected = false
        objectWillChange.send() // `hasKey` is computed; nudge SwiftUI to re-read it.
        // #288: do NOT auto-fetch the provider's model list on key-save. For a cloud provider that GET
        // egresses to the provider the MOMENT a key is saved (IP + request timing + key-validity) — before
        // any send, in an app that is zero-network by default. The picker shows the curated models; the LIVE
        // list is pulled only when the user taps Refresh (an explicit action that is its own consent) or
        // sends. Local Custom servers still refresh on Connect.
    }

    /// Forget the stored key.
    func clearKey() {
        AIKeyStore.clear()
        // Same reasoning as `disconnect`: clearing the key returns the user to the setup screen, and
        // Kotlin empties the transcript when it does. Leaving it meant a "clear my key" on Apple removed
        // the credential and kept the conversation. The conversation itself stays in the history.
        stopReply()
        resetTranscript()
        // The error belongs to the connection being retired, so it goes with it. Kotlin has cleared it
        // here since the method existed and this side never did: harmless while only the chat rendered
        // an error, and a visible defect the moment the setup card does too, because the card this
        // returns to would open carrying "That API key was rejected" above an empty key field, reading
        // as a verdict on the key about to be typed.
        errorText = nil
        keyRejected = false
        objectWillChange.send()
    }

    // MARK: Live model list

    /// Set a custom model id (any string). Adds it to the picker if it isn't already listed.
    func setCustomModel(_ id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !availableModels.contains(trimmed) {
            availableModels.insert(trimmed, at: 0)
        }
        model = trimmed
    }

    /// Test seam (DEBUG only): lets a test stand in for the live `fetchModels` network call so it can
    /// control timing and which provider's ids come back. Production never sets this, so the real path
    /// below is byte-identical in release builds.
    #if DEBUG
    var fetchModelsOverride: ((_ provider: AIProvider, _ key: String) async throws -> [String])?
    #endif

    /// Best-effort: GET the chosen provider's models endpoint with the saved key and merge the
    /// returned ids into `availableModels`. Never crashes; failures land in `errorText` and leave
    /// the existing list intact. Requires a saved key.
    /// When the live catalogue was last pulled for `provider`, keyed per provider so switching does
    /// not hide one provider's stale list behind another's refresh. Kotlin twin:
    /// `NoopPrefs.coachModelsRefreshedAt`.
    static func modelsRefreshedKey(_ provider: AIProvider) -> String {
        "ai.modelsRefreshed.\(provider.rawValue)"
    }

    /// How long a pulled catalogue is trusted. Kotlin twin: `MODEL_REFRESH_INTERVAL_MS`.
    static let modelRefreshInterval: TimeInterval = 7 * 24 * 60 * 60

    /// Whether a catalogue last pulled at `last` is due another pull at `now`.
    ///
    /// Split out and `static` so the rule can be pinned without an engine: it decides how often the app
    /// talks to a provider unasked. A never-pulled catalogue (0) is stale, so the first visit fetches. A
    /// clock moved BACKWARDS gives a negative age and reads as fresh, keeping the cached list rather
    /// than refetching every visit until the clock catches up. Kotlin twin:
    /// `CoachViewModel.isCatalogueStale`.
    static func isCatalogueStale(last: TimeInterval, now: TimeInterval) -> Bool {
        now - last >= modelRefreshInterval
    }

    /// Pull the live catalogue at most once a week, so the picker offers what the provider sells today
    /// without this app shipping a build for every model release.
    ///
    /// Quiet about FAILURE: it passes `silent`, so `refreshModels` leaves the error surface untouched
    /// in both directions rather than this restoring it afterwards. Restoring would have raced — there
    /// is no re-entrancy guard here, so a manual Refresh tapped during the await would have had its
    /// result stomped by a stale snapshot on resume. Not touching the state cannot race with anything.
    ///
    /// Requires a stored key, so it cannot fire during first-run setup where there is nothing to
    /// authenticate with. Custom is excluded: `connectCustom()` already pulls its list, and its server
    /// is the user's own machine rather than a vendor catalogue.
    ///
    /// Only the LIST moves. The selected model is never changed underneath the user. Kotlin twin:
    /// `CoachViewModel.refreshModelsIfStale`.
    func refreshModelsIfStale() async {
        guard provider != .custom, hasKey else { return }
        let last = UserDefaults.standard.double(forKey: Self.modelsRefreshedKey(provider))
        guard Self.isCatalogueStale(last: last, now: Date().timeIntervalSince1970) else { return }
        await refreshModels(silent: true)
    }

    /// `silent` leaves the error surface entirely alone, in both directions: an automatic refresh must
    /// neither wipe a message the user is still reading nor raise one they never asked for. Kotlin twin:
    /// the `silent` parameter on `CoachViewModel.refreshModels`.
    func refreshModels(silent: Bool = false) async {
        guard let key = resolvedKey else {
            if !silent { errorText = AICoachError.noKey.errorDescription }
            return
        }
        if !silent { errorText = nil }

        // Snapshot the provider BEFORE the await. The Picker isn't disabled during a refresh, so the
        // user can switch providers mid-flight (#873). We fetch this provider's ids, then re-check on
        // resume that it's still the live one, and merge against THIS same snapshot, so the guard and
        // the merge always use one consistent provider, never a stale/mixed list for the wrong one.
        let capturedProvider = provider

        do {
            let ids: [String]
            #if DEBUG
            if let override = fetchModelsOverride {
                ids = try await override(capturedProvider, key)
            } else {
                ids = try await capturedProvider.client.fetchModels(key: key, session: session)
            }
            #else
            ids = try await capturedProvider.client.fetchModels(key: key, session: session)
            #endif

            // The user switched providers while we were awaiting, so these ids belong to the old one.
            // Drop them rather than write a list for a provider that's no longer selected.
            guard provider == capturedProvider else { return }

            guard !ids.isEmpty else {
                if !silent { errorText = AICoachError.decode.errorDescription }
                return
            }

            // Merge: keep the captured provider's built-in options on top, append any newly-discovered
            // ids (sorted), and preserve a current custom selection if it isn't otherwise present.
            let builtin = capturedProvider.modelOptions
            let discovered = Set(ids).subtracting(builtin).sorted()
            var merged = builtin + discovered
            if !merged.contains(model) { merged.insert(model, at: 0) }
            availableModels = merged
            // Stamp only on a SUCCESSFUL pull, so a provider that is down does not buy itself a week
            // of silence from `refreshModelsIfStale()`.
            UserDefaults.standard.set(Date().timeIntervalSince1970,
                                      forKey: Self.modelsRefreshedKey(capturedProvider))
        } catch let e as AICoachError {
            // A switch mid-flight makes any error moot for the old provider, so don't surface it.
            guard provider == capturedProvider, !silent else { return }
            // Typed first, because this used to report EVERY failure as a network problem, including a
            // key the provider had just turned away. Refresh is one of the two places a wrong key shows
            // itself, and it was the one that blamed the wrong thing: the wearer read "Network problem"
            // and went looking at their connection. It now says what happened and, for a rejection,
            // opens the field to fix it.
            errorText = e.errorDescription
            if case .badKey = e { keyRejected = true } else { keyRejected = false }
            return
        } catch {
            guard provider == capturedProvider, !silent else { return }
            errorText = AICoachError.network(error.localizedDescription).errorDescription
            keyRejected = false
            return
        }
    }

    // MARK: Sending

    /// Hard rolling cap on the STORED transcript. The network payload is separately windowed by
    /// `windowedMessages()` (`maxHistoryMessages`); this bounds the in-memory `messages` array — and the
    /// SwiftUI transcript rendered from it — so a long-lived session can't grow it without bound. `coach`
    /// is a single app-lifetime instance on `AppModel`, so before this an active chat grew `messages`
    /// until the process was killed: the "gets laggy the longer the app runs, reopening fixes it, feels
    /// like RAM" report. Cap >> the wire window, so it never changes what's sent. (parity with Android)
    private static let maxStoredMessages = 40
    private func appendMessage(_ message: ChatMessage) {
        messages.append(message)
        if messages.count > Self.maxStoredMessages {
            messages.removeFirst(messages.count - Self.maxStoredMessages)
        }
    }

    // MARK: - K2: persisted conversation history

    /// Guards `loadPersistedMessagesIfNeeded()` so it only ever runs once per app launch, even if the
    /// Coach screen's `.task` re-fires (e.g. a tab re-select).
    private var didLoadPersistedMessages = false

    // MARK: - Conversation history (personal fork, migration v50)

    /// The conversation the transcript belongs to; nil until its first save gives it a row.
    private var currentConversation: CoachConversationRow?

    /// Every saved conversation, pinned first then most recent, for the history screen.
    @Published private(set) var conversations: [CoachConversationRow] = []

    /// The id of the conversation on screen, nil for a new one not saved yet.
    var currentConversationId: String? { currentConversation?.id }

    /// Load the history and reopen today's conversation (PRD-K2), so relaunching doesn't lose it.
    /// Called from the Coach screen's `.task` (mirroring `startBriefIfNeeded`) rather than `init`,
    /// which is synchronous and runs for every screen the app builds, not just Coach. Best-effort: a
    /// store failure just leaves the transcript empty, matching pre-K2 behaviour — never crashes.
    func loadPersistedMessagesIfNeeded() async {
        guard !didLoadPersistedMessages else { return }
        didLoadPersistedMessages = true
        guard let store = await repo.storeHandle() else { return }
        conversations = (try? await store.coachConversations()) ?? []
        guard messages.isEmpty, let latest = conversations.max(by: { $0.updatedAt < $1.updatedAt }) else {
            return
        }
        // Only a conversation last written TODAY is reopened (#1542, #2087: the day comes from the
        // stored row, since `conversationDay` does not survive a relaunch). An older one is not
        // restored but stays in the history, where it can be reopened on purpose.
        let lastDay = Self.localEpochDay(Date(timeIntervalSince1970: TimeInterval(latest.updatedAt)))
        guard !Self.isStaleConversation(lastEpochDay: lastDay, todayEpochDay: Self.localEpochDay()) else {
            return
        }
        await putOnScreen(latest, from: store)
        conversationDay = lastDay
    }

    /// Reopen a conversation from the history. Continuing it is a deliberate choice, so it counts as
    /// today's: the day boundary in `send` does not start a new one under it. Ignored mid-reply.
    func openConversation(id: String) async {
        guard activeTurn == nil, id != currentConversation?.id,
              let row = conversations.first(where: { $0.id == id }),
              let store = await repo.storeHandle() else { return }
        await putOnScreen(row, from: store)
        conversationDay = Self.localEpochDay()
    }

    /// Start an empty conversation. The current one stays in the history. Ignored mid-reply.
    func startNewConversation() {
        guard activeTurn == nil else { return }
        resetTranscript()
    }

    /// Rename a conversation. A blank name is ignored; once renamed, the automatic title stops
    /// applying to it.
    func renameConversation(id: String, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if currentConversation?.id == id {
            currentConversation?.title = trimmed
            currentConversation?.titleEdited = true
        }
        updateHistory { try await $0.renameCoachConversation(id: id, title: trimmed) }
    }

    /// Pin a conversation to the top of the history, or unpin it.
    func setConversationPinned(id: String, pinned: Bool) {
        if currentConversation?.id == id { currentConversation?.pinned = pinned }
        updateHistory { try await $0.setCoachConversationPinned(id: id, pinned: pinned) }
    }

    /// Delete a conversation from the history. Deleting the one on screen also stops its reply and
    /// leaves an empty conversation.
    func deleteConversation(id: String) {
        if currentConversation?.id == id {
            stopReply()
            resetTranscript()
        }
        updateHistory { try await $0.deleteCoachConversation(id: id) }
    }

    /// Put a stored conversation on screen.
    private func putOnScreen(_ row: CoachConversationRow, from store: WhoopStore) async {
        let rows = (try? await store.coachConversationMessages(conversationId: row.id)) ?? []
        resetTranscript()
        messages = rows.map {
            ChatMessage(id: UUID(uuidString: $0.id) ?? UUID(),
                        role: ChatMessage.Role(rawValue: $0.role) ?? .user,
                        text: $0.text)
        }
        currentConversation = row
    }

    /// Empty the transcript and detach it from its stored conversation, which is left untouched.
    private func resetTranscript() {
        messages = []
        currentConversation = nil
        conversationDay = nil
        droppedSummary = nil      // K13: the summary belongs to the conversation it summarised
        droppedSummaryKey = []
        errorText = nil
        keyRejected = false
    }

    /// Run one history write, then reload the list. Fire-and-forget, like `persistMessages`.
    private func updateHistory(_ write: @escaping (WhoopStore) async throws -> Void) {
        Task {
            guard let store = await repo.storeHandle() else { return }
            try? await write(store)
            conversations = (try? await store.coachConversations()) ?? conversations
        }
    }

    /// Save the transcript as the current conversation, with ALL of its turns. Called once per
    /// completed send/brief (not per streamed chunk) so a streamed reply's several in-place text
    /// mutations don't hammer the store. Fire-and-forget; a store failure never blocks the UI — the
    /// in-memory transcript (what the user sees) is unaffected either way.
    private func persistMessages() {
        guard !messages.isEmpty else { return }
        let now = Int(Date().timeIntervalSince1970)
        var conversation = currentConversation
            ?? CoachConversationRow(id: UUID().uuidString, title: "", createdAt: now, updatedAt: now)
        conversation.updatedAt = now
        if conversation.title.isEmpty, !conversation.titleEdited,
           let question = messages.first(where: { $0.role == .user }) {
            conversation.title = CoachConversationTitle.make(fromQuestion: question.text)
        }
        currentConversation = conversation
        let snapshot = messages
        let providerId = provider.rawValue
        let saved = conversation
        updateHistory { store in
            let rows = snapshot.enumerated().map { index, m in
                CoachMessageRow(id: m.id.uuidString, role: m.role.rawValue, text: m.text,
                                provider: providerId, createdAt: now, orderIndex: index)
            }
            try await store.saveCoachConversation(saved, messages: rows)
        }
    }

    /// The Coach menu's "Clear conversation" action: deletes the conversation on screen from the
    /// history and leaves an empty one. The in-memory clear is immediate.
    func clearConversation() {
        guard let id = currentConversation?.id else {
            stopReply()
            resetTranscript()
            return
        }
        deleteConversation(id: id)
    }

    /// K5: surface a brief generated by the SCHEDULED morning-brief notification as the first Coach
    /// message, with no network call — called once when the app opens via a tap on that notification.
    /// No-op if a conversation already exists, so it never duplicates into an active chat.
    func surfaceScheduledBrief(_ text: String) {
        guard messages.isEmpty else { return }
        appendMessage(ChatMessage(role: .assistant, text: "Today's brief\n\n" + text))
        conversationDay = Self.localEpochDay()
        persistMessages()
    }

    /// Start a new conversation over yesterday's when Coach is opened, before checking for today's
    /// scheduled brief. A process kept alive overnight does not reload persisted messages, so the
    /// one-time load check cannot do it. Yesterday's conversation stays in the history.
    func retireStaleConversationIfNeeded() {
        guard Self.isStaleConversation(lastEpochDay: conversationDay,
                                       todayEpochDay: Self.localEpochDay()) else { return }
        resetTranscript()
    }

    /// K5: append an explicitly-generated brief (the Coach settings "Generate now" button) as a new
    /// assistant message, unconditionally — unlike `surfaceScheduledBrief`, this always appends so a
    /// mid-conversation tap still shows the fresh brief.
    func appendGeneratedBrief(_ text: String) {
        retireStaleConversationIfNeeded()
        appendMessage(ChatMessage(role: .assistant, text: "Today's brief\n\n" + text))
        conversationDay = Self.localEpochDay()
        persistMessages()
    }

    /// K11: An optional chart image (base64-encoded PNG) to send with the next user message.
    /// Set by the composer's "Attach chart" toggle when multimodal is enabled and the provider
    /// is Gemini. Consumed (cleared) on the next send. nil when no image is attached.
    @Published var pendingChartImage: String?

    // MARK: - The turn in flight

    /// The question or brief being answered right now, owned by the engine rather than by a view.
    ///
    /// A view's `.task` is cancelled when the view disappears, and the first-open brief used to run in
    /// one: switching tab mid-brief cancelled its request and left a network error on screen. Started
    /// here, a turn outlives the screen that asked for it, and only `stopReply()` cancels it. One turn
    /// at a time: two streams writing the same transcript is how a reply lands in the wrong bubble.
    private var activeTurn: Task<Void, Never>?

    /// A question handed over (Siri, the Today launcher, a Lift Log session) while a turn was in
    /// flight. It is asked as soon as that turn ends, instead of being dropped or racing it. One slot:
    /// the composer itself cannot send while a reply streams.
    private var queuedQuestion: String?

    /// Ask `text` on the engine's own task (see `activeTurn`); queued while another turn is in flight.
    func submit(_ text: String) {
        guard activeTurn == nil else {
            queuedQuestion = text
            return
        }
        activeTurn = Task {
            await send(text)
            endTurn()
        }
    }

    /// Run the first-open brief on the engine's own task, when `startBriefIfNeeded` would run one.
    /// Ignored while another turn is in flight.
    func beginBriefIfNeeded() {
        guard activeTurn == nil else { return }
        activeTurn = Task {
            await startBriefIfNeeded()
            endTurn()
        }
    }

    /// The composer's Stop button: cancel the turn in flight. The text already received stays in the
    /// transcript as it stands, and no error is shown, since the wearer asked for it. A queued
    /// question is dropped too: Stop means stop.
    func stopReply() {
        queuedQuestion = nil
        activeTurn?.cancel()
    }

    private func endTurn() {
        activeTurn = nil
        if let next = queuedQuestion {
            queuedQuestion = nil
            submit(next)
        }
    }

    /// Send a question: append it, build the metrics context, call the chosen provider with the
    /// system prompt + context + running history, parse the reply, append it. Never throws/crashes;
    /// failures land in `errorText`.
    func send(_ userText: String) async {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { errorText = AICoachError.emptyQuestion.errorDescription; return }
        // The master switch, checked at the EGRESS rather than only on the routes in. Every way into Coach
        // is gated, but "gated everywhere I thought of" is what #2254 got wrong once: a revoked consent
        // survived in memory because the conversation never re-read it. A wearer can be STANDING on this
        // screen when the switch goes off, and that path passes no tab. Refusing here makes "the AI is off"
        // true however the screen was reached.
        guard CoachBriefScheduler.coachMasterEnabled else { return }
        guard let key = resolvedKey else { errorText = AICoachError.noKey.errorDescription; return }

        // A transcript from an earlier local day is retired before the new turn is appended (#1542,
        // Kotlin twin merged first). `messages` outlives a night — the engine is held for the app's
        // lifetime — so without this the coach answers TODAY's question inside YESTERDAY's
        // conversation. The DATA was never stale: buildFullContext() re-reads on every send. It is the
        // assistant's own earlier turns stating yesterday's figures, and the model staying consistent
        // with them, which reads as "the coach only talks about my imported data" after a night of
        // fresh strap data.
        //
        // Placed AFTER the guards on purpose: a send that never happens must not wipe a transcript.
        retireStaleConversationIfNeeded()
        conversationDay = Self.localEpochDay()

        errorText = nil
        appendMessage(ChatMessage(role: .user, text: trimmed))
        sending = true
        // K2: persist once the turn is fully settled (success, mid-stream error, or empty-stream
        // removal) — not per streamed chunk, so a long reply doesn't hammer the store.
        defer { sending = false; persistMessages() }

        // Build the data context once and prepend it to the FIRST user turn we send. We send the
        // full running history so follow-ups stay coherent; the context only needs to ride the
        // earliest user message.
        // Include the user's data ONLY with explicit consent; otherwise send a note instead of numbers.
        let context = await questionContext()
        // K13: if the conversation overflows the sliding window, summarize the dropped middle so
        // the model retains context continuity. Best-effort; failure degrades to the old gap.
        await summarizeDroppedMiddleIfNeeded(key: key)
        var wire = wireMessages(context: context)

        // K11: If a chart image is pending and the provider is Gemini, attach it to the last
        // user turn as inline_data. Non-Gemini providers can't accept images, so the image is
        // silently dropped (the text question still goes through). Cleared after consumption.
        let imageBase64 = pendingChartImage
        pendingChartImage = nil

        // K1: Stream the reply into a placeholder bubble; an empty stream reads "(no reply)".
        await streamAssistantTurn(key: key, wire: wire, inlineImage: imageBase64, emptyText: "(no reply)")
    }

    /// Proactively generate "Today's brief" the first time the Coach opens, readiness + a training
    /// prescription + one recovery tip, without the user typing. Requires a key + data consent.
    /// K1: streams the brief the same way `send` does.
    func startBriefIfNeeded() async {
        guard isConfigured, dataConsent, messages.isEmpty, !sending else { return }
        guard let key = resolvedKey else { return }
        errorText = nil
        sending = true
        defer { sending = false; persistMessages() }

        let context = await buildFullContext()
        let wire: [(role: ChatMessage.Role, content: String)] =
            [(.user, context + "\n\n---\n\n" + Self.briefInstruction)]

        // An empty brief removes its placeholder rather than leaving a bare heading.
        await streamAssistantTurn(key: key, wire: wire, prefix: "Today's brief\n\n", emptyText: nil)
    }

    /// Stream one assistant turn into the transcript (K1), shared by `send` and `startBriefIfNeeded`.
    ///
    /// Appends a placeholder reading `prefix` and rewrites it as the reply arrives. All of it runs on
    /// the main actor: `streamProvider` relays the provider's chunks here (see `CoachStreamRelay`).
    /// The placeholder is found by its id, never as "the last message", so a bubble appended mid-stream
    /// (a brief generated from settings) is never overwritten. How the turn settles:
    /// - success: the trimmed reply; an empty one shows `emptyText`, or drops the placeholder when nil;
    /// - failure: the partial reply plus an interrupted marker (PRD K1), and the error surfaced;
    /// - Stop (`stopReply`): the partial reply as it stands, and no error.
    private func streamAssistantTurn(key: String,
                                     wire: [(role: ChatMessage.Role, content: String)],
                                     inlineImage: String? = nil,
                                     prefix: String = "",
                                     emptyText: String?) async {
        guard !Task.isCancelled else { return }
        let placeholder = ChatMessage(role: .assistant, text: prefix)
        appendMessage(placeholder)
        var received = ""

        func show(_ text: String) {
            guard let index = messages.lastIndex(where: { $0.id == placeholder.id }) else { return }
            messages[index] = ChatMessage(id: placeholder.id, role: .assistant, text: text)
        }
        func dropPlaceholder() {
            messages.removeAll { $0.id == placeholder.id }
        }

        do {
            let reply = try await streamProvider(key: key, messages: wire, inlineImage: inlineImage) { text in
                received = text
                show(prefix + text)
            }
            let clean = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                show(prefix + clean)
            } else if let emptyText {
                show(prefix + emptyText)
            } else {
                dropPlaceholder()
            }
        } catch {
            let partial = received.trimmingCharacters(in: .whitespacesAndNewlines)
            if Task.isCancelled || error is CancellationError {
                if partial.isEmpty { dropPlaceholder() } else { show(prefix + partial) }
                return
            }
            if partial.isEmpty {
                dropPlaceholder()
            } else {
                show(prefix + partial + "\n\n*(stream interrupted)*")
            }
            if let e = error as? AICoachError {
                errorText = e.errorDescription
                // Typed, never text-matched: the message is localized and the case is not.
                if case .badKey = e { keyRejected = true } else { keyRejected = false }
            } else {
                errorText = AICoachError.network(error.localizedDescription).errorDescription
                keyRejected = false
            }
        }
    }

    /// K5: The brief instruction shared by the interactive `startBriefIfNeeded()` (streamed into the
    /// chat) and the headless `generateBrief()` below (used by the scheduled morning-brief notification).
    /// Kept in one place so the two paths never drift.
    private static let briefInstruction = """
    Based on the data above, give me TODAY'S coaching brief in three short parts: \
    (1) my readiness in one line, citing charge, HRV and rest; \
    (2) exactly what training to do today and what to avoid — when the LIFT LOG names a likely next \
    program in the rotation, name it as today's program and list its exercises with the load to use, \
    stepping up where last time's sets earned it; \
    (3) one specific thing to improve my charge. Be punchy and motivating.
    """

    /// K5: Generate today's coaching brief WITHOUT touching the visible chat transcript. Used by the
    /// scheduled morning-brief notification (`CoachBriefScheduler`), which can run with no Coach screen
    /// open and must never append to (or duplicate into) `messages`. Non-streaming (a background/BGTask
    /// context has no UI to stream into). Returns nil when not configured/consented, on any network
    /// failure, or when the reply is empty — the caller treats nil as "brief unavailable"; never throws.
    func generateBrief() async -> String? {
        // Same master-switch gate as `send`, because this entry has NO UI at all: it is what the scheduler
        // calls, and a caller that skipped the scheduler's own gate would otherwise reach a provider with
        // the AI switched off.
        guard CoachBriefScheduler.coachMasterEnabled else { return nil }
        guard isConfigured, dataConsent, let key = resolvedKey else { return nil }
        let context = await buildFullContext()
        let wire: [(role: ChatMessage.Role, content: String)] =
            [(.user, context + "\n\n---\n\n" + Self.briefInstruction)]
        guard let reply = try? await callProvider(key: key, messages: wire) else { return nil }
        let clean = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    /// The data context a question carries, exactly as `send` attaches it: the full context with data
    /// access on; otherwise the no-consent note and what the user told the coach, which they wrote for it.
    /// One funnel for `send` and the "exact text sent" preview, so the preview cannot show something the
    /// request does not carry.
    func questionContext() async -> String {
        guard dataConsent else { return noConsentNote + "\n\n" + coachProfile.contextBlock }
        return await buildFullContext()
    }

    /// Full data context = the fiche head (profile, what the user told the coach, today, normals, sleep)
    /// + the metrics summary + recent workouts + stress + the Lift Log and its statuses + naps (+ an OPT-IN
    /// on-device-signals summary when the second consent is on). Used when the user has granted data access.
    func buildFullContext() async -> String {
        let fiche = await ficheInputs()
        var ctx = CoachFiche.head(fiche, told: coachProfile.contextBlock)
        ctx += "\n\n" + buildContext()
        ctx += "\n\n" + (await recentWorkoutsBlock())
        // Derived stress: a single Baevsky Stress Index summary line over today's R-R, computed the same
        // way StressView does. Gated here under `dataConsent` (the caller only reaches buildFullContext()
        // with consent on), so it rides the SAME consent + text-only channel as the HRV/RHR summary, a
        // derived number, never raw R-R egress. Omitted when there aren't enough clean beats yet.
        if let line = await stressIndexLine() { ctx += "\n\n" + line }
        // The Lift Log's sets, summarised (personal fork). Same consent as the rest of this context:
        // the caller only reaches here with `dataConsent` on.
        let lift = await liftLogBlock()
        if !lift.isEmpty { ctx += "\n\n" + lift }
        // The Lift Log's own verdict per exercise, after the sets it is drawn from.
        let progression = CoachFiche.progression(fiche)
        if !progression.isEmpty { ctx += "\n\n" + progression }
        // The recent days' naps (personal fork): the day lines carry the main night only.
        let naps = await napsBlock()
        if !naps.isEmpty { ctx += "\n\n" + naps }
        if includeOnDeviceSignals {
            let block = await onDeviceSignalsBlock()
            if !block.isEmpty { ctx += "\n\n" + block }
        }
        return ctx
    }

    /// The body profile as the context states it, nil without a `ProfileStore`. Also what the "What the
    /// coach reads" screen shows, so the two read one resolver.
    var bodyFiche: CoachFiche.Body? {
        guard let profile else { return nil }
        let stored = profile.storedBodyFields
        return CoachFiche.Body(age: profile.age, sex: profile.sex, sexStored: stored.sex,
                               heightCm: profile.heightCm, heightStored: stored.height,
                               weightKg: profile.weightKg, weightStored: stored.weight,
                               hrMax: profile.hrMax, hrMaxSetByUser: profile.hrMaxOverride > 0)
    }

    /// Everything the fiche states, resolved with the helpers the Today, Sleep and Lift Log screens use,
    /// so the coach reads the figures those screens show. Re-read on every question.
    ///
    /// Today's effort and calories are computed over the calendar day (midnight to now); the Today screen
    /// does the same unless its day-cycle mode is set to start at sleep onset.
    func ficheInputs() async -> CoachFiche.Inputs {
        var inputs = CoachFiche.Inputs()
        let system = UnitSystem(rawValue: UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric
        inputs.unitSystem = system
        inputs.body = bodyFiche

        let days = repo.days
        let todayRow = repo.today
        let todayKey = todayRow?.day ?? Repository.localDayKey(Date())
        let through = days.filter { $0.day <= todayKey }

        // Today's own value, else the latest night the Today screen carries forward.
        func carried(_ own: Double?, _ carry: DailyMetric?, _ value: (DailyMetric) -> Double?) -> CoachFiche.Reading? {
            if let own { return CoachFiche.Reading(value: own, day: todayKey) }
            guard let carry, let v = value(carry) else { return nil }
            return CoachFiche.Reading(value: v, day: carry.day)
        }
        let rhr = carried(todayRow?.restingHr.map(Double.init),
                          Repository.lastRestingHrDay(days: days, todayKey: todayKey)) { $0.restingHr.map(Double.init) }
        let hrv = carried(todayRow?.avgHrv, Repository.lastHrvDay(days: days, todayKey: todayKey)) { $0.avgHrv }

        var effort = todayRow?.strain
        var split: TodayEnergy.Split?
        if let profile {
            let now = Date()
            let from = Int(Calendar.current.startOfDay(for: now).timeIntervalSince1970)
            let hr = await repo.hrSamples(from: from, to: Int(now.timeIntervalSince1970), limit: 200_000)
            let maxHR = profile.effortHRmax
            let restHR = todayRow?.restingHr.map(Double.init) ?? StrainScorer.defaultRestingHR
            let dayRest = todayRow?.restingHr.map(Double.init)
            let method = PuffinExperiment.effortMethod
            let sex = profile.sex
            let body = UserProfile(weightKg: profile.weightKg, heightCm: profile.heightCm,
                                   age: Double(profile.age), sex: profile.sex)
            let live = await Task.detached(priority: .utility) {
                StrainScorer.strain(hr, maxHR: maxHR, restingHR: restHR, method: method, sex: sex)
            }.value
            effort = StrainScorer.effectiveEffort(live: live, stored: todayRow?.strain)
            split = await Task.detached(priority: .utility) {
                TodayEnergy.split(hr: hr, profile: body, hrmax: maxHR, restingHR: dayRest)
            }.value
        }

        inputs.today = CoachFiche.Today(
            day: todayKey, charge: todayRow?.recovery, effort: effort, restMin: todayRow?.totalSleepMin,
            deepMin: todayRow?.deepMin, remMin: todayRow?.remMin, lightMin: todayRow?.lightMin,
            efficiency: todayRow?.efficiency, restingHR: rhr, hrv: hrv,
            spo2: carried(todayRow?.spo2Pct, Repository.lastVitalsDay(days: days, todayKey: todayKey)) { $0.spo2Pct },
            respiration: carried(todayRow?.respRateBpm, Repository.lastRespDay(days: days, todayKey: todayKey)) { $0.respRateBpm },
            skinTempDev: carried(todayRow?.skinTempDevC,
                                 Repository.lastSkinTempReadingDay(days: days, todayKey: todayKey)) { $0.skinTempDevC },
            steps: todayRow?.steps, restingKcal: split?.restingKcal, activityKcal: split?.activityKcal)

        // The half-gauges' figures: last night against the last 30 nights and the Charge baseline.
        inputs.restingHRNormal = TodayVitalRange.normalBand(repo.chargeBaselines?.restingHR)
        inputs.hrvNormal = TodayVitalRange.normalBand(repo.chargeBaselines?.hrv)
        inputs.restingHRGauge = TodayVitalRange.gauge(
            value: rhr?.value,
            history: days.compactMap { d in d.restingHr.map { (day: d.day, value: Double($0)) } },
            throughDay: todayKey, normal: inputs.restingHRNormal)
        inputs.hrvGauge = TodayVitalRange.gauge(
            value: hrv?.value,
            history: days.compactMap { d in d.avgHrv.map { (day: d.day, value: $0) } },
            throughDay: todayKey, normal: inputs.hrvNormal)

        // The synthesis' sleep figures: the debt ledger (naps credited), the need, the usual wake.
        if !through.isEmpty {
            let sessions = await repo.allSleepSessions(days: 17)
            let habitual = await repo.habitualMidsleepSec()
            let naps = SleepModel.napSleepMinutesByDay(navDays: SleepModel.navDays(navSessions: sessions),
                                                       habitualMidsleepSec: habitual)
            let nights = SleepNightsData(ledger: SleepModel.debtLedger(days: through, napSleepMinByDay: naps),
                                         month: [])
            let now = Int(Date().timeIntervalSince1970)
            let wakes = repo.sleeps.map(\.endTs).filter { $0 <= now }.sorted()
            let last30 = through.suffix(30).compactMap(\.totalSleepMin)
            inputs.sleep = CoachFiche.Sleep(
                needMin: SleepModel.debtNeedMin(days: through),
                debtMin: nights.recent.isEmpty ? nil : nights.debtMinutes,
                isDebt: nights.isDebt,
                lastShortfallMin: nights.lastShortfallMinutes,
                usualWakeMin: HabitualWake.minutes(wakeTimestamps: wakes, zone: .current),
                lastNightMin: todayRow?.totalSleepMin,
                average30Min: last30.isEmpty ? nil : last30.reduce(0, +) / Double(last30.count))
        }

        // The Lift Log's statuses and priorities, read as the Progression screen reads them.
        let step = system == .imperial ? LiftProgression.imperialStepKg : LiftProgression.metricStepKg
        if let data = await LiftProgressData.load(repo: repo, stepKg: step), !data.isEmpty {
            inputs.exercises = data.exercises
            inputs.priorities = data.priorities(.fourWeeks)
        }
        return inputs
    }

    /// The naps block for the context (`CoachNapContext`): the last two weeks' daytime sleep, split from
    /// the night by the same selector the Sleep tab uses. "" when no day in the window had a nap.
    func napsBlock() async -> String {
        let sessions = await repo.allSleepSessions(days: CoachNapContext.windowDays + 1)
        guard !sessions.isEmpty else { return "" }
        let habitual = await repo.habitualMidsleepSec()
        let naps = CoachNapContext.naps(
            dayGroups: SleepModel.navDays(navSessions: sessions), habitualMidsleepSec: habitual
        ) { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0))) }
        let mainByDay = Dictionary(repo.days.compactMap { d in d.totalSleepMin.map { (d.day, $0) } },
                                   uniquingKeysWith: { _, last in last })
        return CoachNapContext.summary(naps: naps, mainSleepMinByDay: mainByDay, zone: .current)
    }

    /// The Lift Log block for the context (`CoachLiftContext`): the last few weeks of sessions with
    /// their sets, and the saved programs. "" when there is no store or nothing logged.
    func liftLogBlock() async -> String {
        guard let store = await repo.storeHandle() else { return "" }
        let now = Int(Date().timeIntervalSince1970)
        let from = now - CoachLiftContext.lookbackDays * 86_400
        let rows = (try? await store.liftSessions(deviceId: repo.deviceId, fromTs: from, toTs: now)) ?? []
        var sessions: [CoachLiftContext.Session] = []
        for row in rows {
            sessions.append(.init(row: row, sets: (try? await store.liftSets(sessionId: row.id)) ?? []))
        }
        var programs: [CoachLiftContext.Program] = []
        for row in ((try? await store.liftPrograms(deviceId: repo.deviceId)) ?? [])
            .prefix(CoachLiftContext.maxPrograms) {
            programs.append(.init(row: row, items: (try? await store.liftProgramItems(programId: row.id)) ?? []))
        }
        let system = UnitSystem(
            rawValue: UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric
        return CoachLiftContext.summary(sessions: sessions, programs: programs, now: now, system: system)
    }

    /// One derived stress line for the coach context: the Baevsky Stress Index over TODAY's R-R, read
    /// via the same device-aware repository R-R union as `StressView`,
    /// then summarised to a single number with `StressIndex.stressIndex(rr:)`. Returns nil when the
    /// store is unavailable or there are too few clean beats (the histogram needs >= 20), so the line is
    /// simply absent, never a fabricated value. Summary-only: the raw R-R never leaves the device.
    func stressIndexLine() async -> String? {
        let cal = Calendar.current
        let from = Int(cal.startOfDay(for: Date()).timeIntervalSince1970)
        let to = Int(Date().timeIntervalSince1970)
        let rr = await repo.rrIntervals(from: from, to: to, limit: 200_000)
        guard let si = StressIndex.stressIndex(rr: rr) else { return nil }
        return Self.stressIndexSummary(si: si)
    }

    /// Pure formatter for the derived stress line, kept separate so it is unit-testable without a store.
    /// One summary number, labelled, with a plain-English note that it's an autonomic-balance proxy.
    static func stressIndexSummary(si: Double) -> String {
        "Stress (SI): \(Int(si.rounded())) (Baevsky Stress Index over today's R-R; higher means more sympathetic / under load; an autonomic-balance proxy, not a clinical figure)."
    }

    /// A SUMMARY-ONLY block of the new on-device signals, the user's strongest n-of-1 correlations
    /// (lag-aware EffectRanker) and a one-line roll-up of their Lab Book markers. Plain sentences, never
    /// raw readings: this rides the same text channel as the metrics summary, so the no-raw-egress posture
    /// holds. Gated by the caller on the second opt-in; returns "" when there's nothing worth adding.
    func onDeviceSignalsBlock() async -> String {
        var lines: [String] = []

        // 1. Strongest behaviour→outcome associations (EffectRanker over the journal × Charge).
        let entries = await repo.journalEntries()
        // Yes days and NO days, kept apart. A day with no journal row for the question lands in
        // neither, so an unanswered day is never counted as a No (BehaviorInsights.effect).
        var byBehaviour: [String: Set<String>] = [:]
        var controls: [String: Set<String>] = [:]
        for e in entries {
            if e.answeredYes { byBehaviour[e.question, default: []].insert(e.day) }
            else { controls[e.question, default: []].insert(e.day) }
        }
        if !byBehaviour.isEmpty {
            let outcomeByDay = Dictionary(
                repo.days.compactMap { d in d.recovery.map { (d.day, $0) } },
                uniquingKeysWith: { _, last in last })
            let ranked = EffectRanker.rank(behaviors: byBehaviour, controls: controls,
                                           outcomeByDay: outcomeByDay, outcome: "Charge")
                .filter { $0.effect.significant }
                .prefix(3)
            if !ranked.isEmpty {
                lines.append("STRONGEST PERSONAL PATTERNS (the user's own data — association, not cause):")
                for r in ranked { lines.append("  • " + r.sentence()) }
            }
        }

        // 2. Lab Book markers roll-up (count + latest of a few, never the full history).
        if let store = await repo.storeHandle() {
            var markerSummaries: [String] = []
            for category in LabMarkerCategory.allCases {
                let rows = (try? await store.labMarkers(deviceId: repo.deviceId, category: category.rawValue)) ?? []
                let byKey = Dictionary(grouping: rows, by: { $0.markerKey })
                for (key, kRows) in byKey {
                    guard let latest = kRows.sorted(by: { $0.takenAt < $1.takenAt }).last else { continue }
                    let name = MarkerCatalog.definition(for: key)?.displayName ?? key
                    let value = latest.value.map { "\(LabBookFormat.value($0, key: key)) \(latest.unit)" } ?? latest.valueText ?? "—"
                    markerSummaries.append("\(name) \(value)")
                }
            }
            if !markerSummaries.isEmpty {
                lines.append("")
                lines.append("LAB BOOK (the user's own logged health numbers — not medical advice; do not interpret as clinical findings):")
                lines.append("  " + markerSummaries.prefix(8).joined(separator: ", "))
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Dispatch to the user's chosen provider client.
    private func callProvider(key: String,
                              messages: [(role: ChatMessage.Role, content: String)]) async throws -> String {
        try await provider.client.send(
            key: key,
            model: model,
            systemPrompt: systemPrompt,
            messages: messages,
            session: session
        )
    }

    /// K1: Stream the chosen provider's reply and return its full text. The default
    /// `AIProviderClient.stream` falls back to `send` + a single delta, so providers without
    /// streaming still work. K11: dispatches through `streamWithImage` (Gemini sends the image;
    /// the others ignore it).
    ///
    /// The provider runs off the main actor and its chunks come back through `CoachStreamRelay`, so
    /// `onText` (the text received so far) is always called on the main actor, at most every
    /// `CoachStreamThrottle.interval`, and once more with the complete text before this returns or
    /// throws. Throws `CancellationError` when the calling task is cancelled.
    private func streamProvider(key: String,
                                messages: [(role: ChatMessage.Role, content: String)],
                                inlineImage: String? = nil,
                                onText: (String) -> Void) async throws -> String {
        let client = provider.client
        let model = self.model
        let systemPrompt = self.systemPrompt
        let session = self.session
        let chunks = CoachStreamRelay.deltas { onDelta in
            try await client.streamWithImage(key: key, model: model, systemPrompt: systemPrompt,
                                             messages: messages, inlineImage: inlineImage,
                                             session: session, onDelta: onDelta)
        }

        var text = ""
        var published = ""
        var throttle = CoachStreamThrottle()
        defer { if text != published { onText(text) } }
        for try await chunk in chunks {
            text += chunk
            if throttle.shouldPublish(at: Date()) {
                onText(text)
                published = text
            }
        }
        try Task.checkCancellation()
        return text
    }

    /// Sliding window over the chat: the FIRST user turn (it carries the metrics context) plus the most
    /// recent `maxHistoryMessages`, dropping the middle. Sending the whole growing history crowds out the
    /// reply on small-context local servers (Ollama defaults to a 2048-token window, the Custom
    /// provider's main use case) and balloons token cost/latency on cloud providers. (parity with Android)
    /// True when a transcript last written on `lastEpochDay` should be retired before a question asked
    /// on `todayEpochDay` — i.e. the conversation crossed into a new local day.
    ///
    /// STRICTLY forward (`>`, never `!=`): a clock that moves BACKWARDS — the user flying west, a
    /// timezone change, an NTP correction — must not wipe a conversation they are in the middle of.
    /// Only real elapsed days retire a transcript. A nil `lastEpochDay` (nothing sent yet) is never
    /// stale. Kotlin twin: `CoachViewModel.isStaleConversation`.
    ///
    /// `nonisolated` because it is a pure function of its arguments. AICoachEngine is @MainActor, so
    /// without this the rule inherits that isolation and cannot be called from a synchronous test —
    /// which is exactly how the first attempt at this twin failed to compile. Isolating a function
    /// that touches no state buys nothing and costs its testability.
    nonisolated static func isStaleConversation(lastEpochDay: Int?, todayEpochDay: Int) -> Bool {
        guard let lastEpochDay else { return false }
        return todayEpochDay > lastEpochDay
    }

    /// Days since the epoch in the LOCAL calendar. Kotlin computes the same value with
    /// `LocalDate.now().toEpochDay()`.
    ///
    /// Counted with calendar day arithmetic from `startOfDay`, not by dividing an interval by 86,400:
    /// a day is not always 86,400 seconds (DST), and the rule only needs a value that increments
    /// exactly once per local midnight and orders correctly. Injectable so the tests never depend on
    /// the machine's clock or zone.
    nonisolated static func localEpochDay(_ date: Date = Date(), calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: date)
        let epoch = Date(timeIntervalSince1970: 0)
        return calendar.dateComponents([.day], from: epoch, to: start).day ?? 0
    }

    ///
    /// K13: when the middle is dropped, a one-line summary of the dropped turns is prepended to the
    /// first user turn so the model retains context continuity (instead of seeing a gap). The summary
    /// is generated via the same provider, with a short prompt; on failure it degrades to the old
    /// behaviour (no summary, just the windowed set).
    private static let maxHistoryMessages = 10
    /// K13: the cached summary of the dropped middle, regenerated when the dropped set changes.
    private var droppedSummary: String?
    private var droppedSummaryKey: [String] = []

    private func windowedMessages() -> [ChatMessage] {
        guard messages.count > Self.maxHistoryMessages + 1,
              let firstUser = messages.firstIndex(where: { $0.role == .user }) else { return messages }
        let recentStart = messages.count - Self.maxHistoryMessages
        // If the first user turn already falls inside the recent window, that window covers it.
        if firstUser >= recentStart { return Array(messages.suffix(Self.maxHistoryMessages)) }
        // K13: inject the summary of the dropped middle by prepending it to the first user turn,
        // so the model sees continuity instead of a gap. We don't use a separate system message
        // because the Role enum only has .user/.assistant (providers map those to API roles).
        var windowed = [messages[firstUser]]
        if let summary = droppedSummary {
            let first = windowed[0]
            windowed[0] = ChatMessage(id: first.id, role: first.role, text: "\(summary)\n\n---\n\n\(first.text)")
        }
        windowed.append(contentsOf: messages[recentStart...])
        return windowed
    }

    /// K13: When the conversation overflows the sliding window, summarize the dropped middle turns
    /// into a single system message. Called before each send when the window would drop messages.
    /// Best-effort: on any failure, leaves `droppedSummary` nil (the old gap behaviour).
    private func summarizeDroppedMiddleIfNeeded(key: String) async {
        guard messages.count > Self.maxHistoryMessages + 1,
              let firstUser = messages.firstIndex(where: { $0.role == .user }) else { return }
        let recentStart = messages.count - Self.maxHistoryMessages
        guard firstUser < recentStart else { return }

        // The dropped middle is messages[firstUser+1 ..< recentStart]. Cache on its identity so we
        // don't re-summarize the same set on every send.
        let dropped = Array(messages[(firstUser + 1)..<recentStart])
        let keySignature = dropped.map { "\($0.role.rawValue):\($0.text)" }
        guard droppedSummaryKey != keySignature else { return }
        droppedSummaryKey = keySignature

        // Build a compact transcript of the dropped turns for the summarizer.
        let transcript = dropped.map { m in
            "\(m.role == .user ? "User" : "Coach"): \(m.text)"
        }.joined(separator: "\n")

        let summaryPrompt = """
        Summarize the following conversation in 2-3 sentences, preserving the key advice and \
        any specific numbers or recommendations. This summary will be shown to you as context \
        for the ongoing conversation.\n\n\(transcript)
        """
        let wire: [(role: ChatMessage.Role, content: String)] = [
            (.user, "You are a concise summarizer. Summarize the conversation in 2-3 sentences.\n\n\(summaryPrompt)"),
        ]
        if let summary = try? await callProvider(key: key, messages: wire) {
            droppedSummary = "Summary of earlier conversation: \(summary.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }

    /// The chat as `(role, content)` pairs, with the metrics context prepended to the first user turn.
    private func wireMessages(context: String) -> [(role: ChatMessage.Role, content: String)] {
        var out: [(role: ChatMessage.Role, content: String)] = []
        var contextInjected = false
        for m in windowedMessages() {
            if m.role == .user && !contextInjected {
                contextInjected = true
                out.append((.user, context + "\n\n---\n\nQuestion: " + m.text))
            } else {
                out.append((m.role, m.text))
            }
        }
        return out
    }

    // MARK: - Context builder

    /// Build a compact plain-text summary of the user's recent data: last ~14 days of
    /// recovery/strain/sleep-hours/HRV/restingHR where present, plus 30-day averages, plus a few
    /// recent workouts. Kept well under ~1500 tokens. If there's no data, it says so.
    func buildContext() -> String {
        let days = repo.days // oldest → newest
        var lines: [String] = ["USER BIOMETRIC SUMMARY (the user's own wearable data):"]

        guard !days.isEmpty else {
            return """
            USER BIOMETRIC SUMMARY:
            No wearable data is available yet. Acknowledge this and give general, encouraging guidance \
            while inviting the user to sync their device so future advice can reference real numbers.
            """
        }

        // Last ~14 days, newest first for readability.
        let recent = Array(days.suffix(14)).reversed()
        lines.append("")
        lines.append("Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), "
                     + "deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:")
        for d in recent {
            lines.append("  " + dayLine(d))
        }

        // 30-day averages.
        let last30 = Array(days.suffix(30))
        lines.append("")
        lines.append("30-day averages:")
        lines.append("  charge: \(avgInt(last30.compactMap { $0.recovery }))"
                     + ", effort: \(avgOne(last30.compactMap { $0.strain }))"
                     + ", sleep: \(avgSleepHours(last30))h"
                     + ", HRV: \(avgInt(last30.compactMap { $0.avgHrv })) ms"
                     + ", RHR: \(avgInt(last30.compactMap { $0.restingHr.map(Double.init) })) bpm")
        // Additional vitals when present (#124, the coach used to see only recovery/strain/sleep/HRV/RHR).
        lines.append("  SpO2: \(avgInt(last30.compactMap { $0.spo2Pct }))%"
                     + ", respiration: \(avgOne(last30.compactMap { $0.respRateBpm }))/min"
                     + ", skin-temp deviation: \(avgOne(last30.compactMap { $0.skinTempDevC }))°C"
                     + ", steps: \(avgInt(last30.compactMap { $0.steps.map(Double.init) }))/day"
                     + ", active energy: \(avgInt(last30.compactMap { $0.activeKcalEst }))kcal/day")

        return lines.joined(separator: "\n")
    }

    /// Append recent workouts to an existing context string. Async (workouts are read from the store),
    /// so callers that want workouts in the context can await this and feed the result to `send`'s
    /// flow via the chat, kept separate so `buildContext()` stays synchronous per the spec.
    func recentWorkoutsBlock(limit: Int = 6) async -> String {
        let rows = await repo.workoutRows(days: 30) // newest first
        guard !rows.isEmpty else { return "Recent workouts: none recorded in the last 30 days." }
        let bodySystem = UnitSystem(
            rawValue: UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric
        let distanceSystem = UnitPrefs.resolveDistance(
            system: bodySystem,
            override: UserDefaults.standard.string(forKey: UnitPrefs.distanceSystemKey) ?? "")
        var lines = ["Recent workouts (newest first):"]
        for w in rows.prefix(limit) {
            var parts = ["  \(dateString(w.startTs)) \(w.sport)"]
            if let dur = w.durationS { parts.append("\(Int((dur / 60).rounded())) min") }
            if let s = w.strain { parts.append("effort \(String(format: "%.1f", s))") }
            if let hr = w.avgHr { parts.append("avg HR \(hr)") }
            if let kcal = w.energyKcal { parts.append("\(Int(kcal.rounded())) kcal") }
            if let dist = w.distanceM {
                parts.append(UnitFormatter.distanceFromMeters(dist, system: distanceSystem))
            }
            lines.append(parts.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Formatting helpers

    /// `internal`, not private, so `AICoachSleepContextTests` can assert the emitted line directly.
    /// Swift's `buildContext()` takes no arguments (it reads the repo), unlike the Kotlin twin which is
    /// handed the day list — so without this the formatter has no seam and the Swift half of a change
    /// with fifteen Kotlin tests would ship untested.
    func dayLine(_ d: DailyMetric) -> String {
        var parts: [String] = [d.day + ":"]
        parts.append("charge " + (d.recovery.map { "\(Int($0.rounded()))" } ?? "—"))
        parts.append("effort " + (d.strain.map { String(format: "%.1f", $0) } ?? "—"))
        parts.append("rest " + (d.totalSleepMin.map { String(format: "%.1fh", $0 / 60) } ?? "—"))
        // The stage breakdown and efficiency, which the coach could not see at all: a user asked why it
        // said it had no access to sleep stages, and it was answering honestly — `rest 7.8h` was every
        // word it got about a night. These four sit on the SAME DailyMetric the line already reads, so
        // nothing new is plumbed; they were simply never included. (#124 widened this context once
        // before, for the same reason.)
        //
        // Always emitted, "—" when absent, like every other field here. A night with no staging then
        // says so rather than going quiet, which matters more than line length: the alternative — only
        // appending stages when present — gives the model a schema that changes shape between days and
        // invites it to read a missing field as a zero.
        parts.append("deep " + hoursOrDash(d.deepMin))
        parts.append("REM " + hoursOrDash(d.remMin))
        parts.append("light " + hoursOrDash(d.lightMin))
        parts.append("eff " + efficiencyPercentOrDash(d.efficiency))
        parts.append("HRV " + (d.avgHrv.map { "\(Int($0.rounded()))ms" } ?? "—"))
        parts.append("RHR " + (d.restingHr.map { "\($0)bpm" } ?? "—"))
        return parts.joined(separator: ", ")
    }

    /// Minutes as "1.4h", or "—" when the night has no value. Matches the `rest` field's format so a
    /// stage total and the total it is part of read on the same scale.
    private func hoursOrDash(_ minutes: Double?) -> String {
        minutes.map { String(format: "%.1fh", $0 / 60) } ?? "—"
    }

    /// Efficiency as a percentage, NORMALISING the stored value first.
    ///
    /// `DailyMetric.efficiency` is not reliably a 0–1 fraction: it "arrives as % on some import paths",
    /// which `SleepView` and `StagesCard` each guard against inline with this same `> 1.5` test. A bare
    /// `* 100` would therefore hand the coach "eff 9400%" for an imported night — and a model given a
    /// nonsense number reasons about it confidently rather than ignoring it.
    ///
    /// 1.5 rather than 1.0 because a genuine fraction can exceed 1.0 only by floating-point noise, while
    /// a genuine percentage is 30–100 and nowhere near the threshold. Android's two copies of this guard
    /// split at 1.0 instead, which is a pre-existing divergence and not this change's to settle.
    func efficiencyPercentOrDash(_ raw: Double?) -> String {
        guard var e = raw, e > 0 else { return "—" }
        if e > 1.5 { e /= 100 }
        guard e > 0, e <= 1 else { return "—" }
        return "\(Int((e * 100).rounded()))%"
    }

    private func avgOne(_ xs: [Double]) -> String {
        guard !xs.isEmpty else { return "—" }
        return String(format: "%.1f", xs.reduce(0, +) / Double(xs.count))
    }

    private func avgInt(_ xs: [Double]) -> String {
        guard !xs.isEmpty else { return "—" }
        return "\(Int((xs.reduce(0, +) / Double(xs.count)).rounded()))"
    }

    private func avgSleepHours(_ days: [DailyMetric]) -> String {
        let mins = days.compactMap { $0.totalSleepMin }
        guard !mins.isEmpty else { return "—" }
        return String(format: "%.1f", (mins.reduce(0, +) / Double(mins.count)) / 60)
    }

    private func dateString(_ ts: Int) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
}
