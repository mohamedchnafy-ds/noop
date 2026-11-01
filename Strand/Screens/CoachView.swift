import SwiftUI
import MarkdownUI
import StrandDesign

/// Coach, the one feature in NOOP that talks to the network.
///
/// It is strictly opt-in and bring-your-own-key: the user pastes their own OpenAI
/// or Anthropic API key (stored in the macOS Keychain by `AICoachEngine`), and only
/// a compact text summary of their metrics plus their question ever leaves the Mac.
/// Nothing is sent until a key is saved and a question asked.
///
/// This screen compiles against `AICoachEngine`'s public API (the macos-core agent's
/// contract): `hasKey`, `provider` / `provider.modelOptions`, `model`, `messages`,
/// `sending`, `errorText`, `setKey(_:)`, `clearKey()`, and `send(_:)`.
struct CoachView: View {
    @EnvironmentObject var coach: AICoachEngine
    /// K8: used by "Save to Journal" — saves the coach advice as a journal entry with the text
    /// in the notes field, so it appears alongside other journal entries in Insights.
    @EnvironmentObject var repo: Repository

    /// Draft text in the composer (the question being typed).
    /// K15: the composer draft is persisted to UserDefaults so it survives an app relaunch.
    /// Restored on first appear, saved on every change. Keyed identically to the Android twin.
    private static let draftKey = "coach.composerDraft"
    @State private var draft: String = UserDefaults.standard.string(forKey: "coach.composerDraft") ?? ""
    /// Pending key text in the setup card (never persisted here, handed to `setKey`).
    @State private var keyDraft: String = ""
    /// The replacement key, typed into the editor a rejection or Update key opens. Separate from
    /// `keyDraft` so the
    /// setup card's own field is untouched, and cleared on save so a secret does not sit in view state
    /// after it has been stored. Twin of the Kotlin `keyFix`.
    @State private var keyFix: String = ""
    @State private var showKeyEditor = false
    /// Whether the model selector is in free-text "Custom…" mode.
    @State private var customModel: Bool = false
    /// The id typed in the "Custom…" field.
    @State private var customModelDraft: String = ""
    @FocusState private var composerFocused: Bool

    /// K2: confirmation gate for the destructive "Delete conversation" menu action.
    @State private var showClearConfirm = false
    /// The conversations history (personal fork), opened from the header's left button.
    @State private var showHistory = false
    /// The rename prompt of the conversation on screen, and the name being typed.
    @State private var showRename = false
    @State private var renameDraft = ""
    /// #2243: the coach settings, presented as a sheet. See `CoachSettingsView` for why a sheet
    /// rather than a push.
    @State private var showSettings = false
    /// "What the coach should know about you" and "What the coach reads" (personal fork), from the menu.
    @State private var showCoachProfile = false
    @State private var showCoachData = false

    // K4: on-device voice input for the composer (iOS only). macOS gets a no-op stub via
    // `#if os(iOS)` guards — the shared file keeps compiling for both targets.
    #if os(iOS)
    @StateObject private var voiceInput = CoachVoiceInput()
    /// The Lift Log session the card's "Start" hands its plan to (iOS only: the Mac has no session).
    @EnvironmentObject private var liftSession: LiftSessionController
    #endif
    /// The reply whose session card is running an action (personal fork, step 6b).
    @State private var sessionBusy: UUID?

    /// Sentinel tag for the "Custom…" entry in the model Picker.
    private let customModelTag = "__custom__"


