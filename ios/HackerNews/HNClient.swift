//
//  HNClient.swift
//  HackerNews
//
//  Thin async wrapper around the Hacker News Firebase API.
//

import Foundation

struct HNClient {
    static let shared = HNClient()

    private let base = URL(string: "https://hacker-news.firebaseio.com/v0")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Ordered list of the current top-story IDs (up to ~500).
    func topStoryIDs() async throws -> [Int] {
        try await get([Int].self, path: "topstories.json")
    }

    /// Fetch a single item by ID.
    func item(_ id: Int) async throws -> HNItem {
        try await get(HNItem.self, path: "item/\(id).json")
    }

    /// Fetch many items concurrently while preserving the input order.
    func items(_ ids: [Int]) async throws -> [HNItem] {
        try await withThrowingTaskGroup(of: (Int, HNItem).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask { (index, try await item(id)) }
            }
            var results = [(Int, HNItem)]()
            for try await pair in group {
                results.append(pair)
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func get<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        let (data, response) = try await session.data(from: base.appending(path: path))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
