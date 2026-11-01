import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
import Speech
#endif

/// K4: On-device speech-to-text wrapper for the Coach composer (iOS only).
///
/// Design contract (see PRD-K4):
/// - **No raw audio egress.** Recognition is requested with `requiresOnDeviceRecognition = true`
///   wherever the locale supports it. If a locale ONLY supports server recognition, voice is
///   **disabled** for that locale rather than falling back to server transcription — server
///   transcription would ship audio off-device, breaking the offline posture.
/// - The microphone button lives in the shared `CoachView` composer; on macOS this type is a
///   no-op (`isSupported` is `false`, all methods are inert) so the shared file keeps compiling.
/// - Only the resulting TEXT ever reaches the provider, via the same channel a typed question
///   already uses. No new network path is introduced.
///
/// Usage from `CoachView`:
/// 1. `voice.isSupported` gates whether the mic button is shown at all.
/// 2. `voice.authorizationStatus` drives the button's enabled / "open Settings" state.
/// 3. `voice.startTranscribing(partial:)` begins a session; `partial` is called on the main
///    actor with the live transcript.
/// 4. `voice.stopTranscribing(completion:)` finalizes and returns the final text.
@MainActor
final class CoachVoiceInput: ObservableObject {

    /// Whether voice input is available on this device + locale at all.
    static var isSupported: Bool {
        #if canImport(UIKit)
        return SFSpeechRecognizer.authorizationStatus() != .restricted
            && SFSpeechRecognizer.self != nil
            && SFSpeechRecognizer(locale: Locale.current) != nil
        #else
        return false
        #endif
    }

