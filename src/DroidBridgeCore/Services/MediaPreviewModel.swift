import Foundation
import AVFoundation
import Observation

/// Observable model managing AVPlayer lifecycle for audio and video previews.
@Observable
@MainActor
public final class MediaPreviewModel {
    public var player: AVPlayer?
    public var isPlaying: Bool = false
    public var currentTime: Double = 0.0
    public var duration: Double = 0.0
    public var title: String = ""
    public var mediaType: MediaType = .none
    public var isLoaded: Bool = false
    public var errorMessage: String?
    
    private var timeObserverToken: Any?
    private var playerItemStatusObserver: NSKeyValueObservation?
    
    public init() {}
    
    /// Loads a local media URL into the player and prepares playback.
    public func loadMedia(url: URL, title: String, type: MediaType) {
        cleanup()
        
        self.title = title
        self.mediaType = type
        self.errorMessage = nil
        self.isLoaded = false
        self.isPlaying = false
        self.currentTime = 0.0
        self.duration = 0.0
        
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: playerItem)
        self.player = newPlayer
        
        // Observe item readiness and duration
        playerItemStatusObserver = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch item.status {
                case .readyToPlay:
                    self.isLoaded = true
                    let dur = item.duration.seconds
                    if !dur.isNaN && !dur.isInfinite {
                        self.duration = max(0, dur)
                    }
                    self.play()
                case .failed:
                    self.isLoaded = false
                    self.errorMessage = item.error?.localizedDescription ?? "Playback failed: Unsupported codec or corrupt media file."
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }
        
        // Periodic time observer for playback progress
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let secs = time.seconds
                if !secs.isNaN && !secs.isInfinite {
                    self.currentTime = secs
                }
            }
        }
    }
    
    public func play() {
        guard let player = player else { return }
        player.play()
        isPlaying = true
    }
    
    public func pause() {
        guard let player = player else { return }
        player.pause()
        isPlaying = false
    }
    
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    public func seek(to seconds: Double) {
        guard let player = player else { return }
        let clamped = duration > 0 ? max(0, min(seconds, duration)) : max(0, seconds)
        let targetTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
    }
    
    public func cleanup() {
        if let token = timeObserverToken, let p = player {
            p.removeTimeObserver(token)
            timeObserverToken = nil
        }
        playerItemStatusObserver?.invalidate()
        playerItemStatusObserver = nil
        
        player?.pause()
        player = nil
        isPlaying = false
        isLoaded = false
        currentTime = 0.0
        duration = 0.0
    }
    
    isolated deinit {
        // Safe cleanup if not already executed
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
        }
        playerItemStatusObserver?.invalidate()
    }
}
