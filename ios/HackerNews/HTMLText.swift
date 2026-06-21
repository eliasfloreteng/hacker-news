//
//  HTMLText.swift
//  HackerNews
//
//  HN comment bodies are small HTML fragments (<p>, <i>, <a>, <pre><code>,
//  plus entities). This converts them to plain text suitable for SwiftUI Text,
//  avoiding the heavyweight NSAttributedString HTML importer.
//

import Foundation

enum HTMLText {
    static func plain(from html: String) -> String {
        var s = html

        // Paragraph breaks.
        s = s.replacingOccurrences(of: "<p>", with: "\n\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "</p>", with: "", options: .caseInsensitive)

        // Strip any remaining tags (links, italics, code wrappers, etc.).
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Decode the entities HN actually emits.
        let entities = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&#x27;": "'", "&#39;": "'", "&#x2F;": "/", "&#47;": "/", "&nbsp;": " ",
        ]
        for (entity, value) in entities {
            s = s.replacingOccurrences(of: entity, with: value)
        }

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