    #if canImport(UIKit)
    /// Current Speech framework authorization status, mapped to a simple enum the UI can switch on.
    var authorization: AuthorizationState {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .unavailable
        case .notDetermined: return .notDetermined
        @unknown default: return .unavailable
        }
    }
    #else
    var authorization: AuthorizationState { .unavailable }
    #endif

    /// Whether a recognition session is currently recording.
    @Published private(set) var isRecording: Bool = false

    /// The latest partial transcript (live, while recording).
    @Published var partialTranscript: String = ""

    /// A short human-readable status for the disabled-state tooltip (e.g. "On-device speech not
    /// available for en-GB"). `nil` when voice is fully available.
    @Published var statusMessage: String?

    /// On-device support for the current locale. If `false`, voice is disabled rather than
    /// falling back to server recognition (which would be raw-audio egress).
    private static var localeSupportsOnDevice: Bool {
        #if canImport(UIKit)
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) else { return false }
        return recognizer.supportsOnDeviceRecognition
        #else
        return false
        #endif
    }

    /// True when voice can be used right now: supported, authorized, and locale supports on-device.
    var canUseVoice: Bool {
        guard Self.isSupported, authorization == .authorized, Self.localeSupportsOnDevice else {
            return false
        }
        return true
    }

    /// Request Speech + Microphone authorization. Safe to call repeatedly; the system no-ops if
    /// already decided. `completion` fires on the main actor.
    func requestAuthorization(completion: @escaping (AuthorizationState) -> Void) {
        #if canImport(UIKit)
        // Speech auth first; mic auth piggybacks on the same prompt flow but is a separate grant.
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            Task { @MainActor in
                if speechStatus != .authorized {
                    completion(self.mapSpeech(speechStatus))
                    return
                }
                // Mic permission is requested lazily by AVAudioEngine on iOS — but we ask up front
                // so the user sees one consolidated prompt and the button state is correct before
                // the first tap.
                self.requestMicPermission { micGranted in
                    completion(micGranted ? .authorized : .denied)
                }
            }
        }
        #else
        completion(.unavailable)
        #endif
    }

    /// Begin a recognition session. `partial` is invoked on the main actor with the live transcript
    /// as it streams in. No-op (calls `partial` with "") on macOS / unsupported locales.
    func startTranscribing(partial: @escaping (String) -> Void) {
        #if canImport(UIKit)
        guard canUseVoice else {
            statusMessage = Self.localeSupportsOnDevice
                ? String(localized: "Voice input unavailable. Check microphone permission in Settings.")
                : String(localized: "On-device speech not available for \(Locale.current.identifier).")
            return
        }
        stopTranscribing(completion: { _ in })
        partialTranscript = ""
        statusMessage = nil
        beginSession(partial: partial)
        #else
        partial("")
        #endif
    }

    /// Stop the active session and return the finalized transcript via `completion` (main actor).
    func stopTranscribing(completion: @escaping (String) -> Void) {
        #if canImport(UIKit)
        guard isRecording || audioEngine != nil || recognitionTask != nil else {
            completion(partialTranscript)
            return
        }
        finishSession(completion: completion)
        #else
        completion("")
        #endif
    }

    /// Stop any session without delivering a transcript: the screen went away, the app left the
    /// foreground, or another app took the audio session. Releases the microphone and deactivates
    /// the record session. No-op when nothing is recording, and on macOS.
    func cancelTranscribing() {
        #if canImport(UIKit)
        stopTranscribing(completion: { _ in })
        #endif
    }

    // MARK: - Private (iOS only)

    #if canImport(UIKit)
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    /// Identifies the current session. The recognizer reports on its own queue and can still deliver a
    /// result or an error after its session ended; a late callback from an OLD session used to finish
    /// the NEW one, or write its text into the draft. Callbacks carrying a stale id are dropped.
    private var sessionID = 0

    /// Observers that end a session when the app leaves the foreground or the audio session is
    /// interrupted (a call, Siri, another app recording). Registered once, for the object's lifetime.
    private var lifecycleObservers: [NSObjectProtocol] = []

    private func observeLifecycleIfNeeded() {
        guard lifecycleObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let end: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.cancelTranscribing() }
        }
        lifecycleObservers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                               object: nil, queue: .main, using: end),
            center.addObserver(forName: AVAudioSession.interruptionNotification,
                               object: AVAudioSession.sharedInstance(), queue: .main, using: end),
        ]
    }

    private func mapSpeech(_ status: SFSpeechRecognizerAuthorizationStatus) -> AuthorizationState {
        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .unavailable
        case .notDetermined: return .notDetermined
        @unknown default: return .unavailable
        }
    }

    private func requestMicPermission(completion: @escaping (Bool) -> Void) {
        let session = AVAudioSession.sharedInstance()
        session.requestRecordPermission { granted in
            Task { @MainActor in completion(granted) }
        }
    }

    private func beginSession(partial: @escaping (String) -> Void) {
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) else {
            statusMessage = String(localized: "On-device speech not available for \(Locale.current.identifier).")
            return
        }
        observeLifecycleIfNeeded()
        sessionID += 1
        let session = sessionID

        // The audio session goes active BEFORE the engine reads its input format: the input node
        // reports the format of the route that is active when it is first asked.
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            statusMessage = String(localized: "Couldn't start the microphone: \(error.localizedDescription)")
            finishSession(completion: { _ in })
            return
        }

        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        // `installTap` raises an Objective-C exception, which Swift cannot catch and which ends the
        // app, when the format has no sample rate or no channel. That is what the input reports while
        // another app holds the microphone or the route is changing, so check it first.
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            statusMessage = String(localized: "Couldn't start the microphone. Try again in a moment.")
            finishSession(completion: { _ in })
            return
        }
        self.audioEngine = audioEngine

        let request = SFSpeechAudioBufferRecognitionRequest()
        // K4 hard constraint: on-device ONLY. If the locale doesn't support it, voice is disabled
        // upstream — but we set the flag defensively here too so a regression can't slip audio out.
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.sessionID == session else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.partialTranscript = text
                    partial(text)
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.finishSession(completion: { _ in })
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            statusMessage = String(localized: "Couldn't start the microphone: \(error.localizedDescription)")
            finishSession(completion: { _ in })
        }
    }

    private func finishSession(completion: @escaping (String) -> Void) {
        // Retire the session id first, so a callback already queued for it is ignored.
        sessionID += 1
        if let audioEngine {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            self.audioEngine = nil
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
        let final = partialTranscript
        isRecording = false
        completion(final)
    }
    #endif

    /// Simplified authorization state the UI switches on (decoupled from SFSpeech symbols on macOS).
    enum AuthorizationState {
        case notDetermined
        case authorized
        case denied
        case unavailable
    }
}
