import SwiftUI
import PhotosUI
import StrandDesign
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// Personal fork, Nutrition 4c: the photos of the Coach screen. The composer's attachments before a
// question is sent, the photos above a question once sent, and the iPhone camera.

/// What the composer opens when the Coach screen next shows (the Photo and Dictate tiles of "Add a meal").
enum CoachComposerAction: String, Equatable {
    case photoLibrary, camera, dictate
}

/// A meal of the Coach's card open in the editor.
struct CoachMealEditTarget: Identifiable {
    let messageId: UUID
    let day: Date
    let target: NutritionEditorTarget
    var id: String { target.id }
}

/// The photo library and, on iPhone, the camera, presented from the composer.
struct CoachPhotoPickers: ViewModifier {
    @Binding var showLibrary: Bool
    @Binding var picked: [PhotosPickerItem]
    @Binding var showCamera: Bool
    /// How many more photos the question can take.
    let room: Int
    let onPicked: ([PhotosPickerItem]) -> Void
    let onCamera: (Data) -> Void

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $showLibrary, selection: $picked, maxSelectionCount: room, matching: .images)
            .onChangeCompat(of: picked) { onPicked($0) }
            #if os(iOS)
            .fullScreenCover(isPresented: $showCamera) {
                CoachCameraPicker(onPhoto: onCamera).ignoresSafeArea()
            }
            #endif
    }
}

/// One photo of `CoachPhotoStore`, read off the main thread and drawn square.
struct CoachPhotoThumbnail: View {
    let name: String
    var side: CGFloat = 56

    @State private var image: Image?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(StrandPalette.surfaceInset)
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(StrandPalette.hairline, lineWidth: 1))
        .accessibilityLabel(Text("Photo"))
        .task(id: name) {
            let photo = name
            let data = await Task.detached(priority: .utility) { CoachPhotoStore.jpegData(for: photo) }.value
            guard let data else { return }
            #if canImport(UIKit)
            if let ui = UIImage(data: data) { image = Image(uiImage: ui) }
            #else
            if let ns = NSImage(data: data) { image = Image(nsImage: ns) }
            #endif
        }
    }
}

/// The photos attached to the question being written, each with a button to take it off.
struct CoachAttachmentStrip: View {
    let names: [String]
    let onRemove: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(names, id: \.self) { name in
                    CoachPhotoThumbnail(name: name, side: 56)
                        .overlay(alignment: .topTrailing) {
                            Button { onRemove(name) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(StrandPalette.textPrimary, StrandPalette.surfaceOverlay)
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .offset(x: 6, y: -6)
                            .accessibilityLabel(Text("Remove the photo"))
                        }
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 12)
        }
    }
}

#if os(iOS)
/// The iPhone camera, for one photo of a meal. Hands back the photo's JPEG, or nothing when cancelled.
struct CoachCameraPicker: UIViewControllerRepresentable {
    let onPhoto: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CoachCameraPicker

        init(_ parent: CoachCameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
                parent.onPhoto(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif
