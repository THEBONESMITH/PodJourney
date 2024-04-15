//
//  NewContentView.swift
//  PodJourney
//
//  Created by . . on 15/04/2024.
//

import Foundation
import SwiftUI
import Combine

struct NewContentView: View {
    @EnvironmentObject var viewModel: PodcastViewModel

    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(viewModel.podcasts, id: \.id) { podcast in
                    VStack(alignment: .leading) {
                        Text(podcast.trackName)
                            .font(.headline)  // Make sure this displays correctly
                        Text(podcast.artistName)
                            .font(.subheadline)  // Confirm this displays correctly
                        // Check if images are loading properly
                        if let imageUrl = URL(string: podcast.artworkUrl100) {
                            AsyncImage(url: imageUrl) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().aspectRatio(contentMode: .fit)
                                        .frame(width: 100, height: 100)
                                case .failure(_):
                                    Image(systemName: "photo") // Fallback image
                                case .empty:
                                    ProgressView() // Loader while waiting for the image
                                @unknown default:
                                    EmptyView() // Fallback for unexpected cases
                                }
                            }
                        } else {
                            Text("Invalid image URL") // Debug text
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            print("NewContentView appeared with \(viewModel.podcasts.count) podcasts")
        }
    }
}
