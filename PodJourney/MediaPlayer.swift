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
        transitionToState(StoppedState.self) // Corrected usage
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
            
            // Correctly pass the state type to the transition method.
            // This tells the MediaPlayer to transition to the PausedState,
            // but does not create a new instance here; the MediaPlayer will handle that internally.
            transitionToState(PausedState.self)
            
            print("Playback paused. Transitioned to PausedState.")
        } else {
            print("MediaPlayer pause action requested but not in PlayingState. Current state: \(type(of: currentState))")
        }
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

        if autoPlay {
            // Transition to PlayingState and start playback only if autoPlay is true
            transitionToState(PlayingState.self)
            (currentState as? PlayingState)?.startPlaybackIfNeeded()
        } else {
            // Transition to a state that indicates readiness to play, without starting playback
            // E.g., ReadyState, which indicates the player is ready and waiting for a play command
            transitionToState(ReadyState.self)
        }
    }
    
    private func resumeCurrentEpisodePlayback() {
        // Resume playback only if the current state allows it, such as PausedState or ReadyState
        if currentState is PausedState || currentState is ReadyState {
            transitionToState(PlayingState.self)
            (currentState as? PlayingState)?.startPlaybackIfNeeded()
        } else if !(currentState is PlayingState) {
            // If the player is neither playing nor paused/ready, attempt to start playback of the current item
            // This might be necessary if, for example, the app is in StoppedState but a current episode is loaded
            transitionToState(PlayingState.self)
            (currentState as? PlayingState)?.startPlaybackIfNeeded()
        }
    }
    
    func transitionToState(_ newStateType: MediaPlayerState.Type, forcePlay: Bool = false) {
        print("Attempting to transition to state: \(newStateType), forcePlay: \(forcePlay), shouldAutoPlay: \(shouldAutoPlay)")

        if newStateType == PlayingState.self && !forcePlay && !shouldAutoPlay {
            print("Auto-play is disabled. Aborting transition to PlayingState.")
            return
        }

        if let currentState = self.currentState, type(of: currentState) == newStateType {
            print("Already in the target state (\(newStateType)), no transition needed.")
            return
        }

        let newState = newStateType.init(mediaPlayer: self)
        self.currentState = newState
        print("Transitioned to new state: \(newState)")
    }

    func manualPlay() {
            // Guard against playing when it's  already playing
            guard !isPlaying else { return }

            // If there's no current state or it's not PlayingState, initiate playback
            if let currentState = self.currentState, !(currentState is PlayingState) {
                player.play()
                transitionToState(PlayingState.self, forcePlay: true)
                print("Playback started/resumed.")
            } else {
                // Handle uninitialized state or force playback scenario
                player.play() // Directly attempt to play
                currentState = PlayingState(mediaPlayer: self)
                print("Direct playback initiated.")
            }
        }

    // Adjust the part of your UI or logic that handles the play button press to call manualPlay().
    // Example: This could be tied to a button's action in your user interface.


    func prepareForNewEpisode(_ url: URL, autoPlay: Bool) {
        print("Preparing episode with URL: \(url). AutoPlay is set to: \(autoPlay).")

        // Ensure the player item is cleaned up before loading a new one.
        if let _ = self.player.currentItem, let observerExists = self.playerItemStatusObserver {
            observerExists.invalidate() // Removing the previous observer if exists
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

            if item.status == .readyToPlay && self.shouldAutoPlay {
                print("Episode is ready and autoPlay is enabled. Starting playback.")
                DispatchQueue.main.async {
                    // Transitioning to PlayingState and starting playback if autoPlay is true
                    self.transitionToState(PlayingState.self)
                    (self.currentState as? PlayingState)?.startPlaybackIfNeeded()
                }
            } else if item.status == .readyToPlay {
                print("Episode is ready. Waiting for user action to play since auto-play is disabled.")
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
