//
//  PodcastViewModel.swift
//  PodJourney
//
//  Created by . . on 28/03/2024.
//

import Foundation
import SwiftUI
import Combine
import AVFoundation
import FeedKit
import os.log
import AppKit

// Define a logger for the podcast app
let logger = Logger(subsystem: "com.yourdomain.PodcastApp", category: "Playback")

@MainActor
@objc protocol AppMediaControlDelegate: AnyObject {
    func mediaPlayerDidChangeState(isPlaying: Bool)
    func resetPlaybackProgress()
    func playbackProgressDidChange(to progress: Double)
    func updateTimeDisplay(currentTime: String, remainingTime: String)
    @objc optional func mediaPlayerDidStartPlayback()
}

// Provide a default implementation for the optional method
extension AppMediaControlDelegate {
    func mediaPlayerDidStartPlayback() {
        // Default implementation can be empty
    }
}

@MainActor
class PodcastViewModel: NSObject, ObservableObject, MediaPlayerDelegate {
    @Published var currentlyPlaying: Episode?
    @Published var isPlaying = false
    @Published var playbackProgress: Double = 0.0
    @Published var episodes: [Episode] = []
    @Published var selectedEpisodeID: UUID?
    @Published var isUserInteractingWithProgressBar = false
    @Published var currentProgress: Double = 0.0
    @Published var totalDuration: Double = 0.0
    @Published var actualPlaybackProgress: Double = 0
    @Published var uiPlaybackProgress: Double = 0
    @Published var isUserInteracting = false
    @Published var currentTimeDisplay: String = "--:--" {
        didSet {
            print("Current Time Updated: \(currentTimeDisplay)")
            DispatchQueue.main.async {
                // Ensuring UI updates are signaled to the main thread.
                self.objectWillChange.send()
            }
        }
    }
    
