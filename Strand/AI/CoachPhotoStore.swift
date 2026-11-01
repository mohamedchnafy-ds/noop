import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The photos sent to the Coach (personal fork, Nutrition 4c): kept on this device only, reduced, and
/// deleted with their conversation.
///
/// A photo picked in the composer is first reduced to a JPEG of at most `maxPixelSize` on its long edge
/// and staged in the temporary folder, so a photo that is never sent is cleaned up by the system. On
/// send it moves to `Application Support/CoachPhotos`, outside the SQLite database, so a `.noopbak`
/// backup never carries it. A question refers to its photos by file name (`CoachReplyMeta.photos`).
enum CoachPhotoStore {

    /// Long edge of a stored photo, in pixels: the size the Messages API works at.
    static let maxPixelSize = 1568
    static let jpegQuality = 0.8
    /// Most photos sent with one question.
    static let maxPerQuestion = 4

    private static var keptFolder: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("CoachPhotos", isDirectory: true)
    }

    private static var stagedFolder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CoachPhotosStaged", isDirectory: true)
    }

    /// A photo's JPEG reduced to `maxPixelSize`, upright, or nil when the data is not an image.
    static func reducedJPEG(_ data: Data, maxPixelSize: Int = CoachPhotoStore.maxPixelSize) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out as CFMutableData, UTType.jpeg.identifier as CFString,
                                                                 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }

    /// Reduce a picked photo and stage it; its file name, or nil when it is not an image.
    static func stagePhoto(_ data: Data) -> String? {
        guard let jpeg = reducedJPEG(data) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            try FileManager.default.createDirectory(at: stagedFolder, withIntermediateDirectories: true)
            try jpeg.write(to: stagedFolder.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    /// Move staged photos to the kept folder, as their question is sent. Returns the names kept.
    static func keepPhotos(_ names: [String]) -> [String] {
        guard let folder = keptFolder else { return [] }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var kept: [String] = []
        for name in names where isPhotoName(name) {
            let from = stagedFolder.appendingPathComponent(name)
            let to = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: to.path) {
                kept.append(name)
            } else if (try? FileManager.default.moveItem(at: from, to: to)) != nil {
                kept.append(name)
            }
        }
        return kept
    }

    /// Where a photo is, kept or staged; nil when neither has it.
    static func photoURL(for name: String) -> URL? {
        guard isPhotoName(name) else { return nil }
        if let kept = keptFolder?.appendingPathComponent(name), FileManager.default.fileExists(atPath: kept.path) {
            return kept
        }
        let staged = stagedFolder.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: staged.path) ? staged : nil
    }

    /// A photo's JPEG, nil when it is gone.
    static func jpegData(for name: String) -> Data? {
        photoURL(for: name).flatMap { try? Data(contentsOf: $0) }
    }

    /// Delete photos, kept or staged (a deleted conversation, a photo taken off the composer).
    static func removePhotos(_ names: [String]) {
        for name in names where isPhotoName(name) {
            if let kept = keptFolder?.appendingPathComponent(name) { try? FileManager.default.removeItem(at: kept) }
            try? FileManager.default.removeItem(at: stagedFolder.appendingPathComponent(name))
        }
    }

    /// Only the names this store makes: a UUID and ".jpg", nothing that could reach another folder.
    static func isPhotoName(_ name: String) -> Bool {
        name.hasSuffix(".jpg") && UUID(uuidString: String(name.dropLast(4))) != nil
    }
}
