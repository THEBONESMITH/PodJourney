//
//  PodcastRowView.swift
//  PodJourney
//
//  Created by . . on 15/04/2024.
//

import Foundation
import SwiftUI

// Simplified interaction inside PodcastRowView
struct PodcastRowView: View {
    let podcast: Podcast
    @Binding var selectedPodcast: Podcast?
    @EnvironmentObject var viewModel: PodcastViewModel

    @State private var isHovering = false

    // Define colors within the struct
    private let highlightColor = Color(red: 27 / 255.0, green: 84 / 255.0, blue: 199 / 255.0)
    private let hoverColor = Color.gray.opacity(0.2)

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
            .background(RoundedRectangle(cornerRadius: 8).fill(selectedPodcast?.id == podcast.id ? highlightColor : (isHovering ? hoverColor : Color.clear)))
            .cornerRadius(8)
            .onTapGesture {
                self.selectedPodcast = podcast
                // Use Task.init to handle asynchronous operations
                Task {
                    await viewModel.loadEpisodes(for: podcast, isForSearch: false)
                }
            }
            .onHover { hover in
                self.isHovering = hover
            }
        }
        .frame(height: 112) // Fixed height for the entire row
    }
}