    @Published var remainingTimeDisplay: String = "--:--" {
        didSet {
            print("Remaining Time Updated: \(remainingTimeDisplay)")
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
    
    @Published var elapsedTime: Double = 0.0
    @Published var remainingTime: Double = 0.0
    // Removed the duplicated MediaPlayer property
    @Published var mediaPlayer: MediaPlayer?
    @Published var isPreparingInitialPlayback = true
    @Published var podcastCategory: String = "General"
    @Published var searchResults: [Podcast] = [] // Assume Podcast is your model type for search results
    @Published var selectedEpisodeTitle: String = ""
    @Published var isPlayButtonEnabled: Bool = false
    @Published var currentlyPlayingEpisode: Episode?
    private var subscriptions = Set<AnyCancellable>()
    private var playerItemObserver: Any?
    private var playbackTimeObserverToken: AVPlayerItem?
    private let episodeSelectionSubject = PassthroughSubject<Episode, Never>()
    private let debounceInterval = 0.1
    private var cancellables = Set<AnyCancellable>()
    private let seekProgressSubject = PassthroughSubject<Double, Never>()
    private var lastUpdateTime: Date?
    private var timeFormatCache: [Double: String] = [:]
    private var searchCancellable: AnyCancellable?
    weak var delegate: MediaPlayerDelegate?
    var timeObserverToken: Any?
    var shouldAutoPlay = false
    var player: AVPlayer?
    
    override init() {
        super.init()
        print("Initializing PodcastViewModel...")
        
        // Initialize MediaPlayer without setting an initial state here
        let newMediaPlayer = MediaPlayer()
        self.mediaPlayer = newMediaPlayer
        
        // Now MediaPlayer is ready, you can set its initial state
        if let mediaPlayer = self.mediaPlayer {
            mediaPlayer.transitionToState(StoppedState(mediaPlayer: mediaPlayer))
        }
        
        print("MediaPlayer initialized and delegate set.")
        
        // Additional setup after MediaPlayer is fully configured
        setupDebouncedSeek()
        setupPlaybackProgressSync()
        setupMediaPlayer()
        setupTimeUpdates()
    }
    
    func mediaPlayerRequiresTimeFormat(seconds: Double) -> String {
            return formatTime(seconds: seconds)
        }
    
    nonisolated func updateTimeDisplay(currentTime: String, remainingTime: String) {
            // Implement this method to update the UI with the current time and remaining time.
            print("Current time: \(currentTime), Remaining time: \(remainingTime)")
        }
    
    func playbackProgressDidChange(to progress: Double) {
        DispatchQueue.main.async {
            // Assuming totalDuration is already set correctly when the episode is loaded
            self.currentProgress = progress * self.totalDuration
            // This will update the progress bar's fill based on the current progress
        }
    }
    
    func resetPlaybackProgress() {
        // Implementation to reset playback progress
        DispatchQueue.main.async {
            self.uiPlaybackProgress = 0.0
        }
    }
    
    func mediaPlayerDidChangeState(isPlaying: Bool) {
        DispatchQueue.main.async {
            // Update the ViewModel's isPlaying property based on the delegate callback
            self.isPlaying = isPlaying
            
            // Log the current playback state along with the episode title if available
            if let episodeTitle = self.currentlyPlaying?.title {
                print("mediaPlayerDidChangeState: MediaPlayer state changed to isPlaying: \(isPlaying) for episode: \(episodeTitle)")
            } else {
                print("mediaPlayerDidChangeState: MediaPlayer state changed to isPlaying: \(isPlaying), no episode currently selected")
            }
            
            // Optionally, inform about the playback action taken
            if isPlaying {
                print("Playback has started/resumed.")
            } else {
                print("Playback has been paused or stopped.")
            }

            // This method informs you about the playback state change, allowing you to update your UI accordingly
            // Update UI components here, such as play/pause button appearance, episode highlight, etc.
        }
    }
    
    func mediaPlayerDidStartPlayback() {
        print("MediaPlayerDidStartPlayback delegate method called.")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.resetPlaybackProgress()
            print("Playback progress reset.")

            // Ensure that the AVPlayerItem is ready to play
            guard self.player?.currentItem?.status == .readyToPlay else {
                print("Attempted to start playback but AVPlayerItem is not ready.")
                return
            }

            // Ensure that this method does not proceed unless the player is in a state expected to start playback
            if self.player?.rate == 0 { // Check if the player is not already playing
                // Call to reset the playback progress bar to its initial state.
                
                // Start playback
                self.player?.play()
                print("Playback has started for new episode.")

                // Initialize the time updates for the UI, ensuring that we only update time when playback is active
                self.startPlaybackUpdates()
            } else {
                print("Player is already playing.")
            }
        }
    }
    
    func userDidStartInteracting() {
        isUserInteracting = true
    }
    
    @MainActor
    func updateUIForEpisodeSelection(episode: Episode) async {
        // Implementation details to update the UI based on the selected episode
        // This should involve only passive UI updates like enabling the play button, updating episode titles, descriptions, etc.
        print("UI updating for episode: \(episode.title)")
            
        // Add UI update logic here.
        // For example:
        // self.selectedEpisodeTitle = episode.title
        // self.isPlayButtonEnabled = true
        // Note: Ensure that no part of this method starts playback or has side effects that could trigger playback.
    }
    
    @MainActor
    func preparePlayerForEpisode(_ episode: Episode, autoPlay: Bool) async {
        guard let episodeURL = URL(string: episode.link) else {
            print("Invalid URL for episode: \(episode.title).")
            return
        }
        print("Preparing episode: \(episode.title) for playback. AutoPlay flag is set to: \(autoPlay).")

        if self.currentlyPlayingEpisode?.id != episode.id {
            // New episode logic
            self.currentlyPlayingEpisode = episode
            mediaPlayer?.currentMediaURL = episodeURL
            mediaPlayer?.prepareForNewEpisode(episodeURL, autoPlay: autoPlay)
            
            if autoPlay {
                    mediaPlayer?.play() // This should only be called if autoPlay is true.
                } else {
                    print("Episode prepared, waiting for user action to play.")
                    // Do not initiate playback here.
            }
        } else {
            // Handling re-selected or currently paused episode
            if autoPlay {
                print("Episode re-selected with autoPlay enabled. Checking current playback state.")
                if mediaPlayer?.currentState is PausedState {
                    print("Resuming playback for the currently paused episode.")
                    mediaPlayer?.play()
                } else {
                    print("Current state does not require action. Playback remains paused or stopped.")
                }
            } else {
                print("Episode re-selected or autoPlay is false, no immediate action taken.")
            }
        }
    }
    
    @MainActor
    func seekToProgress(_ progress: Double) async {
        print("Seeking to progress: \(progress)")
        guard let mediaPlayer = mediaPlayer else {
            print("MediaPlayer instance is nil.")
            return
        }
        
        // Directly calling a synchronous method without actual awaiting, but in an async context
        mediaPlayer.seekToProgress(progress)
    }
    
    func updateCurrentTimeDisplay(time: CMTime) {
        let currentSeconds = time.seconds
        let durationSeconds = mediaPlayer?.player.currentItem?.duration.seconds ?? 0
        let remainingSeconds = max(durationSeconds - currentSeconds, 0)

        print("Current seconds: \(currentSeconds), Duration: \(durationSeconds), Remaining: \(remainingSeconds)")

        currentTimeDisplay = formatTime(seconds: currentSeconds)
        remainingTimeDisplay = formatTime(seconds: remainingSeconds)
        // Continue with the rest of your function...
    }
    
    func setupPeriodicTimeObserver() {
        let interval = CMTime(seconds: 1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        mediaPlayer?.player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            print("Periodic time observer triggered: \(time.seconds)") // Add this line
            self?.updateCurrentTimeDisplay(time: time)
        }
    }
    
    func formatTime(seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN else {
            // Return a default or placeholder string if the input is not valid
            return "00:00:00"
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: TimeInterval(seconds)) ?? "00:00:00"
    }
    
    // Call this method when your player starts playing
        func startPlaybackUpdates() {
            setupPeriodicTimeObserver()
            if let duration = mediaPlayer?.player.currentItem?.duration.seconds, duration.isFinite {
                totalDuration = duration
            }
        }
    
    private func setupTimeUpdates() {
        print("Setting up time updates...")
        let interval = CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        mediaPlayer?.player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            print("Periodic time observer triggered: \(time.seconds)") // Add this line
            guard let self = self else { return }
                
            Task { @MainActor in
                guard let duration = self.mediaPlayer?.player.currentItem?.duration.seconds,
                      duration.isFinite && !duration.isNaN else {
                    print("Invalid duration. Skipping time update.")
                    return
                }
                    
                let currentTime = time.seconds
                let remainingTime = duration - currentTime
                    
                if currentTime.isFinite && !currentTime.isNaN && remainingTime.isFinite && !remainingTime.isNaN {
                    print("Current Time: \(self.formatTime(seconds: currentTime)), Remaining Time: \(self.formatTime(seconds: remainingTime))")
                    self.currentTimeDisplay = self.formatTime(seconds: currentTime)
                    self.remainingTimeDisplay = self.formatTime(seconds: remainingTime)
                }
            }
        }
    }
    
