import Foundation
import AVFoundation

/// Writes Title/Artist/Album/Artwork back into the audio file itself via a
/// passthrough export (no re-encode) so edits are genuinely embedded, not a
/// sidecar hack. Only MP4/M4A containers support this; other formats are
/// left untouched and the caller should show that editing isn't available.
enum MetadataWriter {
    struct Update {
        var title: String?
        var artist: String?
        var album: String?
        var artwork: Data?
    }

    enum WriterError: LocalizedError {
        case unsupportedFormat
        case exportSessionUnavailable
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat:
                return "Editing embedded metadata is only supported for .mp4/.m4a files."
            case .exportSessionUnavailable:
                return "Could not prepare this file for editing."
            case .exportFailed(let message):
                return "Saving failed: \(message)"
            }
        }
    }

    static func supportsEmbeddedEditing(_ song: Song) -> Bool {
        ["mp4", "m4a"].contains(song.fileURL.pathExtension.lowercased())
    }

    @discardableResult
    static func write(_ update: Update, to song: Song) async throws -> URL {
        guard supportsEmbeddedEditing(song) else { throw WriterError.unsupportedFormat }

        let asset = AVURLAsset(url: song.fileURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw WriterError.exportSessionUnavailable
        }

        let existingMetadata = (try? await asset.load(.metadata)) ?? []
        var replacedKeys = Set<AVMetadataKey>()
        if update.title != nil { replacedKeys.insert(.commonKeyTitle) }
        if update.artist != nil { replacedKeys.insert(.commonKeyArtist) }
        if update.album != nil { replacedKeys.insert(.commonKeyAlbumName) }
        if update.artwork != nil { replacedKeys.insert(.commonKeyArtwork) }

        let artworkToPreserve = update.artwork == nil && !existingMetadata.contains(where: isArtworkItem)
            ? song.artwork
            : nil
        var items = existingMetadata.filter { item in
            guard item.keySpace == .common,
                  let key = item.key as? String,
                  replacedKeys.contains(AVMetadataKey(rawValue: key)) else {
                return true
            }
            return false
        }
        if let title = update.title { items.append(metadataItem(.commonKeyTitle, value: title as NSString)) }
        if let artist = update.artist { items.append(metadataItem(.commonKeyArtist, value: artist as NSString)) }
        if let album = update.album { items.append(metadataItem(.commonKeyAlbumName, value: album as NSString)) }
        if let artwork = update.artwork ?? artworkToPreserve {
            items.append(metadataItem(.commonKeyArtwork, value: artwork as NSData))
        }
        exportSession.metadata = items

        let ext = song.fileURL.pathExtension.lowercased()
        exportSession.outputFileType = ext == "mp4" ? .mp4 : .m4a
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        exportSession.outputURL = tempURL

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    let message = exportSession.error?.localizedDescription ?? "unknown error"
                    continuation.resume(throwing: WriterError.exportFailed(message))
                default:
                    continuation.resume(throwing: WriterError.exportFailed("unexpected export status"))
                }
            }
        }

        let fm = FileManager.default
        let originalURL = song.fileURL
        let backupURL = originalURL.appendingPathExtension("bak")
        try? fm.removeItem(at: backupURL)
        try fm.moveItem(at: originalURL, to: backupURL)
        do {
            try fm.moveItem(at: tempURL, to: originalURL)
            try? fm.removeItem(at: backupURL)
        } catch {
            try? fm.moveItem(at: backupURL, to: originalURL)
            throw error
        }
        return originalURL
    }

    private static func metadataItem(_ key: AVMetadataKey, value: NSCopying & NSObjectProtocol) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.keySpace = .common
        item.key = key.rawValue as NSString
        item.value = value
        return item
    }

    private static func isArtworkItem(_ item: AVMetadataItem) -> Bool {
        item.commonKey == .commonKeyArtwork
    }
}
