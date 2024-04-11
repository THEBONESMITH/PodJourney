//
//  MediaPlayer.swift
//  PodJourney
//
//  Created by . . on 28/03/2024.
//

import Foundation
import AVFoundation

extension MediaPlayer {
    var isPlaying: Bool {
        return player.rate != 0
    }
    
    func togglePlayPause() async {
            // Using isPlaying to check if the player is currently playing
            if isPlaying {
                pause()
            } else {
                manualPlay()
            }
        }
    
    private func handleUndefinedOrUninitializedState() {
        print("Player is in an undefined or uninitialized state. Checking for media URL to start new playback.")
        if let url = currentMediaURL {
            print("Found media URL. Starting playback for new episode.")
            playNewEpisode(url: url, autoPlay: true) // Assuming immediate playback is desired
        } else {
            print("No episode URL available to start playback.")
        }
    }
}

// Add this extension to your project
extension AVPlayer {
    var isPlaying: Bool {
        return rate != 0 && error == nil
    }
}
    
@MainActor
protocol MediaPlayerDelegate: AnyObject {
    func mediaPlayerDidStartPlayback()
    func resetPlaybackProgress() async
    func mediaPlayerDidChangeState(isPlaying: Bool) async
    func updateTimeDisplay(currentTime: String, remainingTime: String)
    func playbackProgressDidChange(to progress: Double) async
    func mediaPlayerRequiresTimeFormat(seconds: Double) -> String
    func mediaPlayerPlaybackStateDidChange(isPlaying: Bool)
    func mediaPlayerDidPause()
    func mediaPlayerProgressDidUpdate(to progress: Double)  
    // Add other necessary methods here
}

class MediaPlayer: NSObject {
    var player: AVPlayer = AVPlayer()
    var currentMediaURL: URL?
    weak var delegate: MediaPlayerDelegate?
    var currentEpisode: Episode?
    var isEpisodeLoaded: Bool = false
    var currentlyPlayingEpisode: Episode?
    var shouldAutoPlay = false
    var userDidRequestPlayback: Bool = false
    var currentState: MediaPlayerState? {
        didSet {
            currentState?.mediaPlayer = self
            notifyDelegateOfStateChange()
        }
    }
    private var isUpdatingPlaybackProgress = true
    private var playerItemStatusObserver: NSKeyValueObservation?
    private var playerTimeControlStatusObserver: NSKeyValueObservation?
    private var hasAddedObserver: Bool = false
    private var timeObserverToken: Any?
    
