//
//  HTMLText.swift
//  HackerNews
//
//  HN comment bodies are small HTML fragments (<p>, <i>, <a>, <pre><code>,
//  plus entities). These converters turn them into text suitable for SwiftUI
//  Text, avoiding the heavyweight NSAttributedString HTML importer.
//

import Foundation

enum HTMLText {
    /// Flattens a fragment to plain text, dropping all markup.
    static func plain(from html: String) -> String {
        var s = html

        // Paragraph breaks.
        s = s.replacingOccurrences(of: "<p>", with: "\n\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "</p>", with: "", options: .caseInsensitive)

        // Strip any remaining tags (links, italics, code wrappers, etc.).
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        return decodeEntities(s).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Converts a fragment to an `AttributedString`, keeping `<a>` links
    /// tappable and `<i>`/`<code>` runs styled. Anything else is flattened.
    static func attributed(from html: String) -> AttributedString {
        // Paragraph tags become blank lines; the rest is parsed inline below.
        var s = html.replacingOccurrences(of: "<p>", with: "\n\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "</p>", with: "", options: .caseInsensitive)

        var result = AttributedString()
        var pending = ""
        var presentation: InlinePresentationIntent = []
        var linkURL: URL?

        // Emit the buffered text under the current formatting state.
        func flush() {
            guard !pending.isEmpty else { return }
            var run = AttributedString(decodeEntities(pending))
            if !presentation.isEmpty { run.inlinePresentationIntent = presentation }
            if let linkURL { run.link = linkURL }
            result += run
            pending = ""
        }

        var idx = s.startIndex
        while idx < s.endIndex {
            let ch = s[idx]
            guard ch == "<", let close = s[idx...].firstIndex(of: ">") else {
                pending.append(ch)
                idx = s.index(after: idx)
                continue
            }

            // Text accumulated so far keeps the state in effect before the tag.
            flush()

            let tag = String(s[s.index(after: idx)..<close])
            let lower = tag.lowercased()
            if lower == "i" || lower == "em" {
                presentation.insert(.emphasized)
            } else if lower == "/i" || lower == "/em" {
                presentation.remove(.emphasized)
            } else if lower == "code" || lower == "pre" {
                presentation.insert(.code)
            } else if lower == "/code" || lower == "/pre" {
                presentation.remove(.code)
            } else if lower.hasPrefix("a ") || lower == "a" {
                linkURL = href(in: tag)
            } else if lower == "/a" {
                linkURL = nil
            }

            idx = s.index(after: close)
        }
        flush()

        // Trim leading/trailing whitespace introduced by paragraph breaks.
        while let first = result.characters.first, first.isWhitespace {
            result.removeSubrange(result.startIndex..<result.index(afterCharacter: result.startIndex))
        }
        while let last = result.characters.last, last.isWhitespace {
            result.removeSubrange(result.index(beforeCharacter: result.endIndex)..<result.endIndex)
        }
        return result
    }

    // MARK: - Helpers

    /// Pulls the (entity-decoded) URL out of an anchor tag's `href` attribute.
    private static func href(in tag: String) -> URL? {
        guard let range = tag.range(of: "href", options: .caseInsensitive) else { return nil }
        let after = tag[range.upperBound...]
        // Skip "=" and optional surrounding whitespace, then read the quoted value.
        guard let eq = after.firstIndex(of: "=") else { return nil }
        let rest = after[after.index(after: eq)...].drop { $0 == " " || $0 == "\"" || $0 == "'" }
        let value = rest.prefix { $0 != "\"" && $0 != "'" && $0 != " " && $0 != ">" }
        return URL(string: decodeEntities(String(value)))
    }

    private static func decodeEntities(_ input: String) -> String {
        var s = input
        let entities = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&#x27;": "'", "&#39;": "'", "&#x2F;": "/", "&#47;": "/", "&nbsp;": " ",
        ]
        for (entity, value) in entities {
            s = s.replacingOccurrences(of: entity, with: value)
        }
        return s
    }
}
