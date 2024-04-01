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
    @State private var showingSearch = false
    @State private var showingEpisodeDetail = false
    @State private var selectedEpisode: Episode? // Holds the selected episode for details
    private let seekPublisher = PassthroughSubject<Double, Never>()
    private var cancellables: Set<AnyCancellable> = []
    var onSeekEnd: ((Double) -> Void)? = nil
    @Environment(\.scenePhase) private var scenePhase
    
    let customBlue = Color(red: 25 / 255.0, green: 79 / 255.0, blue: 189 / 255.0)
    
    // Define the body property of a SwiftUI View
    var body: some View {
        // Button("Play Audio") {
                    // viewModel.playSampleAudio()
                // }
        HStack { // Start of the main horizontal layout
            // MARK: - Sidebar
            VStack {
                if showingSearch {
                    // MARK: - Back Button (when search is active)
                    Button(action: {
                        self.showingSearch.toggle()
                        // Simulate tab press after a delay
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
                    .buttonStyle(PlainButtonStyle()) // Make the button's background transparent
                } else {
                    // MARK: - Search Button (default state)
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
                    .buttonStyle(PlainButtonStyle()) // Make the button's background transparent
                }
                Spacer()
            }
            .frame(width: 90)
            .background(Color.gray.opacity(0)) // Sidebar background color
            
            Divider() // Separator between the sidebar and main content
            
            // MARK: - Main Content Area
            VStack {
                HStack { // This HStack contains the podcast image/title on the left side and content area on the right
                    if !showingSearch { // Only show the podcast image and title if the search view is not active
                        podcastImageAndTitleView
                            .frame(width: 300)
                        
                        Divider()
                    }
                    
                    VStack { // This VStack will contain the search view, episode details, or the episodes list
                            if showingSearch {
                                // MARK: - Search View (when search is active)
                                SearchView(showingSearch: $showingSearch, viewModel: viewModel)
                                    .frame(maxWidth: .infinity,          maxHeight: .infinity)
                            } else if showingEpisodeDetail, let episode = selectedEpisode {
                                // MARK: - Episode Details View with Back Button
                                VStack(alignment: .leading) {
                                    Button(action: {
                                        self.showingEpisodeDetail = false
                                        // Add simulated tab press immediately after toggling the detail view
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            simulateTabPress()
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: "chevron.backward")
                                                .resizable()
                                                .scaledToFit()
                                                .foregroundColor(.gray)
                                                .frame(width: 30, height: 30) // Adjust for larger button
                                                .padding(.top, 25) // Increase the top padding to move the button down
                                                .padding(.leading)
                                        }
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .padding(.leading, 5) // Adjust padding as needed to position the back button
                                    
                                    EpisodeDetailSubView(episode: episode) // Display episode details
                                        .padding(.leading)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            } else {
                                // MARK: - Episodes List View (default state for main content area)
                                ScrollView {
                                    LazyVStack(spacing: 0) {
                                        ForEach(viewModel.episodes.indices, id: \.self) { index in
                                            EpisodeRowView(
                                                episode: viewModel.episodes[index],
                                                selectedEpisode: $selectedEpisode,
                                                showingEpisodeDetail: $showingEpisodeDetail,
                                                onDoubleTap: {
                                                    // Implementation for double-tap action
                                                    // Likely you want to play the episode here, similar to:
                                                    // viewModel.onEpisodeDoubleClicked(viewModel.episodes[index])
                                                },
                                                onPlay: {
                                                    // Placeholder action for onPlay, does nothing for now
                                                    // Adjust this based on how you want to handle play actions from this context
                                                },
                                                viewModel: viewModel // Make sure to pass the viewModel here
                                            )
                                            
                                            // Only add a divider if it's not the last item
                                            if index < viewModel.episodes.count - 1 {
                                                // Wrapping CustomDivider in a VStack and applying horizontal padding
                                                VStack {
                                                    CustomDivider(color: Color.gray.opacity(0.3), thickness: 1)
                                                }
                                                .padding(.horizontal, 8) // Adjust this value to control the divider's length
                                            }
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity) // Ensure the ScrollView takes up the full available width
                                
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure VStack takes up all available space
                        .background(FocusableView()) // Background of the content area
                    }
                Spacer()
                
                // MARK: - Playback Controls (Always Visible, below the main content)
                VStack {
                    HStack {
                        Spacer(minLength: 45)
                        
                        Text(viewModel.currentTimeDisplay)
                            .frame(width: 80, alignment: .trailing)
                        
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
                        .frame(width: 200, height: 10)
                        
                        Text(viewModel.remainingTimeDisplay)
                            .frame(width: 80, alignment: .leading)
                        
                        Spacer()
                        
                        VolumeSlider(volume: $volume, onVolumeChange: { newVolume in
                                    viewModel.adjustVolume(to: Float(newVolume))
                                })
                                .frame(width: 100)
                                .padding(.top, 20)
                                .offset(x: -10, y: -8)
                                .onAppear {
                                    // Adjust the actual volume to match the UI's default when ContentView appears
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
                    // Any post-fetch logic should go here, after the 'await' call
                    // For example, if you need to update the UI or process episodes further:
                    // self.updateUIAfterFetchingEpisodes()
                }
            }
            .onChange(of: scenePhase, initial: false) { _, newPhase in
                // Handling app state changes
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
        @State private var searchText = ""
        @ObservedObject var viewModel: PodcastViewModel

        var body: some View {
                VStack {
                    HStack {
                        TextField("Search...", text: $searchText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(maxWidth: 200) // Adjust this value as needed
                            .padding(.leading, 10) // Match this padding with the back button's horizontal padding to align them
                            .onSubmit { // Call search when the user submits the text
                                viewModel.searchPodcasts(with: searchText)
                            }
                        Spacer() // This will push the TextField to the left
                    }
                    .padding(.top, 25) // Adjust top padding to move the search bar up

                    Spacer() // This will push all content to the top

                    // The rest of your view content here
                }
                .padding(.horizontal) // Add horizontal padding to the VStack if needed
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
                    }

                    Spacer()

                    if isHovering {
                        VStack {
                            playButton.padding(.top, 2)
                            Spacer()
                        }
                        .transition(.opacity)
                        .animation(.easeInOut, value: isHovering)
                    }

                    VStack {
                        Spacer()
                        infoButton.padding(.bottom, 2)
                    }
                }
                .padding(.vertical, 4)

                Spacer(minLength: 2)

                HStack {
                    Spacer()
                    Text(Self.formatDate(episode.date))
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.bottom, 8)
                }
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
                    // Replace direct mediaPlayer access with a call to the new ViewModel method
                    Task {
                        viewModel.userRequestsPlayback(for: episode)
                    }
                }
            )
            .onHover { hover in
                self.isHovering = hover
            }
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
        @State private var selectedEpisode: Episode? = nil

        var body: some View {
            Button("Play Episode") {
                print("Play Episode button pressed for episode: \(selectedEpisode?.title ?? "N/A")")
                if let episode = selectedEpisode {
                    Task {
                        await viewModel.prepareAndPlayEpisode(episode, autoPlay: false)
                    }
                }
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
