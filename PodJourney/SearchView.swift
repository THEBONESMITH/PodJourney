//
//  SearchView.swift
//  PodJourney
//
//  Created by . . on 25/04/2024.
//

import Foundation
import SwiftUI

struct SearchView: View {
    @Binding var showingSearch: Bool
    @Binding var selectedPodcast: Podcast?
    @Binding var selectedEpisode: Episode?
    @Binding var episodeDetailVisible: Bool
    @EnvironmentObject var viewModel: PodcastViewModel

    var resultsList: some View {
        ScrollView {
            VStack(alignment: .leading) {
                ForEach(viewModel.searchResults, id: \.id) { podcast in
                    PodcastRow(
                        podcast: podcast,
                        selectedPodcast: $selectedPodcast,
                        viewModel: viewModel
                    )
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
            .padding(.horizontal)
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                TextField("Search...", text: $viewModel.searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 300)
                    .onChange(of: viewModel.searchText) { _, newValue in
                        viewModel.searchSubject.send(newValue)
                    }

                if viewModel.isSearching {
                    ProgressView("Searching...")
                } else {
                    resultsList // Ensure a valid view is returned
                }
            }
            .padding(.leading)

            Spacer()

            if let selectedPod = selectedPodcast {
                VStack {
                    if episodeDetailVisible, let selectedEpisode = selectedEpisode {
                        CustomEpisodeDetailSubView(episode: selectedEpisode) // Ensure this is a valid view
                    } else {
                        EpisodesListView(episodes: viewModel.searchEpisodes) // Default to this view
                            .frame(maxWidth: .infinity)
                            .onAppear {
                                Task {
                                    await viewModel.fetchEpisodes(for: selectedPod)
                                }
                            }
                    }
                }
            } else {
                Text("No podcast selected.") // Ensure fallback view for other branches
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
    
    struct CustomEpisodeDetailSubView: View {
        let episode: Episode

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom Episode Detail for: \(episode.title)") // Customise as needed
                        .font(.title2)
                    
                    Text("Description: \(episode.description.simplifiedHTML())")
                        .padding(.bottom)
                    
                    // Add more custom elements or data here, based on your requirements
                }
                .padding()
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

// MARK: - Episodes list in search view
struct EpisodesListView: View {
    @EnvironmentObject var viewModel: PodcastViewModel
    @State private var selectedEpisode: Episode?
    @State private var showingEpisodeDetail = false
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
                            ContentView.CustomDivider(color: Color.gray.opacity(0.3), thickness: 1)
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
    @State private var dateLabelAdjusted: Bool = false
    @State private var episodeDetailVisible = false
    
    let highlightColor = Color(red: 27 / 255.0, green: 84 / 255.0, blue: 199 / 255.0)
    let hoverColor = Color.gray.opacity(0.2)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                // Left side: Displays the episode's title, description, and duration.
                VStack(alignment: .leading, spacing: 4) {
                    Text(episode.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text(episode.description)
                        .font(.caption)
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text(parseDuration(duration: episode.duration))
                        .font(.caption)
                        .foregroundColor(.white)
                        .offset(x: durationXOffset(), y: durationYOffset())
                }
                Spacer()

                // Right side content with ZStack to overlay play button
                ZStack(alignment: .trailing) {
                    VStack(alignment: .trailing) {
                        Spacer()
                        infoButton
                            .offset(x: infoButtonXOffset(), y: infoButtonYOffset())
                        Text(ContentView.formatDate(episode.date))
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.top, 10)
                            .offset(x: dateXOffset(), y: dateYOffset())
                    }
                    
                    // Play button appears at the top when hovering
                    if isHovering {
                        playButton
                            .offset(x: playButtonXOffset(), y: playButtonYOffset())
                            .transition(.move(edge: .trailing))
                    }
                }
                .padding(.trailing, 10)
            }
            .padding(.horizontal, 8)
            .frame(height: 112)
            .background(RoundedRectangle(cornerRadius: 8).fill(selectedEpisode?.id == episode.id ? highlightColor : Color.clear))
            .background(isHovering && selectedEpisode?.id != episode.id ? hoverColor : Color.clear)
            .cornerRadius(8)
            .onHover { hover in
                self.isHovering = hover
            }
            .onAppear {
                self.dateLabelAdjusted = self.isDateLabelAdjusted(dateString: episode.date)
            }
            .onChange(of: episode.date) { _, newDate in
                self.dateLabelAdjusted = self.isDateLabelAdjusted(dateString: newDate)
            }
            .onTapGesture {
                self.selectedEpisode = episode
                Task {
                    viewModel.selectEpisode(episode)
                }
            }
        }
    }

    private func isDateLabelAdjusted(dateString: String) -> Bool {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        if let date = dateFormatter.date(from: dateString) {
            return ContentView.isDateWithinLastSixDays(date) || Calendar.current.isDateInToday(date)
        }
        return false
    }

    // Offset functions for each UI element:
    private func durationXOffset() -> CGFloat {
        return dateLabelAdjusted ? 0 : 0
    }
    private func durationYOffset() -> CGFloat {
        return dateLabelAdjusted ? 12 : 12
    }
    private func playButtonXOffset() -> CGFloat {
        return dateLabelAdjusted ? 3 : 3
        }
    private func playButtonYOffset() -> CGFloat {
        return dateLabelAdjusted ? -40 : -40
        }
    private func infoButtonXOffset() -> CGFloat {
        return dateLabelAdjusted ? 2 : 2
    }
    private func infoButtonYOffset() -> CGFloat {
        return dateLabelAdjusted ? -15 : -15
    }
    private func dateXOffset() -> CGFloat {
        return dateLabelAdjusted ? 3 : 3
    }
    private func dateYOffset() -> CGFloat {
        return dateLabelAdjusted ? -5 : -5
    }

    private func parseDuration(duration: String) -> String {
        // Correctly using components(separatedBy:) method
        let components = duration.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
        if components.count == 3 {
            return String(format: "%d:%02d:%02d", components[0], components[1], components[2])
        } else if components.count == 2 {
            return String(format: "0:%02d:%02d", components[0], components[1])
        } else if components.count == 1 {
            return String(format: "0:00:%02d", components[0])
        }
        return "0:00:00"  // Default case if parsing fails
    }

    private var playButton: some View {
        Button(action: onPlay) {
            Image(systemName: "play")
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var infoButton: some View {
        Button(action: {
            print("Info button pressed for episode: \(episode.title)")
            self.selectedEpisode = episode
            self.episodeDetailVisible = true
            print("episodeDetailVisible set to: \(self.episodeDetailVisible)") // Additional print statement
        }) {
            Image(systemName: "info.circle")
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
                .foregroundColor(.primary) // Ensure correct foreground colour
        }
        .buttonStyle(PlainButtonStyle()) // Prevents visual change on click
    }

    static func formatDate(_ dateString: String) -> String {
            let inputFormatter = DateFormatter()
            inputFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            
            guard let date = inputFormatter.date(from: dateString) else { return dateString }
            
            let calendar = Calendar.current
            if calendar.isDateInToday(date) {
                return "Today"
            } else if isDateWithinLastSixDays(date) {
                let dayFormatter = DateFormatter()
                dayFormatter.dateFormat = "EEEE" // Day of the week
                return dayFormatter.string(from: date)
            } else {
                let outputFormatter = DateFormatter()
                outputFormatter.dateFormat = "dd/MM/yyyy"
                return outputFormatter.string(from: date)
            }
        }

        private static func isDateWithinLastSixDays(_ date: Date) -> Bool {
            let calendar = Calendar.current
            let now = Date()
            let sixDaysAgo = calendar.date(byAdding: .day, value: -6, to: now)!
            return date > sixDaysAgo && !calendar.isDateInToday(date)
        }
}
