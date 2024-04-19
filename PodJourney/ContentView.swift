//
//  ContentView.swift
//  PodJourney
//
//  Created by . . on 28/03/2024.
//

import CoreData
import SwiftUI
import AVFoundation
import Combine
import os

// Extension to parse hex colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

struct PodcastEpisode: Identifiable {
    let id: UUID = UUID()
    let title: String
    let releaseDate: String
}

struct PodcastView: View {
    var podcast: PodcastEpisode
    @Binding var selectedPodcast: PodcastEpisode?
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(podcast.title)
                    .foregroundColor(selectedPodcast?.id == podcast.id ? .white : .black)
                    .padding()
                
                Text(podcast.releaseDate)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            if selectedPodcast?.id == podcast.id {
                Image(systemName: "play.circle.fill")
                    .imageScale(.large)
                    .foregroundColor(.blue)
                
                Button(action: {
                    print("Info for \(podcast.title)")
                }) {
                    Image(systemName: "info.circle")
                        .imageScale(.large)
                }
            }
        }
        .padding(.horizontal)
        .background(selectedPodcast?.id == podcast.id ? Color.blue : Color.clear)
        .onTapGesture {
            self.selectedPodcast = self.podcast
        }
        .onHover { hover in
            if hover {
                self.selectedPodcast = self.podcast
            }
        }
        .cornerRadius(5)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.blue, lineWidth: selectedPodcast?.id == podcast.id ? 2 : 0)
        )
    }
}

struct ContentView: View {
    @EnvironmentObject var viewModel: PodcastViewModel
    @State private var selectedEpisodeID: UUID?
    @State private var totalDuration: Double = 0
    @State private var isUserInteracting = false
    // This needs to be an @State or similar property to be mutable
    @State private var player: AVAudioPlayer?
    @State private var volume: Double = 0.25 // Default volume level
    @ObservedObject var mediaPlayer = MediaPlayer()
    @State private var showingSearch = false
    @State private var showingEpisodeDetail = false
    @State private var selectedEpisode: Episode? // Holds the selected episode for details
    @State private var selectedPodcast: Podcast?
    private let seekPublisher = PassthroughSubject<Double, Never>()
    private var cancellables: Set<AnyCancellable> = []
    var onSeekEnd: ((Double) -> Void)? = nil
    @Environment(\.scenePhase) private var scenePhase
    
    let customBlue = Color(red: 25 / 255.0, green: 79 / 255.0, blue: 189 / 255.0)
    