    override init() {
        super.init()
        setupPlayer()
        player.addObserver(self, forKeyPath: "status", options: [.new, .old], context: nil)
        addPeriodicTimeObserver()
        setupObservers()
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status" {
            if let playerItem = object as? AVPlayerItem {
                switch playerItem.status {
                case .readyToPlay:
                    // Player item is ready. You might choose to play() here or update UI.
                    break
                case .failed:
                    // Handle failure
                    break
                case .unknown:
                    // Handle unknown state
                    break
                @unknown default:
                    break
                }
            }
        }
    }
    
    func notifyPlaybackStateChanged() {
        Task {
            await delegate?.mediaPlayerDidChangeState(isPlaying: self.player.isPlaying)
        }
    }
    
    func stop() {
            // Pause the player
            player.pause()

            // Optionally, seek to the beginning of the current item if you want to reset its playback position
            player.seek(to: CMTime.zero)

            // Reset or clear the current player item if needed
            player.replaceCurrentItem(with: nil)

            // Notify the delegate or update any relevant properties to reflect the change in playback state
            DispatchQueue.main.async {
                Task {
                        await self.delegate?.mediaPlayerDidChangeState(isPlaying: false)
                    }

                    print("Playback stopped and media player reset.")
                }
        }
    
    func setupPlayer() {
        print("setupPlayer called")
        player = AVPlayer()
        
        // Continue setup...
    }
    
    func skipForward(seconds: Double) {
        let currentTime = player.currentTime() // 'player' is non-optional, so direct access is fine
        let newTime = CMTimeAdd(currentTime, CMTimeMakeWithSeconds(seconds, preferredTimescale: 600))

        player.seek(to: newTime) { [weak self] _ in
            Task { [weak self] in
                guard let self = self else { return }
                // Now `self` is safely unwrapped for use within this block
                let progress = self.calculateCurrentProgress() // Calculate the progress
                await self.delegate?.playbackProgressDidChange(to: progress)
                // Assuming 'calculateCurrentProgress()' calculates the progress based on the player's current time and total duration.
                await self.delegate?.playbackProgressDidChange(to: progress)
            }
        }
    }

    func skipBackward(seconds: Double) {
        let currentTime = player.currentTime()
        var newTime = CMTimeSubtract(currentTime, CMTimeMakeWithSeconds(seconds, preferredTimescale: 600))
        if CMTimeGetSeconds(newTime) < 0 {
            newTime = CMTimeMake(value: 0, timescale: 1)
        }
        player.seek(to: newTime) { [weak self] _ in
            Task { [weak self] in
                guard let self = self else { return }
                let progress = self.calculateCurrentProgress()
                await self.delegate?.playbackProgressDidChange(to: progress)
            }
        }
    }
    
    func calculateCurrentProgress() -> Double {
        guard let currentItem = player.currentItem, !currentItem.duration.isIndefinite else {
            return 0.0
        }
        let currentTimeSeconds = CMTimeGetSeconds(player.currentTime())
        let durationSeconds = CMTimeGetSeconds(currentItem.duration)
        return durationSeconds > 0 ? currentTimeSeconds / durationSeconds : 0.0
    }
    
    private func setupObservers() {
            // Setup observers within the init or appropriate method

            playerTimeControlStatusObserver = player.observe(\.timeControlStatus, options: [.new, .old]) { [weak self] player, change in
                guard let self = self else { return }
                
                if player.timeControlStatus == .playing {
                    // Use `self` directly here since it's now strongly captured within the guard statement
                    Task {
                        // Swift 5.5+ allows for structured concurrency. Ensure delegate exists and call on the main thread if updating UI
                        await self.delegate?.mediaPlayerDidChangeState(isPlaying: true)
                    }
                }
            }
        }
    
    func addPeriodicTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        if let existingToken = timeObserverToken {
            player.removeTimeObserver(existingToken)
            timeObserverToken = nil
        }

        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: DispatchQueue.main) { [weak self] time in
            guard let self = self,
                  self.player.rate > 0, // Confirm player is actively playing
                  let currentItem = self.player.currentItem,
                  currentItem.status == .readyToPlay else { return }

            // The player is playing, and the AVPlayerItem is ready.
            let currentTime = CMTimeGetSeconds(time)
            let duration = CMTimeGetSeconds(currentItem.duration)
            if duration > 0 {
                let progress = currentTime / duration
                Task {
                    await self.delegate?.playbackProgressDidChange(to: progress)
                }
            }
        }
    }
    
    private func notifyDelegateOfStateChange() {
            // Assuming `isPlaying` returns true if the player is playing
            let isPlaying = player.rate != 0
            Task {
                await delegate?.mediaPlayerDidChangeState(isPlaying: isPlaying)
            }
        }
    
    func playNewEpisode(url: URL?, autoPlay: Bool) {
        guard let playURL = url ?? currentMediaURL else {
            print("MediaPlayer play action attempted without a valid URL.")
            return
        }

        let playerItem = AVPlayerItem(url: playURL)
        self.player.replaceCurrentItem(with: playerItem)
        self.currentMediaURL = playURL
        print("MediaPlayer: Loading new episode for playback.")

        if autoPlay {
            self.player.play()
            print("MediaPlayer play invoked. Starting playback due to user action.")
        } else {
            print("AutoPlay is disabled. Episode loaded, waiting for user action to play.")
        }
    }
    
    func pause() {
            guard player.isPlaying else {
                print("Playback is already paused.")
                return
            }

            player.pause()
            print("Playback paused manually.")
            notifyPlaybackStateChanged()
        }
    
    func play(url: URL? = nil) {
        if let url = url {
            // Prepare the new episode without auto-playing
            prepareNewEpisode(url: url, autoPlay: false) // This method needs to prepare the episode without starting playback
        } else {
            // No URL provided, check if we're in a state that allows resuming playback
            resumeCurrentEpisodePlayback()
        }
    }
    
    private func prepareNewEpisode(url: URL, autoPlay: Bool) {
        // Ensure this method prepares the episode and respects the autoPlay parameter
        let playerItem = AVPlayerItem(url: url)
        self.player.replaceCurrentItem(with: playerItem)
        self.currentMediaURL = url

    }
    
    private func resumeCurrentEpisodePlayback() {
        
    }

    private func performActionsForPlaying() {
        
    }
    
    private func performStateActionForPlaying() {
        // Since 'player' is not optional, you don't need to unwrap it.
        // Check if the player is playing by examining its 'rate' property.
        if self.player.rate == 0 {
            self.player.play()
            print("Playback started due to state transition to PlayingState.")
        } else {
            print("Player is already playing.")
        }
    }
    
    func manualPlay() {
            guard !player.isPlaying else {
                print("Playback is already in progress.")
                return
            }

            player.play()
            print("Playback started manually.")
            notifyPlaybackStateChanged()
        }
    
    func prepareForNewEpisode(_ url: URL, autoPlay: Bool) {
        print("Preparing episode with URL: \(url). AutoPlay is set to: \(autoPlay).")

        // Clean up before loading a new item.
        if let _ = self.player.currentItem, let observerExists = self.playerItemStatusObserver {
            observerExists.invalidate() // Remove the previous observer
            print("Observer removed from current item.")
        }

        let playerItem = AVPlayerItem(url: url)
        self.player.replaceCurrentItem(with: playerItem)

        // Directly setting shouldAutoPlay based on the autoPlay parameter
        self.shouldAutoPlay = autoPlay
        print("Setting shouldAutoPlay to \(autoPlay) for episode at URL: \(url).")

        // Adjusting the observer logic to respect the autoPlay flag
        self.playerItemStatusObserver = playerItem.observe(\.status, options: [.new, .old]) { [weak self] item, change in
            guard let self = self else { return }
            
            if item.status == .readyToPlay {
                DispatchQueue.main.async {
                    if self.shouldAutoPlay {
                        print("Auto-play enabled, starting playback.")
                        Task {
                            self.manualPlay()
                        }
                    } else {
                        print("Episode is ready. Auto-play is disabled, waiting for user action.")
                    }
                }
            }
        }
        print("Observer added to new player item.")
    }
    
    func seekToProgress(_ progress: Double) {
        guard let duration = player.currentItem?.duration else { return }
        let totalDurationSeconds = CMTimeGetSeconds(duration)
        let seekTimeSeconds = progress * totalDurationSeconds
        let seekTime = CMTimeMakeWithSeconds(seekTimeSeconds, preferredTimescale: 600)
        
        player.seek(to: seekTime) { [weak self] _ in
            Task { [weak self] in
                guard let self = self else { return }
                let newProgress = self.calculateCurrentProgress()
                await self.delegate?.playbackProgressDidChange(to: newProgress)
            }
        }
    }
}
