#if os(iOS)
import SwiftUI
import AVFoundation
import UIKit
import StrandDesign
import WhoopStore

/// The barcode scanner (personal fork, Nutrition 4d, mockups 7 to 9), opened from the Barcode tile of
/// "Add a meal".
///
/// A product the journal already holds (`BarcodeCatalog`) is shown at once, offline, with its portion
/// to add. A barcode never seen asks for a photo of the nutrition label: the photo goes to the Coach
/// with the barcode (`coach.submit`, Anthropic only), which answers with a product card to check and
/// add. No product database is queried.
struct NutritionBarcodeScanner: View {
    /// The day the product is added to.
    let day: Date
    /// The Coach is on, connected, and reads photos (Anthropic).
    let canReadLabel: Bool
    /// "Enter by hand": the scanner closes, then the editor opens.
    let onManual: () -> Void
    /// The label's photo went to the Coach: the scanner closes, then the Coach opens.
    let onLabelSent: () -> Void

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var coach: AICoachEngine
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case looking
        /// A barcode was read; the journal is being searched.
        case reading(String)
        case unknown(String)
        case known(BarcodeProduct)
    }

    @State private var phase: Phase = .looking
    @State private var grams: Double = 100
    @State private var torchOn = false
    @State private var showLabelCamera = false
    /// The label photo taken, staged until the camera has closed.
    @State private var labelPhoto: String?
    @State private var saving = false
    @State private var cameraAccess = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        ZStack(alignment: .bottom) {
            cameraLayer
                .ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
            }
            panel
        }
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
        .task { await askCameraAccessIfNeeded() }
        .fullScreenCover(isPresented: $showLabelCamera, onDismiss: sendLabelIfTaken) {
            CoachCameraPicker { data in
                labelPhoto = CoachPhotoStore.stagePhoto(data)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Parts

    @ViewBuilder private var cameraLayer: some View {
        if cameraAccess == .authorized {
            BarcodeCameraView(active: phase == .looking && !showLabelCamera, torchOn: torchOn) { code in
                found(code)
            }
        } else {
            VStack {
                Group {
                    if cameraAccess == .notDetermined {
                        Text("Waiting for camera access…")
                    } else {
                        Text("Camera access is off for NOOP. Allow it in Settings, or enter the product by hand.")
                    }
                }
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, NoopMetrics.space8)
                    .padding(.top, 140)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var topBar: some View {
        HStack {
            scannerRoundButton(symbol: "xmark", label: "Close the scanner") { dismiss() }
            Spacer(minLength: NoopMetrics.space2)
            Text(statusText)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textPrimary)
                .padding(.horizontal, NoopMetrics.space3)
                .padding(.vertical, 6)
                .background(StrandPalette.surfaceInset.opacity(0.85), in: Capsule())
            Spacer(minLength: NoopMetrics.space2)
            if cameraAccess == .authorized, phase == .looking {
                scannerRoundButton(symbol: torchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                                   label: torchOn ? "Turn the light off" : "Turn the light on") {
                    torchOn.toggle()
                }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, NoopMetrics.screenPadding)
        .padding(.top, NoopMetrics.space2)
    }

    private var statusText: LocalizedStringKey {
        switch phase {
        case .looking: return "Looking for a barcode"
        case .reading, .unknown: return "Barcode read"
        case .known: return "Product recognised · no network"
        }
    }

    private func scannerRoundButton(symbol: String, label: LocalizedStringKey,
                                    action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: 44, height: 44)
                .background(StrandPalette.surfaceInset, in: Circle())
                .overlay(Circle().strokeBorder(StrandPalette.hairlineStrong, lineWidth: NoopMetrics.hairlineWidth))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    @ViewBuilder private var panel: some View {
        switch phase {
        case .looking, .reading:
            BarcodeLookingPanel(onManual: onManual)
        case .unknown(let code):
            BarcodeUnknownPanel(barcode: code, canReadLabel: canReadLabel,
                                onPhoto: { showLabelCamera = true }, onManual: onManual)
        case .known(let product):
            BarcodeKnownPanel(product: product, grams: $grams, saving: saving,
                              onReread: canReadLabel ? { showLabelCamera = true } : nil,
                              onAdd: { addProduct(product) })
        }
    }

    // MARK: Actions

    private var currentBarcode: String? {
        switch phase {
        case .looking: return nil
        case .reading(let code), .unknown(let code): return code
        case .known(let product): return product.barcode
        }
    }

    private func askCameraAccessIfNeeded() async {
        guard cameraAccess == .notDetermined else { return }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        cameraAccess = granted ? .authorized : .denied
    }

    /// A barcode in front of the camera: look it up in the journal, on the device.
    private func found(_ raw: String) {
        guard phase == .looking, let code = BarcodeCatalog.normalizedBarcode(raw) else { return }
        phase = .reading(code)
        torchOn = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task {
            let product: BarcodeProduct?
            if let store = await repo.storeHandle() {
                product = await BarcodeCatalog.productInJournal(store, barcode: code)
            } else {
                product = nil
            }
            guard phase == .reading(code) else { return }
            if let product {
                grams = BarcodeCatalog.startingGrams(product)
                phase = .known(product)
            } else {
                phase = .unknown(code)
            }
        }
    }

    /// The label photo, once the camera has closed: to the Coach, in a new conversation.
    private func sendLabelIfTaken() {
        guard let photo = labelPhoto, let code = currentBarcode else { return }
        labelPhoto = nil
        coach.startNewConversation()
        coach.submit(String(localized: "Read the label of this product (barcode \(code))"),
                     photos: [photo], labelBarcode: code)
        onLabelSent()
    }

    /// "Add to journal" for a product already known: its values for 100 g × the portion.
    private func addProduct(_ product: BarcodeProduct) {
        guard !saving else { return }
        saving = true
        let portion = grams
        Task {
            defer { saving = false }
            guard let store = await repo.storeHandle() else { return }
            let line = MealJournal.measuredMealLine(name: product.name, grams: portion, estimated: false,
                                                    per100: product.per100,
                                                    foodRef: BarcodeCatalog.productRef(product.barcode))
            let saved = try? await MealJournal.saveMealEntry(store, name: product.name, origin: .barcode,
                                                             eatenAt: NutritionMealEditor.defaultTime(on: day),
                                                             lines: [line])
            if saved != nil {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            }
        }
    }
}

/// The back camera reading EAN-13, EAN-8 and UPC-E barcodes, running only while `active`.
struct BarcodeCameraView: UIViewControllerRepresentable {
    let active: Bool
    let torchOn: Bool
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeCameraController {
        let controller = BarcodeCameraController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ controller: BarcodeCameraController, context: Context) {
        controller.onCode = onCode
        controller.applyCameraState(active: active, torchOn: torchOn && active)
    }

    static func dismantleUIViewController(_ controller: BarcodeCameraController, coordinator: ()) {
        controller.applyCameraState(active: false, torchOn: false)
    }
}

/// The capture session behind `BarcodeCameraView`. Configured and started on its own queue, as
/// AVFoundation asks; barcodes are delivered on the main queue.
final class BarcodeCameraController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "noop.barcode.session")
    private var preview: AVCaptureVideoPreviewLayer?
    private var camera: AVCaptureDevice?
    private var configured = false
    private var wantsRunning = false
    private var lastState: (active: Bool, torch: Bool)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        preview = layer
        sessionQueue.async { [weak self] in
            self?.configureSession()
            self?.applyRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    /// Start or stop reading and set the light; repeated values change nothing.
    func applyCameraState(active: Bool, torchOn: Bool) {
        if let last = lastState, last.active == active, last.torch == torchOn { return }
        lastState = (active, torchOn)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.wantsRunning = active
            self.applyRunning()
            self.applyTorch(torchOn)
        }
    }

    private func configureSession() {
        guard !configured,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        let wanted: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce]
        output.metadataObjectTypes = wanted.filter { output.availableMetadataObjectTypes.contains($0) }
        camera = device
        configured = true
    }

    private func applyRunning() {
        guard configured else { return }
        if wantsRunning, !session.isRunning { session.startRunning() }
        if !wantsRunning, session.isRunning { session.stopRunning() }
    }

    private func applyTorch(_ on: Bool) {
        guard let camera, camera.hasTorch, (try? camera.lockForConfiguration()) != nil else { return }
        camera.torchMode = on && session.isRunning ? .on : .off
        camera.unlockForConfiguration()
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let code = metadataObjects.lazy
            .compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first else { return }
        onCode?(code)
    }
}
#endif