    private func setupMediaPlayer() {
            self.mediaPlayer = MediaPlayer()
            self.mediaPlayer?.delegate = self // Correctly set delegate here
            // Other setup or configuration
        }
    
    private func setupPlaybackProgressSync() {
            $actualPlaybackProgress
                .receive(on: RunLoop.main)
                .sink { [weak self] progress in
                    guard let self = self, !self.isUserInteracting else { return }
                    self.uiPlaybackProgress = progress
                }
                .store(in: &cancellables)
        }
    
    private func setupDebouncedSeek() {
        seekProgressSubject
            .debounce(for: .seconds(debounceInterval), scheduler: DispatchQueue.main) // Adjust debounce interval as needed
            .sink { [weak self] progress in
                Task { // Create a new task for asynchronous operations
                    await self?.seekToProgress(progress)
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: func selectEpisode
        @MainActor
        func selectEpisode(_ episode: Episode) async {
            let isNewEpisode = self.currentlyPlaying?.id != episode.id
            print("Episode selection initiated for: \(episode.title), isNewEpisode: \(isNewEpisode)")

            if isNewEpisode {
                print("New episode selected: \(episode.title). Preparing for playback without auto-play.")
                // Explicitly set autoPlay to false to avoid playing the episode
                await preparePlayerForEpisode(episode, autoPlay: false)
                self.currentlyPlaying = episode // Update the currentlyPlaying episode reference
                print("New episode prepared without auto-play.")
            } else {
                print("Episode re-selected, no action taken for auto-play.")
                // Do nothing if the episode is re-selected, waiting for user action to play
            }

            // Ensure the UI is updated to reflect the new episode selection without assuming playback
            await updateUIForEpisodeSelection(episode: episode)
        }
}

extension PodcastViewModel {
    func mediaPlayerPlaybackStateDidChange(isPlaying: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = isPlaying
            // Update any other relevant UI components.
        }
    }
}
