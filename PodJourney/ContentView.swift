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
                        self.showingSearch.toggle()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            simulateTabPress()
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
                        self.showingSearch.toggle()
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
                            HStack { // This HStack contains the search results and the custom list
                                SearchView(showingSearch: $showingSearch, selectedPodcast: $selectedPodcast)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                
                                Divider() // Vertical divider between search results and the custom list
                                
                                // Custom List appears to the right when search is active
                                VStack {
                                    Text("Episodes")
                                        .font(.headline)
                                        .padding()
                                    
                                    ScrollView {
                                        VStack(spacing: 0) {
                                            if let podcast = selectedPodcast {
                                                ForEach(viewModel.episodes, id: \.id) { episode in
                                                    EpisodeRowView(
                                                        episode: Episode(
                                                            title: episode.title,
                                                            link: episode.link,
                                                            description: episode.description.simplifiedHTML(), // HTML stripped description
                                                            mediaURL: episode.mediaURL,
                                                            date: episode.date,
                                                            duration: episode.duration
                                                            // ... add other properties as needed
                                                        ),
                                                        selectedEpisode: .constant(nil),
                                                        showingEpisodeDetail: .constant(false),
                                                        onDoubleTap: { /* Implement double tap action if needed */ },
                                                        onPlay: { /* Implement play action if needed */ },
                                                        viewModel: viewModel
                                                    )
                                                    .padding(.horizontal, 8) // Horizontal padding for the content
                                                    .padding(.vertical, 4) // Vertical padding for each item

                                                    Divider()
                                                        .background(Color.gray.opacity(0.3))
                                                }
                                            } else {
                                                Text("Select a podcast to view episodes")
                                                    .foregroundColor(.gray)
                                                    .padding(10)
                                                    .frame(maxWidth: .infinity, alignment: .center) // Center the placeholder text
                                            }
                                        }
                                    }
                                    .background(Color("systemGroupedBackground")) // Ensure this color is defined in your Assets
                                    .cornerRadius(10)
                                    .shadow(radius: 5)
                                }
                                .frame(width: 500) // Custom width for the search results panel
                                .padding(.horizontal) // Padding to ensure it doesn't touch the edges of the screen
                            }
 
                        } else if showingEpisodeDetail, let episode = selectedEpisode {
                            VStack(alignment: .leading) {
                                Button(action: {
                                    self.showingEpisodeDetail = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        simulateTabPress()
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "chevron.backward")
                                            .resizable()
                                            .scaledToFit()
                                            .foregroundColor(.gray)
                                            .frame(width: 30, height: 30)
                                            .padding(.top, 25)
                                            .padding(.leading)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding(.leading, 5)
                                
                                EpisodeDetailSubView(episode: episode)
                                    .padding(.leading)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            .onAppear {
                Task {
                    let defaultFeedUrl = "https://thecultcast.libsyn.com/rss"
                    await viewModel.fetchEpisodes(feedUrl: defaultFeedUrl)
                }
            }
            .onChange(of: scenePhase, initial: false) { _, newPhase in
                switch newPhase {
                case .background:
                    viewModel.handleAppMovedToBackground()
                case .inactive, .active:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    // MARK:PodcastFooter
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

        var body: some View {
            VStack {
                TextField("Search...", text: $viewModel.searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: viewModel.searchText) { newValue in
                        viewModel.searchSubject.send(newValue)
                    }

                if viewModel.isSearching {
                    ProgressView("Searching...")
                } else {
                    List(viewModel.searchResults, id: \.id) { podcast in
                        HStack {
                            AsyncImage(url: URL(string: podcast.artworkUrl100)) { image in
                                image.resizable()
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 50, height: 50)
                            .cornerRadius(8)

                            VStack(alignment: .leading) {
                                Text(podcast.trackName)
                                    .fontWeight(.bold)
                                Text(podcast.artistName)
                                    .font(.caption)
                            }
                        }
                        .onTapGesture {
                            self.selectedPodcast = podcast
                            viewModel.loadEpisodes(for: podcast)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        
        var resultsList: some View {
            ScrollView {
                ForEach(viewModel.searchResults, id: \.id) { podcast in
                    PodcastRow(podcast: podcast, selectedPodcast: $selectedPodcast, viewModel: viewModel)
                        .padding(.vertical, 4)
                        .onTapGesture {
                            self.selectedPodcast = podcast
                        }
                }
            }
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
                        
                        VStack {
                            if isHovering {
                                Button(action: {
                                    // Define action for play button
                                }) {
                                    Image(systemName: "play.circle")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 30, height: 30)
                                        .foregroundColor(.white)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                            Spacer()
                        }
                        .padding(.trailing, 20) // Add more padding to push the buttons further to the right
                    }
                    .padding(.horizontal, 8)
                }
                .frame(height: 112)
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
                    .onChange(of: viewModel.searchText) { newValue in
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
    
    struct EpisodesListView: View {
        @EnvironmentObject var viewModel: PodcastViewModel
        @State private var selectedEpisode: Episode?

        var body: some View {
            List(viewModel.episodes, id: \.id) { episode in
                Text(episode.title)
                    .onTapGesture {
                        self.selectedEpisode = episode
                    }
            }
            EpisodeView(selectedEpisode: $selectedEpisode)
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
                    // Implementation for double-tap action
                    // Example: viewModel.onEpisodeDoubleClicked(episode)
                },
                onPlay: {
                    // Implementation for play action
                    // Example: viewModel.playEpisode(episode)
                },
                viewModel: viewModel // Pass the viewModel here
            )
        }
    }

    struct PodcastRowView: View {
        let podcast: Podcast
        @Binding var selectedPodcast: Podcast?
        @EnvironmentObject var viewModel: PodcastViewModel

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

                    Spacer() // Pushes content to the sides
                }
                .padding(.horizontal, 8) // Add horizontal padding to the HStack
            }
            .frame(height: 112) // Fixed height for the entire row
            .background(RoundedRectangle(cornerRadius: 8).fill(selectedPodcast?.id == podcast.id ? highlightColor : (isHovering ? hoverColor : Color.clear)))
            .cornerRadius(8)
            .onTapGesture {
                self.selectedPodcast = podcast
                viewModel.loadEpisodes(for: podcast)
            }
            .onHover { hover in
                self.isHovering = hover
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