    // Define the body property of a SwiftUI View
    var body: some View {
            HStack { // Start of the main horizontal layout
                // Sidebar
                VStack {
                    if showingSearch {
                        Button(action: {
                            showingSearch.toggle()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                // Simulated button press effect or other UI-related update
                            }
                        }) {
                            Image(systemName: "chevron.backward")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                                .padding()
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        Button(action: {
                            showingSearch.toggle()
                        }) {
                            Image(systemName: "plus.app")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 50, height: 50)
                                .padding()
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    Spacer()
                }
                .frame(width: 90)
                .background(Color.gray.opacity(0))

                Divider()

                // Main Content Area
                VStack {
                    HStack {
                        if !showingSearch {
                            podcastImageAndTitleView
                                .frame(width: 300)
                            
                            Divider()
                        }
                        
                        VStack {
                            if showingSearch {
                                SearchView(showingSearch: $showingSearch, selectedPodcast: $selectedPodcast)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .onAppear {
                                        Task {
                                            viewModel.clearEpisodes()
                                        }
                                    }
                                    .onDisappear {
                                        Task {
                                            await viewModel.loadDefaultEpisodes()
                                        }
                                    }
                            } else {
                                ScrollView {
                                    LazyVStack(spacing: 0) {
                                        ForEach(viewModel.episodes.indices, id: \.self) { index in
                                            EpisodeRowView(
                                                episode: viewModel.episodes[index],
                                                selectedEpisode: $selectedEpisode,
                                                showingEpisodeDetail: $showingEpisodeDetail,
                                                onDoubleTap: {
                                                    // Placeholder action
                                                },
                                                onPlay: {
                                                    // Placeholder action
                                                },
                                                viewModel: viewModel
                                            )
                                            
                                            if index < viewModel.episodes.count - 1 {
                                                VStack {
                                                    CustomDivider(color: Color.gray.opacity(0.3), thickness: 1)
                                                }
                                                .padding(.horizontal, 8)
                                            }
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .onAppear {
                                    Task {
                                        await viewModel.loadDefaultEpisodes()
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(FocusableView())
                    }
                    Spacer()

                    PodcastFooter()
                        .environmentObject(viewModel)
                        .padding(.horizontal, -266)
                        .padding(.bottom, -45)

                    VStack {
                        HStack {
                            Spacer(minLength: 45)
                            
                            VolumeSlider(volume: $volume, onVolumeChange: { newVolume in
                                viewModel.adjustVolume(to: Float(newVolume))
                            })
                            .frame(width: 100)
                            .padding(.top, 20)
                            .offset(x: -10, y: -8)
                            .onAppear {
                                viewModel.adjustVolume(to: Float(volume))
                            }
                        }
                        
                        HStack {
                            controlButtonsView
                            
                            Color.clear.frame(width: 84, height: 20)
                            
                            Spacer() // Pushes everything to the left
                        }
                    }
                }
                .onChange(of: showingSearch) { oldSearch, newSearch in
                    if newSearch {
                        // Clear episodes when entering search mode
                        viewModel.clearEpisodesForSearch()
                    } else {
                        // Load default episodes when leaving search mode
                        Task {
                            await viewModel.loadDefaultEpisodes()
                        }
                    }
                }
                .onChange(of: selectedPodcast) { oldPodcast, newPodcast in
                    guard let podcast = newPodcast else { return }
                    Task {
                        await viewModel.fetchEpisodes(for: podcast)
                    }
                }
            .onAppear {
                Task {
                    await viewModel.loadInitialEpisodes()
                }
            }
        }
    }
    
    // MARK: - PodcastFooter
    struct PodcastFooter: View {
        @EnvironmentObject var viewModel: PodcastViewModel
        @State private var animateText: Bool = false
        @State private var textOffset: CGFloat = 0
        @State private var animationKey: Int = 0  // New state to force reanimation
        
        private let imageWidth: CGFloat = 80
        private let additionalSpacing: CGFloat = 10
        private let animationDuration: Double = 15.0
        private let footerHeight: CGFloat = 80
        private let footerWidth: CGFloat = 450
        private let footerBackgroundColor = Color(hex: "404040")
        
        private let logger = Logger(subsystem: "com.yourdomain.yourapp", category: "PodcastFooter")
        
        var body: some View {
            HStack(alignment: .top, spacing: 0) {
                // Display chapter art if available, else podcast image
                if let chapterImageUrl = viewModel.currentlyPlaying?.chapterImageUrl {
                    AsyncImage(url: chapterImageUrl) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable()
                        case .failure:
                            Image(systemName: "photo")
                        case .empty:
                            ProgressView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: imageWidth, height: imageWidth)
                    .cornerRadius(5)
                    .padding(.leading, 10)
                } else if let imageUrl = viewModel.podcastImageUrl {
                    AsyncImage(url: imageUrl) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable()
                        case .failure:
                            Image(systemName: "photo")
                        case .empty:
                            ProgressView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: imageWidth, height: imageWidth)
                    .cornerRadius(5)
                    .padding(.leading, 10)
                }
                
                ZStack(alignment: .leading) {
                    footerBackgroundColor
                        .frame(width: footerWidth - imageWidth, height: footerHeight)
                        .cornerRadius(10)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        GeometryReader { geometry in
                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(viewModel.currentlyPlaying?.title ?? "")
                                    .font(.headline)
                                    .lineLimit(1)
                                    .padding(.vertical, 4)
                                    .offset(x: animateText ? -textOffset : 0)
                                    .animation(animateText ? .linear(duration: animationDuration).repeatForever(autoreverses: false) : nil, value: animateText)
                                    .onAppear {
                                        setupTextAnimation(with: geometry.size.width)
                                    }
                                    .onChange(of: viewModel.currentlyPlaying?.title) { _, _ in
                                        setupTextAnimation(with: geometry.size.width)
                                    }
                            }
                            .frame(width: geometry.size.width, alignment: .leading)
                        }
                        
                        Text("\(viewModel.podcastTitle ?? "Unknown Podcast") — \(viewModel.currentlyPlaying?.formattedDate ?? "Unknown Date")")
                            .font(.headline)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .center)
                        
                        VStack(spacing: 4) {
                            HStack {
                                Text(viewModel.currentTimeDisplay)
                                    .font(.caption)
                                    .frame(alignment: .leading)
                                
                                Spacer()
                                
                                Text(viewModel.remainingTimeDisplay)
                                    .font(.caption)
                                    .frame(alignment: .trailing)
                            }
                            
                            CustomProgressBar(
                                progress: $viewModel.uiPlaybackProgress,
                                totalDuration: $viewModel.totalDuration,
                                isUserInteracting: $viewModel.isUserInteracting,
                                onSeek: { newProgress in
                                    Task {
                                        await viewModel.seekToProgress(newProgress)
                                    }
                                },
                                onSeekStart: {
                                    viewModel.userDidStartInteracting()
                                },
                                onSeekEnd: { finalProgress in
                                    Task {
                                        await viewModel.userDidEndInteracting(progress: finalProgress)
                                    }
                                }
                            )
                            .frame(height: 5)
                        }
                    }
                    .padding(.horizontal, additionalSpacing)
                }
                
                Spacer()
            }
            .frame(width: footerWidth, height: footerHeight)
            .background(footerBackgroundColor)
            .cornerRadius(10)
        }
        
        private func setupTextAnimation(with containerWidth: CGFloat) {
                let textWidth = viewModel.widthOfString(viewModel.currentlyPlaying?.title ?? "", font: .systemFont(ofSize: NSFont.systemFontSize))
                if textWidth > containerWidth - (imageWidth + additionalSpacing * 2) {
                    textOffset = textWidth
                    animateText = false  // Stop the current animation
                    logger.log("Preparing to start text animation after delay...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self.animationKey += 1  // Increment to trigger a new animation
                        self.animateText = true
                        self.logger.log("Text animation started.")
                    }
                } else {
                    animateText = false
                }
            }
        }
    
    private func handleVolumeChange(newVolume: Double) {
            viewModel.adjustVolume(to: Float(newVolume))
        }
    
    struct CustomDivider: View {
        var color: Color = .gray
        var thickness: CGFloat = 1

        var body: some View {
            Rectangle()
                .fill(color)
                .frame(height: thickness)
        }
    }

    struct EpisodeDetailSubView: View {
        let episode: Episode

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(episode.title)
                        .font(.title2)
                    
                    // Preprocess the episode's description to simplify HTML content
                    let simplifiedDescription = episode.description.simplifiedHTML()
                    // Split the simplified description into lines for separate Text views
                    let lines = simplifiedDescription.split(separator: "\n", omittingEmptySubsequences: false)

                    ForEach(lines, id: \.self) { line in
                        Text(String(line))
                            .padding(.bottom, line.isEmpty ? 12 : 0) // Add extra padding for paragraphs
                    }
                    
                    Divider()

                    Group {
                        Link(destination: episode.mediaURL) {
                            Text(episode.mediaURL.absoluteString)
                                .foregroundColor(.blue)
                                .underline()
                        }
                        .font(.subheadline)
                        
                        // Use the provided date string and format it
                        Text("Published: \(reformatDateString(episode.date))")
                        
                        if let author = episode.author {
                            Text("Author: \(author)")
                        }
                        if let website = episode.website {
                            Link(destination: website) {
                                Text(website.absoluteString)
                                    .foregroundColor(.blue)
                                    .underline()
                            }
                            .font(.subheadline)
                        }
                        if let category = episode.category {
                            Text("Category: \(category)")
                        }
                        if let rating = episode.rating {
                            Text("Rating: \(rating)")
                        }
                        if let size = episode.size {
                            Text("Size: \(sizeString(size))")
                        }
                    }
                    .font(.subheadline)
                }
                .padding()
            }
        }

        private func reformatDateString(_ dateString: String) -> String {
            let inputFormatter = DateFormatter()
            inputFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            if let date = inputFormatter.date(from: dateString) {
                let outputFormatter = DateFormatter()
                outputFormatter.dateFormat = "EEEE dd MMMM yyyy"
                return outputFormatter.string(from: date)
            }
            return dateString // Return the original string if conversion fails
        }

        private func sizeString(_ size: Int64) -> String {
            let sizeInMB = Double(size) / 1_048_576 // Convert bytes to megabytes
            return String(format: "%.1f MB", sizeInMB)
        }
    }

