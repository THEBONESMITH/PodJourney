//
//  EpisodeDetailView.swift
//  PodJourney
//
//  Created by . . on 28/03/2024.
//

import Foundation
import SwiftUI

struct Episode: Identifiable, Hashable {
    let id: UUID
    let url: URL
    var title: String
    var link: String
    var description: String // Plain text description
    var attributedDescription: AttributedString? // Optional attributed string for rich text
    var mediaURL: URL?
    var date: String
    var author: String?
    var website: URL?
    var category: String?
    var rating: String?
    var size: Int64?
    var duration: String
    var chapterImageUrl: URL?
    
    init(id: UUID = UUID(), title: String, link: String, description: String, attributedDescription: AttributedString? = nil, mediaURL: URL, date: String, author: String? = nil, website: URL? = nil, category: String? = nil, rating: String? = nil, size: Int64? = nil, duration: String, chapterImageUrl: URL? = nil) {
        self.id = id
        self.url = mediaURL // Initializing `url` with `mediaURL`
        self.title = title
        self.link = link
        self.description = description
        self.attributedDescription = attributedDescription
        self.mediaURL = mediaURL
        self.date = date
        self.author = author
        self.website = website
        self.category = category
        self.rating = rating
        self.size = size
        self.duration = duration
        self.chapterImageUrl = chapterImageUrl
    }

    
    // Hashable and Equatable conformances
    static func == (lhs: Episode, rhs: Episode) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Date {
    func formattedToString(format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format // Allow custom format strings
        return formatter.string(from: self)
    }

    func formattedForDisplay(type: DateFormatType) -> String {
        switch type {
        case .simple:
            return formattedToString(format: "dd/MM/yyyy") // Simple date format
        case .detailed:
            return formattedToString(format: "dd MMMM yyyy") // More detailed with month spelled out
        case .timeIncluded:
            return formattedToString(format: "dd MMMM yyyy, HH:mm") // Date with time
        }
    }
}

enum DateFormatType {
    case simple, detailed, timeIncluded
}

extension Episode {
    // Method to format the stored date string which is in the format "EEE, dd MMM yyyy HH:mm:ss Z"
    var formattedDate: String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        inputFormatter.locale = Locale(identifier: "en_US_POSIX") // Important for parsing English month names and the format correctly

        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "d MMMM yyyy" // Target format "(D)D Month YYYY"
        outputFormatter.locale = Locale(identifier: "en_US") // Ensure month names are in English

        if let date = inputFormatter.date(from: self.date) {
            return outputFormatter.string(from: date)
        } else {
            return "Unknown Date"
        }
    }
}
