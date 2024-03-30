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
                await manualPlay()
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
    
    func transitionToReadyStateWithoutAutoplay() {
        print("🔄 Transitioning to ReadyState without auto-play.")

        if !(currentState is ReadyState) {
            self.currentState = ReadyState(mediaPlayer: self)
            print("✅ Transitioned to ReadyState. Awaiting user action to play.")
        } else {
            print("✅ Already in ReadyState. Awaiting user action.")
        }
    }

    /// Transitions the media player to the `ReadyState`, indicating it's ready to play the selected media
        /// but does not start playing automatically.
        func transitionToReadyState() {
            // Transition to `ReadyState` without starting playback automatically.
            transitionToState(ReadyState.self)
            print("MediaPlayer transitioned to ReadyState, awaiting user action.")
        }
    
    func stop() {
            // Pause the player
            player.pause()

            // Optionally, seek to the beginning of the current item if you want to reset its playback position
            player.seek(to: CMTime.zero)

            // Reset or clear the current player item if needed
            player.replaceCurrentItem(with: nil)

            // Update the media player's state to reflect that it's stopped
            transitionToState(StoppedState.self)

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
        DispatchQueue.main.async {
            // This check relies on the AVPlayer's rate to determine if it's playing.
            if self.player.rate != 0 {
                self.player.pause()
                // Transition to PausedState, ensuring the currentState is updated accurately.
                self.transitionToState(PausedState.self)
                print("Playback paused.")
            } else {
                print("Attempted to pause, but player is not currently playing.")
            }
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
    
    // MARK:func transitionToState
    func transitionToState(_ newState: MediaPlayerState.Type, forcePlay: Bool = false) {
        guard type(of: currentState) != newState else {
            print("✅ Already in the target state (\(newState)). No transition necessary.")
            return
        }

        print("🔄 Transitioning to state: \(newState)")
        currentState = newState.init(mediaPlayer: self)
        print("✅ Transitioned to new state: \(newState)")

        // Execute actions based on the specific state
        if newState == PlayingState.self && forcePlay {
            // Only start playback if explicitly requested
            play()
        } else {
            // For ReadyState, ensure the player is prepared but not playing
            print("🔄 Player is in ReadyState, ready for user command.")
        }
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
    
    func manualPlay() async {
            guard !isPlaying else { return }
            print("Starting playback manually.")
            player.play()
            // Similarly, prepare for additional async operations as needed
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
                            await self.manualPlay()
                        }
                    } else {
                        print("Episode is ready. Auto-play is disabled, waiting for user action.")
                    }
                    self.transitionToState(ReadyState.self)
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
