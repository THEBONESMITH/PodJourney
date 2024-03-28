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
    
    func togglePlayPause() {
        guard let currentState = self.currentState else {
            print("MediaPlayer state is undefined or uninitialized.")
            // Attempt to initialize or load default state
            return
        }

        if currentState is PlayingState {
            self.pause() // Ensure this transitions the state to PausedState.
        } else {
            self.play() // Ensure this checks if playback can be initiated or resumed.
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
    
@MainActor
protocol MediaPlayerDelegate: AnyObject {
    func mediaPlayerDidStartPlayback()
    func resetPlaybackProgress() async
    func mediaPlayerDidChangeState(isPlaying: Bool) async
    func updateTimeDisplay(currentTime: String, remainingTime: String)
    func playbackProgressDidChange(to progress: Double) async
    func mediaPlayerRequiresTimeFormat(seconds: Double) -> String
    func mediaPlayerPlaybackStateDidChange(isPlaying: Bool)
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
        
        // Initialize with the StoppedState
        transitionToState(StoppedState(mediaPlayer: self))
    }
    
    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?) {
        if keyPath == "status",
           let _ = object as? AVPlayer, // Changed 'player' to '_'
           let statusNumber = change?[.newKey] as? NSNumber,
           let status = AVPlayer.Status(rawValue: statusNumber.intValue) {
            
            switch status {
            case .readyToPlay:
                print("Player is ready to play")
                // Handle player ready to play
            case .failed:
                print("Player failed")
                // Handle failure
            case .unknown:
                print("Player status unknown")
                // Handle unknown status
            @unknown default:
                print("Encountered an unknown player status")
                // Handle any future cases
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
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
        if currentState is PlayingState {
            print("Pausing MediaPlayer from PlayingState.")
            player.pause()
            // Transition to PausedState and notify any observers or the UI about the change.
            transitionToState(PausedState(mediaPlayer: self))
            print("Playback paused. Transitioned to PausedState.")
        } else {
            print("MediaPlayer pause action requested but not in     PlayingState. Current state: \(type(of: currentState))")
        }
    }
    
    func play() {
        // Ensure this method correctly transitions the state to PlayingState and is only called when appropriate.
        self.currentState = PlayingState(mediaPlayer: self)
        // Start or resume playback.
    }
    
    func transitionToState(_ newState: MediaPlayerState) {
        guard !(newState is PlayingState && !shouldAutoPlay) else {
            print("Skipping transition to PlayingState due to shouldAutoPlay being false.")
            return
        }

        let prevStateName = String(describing: type(of: self.currentState))
        let newStateName = String(describing: type(of: newState))

        print("Transitioning from \(prevStateName) to \(newStateName). shouldAutoPlay: \(self.shouldAutoPlay)")

        self.currentState = newState
    }
    
    func prepareForNewEpisode(_ url: URL, autoPlay: Bool) {
            print("Preparing episode with URL: \(url). AutoPlay is set to: \(autoPlay).")

            // Ensure the player item is cleaned up before loading a new one.
        if let _ = self.player.currentItem, let observerExists = self.playerItemStatusObserver {
            observerExists.invalidate() // Assuming 'observerExists' holds your observer token
            print("Observer removed from current item.")
        }

            let playerItem = AVPlayerItem(url: url)
            self.player.replaceCurrentItem(with: playerItem)

            // Setting shouldAutoPlay directly based on the autoPlay parameter
            self.shouldAutoPlay = autoPlay // Correctly respect the function parameter
            print("Setting shouldAutoPlay to \(autoPlay) for episode at URL: \(url).")

            // Add observer to the new player item using a more robust method if available
        self.playerItemStatusObserver = playerItem.observe(\.status, options: [.new, .old]) { [weak self] item, change in
            guard let self = self else { return }

            if item.status == .readyToPlay && self.shouldAutoPlay {
                // Only auto-play if shouldAutoPlay is true
                DispatchQueue.main.async {
                    self.player.play()
                    print("Auto-playing as episode is ready.")
                }
            } else if item.status == .readyToPlay {
                print("Episode is ready. Waiting for user action to play.")
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


