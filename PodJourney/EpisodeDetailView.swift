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
    var mediaURL: URL
    var date: String
    var author: String?
    var website: URL?
    var category: String?
    var rating: String?
    var size: Int64?
    var duration: String
    
    init(id: UUID = UUID(), title: String, link: String, description: String, attributedDescription: AttributedString? = nil, mediaURL: URL, date: String, author: String? = nil, website: URL? = nil, category: String? = nil, rating: String? = nil, size: Int64? = nil, duration: String) {
        self.id = id
        self.url = mediaURL // Assuming you want to initialize `url` with `mediaURL`
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
    func formattedToString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy" // Adjust this format as needed.
        return formatter.string(from: self)
    }
}

extension Date {
    func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy" // Use the format "20/03/2024" as per your requirement.
        return formatter.string(from: self)
    }
}

extension Date {
    func formattedDateAndTime() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
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
