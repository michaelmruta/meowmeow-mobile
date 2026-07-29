import Foundation
import AVFoundation

/// Writes Title/Artist/Album/Artwork back into the audio file itself via a
/// passthrough export (no re-encode) so edits are genuinely embedded, not a
/// sidecar hack. Only MP4/M4A containers support this; other formats are
/// left untouched and the caller should show that editing isn't available.
enum MetadataWriter {
    struct Update {
        var title: String? = nil
        var artist: String? = nil
        var album: String? = nil
        var albumArtist: String? = nil
        var genre: String? = nil
        var trackNumber: Int? = nil
        var year: Int? = nil
        var composer: String? = nil
        var artwork: Data? = nil
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

        // Items are matched for removal by `commonKey` (which native format
        // items carry too, not just the synthesized `.common` keyspace copy)
        // or by `identifier` for fields with no common-keyspace equivalent,
        // so the old value doesn't linger alongside the new one after export.
        var replacedCommonKeys = Set<AVMetadataKey>()
        if update.title != nil { replacedCommonKeys.insert(.commonKeyTitle) }
        if update.artist != nil { replacedCommonKeys.insert(.commonKeyArtist) }
        if update.album != nil { replacedCommonKeys.insert(.commonKeyAlbumName) }
        if update.artwork != nil { replacedCommonKeys.insert(.commonKeyArtwork) }
        if update.year != nil { replacedCommonKeys.insert(.commonKeyCreationDate) }

        var replacedIdentifiers = Set<AVMetadataIdentifier>()
        if update.albumArtist != nil { replacedIdentifiers.insert(.iTunesMetadataAlbumArtist) }
        if update.genre != nil {
            replacedIdentifiers.insert(.iTunesMetadataUserGenre)
            replacedIdentifiers.insert(.iTunesMetadataPredefinedGenre)
        }
        if update.trackNumber != nil { replacedIdentifiers.insert(.iTunesMetadataTrackNumber) }
        if update.composer != nil { replacedIdentifiers.insert(.iTunesMetadataComposer) }

        let artworkToPreserve = update.artwork == nil && !existingMetadata.contains(where: isArtworkItem)
            ? song.artwork
            : nil
        var items = existingMetadata.filter { item in
            if let key = item.commonKey, replacedCommonKeys.contains(key) { return false }
            if let identifier = item.identifier, replacedIdentifiers.contains(identifier) { return false }
            return true
        }
        if let title = update.title { items.append(metadataItem(.commonKeyTitle, value: title as NSString)) }
        if let artist = update.artist { items.append(metadataItem(.commonKeyArtist, value: artist as NSString)) }
        if let album = update.album { items.append(metadataItem(.commonKeyAlbumName, value: album as NSString)) }
        if let albumArtist = update.albumArtist {
            items.append(iTunesMetadataItem(.iTunesMetadataKeyAlbumArtist, value: albumArtist as NSString))
        }
        if let genre = update.genre {
            items.append(iTunesMetadataItem(.iTunesMetadataKeyUserGenre, value: genre as NSString))
        }
        if let trackNumber = update.trackNumber {
            items.append(iTunesMetadataItem(.iTunesMetadataKeyTrackNumber, value: NSNumber(value: trackNumber)))
        }
        if let year = update.year {
            items.append(metadataItem(.commonKeyCreationDate, value: "\(year)" as NSString))
        }
        if let composer = update.composer {
            items.append(iTunesMetadataItem(.iTunesMetadataKeyComposer, value: composer as NSString))
        }
        if let artwork = update.artwork ?? artworkToPreserve {
            items.append(metadataItem(.commonKeyArtwork, value: artwork as NSData))
        }
        exportSession.metadata = items

        let ext = song.fileURL.pathExtension.lowercased()
        let outputFileType: AVFileType = ext == "mp4" ? .mp4 : .m4a
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)

        do {
            try await exportSession.export(to: tempURL, as: outputFileType)
        } catch {
            throw WriterError.exportFailed(error.localizedDescription)
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

    private static func iTunesMetadataItem(_ key: AVMetadataKey, value: NSCopying & NSObjectProtocol) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.keySpace = .iTunes
        item.key = key.rawValue as NSString
        item.value = value
        return item
    }

    private static func isArtworkItem(_ item: AVMetadataItem) -> Bool {
        item.commonKey == .commonKeyArtwork
    }
}
