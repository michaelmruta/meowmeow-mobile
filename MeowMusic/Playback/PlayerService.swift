import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import Observation

enum RepeatMode {
    case off, all, one

    mutating func cycle() {
        switch self {
        case .off: self = .all
        case .all: self = .one
        case .one: self = .off
        }
    }
}

enum PlaybackMode {
    case off, shuffle, repeatOne, repeatAll
}

/// App-wide playback engine. Owns the `AVPlayer` (single instance, item swapped
/// per song), the current queue (Favorites/Browse/Playlist all hand it a queue
/// + starting song), shuffle and repeat state, and Control Center / lock-screen
/// integration.
///
/// Uses `AVPlayer` rather than `AVAudioPlayer`: the latter can fail to open
/// AAC/M4A files in the iOS Simulator (missing/unreliable AAC decoder
/// component there) even for files that decode fine everywhere else.
/// `AVPlayer` doesn't hit that failure mode.
@MainActor
@Observable
final class PlayerService {
    private(set) var currentSong: Song?
    private(set) var queue: [Song] = []
    private(set) var queueIndex: Int = 0
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    var shuffle: Bool = false {
        didSet {
            guard oldValue != shuffle, !queue.isEmpty else { return }
            rebuildShuffleOrder(startingAt: queueIndex)
        }
    }
    var repeatMode: RepeatMode = .off

    private let player = AVPlayer()
    private var itemStatusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var timeObserverToken: Any?
    private var shuffledOrder: [Int] = []
    private var playOrderPosition: Int = 0

    init() {
        configureAudioSession()
        configureRemoteCommands()
        configureEndOfItemObserver()
        configureTimeObserver()
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("MeowMusic: audio session error \(error)")
        }
    }

    func play(song: Song, in newQueue: [Song]) {
        queue = newQueue
        queueIndex = newQueue.firstIndex(of: song) ?? 0
        if shuffle {
            rebuildShuffleOrder(startingAt: queueIndex)
        }
        startPlayback(song: song)
    }

    private func startPlayback(song: Song) {
        let item = AVPlayerItem(url: song.fileURL)
        observeStatus(of: item)
        player.replaceCurrentItem(with: item)

        currentSong = song
        currentTime = 0
        duration = 0

        resume()
    }

    private func observeStatus(of item: AVPlayerItem) {
        itemStatusObservation?.invalidate()
        itemStatusObservation = item.observe(\.status, options: [.new]) { observedItem, _ in
            guard observedItem.status == .failed else { return }
            let message = observedItem.error?.localizedDescription ?? "unknown error"
            Task { @MainActor in
                print("MeowMusic: playback error \(message)")
            }
        }
    }

    func resume() {
        player.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    var playbackMode: PlaybackMode {
        if shuffle { return .shuffle }
        switch repeatMode {
        case .off: return .off
        case .all: return .repeatAll
        case .one: return .repeatOne
        }
    }

    func cyclePlaybackMode() {
        switch playbackMode {
        case .off:
            shuffle = true
            repeatMode = .off
        case .shuffle:
            shuffle = false
            repeatMode = .one
        case .repeatOne:
            shuffle = false
            repeatMode = .all
        case .repeatAll:
            shuffle = false
            repeatMode = .off
        }
    }

    func seek(to time: TimeInterval) {
        let clamped = max(0, min(time, duration))
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlayingInfo()
    }

    func next() {
        advance(forward: true, userInitiated: true)
    }

    func previous() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        advance(forward: false, userInitiated: true)
    }

    func isFavoriteQueueEmpty() -> Bool { queue.isEmpty }

    /// Patches the in-memory current song after a metadata edit, without
    /// restarting playback, so the Player/lock-screen reflect the new tags.
    func updateCurrentSongMetadata(title: String, artist: String, album: String) {
        guard var song = currentSong else { return }
        song.title = title
        song.artist = artist
        song.album = album
        currentSong = song
        if let index = queue.firstIndex(where: { $0.id == song.id }) {
            queue[index] = song
        }
        updateNowPlayingInfo()
    }

    private func advance(forward: Bool, userInitiated: Bool) {
        guard !queue.isEmpty else { return }

        if shuffle {
            var position = playOrderPosition + (forward ? 1 : -1)
            if position < 0 {
                position = userInitiated ? 0 : shuffledOrder.count - 1
            }
            if position >= shuffledOrder.count {
                guard repeatMode == .all || userInitiated else { pause(); return }
                position = 0
                if !userInitiated { shuffledOrder.shuffle() }
            }
            playOrderPosition = position
            queueIndex = shuffledOrder[position]
        } else {
            var index = queueIndex + (forward ? 1 : -1)
            if index < 0 {
                index = userInitiated ? 0 : queue.count - 1
            }
            if index >= queue.count {
                guard repeatMode == .all || userInitiated else { pause(); return }
                index = 0
            }
            queueIndex = index
        }
        startPlayback(song: queue[queueIndex])
    }

    private func rebuildShuffleOrder(startingAt index: Int) {
        var order = Array(queue.indices)
        order.removeAll { $0 == index }
        order.shuffle()
        shuffledOrder = [index] + order
        playOrderPosition = 0
    }

    private func configureTimeObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.tick(time: time)
            }
        }
    }

    private func tick(time: CMTime) {
        currentTime = time.seconds.isFinite ? time.seconds : 0
        if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite {
            duration = itemDuration
        }
    }

    private func configureEndOfItemObserver() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let endedItem = note.object as? AVPlayerItem
            Task { @MainActor in
                guard let self, let endedItem, endedItem === self.player.currentItem else { return }
                self.handlePlaybackFinished()
            }
        }
    }

    private func handlePlaybackFinished() {
        if repeatMode == .one {
            seek(to: 0)
            resume()
        } else {
            advance(forward: true, userInitiated: false)
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.resume(); return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause(); return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause(); return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.next(); return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous(); return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: event.positionTime)
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyAlbumTitle: song.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let artworkData = song.artwork, let image = UIImage(data: artworkData) {
            let artwork = Self.makeNowPlayingArtwork(from: image)
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// MediaPlayer invokes the artwork request handler on its private access
    /// queue. Building the handler in this nonisolated context prevents it from
    /// inheriting `PlayerService`'s main-actor isolation.
    private nonisolated static func makeNowPlayingArtwork(from image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
