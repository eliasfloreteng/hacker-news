//
//  CommentPageParserTests.swift
//  HackerNewsTests
//
//  The parser reads HTML the site never promised to keep stable, so these pin
//  down the parts of its markup the app relies on. The rows are trimmed copies
//  of real ones.
//

import Foundation
import Testing
@testable import HackerNews

private func row(
    id: Int, indent: Int, by: String? = "pg", title: String = "2026-10-13T21:44:46",
    text: String? = "Hello<p>world", classes: String = ""
) -> String {
    let user = by.map { #"<a href="user?id=\#($0)" class="hnuser">\#($0)</a> "# } ?? ""
    let body = text.map { #"<div class="commtext c00">\#($0)</div><div class="reply"><p>reply</div>"# } ?? ""
    return #"""
    <tr class="athing comtr\#(classes)" id="\#(id)"><td><table border="0"><tr><td class="ind" indent="\#(indent)"><img src="s.gif" height="1" width="0"></td><td class="default"><div style="margin-top:2px; margin-bottom:-10px;"><span class="comhead">\#(user)<span class="age" title="\#(title)"><a href="item?id=\#(id)">9 minutes ago</a></span></span></div><br>
    <div class="comment">\#(body)</div></td></tr></table></td></tr>
    """#
}

private func page(_ rows: String...) -> String {
    #"<html><table><tr class="athing submission" id="1"><td>story</td></tr>\#(rows.joined())</table></html>"#
}

struct CommentPageParserTests {

    @Test func indentationBecomesTheReplyTree() throws {
        let thread = try #require(CommentPageParser.parse(page(
            row(id: 10, indent: 0),
            row(id: 11, indent: 1),
            row(id: 12, indent: 2),
            row(id: 13, indent: 1),
            row(id: 20, indent: 0)
        )))
        #expect(thread.rootIDs == [10, 20])
        #expect(thread.items[10]?.kids == [11, 13])
        #expect(thread.items[11]?.kids == [12])
        #expect(thread.items[13]?.kids == nil)
        #expect(thread.items[20]?.kids == nil)
    }

    @Test func readsAuthorTimeAndText() throws {
        let thread = try #require(CommentPageParser.parse(page(row(id: 10, indent: 0))))
        let item = try #require(thread.items[10])
        #expect(item.by == "pg")
        #expect(item.time == 1_791_927_886)
        #expect(item.text == "Hello<p>world")
        #expect(item.type == "comment")
        #expect(!item.isDeadOrDeleted)
    }

    @Test func prefersAUnixTimestampInTheTitle() throws {
        let thread = try #require(CommentPageParser.parse(page(
            row(id: 10, indent: 0, title: "2026-10-13T21:44:46 1700000000")
        )))
        #expect(thread.items[10]?.time == 1_700_000_000)
    }

    /// The site marks some rows with extra classes; they're still comments.
    @Test func includesRowsWithExtraClasses() throws {
        let thread = try #require(CommentPageParser.parse(page(row(id: 10, indent: 0, classes: " coll"))))
        #expect(thread.rootIDs == [10])
    }

    @Test func aRowWithoutAuthorOrTextIsDeleted() throws {
        let thread = try #require(CommentPageParser.parse(page(
            row(id: 10, indent: 0, by: nil, text: nil),
            row(id: 11, indent: 1)
        )))
        #expect(thread.items[10]?.isDeadOrDeleted == true)
        #expect(thread.items[10]?.kids == [11])
    }

    @Test func dropsARowWithNoParentOnThePage() throws {
        let thread = try #require(CommentPageParser.parse(page(
            row(id: 10, indent: 0),
            row(id: 11, indent: 2)
        )))
        #expect(thread.items[11] == nil)
        #expect(thread.items[10]?.kids == nil)
    }

    @Test func aPageWithoutCommentsIsNotAThread() {
        #expect(CommentPageParser.parse(page()) == nil)
        #expect(CommentPageParser.parse("Sorry, we're not able to serve your requests this quickly.") == nil)
    }
}
