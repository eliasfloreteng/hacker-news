//
//  Models.swift
//  HackerNews
//
//  Domain models mapped from the official Hacker News Firebase API.
//  https://github.com/HackerNews/API
//

import Foundation

/// A single Hacker News item. The API uses one shape for stories, comments,
/// jobs, polls, etc.; we only decode the fields the app needs.
struct HNItem: Codable, Identifiable, Hashable {
    let id: Int
    let type: String?
    let by: String?
    let time: Int?
    let text: String?
    let url: String?
    let title: String?
    let score: Int?
    let descendants: Int?
    let kids: [Int]?
    let deleted: Bool?
    let dead: Bool?

    var date: Date? {
        time.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    /// The link a story row should open. Stories without an external URL
    /// (Ask HN / discussions) fall back to their HN item page.
    var destinationURL: URL {
        if let url, let parsed = URL(string: url) {
            return parsed
        }
        return Self.hnItemURL(id)
    }

    /// Host shown next to the title, e.g. "github.com".
    var displayHost: String? {
        guard let url, let host = URL(string: url)?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var isDeadOrDeleted: Bool {
        (deleted ?? false) || (dead ?? false)
    }

    static func hnItemURL(_ id: Int) -> URL {
        URL(string: "https://news.ycombinator.com/item?id=\(id)")!
    }
}