    private func simulateTabPress() {
            DispatchQueue.main.async {
                if let window = NSApplication.shared.keyWindow {
                    window.selectNextKeyView(nil) // Simulating a tab press
                }
            }
        }
    
    struct SearchView: View {
        @Binding var showingSearch: Bool
        @Binding var selectedPodcast: Podcast?
        @EnvironmentObject var viewModel: PodcastViewModel
        
        var resultsList: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {  // Aligning content to the leading edge
                    ForEach(viewModel.searchResults, id: \.id) { podcast in
                        PodcastRow(podcast: podcast, selectedPodcast: $selectedPodcast, viewModel: viewModel)
                            .padding(.vertical, 4)
                            .onTapGesture {
                                self.selectedPodcast = podcast
                                Task {
                                    await viewModel.fetchEpisodes(for: podcast)
                                }
                            }
                            .background(selectedPodcast?.id == podcast.id ? Color.gray.opacity(0.2) : Color.clear)
                    }
                }
                .padding(.horizontal)  // Adding horizontal padding for better alignment
            }
        }
        
        var body: some View {
            HStack(alignment: .top) { // Aligning content to the top
                VStack(alignment: .leading) { // Aligning content to the leading edge
                    TextField("Search...", text: $viewModel.searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 300) // Set the width of the search field
                        .onChange(of: viewModel.searchText) { _, newValue in
                            viewModel.searchSubject.send(newValue)
                        }
                    
                    if viewModel.isSearching {
                        ProgressView("Searching...")
                    } else {
                        resultsList
                    }
                }
                .padding(.leading) // Ensure everything is aligned to the left

                Spacer() // This pushes all content to the left
                
                // Right side of the HStack, displaying episodes or details
                if let selectedPod = selectedPodcast {
                    EpisodesListView(episodes: viewModel.searchEpisodes)
                        .frame(maxWidth: .infinity)
                        .onAppear {
                            Task {
                                await viewModel.fetchEpisodes(for: selectedPod)
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading) // Maximize width and align content to the left
        }
        
        struct PodcastRow: View {
            let podcast: Podcast
            @Binding var selectedPodcast: Podcast?
            var viewModel: PodcastViewModel
            
            @State private var isHovering = false
            
            let highlightColor = Color(red: 27 / 255.0, green: 84 / 255.0, blue: 199 / 255.0)
            let hoverColor = Color.gray.opacity(0.2)
            
            var body: some View {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        AsyncImage(url: URL(string: podcast.artworkUrl100)) { imagePhase in
                            switch imagePhase {
                            case .success(let image):
                                image.resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 100, height: 100)
                            case .failure(_):
                                Image(systemName: "photo")
                            case .empty:
                                ProgressView()
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(width: 100, height: 100)
                        .cornerRadius(8)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Spacer(minLength: 6)
                            Text(podcast.trackName)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .lineLimit(2)
                            Text(podcast.artistName)
                                .font(.caption)
                                .foregroundColor(.white)
                                .lineLimit(2)
                            Spacer(minLength: 6)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                }
                .frame(height: 112)
                .frame(maxWidth: 300) // Set the maximum width here
                .background(RoundedRectangle(cornerRadius: 8).fill(selectedPodcast?.id == podcast.id ? highlightColor : (isHovering ? hoverColor : Color.clear)))
                .cornerRadius(8)
                .onHover { hover in
                    self.isHovering = hover
                }
            }
        }
    }
    
    struct CustomProgressBar: View {
        @Binding var progress: Double
        @Binding var totalDuration: Double
        @Binding var isUserInteracting: Bool
        var onSeek: (Double) -> Void
        var onSeekStart: (() -> Void)? = nil
        var onSeekEnd: (Double) -> Void

        var body: some View {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().foregroundColor(Color.gray.opacity(0.3))
                    Rectangle().foregroundColor(Color.gray)
                        .frame(width: geometry.size.width * CGFloat(self.progress))
                }
                .cornerRadius(5.0)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let newProgress = min(max(0, Double(value.location.x / geometry.size.width)), 1)
                            print("User is seeking: \(newProgress)")
                            self.onSeekStart?()
                            self.progress = newProgress
                            self.onSeek(newProgress)
                        }
                        .onEnded { value in
                            let finalPosition = value.location.x / geometry.size.width
                            let finalProgress = min(max(0, Double(finalPosition)), 1)
                            print("User ended seeking: \(finalProgress)")
                            self.onSeekEnd(finalProgress)
                        }
                )
            }
            .frame(height: 10)
        }
    }
        
        var duration: String {
            return formatTime(seconds: totalDuration) // Use the local state
        }
        
        func formatTime(seconds: Double) -> String {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute, .second]
            formatter.unitsStyle = .positional
            formatter.zeroFormattingBehavior = .pad
            return formatter.string(from: TimeInterval(seconds)) ?? "00:00"
        }

    
    // Define your controlButtonsView and other views here
    
    var podcastImageAndTitleView: some View {
        VStack {
            if let imageUrl = viewModel.podcastImageUrl {
                AsyncImage(url: imageUrl) { imagePhase in
                    switch imagePhase {
                    case .success(let image):
                        image.resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100)
                    case .failure(_):
                        Image(systemName: "photo")
                    case .empty:
                        ProgressView()
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            Text(viewModel.podcastTitle ?? "Loading Podcast...")
                .font(.title)
                .padding([.top, .leading, .trailing])
        }
    }
    
    struct SearchAndResultsView: View {
        @Binding var selectedPodcast: Podcast?
        @EnvironmentObject var viewModel: PodcastViewModel

        var body: some View {
            VStack {
                TextField("Search...", text: $viewModel.searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: viewModel.searchText) { _, newValue in
                        viewModel.searchPodcasts(with: newValue)
                    }

                if viewModel.isSearching {
                    ProgressView("Searching...")
                } else {
                    List(viewModel.searchResults, id: \.id) { podcast in
                        Text(podcast.trackName)
                            .onTapGesture {
                                self.selectedPodcast = podcast
                                viewModel.loadEpisodes(for: podcast)
                            }
                    }
                }
            }
        }
    }
    
    // MARK - Episodes list in search view
    struct EpisodesListView: View {
        @EnvironmentObject var viewModel: PodcastViewModel
        @State private var selectedEpisode: Episode?
        var episodes: [Episode]

        var body: some View {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.episodes.indices, id: \.self) { index in
                        SearchEpisodeRow(episode: viewModel.episodes[index], selectedEpisode: $selectedEpisode, showingEpisodeDetail: .constant(false), onDoubleTap: {}, onPlay: {
                            // Add your play action here
                        }, viewModel: viewModel)
                        .onTapGesture {
                            self.selectedEpisode = viewModel.episodes[index]
                        }

                        if index < viewModel.episodes.count - 1 {
                            VStack {
                                CustomDivider(color: Color.gray.opacity(0.3), thickness: 1)
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity) // Ensure the ScrollView fills the available horizontal space
            .onAppear {
                Task {
                    await viewModel.loadDefaultEpisodes()
                }
            }
        }
    }

    struct SearchEpisodeRow: View {
        let episode: Episode
        @Binding var selectedEpisode: Episode?
        @Binding var showingEpisodeDetail: Bool
        var onDoubleTap: () -> Void
        var onPlay: () -> Void
        var viewModel: PodcastViewModel

        @State private var isHovering = false
        
        let highlightColor = Color(red: 27 / 255.0, green: 84 / 255.0, blue: 199 / 255.0)
        let hoverColor = Color.gray.opacity(0.2)

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    // Left side content, including title, description, and duration
                    VStack(alignment: .leading, spacing: 4) {
                        Spacer(minLength: 6)
                        Text(episode.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .lineLimit(2)
                        Text(episode.description)
                            .font(.caption)
                            .foregroundColor(.white)
                            .lineLimit(2)
                        Spacer(minLength: 6)
                        Text(parseDuration(duration: episode.duration))
                            .font(.caption)
                            .foregroundColor(.white)
                            .offset(x: 0, y: -5) // Nudge duration up
                    }
                    Spacer() // Pushes content to the sides

                    // Right side content, with play button on top and info button centered
                    VStack {
                        if isHovering {
                            playButton
                                .offset(x: 20, y: 5) // Nudge play button to the right/down
                        }
                        Spacer() // This will dynamically resize

                        infoButton
                            .offset(x: 20, y: -5) // Nudge info button to the right/up

                        Spacer() // This will dynamically resize

                        Text(SearchEpisodeRow.formatDate(episode.date)) // Display formatted date
                            .font(.caption)
                            .foregroundColor(.white)
                            .offset(x: 0, y: -5) // Nudge date up
                    }
                    .padding(.trailing, 0) // Add more padding to push the buttons further to the right
                }
                .padding(.horizontal, 8)
                .frame(height: 112)
                .background(RoundedRectangle(cornerRadius: 8).fill(selectedEpisode?.id == episode.id ? highlightColor : Color.clear))
                .background(isHovering && selectedEpisode?.id != episode.id ? hoverColor : Color.clear)
                .cornerRadius(8)
                .onHover { hover in
                    self.isHovering = hover
                }
            }
        }

        private func parseDuration(duration: String) -> String {
                let components = duration.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
                if components.count == 3 {
                    return String(format: "%d:%02d:%02d", components[0], components[1], components[2])
                } else if components.count == 2 {
                    return String(format: "0:%02d:%02d", components[0], components[1])
                } else if components.count == 1 {
                    return String(format: "0:00:%02d", components[0])
                }
                return "0:00:00" // Default case if parsing fails
            }
        
        private var playButton: some View {
            Button(action: onPlay) {
                Image(systemName: "play")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
            }
            .buttonStyle(BorderlessButtonStyle())
        }

        private var infoButton: some View {
            Button(action: {
                self.selectedEpisode = episode
                self.showingEpisodeDetail = true
            }) {
                Image(systemName: "info.circle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
            }
            .buttonStyle(BorderlessButtonStyle())
        }

        static func formatDate(_ dateString: String) -> String {
            let inputFormatter = DateFormatter()
            inputFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            guard let date = inputFormatter.date(from: dateString) else { return dateString }

            let outputFormatter = DateFormatter()
            outputFormatter.dateFormat = "dd/MM/yyyy"
            return outputFormatter.string(from: date)
        }
    } 
    
    struct EpisodeDetailView: View {
        var episode: Episode

        var body: some View {
            Text(episode.title)
            // Additional details and controls for the episode
        }
    }

    struct DefaultContentView: View {
        var body: some View {
            Text("Select a podcast to start")
        }
    }
    
    var episodesListView: some View {
        List(viewModel.episodes, id: \.id) { episode in
            EpisodeRowView(
                episode: episode,
                selectedEpisode: $selectedEpisode,
                showingEpisodeDetail: $showingEpisodeDetail,
                onDoubleTap: {
                    // This could be where you handle the double tap action, like showing episode details
                    selectedEpisode = episode
                    showingEpisodeDetail = true
                },
                onPlay: {
                    // Here you might want to handle the play action, like playing the episode
                    Task {
                        await viewModel.prepareAndPlayEpisode(episode, autoPlay: true)
                    }
                },
                viewModel: viewModel // Pass the viewModel here
            )
            .padding(.vertical, 4)
            .onTapGesture(count: 2) {
                // Handle double-tap gesture to play the episode
                Task {
                    await viewModel.prepareAndPlayEpisode(episode, autoPlay: true)
                }
            }
            // If you need hover effects on macOS, you can add an .onHover modifier here
            .onTapGesture {
                // Handle single tap gesture to select the episode
                selectedEpisode = episode
            }
        }
    }

    struct EpisodeRowView: View {
        let episode: Episode
        @Binding var selectedEpisode: Episode?
        @Binding var showingEpisodeDetail: Bool
        var onDoubleTap: () -> Void
        var onPlay: () -> Void
        var viewModel: PodcastViewModel

        @State private var isHovering = false

        let highlightColor = Color(red: 27 / 255.0, green: 84 / 255.0, blue: 199 / 255.0)
        let hoverColor = Color.gray.opacity(0.2)

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    // Left side content, including title, description, and duration
                    VStack(alignment: .leading, spacing: 4) {
                        Spacer(minLength: 6)
                        Text(episode.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .lineLimit(2)
                        Text(episode.description)
                            .font(.caption)
                            .foregroundColor(.white)
                            .lineLimit(2)
                        Spacer(minLength: 6)
                        Text(parseDuration(duration: episode.duration))
                            .font(.caption)
                            .foregroundColor(.white)
                            .offset(x: 0, y: -5) // Nudge duration up
                    }
                    Spacer() // Pushes content to the sides

                    // Right side content, with play button on top and info button centered
                    VStack {
                        // Fixed size container for the play button
                        VStack {
                            if isHovering {
                                playButton
                                    .offset(x: 20, y: 0) // Nudge play button to the right
                            }
                        }
                        .frame(height: 30) // Adjust the height as needed for your layout

                        Spacer() // This will dynamically resize

                        infoButton
                            .offset(x: 20, y: -5) // Nudge info button to the right/up

                        Spacer() // This will dynamically resize
                        
                        Text(EpisodeRowView.formatDate(episode.date)) // Display formatted date
                            .font(.caption)
                            .foregroundColor(.white)
                            .offset(x: 0, y: -5) // Nudge date up
                    }
                    .padding(.trailing, 0) // Add more padding to push the buttons further to the right
                }
                .padding(.horizontal, 8) // Add horizontal padding to the HStack
            }
            .frame(height: 112) // Fixed height for the entire row
            .background(RoundedRectangle(cornerRadius: 8).fill(selectedEpisode?.id == episode.id ? highlightColor : Color.clear))
            .background(isHovering && selectedEpisode?.id != episode.id ? hoverColor : Color.clear)
            .cornerRadius(8)
            .onTapGesture {
                print("Tap recognized, episode selected: \(episode.title)")
                self.selectedEpisode = episode
                Task {
                    viewModel.selectEpisode(episode)
                }
            }
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    Task {
                        viewModel.userRequestsPlayback(for: episode)
                    }
                }
            )
            .onHover { hover in
                self.isHovering = hover
            }
        }

        private func parseDuration(duration: String) -> String {
            let components = duration.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
            if components.count == 3 {
                return String(format: "%d:%02d:%02d", components[0], components[1], components[2])
            } else if components.count == 2 {
                return String(format: "0:%02d:%02d", components[0], components[1])
            } else if components.count == 1 {
                return String(format: "0:00:%02d", components[0])
            }
            return "0:00:00" // Default case if parsing fails
        }

        private var playButton: some View {
            Button(action: onPlay) {
                Image(systemName: "play")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
            }
            .buttonStyle(BorderlessButtonStyle())
        }

        private var infoButton: some View {
            Button(action: {
                self.selectedEpisode = episode
                self.showingEpisodeDetail = true
            }) {
                Image(systemName: "info.circle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        
        static func formatDate(_ dateString: String) -> String {
                let inputFormatter = DateFormatter()
                inputFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
                guard let date = inputFormatter.date(from: dateString) else { return dateString }
                
                let outputFormatter = DateFormatter()
                outputFormatter.dateFormat = "dd/MM/yyyy"
                return outputFormatter.string(from: date)
            }
    }
    
    /*
    @ViewBuilder
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(selectedEpisode?.id == episode.id ? customBlue : Color.clear)
    }
    */
    
    var controlButtonsView: some View {
            HStack {
                Button(action: {
                    viewModel.skipBackward(seconds: 10)
                }) {
                    Image(systemName: "gobackward.10")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                }
                .padding()
                .disabled(!viewModel.isEpisodeLoaded) // Disable the button if no episode is selected
                
                Button(action: {
                    viewModel.togglePlayPause()
                }) {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                }
                .padding()
                .disabled(!viewModel.isEpisodeLoaded) // Disable if no episode is loaded and ready to play
                
                Button(action: {
                    viewModel.skipForward(seconds: 30)
                }) {
                    Image(systemName: "goforward.30")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                }
                .padding()
                .disabled(!viewModel.isEpisodeLoaded) // And disable if no episode is selected
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(PlainButtonStyle())
        }
    
    // Define your EpisodeRow view without needing to check isSelected state
    struct EpisodeRow: View {
        let episode: Episode // Your Episode model
        @State private var isHovering = false
        var playEpisode: (Episode) -> Void // Closure to play the episode

        var body: some View {
            HStack {
                Text(episode.title)
                    .fontWeight(.bold)

                Spacer()

                if isHovering {
                    Button(action: {
                        playEpisode(episode)
                    }) {
                        Image(systemName: "play")
                            .foregroundColor(.primary)
                            .imageScale(.large)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }
            .padding()
            .background(isHovering ? Color.gray.opacity(0.1) : Color.clear) // Visual cue for hover state
            .onHover { hovering in
                self.isHovering = hovering
            }
        }
    }
        
    struct PlayPauseButton: View {
        @ObservedObject var viewModel: PodcastViewModel
        
        var body: some View {
            Button(action: {
                // Wrap the async call in a Task
                Task {
                    await viewModel.startPlaybackManually()
                }
            }) {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 28)
            }
            .padding()
        }
    }
    
    /*
    struct EpisodeView: View {
        @EnvironmentObject var viewModel: PodcastViewModel
        @Binding var selectedEpisode: Episode?

        var body: some View {
            if let episode = selectedEpisode {
                Button(viewModel.isPlaying && viewModel.currentlyPlaying?.id == episode.id ? "Pause Episode" : "Play Episode") {
                    if viewModel.isPlaying && viewModel.currentlyPlaying?.id == episode.id {
                        viewModel.pausePlayback()
                    } else {
                        Task {
                            await viewModel.prepareAndPlayEpisode(episode, autoPlay: true)
                        }
                    }
                }
            } else {
                Text("Select an episode to play")
            }
        }
    }
    */
    
    struct EpisodeProgressBar: View {
        @ObservedObject var viewModel: PodcastViewModel
        
        var body: some View {
            ProgressBar(
                progress: $viewModel.uiPlaybackProgress,
                maxValue: viewModel.totalDuration,
                onSeek: { newProgress in
                    Task {
                        await viewModel.seekToProgress(newProgress)
                    }
                }
            )
            .frame(height: 4) // Control the height of the progress bar
            .padding(.horizontal) // Add some horizontal padding if needed
        }
    }
}
