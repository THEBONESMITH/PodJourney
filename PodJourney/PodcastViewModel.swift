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
            mediaPlayer.transitionToState(StoppedState.self)
        }
        
        print("MediaPlayer initialized and delegate set.")
        
        // Additional setup after MediaPlayer is fully configured
        setupDebouncedSeek()
        setupPlaybackProgressSync()
        setupMediaPlayer()
        setupTimeUpdates()
    }
    
    @MainActor
    func togglePlayback() async {
        print("togglePlayback: Toggling playback. Current isPlaying state: \(self.isPlaying).")

        if self.isPlaying {
            // Pausing the player directly and updating the state accordingly.
            mediaPlayer?.pause()
            print("togglePlayback: Playback paused.")
        } else if let episode = currentlyPlaying {
            // Direct play request, considered as explicit user action.
            print("togglePlayback: Attempting to start/resume playback for episode: \(episode.title).")
            
            // Assuming mediaPlayer has been updated to handle state transitions and start playback
            mediaPlayer?.play(url: URL(string: episode.link))
        } else {
            print("togglePlayback: No episode selected or currently playing. Playback toggle ignored.")
        }
    }
    
    @MainActor
        func prepareAndPlayEpisode(_ episode: Episode, autoPlay: Bool) async {
            guard let episodeURL = URL(string: episode.link) else {
                print("Invalid URL for episode: \(episode.title)")
                return
            }

            print("Preparing episode: \(episode.title) for playback. AutoPlay flag is set to: \(autoPlay).")
            mediaPlayer?.prepareForNewEpisode(episodeURL, autoPlay: autoPlay)
        }
    
    private func updateUIPlaybackProgress() {
        if let mediaPlayer = mediaPlayer {
            let newProgress = mediaPlayer.calculateCurrentProgress()
            DispatchQueue.main.async {
                self.uiPlaybackProgress = newProgress
            }
        } else {
            print("MediaPlayer instance is nil.")
        }
    }
    
    @MainActor
    func togglePlayPause() async {
        guard let mediaPlayer = mediaPlayer else {
            print("MediaPlayer is nil.")
            return
        }

        if mediaPlayer.isPlaying {
            mediaPlayer.pause()
        } else {
            await mediaPlayer.manualPlay() // Assuming manualPlay might become async
        }
    }
    
    func skipBackward(seconds: Double) {
        mediaPlayer?.skipBackward(seconds: seconds)
        
        // After skipping, update the UI progress property
        updateUIPlaybackProgress()
    }
        
    func skipForward(seconds: Double) {
        // Assuming you have a method in MediaPlayer to perform the skip
        mediaPlayer?.skipForward(seconds: seconds)
        
        // After skipping, update the UI progress property
        updateUIPlaybackProgress()
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
            await mediaPlayer?.togglePlayPause()
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
        mediaPlayer?.player.volume = newVolume
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
        mediaPlayer?.pause()
        DispatchQueue.main.async {
            self.isPlaying = false
        }
        print("Playback paused.")
    }
    
    func mediaPlayerRequiresTimeFormat(seconds: Double) -> String {
            return formatTime(seconds: seconds)
        }
    
    nonisolated func updateTimeDisplay(currentTime: String, remainingTime: String) {
            // Implement this method to update the UI with the current time and remaining time.
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
                print("🔊 mediaPlayerDidChangeState: MediaPlayer state changed to isPlaying: \(isPlaying) for episode: \(episodeTitle)")
            } else {
                print("🔊 mediaPlayerDidChangeState: MediaPlayer state changed to isPlaying: \(isPlaying), no episode currently selected")
            }
            
            // Optionally, inform about the playback action taken
            if isPlaying {
                print("▶️ Playback has started/resumed.")
            } else {
                print("⏸ Playback has been paused or stopped.")
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
                    mediaPlayer?.play(url: URL(string: episode.link)) // This should only be called if autoPlay is true.
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
                    mediaPlayer?.play(url: URL(string: episode.link))
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
            
            Task { [weak self] in
                guard let strongSelf = self else { return }
                await strongSelf.updateCurrentTimeDisplay(time: time)
            }
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
        print("🚀 Episode selection initiated for: \(episode.title), isNewEpisode: \(isNewEpisode)")

        if isNewEpisode {
            mediaPlayer?.stop()
            print("🛑 Playback stopped and media player reset for new episode selection.")

            await preparePlayerForEpisode(episode, autoPlay: false)
            print("🆕 Episode prepared: \(episode.title). AutoPlay is disabled, awaiting user action.")

            self.currentlyPlaying = episode
            print("📝 Currently playing episode updated to: \(episode.title), ready for user action.")

            // Ensure player is ready to play without automatically starting playback
            mediaPlayer?.transitionToState(ReadyState.self, forcePlay: false)
            print("🔄 Player transitioned to ReadyState, awaiting user action to play.")
        } else {
            // Handle reselection of the same episode
            print("🔄 Same episode re-selected. No immediate action taken.")
        }

        await updateUIForEpisodeSelection(episode: episode)
        print("👁️ UI updated for episode selection.")
    }

    func playSelectedEpisode(_ episode: Episode) {
        guard currentlyPlaying?.id == episode.id else {
            print("Episode not prepared or mismatch. Preparing episode for playback.")
            // Prepare the episode if not already done.
            Task {
                await selectEpisode(episode)
            }
            return
        }

        print("Starting playback for episode: \(episode.title)")
        mediaPlayer?.play()
    }
    
    private func togglePlayPauseBasedOnCurrentState() {
        
    }
    
    private func togglePlayPauseForCurrentEpisode() {
        guard let mediaPlayer = mediaPlayer else { return }

        if mediaPlayer.isPlaying {
            mediaPlayer.pause()
            print("⏸ Episode paused. UI should now show the play button.")
            mediaPlayer.transitionToState(PausedState.self) // Corrected to pass type
        } else {
            mediaPlayer.play()
            print("▶️ Episode resumed. UI should now show the pause button.")
            mediaPlayer.transitionToState(PlayingState.self) // Corrected to pass type
        }
    }

    private func manageCurrentEpisodePlaybackState() {
        guard let isPlaying = mediaPlayer?.isPlaying else { return }

        if isPlaying {
            mediaPlayer?.pause()
            print("⏸ Playback paused. Toggle button should show play icon.")
        } else {
            mediaPlayer?.play()
            print("▶️ Playback resumed. Toggle button should show pause icon.")
        }
    }
    
    private func startPlayback() {
        mediaPlayer?.play()
        log("Playback has started/resumed for the current episode.")
    }
    
    // Example modularization of additional functionality
    private func stopCurrentPlayback() {
        mediaPlayer?.stop()
        log("Playback stopped, preparing for new episode.")
    }

    private func attemptAutoPlay() {
        if self.shouldAutoPlay {
            log("▶️ Auto-play enabled, starting playback for the new episode.")
            self.mediaPlayer?.play()
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
    func mediaPlayerPlaybackStateDidChange(isPlaying: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = isPlaying
            // Update any other relevant UI components.
        }
    }
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
