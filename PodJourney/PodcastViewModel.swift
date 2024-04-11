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
let logger = Logger(subsystem: "com.yourdomain.PodJourney", category: "Playback")

@MainActor
@objc protocol AppMediaControlDelegate: AnyObject {
    func mediaPlayerDidChangeState(isPlaying: Bool)
    func resetPlaybackProgress()
    func playbackProgressDidChange(to progress: Double)
    func updateTimeDisplay(currentTime: String, remainingTime: String)
    @objc optional func mediaPlayerDidStartPlayback()
}

// Provide a default implementation for the optional method
/*
extension AppMediaControlDelegate {
    func mediaPlayerDidStartPlayback() {
        // Default implementation can be empty
    }
}
*/

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
            DispatchQueue.main.async {
                // Ensuring UI updates are signaled to the main thread.
                self.objectWillChange.send()
            }
        }
    }
    
    @Published var remainingTimeDisplay: String = "--:--" {
        didSet {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
    
    @Published var elapsedTime: Double = 0.0
    @Published var remainingTime: Double = 0.0
    // Removed the duplicated MediaPlayer property
    @Published var isPreparingInitialPlayback = true
    @Published var podcastCategory: String = "General"
    @Published var searchResults: [Podcast] = [] // Assume Podcast is your model type for search results
    @Published var selectedEpisodeTitle: String = ""
    @Published var isPlayButtonEnabled: Bool = false
    @Published var currentlyPlayingEpisode: Episode?
    @Published var isEpisodeLoaded = false
    private var subscriptions = Set<AnyCancellable>()
    private var playbackTimeObserverToken: AVPlayerItem?
    private let episodeSelectionSubject = PassthroughSubject<Episode, Never>()
    private let debounceInterval = 0.1
    private var cancellables = Set<AnyCancellable>()
    private let seekProgressSubject = PassthroughSubject<Double, Never>()
    private var lastUpdateTime: Date?
    private var timeFormatCache: [Double: String] = [:]
    private var searchCancellable: AnyCancellable?
    private var playerItemStatusObserver: NSKeyValueObservation?
    private var playerItemObserver: NSKeyValueObservation?
    weak var delegate: MediaPlayerDelegate?
    var timeObserverToken: Any?
    var shouldAutoPlay = false
    var player: AVPlayer = AVPlayer()
    var mediaPlayer = MediaPlayer()
    
    init(mediaPlayer: MediaPlayer) {
            self.mediaPlayer = mediaPlayer
            super.init()
            print("Initializing PodcastViewModel...")
            
            // Additional setup after MediaPlayer is fully configured
            setupDebouncedSeek()
            setupPlaybackProgressSync()
            setupMediaPlayer()
            setupTimeUpdates()
            setupPlayer()
            self.player = AVPlayer()
        }
    
    override init() {
            self.player = AVPlayer()
            super.init()
            setupPlayer()
            print("PodcastViewModel initialized with direct AVPlayer control.")
        }
    
    // Update UI based on the current playback time and total duration
    func updatePlaybackUI() {
        guard let duration = self.player.currentItem?.duration.seconds, duration.isFinite else {
            print("Duration unavailable or infinite, cannot update UI.")
            return
        }

        let currentTime = self.player.currentTime().seconds
        let remainingTime = duration - currentTime

        DispatchQueue.main.async {
            self.currentTimeDisplay = self.formatTime(seconds: currentTime)
            self.remainingTimeDisplay = self.formatTime(seconds: remainingTime)
        }
    }

    func mediaPlayerProgressDidChange(currentTime: Double, duration: Double) {
        DispatchQueue.main.async {
            // Update your UI components here based on currentTime and duration.
            // For example, updating a progress bar's value or displaying the current time and duration in labels.
            
            // If updatePlaybackUI is designed to refresh the entire playback UI independently,
            // you can still call it without arguments for a full UI refresh.
            self.updatePlaybackUI()
        }
    }
    
    // When an episode is selected, prepare it but wait for explicit play command.
    func episodeSelected(_ episode: Episode) {
        selectEpisode(episode)
        // Reset any flag that might indicate playback should start automatically.
        isEpisodeLoaded = true // This indicates an episode is ready but not automatically played.
    }
    
    func mediaPlayerDidChangeState(isPlaying: Bool) {
            // Update your UI accordingly
            print("Media player state changed: \(isPlaying)")
        }

    private func setupPlayer() {
            // Setup your AVPlayer if needed, e.g., observe its status or item's status
            // For simplicity, this is just a placeholder
            print("AVPlayer setup completed.")
        }

    func userRequestsPlayback(for episode: Episode) {
            // Assuming mediaPlayer is accessible here and has a userDidRequestPlayback property
        mediaPlayer.userDidRequestPlayback = true
            // Call any methods necessary to start playback
            Task {
                playSelectedEpisode()
            }
        }
    
    func startPlaybackManually() async {
        mediaPlayer.manualPlay()
        }
    
    func togglePlayback() {
        print("Toggle playback called")
        if player.rate == 0 {
            if player.currentItem == nil, let episodeURL = currentlyPlaying?.mediaURL {
                    preparePlayer(with: episodeURL)
                }
            player.play()
                isPlaying = true
            } else {
                player.pause()
                isPlaying = false
            }
        }
    
    private func preparePlayer(with url: URL) {
        let playerItem = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: playerItem)

        playerItemObserver?.invalidate()

        playerItemObserver = playerItem.observe(\.status, options: [.new, .old]) { [weak self] item, change in
            DispatchQueue.main.async {
                guard let strongSelf = self else { return }
                if item.status == .readyToPlay {
                    print("🟢 Player item is now ready to play. Duration: \(item.duration.seconds) seconds")
                    strongSelf.setupPeriodicTimeObserver()
                    strongSelf.totalDuration = item.duration.seconds
                    strongSelf.updatePlaybackUI()
                }
            }
        }

        player.play()
        isPlaying = true
        print("▶️ Episode loaded and playback started.")
    }
    
    func prepareAndPlayEpisode(_ episode: Episode, autoPlay: Bool) async {
        // Ensure this method prepares the player and starts playback if `autoPlay` is true.
        // After preparing the player, call setupPeriodicTimeObserver to start the time updates.
        // Example:
        guard let episodeURL = URL(string: episode.link) else {
            print("Invalid URL for episode: \(episode.title)")
            return
        }
        
        let playerItem = AVPlayerItem(url: episodeURL)
        player.replaceCurrentItem(with: playerItem)
        
        if autoPlay {
            player.play()
            setupPeriodicTimeObserver() // Start observing time after playback starts
            isPlaying = true
        }
    }
    
    private func updateUIPlaybackProgress() {
        let newProgress = mediaPlayer.calculateCurrentProgress()
        DispatchQueue.main.async {
            self.uiPlaybackProgress = newProgress
        }
    }
    
    func togglePlayPause() {
        guard let episode = currentlyPlaying else {
            print("⚠️ No episode selected.")
            return
        }

        // Check if the current episode URL matches the selected episode URL
        if let currentEpisodeURL = player.currentItem?.asset as? AVURLAsset, currentEpisodeURL.url == episode.mediaURL {
            // The selected episode is already loaded, toggle play/pause based on current state
            if player.rate == 0 {
                player.play()
                isPlaying = true
            } else {
                player.pause()
                isPlaying = false
                print("⏸ Playback paused for \(episode.title).")
            }
        } else {
            // Here, we handle the case where a new episode is selected, and the user hits the pause button.
            // The expected behavior is to pause the currently playing episode without auto-playing the new one.
            
            // First, check if something is currently playing.
            if player.rate != 0 {
                // If so, pause the current playback and don't start the new episode.
                player.pause()
                isPlaying = false
                print("⏸ Playback paused for the currently playing episode.")
            } else {
                // If nothing is playing, prepare the new episode for playback (but do not play it automatically).
                // This allows the user to play the new episode with a subsequent play action.
                preparePlayer(with: episode.mediaURL)
                // Note: You might decide not to auto-load the new episode here, based on your app's behavior.
                // In such a case, simply inform the user that the episode is ready to be played.
            }
        }
    }
        
    func playEpisode(episode: Episode) async {
        guard let url = URL(string: episode.link) else {
            print("❌ Invalid episode URL")
            return
        }
        
        print("Starting playback for episode: \(episode.title) at URL: \(url)")
        mediaPlayer.play(url: url)
        isPlaying = true
        print("Playback initiated.")
    }

    func skipForward(seconds: Double) {
        let currentTime = player.currentTime()
        let newTime = CMTimeAdd(currentTime, CMTimeMakeWithSeconds(seconds, preferredTimescale: Int32(NSEC_PER_SEC)))
        player.seek(to: newTime)
        print("Skipped forward \(seconds) seconds.")
    }

    func skipBackward(seconds: Double) {
        let currentTime = player.currentTime()
        let newTime = CMTimeSubtract(currentTime, CMTimeMakeWithSeconds(seconds, preferredTimescale: Int32(NSEC_PER_SEC)))
        player.seek(to: newTime)
        print("Skipped backward \(seconds) seconds.")
    }
    
    @MainActor
    func togglePlayPauseForEpisode(_ episode: Episode?) async {
        guard let episode = episode else {
            print("No episode provided for toggling play/pause.")
            return
        }
        
        // Check if the episode to play/pause is the currently playing one
        if let currentlyPlaying = self.currentlyPlaying, currentlyPlaying.id == episode.id {
            // The episode to control is currently selected, toggle play/pause
            await mediaPlayer.togglePlayPause()
        } else {
            // If it's a different episode, first prepare it, then play
            print("Switching to a new episode and starting playback.")
            await prepareAndPlayEpisode(episode, autoPlay: true)
        }
    }
    
    private var _podcastImageUrl: URL? {
        didSet {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
    
    private var _podcastTitle: String? {
        didSet {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
    
    var podcastTitle: String? {
        get { _podcastTitle }
        set { _podcastTitle = newValue }
    }
    
    var podcastImageUrl: URL? {
        get { _podcastImageUrl }
        set { _podcastImageUrl = newValue }
    }
    
    func handleAppMovedToBackground() {
            // Implementation
        }
    
    func fetchEpisodes(feedUrl: String) async {
        guard let url = URL(string: feedUrl) else {
            print("Invalid feed URL.")
            return
        }

        // Move to asynchronous context
        await withCheckedContinuation { continuation in
            let parser = FeedParser(URL: url)

            parser.parseAsync { [weak self] result in
                guard let self = self else {
                    continuation.resume()
                    return
                }

                DispatchQueue.main.async {
                    switch result {
                    case .success(let feed):
                        if let rssFeed = feed.rssFeed {
                            self.podcastTitle = rssFeed.title ?? "Unknown Title"
                            self.podcastImageUrl = URL(string: rssFeed.image?.url ?? "")
                            
                            self.episodes = rssFeed.items?.compactMap { item -> Episode? in
                                guard let title = item.title,
                                      let rawDescription = item.description,
                                      let pubDate = item.pubDate,
                                      let episodeLink = item.enclosure?.attributes?.url,
                                      let episodeUrl = URL(string: episodeLink) else {
                                    return nil
                                }
                                
                                let dateFormatter = DateFormatter()
                                dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
                                let pubDateString = dateFormatter.string(from: pubDate)
                                let cleanDescription = rawDescription.simplifiedHTML().fixApostrophes()

                                return Episode(
                                    id: UUID(),
                                    title: title,
                                    link: episodeLink,
                                    description: cleanDescription,
                                    mediaURL: episodeUrl,
                                    date: pubDateString,
                                    author: item.iTunes?.iTunesAuthor ?? rssFeed.iTunes?.iTunesAuthor ?? "Unknown Author",
                                    website: URL(string: item.link ?? ""),
                                    rating: item.iTunes?.iTunesExplicit == "yes" ? "Explicit" : "Clean",
                                    size: item.enclosure?.attributes?.length.flatMap(Int64.init) ?? 0
                                )
                            } ?? []
                        } else {
                            print("RSS feed not found.")
                            self.episodes = []
                        }
                    case .failure(let error):
                        print("Error parsing feed: \(error.localizedDescription)")
                        self.episodes = []
                    }
                    // Once all updates are done, resume the continuation to signal completion of async task
                    continuation.resume()
                }
            }
        }
    }
    
    func adjustVolume(to newVolume: Float) {
        mediaPlayer.player.volume = newVolume
        print("Volume adjusted to \(newVolume)")
    }
    
    @MainActor
    func userDidEndInteracting(progress: Double) async {
        // Assuming seekToProgress is an async function
        await seekToProgress(progress)
        // Additional logic...
    }
    
    func searchPodcasts(with query: String) {
            // Cancel any existing search request
            searchCancellable?.cancel()
            
            // Ensure that the query is not empty and is not just whitespace
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedQuery.isEmpty else {
                self.searchResults = []
                return
            }
            
            let urlString = "https://itunes.apple.com/search?media=podcast&term=\(trimmedQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            guard let url = URL(string: urlString) else { return }

            // Perform the search with a delay, throttling the search requests
            searchCancellable = URLSession.shared.dataTaskPublisher(for: url)
                .map(\.data)
                .decode(type: SearchResponse.self, decoder: JSONDecoder())
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        break
                    case .failure(let error):
                        print(error.localizedDescription)
                        // Update UI to show error message
                    }
                }, receiveValue: { [weak self] response in
                    self?.searchResults = response.results
                    // Update UI to show search results
                })
        }
    
    struct SearchResponse: Decodable {
        let results: [Podcast]
    }
    
    func pausePlayback() {
        mediaPlayer.pause()
        DispatchQueue.main.async {
            self.isPlaying = false
        }
        print("Playback paused.")
    }
    
    /*
    func mediaPlayerRequiresTimeFormat(seconds: Double) -> String {
            return formatTime(seconds: seconds)
        }
     */
    
    func updateTimeDisplay() {
        guard let currentItem = player.currentItem else {
            currentTimeDisplay = "--:--"
            remainingTimeDisplay = "--:--"
            return
        }
        
        let currentSeconds = currentItem.currentTime().seconds
        let totalSeconds = currentItem.duration.seconds
        let remainingSeconds = max(totalSeconds - currentSeconds, 0)
        
        currentTimeDisplay = formatTime(seconds: currentSeconds)
        remainingTimeDisplay = formatTime(seconds: remainingSeconds)
    }
    
    func resetPlaybackProgress() {
        // Implementation to reset playback progress
        DispatchQueue.main.async {
            self.uiPlaybackProgress = 0.0
        }
    }
    
    /*
    func mediaPlayerDidStartPlayback() {
        print("MediaPlayerDidStartPlayback delegate method called.")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.resetPlaybackProgress()
            print("Playback progress reset.")

            // Ensure that the AVPlayerItem is ready to play
            guard self.player.currentItem?.status == .readyToPlay else {
                print("Attempted to start playback but AVPlayerItem is not ready.")
                return
            }

            // Ensure that this method does not proceed unless the player is in a state expected to start playback
            if self.player.rate == 0 { // Check if the player is not already playing
                // Call to reset the playback progress bar to its initial state.
                
                // Start playback
                self.player.play()
                print("Playback has started for new episode.")

                // Initialize the time updates for the UI, ensuring that we only update time when playback is active
                self.startPlaybackUpdates()
            } else {
                print("Player is already playing.")
            }
        }
    }
    */
    
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
            mediaPlayer.currentMediaURL = episodeURL
            mediaPlayer.prepareForNewEpisode(episodeURL, autoPlay: autoPlay)
            
            if autoPlay {
                mediaPlayer.play(url: URL(string: episode.link)) // This should only be called if autoPlay is true.
                } else {
                    print("Episode prepared, waiting for user action to play.")
                    // Do not initiate playback here.
            }
        } else {
            // Handling re-selected or currently paused episode
            if autoPlay {
                print("Episode re-selected with autoPlay enabled. Checking current playback state.")
                if mediaPlayer.currentState is PausedState {
                    print("Resuming playback for the currently paused episode.")
                    mediaPlayer.play(url: URL(string: episode.link))
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
        guard let currentItem = player.currentItem else {
            print("No current item to seek.")
            return
        }

        let duration = currentItem.duration.seconds
        if duration.isFinite {
            let seekTimeSeconds = progress * duration
            let seekTime = CMTime(seconds: seekTimeSeconds, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            player.seek(to: seekTime) { _ in
                print("Seeked to \(seekTimeSeconds) seconds")
                // Optionally, resume playback if it was paused for seeking
                if self.isPlaying {
                    self.player.play()
                }
            }
        }
    }
    
    func updateCurrentTimeDisplay(time: CMTime) {
        let currentSeconds = time.seconds
        let durationSeconds = mediaPlayer.player.currentItem?.duration.seconds ?? 0
        let remainingSeconds = max(durationSeconds - currentSeconds, 0)

        print("Current seconds: \(currentSeconds), Duration: \(durationSeconds), Remaining: \(remainingSeconds)")

        currentTimeDisplay = formatTime(seconds: currentSeconds)
        remainingTimeDisplay = formatTime(seconds: remainingSeconds)
        // Continue with the rest of your function...
    }
    
    func setupPeriodicTimeObserver() {
        // Remove any existing time observer
        if let timeObserverToken = timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
        }

        let interval = CMTime(seconds: 1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        // Add a new time observer
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.updatePlaybackUI()
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
            if let duration = mediaPlayer.player.currentItem?.duration.seconds, duration.isFinite {
                totalDuration = duration
            }
        }
    
    private func setupTimeUpdates() {
        print("Setting up time updates...")
        let interval = CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        mediaPlayer.player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            print("Time observer triggered: currentTime = \(time.seconds) seconds")
                
            // Explicitly indicate that updatePlaybackUI() is called on the main actor
            Task {
                await MainActor.run {
                    self.updatePlaybackUI()
                }
            }
        }
    }
    
    private func setupMediaPlayer() {
            self.mediaPlayer = MediaPlayer()
        self.mediaPlayer.delegate = self // Correctly set delegate here
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
    func selectEpisode(_ episode: Episode) {
        currentlyPlaying = episode
        isEpisodeLoaded = true // Signal that an episode is loaded and ready

        // Optionally, remove player item preparation from here if it's causing issues
        // and prepare it in the play method if not already prepared.
    }

    func playSelectedEpisode() {
        if let _ = currentlyPlaying {
            // Assuming you have logic here to play the currently selected episode.
            // If `player.rate == 0`, indicating the player is not currently playing, you can proceed to play the episode.
            if player.rate == 0 {
                player.play()
                print("Playing selected episode.")
            } else {
                print("Player is already playing.")
            }
        } else {
            print("No episode selected to play.")
        }
    }
    
    private func togglePlayPauseBasedOnCurrentState() {
        
    }

    private func manageCurrentEpisodePlaybackState() {

        if isPlaying {
            mediaPlayer.pause()
            print("⏸ Playback paused. Toggle button should show play icon.")
        } else {
            mediaPlayer.play()
            print("▶️ Playback resumed. Toggle button should show pause icon.")
        }
    }
    
    private func startPlayback() {
        mediaPlayer.play()
        log("Playback has started/resumed for the current episode.")
    }
    
    // Example modularization of additional functionality
    private func stopCurrentPlayback() {
        mediaPlayer.stop()
        log("Playback stopped, preparing for new episode.")
    }

    private func attemptAutoPlay() {
        if self.shouldAutoPlay {
            log("▶️ Auto-play enabled, starting playback for the new episode.")
            self.mediaPlayer.play()
        } else {
            log("⏸ New episode prepared. Waiting for user action to play.")
        }
    }

    private func log(_ message: String) {
        // A centralized logging function could add more details or handle logging differently based on environment
        print(message)
    }
}

extension PodcastViewModel {

    func mediaPlayerDidStartPlayback() {
        // Implement according to your app's needs
        print("Media player started playback.")
    }
    
    func resetPlaybackProgress() async {
        // Asynchronous method, implement as needed
        DispatchQueue.main.async {
            self.playbackProgress = 0.0
        }
    }

    func mediaPlayerDidChangeState(isPlaying: Bool) async {
        DispatchQueue.main.async {
            self.isPlaying = isPlaying
            print("Playback state changed: isPlaying = \(isPlaying)")
        }
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

    func mediaPlayerRequiresTimeFormat(seconds: Double) -> String {
        // Implement your time formatting logic here
        return formatTime(seconds: seconds)
    }

    func mediaPlayerPlaybackStateDidChange(isPlaying: Bool) {
        // This method seems to be both in your original implementation and in the protocol
        DispatchQueue.main.async {
            self.isPlaying = isPlaying
        }
    }

    func mediaPlayerDidPause() {
        // Implement according to your app's needs
        print("Media player was paused.")
    }

    func mediaPlayerProgressDidUpdate(to progress: Double) {
        // This seems to duplicate the functionality of `playbackProgressDidChange(to:)`
        DispatchQueue.main.async {
            self.playbackProgress = progress
        }
    }

    // Add other protocol methods here...
}


extension String {
        func simplifiedHTML() -> String {
            // Replace paragraph and break tags with newlines
            let withNewLines = self.replacingOccurrences(of: "<p>", with: "\n\n")
                               .replacingOccurrences(of: "<br>", with: "\n")
                               .replacingOccurrences(of: "<br/>", with: "\n")
                               .replacingOccurrences(of: "<br />", with: "\n")
            // Remove any remaining HTML tags
            let withoutHTMLTags = withNewLines.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
            // Trim leading and trailing whitespace and newlines
            return withoutHTMLTags.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func toAttributedString() -> AttributedString? {
            do {
                return try AttributedString(markdown: self)
            } catch {
                print("Error converting markdown to AttributedString: \(error)")
                return nil
            }
        }
    
    func convertingHTMLToPlainText() -> String {
            var plainText = self
            // Replace paragraph tags with double newlines
            plainText = plainText.replacingOccurrences(of: "<p>", with: "")
            plainText = plainText.replacingOccurrences(of: "</p>", with: "\n\n")
            // Replace line break tags with a single newline
            let lineBreakPatterns = ["<br>", "<br/>", "<br />"]
            for pattern in lineBreakPatterns {
                plainText = plainText.replacingOccurrences(of: pattern, with: "\n")
            }
            // Decode HTML entities and strip remaining tags if needed.
            plainText = plainText.strippingHTML().decodingHTMLEntities()
            return plainText
        }
    
    func fixApostrophes() -> String {
            return self.replacingOccurrences(of: "â€™", with: "'")
                .replacingOccurrences(of: "&apos;", with: "'")
                .replacingOccurrences(of: "&#39;", with: "'")
                // Add more replacements as needed
        }
    
    func decodingHTMLEntities() -> String {
            guard let data = self.data(using: .utf8) else { return self }
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ]
            guard let decodedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil).string else {
                return self
            }
            return decodedString
        }
    
    
    func decodeUnicodeCharacters() -> String {
        applyingTransform(StringTransform("Any-Hex/Java"), reverse: false) ?? self
    }
    
    func strippingHTML() -> String {
        guard let data = data(using: .utf8) else { return self }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        
        guard let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return self
        }
        
        return attributedString.string
    }
}
