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
    @Published var searchResults: [Podcast] = [] // Search results
    @Published var searchEpisodes: [Episode] = [] // Episodes from search results
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
    @Published var selectedEpisodeTitle: String = ""
    @Published var isPlayButtonEnabled: Bool = false
    @Published var currentlyPlayingEpisode: Episode?
    @Published var isEpisodeLoaded = false
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var searchText = ""
    @Published var podcasts: [Podcast] = []
    @Published var selectedPodcast: Podcast?
    @Published var episodeDetailVisible: Bool = false
    private var subscriptions = Set<AnyCancellable>()
    private var playbackTimeObserverToken: AVPlayerItem?
    private let episodeSelectionSubject = PassthroughSubject<Episode, Never>()
    private let debounceInterval = 0.1
    private let seekProgressSubject = PassthroughSubject<Double, Never>()
    private var lastUpdateTime: Date?
    private var timeFormatCache: [Double: String] = [:]
    private var searchCancellable: AnyCancellable?
    private var playerItemStatusObserver: NSKeyValueObservation?
    private var playerItemObserver: NSKeyValueObservation?
    private var searchDelayPublisher: AnyPublisher<String, Never>?
    private var isParsingCancelled = false
    private let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            return formatter
        }()
    weak var delegate: MediaPlayerDelegate?
    var timeObserverToken: Any?
    var shouldAutoPlay = false
    var player: AVPlayer = AVPlayer()
    var mediaPlayer = MediaPlayer()
    var cancellables = Set<AnyCancellable>()
    let searchSubject = PassthroughSubject<String, Never>()
    
    init(mediaPlayer: MediaPlayer) {
            self.mediaPlayer = mediaPlayer
            super.init()
            print("ViewModel initialized")
            
            // Additional setup after MediaPlayer is fully configured
            setupDebouncedSeek()
            setupPlaybackProgressSync()
            setupMediaPlayer()
            setupTimeUpdates()
            setupPlayer()
            self.player = AVPlayer()
            setupSearchPublisher()
            setupSearchSubscriber()
            // loadPodcasts()
        self.podcasts = [
            Podcast(id: 1, artistName: "Artist One", trackName: "Podcast One", artworkUrl100: "http://example.com/artwork1.jpg", feedUrl: "http://example.com/feed1.rss"),
            Podcast(id: 2, artistName: "Artist Two", trackName: "Podcast Two", artworkUrl100: "http://example.com/artwork2.jpg", feedUrl: "http://example.com/feed2.rss")
            ]
        }
    
    override init() {
            self.player = AVPlayer()
            super.init()
            setupPlayer()
            print("PodcastViewModel initialized with direct AVPlayer control.")
        }
    
    // Method to fetch episodes for a selected podcast in search results
    func searchFetchEpisodes(for podcast: Podcast) async {
        print("Fetching episodes for: \(podcast.trackName)")
        guard let url = URL(string: podcast.feedUrl) else {
            print("Invalid feed URL for podcast: \(podcast.trackName)")
            return
        }

        // Clear previous search episodes immediately to prevent old data from being displayed
        await MainActor.run {
            self.searchEpisodes = []
        }

        // Create an instance of FeedParser and parse the feed asynchronously
        let parser = FeedParser(URL: url)
        let result = await withCheckedContinuation { continuation in
            parser.parseAsync(queue: DispatchQueue.global(qos: .userInitiated)) { result in
                continuation.resume(returning: result)
            }
        }

        await MainActor.run {
            switch result {
            case .success(let feed):
                // Process the feed if it's an RSS type
                if let rssFeed = feed.rssFeed {
                    let episodes = parseEpisodes(from: rssFeed)
                    self.searchEpisodes = episodes
                    print("Loaded \(episodes.count) episodes for \(podcast.trackName)")
                } else {
                    print("The feed is not an RSS feed.")
                }
            case .failure(let error):
                print("Error parsing feed: \(error.localizedDescription)")
                self.searchEpisodes = []  // Clear episodes if there is an error
            }
        }
    }

    // Helper method to parse episodes from an RSSFeed
    private func parseEpisodes(from rssFeed: FeedKit.RSSFeed) -> [Episode] {
        return rssFeed.items?.compactMap { item -> Episode? in
            guard let title = item.title,
                  let link = item.link,
                  let description = item.description,
                  let enclosure = item.enclosure,
                  let url = URL(string: enclosure.attributes?.url ?? ""),
                  let pubDate = item.pubDate else {
                return nil
            }
            let durationString = formatDuration(from: item.iTunes?.iTunesDuration)
            return Episode(
                title: title,
                link: link,
                description: description,
                mediaURL: url,
                date: dateFormatter.string(from: pubDate),
                author: item.author ?? "Unknown",
                category: item.categories?.first?.value ?? "General",
                rating: item.iTunes?.iTunesExplicit == "yes" ? "Explicit" : "Clean",
                duration: durationString
            )
        } ?? []
    }
    
    // In PodcastViewModel
    func loadInitialEpisodes() async {
        // Your logic to load episodes
        print("Initial episodes are loaded")
    }

    // Method to clear episodes list
    func clearEpisodes() {
        DispatchQueue.main.async {
            self.episodes = []
        }
    }
    
    func clearEpisodesForSearch() {
            DispatchQueue.main.async {
                self.episodes = []  // Modify to affect the correct episodes array
            }
        }
    
    // Method to load the default episodes for your example podcast
    func loadDefaultEpisodes() async {
        let defaultFeedUrl = "https://thecultcast.libsyn.com/rss"
        guard let url = URL(string: defaultFeedUrl) else {
            print("Invalid URL")
            return
        }

        // Assuming fetchEpisodes is an async method that fetches and updates episodes based on a URL
        await fetchEpisodes(for: Podcast(id: 0, artistName: "", trackName: "", artworkUrl100: "", feedUrl: url.absoluteString))
    }
    
    private func setupSearchSubscriber() {
        searchSubject
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink(receiveValue: { [weak self] query in
                self?.searchPodcasts(with: query)
            })
            .store(in: &cancellables)
    }
    
    func setupSearchPublisher() {
            let publisher = PassthroughSubject<String, Never>()
            searchDelayPublisher = publisher
                .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
                .eraseToAnyPublisher()
            searchDelayPublisher?
                .sink(receiveValue: { [weak self] query in
                    self?.searchPodcasts(with: query)
                }).store(in: &cancellables)
        }
    
    func searchPodcasts(with query: String) {
        searchCancellable?.cancel() // Ensure to cancel the existing request before starting a new one

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            // Immediate clearing of results without delay
            self.updateSearchResults(with: [])
            self.isSearching = false
            return
        }

        self.isSearching = true
        let encodedQuery = trimmedQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://itunes.apple.com/search?media=podcast&term=\(encodedQuery)"
        guard let url = URL(string: urlString) else {
            self.isSearching = false
            return
        }

        searchCancellable = URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .decode(type: SearchResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main) // Decoding and error handling occurs on a background thread, but UI updates are dispatched to the main thread.
            .sink(receiveCompletion: { [weak self] completion in
                switch completion {
                case .finished:
                    // Nothing needed here since the next step will stop the search
                    break
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                    self?.updateSearchResults(with: []) // Update results immediately without delay
                }
                self?.isSearching = false
            }, receiveValue: { [weak self] response in
                self?.updateSearchResults(with: response.results)
            })
    }

    func updateSearchResults(with podcasts: [Podcast]) {
        DispatchQueue.main.async {
            self.searchResults = podcasts
        }
    }
    
    func loadEpisodesForSearchResults(_ podcasts: [Podcast]) async {
        // For each podcast, fetch episodes and update `searchEpisodes`
        for podcast in podcasts.prefix(3) {  // Example: Load episodes for the first three podcasts only
            await fetchEpisodes(for: podcast)
        }
    }
    
    struct SearchResponse: Decodable {
        let results: [Podcast]
    }
    
    // Calculate the width of the text using the NSFont (macOS)
    func widthOfString(_ string: String, font: NSFont) -> CGFloat {
            let attributedString = NSAttributedString(string: string, attributes: [.font: font])
            let size = attributedString.size()
            return size.width
        }
        
        // Function to decide whether the text should scroll
        func shouldScrollText(_ text: String, in size: CGSize) -> Bool {
            let textWidth = widthOfString(text, font: .systemFont(ofSize: NSFont.systemFontSize))
            return textWidth > size.width
        }

    // Update UI based on the current playback time and total duration
    func updatePlaybackUI() {
        guard let currentItem = self.player.currentItem else {
            print("Current item is nil, cannot update UI.")
            return
        }

        let duration = currentItem.duration.seconds
        guard duration.isFinite && !duration.isNaN else {
            print("Duration unavailable or infinite, cannot update UI.")
            return
        }

        let currentTime = self.player.currentTime().seconds
        let progress = currentTime / duration // Calculate the progress as a fraction

        DispatchQueue.main.async {
            // Update the time displays
            self.currentTimeDisplay = self.formatTime(seconds: currentTime)
            self.remainingTimeDisplay = self.formatTime(seconds: max(0, duration - currentTime))

            // Only update the uiPlaybackProgress if the user is not interacting with the progress bar
            if !self.isUserInteractingWithProgressBar {
                self.uiPlaybackProgress = progress
            }
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
    
    @MainActor // Use this if only specific functions need to be on the main thread
        private func preparePlayer(with url: URL) {
            let playerItem = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: playerItem)

            playerItemObserver?.invalidate()

            playerItemObserver = playerItem.observe(\.status, options: [.new, .old]) { [weak self] item, change in
                DispatchQueue.main.async { [weak self] in
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
        if let currentEpisodeAsset = player.currentItem?.asset as? AVURLAsset,
               currentEpisodeAsset.url == episode.mediaURL {
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
            // Handle new episode case and ensure mediaURL is valid
            if let mediaURL = episode.mediaURL {
                // Here, we handle the case where a new episode is selected, and the user hits the pause button.
                if player.rate != 0 {
                    // Pause the current playback if something is playing
                    player.pause()
                    isPlaying = false
                    print("⏸ Playback paused for the currently playing episode.")
                } else {
                    // Prepare the new episode for playback without auto-playing
                    preparePlayer(with: mediaURL)
                    print("🔊 Player prepared with \(episode.title).")
                }
            } else {
                print("⚠️ Episode \(episode.title) does not have a valid media URL.")
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
        guard let duration = player.currentItem?.duration, duration.isNumeric else { return }
        let newTime = CMTimeAdd(currentTime, CMTimeMakeWithSeconds(seconds, preferredTimescale: Int32(NSEC_PER_SEC)))

        player.seek(to: newTime) { [weak self] _ in
            // Ensure updatePlaybackUI() is called on the main thread
            DispatchQueue.main.async {
                self?.updatePlaybackUI()
            }
        }
    }

    func skipBackward(seconds: Double) {
        let currentTime = player.currentTime()
        guard let duration = player.currentItem?.duration, duration.isNumeric else { return }
        let newTime = CMTimeSubtract(currentTime, CMTimeMakeWithSeconds(seconds, preferredTimescale: Int32(NSEC_PER_SEC)))

        player.seek(to: newTime) { [weak self] _ in
            // Ensure updatePlaybackUI() is called on the main thread
            DispatchQueue.main.async {
                self?.updatePlaybackUI()
            }
        }
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
    
    func fetchEpisodes(for podcast: Podcast) async {
        guard let url = URL(string: podcast.feedUrl) else {
            print("Invalid feed URL for podcast: \(podcast.trackName)")
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

        // Wrap the asynchronous operation in an async closure to use 'await'
        await withCheckedContinuation { continuation in
            let parser = FeedParser(URL: url)
            parser.parseAsync(queue: DispatchQueue.global(qos: .userInitiated)) { [weak self] result in
                switch result {
                case .success(let feed):
                    // Extract the RSSFeed from the Feed enum using pattern matching.
                    if let rssFeed = feed.rssFeed {
                        let episodes = self?.parseEpisodes(from: rssFeed, using: dateFormatter) ?? []
                        DispatchQueue.main.async {
                            // Make sure you're updating the episodes and podcast details on the main thread because they're @Published properties.
                            self?.episodes = episodes
                            self?.updatePodcastDetails(from: rssFeed) // Include this line to update podcast details
                            continuation.resume()
                        }
                    } else {
                        DispatchQueue.main.async {
                            print("The feed is not an RSS feed.")
                            // Handle the case where the feed is not an RSS feed.
                            continuation.resume()
                        }
                    }
                case .failure(let error):
                    DispatchQueue.main.async {
                        self?.episodes = []
                        print("Error parsing feed: \(error.localizedDescription)")
                        // Update UI to show an error message or state.
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func parseEpisodes(from rssFeed: FeedKit.RSSFeed, using dateFormatter: DateFormatter) -> [Episode] {
        return rssFeed.items?.compactMap { item -> Episode? in
            guard let title = item.title,
                  let pubDate = item.pubDate,
                  let enclosure = item.enclosure,
                  let enclosureUrl = enclosure.attributes?.url, // Now using the `url` property of `attributes`
                  let episodeUrl = URL(string: enclosureUrl) else { // Now using the unwrapped `enclosureUrl`
                return nil
            }

            let rawDescription = item.description ?? "No description available"
            let pubDateString = dateFormatter.string(from: pubDate)
            let cleanDescription = rawDescription.simplifiedHTML().fixApostrophes()
            let duration = item.iTunes?.iTunesDuration.map { interval -> String in
                return stringFromTimeInterval(interval: interval)
            } ?? "Unknown Duration"

            return Episode(
                id: UUID(),
                title: title,
                link: enclosureUrl, // Directly using the unwrapped `enclosureUrl`
                description: cleanDescription,
                mediaURL: episodeUrl,
                date: pubDateString,
                author: item.iTunes?.iTunesAuthor ?? "Unknown Author",
                website: URL(string: item.link ?? ""),
                category: item.categories?.first?.value,
                rating: item.iTunes?.iTunesExplicit == "yes" ? "Explicit" : "Clean",
                size: enclosure.attributes?.length ?? 0, // Using the `length` property of `attributes`
                duration: duration
            )
        } ?? []
    }

    private func updatePodcastDetails(from rssFeed: FeedKit.RSSFeed) {
        self.podcastTitle = rssFeed.title ?? "Unknown Title"
        self.podcastImageUrl = URL(string: rssFeed.image?.url ?? "")
    }

    private func updateEpisodes(_ episodes: [Episode]) {
        self.episodes = episodes
    }
    
    func stringFromTimeInterval(interval: TimeInterval) -> String {
        let interval = Int(interval)
        let hours = interval / 3600
        let minutes = (interval % 3600) / 60
        let seconds = interval % 60
        if hours > 0 {
            return String(format: "%d hours %d minutes %d seconds", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%d minutes %d seconds", minutes, seconds)
        } else {
            return String(format: "%d seconds", seconds)
        }
    }

    @MainActor
    func userDidEndInteracting(progress: Double) async {
        // Assuming seekToProgress is an async function
        await seekToProgress(progress)
        // Additional logic...
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
        // Ensure any existing observer is removed
        if let timeObserverToken = timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
        }

        let interval = CMTime(seconds: 1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            guard let self = self else { return } // Safely unwrap weak self

            Task { @MainActor in  // Ensure execution on the main actor
                self.updatePlaybackUI()
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
            // Configure MediaPlayer volume, audio session, etc.
        mediaPlayer.player.volume = 0.25
            print("MediaPlayer volume adjusted and configured.")
            
            // Additional MediaPlayer setup if required
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
    func loadEpisodes(for podcast: Podcast) {
            guard let url = URL(string: podcast.feedUrl) else {
                print("Invalid URL")
                return
            }

            // Reset cancellation flag at the start
            isParsingCancelled = false

            let parser = FeedParser(URL: url)
            parser.parseAsync(queue: DispatchQueue.global(qos: .background)) { [weak self] result in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    if self.isParsingCancelled {
                        print("Parsing was cancelled or timed out.")
                        return
                    }

                    switch result {
                    case .success(let feed):
                        self.episodes = feed.rssFeed?.items?.compactMap { item in
                            Episode(
                                title: item.title ?? "No title",
                                link: item.link ?? "",
                                description: item.description ?? "",
                                mediaURL: URL(string: item.enclosure?.attributes?.url ?? "https://example.com") ?? URL(string: "https://example.com")!,
                                date: item.pubDate?.formattedToString() ?? "Unknown date",
                                author: item.author ?? "Unknown author",
                                category: item.categories?.first?.value ?? "No category",
                                rating: "G",
                                duration: self.formatDuration(from: item.iTunes?.iTunesDuration)
                            )
                        } ?? []
                        print("Episodes loaded: \(self.episodes.count)")
                    case .failure(let error):
                        print("Failed to parse feed: \(error.localizedDescription)")
                    }
                }
            }

            // Setup a timeout to set the cancellation flag
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.isParsingCancelled = true
            }
        }
    
    private func parseFeedData(_ data: Data) -> [Episode] {
        // Assuming parsing logic here, which converts data to episodes
        let episodes = [Episode]()

        // Since we're not modifying `episodes` after its declaration,
        // we declare it as 'let'. If you later add code that modifies it,
        // you'll need to change it back to 'var'.

        // Parsing logic to convert 'data' into 'episodes'
        // For example purposes, let's assume you populate it like this:
        // episodes.append(Episode(title: "Example", description: "Example Description"))

        return episodes
    }
    
    func formatDuration(from timeInterval: TimeInterval?) -> String {
        guard let interval = timeInterval else {
            return "Unknown duration"
        }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.hour, .minute, .second]
        return formatter.string(from: interval) ?? "Unknown duration"
    }

    func adjustVolume(to newVolume: Float) {
            player.volume = newVolume
            print("Volume adjusted to \(newVolume)")
        }
    
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
