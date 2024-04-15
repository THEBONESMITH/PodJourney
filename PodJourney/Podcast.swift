//
//  Podcast.swift
//  PodJourney
//
//  Created by . . on 28/03/2024.
//

import Foundation
import SwiftUI

struct Podcast: Identifiable, Decodable {
    let id: Int
    let artistName: String
    let trackName: String
    let artworkUrl100: String  // URL to the artwork image
    let feedUrl: String        // URL to the RSS feed

    enum CodingKeys: String, CodingKey {
        case id = "trackId"
        case artistName
        case trackName
        case artworkUrl100
        case feedUrl
    }
}
