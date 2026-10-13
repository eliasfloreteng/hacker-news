//
//  CommentPageParser.swift
//  HackerNews
//
//  Reads a comment thread out of the HN site's own discussion page. The page
//  carries the whole thread in one response, already ranked the way the site
//  ranks it at every level — where the Firebase API needs a request per
//  comment, one depth level at a time.
//
//  Each comment is a `<tr class="athing comtr" id="…">` row whose `indent`
//  attribute is its depth; replies follow their parent directly, so the tree
//  falls out of the row order.
//

import Foundation

/// A story's comments, as the HN page presents them.
struct CommentThread: Codable, Equatable {
    /// Top-level comment IDs, in the page's order.
    let rootIDs: [Int]
    /// Every comment on the page. Each item's `kids` lists only the replies
    /// the page shows, in the page's order.
    let items: [Int: HNItem]
}

enum CommentPageParser {
    /// Parse a discussion page. Returns nil when the page has no comment rows
    /// at all — callers can't tell an empty thread from a page that isn't a
    /// thread (an error page, a changed layout), so that call is theirs.
    static func parse(_ html: String) -> CommentThread? {
        var rootIDs: [Int] = []
        var order: [Int] = []
        var rows: [Int: Row] = [:]
        var kids: [Int: [Int]] = [:]
        /// The most recent comment at each depth: a row's parent is the last
        /// one seen one level up.
        var lastAtDepth: [Int] = []

        for chunk in html.split(separator: rowStart).dropFirst() {
            guard let row = Row(chunk), rows[row.id] == nil else { continue }

            // A row deeper than anything open has no parent on the page; drop
            // it rather than guess which comment it hangs off.
            guard row.depth <= lastAtDepth.count else { continue }
            lastAtDepth.removeSubrange(row.depth...)
            if let parent = lastAtDepth.last {
                kids[parent, default: []].append(row.id)
            } else {
                rootIDs.append(row.id)
            }
            lastAtDepth.append(row.id)
            rows[row.id] = row
            order.append(row.id)
        }

        guard !order.isEmpty else { return nil }
        let items = Dictionary(uniqueKeysWithValues: order.compactMap { id in
            rows[id].map { (id, $0.item(kids: kids[id])) }
        })
        return CommentThread(rootIDs: rootIDs, items: items)
    }

    /// Every comment row opens with this. Matching on the prefix also takes in
    /// rows with extra classes, like the `coll` the site adds to some.
    private static let rowStart = #"<tr class="athing comtr"#

    private struct Row {
        let id: Int
        let depth: Int
        let by: String?
        let time: Int?
        let text: String?

        init?(_ chunk: Substring) {
            // Plain substring searches rather than `Regex`: a busy thread is
            // thousands of rows, and this is several times faster on them.
            guard let id = chunk.value(between: #"id=""#, and: #"""#).flatMap({ Int($0) }),
                  let depth = chunk.value(between: #"indent=""#, and: #"""#).flatMap({ Int($0) })
            else { return nil }
            self.id = id
            self.depth = depth
            by = chunk.value(between: #"class="hnuser">"#, and: "<").map(String.init)
            time = chunk.value(between: #"<span class="age" title=""#, and: #"""#).flatMap { Self.timestamp(String($0)) }
            // Comment HTML holds paragraphs, links, code and italics but never
            // a div, so the first closing div ends it. A row without one is a
            // deleted comment kept for the sake of its replies.
            text = chunk.value(between: #"<div class="commtext"#, and: "</div>")
                .flatMap { $0.value(between: ">", and: nil) }
                .map(String.init)
        }

        func item(kids: [Int]?) -> HNItem {
            HNItem(
                id: id, type: "comment", by: by, time: time, text: text,
                url: nil, title: nil, score: nil, descendants: nil, kids: kids,
                deleted: text == nil && by == nil ? true : nil, dead: nil
            )
        }

        /// The age span's title is the post time in UTC, sometimes followed by
        /// the Unix timestamp itself; the timestamp wins when it's there.
        private static func timestamp(_ title: String) -> Int? {
            let parts = title.split(separator: " ")
            if parts.count > 1, let unix = Int(parts[1]) { return unix }
            guard let first = parts.first,
                  let date = try? Date(String(first) + "Z", strategy: .iso8601) else { return nil }
            return Int(date.timeIntervalSince1970)
        }
    }
}

private extension Substring {
    /// The text after the first `start`, up to the next `end` (or to the end
    /// when `end` is nil). Nil if either marker is missing.
    func value(between start: String, and end: String?) -> Substring? {
        guard let open = range(of: start) else { return nil }
        let rest = self[open.upperBound...]
        guard let end else { return rest }
        guard let close = rest.range(of: end) else { return nil }
        return rest[..<close.lowerBound]
    }
}
