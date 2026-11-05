import SwiftUI
import PhotosUI
import StrandDesign
import WhoopStore

// MARK: - Dictate or photograph a meal (personal fork, Nutrition)
//
// The Dictate and Photo tiles of "Add a meal": say what was eaten (transcribed on the iPhone, and editable)
// or photograph it, then one request finds the foods (`AICoachEngine.estimateMeal`). The proposal opens in
// the meal editor, where each quantity can change and a food can be removed or added, and only "Add to
// journal" saves it. No Coach conversation is created.

/// What the capture sheet starts with.
enum NutritionCaptureMode: String, Identifiable {
    case voice, photo
    var id: String { rawValue }
}

/// The capture sheet's content, without its state: pure, so the render test draws each phase.
struct NutritionCaptureBody: View {
    enum Phase: Equatable {
        case editing
        case working
        case problem(String)
    }

    let mode: NutritionCaptureMode
    @Binding var text: String
    var photos: [String] = []
    var phase: Phase = .editing
    var isListening = false
    /// The microphone can be used (on-device recognition, permission not refused).
    var canListen = true
    var onMic: () -> Void = {}
    /// Nil when the device has no camera.
    var onCamera: (() -> Void)? = nil
    var onLibrary: () -> Void = {}
    var onRemovePhoto: (String) -> Void = { _ in }

