import Foundation
import AVFoundation

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let time: TimeInterval?
    let text: String
}

/// Lyrics come from (in priority order): a `.lrc` sidecar (timed), a `.txt`
/// sidecar (plain), or embedded iTunes-style `©lyr` metadata (plain, unsynced).
enum LyricsService {
    static func lrcURL(for song: Song) -> URL {
        song.fileURL.deletingPathExtension().appendingPathExtension("lrc")
    }

    static func txtURL(for song: Song) -> URL {
        song.fileURL.deletingPathExtension().appendingPathExtension("txt")
    }

    static func isTimed(_ lines: [LyricLine]) -> Bool {
        lines.contains { $0.time != nil }
    }

    static func load(for song: Song) async -> [LyricLine] {
        let fm = FileManager.default

        let lrc = lrcURL(for: song)
        if fm.fileExists(atPath: lrc.path), let content = try? String(contentsOf: lrc, encoding: .utf8) {
            let parsed = parseLRC(content)
            if !parsed.isEmpty { return parsed }
        }

        let txt = txtURL(for: song)
        if fm.fileExists(atPath: txt.path), let content = try? String(contentsOf: txt, encoding: .utf8) {
            return parsedOrPlainLines(content)
        }

        if let embedded = await embeddedLyrics(for: song), !embedded.isEmpty {
            return parsedOrPlainLines(embedded)
        }

        return []
    }

    /// Existing raw text for the editor: prefers the `.lrc` sidecar verbatim
    /// (so timestamps round-trip), then `.txt`, then embedded lyrics.
    static func loadRawText(for song: Song) async -> String {
        let fm = FileManager.default
        let lrc = lrcURL(for: song)
        if fm.fileExists(atPath: lrc.path), let content = try? String(contentsOf: lrc, encoding: .utf8) {
            return content
        }
        let txt = txtURL(for: song)
        if fm.fileExists(atPath: txt.path), let content = try? String(contentsOf: txt, encoding: .utf8) {
            return content
        }
        return await embeddedLyrics(for: song) ?? ""
    }

    static func save(_ text: String, for song: Song) {
        let hasTimeTags = text.range(of: #"\[\d{2}:\d{2}"#, options: .regularExpression) != nil
        let url = hasTimeTags ? lrcURL(for: song) : txtURL(for: song)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func embeddedLyrics(for song: Song) async -> String? {
        let asset = AVURLAsset(url: song.fileURL)
        guard let allMetadata = try? await asset.load(.metadata) else { return nil }
        let items = AVMetadataItem.metadataItems(from: allMetadata, filteredByIdentifier: .iTunesMetadataLyrics)
        guard let item = items.first else { return nil }
        return try? await item.load(.stringValue)
    }

    /// Parses `[mm:ss.xx]lyric text` lines. A line may carry multiple time tags.
    /// Also preserves blank lines without timestamps to maintain verse structure.
    static func parseLRC(_ content: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let tagPattern = #"\[(\d{2}):(\d{2})(?:\.(\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: tagPattern) else { return [] }
        
        let allLines = content.components(separatedBy: .newlines)
        var hasAnyTimestamp = false
        
        // First pass: check if this is actually an LRC file (has at least one timestamp)
        for rawLine in allLines {
            let fullRange = NSRange(rawLine.startIndex..., in: rawLine)
            let matches = regex.matches(in: rawLine, range: fullRange)
            if !matches.isEmpty {
                hasAnyTimestamp = true
                break
            }
        }
        
        // If no timestamps at all, this isn't an LRC file
        guard hasAnyTimestamp else { return [] }

        // Second pass: parse all lines, preserving blank lines
        for rawLine in allLines {
            let fullRange = NSRange(rawLine.startIndex..., in: rawLine)
            let matches = regex.matches(in: rawLine, range: fullRange)
            
            // If line has no timestamp tags
            if matches.isEmpty {
                // Preserve blank lines (empty or whitespace-only)
                let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    lines.append(LyricLine(time: nil, text: ""))
                }
                // Skip non-blank lines without timestamps (metadata like [ar:Artist])
                continue
            }

            let text = regex.stringByReplacingMatches(in: rawLine, range: fullRange, withTemplate: "")
                .trimmingCharacters(in: .whitespaces)
            // Allow empty text for blank lines with timestamps (preserves verse breaks)

            for match in matches {
                guard let mmRange = Range(match.range(at: 1), in: rawLine),
                      let ssRange = Range(match.range(at: 2), in: rawLine),
                      let mm = Int(rawLine[mmRange]), let ss = Int(rawLine[ssRange]) else { continue }
                var frac: Double = 0
                if match.range(at: 3).location != NSNotFound, let fracRange = Range(match.range(at: 3), in: rawLine) {
                    frac = Double("0.\(rawLine[fracRange])") ?? 0
                }
                let time = TimeInterval(mm * 60 + ss) + frac
                lines.append(LyricLine(time: time, text: text))
            }
        }
        
        // Don't sort! Keep lines in the order they appeared in the file
        // This preserves the structure with blank lines in their correct positions
        return lines
    }

    static func plainLines(_ content: String) -> [LyricLine] {
        content
            .components(separatedBy: .newlines)
            .map { LyricLine(time: nil, text: $0) }
    }

    private static func parsedOrPlainLines(_ content: String) -> [LyricLine] {
        let parsed = parseLRC(content)
        return parsed.isEmpty ? plainLines(content) : parsed
    }
}