    var body: some View {
        Group {
            if coach.isConfigured {
                // Personal fork: once connected, the conversation IS the screen — the transcript fills
                // every point between a slim header and the docked composer, and everything else (the
                // provider, the settings, the key, clearing) sits behind the header's one gear button.
                chatScreen
            } else {
                ScreenScaffold(title: "Coach",
                               subtitle: "Ask about your charge, effort, rest and workouts, grounded in your own numbers.",
                               // Liquid finish: the same full-bleed day-of-sky backdrop Today + the other liquid
                               // tabs carry, so Coach sits in one atmosphere. Static + non-interactive; the frosted
                               // setup card below sits on the opaque canvas and stays legible.
                               topBackground: liquidScaffoldSky()) {
                    setupCard
                }
            }
        }
        // Personal fork: the toolbar the macOS app carried (Update key, Clear, Disconnect) is gone. Those
        // actions live in the header's ⋯ menu on every platform, so the iPhone pillar sheet, whose bar
        // is visible, and the Mac never show them twice.
        // #2243: coach settings. `repo` rides along because the scaffold's environment is not
        // inherited by a sheet's own view tree.
        .sheet(isPresented: $showCoachProfile) {
            CoachProfileView().environmentObject(coach).environmentObject(repo)
        }
        .sheet(isPresented: $showCoachData) {
            CoachDataView().environmentObject(coach).environmentObject(repo)
        }
        .sheet(isPresented: $showSettings) {
            CoachSettingsView()
                .environmentObject(coach)
                .environmentObject(repo)
        }
        .sheet(isPresented: $showHistory) {
            CoachHistoryView().environmentObject(coach).environmentObject(repo)
        }
        .confirmationDialog(
            "Delete this conversation?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { coach.clearConversation() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It is removed from this device and from your conversations.")
        }
        .alert("Rename conversation", isPresented: $showRename) {
            TextField("Name", text: $renameDraft)
            Button("Rename") {
                if let id = coach.currentConversationId { coach.renameConversation(id: id, to: renameDraft) }
            }
            Button("Cancel", role: .cancel) {}
        }
        // K2 + K5 ordering matters and every step gates on an EMPTY transcript, so this is ONE `.task`
        // running sequentially (separate `.task`s can interleave at their await points on the same
        // actor): restore whatever the prior launch persisted, THEN surface a brief the scheduled
        // notification already generated (if any). Personal fork: the interactive brief no longer
        // starts on its own; it is the empty screen's "Today's brief" card.
        .task {
            await coach.loadPersistedMessagesIfNeeded()
            coach.retireStaleConversationIfNeeded()
            // Gated on the transcript BEFORE consuming. `consumeStoredBrief()` clears the unconsumed
            // flag, and `surfaceScheduledBrief` then drops the text if a transcript exists, so a brief
            // that arrived on a day with a conversation already open was consumed and thrown away, gone
            // for good. Android checked first and so only ever failed to SHOW it (#2087).
            if coach.messages.isEmpty, let stored = CoachBriefScheduler.consumeStoredBrief() {
                coach.surfaceScheduledBrief(stored)
            }
            CoachBriefScheduler.activateIfEnabled { await coach.generateBrief() }
        }
        // #1862: a question handed over by the Today launcher sheet. Cleared BEFORE sending so a view
        // rebuild mid-flight cannot send it twice, and gated on `isConfigured` so an unconfigured handoff
        // (which the launcher does not produce, but a future caller might) degrades to showing setup
        // rather than a failed request.
        .task(id: coach.pendingPrompt) {
            guard let prompt = coach.pendingPrompt, !prompt.isEmpty else { return }
            coach.pendingPrompt = nil
            guard coach.isConfigured else { return }
            coach.submit(prompt)
        }
        // K15: persist the composer draft so it survives an app relaunch.
        .onChangeCompat(of: draft) { newValue in
            UserDefaults.standard.set(newValue, forKey: Self.draftKey)
        }
        // K14: haptic feedback when a reply arrives (sending goes true → false).
        .onChangeCompat(of: coach.sending) { isSending in
            if !isSending && !coach.messages.isEmpty {
                triggerReplyHaptic()
            }
        }
    }

    // MARK: - Setup (no key yet)

    private var setupCard: some View {
        StrandCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityHidden(true)
                    Text("Connect a provider")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                }

                Text("Coach uses your own API key. Pick a provider, paste a key, and choose a model. Your key is stored securely in the Keychain and never leaves \(Platform.deviceNounPhrase) except as the request you make.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Provider
                VStack(alignment: .leading, spacing: 6) {
                    Text("Provider").strandOverline()
                    Picker("Provider", selection: $coach.provider) {
                        ForEach(AIProvider.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Provider")
                }

                // Server URL (Custom / local LLM only)
                if coach.provider == .custom {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Server URL").strandOverline()
                        TextField("http://localhost:11434/v1", text: $coach.customBaseURL)
                            .textFieldStyle(.plain)
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(StrandPalette.hairline, lineWidth: 1))
                            .disableAutocorrection(true)
                            .accessibilityLabel("Server URL")
                        Text("Any OpenAI-compatible server: Ollama, LM Studio, llama.cpp, or your own gateway. Stays on your network; nothing leaves \(Platform.deviceNounPhrase).")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Key header").strandOverline()
                        Picker("Key header", selection: $coach.customAuthHeader) {
                            ForEach(CustomAIAuthHeader.allCases) { header in
                                Text(header.displayName).tag(header)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Key header")
                        Text("Use Bearer for most local servers; use x-api-key for gateways that require the key in that header.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Model
                modelSelector

                // Key
                VStack(alignment: .leading, spacing: 6) {
                    Text(coach.provider == .custom ? "API key (optional)" : "API key").strandOverline()
                    SecureField(coach.provider == .custom
                                ? "Only if your server requires one"
                                : "Paste your \(coach.provider.displayName) API key", text: $keyDraft)
                        .textFieldStyle(.plain)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(StrandPalette.hairline, lineWidth: 1))
                        .onSubmit { coach.provider == .custom ? connectCustom() : saveKey() }
                        .accessibilityLabel("API key")
                }

                HStack {
                    if coach.provider == .custom {
                        NoopButton("Connect", systemImage: "link", kind: .primary, action: connectCustom)
                            .disabled(coach.customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        NoopButton("Save key", systemImage: "key.fill", kind: .primary, action: saveKey)
                            .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Spacer()
                }

                // Whatever the last attempt from THIS card ran into. The setup card had no error line
                // at all, so every way it can fail before a key is committed failed silently: a Refresh
                // the provider turned away, a Connect to a server that wants auth. The wearer saw a
                // button do nothing. No repair affordance beside it, unlike the chat: the key field is
                // already on screen, which is the whole point of the card.
                if let error = coach.errorText, !error.isEmpty {
                    errorBanner(error)
                }

                Divider().overlay(StrandPalette.hairline)
                privacyFootnote
            }
        }
    }

    /// Model selector: a Picker over `coach.availableModels` with a free-text "Custom…" path and a
    /// "Refresh models" button that fetches the provider's live list.
    private var modelSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Model").strandOverline()
                Spacer()
                Button {
                    Task { await coach.refreshModels() }
                } label: {
                    Label("Refresh models", systemImage: "arrow.clockwise")
                        .font(StrandFont.footnote)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(StrandPalette.accent)
                .disabled(!coach.hasKey)
                .help("Fetch the available models from \(coach.provider.displayName) using your saved key")
                .accessibilityLabel("Refresh models from provider")
            }

            Picker("Model", selection: modelPickerSelection) {
                ForEach(coach.availableModels, id: \.self) { m in
                    Text(m).tag(m)
                }
                Divider()
                Text("Custom…").tag(customModelTag)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityLabel("Model")

            if customModel {
                HStack(spacing: 8) {
                    TextField("Enter a model id", text: $customModelDraft)
                        .textFieldStyle(.plain)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(StrandPalette.hairline, lineWidth: 1))
                        .onSubmit(applyCustomModel)
                        .accessibilityLabel("Custom model id")

                    Button("Use", action: applyCustomModel)
                        .buttonStyle(NoopButtonStyle(.secondary))
                        .disabled(customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Use custom model")
                }
            }
        }
    }

    /// Bridges the model Picker to `coach.model`, with a "Custom…" sentinel that opens the free-text
    /// field instead of selecting a real id.
    private var modelPickerSelection: Binding<String> {
        Binding(
            get: { customModel ? customModelTag : coach.model },
            set: { newValue in
                if newValue == customModelTag {
                    customModel = true
                    if customModelDraft.isEmpty { customModelDraft = coach.model }
                } else {
                    customModel = false
                    coach.model = newValue
                }
            }
        )
    }

    private func applyCustomModel() {
        let trimmed = customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        coach.setCustomModel(trimmed)
        customModel = false
    }

    // MARK: - Connected state

    // MARK: - Connected: the full-screen conversation

    /// The conversation, full height: header, transcript, then the docked input. The transcript is the
    /// only part that scrolls; the composer stays where the thumb is, and the keyboard pushes it up.
    private var chatScreen: some View {
        VStack(spacing: 0) {
            chatHeader
                .padding(.horizontal, chatHPadding)
                .padding(.top, 8)
                .padding(.bottom, 6)
            transcript
            bottomPanel
                .padding(.horizontal, chatHPadding)
                .padding(.top, 6)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                StrandPalette.surfaceBase
                liquidScaffoldSky()
            }
            .ignoresSafeArea()
        }
    }

    private var chatHPadding: CGFloat {
        #if os(iOS)
        NoopMetrics.screenHPadding
        #else
        28
        #endif
    }

    /// The header (personal fork, Coach mockups 1 and 8): the history on the left, the conversation's
    /// title and when it was last written, a new conversation, and the ⋯ menu that holds everything else.
    private var chatHeader: some View {
        HStack(spacing: 8) {
            headerButton("clock.arrow.circlepath", label: "Conversations") { showHistory = true }
            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                if coach.sending {
                    StatePill("Thinking", tone: .accent, pulsing: true)
                } else {
                    Text(headerSubtitle)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            headerButton("square.and.pencil", label: "New conversation") { coach.startNewConversation() }
                .disabled(coach.sending || coach.messages.isEmpty)
            optionsMenu
        }
    }

    /// The conversation's title, or "New conversation" before its first save.
    private var headerTitle: String {
        let title = coach.currentConversationRow?.title ?? ""
        return title.isEmpty ? String(localized: "New conversation") : title
    }

    /// "Coach · today 09:12" for a saved conversation, "Coach" for a new one.
    private var headerSubtitle: String {
        guard let row = coach.currentConversationRow else { return String(localized: "Coach") }
        let date = Date(timeIntervalSince1970: TimeInterval(row.updatedAt))
        let time = AppClock.hourMinuteFormatter().string(from: date)
        switch CoachHistory.dayDistance(from: row.updatedAt, to: Date()) {
        case ..<1: return String(localized: "Coach · today \(time)")
        case 1: return String(localized: "Coach · yesterday \(time)")
        default: return String(localized: "Coach · \(date.formatted(.dateTime.day().month(.abbreviated)))")
        }
    }

    private func headerButton(_ symbol: String, label: LocalizedStringKey,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CoachHeaderIcon(symbol: symbol)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    /// Everything that is not the conversation, behind ONE button (Coach mockup 8): the conversation
    /// on screen, what the coach knows and reads, its settings, and the connection.
    ///
    /// #2206: on iOS the connection actions cannot live in the toolbar. `RootTabView.tab(...)` wraps
    /// every primary tab root in a NavigationStack and applies `.toolbar(.hidden, for: .navigationBar)`,
    /// so Clear conversation and Disconnect placed there rendered nowhere — and Disconnect was the only
    /// route back to the setup card, leaving a key that could be set once and never changed. Personal
    /// fork: the Mac now uses this menu too, so no platform shows these actions twice. A menu also puts
    /// two taps in front of a destructive action.
    ///
    /// Worth knowing before changing `disconnect()`: neither `hasKey` nor `isConfigured` is published,
    /// since `hasKey` reads the Keychain on each evaluation. The setup card reappears because
    /// `disconnect()` ALSO assigns the published `messages`, which is what re-evaluates the body.
    private var optionsMenu: some View {
        Menu {
            if let row = coach.currentConversationRow {
                Section {
                    Button {
                        renameDraft = row.title
                        showRename = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button {
                        coach.setConversationPinned(id: row.id, pinned: !row.pinned)
                    } label: {
                        Label(row.pinned ? "Unpin" : "Pin", systemImage: row.pinned ? "pin.slash" : "pin")
                    }
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("Delete conversation", systemImage: "trash")
                    }
                }
            }
            Section {
                Button {
                    showCoachProfile = true
                } label: {
                    Label("What the coach should know about you", systemImage: "person.crop.circle")
                }
                Button {
                    showCoachData = true
                } label: {
                    Label("What the coach reads", systemImage: "eye")
                }
                Button {
                    showSettings = true
                } label: {
                    Label("Coach settings", systemImage: "slider.horizontal.3")
                }
            }
            Section("\(coach.provider.displayName) · \(coach.model)") {
                Button {
                    toggleKeyEditor()
                } label: {
                    Label("Update key", systemImage: "key.fill")
                }
                Button(role: .destructive) {
                    coach.disconnect()
                    keyDraft = ""
                } label: {
                    Label("Disconnect", systemImage: "power")
                }
            }
        } label: {
            CoachHeaderIcon(symbol: "ellipsis")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "More options"))
    }

    /// What sits under the transcript: a problem that needs the user (an error, a rejected key), the
    /// composer, and a token warning only when a question would be large enough to matter. Personal
    /// fork: the suggestions moved into the transcript (the empty screen, and the follow-ups under the
    /// last answer), so no row scrolls sideways here and swipes between tabs stay what they were.
    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = coach.errorText, !error.isEmpty {
                errorBanner(error)
            }
            if coach.keyRejected || showKeyEditor { keyRepairPanel }
            composer
            // K12: the estimate, now only when it is worth a warning.
            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let tokens = coach.estimatedTokens(forDraft: draft), tokens > 8000 {
                tokenEstimateBar(tokens)
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Lazy so off-screen bubbles aren't all resident/laid-out at once; with the
                // `maxStoredMessages` cap the transcript is already bounded, this keeps render cost flat.
                LazyVStack(alignment: .leading, spacing: 14) {
                    if coach.messages.isEmpty && !coach.sending {
                        CoachEmptyState(briefAvailable: coach.dataConsent,
                                        providerName: coach.provider.displayName,
                                        onBrief: { coach.beginBriefIfNeeded() },
                                        onAsk: { send($0) },
                                        onShowData: { showCoachData = true })
                    }
                    ForEach(coach.messages) { message in
                        bubble(message).id(message.id)
                    }
                    if coach.sending {
                        typingIndicator.id("typing")
                    } else if showFollowUps {
                        followUps
                    }
                }
                .padding(.horizontal, chatHPadding)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // #697 parity: this screen builds its OWN ScrollView rather than going through
            // ScreenScaffold, so it never inherited the scaffold's horizontal-bounce suppression and
            // could still rubber-band left-right on a purely vertical scroll. Same modifier, same
            // guard. `.basedOnSize` permits horizontal bounce only when content genuinely overflows
            // the width, so nothing that is meant to scroll sideways is affected. (#1532 follow-up)
            #if os(iOS)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { scrollToEnd(proxy, animated: false) }
            .onChangeCompat(of: coach.messages.count) { _ in
                scrollToEnd(proxy)
            }
            .onChangeCompat(of: coach.sending) { _ in
                scrollToEnd(proxy)
            }
            .onChangeCompat(of: composerFocused) { focused in
                if focused { scrollToEnd(proxy) }
            }
        }
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.surfaceBase)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(StrandPalette.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(maxWidth: 520, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You said: \(message.text)")
        case .assistant:
            // Personal fork (Coach mockup 2): the answer reads full width, with no card around it, under
            // a small "Coach" mark, and its actions sit in a row underneath. LLM replies arrive as
            // Markdown (bold, lists, headings, tables), rendered with the chat-sized Strand theme; user
            // bubbles stay verbatim `Text` so typed `*`/`#` never turn into surprise formatting.
            // The words and the stored extras (`CoachReplyMeta`) are read apart: the block is never
            // rendered, copied or shared as part of the answer. A reply still empty (the first chunk has
            // not arrived) shows nothing; the typing indicator under it says the coach is working.
            let reply = CoachReplyMeta.split(message.text)
            let streaming = coach.sending && message.id == coach.messages.last?.id
            let session = reply.meta?.session
            if !reply.body.isEmpty || session != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text("Coach").font(StrandFont.overline).tracking(1)
                    } icon: {
                        Image(systemName: "sparkles").font(StrandFont.caption)
                    }
                    .foregroundStyle(StrandPalette.textSecondary)
                    .accessibilityHidden(true)
                    if !reply.body.isEmpty {
                        Markdown(reply.body)
                            .markdownTheme(.strand)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 680, alignment: .leading)
                            .accessibilityLabel("Coach said: \(reply.body)")
                    }
                    if let session {
                        sessionCard(session, messageId: message.id)
                            .frame(maxWidth: 520, alignment: .leading)
                            .padding(.top, 2)
                    }
                    if let consulted = reply.meta?.consulted, !consulted.isEmpty {
                        consultedLine(consulted)
                    }
                    if !streaming { replyActions(message, text: shareText(reply.body, session: session)) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The session card of a reply, with its two actions.
    private func sessionCard(_ session: CoachSessionProposal, messageId: UUID) -> some View {
        let start: (() -> Void)?
        #if os(iOS)
        start = { startSession(messageId: messageId) }
        #else
        start = nil
        #endif
        return CoachSessionCard(proposal: session, system: unitSystem, busy: sessionBusy == messageId,
                                onAdd: { addSession(messageId: messageId) }, onStart: start)
    }

    private var unitSystem: UnitSystem {
        UnitSystem(rawValue: UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric
    }

    /// What Copy, Share and the Journal take from a reply: its words, then its session written out.
    private func shareText(_ body: String, session: CoachSessionProposal?) -> String {
        guard let session else { return body }
        let system = unitSystem
        let card = session.text(
            weight: { LiftFormat.trim(LiftFormat.display(fromKilograms: $0, system: system)) + " "
                + LiftFormat.weightUnit(system) },
            rest: { seconds, after in
                let rest = CoachSessionProposal.restText(seconds)
                if let after { return String(localized: "rest \(rest) after \(after)") }
                return String(localized: "rest \(rest)")
            })
        let words = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return words.isEmpty ? card : words + "\n\n" + card
    }

    private func addSession(messageId: UUID) {
        guard sessionBusy == nil else { return }
        sessionBusy = messageId
        Task {
            await coach.addSessionToLiftLog(messageId: messageId)
            sessionBusy = nil
        }
    }

    #if os(iOS)
    /// Start the card's session in the Lift Log, as a program start does; a session already running is
    /// brought up instead of being replaced.
    private func startSession(messageId: UUID) {
        guard sessionBusy == nil else { return }
        guard !liftSession.isActive else {
            liftSession.isPresented = true
            return
        }
        sessionBusy = messageId
        Task {
            if let start = await coach.liftPlan(messageId: messageId), !start.plan.isEmpty, !liftSession.isActive {
                liftSession.start(plan: start.plan, programId: start.programId, programName: start.name)
            }
            sessionBusy = nil
        }
    }
    #endif

    /// What the coach looked at with its tools, under the reply ("What the coach reads": it goes and
    /// fetches the detail itself, then shows it under its answer).
    private func consultedLine(_ consulted: [String]) -> some View {
        let list = consulted.joined(separator: " · ")
        return Label {
            Text("Looked at: \(list)")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "magnifyingglass")
        }
        .font(StrandFont.caption)
        .foregroundStyle(StrandPalette.textTertiary)
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    /// Copy, save to the Journal, redo (the last answer to a question only) and share. `text` is the
    /// reply's words, without its stored extras.
    private func replyActions(_ message: ChatMessage, text: String) -> some View {
        HStack(spacing: 0) {
            replyAction("doc.on.doc", label: "Copy") { copy(text) }
            replyAction("square.and.pencil", label: "Save to Journal") { saveAdvice(text) }
            if message.id == coach.messages.last?.id, !coach.sending,
               coach.messages.contains(where: { $0.role == .user }) {
                replyAction("arrow.clockwise", label: "Redo") { coach.regenerateLastReply() }
            }
            ShareLink(item: text) {
                Image(systemName: "square.and.arrow.up")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .frame(width: 44, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Share"))
        }
        .padding(.leading, -12)
    }

    private func replyAction(_ symbol: String, label: LocalizedStringKey,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    private var typingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).tint(StrandPalette.accent)
            Group {
                if let looking = coach.toolActivity {
                    Text("Looking at \(looking)…")
                } else {
                    Text("Coach is thinking…")
                }
            }
            .font(StrandFont.subhead)
            .foregroundStyle(StrandPalette.textSecondary)
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frostedCardSurface(tint: StrandPalette.chargeColor, cornerRadius: 16)
        .frame(maxWidth: 320, alignment: .leading)
        .accessibilityLabel("Coach is thinking")
    }

    private func errorBanner(_ message: String) -> some View {
        StrandCard(padding: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(StrandPalette.statusCritical)
                    .accessibilityHidden(true)
                Text(message)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.statusCritical)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }

    /// The inline replacement-key editor, shown after a rejection or an Update key action.
    ///
    /// Saving goes through `setKey`, which replaces the stored key and leaves the transcript alone. The
    /// existing route was the Disconnect button, which also wipes the conversation and un-commits a
    /// custom provider: far more than correcting a typo asks for, and named for an outcome the wearer
    /// is trying to avoid. Twin of the Kotlin editor in `CoachChat`.
    private var keyRepairPanel: some View {
        StrandCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                if coach.keyRejected {
                    Text("Paste the corrected key. Your conversation is kept.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SecureField("Paste your \(coach.provider.displayName) API key", text: $keyFix)
                    .textFieldStyle(.plain)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(StrandPalette.hairline, lineWidth: 1))
                    .onSubmit(saveRepairedKey)
                    .accessibilityLabel(coach.keyRejected ? Text("Corrected API key") : Text("API key"))
                HStack {
                    NoopButton("Update key", systemImage: "key.fill", kind: .primary, action: saveRepairedKey)
                        .disabled(keyFix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                    if showKeyEditor && !coach.keyRejected {
                        Button("Cancel") { toggleKeyEditor() }
                    }
                }
            }
        }
    }

    /// Store the corrected key and drop it from view state. `setKey` clears the error and the rejection
    /// flag, which is what closes this panel.
    private func saveRepairedKey() {
        let trimmed = keyFix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        coach.setKey(trimmed)
        guard coach.errorText == nil else { return }
        keyFix = ""
        showKeyEditor = false
    }

    private func toggleKeyEditor() {
        showKeyEditor.toggle()
        if !showKeyEditor { keyFix = "" }
    }

    /// K7: True when follow-ups should show under the last message: it is an answer and no reply is
    /// on its way.
    private var showFollowUps: Bool {
        guard let last = coach.messages.last, !coach.sending else { return false }
        return last.role == .assistant
    }

    /// K7, personal fork (Coach mockup 2): two or three follow-ups under the last answer, wrapped rather
    /// than scrolled sideways. They follow the theme of the conversation's first question when it is one
    /// of the suggested ones (`CoachPrompts`).
    private var followUps: some View {
        let first = coach.messages.first(where: { $0.role == .user })?.text
        let lastHasSession = coach.messages.last.map { CoachReplyMeta.split($0.text).meta?.session != nil } ?? false
        let startsWithBrief = coach.messages.first.map {
            $0.role == .assistant && $0.text.hasPrefix(AICoachEngine.briefPrefix)
        } ?? false
        let prompts = CoachPrompts.followUps(forFirstQuestion: first, lastReplyHasSession: lastHasSession,
                                             startsWithBrief: startsWithBrief)
        return CoachChipFlow(spacing: 8) {
            ForEach(prompts, id: \.self) { prompt in
                Button {
                    send(prompt)
                } label: {
                    Text(prompt)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 40)
                        .background(StrandPalette.surfaceInset, in: Capsule(style: .continuous))
                        .overlay(Capsule(style: .continuous).strokeBorder(StrandPalette.hairline, lineWidth: 1))
                }
                .buttonStyle(LiquidPressStyle())
                .accessibilityLabel("Follow-up prompt: \(prompt)")
            }
        }
        .padding(.top, 2)
    }

    /// K12: A subtle token estimate shown below the composer when the draft is non-empty.
    /// Uses the ~4 chars/token heuristic — an estimate only, not an exact tokenizer count.
    private func tokenEstimateBar(_ tokens: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "speedometer")
                .font(.system(size: 10))
                .foregroundStyle(StrandPalette.textTertiary)
            Text("~\(tokens) tokens")
                .font(StrandFont.captionNumber)
                .foregroundStyle(StrandPalette.textTertiary)
            if tokens > 8000 {
                Text("· may exceed small context windows")
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .padding(.top, 2)
    }

    /// The input capsule (Coach mockup 1): the field, the microphone, and a round Send that appears once
    /// there is something to send. While a reply streams it becomes Stop, which keeps the text received
    /// so far. The photo button of the mockups comes with photos.
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 4) {
            TextField("Ask Coach…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1...5)
                .focused($composerFocused)
                .padding(.leading, 14)
                .padding(.vertical, 12)
                .onSubmit { send(draft) }
                .accessibilityLabel("Question")

            // K4: on-device voice input (iOS only). macOS compiles this section out entirely.
            #if os(iOS)
            micButton
            #endif

            if coach.sending || hasDraft || !micAvailable {
                Button {
                    if coach.sending { coach.stopReply() } else { send(draft) }
                } label: {
                    Image(systemName: coach.sending ? "stop.fill" : "arrow.up")
                        .font(StrandFont.headline)
                        .frame(width: 40, height: 40)
                        .foregroundStyle(StrandPalette.goldDeepText)
                        .background(StrandPalette.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!coach.sending && !hasDraft)
                .padding(2)
                .accessibilityLabel(coach.sending ? Text("Stop") : Text("Send"))
            }
        }
        .padding(2)
        .background(NoopPanelSurface(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .strokeBorder(composerFocused ? StrandPalette.focusRing : StrandPalette.hairline, lineWidth: 1))
    }

    private var hasDraft: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Whether the capsule has a microphone, so a Send button is needed even with an empty field.
    private var micAvailable: Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }

    // MARK: - K4: Voice input (iOS only)

    #if os(iOS)
    /// Mic button: starts/stops on-device speech recognition. Disabled when the locale lacks
    /// on-device support or permission is denied; tapping when permission is not yet determined
    /// triggers the system prompt.
    private var micButton: some View {
        Button {
            toggleVoice()
        } label: {
            Group {
                if voiceInput.isRecording {
                    Image(systemName: "stop.circle.fill")
                        .font(StrandFont.title2)
                        .foregroundStyle(StrandPalette.statusCritical)
                } else {
                    Image(systemName: "mic")
                        .font(StrandFont.headline)
                        .foregroundStyle(canUseVoice ? StrandPalette.textSecondary : StrandPalette.textTertiary)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!micButtonEnabled)
        .help(voiceInput.statusMessage ?? "Ask out loud")
        .accessibilityLabel(voiceInput.isRecording ? "Stop voice input" : "Voice input")
        .accessibilityHint(voiceInput.statusMessage ?? "Transcribes your question on-device")
        .task {
            // Pre-check on appear so the button reflects the right state without a tap.
            if voiceInput.authorization == .notDetermined {
                voiceInput.requestAuthorization { _ in }
            }
        }
        // Leaving the screen mid-dictation releases the microphone and the record audio session,
        // which otherwise stayed active (and kept other audio ducked) after a tab switch. What was
        // already transcribed is in the draft.
        .onDisappear { voiceInput.cancelTranscribing() }
    }

    /// Whether the mic button is tappable: not while sending, and only if voice is either
    /// already usable or permission hasn't been asked yet (first tap triggers the prompt).
    private var canUseVoice: Bool { voiceInput.canUseVoice }
    private var micButtonEnabled: Bool {
        !coach.sending && (canUseVoice || voiceInput.authorization == .notDetermined)
    }

    private func toggleVoice() {
        if voiceInput.isRecording {
            voiceInput.stopTranscribing { finalText in
                let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    // Append to the draft (not replace) so a user can speak into existing text.
                    draft = draft.isEmpty ? trimmed : "\(draft) \(trimmed)"
                }
            }
        } else {
            // First tap with undetermined permission triggers the system prompt; if granted,
            // start transcribing immediately on the next tap. If already authorized, start now.
            if voiceInput.authorization == .notDetermined {
                voiceInput.requestAuthorization { state in
                    if state == .authorized {
                        voiceInput.startTranscribing { partial in
                            draft = partial
                        }
                    }
                }
            } else {
                voiceInput.startTranscribing { partial in
                    draft = partial
                }
            }
        }
    }
    #endif

    private var privacyFootnote: some View {
        Label {
            Text(coach.provider == .custom
                 ? "Coach talks only to the server URL you set. Point it at a local model (Ollama, LM Studio, llama.cpp) to keep everything on your own machine. Nothing is sent until you ask."
                 : "This is the only feature that leaves \(Platform.deviceNounPhrase). It sends a summary of your metrics to \(coach.provider.displayName) using your own key. Nothing is sent until you ask.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.shield")
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    private func saveKey() {
        let trimmed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        coach.setKey(trimmed)
        keyDraft = ""
    }

    /// Commit the Custom (local) provider: save an optional key, then connect on the entered URL.
    private func connectCustom() {
        let trimmed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            coach.setKey(trimmed)
            keyDraft = ""
        }
        coach.connectCustom()
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !coach.sending else { return }
        draft = ""
        composerFocused = false
        coach.submit(trimmed)
    }

    /// K14: Trigger a subtle haptic when the Coach reply arrives. On iOS, a light impact feedback.
    /// macOS doesn't have an equivalent simple API, so it's a no-op there.
    private func triggerReplyHaptic() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }

    /// K8: Save a coach reply to the journal as a note, so it appears alongside other journal
    /// entries in Insights and can be reviewed later. Uses the existing journal API with a
    /// fixed question ("Coach advice") and the reply text in the notes field.
    private func saveAdvice(_ text: String) {
        let day = Repository.localDayKey(Date())
        Task {
            await repo.saveJournalAnswer(
                day: day,
                question: "Coach advice",
                answeredYes: true,
                notes: text
            )
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let scroll = {
            if coach.sending {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = coach.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
        if animated { withAnimation(StrandMotion.fade) { scroll() } } else { scroll() }
    }
}