    private var working: Bool { phase == .working }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            (mode == .voice
                 ? Text("Say what you ate, with the quantities if you know them: “150 g of rice, a chicken breast and an apple”.")
                 : Text("Photograph your plate. You can add a detail below: quantities, sauce, what is hidden."))
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if mode == .photo { photoSection }
            textSection
            if mode == .voice { micButton }
            status
            Label {
                Text("Sent with your Anthropic key, like the Coach. Nothing is saved before “Add to journal”.")
            } icon: {
                Image(systemName: "lock")
            }
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(photos, id: \.self) { name in
                            CoachPhotoThumbnail(name: name, side: 84)
                                .overlay(alignment: .topTrailing) {
                                    Button { onRemovePhoto(name) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 20))
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(StrandPalette.textPrimary, StrandPalette.surfaceOverlay)
                                            .frame(width: 32, height: 32)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 6, y: -6)
                                    .accessibilityLabel(Text("Remove the photo"))
                                    .disabled(working)
                                }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            HStack(spacing: 8) {
                if let onCamera {
                    captureButton("Camera", systemImage: "camera", action: onCamera)
                }
                captureButton("Photo library", systemImage: "photo.on.rectangle", action: onLibrary)
            }
            .disabled(working || photos.count >= CoachPhotoStore.maxPerQuestion)
        }
    }

    private func captureButton(_ title: LocalizedStringKey, systemImage: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(StrandPalette.surfaceOverlay, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(StrandPalette.hairlineStrong, lineWidth: NoopMetrics.hairlineWidth))
        }
        .buttonStyle(.plain)
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            (mode == .voice ? Text("What you ate") : Text("A detail (optional)"))
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
            Group {
                if isListening || working {
                    // While listening or finding the foods, the text as plain text: not editable meanwhile.
                    Text(verbatim: text.isEmpty ? "…" : text)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                } else {
                    TextField("", text: $text, prompt: Text("150 g of rice, a chicken breast…"), axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .font(StrandFont.body)
            .foregroundStyle(StrandPalette.textPrimary)
            .padding(12)
            .frame(minHeight: mode == .voice ? 110 : 64, alignment: .topLeading)
            .background(StrandPalette.surfaceBase, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isListening ? StrandPalette.statusCritical.opacity(0.6) : StrandPalette.hairline,
                              lineWidth: isListening ? 1.5 : NoopMetrics.hairlineWidth))
        }
    }

    private var micButton: some View {
        HStack(spacing: 12) {
            Button(action: onMic) {
                Image(systemName: isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isListening ? StrandPalette.textPrimary : StrandPalette.surfaceBase)
                    .frame(width: 64, height: 64)
                    .background(isListening ? StrandPalette.statusCritical : StrandPalette.textPrimary, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(working || !canListen)
            .opacity(canListen ? 1 : 0.4)
            .accessibilityLabel(isListening ? Text("Stop voice input") : Text("Voice input"))
            micCaption
                .font(StrandFont.subhead)
                .foregroundStyle(isListening ? StrandPalette.textPrimary : StrandPalette.textSecondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var micCaption: Text {
        if isListening { return Text("Listening… tap to stop") }
        return canListen ? Text("Tap to speak") : Text("Dictation is off on this iPhone")
    }

    @ViewBuilder
    private var status: some View {
        switch phase {
        case .editing:
            EmptyView()
        case .working:
            HStack(spacing: 10) {
                #if os(iOS)
                ProgressView()
                #else
                Image(systemName: "sparkles").foregroundStyle(StrandPalette.textSecondary)
                #endif
                Text("Looking for the foods…")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            // Fork chantier 12: a sweep of light while the Coach estimates.
            .noopShimmer(true)
        case .problem(let message):
            Text(verbatim: message)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.statusWarning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The sheet: the transcript or the photos, then "Find the foods". Hands the proposal back and closes.
struct NutritionMealCaptureSheet: View {
    let mode: NutritionCaptureMode
    let onProposal: (CoachMealProposal) -> Void

    @EnvironmentObject private var coach: AICoachEngine
    @Environment(\.dismiss) private var dismiss

    #if os(iOS)
    @StateObject private var voice = CoachVoiceInput()
    #endif
    @State private var text = ""
    @State private var photos: [String] = []
    @State private var picked: [PhotosPickerItem] = []
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var phase: NutritionCaptureBody.Phase = .editing
    @State private var request: Task<Void, Never>?

    private var canFind: Bool {
        phase != .working && !isListening
            && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !photos.isEmpty)
    }

    private var isListening: Bool {
        #if os(iOS)
        return voice.isRecording
        #else
        return false
        #endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                NutritionCaptureBody(
                    mode: mode, text: $text, photos: photos, phase: phase, isListening: isListening,
                    canListen: canListen, onMic: toggleMic, onCamera: cameraAction,
                    onLibrary: { showLibrary = true }, onRemovePhoto: removePhoto)
                    .padding(.horizontal, NoopMetrics.screenHPadding)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(StrandPalette.surfaceRaised.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                NoopButton("Find the foods", systemImage: "sparkles", kind: .primary, fullWidth: true) { find() }
                    .disabled(!canFind)
                    .opacity(canFind ? 1 : 0.5)
                    .padding(.horizontal, NoopMetrics.screenHPadding)
                    .padding(.bottom, NoopMetrics.space2)
            }
            .navigationTitle(mode == .voice ? Text("Dictate a meal") : Text("Photo of a meal"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .photosPicker(isPresented: $showLibrary, selection: $picked,
                      maxSelectionCount: max(1, CoachPhotoStore.maxPerQuestion - photos.count), matching: .images)
        .onChangeCompat(of: picked) { addPicked($0) }
        #if os(iOS)
        .fullScreenCover(isPresented: $showCamera) {
            CoachCameraPicker(onPhoto: addPhoto).ignoresSafeArea()
        }
        .presentationDragIndicator(.visible)
        #endif
        .task { await start() }
        .onDisappear {
            request?.cancel()
            #if os(iOS)
            voice.cancelTranscribing()
            #endif
            // The photos only served the request: the journal keeps the foods, never the pictures.
            CoachPhotoStore.removePhotos(photos)
        }
    }

    // MARK: Starting

    /// Voice starts listening at once; Photo opens the camera (the library on a device without one).
    private func start() async {
        try? await Task.sleep(nanoseconds: 400_000_000)
        switch mode {
        case .voice:
            if !isListening { toggleMic() }
        case .photo:
            if photos.isEmpty {
                if let cameraAction { cameraAction() } else { showLibrary = true }
            }
        }
    }

    // MARK: Voice

    private var canListen: Bool {
        #if os(iOS)
        return voice.canUseVoice || voice.authorization == .notDetermined
        #else
        return false
        #endif
    }

    private func toggleMic() {
        #if os(iOS)
        if voice.isRecording {
            voice.stopTranscribing { final in
                let said = final.trimmingCharacters(in: .whitespacesAndNewlines)
                if !said.isEmpty { text = said }
            }
            return
        }
        let before = text
        func listen() {
            voice.startTranscribing { partial in
                text = before.isEmpty ? partial : before + " " + partial
            }
        }
        if voice.authorization == .notDetermined {
            voice.requestAuthorization { state in if state == .authorized { listen() } }
        } else {
            listen()
        }
        #endif
    }

    // MARK: Photos

    private var cameraAction: (() -> Void)? {
        #if os(iOS)
        return CoachCameraPicker.isAvailable ? { showCamera = true } : nil
        #else
        return nil
        #endif
    }

    private func addPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        picked = []
        Task {
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                addPhoto(data)
            }
        }
    }

    private func addPhoto(_ data: Data) {
        guard photos.count < CoachPhotoStore.maxPerQuestion, let name = CoachPhotoStore.stagePhoto(data) else { return }
        photos.append(name)
        if phase != .working { phase = .editing }
    }

    private func removePhoto(_ name: String) {
        photos.removeAll { $0 == name }
        CoachPhotoStore.removePhotos([name])
    }

    // MARK: Finding the foods

    private func find() {
        guard canFind else { return }
        phase = .working
        let said = text
        let shown = photos
        let origin: MealOrigin = shown.isEmpty ? .voice : .photo
        request = Task {
            let outcome = await coach.estimateMeal(text: said, photos: shown, origin: origin)
            guard !Task.isCancelled else { return }
            switch outcome {
            case .proposal(let proposal):
                onProposal(proposal)
                dismiss()
            case .noMeal(let message):
                phase = .problem(message)
            case .failure(let message):
                phase = message.isEmpty ? .editing : .problem(message)
            }
        }
    }
}

/// "Add a food" in a weighed meal: the Ciqual table, searched on the device; a tap adds the food at 100 g.
struct NutritionFoodSearchSheet: View {
    let onPick: (CiqualFood) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [CiqualFood] = []
    @FocusState private var focused: Bool

    /// Most foods listed for one search.
    static let resultLimit = 25

    /// The food's name in the app's language: French unless the app runs in another language.
    static func displayName(_ food: CiqualFood, locale: Locale = .current) -> String {
        locale.language.languageCode?.identifier == "fr" || food.nameEn.isEmpty ? food.nameFr : food.nameEn
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(results, id: \.code) { food in
                    Button {
                        onPick(food)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: Self.displayName(food))
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textPrimary)
                                .lineLimit(2)
                            Text(verbatim: NutritionFormat.per100Line(food.per100))
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(StrandPalette.surfaceRaised)
                }
                Text("Food values: \(CiqualTable.attribution)")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .listRowBackground(StrandPalette.surfaceRaised)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(StrandPalette.surfaceRaised.ignoresSafeArea())
            .safeAreaInset(edge: .top) {
                TextField("", text: $query, prompt: Text("Search Ciqual: rice, chicken…"))
                    .focused($focused)
                    .font(StrandFont.body)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(StrandPalette.surfaceBase, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(StrandPalette.hairline, lineWidth: NoopMetrics.hairlineWidth))
                    .padding(.horizontal, NoopMetrics.screenHPadding)
                    .padding(.vertical, NoopMetrics.space2)
                    .background(StrandPalette.surfaceRaised)
            }
            .navigationTitle(Text("Add a food"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task(id: query) {
            let text = query
            let limit = Self.resultLimit
            // A short pause, so the table is searched once the typing settles.
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let found = await Task.detached(priority: .userInitiated) {
                CiqualTable.search(text, limit: limit)
            }.value
            if !Task.isCancelled { results = found }
        }
        .onAppear { focused = true }
    }
}
