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
    let artworkUrl100: String // URL to the artwork image
    
    // iTunes Search API uses "trackId" as the unique identifier for each item
    enum CodingKeys: String, CodingKey {
        case id = "trackId"
        case artistName
        case trackName
        case artworkUrl100
    }
}
