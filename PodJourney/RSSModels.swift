//
//  RSSModels.swift
//  PodJourney
//
//  Created by . . on 28/03/2024.
//

import Foundation

struct RSSFeed: Decodable {
    var items: [RSSItem]
}

struct RSSItem: Decodable {
    var title: String
    
    enum CodingKeys: String, CodingKey {
        case title = "title"
    }
}
