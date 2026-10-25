import UniformTypeIdentifiers

/// Chooses which representation of a photo library item to load.
///
/// Kept free of UIKit, AppKit and Flutter so it can be unit tested on its own.
@available(iOS 14.0, macOS 11.0, *)
enum MediaRepresentation {
    /// Whether `type` is an image or a video.
    static func isMedia(_ type: UTType) -> Bool {
        type.conforms(to: .image) || type.conforms(to: .movie)
    }

    /// The image or video representation to load from an item's
    /// `registeredTypeIdentifiers`, or `nil` if it has none.
    ///
    /// A Live Photo registers its `.pvt` bundle type first, which is neither,
    /// so this picks its still image instead of the whole bundle with the
    /// paired video.
    ///
    /// The photo picker transcodes images to JPEG, and may list JPEG before
    /// the original format, as it does for a HEIC Live Photo. So unless
    /// `preferringCompatible` is set, an image prefers any other image
    /// representation over JPEG, which then is the original.
    static func mediaType(
        in registeredTypeIdentifiers: [String],
        preferringCompatible: Bool = false
    ) -> UTType? {
        let media = registeredTypeIdentifiers.compactMap { UTType($0) }.filter(isMedia)
        guard let first = media.first else {
            return nil
        }
        if preferringCompatible || !first.conforms(to: .image) {
            return first
        }
        return media.first { $0.conforms(to: .image) && $0 != .jpeg } ?? first
    }

    /// The type identifier to load an item with: its image or video
    /// representation, or any representation if it has neither.
    static func typeIdentifier(
        for registeredTypeIdentifiers: [String],
        preferringCompatible: Bool = false
    ) -> String {
        (mediaType(in: registeredTypeIdentifiers, preferringCompatible: preferringCompatible)
            ?? .item).identifier
    }
}
